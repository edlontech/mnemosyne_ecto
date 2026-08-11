defmodule MnemosyneEcto.TestRepo.Postgres.Migrations.SetupIntegration do
  use Ecto.Migration

  def up do
    MnemosyneEcto.Migrations.up(
      version: 1,
      embedding_dimensions: 1536,
      prefix: "integration_"
    )
  end

  def down do
    MnemosyneEcto.Migrations.down(version: 1, prefix: "integration_")
  end
end
