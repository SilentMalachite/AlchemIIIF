defmodule AlchemIiif.Ingestion.PdfSource do
  @moduledoc """
  PDF ソースを管理する Ecto スキーマ。
  PDFファイルの追跡・ステータス管理を行います。

  ## なぜこの設計か

  - **ステータス管理**: `uploading → converting → ready / error` の遷移を
    追跡することで、処理途中でサーバーが再起動した場合でも、
    どのPDFがどの段階にあるか復元できます。
  - **ExtractedImage との 1:N 関連**: 1つのPDFから複数のページ画像が
    抽出されるため、親子関係で管理します。PDF単位での一括削除にも対応します。
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "pdf_sources" do
    # PDFファイル名
    field :filename, :string
    # ページ数
    field :page_count, :integer
    # 処理ステータス (uploading, converting, ready, error)
    field :status, :string, default: "uploading"

    has_many :extracted_images, AlchemIiif.Ingestion.ExtractedImage

    timestamps(type: :utc_datetime)
  end

  @doc "バリデーション用 changeset"
  def changeset(pdf_source, attrs) do
    pdf_source
    |> cast(attrs, [:filename, :page_count, :status])
    |> validate_required([:filename])
    |> validate_inclusion(:status, ["uploading", "converting", "ready", "error"])
  end
end
