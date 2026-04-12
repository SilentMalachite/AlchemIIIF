defmodule AlchemIiifWeb.IIIF.PresentationController do
  @moduledoc """
  IIIF Presentation API v3.0 — PdfSource 単位の Manifest コントローラー。
  エンドポイント: GET /iiif/presentation/:source_id/manifest

  PdfSource に紐づく公開済み画像を Canvas として集約した
  JSON-LD Manifest を返します。Mirador 等の IIIF ビューアで閲覧可能です。
  """
  use AlchemIiifWeb, :controller

  require Logger

  alias AlchemIiif.Ingestion
  alias AlchemIiif.Repo
  alias AlchemIiifWeb.IIIF.MetadataHelper

  @default_canvas_dimensions {1000, 1000}

  @doc """
  PdfSource 単位の IIIF 3.0 Manifest を JSON-LD で返します。

  - published ステータスの画像のみ含む
  - page_number 昇順で Canvas を生成
  """
  def manifest(conn, %{"source_id" => source_id}) do
    case Repo.get(AlchemIiif.Ingestion.PdfSource, source_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "指定された Source が見つかりません"})

      source ->
        images = Ingestion.list_published_images_by_source(source.id)
        base_url = AlchemIiifWeb.Endpoint.url()

        manifest_json = build_manifest(source, images, base_url)

        conn
        |> put_resp_content_type("application/ld+json")
        |> put_resp_header("access-control-allow-origin", "*")
        |> json(manifest_json)
    end
  end

  # --- プライベート関数 ---

  # Manifest 全体を組み立てる
  defp build_manifest(source, images, base_url) do
    manifest_id = "#{base_url}/iiif/presentation/#{source.id}/manifest"

    base = %{
      "@context" => "http://iiif.io/api/presentation/3/context.json",
      "id" => manifest_id,
      "type" => "Manifest",
      "label" => MetadataHelper.build_manifest_label(source),
      "items" => Enum.map(images, &build_canvas(&1, base_url))
    }

    recommended = MetadataHelper.build_recommended_properties(source)
    bibliographic = MetadataHelper.build_bibliographic_metadata(source)

    base
    |> Map.merge(recommended)
    |> maybe_put_metadata(bibliographic)
  end

  defp maybe_put_metadata(manifest, []), do: manifest
  defp maybe_put_metadata(manifest, metadata), do: Map.put(manifest, "metadata", metadata)

  # ExtractedImage → IIIF Canvas
  defp build_canvas(image, base_url) do
    {width, height} = extract_dimensions(image)
    canvas_id = "#{base_url}/iiif/presentation/#{image.pdf_source_id}/canvas/#{image.page_number}"

    canvas = %{
      "id" => canvas_id,
      "type" => "Canvas",
      "width" => width,
      "height" => height,
      "label" => MetadataHelper.build_canvas_label(image),
      "items" => [
        %{
          "id" => "#{canvas_id}/page",
          "type" => "AnnotationPage",
          "items" => [
            %{
              "id" => "#{canvas_id}/page/annotation",
              "type" => "Annotation",
              "motivation" => "painting",
              "body" => build_image_body(image, base_url, width, height),
              "target" => canvas_id
            }
          ]
        }
      ]
    }

    canvas_metadata =
      [
        MetadataHelper.label_value("素材", "Material", image.material)
      ]
      |> Enum.reject(&is_nil/1)

    if canvas_metadata == [] do
      canvas
    else
      Map.put(canvas, "metadata", canvas_metadata)
    end
  end

  # 画像リソースの body を構築
  defp build_image_body(image, base_url, width, height) do
    # image_path は "priv/static/uploads/..." 形式
    # 静的ファイルとしての URL は "/uploads/..." 部分
    image_url = build_image_url(image.image_path, base_url)
    format = detect_format(image.image_path)

    %{
      "id" => image_url,
      "type" => "Image",
      "format" => format,
      "width" => width,
      "height" => height
    }
  end

  # geometry から幅・高さを抽出。geometry がない場合は Vix で実ファイルを読む（最終フォールバック: @default_canvas_dimensions）
  defp extract_dimensions(%{geometry: %{"width" => w, "height" => h}})
       when is_number(w) and is_number(h) and w > 0 and h > 0 do
    {trunc(w), trunc(h)}
  end

  defp extract_dimensions(%{image_path: path}) when is_binary(path) do
    case resolve_image_path(path) do
      {:ok, full_path} ->
        case AlchemIiif.Ingestion.ImageProcessor.get_image_dimensions(full_path) do
          {:ok, %{width: w, height: h}} ->
            {w, h}

          err ->
            Logger.warning("Canvas 寸法の取得に失敗: path=#{full_path} error=#{inspect(err)}")

            @default_canvas_dimensions
        end

      {:error, reason} ->
        Logger.warning("Canvas 寸法の解決に失敗: path=#{path} reason=#{reason}")
        @default_canvas_dimensions
    end
  end

  defp extract_dimensions(_), do: @default_canvas_dimensions

  # image_path（DB に保存された相対 or 絶対パス）を、リリース環境でも安全な
  # 絶対パスに解決する。priv/static/uploads 配下に閉じ込めて Path Traversal を防ぐ。
  defp resolve_image_path(path) do
    upload_root = Path.expand(Application.app_dir(:alchem_iiif, "priv/static/uploads"))

    full_path =
      cond do
        Path.type(path) == :absolute ->
          Path.expand(path)

        String.starts_with?(path, "priv/static/") ->
          rel = String.replace_prefix(path, "priv/static/", "")
          Path.expand(Path.join(Application.app_dir(:alchem_iiif, "priv/static"), rel))

        true ->
          Path.expand(Path.join(Application.app_dir(:alchem_iiif, "."), path))
      end

    cond do
      not String.starts_with?(full_path, upload_root) ->
        {:error, "upload ディレクトリ外"}

      not File.exists?(full_path) ->
        {:error, "ファイルが存在しません"}

      true ->
        {:ok, full_path}
    end
  end

  # priv/static/uploads/... → 絶対 URL に変換
  defp build_image_url(image_path, base_url) when is_binary(image_path) do
    # "priv/static/uploads/pages/..." → "/uploads/pages/..."
    relative =
      image_path
      |> String.replace_prefix("priv/static", "")

    base_url <> relative
  end

  defp build_image_url(_, base_url), do: base_url <> "/placeholder.png"

  # ファイル拡張子から MIME タイプを推定
  defp detect_format(path) when is_binary(path) do
    case Path.extname(path) |> String.downcase() do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".webp" -> "image/webp"
      ".tif" -> "image/tiff"
      ".tiff" -> "image/tiff"
      _ -> "image/png"
    end
  end

  defp detect_format(_), do: "image/png"
end
