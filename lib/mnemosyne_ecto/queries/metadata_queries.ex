defmodule MnemosyneEcto.Queries.MetadataQueries do
  @moduledoc """
  Ecto query builders for the node metadata table (engine-agnostic).
  """

  import Ecto.Query

  alias MnemosyneEcto.Schema.NodeMetadata

  @doc "Returns the `{table_name, schema}` source tuple for the metadata table."
  @spec source(map()) :: {String.t(), module()}
  def source(%{prefix: prefix}), do: {"#{prefix}node_metadata", NodeMetadata}

  @doc "Base query scoped to the current tenant."
  @spec base(map()) :: Ecto.Query.t()
  def base(state) do
    from m in source(state), where: m.tenant_id == ^state.tenant_id
  end

  @doc "Filters the query to only include rows matching the given node IDs."
  @spec by_node_ids(Ecto.Query.t(), [String.t()]) :: Ecto.Query.t()
  def by_node_ids(query, node_ids) do
    from m in query, where: m.node_id in ^node_ids
  end
end
