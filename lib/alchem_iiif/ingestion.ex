defmodule AlchemIiif.Ingestion do
  @moduledoc """
  取り込みパイプラインのコンテキストモジュール。
  PDFアップロード、ページ画像変換、クロップ、PTIF生成を管理します。
  """
  import Ecto.Query
  alias AlchemIiif.Repo
  alias AlchemIiif.Ingestion.{PdfSource, ExtractedImage}

  # === PdfSource ===

  @doc "全てのPDFソースを取得"
  def list_pdf_sources do
    Repo.all(PdfSource)
  end

  @doc "IDでPDFソースを取得"
  def get_pdf_source!(id), do: Repo.get!(PdfSource, id)

  @doc "PDFソースを作成"
  def create_pdf_source(attrs \\ %{}) do
    %PdfSource{}
    |> PdfSource.changeset(attrs)
    |> Repo.insert()
  end

  @doc "PDFソースを更新"
  def update_pdf_source(%PdfSource{} = pdf_source, attrs) do
    pdf_source
    |> PdfSource.changeset(attrs)
    |> Repo.update()
  end

  # === ExtractedImage ===

  @doc "PDFソースに紐づく抽出画像一覧を取得"
  def list_extracted_images(pdf_source_id) do
    from(e in ExtractedImage, where: e.pdf_source_id == ^pdf_source_id)
    |> Repo.all()
  end

  @doc "IDで抽出画像を取得"
  def get_extracted_image!(id), do: Repo.get!(ExtractedImage, id)

  @doc "抽出画像を作成"
  def create_extracted_image(attrs \\ %{}) do
    %ExtractedImage{}
    |> ExtractedImage.changeset(attrs)
    |> Repo.insert()
  end

  @doc "抽出画像を更新（クロップデータ等）"
  def update_extracted_image(%ExtractedImage{} = image, attrs) do
    image
    |> ExtractedImage.changeset(attrs)
    |> Repo.update()
  end
end
