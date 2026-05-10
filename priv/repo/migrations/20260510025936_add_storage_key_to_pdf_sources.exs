defmodule AlchemIiif.Repo.Migrations.AddStorageKeyToPdfSources do
  @moduledoc """
  pdf_sources に storage_key を追加。
  ファイル保存パスを `pages/{storage_key}/` に切り替えて、
  `mix ecto.reset` 後の ID 再採番でも旧ファイルと混在しないようにする。

  既存レコードは `to_string(id)` でバックフィルし、
  互換のため旧パス `pages/{id}/` がそのまま参照可能な状態を保つ。
  新規作成行は schema 側で UUID を生成する。
  """
  use Ecto.Migration

  def change do
    alter table(:pdf_sources) do
      add :storage_key, :string
    end

    execute(
      """
      UPDATE pdf_sources SET storage_key = id::text WHERE storage_key IS NULL
      """,
      """
      UPDATE pdf_sources SET storage_key = NULL
      """
    )

    alter table(:pdf_sources) do
      modify :storage_key, :string, null: false
    end

    create unique_index(:pdf_sources, [:storage_key])
  end
end
