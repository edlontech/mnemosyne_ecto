if Code.ensure_loaded?(Pgvector) do
  defmodule MnemosyneEcto.Adapter.Postgres do
    @moduledoc """
    PostgreSQL + pgvector implementation of `MnemosyneEcto.Adapter`.

    Stores embeddings in a `vector(N)` column, performs KNN via pgvector's
    `cosine_distance/2`, creates per-node-type partial HNSW/IVFFlat indexes,
    and tracks the migrated schema version in the nodes table comment.
    """

    @behaviour MnemosyneEcto.Adapter

    use Ecto.Migration

    import Ecto.Query
    import Pgvector.Ecto.Query

    alias MnemosyneEcto.Schema.Node.Postgres, as: NodeSchema

    @node_types ~W(semantic episodic procedural subgoal source tag intent)

    @impl true
    def node_schema, do: NodeSchema

    @impl true
    def encode_embedding(nil), do: nil
    def encode_embedding(list) when is_list(list), do: Pgvector.new(list)
    def encode_embedding(%Pgvector{} = vec), do: vec

    @impl true
    def decode_embedding(nil), do: nil
    def decode_embedding(%Pgvector{} = vec), do: Pgvector.to_list(vec)
    def decode_embedding(list) when is_list(list), do: list

    @impl true
    def vector_search(state, type, query_embedding, limit) do
      type_str = Atom.to_string(type)
      query_vec = Pgvector.new(query_embedding)

      from n in {"#{state.prefix}nodes", NodeSchema},
        where: n.tenant_id == ^state.tenant_id,
        where: n.repo_id == ^state.repo_id,
        where: n.type == ^type_str,
        where: not is_nil(n.embedding),
        order_by: cosine_distance(n.embedding, ^query_vec),
        limit: ^limit
    end

    @impl true
    def setup(_opts) do
      execute "CREATE EXTENSION IF NOT EXISTS vector"
    end

    @impl true
    def embedding_column_type(dimensions), do: :"vector(#{dimensions})"

    @impl true
    def timestamp_column_type, do: :timestamptz

    @impl true
    def create_vector_indexes(table, opts) do
      index_type = Keyword.get(opts, :index_type, :hnsw)

      for node_type <- @node_types do
        execute vector_index_sql(table, node_type, index_type, opts)
      end
    end

    @impl true
    def migrated_version(repo, prefix) do
      table_name = "#{prefix}nodes"
      query = "SELECT obj_description(oid) FROM pg_class WHERE relname = '#{table_name}'"

      case repo.query(query) do
        {:ok, %{rows: [[comment]]}} when is_binary(comment) -> String.to_integer(comment)
        _ -> 0
      end
    end

    @impl true
    def set_version(prefix, version) do
      execute "COMMENT ON TABLE #{prefix}nodes IS '#{version}'"
    end

    @impl true
    def teardown(_prefix), do: :ok

    defp vector_index_sql(table, node_type, :hnsw, opts) do
      """
      CREATE INDEX #{table}_#{node_type}_embedding_idx
      ON #{table}
      USING hnsw (embedding vector_cosine_ops)#{hnsw_with_clause(opts)}
      WHERE type = '#{node_type}'
      """
    end

    defp vector_index_sql(table, node_type, :ivfflat, opts) do
      """
      CREATE INDEX #{table}_#{node_type}_embedding_idx
      ON #{table}
      USING ivfflat (embedding vector_cosine_ops)#{ivfflat_with_clause(opts)}
      WHERE type = '#{node_type}'
      """
    end

    defp hnsw_with_clause(opts) do
      params =
        []
        |> maybe_add_param("m", opts[:hnsw_m])
        |> maybe_add_param("ef_construction", opts[:hnsw_ef_construction])

      case params do
        [] -> ""
        parts -> " WITH (#{Enum.join(parts, ", ")})"
      end
    end

    defp ivfflat_with_clause(opts) do
      case opts[:ivfflat_lists] do
        nil -> ""
        lists -> " WITH (lists = #{lists})"
      end
    end

    defp maybe_add_param(params, _key, nil), do: params
    defp maybe_add_param(params, key, value), do: params ++ ["#{key} = #{value}"]
  end
end
