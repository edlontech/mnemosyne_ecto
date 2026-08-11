defmodule MnemosyneEcto.Factory do
  @moduledoc """
  Lightweight, engine-agnostic test factory.

  Rows are inserted directly through the active repo's `{table, schema}` source
  resolved from the backend `state` (which carries `:repo`, `:adapter` and
  `:prefix`), encoding embeddings via the adapter so the same helpers work on
  PostgreSQL and SQLite.
  """

  alias MnemosyneEcto.Queries.MetadataQueries
  alias MnemosyneEcto.Queries.NodeQueries

  @doc "Builds a node attribute map, applying any overrides (map or keyword)."
  def node_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        id: "node-#{System.unique_integer([:positive])}",
        tenant_id: "t1",
        repo_id: "r1",
        type: "semantic",
        data: %{"proposition" => "test fact", "confidence" => 0.9},
        embedding: [0.1, 0.2, 0.3],
        links: %{},
        created_at: DateTime.utc_now()
      },
      Map.new(overrides)
    )
  end

  @doc "Inserts a node row into the active repo, returning the attribute map used."
  def insert_node(state, overrides \\ %{}) do
    attrs = node_attrs(overrides)
    row = %{attrs | embedding: state.adapter.encode_embedding(attrs.embedding)}
    state.repo.insert_all(NodeQueries.source(state), [row])
    attrs
  end

  @doc "Builds a node-metadata attribute map, applying any overrides (map or keyword)."
  def node_metadata_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        tenant_id: "t1",
        node_id: "node-#{System.unique_integer([:positive])}",
        access_count: 0,
        last_accessed_at: nil,
        created_at: DateTime.utc_now(),
        cumulative_reward: 0.0,
        reward_count: 0
      },
      Map.new(overrides)
    )
  end

  @doc "Inserts a node-metadata row into the active repo, returning the attribute map used."
  def insert_node_metadata(state, overrides \\ %{}) do
    attrs = node_metadata_attrs(overrides)
    state.repo.insert_all(MetadataQueries.source(state), [attrs])
    attrs
  end
end
