defmodule AlchemIiif.Repo.Migrations.AddSiteCodeToPdfSources do
  use Ecto.Migration

  def change do
    alter table(:pdf_sources) do
      add :site_code, :string
    end
  end
end
