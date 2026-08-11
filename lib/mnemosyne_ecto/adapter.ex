defmodule MnemosyneEcto.Adapter do
  @moduledoc """
  Database-specific behaviour for the Mnemosyne Ecto backend.

  Each supported database (PostgreSQL + pgvector, SQLite + sqlite-vec) provides
  an implementation that encapsulates everything that differs between engines:
  the embedding column type, how embeddings are encoded/decoded, how a vector
  similarity query is expressed, extension setup, and how the migration version
  is tracked.

  The active adapter is resolved at runtime from the repository's Ecto adapter
  via `for_repo/1`, so callers only ever configure a standard `Ecto.Repo`.
  """

  @type state :: map()

  @doc "The Ecto schema module for the `nodes` table (embedding column type differs per engine)."
  @callback node_schema() :: module()

  @doc "Encodes an embedding list into the value the driver expects for `insert_all`. Passthrough for `nil`."
  @callback encode_embedding([float()] | nil) :: term()

  @doc "Decodes a stored embedding value (driver struct or list) back into a plain list of floats."
  @callback decode_embedding(term()) :: [float()] | nil

  @doc """
  Builds an `Ecto.Query` returning the `limit` nearest nodes of `type` to
  `query_embedding` (a plain list), ordered by ascending cosine distance and
  scoped to the state's tenant/repo.
  """
  @callback vector_search(
              state(),
              type :: atom(),
              query_embedding :: [float()],
              limit :: non_neg_integer()
            ) ::
              Ecto.Query.t()

  @doc "Engine-specific setup run before creating tables (e.g. `CREATE EXTENSION vector`). May be a no-op."
  @callback setup(opts :: keyword()) :: any()

  @doc "The migration column type for the embedding field given the vector dimensionality."
  @callback embedding_column_type(dimensions :: pos_integer()) :: atom()

  @doc "The migration column type used for timestamp columns."
  @callback timestamp_column_type() :: atom()

  @doc "Creates engine-specific vector indexes for the nodes table. May be a no-op (e.g. SQLite brute-force)."
  @callback create_vector_indexes(table :: atom(), opts :: keyword()) :: any()

  @doc "Reads the currently migrated schema version for the given prefix. Returns 0 when unmigrated."
  @callback migrated_version(repo :: Ecto.Repo.t(), prefix :: String.t()) :: non_neg_integer()

  @doc "Persists the migrated schema version for the given prefix (run inside a migration)."
  @callback set_version(prefix :: String.t(), version :: pos_integer()) :: any()

  @doc "Engine-specific teardown run during a full rollback (e.g. dropping a version table). May be a no-op."
  @callback teardown(prefix :: String.t()) :: any()

  @doc """
  Resolves the `MnemosyneEcto.Adapter` implementation for the given repo based on
  its configured Ecto adapter.

  Raises `ArgumentError` for unsupported adapters.
  """
  @spec for_repo(Ecto.Repo.t()) :: module()
  def for_repo(repo) do
    for_ecto_adapter(repo.__adapter__())
  end

  @doc "Resolves the implementation directly from an Ecto adapter module."
  @spec for_ecto_adapter(module()) :: module()
  def for_ecto_adapter(Ecto.Adapters.Postgres), do: MnemosyneEcto.Adapter.Postgres
  def for_ecto_adapter(Ecto.Adapters.SQLite3), do: MnemosyneEcto.Adapter.SQLite

  def for_ecto_adapter(other) do
    raise ArgumentError, """
    Unsupported Ecto adapter: #{inspect(other)}.

    MnemosyneEcto supports:
      * Ecto.Adapters.Postgres (requires :pgvector)
      * Ecto.Adapters.SQLite3  (requires :sqlite_vec)
    """
  end
end
