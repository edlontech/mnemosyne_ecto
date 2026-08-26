defmodule MnemosyneEcto.Backend do
  @moduledoc """
  Database-agnostic Ecto implementation of `Mnemosyne.GraphBackend`.

  Persists knowledge graph nodes in a single polymorphic `nodes` table with JSON
  `data`, vector embeddings, and JSON link maps. Metadata and durable ingestion
  receipts are stored in separate tables.

  `get_ingestion/2` returns the scoped durable record or `nil` without changing
  backend state. `commit_ingestion/3` atomically arbitrates a scoped source record
  and its graph changes. New sources return `:inserted`; equal digest and fingerprint retries
  return `:existing` with the original durable receipt and do not apply the
  supplied graph. Conflicting retries return `IngestionError`, while database or
  graph persistence failures return `StorageError`.

  The concrete database engine is resolved automatically from the configured
  repository's Ecto adapter:

    * `Ecto.Adapters.Postgres` → PostgreSQL + pgvector
    * `Ecto.Adapters.SQLite3` → SQLite + sqlite-vec

  See `MnemosyneEcto.Adapter` for the per-engine seam.

  ## Telemetry

  See `MnemosyneEcto.Telemetry` for the full list of events and their metadata.

  ## Error handling

  Callbacks whose behaviour spec includes `{:error, ...}` returns
  (`apply_changeset`, `get_ingestion`, `commit_ingestion`, `delete_nodes`,
  `find_candidates`, `get_nodes_by_type`) catch exceptions and return
  `{:error, StorageError.t()}`. `commit_ingestion` returns `IngestionError` for a
  durable source conflict instead. Callbacks that
  only define `{:ok, ...}` returns (`get_node`, `get_linked_nodes`,
  `get_metadata`, `update_metadata`, `delete_metadata`) let exceptions
  propagate, as the caller is expected to handle crashes via supervision.
  """

  @behaviour Mnemosyne.GraphBackend

  import Ecto.Query

  require Logger

  alias Mnemosyne.Errors.Framework.StorageError
  alias Mnemosyne.Errors.Invalid.IngestionError
  alias Mnemosyne.Graph.Edge
  alias Mnemosyne.Graph.Node, as: NodeProtocol
  alias Mnemosyne.Graph.Similarity
  alias Mnemosyne.NodeMetadata
  alias MnemosyneEcto.Adapter
  alias MnemosyneEcto.IngestionSerializer
  alias MnemosyneEcto.NodeSerializer
  alias MnemosyneEcto.Queries.IngestionQueries
  alias MnemosyneEcto.Queries.MetadataQueries
  alias MnemosyneEcto.Queries.NodeQueries
  alias MnemosyneEcto.Telemetry

  @required_opts [:repo, :repo_id]

  @impl true
  def init(opts) do
    with :ok <- validate_opts(opts) do
      repo = opts[:repo]

      {:ok,
       %{
         repo: repo,
         adapter: Adapter.for_repo(repo),
         tenant_id: Keyword.get(opts, :tenant_id, "default"),
         repo_id: opts[:repo_id],
         prefix: Keyword.get(opts, :prefix, "mnemosyne_")
       }}
    end
  end

  @impl true
  def get_ingestion(source_id, state) do
    metadata = %{tenant_id: state.tenant_id, repo_id: state.repo_id, source_id: source_id}

    Telemetry.span(:get_ingestion, metadata, fn ->
      result =
        try do
          row = state |> IngestionQueries.for_source(source_id) |> state.repo.one()
          record = if row, do: IngestionSerializer.from_row(row)
          {:ok, record, state}
        rescue
          exception ->
            Logger.error("get_ingestion failed: #{Exception.message(exception)}")
            {:error, storage_error(:get_ingestion, exception)}
        end

      {status, record_count} =
        case result do
          {:ok, nil, _state} -> {:missing, 0}
          {:ok, _record, _state} -> {:found, 1}
          {:error, _error} -> {:error, 0}
        end

      {result, %{record_count: record_count}, Map.put(metadata, :status, status)}
    end)
  end

  @impl true
  def commit_ingestion(record, changeset, state) do
    metadata = %{
      tenant_id: state.tenant_id,
      repo_id: state.repo_id,
      source_id: record.source_id
    }

    Telemetry.span(:commit_ingestion, metadata, fn ->
      result =
        try do
          state.repo.transaction(fn -> commit_ingestion_transaction(record, changeset, state) end)
          |> normalize_commit_result(state)
        rescue
          exception ->
            Logger.error("commit_ingestion failed: #{Exception.message(exception)}")
            {:error, storage_error(:commit_ingestion, exception)}
        end

      {status, record_inserted, nodes_inserted} =
        case result do
          {:ok, :inserted, _receipt, _state} ->
            {:inserted, 1, length(changeset.additions)}

          {:ok, :existing, _receipt, _state} ->
            {:existing, 0, 0}

          {:error, %IngestionError{}} ->
            {:conflict, 0, 0}

          {:error, _error} ->
            {:error, 0, 0}
        end

      measurements = %{record_inserted: record_inserted, nodes_inserted: nodes_inserted}
      {result, measurements, Map.put(metadata, :status, status)}
    end)
  end

  @impl true
  def apply_changeset(changeset, state) do
    metadata = %{tenant_id: state.tenant_id, repo_id: state.repo_id}

    Telemetry.span(:apply_changeset, metadata, fn ->
      result =
        state.repo.transaction(fn -> persist_changeset(changeset, state) end)
        |> case do
          {:ok, _} -> {:ok, state}
          {:error, reason} -> {:error, storage_error(:apply_changeset, reason)}
        end

      {result, %{nodes_inserted: length(changeset.additions)}}
    end)
  end

  @impl true
  def delete_nodes(node_ids, state) when is_list(node_ids) do
    metadata = %{
      tenant_id: state.tenant_id,
      repo_id: state.repo_id,
      node_count: length(node_ids)
    }

    Telemetry.span(:delete_nodes, metadata, fn ->
      result =
        state.repo.transaction(fn ->
          clean_stale_links(node_ids, state)
          delete_metadata_for_ids(node_ids, state)
          delete_nodes_by_ids(node_ids, state)
        end)
        |> case do
          {:ok, _} -> {:ok, state}
          {:error, reason} -> {:error, storage_error(:delete_nodes, reason)}
        end

      {result, %{}}
    end)
  end

  @impl true
  def find_candidates(node_types, query_embedding, tag_embeddings, vf_config, _opts, state) do
    metadata = %{
      node_types: node_types,
      tenant_id: state.tenant_id,
      repo_id: state.repo_id
    }

    Telemetry.span(:find_candidates, metadata, fn ->
      vf_module = Map.get(vf_config, :module, Mnemosyne.ValueFunction.Default)

      try do
        rows_by_type =
          Enum.map(node_types, fn type ->
            params = get_in(vf_config, [:params, type]) || %{}
            top_k = Map.get(params, :top_k, 20)
            limit = top_k * 2

            rows =
              state.adapter.vector_search(state, type, query_embedding, limit)
              |> state.repo.all()

            {type, rows}
          end)

        all_node_ids =
          rows_by_type
          |> Enum.flat_map(fn {_type, rows} -> Enum.map(rows, & &1.id) end)
          |> Enum.uniq()

        metadata_map = fetch_metadata_map(all_node_ids, state)

        candidates =
          Enum.flat_map(rows_by_type, fn {type, rows} ->
            params = get_in(vf_config, [:params, type]) || %{}
            threshold = Map.get(params, :threshold, 0.0)
            top_k = Map.get(params, :top_k, 20)

            rows
            |> Enum.map(fn row ->
              node = NodeSerializer.from_row(row, state.adapter)
              emb = NodeProtocol.embedding(node)
              relevance = compute_relevance(emb, query_embedding, tag_embeddings)
              node_meta = Map.get(metadata_map, node.id)
              score = vf_module.score(relevance, node, node_meta, params)
              {node, score}
            end)
            |> Enum.filter(fn {_node, score} -> score >= threshold end)
            |> Enum.sort_by(&elem(&1, 1), :desc)
            |> Enum.take(top_k)
          end)

        deduped =
          Enum.uniq_by(candidates, fn {node, _score} -> NodeProtocol.id(node) end)

        result = {:ok, deduped, state}
        {result, %{candidate_count: length(deduped)}}
      rescue
        e ->
          Logger.error("find_candidates failed: #{Exception.message(e)}")
          {{:error, storage_error(:find_candidates, e)}, %{}}
      end
    end)
  end

  @impl true
  def get_node(id, state) do
    metadata = %{tenant_id: state.tenant_id, repo_id: state.repo_id, node_id: id}

    Telemetry.span(:get_node, metadata, fn ->
      row =
        state
        |> NodeQueries.base()
        |> NodeQueries.by_ids([id])
        |> state.repo.one()

      node = if row, do: NodeSerializer.from_row(row, state.adapter)
      {{:ok, node, state}, %{}}
    end)
  end

  @impl true
  def get_linked_nodes(node_ids, _edge_type, state) do
    unique_ids = Enum.uniq(node_ids)

    nodes =
      state
      |> NodeQueries.base()
      |> NodeQueries.by_ids(unique_ids)
      |> state.repo.all()
      |> Enum.map(&NodeSerializer.from_row(&1, state.adapter))
      |> Enum.uniq_by(&NodeProtocol.id/1)

    {:ok, nodes, state}
  end

  @impl true
  def get_nodes_by_type(node_types, state) do
    metadata = %{
      tenant_id: state.tenant_id,
      repo_id: state.repo_id,
      node_types: node_types
    }

    Telemetry.span(:get_nodes_by_type, metadata, fn ->
      try do
        nodes =
          state
          |> NodeQueries.scoped()
          |> NodeQueries.by_types(node_types)
          |> state.repo.all()
          |> Enum.map(&NodeSerializer.from_row(&1, state.adapter))

        {{:ok, nodes, state}, %{}}
      rescue
        e ->
          Logger.error("get_nodes_by_type failed: #{Exception.message(e)}")
          {{:error, storage_error(:get_nodes_by_type, e)}, %{}}
      end
    end)
  end

  @impl true
  def get_metadata(node_ids, state) do
    rows =
      state
      |> MetadataQueries.base()
      |> MetadataQueries.by_node_ids(node_ids)
      |> state.repo.all()

    result = Map.new(rows, fn row -> {row.node_id, row_to_node_metadata(row)} end)
    {:ok, result, state}
  end

  @impl true
  def update_metadata(entries, state) when map_size(entries) == 0, do: {:ok, state}

  def update_metadata(entries, state) do
    now = DateTime.utc_now()
    source = MetadataQueries.source(state)

    rows =
      Enum.map(entries, fn {node_id, %NodeMetadata{} = meta} ->
        %{
          tenant_id: state.tenant_id,
          node_id: node_id,
          access_count: meta.access_count,
          last_accessed_at: meta.last_accessed_at,
          created_at: meta.created_at || now,
          cumulative_reward: meta.cumulative_reward,
          reward_count: meta.reward_count
        }
      end)

    replace_fields = [
      :access_count,
      :last_accessed_at,
      :cumulative_reward,
      :reward_count
    ]

    state.repo.insert_all(source, rows,
      on_conflict: {:replace, replace_fields},
      conflict_target: [:tenant_id, :node_id]
    )

    {:ok, state}
  end

  @impl true
  def delete_metadata(node_ids, state) do
    state
    |> MetadataQueries.base()
    |> MetadataQueries.by_node_ids(node_ids)
    |> state.repo.delete_all()

    {:ok, state}
  end

  # -- Private helpers --

  defp validate_opts(opts) do
    missing = Enum.reject(@required_opts, &Keyword.has_key?(opts, &1))

    case missing do
      [] -> :ok
      keys -> {:error, storage_error(:init, "missing required options: #{inspect(keys)}")}
    end
  end

  defp commit_ingestion_transaction(record, changeset, state) do
    row = IngestionSerializer.to_row(record, state.tenant_id, state.repo_id)

    case insert_ingestion(row, state) do
      1 ->
        persist_changeset(changeset, state)
        stored = fetch_ingestion!(record.source_id, state)
        {:inserted, stored.receipt}

      0 ->
        resolve_existing_ingestion(record, state)

      count ->
        state.repo.rollback(storage_error(:commit_ingestion, {:unexpected_insert_count, count}))
    end
  end

  defp resolve_existing_ingestion(record, state) do
    stored = fetch_ingestion!(record.source_id, state)

    if same_payload?(stored, record) do
      {:existing, stored.receipt}
    else
      state.repo.rollback(
        IngestionError.exception(source_id: record.source_id, reason: :source_conflict)
      )
    end
  end

  defp normalize_commit_result({:ok, {status, receipt}}, state) do
    {:ok, status, receipt, state}
  end

  defp normalize_commit_result({:error, %IngestionError{} = error}, _state), do: {:error, error}
  defp normalize_commit_result({:error, %StorageError{} = error}, _state), do: {:error, error}

  defp normalize_commit_result({:error, reason}, _state) do
    {:error, storage_error(:commit_ingestion, reason)}
  end

  defp insert_ingestion(row, state) do
    {count, _rows} =
      state.repo.insert_all(IngestionQueries.source(state), [row],
        on_conflict: :nothing,
        conflict_target: [:tenant_id, :repo_id, :source_id]
      )

    count
  end

  defp fetch_ingestion!(source_id, state) do
    case state |> IngestionQueries.for_source(source_id) |> state.repo.one() do
      nil ->
        state.repo.rollback(
          storage_error(:commit_ingestion, "ingestion record missing after insert arbitration")
        )

      row ->
        IngestionSerializer.from_row(row)
    end
  end

  defp same_payload?(stored, supplied) do
    stored.fingerprint_version == supplied.fingerprint_version and
      stored.payload_digest == supplied.payload_digest
  end

  defp persist_changeset(changeset, state) do
    insert_nodes(changeset.additions, state)
    apply_links(changeset.links, state)
    upsert_metadata(changeset.metadata, state)
    :ok
  end

  defp insert_nodes([], _state), do: :ok

  defp insert_nodes(additions, state) do
    rows =
      Enum.map(
        additions,
        &NodeSerializer.to_row(&1, state.tenant_id, state.repo_id, state.adapter)
      )

    source = NodeQueries.source(state)
    state.repo.insert_all(source, rows)
  end

  defp apply_links([], _state), do: :ok

  defp apply_links(links, state) do
    link_map = build_link_map(links)
    affected_ids = Map.keys(link_map)

    current_links_by_id =
      state
      |> NodeQueries.base()
      |> NodeQueries.by_ids(affected_ids)
      |> select([n], {n.id, n.links})
      |> state.repo.all()
      |> Map.new()

    source = NodeQueries.source(state)

    Enum.each(link_map, fn {node_id, new_links} ->
      current = Map.get(current_links_by_id, node_id, Edge.empty_links())
      merged = merge_links(current, new_links)

      from(n in source, where: n.id == ^node_id and n.tenant_id == ^state.tenant_id)
      |> state.repo.update_all(set: [links: merged])
    end)
  end

  defp build_link_map(links) do
    Enum.reduce(links, %{}, fn {id_a, id_b, edge_type}, acc ->
      acc
      |> Map.update(id_a, %{edge_type => MapSet.new([id_b])}, fn existing ->
        Map.update(existing, edge_type, MapSet.new([id_b]), &MapSet.put(&1, id_b))
      end)
      |> Map.update(id_b, %{edge_type => MapSet.new([id_a])}, fn existing ->
        Map.update(existing, edge_type, MapSet.new([id_a]), &MapSet.put(&1, id_a))
      end)
    end)
  end

  defp merge_links(current_links, new_links) do
    Enum.reduce(new_links, current_links, fn {edge_type, id_set}, acc ->
      existing = Map.get(acc, edge_type, MapSet.new())
      Map.put(acc, edge_type, MapSet.union(existing, id_set))
    end)
  end

  # Removes references to deleted node IDs from every remaining node's links.
  #
  # Implemented in pure Elixir (rather than an engine-specific JSON SQL query) so
  # it works identically on PostgreSQL and SQLite.
  defp clean_stale_links(deleted_ids, state) do
    deleted_set = MapSet.new(deleted_ids)
    source = NodeQueries.source(state)

    rows =
      state
      |> NodeQueries.scoped()
      |> where([n], n.id not in ^deleted_ids)
      |> select([n], {n.id, n.links})
      |> state.repo.all()

    rows
    |> Enum.filter(fn {_node_id, links} -> references_any?(links, deleted_set) end)
    |> Enum.each(fn {node_id, links} ->
      cleaned = clean_links(links, deleted_set)

      from(n in source, where: n.id == ^node_id and n.tenant_id == ^state.tenant_id)
      |> state.repo.update_all(set: [links: cleaned])
    end)
  end

  defp clean_links(links, deleted_set) do
    Map.new(links, fn {edge_type, id_set} ->
      {edge_type, MapSet.difference(id_set, deleted_set)}
    end)
  end

  defp references_any?(links, deleted_set) do
    Enum.any?(links, fn {_edge_type, id_set} -> not MapSet.disjoint?(id_set, deleted_set) end)
  end

  defp delete_metadata_for_ids(node_ids, state) do
    state
    |> MetadataQueries.base()
    |> MetadataQueries.by_node_ids(node_ids)
    |> state.repo.delete_all()
  end

  defp delete_nodes_by_ids(node_ids, state) do
    state
    |> NodeQueries.base()
    |> NodeQueries.by_ids(node_ids)
    |> state.repo.delete_all()
  end

  defp upsert_metadata(metadata, _state) when map_size(metadata) == 0, do: :ok

  defp upsert_metadata(metadata, state) do
    now = DateTime.utc_now()
    source = MetadataQueries.source(state)

    rows =
      Enum.map(metadata, fn {node_id, %NodeMetadata{} = meta} ->
        %{
          tenant_id: state.tenant_id,
          node_id: node_id,
          access_count: meta.access_count,
          last_accessed_at: meta.last_accessed_at,
          created_at: meta.created_at || now,
          cumulative_reward: meta.cumulative_reward,
          reward_count: meta.reward_count
        }
      end)

    replace_fields = [
      :access_count,
      :last_accessed_at,
      :cumulative_reward,
      :reward_count
    ]

    state.repo.insert_all(source, rows,
      on_conflict: {:replace, replace_fields},
      conflict_target: [:tenant_id, :node_id]
    )
  end

  defp fetch_metadata_map([], _state), do: %{}

  defp fetch_metadata_map(node_ids, state) do
    rows =
      state
      |> MetadataQueries.base()
      |> MetadataQueries.by_node_ids(node_ids)
      |> state.repo.all()

    Map.new(rows, fn row -> {row.node_id, row_to_node_metadata(row)} end)
  end

  defp compute_relevance(nil, _query_embedding, _tag_embeddings), do: 0.0

  defp compute_relevance(emb, query_embedding, tag_embeddings) do
    query_sim = Similarity.cosine_similarity(query_embedding, emb)

    tag_sim =
      tag_embeddings
      |> Enum.map(&Similarity.cosine_similarity(&1, emb))
      |> Enum.max(fn -> 0.0 end)

    max(query_sim, tag_sim) |> max(0.0)
  end

  defp row_to_node_metadata(row) do
    %NodeMetadata{
      access_count: row.access_count,
      last_accessed_at: row.last_accessed_at,
      created_at: row.created_at,
      cumulative_reward: row.cumulative_reward,
      reward_count: row.reward_count
    }
  end

  defp storage_error(operation, reason) do
    %StorageError{operation: operation, reason: reason}
  end
end
