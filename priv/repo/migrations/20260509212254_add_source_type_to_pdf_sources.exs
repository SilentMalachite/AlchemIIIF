defmodule AlchemIiif.Repo.Migrations.AddSourceTypeToPdfSources do
  use Ecto.Migration

  def change do
    alter table(:pdf_sources) do
      add :source_type, :string, null: false, default: "pdf"
    end

    create index(:pdf_sources, [:source_type])
  end
end
