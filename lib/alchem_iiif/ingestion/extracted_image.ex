defmodule AlchemIiif.Ingestion.ExtractedImage do
  @moduledoc """
  抽出画像を管理する Ecto スキーマ。
  クロップデータ(JSONB)、キャプション、ラベル、PTIFパスを保持します。
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
      :ptif_path
    ])
    |> validate_required([:pdf_source_id, :page_number])
    |> foreign_key_constraint(:pdf_source_id)
  end
end
