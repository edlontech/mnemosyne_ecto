if Code.ensure_loaded?(SqliteVec) do
  defmodule MnemosyneEcto.Adapter.SQLite do
    @moduledoc """
    SQLite + sqlite-vec implementation of `MnemosyneEcto.Adapter`.

    Stores embeddings as float32 blobs in a regular table (`float[N]` column),
    performs KNN via sqlite-vec's `vec_distance_cosine/2` with an `ORDER BY`
    brute-force scan (which honours the tenant/repo/type SQL filters), and tracks
    the migrated schema version in a dedicated `#{"<prefix>"}schema_version` table.

    The `sqlite-vec` extension must be loaded on every connection via the repo's
    `:load_extensions` option, e.g.

        config :my_app, MyApp.Repo,
          adapter: Ecto.Adapters.SQLite3,
          load_extensions: [SqliteVec.path()]
    """

    @behaviour MnemosyneEcto.Adapter

    use Ecto.Migration

    import Ecto.Query
    import SqliteVec.Ecto.Query

    alias MnemosyneEcto.Schema.Node.SQLite, as: NodeSchema

    @impl true
    def node_schema, do: NodeSchema

    @impl true
    def encode_embedding(nil), do: nil
    def encode_embedding(list) when is_list(list), do: SqliteVec.Float32.new(list)
    def encode_embedding(%SqliteVec.Float32{} = vec), do: vec

    @impl true
    def decode_embedding(nil), do: nil
    def decode_embedding(%SqliteVec.Float32{} = vec), do: SqliteVec.Float32.to_list(vec)
    def decode_embedding(list) when is_list(list), do: list

    @impl true
    def vector_search(state, type, query_embedding, limit) do
      type_str = Atom.to_string(type)
      query_vec = SqliteVec.Float32.new(query_embedding)

      from n in {"#{state.prefix}nodes", NodeSchema},
        where: n.tenant_id == ^state.tenant_id,
        where: n.repo_id == ^state.repo_id,
        where: n.type == ^type_str,
        where: not is_nil(n.embedding),
        order_by: vec_distance_cosine(n.embedding, vec_f32(query_vec)),
        limit: ^limit
    end

    @impl true
    def setup(_opts), do: :ok

    @impl true
    def embedding_column_type(dimensions), do: :"float[#{dimensions}]"

    @impl true
    def timestamp_column_type, do: :utc_datetime_usec

    @impl true
    def create_vector_indexes(_table, _opts), do: :ok

    @impl true
    def migrated_version(repo, prefix) do
      table_name = "#{prefix}schema_version"

      case repo.query("SELECT version FROM #{table_name} LIMIT 1") do
        {:ok, %{rows: [[version]]}} when is_integer(version) -> version
        _ -> 0
      end
    end

    @impl true
    def set_version(prefix, version) do
      table_name = "#{prefix}schema_version"
      execute "CREATE TABLE IF NOT EXISTS #{table_name} (version INTEGER NOT NULL)"
      execute "DELETE FROM #{table_name}"
      execute "INSERT INTO #{table_name} (version) VALUES (#{version})"
    end

    @impl true
    def teardown(prefix) do
      execute "DROP TABLE IF EXISTS #{prefix}schema_version"
    end
  end
end
