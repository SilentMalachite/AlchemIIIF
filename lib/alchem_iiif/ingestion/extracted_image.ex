defmodule AlchemIiif.Ingestion.ExtractedImage do
  @moduledoc """
  抽出画像を管理する Ecto スキーマ。
  クロップデータ(JSONB)、キャプション、ラベル、PTIFパスを保持します。

  ## なぜこの設計か

  - **geometry を JSONB で保持**: クロップ領域 `{x, y, width, height}` を
    マップとして保存することで、将来的に矩形以外のクロップ形状（多角形や
    円形）にも拡張可能です。専用カラムに分離するよりスキーマ変更が不要です。
  - **status フィールド**: Stage-Gate ワークフローに対応し、
    `draft / pending_review / published` の3状態を文字列で管理します。
    Enum 型ではなく文字列を使うことで、マイグレーションなしに新しい
    ステータスを追加できる柔軟性を確保しています。
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "extracted_images" do
    # 抽出元のページ番号
    field :page_number, :integer
    # 抽出画像のファイルパス
    field :image_path, :string
    # クロップデータ (x, y, width, height) — JSONB
    field :geometry, :map
    # キャプション (手動入力)
    field :caption, :string
    # ラベル (手動入力)
    field :label, :string
    # 生成された PTIF のパス
    field :ptif_path, :string
    # 検索用メタデータ（遺跡名、時代、遺物種別）
    field :site, :string
    field :period, :string
    field :artifact_type, :string
    # ステータス (draft / pending_review / published)
    field :status, :string, default: "draft"

    belongs_to :pdf_source, AlchemIiif.Ingestion.PdfSource
    has_one :iiif_manifest, AlchemIiif.IIIF.Manifest

    timestamps(type: :utc_datetime)
  end

  @doc "バリデーション用 changeset"
  def changeset(extracted_image, attrs) do
    extracted_image
    |> cast(attrs, [
      :pdf_source_id,
      :page_number,
      :image_path,
      :geometry,
      :caption,
      :label,
      :ptif_path,
      :site,
      :period,
      :artifact_type,
      :status
    ])
    |> validate_required([:pdf_source_id, :page_number])
    |> validate_inclusion(:status, ~w(draft pending_review published deleted))
    |> foreign_key_constraint(:pdf_source_id)
    |> unique_constraint([:pdf_source_id, :label],
      name: :extracted_images_pdf_source_id_label_unique,
      message: "このラベルは既にこの PDF 内で使用されています"
    )
  end
end
