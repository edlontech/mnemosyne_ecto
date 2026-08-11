defmodule MnemosyneEcto.Migrations do
  @current_version 1

  @moduledoc """
  Database-agnostic migrations for the MnemosyneEcto tables and indexes.

  Write a single migration in your application; the correct DDL for your repo's
  Ecto adapter (PostgreSQL/pgvector or SQLite/sqlite-vec) is emitted automatically
  via `MnemosyneEcto.Adapter`.

  ## Usage

      defmodule MyApp.Repo.Migrations.AddMnemosyne do
        use Ecto.Migration

        def up, do: MnemosyneEcto.Migrations.up(version: 1, embedding_dimensions: 1536)
        def down, do: MnemosyneEcto.Migrations.down(version: 1)
      end

  When a new version is released, generate a new migration:

      defmodule MyApp.Repo.Migrations.UpgradeMnemosyneV2 do
        use Ecto.Migration

        def up, do: MnemosyneEcto.Migrations.up(version: 2, embedding_dimensions: 1536)
        def down, do: MnemosyneEcto.Migrations.down(version: 2)
      end

  ## Options

    * `:version` - the target migration version (defaults to `#{@current_version}`)
    * `:embedding_dimensions` - (required for V1) the dimensionality of your embedding vectors
    * `:index_type` - PostgreSQL only: `:hnsw` (default) or `:ivfflat`
    * `:hnsw_m` - PostgreSQL only: max number of connections per layer for HNSW
    * `:hnsw_ef_construction` - PostgreSQL only: size of the dynamic candidate list for HNSW
    * `:ivfflat_lists` - PostgreSQL only: number of inverted lists for IVFFlat
    * `:prefix` - table name prefix, defaults to `"mnemosyne_"`

  SQLite uses a brute-force `vec_distance_cosine` scan, so the PostgreSQL-only
  index options are ignored for SQLite repos.
  """
  use Ecto.Migration

  # Both adapter modules (Postgres/SQLite) are conditionally compiled depending on
  # whether their optional deps (pgvector / sqlite_vec) are present in the project.
  # `Adapter.for_repo/1` resolves the correct implementation at runtime from the
  # repo's Ecto adapter, so the compile-time references below are legitimately
  # to a module that may be absent (e.g. Postgres in a SQLite-only project).
  # Silence the resulting "module is not available" warnings.
  @compile {:no_warn_undefined, [MnemosyneEcto.Adapter.Postgres, MnemosyneEcto.Adapter.SQLite]}

  alias MnemosyneEcto.Adapter

  @version_modules %{
    1 => MnemosyneEcto.Migrations.V1
  }

  @doc "Returns the current migration version."
  @spec current_version() :: pos_integer()
  def current_version, do: @current_version

  @doc """
  Runs the `up` migration for the given version.

  Executes all migration versions from the currently migrated version
  up to the target version sequentially.
  """
  @spec up(keyword()) :: :ok
  def up(opts \\ []) do
    version = Keyword.get(opts, :version, @current_version)
    prefix = Keyword.get(opts, :prefix, "mnemosyne_")
    adapter = Adapter.for_repo(repo())

    initial = adapter.migrated_version(repo(), prefix)

    Enum.each((initial + 1)..version//1, fn vsn ->
      module = Map.fetch!(@version_modules, vsn)
      module.up(opts)
    end)

    adapter.set_version(prefix, version)
  end

  @doc """
  Runs the `down` migration for the given version.

  Rolls back from the currently migrated version down to the target version.
  When called with `version: 1`, it rolls back V1 (dropping all tables).
  """
  @spec down(keyword()) :: :ok
  def down(opts \\ []) do
    version = Keyword.get(opts, :version, @current_version)
    prefix = Keyword.get(opts, :prefix, "mnemosyne_")
    adapter = Adapter.for_repo(repo())

    current = adapter.migrated_version(repo(), prefix)

    Enum.each(current..version//-1, fn vsn ->
      module = Map.fetch!(@version_modules, vsn)
      module.down(opts)
    end)

    if version <= 1, do: adapter.teardown(prefix)

    :ok
  end

  @doc """
  Returns the version that has been migrated for the given prefix.

  Returns 0 if no migrations have run.
  """
  @spec migrated_version(Ecto.Repo.t(), String.t()) :: non_neg_integer()
  def migrated_version(repo, prefix \\ "mnemosyne_") do
    Adapter.for_repo(repo).migrated_version(repo, prefix)
  end
end
