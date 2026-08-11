defmodule MnemosyneEcto.Queries.NodeQueries do
  @moduledoc """
  Engine-agnostic Ecto query builders for the nodes table.

  The `{table, schema}` source is resolved from the active
  `MnemosyneEcto.Adapter` carried in the state, so the same builders work for
  both PostgreSQL and SQLite. Vector similarity search lives on the adapter
  (`c:MnemosyneEcto.Adapter.vector_search/4`) because its expression differs
  per engine.
  """

  import Ecto.Query

  @doc "Returns the `{table_name, schema}` source tuple for the nodes table."
  @spec source(map()) :: {String.t(), module()}
  def source(%{prefix: prefix, adapter: adapter}), do: {"#{prefix}nodes", adapter.node_schema()}

  @doc "Base query scoped to the current tenant."
  @spec base(map()) :: Ecto.Query.t()
  def base(state) do
    from n in source(state), where: n.tenant_id == ^state.tenant_id
  end

  @doc "Base query scoped to the current tenant and repo."
  @spec scoped(map()) :: Ecto.Query.t()
  def scoped(state) do
    from n in base(state), where: n.repo_id == ^state.repo_id
  end

  @doc "Filters the query to only include nodes with the given IDs."
  @spec by_ids(Ecto.Query.t(), [String.t()]) :: Ecto.Query.t()
  def by_ids(query, ids) do
    from n in query, where: n.id in ^ids
  end

  @doc "Filters the query to only include nodes of the given types."
  @spec by_types(Ecto.Query.t(), [atom()]) :: Ecto.Query.t()
  def by_types(query, types) do
    type_strings = Enum.map(types, &Atom.to_string/1)
    from n in query, where: n.type in ^type_strings
  end
end
