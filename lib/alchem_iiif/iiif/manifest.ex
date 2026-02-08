defmodule AlchemIiif.IIIF.Manifest do
  @moduledoc """
  IIIF Manifest を管理する Ecto スキーマ。
  メタデータ(多言語ラベル等)をJSONBで保持します。
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "iiif_manifests" do
    # IIIF 識別子
    field :identifier, :string
    # IIIF メタデータ (多言語ラベル等) — JSONB
    field :metadata, :map, default: %{}

    belongs_to :extracted_image, AlchemIiif.Ingestion.ExtractedImage

    timestamps(type: :utc_datetime)
  end

  @doc "バリデーション用 changeset"
  def changeset(manifest, attrs) do
    manifest
    |> cast(attrs, [:extracted_image_id, :identifier, :metadata])
    |> validate_required([:extracted_image_id, :identifier])
    |> unique_constraint(:identifier)
    |> foreign_key_constraint(:extracted_image_id)
  end
end
