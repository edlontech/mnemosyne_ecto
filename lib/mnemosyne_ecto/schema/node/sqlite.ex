if Code.ensure_loaded?(SqliteVec.Ecto.Float32) do
  defmodule MnemosyneEcto.Schema.Node.SQLite do
    @moduledoc """
    `mnemosyne_nodes` schema for SQLite, using a `sqlite-vec` float32 embedding column.
    """
    use MnemosyneEcto.Schema.Node, embedding_type: SqliteVec.Ecto.Float32
  end
end
