defmodule AlchemIiif.Ingestion do
  @moduledoc """
  取り込みパイプラインのコンテキストモジュール。
  PDFアップロード、ページ画像変換、クロップ、PTIF生成を管理します。

  ## なぜこの設計か

  - **Phoenix Contexts パターン**: LiveView やコントローラーから直接 `Repo` を
    呼ばず、このコンテキストを経由することで、ビジネスロジックを一箇所に集約します。
    将来的に内部実装が変わっても、公開 API を維持すれば呼び出し側に影響しません。
  - **Stage-Gate ステータス遷移**: `draft → pending_review → published` の
    3段階ステータスは、内部ワークスペース（Lab）と公開ギャラリー（Museum）を
    分離するための設計です。明示的なステータス遷移関数により、不正な遷移を
    コンパイル時ではなく実行時にパターンマッチで防ぎます。
  """
  import Ecto.Query
  alias AlchemIiif.Ingestion.{ExtractedImage, PdfSource}
  alias AlchemIiif.Repo

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

  @doc "IDで抽出画像を取得（iiif_manifest プリロード付き、nil 安全）"
  def get_extracted_image_with_manifest(id) do
    case Repo.get(ExtractedImage, id) do
      nil -> nil
      image -> Repo.preload(image, :iiif_manifest)
    end
  end

  @doc "pdf_source_id と page_number で既存の抽出画像を検索（Write-on-Action 用）"
  def find_extracted_image_by_page(pdf_source_id, page_number) do
    from(e in ExtractedImage,
      where: e.pdf_source_id == ^pdf_source_id,
      where: e.page_number == ^page_number,
      where: e.status != "deleted",
      order_by: [desc: e.updated_at],
      limit: 1
    )
    |> Repo.one()
  end

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

  @doc "同一 PDF 内で同じラベルを持つレコードを検索（自分自身を除く）"
  def find_duplicate_label(pdf_source_id, label, exclude_id \\ nil)

  def find_duplicate_label(_pdf_source_id, label, _exclude_id)
      when is_nil(label) or label == "",
      do: nil

  def find_duplicate_label(pdf_source_id, label, exclude_id) do
    query =
      from(e in ExtractedImage,
        where: e.pdf_source_id == ^pdf_source_id,
        where: e.label == ^label,
        where: e.status != "deleted",
        limit: 1
      )

    query =
      if exclude_id,
        do: from(e in query, where: e.id != ^exclude_id),
        else: query

    Repo.one(query)
  end

  # === ステータス遷移 ===

  @doc "レビュー提出 (draft → pending_review)"
  def submit_for_review(%ExtractedImage{status: "draft"} = image) do
    update_extracted_image(image, %{status: "pending_review"})
  end

  def submit_for_review(_image), do: {:error, :invalid_status_transition}

  @doc "承認して公開 (pending_review → published)。PubSub で IIIF コレクション更新を通知。"
  def approve_and_publish(%ExtractedImage{status: "pending_review"} = image) do
    case update_extracted_image(image, %{status: "published"}) do
      {:ok, updated} ->
        # IIIF コレクション更新をバックグラウンドワーカーに通知
        Phoenix.PubSub.broadcast(
          AlchemIiif.PubSub,
          "iiif:collection",
          {:image_published, updated.id}
        )

        {:ok, updated}

      error ->
        error
    end
  end

  def approve_and_publish(_image), do: {:error, :invalid_status_transition}

  @doc "差し戻し (pending_review → draft)"
  def reject_to_draft(%ExtractedImage{status: "pending_review"} = image) do
    update_extracted_image(image, %{status: "draft"})
  end

  def reject_to_draft(_image), do: {:error, :invalid_status_transition}

  @doc "差し戻し（理由メモ付き） (pending_review → draft)"
  def reject_to_draft_with_note(%ExtractedImage{status: "pending_review"} = image, note) do
    # Note はキャプションに追記（将来的に専用カラムへ移行可能）
    caption_with_note =
      case image.caption do
        nil -> "[差し戻し] #{note}"
        existing -> "#{existing}\n[差し戻し] #{note}"
      end

    update_extracted_image(image, %{status: "draft", caption: caption_with_note})
  end

  def reject_to_draft_with_note(_image, _note), do: {:error, :invalid_status_transition}

  @doc "ソフトデリート (pending_review → deleted)。誤登録エントリの論理削除。"
  def soft_delete_image(%ExtractedImage{status: "pending_review"} = image) do
    update_extracted_image(image, %{status: "deleted"})
  end

  def soft_delete_image(_image), do: {:error, :invalid_status_transition}

  @doc "レビュー待ちの画像一覧（Admin Review Dashboard 用）"
  def list_pending_review_images do
    from(e in ExtractedImage,
      where: e.status == "pending_review",
      where: not is_nil(e.image_path),
      where: not is_nil(e.geometry),
      order_by: [desc: e.inserted_at],
      preload: [:iiif_manifest, :pdf_source]
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

  # === バリデーション（Admin Review Dashboard 用） ===

  @doc "画像データの技術的妥当性を検証（Validation Badge 用）"
  def validate_image_data(%ExtractedImage{} = image) do
    checks = [
      {:image_file, not is_nil(image.image_path) and image.image_path != ""},
      {:ptif_file, not is_nil(image.ptif_path) and image.ptif_path != ""},
      {:geometry, is_map(image.geometry) and map_size(image.geometry) > 0},
      {:metadata, not is_nil(image.label) and image.label != ""}
    ]

    failed = Enum.filter(checks, fn {_name, result} -> not result end)

    case failed do
      [] -> {:ok, :valid}
      _ -> {:error, Enum.map(failed, fn {name, _} -> name end)}
    end
  end
end
