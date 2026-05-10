defmodule AlchemIiif.Ingestion.PdfSource do
  @moduledoc """
  ソース（PDF/ZIP）を管理する Ecto スキーマ。

  ## 設計メモ

  - **source_type**: "pdf" / "zip" のいずれか。テーブル名・モジュール名・外部キー名は
    既存互換のため `pdf_*` を維持しつつ、内部で source_type による分岐を行う。
  - **status 遷移**: `uploading → converting → ready / error`（PDF・ZIP 共通）
  - **workflow_status**: `wip → pending_review → returned / approved`
  - **ExtractedImage との 1:N**: PDF/ZIP どちらも展開後の各ページが ExtractedImage
  """
  use Ecto.Schema
  import Ecto.Changeset

  @workflow_statuses ["wip", "pending_review", "returned", "approved"]
  @source_types ["pdf", "zip"]

  schema "pdf_sources" do
    field :filename, :string
    field :source_type, :string, default: "pdf"
    field :storage_key, :string
    field :page_count, :integer
    field :status, :string, default: "uploading"

    field :workflow_status, :string, default: "wip"
    field :return_message, :string

    field :deleted_at, :utc_datetime

    field :investigating_org, :string
    field :survey_year, :integer
    field :report_title, :string
    field :license_uri, :string
    field :site_code, :string

    belongs_to :user, AlchemIiif.Accounts.User

    has_many :extracted_images, AlchemIiif.Ingestion.ExtractedImage

    field :image_count, :integer, virtual: true, default: 0
    field :owner_email, :string, virtual: true, default: nil

    timestamps(type: :utc_datetime)
  end

  @doc "バリデーション用 changeset"
  def changeset(pdf_source, attrs) do
    pdf_source
    |> cast(attrs, [
      :filename,
      :source_type,
      :storage_key,
      :page_count,
      :status,
      :deleted_at,
      :workflow_status,
      :return_message,
      :user_id,
      :investigating_org,
      :survey_year,
      :report_title,
      :license_uri,
      :site_code
    ])
    |> ensure_storage_key()
    |> validate_required([:filename, :source_type, :storage_key])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:status, ["uploading", "converting", "ready", "error"])
    |> validate_inclusion(:workflow_status, @workflow_statuses)
    |> validate_number(:survey_year,
      greater_than_or_equal_to: 1900,
      less_than_or_equal_to: Date.utc_today().year
    )
    |> validate_length(:investigating_org, max: 200)
    |> validate_length(:report_title, max: 500)
    |> validate_license_uri()
    |> validate_length(:site_code, max: 30, message: "30文字以内で入力してください")
    |> unique_constraint(:storage_key)
  end

  @doc "ワークフロー遷移専用 changeset"
  def workflow_changeset(pdf_source, attrs) do
    pdf_source
    |> cast(attrs, [:workflow_status, :return_message])
    |> validate_required([:workflow_status])
    |> validate_inclusion(:workflow_status, @workflow_statuses)
  end

  @doc "PDF 由来の source か判定"
  def pdf?(%__MODULE__{source_type: "pdf"}), do: true
  def pdf?(%{source_type: "pdf"}), do: true
  def pdf?(_), do: false

  @doc "ZIP 由来の source か判定"
  def zip?(%__MODULE__{source_type: "zip"}), do: true
  def zip?(%{source_type: "zip"}), do: true
  def zip?(_), do: false

  # 新規作成時に storage_key が未指定なら UUID を自動付与する。
  # 永続化済みレコードに対する更新では既存値を維持する。
  defp ensure_storage_key(changeset) do
    case get_field(changeset, :storage_key) do
      key when is_binary(key) and key != "" -> changeset
      _ -> put_change(changeset, :storage_key, Ecto.UUID.generate())
    end
  end

  defp validate_license_uri(changeset) do
    validate_change(changeset, :license_uri, fn :license_uri, uri ->
      if String.starts_with?(uri, "http://") or String.starts_with?(uri, "https://") do
        []
      else
        [license_uri: "は http:// または https:// で始まる必要があります"]
      end
    end)
  end
end
