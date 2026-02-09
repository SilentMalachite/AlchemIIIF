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

  # === ステータス遷移 ===

  @doc "レビュー提出 (draft → pending_review)"
  def submit_for_review(%ExtractedImage{status: "draft"} = image) do
    update_extracted_image(image, %{status: "pending_review"})
  end

  def submit_for_review(_image), do: {:error, :invalid_status_transition}

  @doc "承認して公開 (pending_review → published)"
  def approve_and_publish(%ExtractedImage{status: "pending_review"} = image) do
    update_extracted_image(image, %{status: "published"})
  end

  def approve_and_publish(_image), do: {:error, :invalid_status_transition}

  @doc "差し戻し (pending_review → draft)"
  def reject_to_draft(%ExtractedImage{status: "pending_review"} = image) do
    update_extracted_image(image, %{status: "draft"})
  end

  def reject_to_draft(_image), do: {:error, :invalid_status_transition}

  @doc "レビュー待ちの画像一覧"
  def list_pending_review_images do
    from(e in ExtractedImage,
      where: e.status == "pending_review",
      where: not is_nil(e.ptif_path),
      order_by: [desc: e.inserted_at],
      preload: [:iiif_manifest]
    )
    |> Repo.all()
  end

  @doc "Lab用: 全ステータスの画像一覧（PTIFあり）"
  def list_all_images_for_lab do
    from(e in ExtractedImage,
      where: not is_nil(e.ptif_path),
      order_by: [desc: e.inserted_at],
      preload: [:iiif_manifest]
    )
    |> Repo.all()
  end
end
