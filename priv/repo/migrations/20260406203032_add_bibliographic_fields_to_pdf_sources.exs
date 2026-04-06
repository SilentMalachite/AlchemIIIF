defmodule AlchemIiif.Repo.Migrations.AddBibliographicFieldsToPdfSources do
  use Ecto.Migration

  def change do
    alter table(:pdf_sources) do
      add :investigating_org, :string
      add :survey_year, :integer
      add :report_title, :string
      add :license_uri, :string, default: "http://rightsstatements.org/vocab/InC/1.0/"
    end
  end
end
