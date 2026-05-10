defmodule AlchemIiifWeb.DownloadController do
  @moduledoc """
  高解像度クロップ画像のダウンロードを提供するコントローラー。
  公開済み (published) の ExtractedImage に対して、サーバーサイドで
  Vix を使ってクロップし、日本語セマンティックファイル名で配信します。
  """
  use AlchemIiifWeb, :controller

  alias AlchemIiif.Ingestion
  alias AlchemIiif.Ingestion.{ExtractedImage, PdfSource}
  alias AlchemIiif.Ingestion.ImageProcessor
  alias AlchemIiif.Repo
  alias AlchemIiif.UploadStore

  @doc """
  GET /download/:id — クロップ済み画像をダウンロードとして送信します。
  """
  def show(conn, %{"id" => id}) do
    case Repo.get(ExtractedImage, id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> text("画像が見つかりません")

      %ExtractedImage{status: status} when status != "published" ->
        conn
        |> put_status(:forbidden)
        |> text("この画像はダウンロードできません")

      image ->
        serve_cropped_image(conn, image)
    end
  end

  @doc """
  GET /download/pdf/:id — 公開済み画像を含む PdfSource の元 PDF を配信します。
  """
  def pdf(conn, %{"id" => id}) do
    case Repo.get(PdfSource, id) do
      %PdfSource{} = source ->
        serve_pdf(conn, source)

      nil ->
        not_found(conn)
    end
  end

  # --- プライベート関数 ---

  defp serve_pdf(conn, source) do
    with true <- PdfSource.pdf?(source),
         true <- Ingestion.published?(source),
         true <- UploadStore.safe_filename?(source.filename),
         {:ok, path} <- UploadStore.existing_pdf_path(source.filename),
         {:ok, full_path} <- UploadStore.resolve_path(path) do
      conn
      |> put_resp_header("content-type", "application/pdf")
      |> put_resp_header("content-disposition", pdf_content_disposition(source.filename))
      |> send_file(200, full_path)
    else
      _ -> not_found(conn)
    end
  end

  # クロップ済み画像をバイナリとして生成し、ダウンロードとして送信
  defp serve_cropped_image(conn, image) do
    case crop_image_to_binary(image) do
      {:ok, binary} ->
        filename = build_filename(image)

        send_download(conn, {:binary, binary},
          filename: filename,
          content_type: "image/jpeg"
        )

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> text("画像の処理に失敗しました: #{inspect(reason)}")
    end
  end

  # 画像をクロップしてバイナリに変換
  defp crop_image_to_binary(%ExtractedImage{image_path: image_path, geometry: geometry})
       when is_map(geometry) do
    with {:ok, full_path} <- UploadStore.resolve_path(image_path) do
      ImageProcessor.crop_to_binary(full_path, geometry)
    end
  end

  # geometry がない場合は元画像をそのまま JPEG バッファとして返す
  defp crop_image_to_binary(%ExtractedImage{image_path: image_path}) do
    with {:ok, full_path} <- UploadStore.resolve_path(image_path),
         {:ok, image} <- Vix.Vips.Image.new_from_file(full_path) do
      Vix.Vips.Image.write_to_buffer(image, ".jpg")
    end
  end

  # セマンティックファイル名の生成
  # パターン: {遺跡名}_{ラベル}_{遺物種別}.jpg
  defp build_filename(image) do
    [image.site, image.label, image.artifact_type]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(&sanitize_segment/1)
    |> case do
      [] -> "download.jpg"
      parts -> Enum.join(parts, "_") <> ".jpg"
    end
  end

  # 日本語対応のファイル名サニタイズ
  # - 漢字・ひらがな・カタカナは保持
  # - 半角/全角スペースを _ に置換
  # - 危険なファイルシステム文字を除去
  defp sanitize_segment(str) do
    str
    |> String.replace(~r/[\s　]+/u, "_")
    |> String.replace(~r/[\/\\:*?"<>|]/, "")
    |> String.trim("_")
  end

  defp pdf_content_disposition(filename) do
    fallback =
      filename
      |> String.replace(~r/[^\x20-\x7E]/u, "_")
      |> String.replace(~r/["\\\r\n]/, "_")

    encoded = URI.encode(filename, &URI.char_unreserved?/1)

    ~s(attachment; filename="#{fallback}"; filename*=UTF-8''#{encoded})
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> text("Not Found")
  end
end
