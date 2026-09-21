defmodule MnemosyneEcto.TestRepo.SQLite.Migrations.UpgradeMetadata do
  use Ecto.Migration

  def up, do: MnemosyneEcto.Migrations.up(version: 2)
  def down, do: MnemosyneEcto.Migrations.down(version: 2)
end
