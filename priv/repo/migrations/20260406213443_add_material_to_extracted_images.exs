defmodule AlchemIiif.Repo.Migrations.AddMaterialToExtractedImages do
  use Ecto.Migration

  def change do
    alter table(:extracted_images) do
      add :material, :string
    end
  end
end
