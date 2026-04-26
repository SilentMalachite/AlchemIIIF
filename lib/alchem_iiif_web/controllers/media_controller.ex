defmodule AlchemIiifWeb.MediaController do
  @moduledoc """
  アップロード済み画像を認可チェック後に配信するコントローラー。
  """
  use AlchemIiifWeb, :controller

  alias AlchemIiif.Ingestion
  alias AlchemIiif.Ingestion.ExtractedImage
  alias AlchemIiif.Repo
  alias AlchemIiif.UploadStore

  def published_image(conn, %{"id" => id}) do
    case Repo.get(ExtractedImage, id) do
      %ExtractedImage{status: "published"} = image ->
        serve_upload(conn, image.image_path)

      _ ->
        not_found(conn)
    end
  end

  def lab_image(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    try do
      image = Ingestion.get_extracted_image!(id, user)
      serve_upload(conn, image.image_path)
    rescue
      Ecto.NoResultsError -> not_found(conn)
    end
  end

  def lab_page(conn, %{"pdf_source_id" => pdf_source_id, "filename" => filename}) do
    user = conn.assigns.current_scope.user

    with true <- UploadStore.safe_filename?(filename),
         _source <- Ingestion.get_pdf_source!(pdf_source_id, user),
         {:ok, path} <- UploadStore.existing_page_path(pdf_source_id, filename) do
      serve_upload(conn, path)
    else
      _ -> not_found(conn)
    end
  rescue
    Ecto.NoResultsError -> not_found(conn)
  end

  defp serve_upload(conn, path) do
    with {:ok, full_path} <- UploadStore.resolve_path(path),
         {:ok, content_type} <- content_type(full_path) do
      conn
      |> put_resp_header("content-type", content_type)
      |> send_file(200, full_path)
    else
      _ -> not_found(conn)
    end
  end

  defp content_type(path) do
    case Path.extname(path) |> String.downcase() do
      ".png" -> {:ok, "image/png"}
      ".jpg" -> {:ok, "image/jpeg"}
      ".jpeg" -> {:ok, "image/jpeg"}
      ".webp" -> {:ok, "image/webp"}
      ".gif" -> {:ok, "image/gif"}
      ".tif" -> {:ok, "image/tiff"}
      ".tiff" -> {:ok, "image/tiff"}
      _ -> {:error, :unsupported_media_type}
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> text("Not Found")
  end
end
