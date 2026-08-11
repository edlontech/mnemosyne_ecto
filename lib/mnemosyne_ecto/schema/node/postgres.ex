if Code.ensure_loaded?(Pgvector.Ecto.Vector) do
  defmodule MnemosyneEcto.Schema.Node.Postgres do
    @moduledoc """
    `mnemosyne_nodes` schema for PostgreSQL, using a `pgvector` embedding column.
    """
    use MnemosyneEcto.Schema.Node, embedding_type: Pgvector.Ecto.Vector
  end
end
