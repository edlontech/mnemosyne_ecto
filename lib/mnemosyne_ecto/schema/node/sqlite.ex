if Code.ensure_loaded?(Ecto.Adapters.SQLite3) do
  defmodule MnemosyneEcto.Schema.Node.SQLite do
    @moduledoc """
    `mnemosyne_nodes` schema for SQLite, using a `sqlite-vec` float32 embedding column.
    """
    use MnemosyneEcto.Schema.Node, embedding_type: MnemosyneEcto.SqliteVec.Ecto.Float32
  end
end
