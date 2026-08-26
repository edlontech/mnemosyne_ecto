defmodule MnemosyneEcto.Queries.IngestionQueries do
  @moduledoc """
  Ecto query builders for durable source ingestion records.
  """

  import Ecto.Query

  alias MnemosyneEcto.Schema.Ingestion

  @doc "Returns the `{table_name, schema}` source tuple for ingestion records."
  @spec source(map()) :: {String.t(), module()}
  def source(%{prefix: prefix}), do: {"#{prefix}ingestions", Ingestion}

  @doc "Filters ingestion records by tenant, repository, and source."
  @spec for_source(map(), String.t()) :: Ecto.Query.t()
  def for_source(state, source_id) do
    from i in source(state),
      where:
        i.tenant_id == ^state.tenant_id and i.repo_id == ^state.repo_id and
          i.source_id == ^source_id
  end
end
