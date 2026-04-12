defmodule AlchemIiifWeb.IIIF.ManifestController do
  @moduledoc """
  IIIF Presentation API v3.0 コントローラー。
  エンドポイント: /iiif/manifest/:identifier

  JSON-LD 形式で IIIF 3.0 準拠の Manifest を返します。
  多言語ラベル (英語/日本語) 対応。
  """
  use AlchemIiifWeb, :controller

  require Logger

  alias AlchemIiif.Iiif.Manifest
  alias AlchemIiif.Ingestion.{ExtractedImage, ImageProcessor}
  alias AlchemIiif.Ingestion.PdfSource
  alias AlchemIiif.Repo
  alias AlchemIiifWeb.IIIF.MetadataHelper

  import Ecto.Query

  @default_dimensions %{width: 1000, height: 1000}

  @doc """
  IIIF Presentation API v3.0 Manifest を JSON-LD で返します。
  """
  def show(conn, %{"identifier" => identifier}) do
    case Repo.one(from m in Manifest, where: m.identifier == ^identifier) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Manifest が見つかりません"})

      manifest ->
        image = Repo.get!(ExtractedImage, manifest.extracted_image_id)

        if image.status != "published" do
          conn
          |> put_status(:forbidden)
          |> json(%{error: "この画像はまだ公開されていません"})
        else
          source = Repo.get(PdfSource, image.pdf_source_id)
          manifest_json = build_manifest_json(manifest, image, identifier, source)

          conn
          |> put_resp_content_type("application/ld+json")
          |> put_resp_header("access-control-allow-origin", "*")
          |> json(manifest_json)
        end
    end
  end

  # --- プライベート関数 ---

  defp build_manifest_json(manifest, image, identifier, source) do
    dimensions = get_dimensions(image)
    base_url = AlchemIiifWeb.Endpoint.url()

    manifest_json = %{
      "@context" => "http://iiif.io/api/presentation/3/context.json",
      "id" => "#{base_url}/iiif/manifest/#{identifier}",
      "type" => "Manifest",
      "label" => build_top_label(manifest, source, identifier),
      "metadata" => build_metadata(manifest.metadata),
      "items" => [build_canvas(manifest, identifier, dimensions, base_url, image)]
    }

    merge_bibliographic(manifest_json, source)
  end

  defp get_dimensions(image) do
    with path when is_binary(path) <- image.ptif_path,
         true <- File.exists?(path),
         {:ok, dims} <- ImageProcessor.get_image_dimensions(path) do
      dims
    else
      _ -> get_dimensions_from_source_image(image)
    end
  end

  defp get_dimensions_from_source_image(%{image_path: path}) when is_binary(path) do
    case resolve_image_path(path) do
      {:ok, full_path} ->
        case ImageProcessor.get_image_dimensions(full_path) do
          {:ok, dims} ->
            dims

          error ->
            Logger.warning("Canvas 寸法の取得に失敗: path=#{full_path} error=#{inspect(error)}")
            @default_dimensions
        end

      {:error, reason} ->
        Logger.warning("Canvas 寸法の解決に失敗: path=#{path} reason=#{reason}")
        @default_dimensions
    end
  end

  defp get_dimensions_from_source_image(_), do: @default_dimensions

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

  defp build_canvas(_manifest, identifier, dimensions, base_url, image) do
    canvas = %{
      "id" => "#{base_url}/iiif/manifest/#{identifier}/canvas/1",
      "type" => "Canvas",
      "width" => dimensions.width,
      "height" => dimensions.height,
      "label" => MetadataHelper.build_canvas_label(image),
      "items" => [
        %{
          "id" => "#{base_url}/iiif/manifest/#{identifier}/canvas/1/page/1",
          "type" => "AnnotationPage",
          "items" => [
            %{
              "id" => "#{base_url}/iiif/manifest/#{identifier}/canvas/1/page/1/annotation/1",
              "type" => "Annotation",
              "motivation" => "painting",
              "body" => %{
                "id" => "#{base_url}/iiif/image/#{identifier}/full/max/0/default.jpg",
                "type" => "Image",
                "format" => "image/jpeg",
                "width" => dimensions.width,
                "height" => dimensions.height,
                "service" => [
                  %{
                    "id" => "#{base_url}/iiif/image/#{identifier}",
                    "type" => "ImageService3",
                    "profile" => "level1"
                  }
                ]
              },
              "target" => "#{base_url}/iiif/manifest/#{identifier}/canvas/1"
            }
          ]
        }
      ]
    }

    canvas_metadata = build_canvas_metadata(image)

    if canvas_metadata == [] do
      canvas
    else
      Map.put(canvas, "metadata", canvas_metadata)
    end
  end

  defp build_canvas_metadata(image) do
    [
      MetadataHelper.label_value("素材", "Material", image.material)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp merge_bibliographic(manifest_json, nil), do: manifest_json

  defp merge_bibliographic(manifest_json, source) do
    recommended = MetadataHelper.build_recommended_properties(source)
    bibliographic = MetadataHelper.build_bibliographic_metadata(source)
    existing_metadata = manifest_json["metadata"] || []

    manifest_json
    |> Map.merge(recommended)
    |> Map.put("metadata", existing_metadata ++ bibliographic)
  end

  # メタデータを IIIF 3.0 形式に変換
  defp build_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.drop(["label", "summary"])
    |> Enum.map(fn {key, value} ->
      %{
        "label" => %{"en" => [key]},
        "value" => format_metadata_value(value)
      }
    end)
  end

  defp build_metadata(_), do: []

  # トップ label を生成する。source があればそれを優先し、なければ
  # manifest.metadata["label"] → identifier フォールバック の順で使う。
  defp build_top_label(_manifest, source, _identifier) when not is_nil(source) do
    MetadataHelper.build_manifest_label(source)
  end

  defp build_top_label(manifest, nil, identifier) do
    case manifest.metadata && manifest.metadata["label"] do
      %{} = label when map_size(label) > 0 -> label
      _ -> %{"ja" => [identifier], "en" => [identifier]}
    end
  end

  defp format_metadata_value(value) when is_map(value), do: value
  defp format_metadata_value(value) when is_list(value), do: %{"none" => value}
  defp format_metadata_value(value), do: %{"none" => [to_string(value)]}
end
