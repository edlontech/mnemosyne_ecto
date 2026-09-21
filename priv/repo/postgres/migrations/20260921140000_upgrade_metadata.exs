defmodule MnemosyneEcto.TestRepo.Postgres.Migrations.UpgradeMetadata do
  use Ecto.Migration

  def up do
    MnemosyneEcto.Migrations.up(version: 2)
    MnemosyneEcto.Migrations.up(version: 2, prefix: "integration_")
  end

  def down do
    MnemosyneEcto.Migrations.down(version: 2, prefix: "integration_")
    MnemosyneEcto.Migrations.down(version: 2)
  end
end
