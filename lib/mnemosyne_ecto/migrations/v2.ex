defmodule MnemosyneEcto.Migrations.V2 do
  @moduledoc false
  use Ecto.Migration

  @doc "Adds audience classification and caller-owned metadata without classifying legacy rows."
  @spec up(keyword()) :: any()
  def up(opts) do
    prefix = Keyword.get(opts, :prefix, "mnemosyne_")

    alter table(:"#{prefix}node_metadata") do
      add :audience, :binary
      add :custom, :map, null: false, default: %{}
    end

    alter table(:"#{prefix}ingestions") do
      add :audience, :binary
    end
  end

  @doc "Removes the V2 metadata columns."
  @spec down(keyword()) :: any()
  def down(opts) do
    prefix = Keyword.get(opts, :prefix, "mnemosyne_")

    alter table(:"#{prefix}ingestions") do
      remove :audience
    end

    alter table(:"#{prefix}node_metadata") do
      remove :custom
      remove :audience
    end
  end
end
