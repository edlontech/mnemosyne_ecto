defmodule MnemosyneEcto.TestRepo.SQLite.Migrations.SetupMnemosyne do
  use Ecto.Migration

  def up do
    MnemosyneEcto.Migrations.up(version: 1, embedding_dimensions: 3)
  end

  def down do
    MnemosyneEcto.Migrations.down(version: 1)
  end
end
