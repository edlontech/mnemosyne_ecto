defmodule MnemosyneEcto do
  @moduledoc """
  Database-agnostic Ecto backend for the Mnemosyne agentic memory library.

  Provides `MnemosyneEcto.Backend`, a `Mnemosyne.GraphBackend` implementation for
  PostgreSQL with pgvector or SQLite with sqlite-vec. The configured Ecto adapter
  selects the engine; `MnemosyneEcto.Adapter` contains engine-specific vector,
  migration, and extension behavior.

  Graph nodes, node metadata, and permanent ingestion records use three
  dynamically prefixed tables. Ingestion records are scoped by tenant, repository,
  and source ID. They preserve a payload digest, fingerprint version, ordered node
  IDs, and microsecond stored timestamp without a graph foreign key, so receipts
  survive graph-node deletion.

  ## Trajectory ingestion

  Configure `MnemosyneEcto.Backend` normally, then submit caller-owned complete
  trajectories through `Mnemosyne.ingest/3`. It blocks until graph changes and the
  durable receipt are stored, or returns an error. The returned node IDs are
  immediately queryable. Equal retries return the exact original receipt;
  conflicting source reuse returns an ingestion error. Database uniqueness selects
  the concurrent winner, making receipts durable across restarts and independent
  across tenants and repositories.

  PostgreSQL and SQLite have equivalent observable behavior. SQLite retries one
  complete rolled-back transaction only for Exqlite's locked `"Database busy"`
  error; a second or nonmatching error is a `StorageError`.

  `MnemosyneEcto.Telemetry` documents the `get_ingestion` and `commit_ingestion`
  spans, including correlation, status, and numeric count measurements.

  ## Choosing a database

  Configure your own `Ecto.Repo` with the desired adapter:

      # PostgreSQL
      defmodule MyApp.Repo do
        use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres
      end

      # SQLite (load the sqlite-vec extension on every connection)
      defmodule MyApp.Repo do
        use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.SQLite3
      end

      config :my_app, MyApp.Repo, load_extensions: [SqliteVec.path()]

  ## Setup

      {Mnemosyne.Supervisor,
        config: config,
        llm: MyApp.LLM,
        embedding: MyApp.Embedding,
        backend: {MnemosyneEcto.Backend, repo: MyApp.Repo}}

      # The configured backend defaults tenant_id to "default".
      Mnemosyne.open_repo("my-project")

      Mnemosyne.open_repo("my-project",
        backend: {MnemosyneEcto.Backend, repo: MyApp.Repo, tenant_id: "org-123"}
      )

  ## Migrations

  A V1 migration creates all three tables for either adapter:

      defmodule MyApp.Repo.Migrations.SetupMnemosyne do
        use Ecto.Migration

        def up, do: MnemosyneEcto.Migrations.up(version: 1, embedding_dimensions: 1536)
        def down, do: MnemosyneEcto.Migrations.down(version: 1)
      end

  This is a clean break. Drop and recreate MnemosyneEcto tables or databases from
  pre-ingestion versions. V1 was rewritten in place: `current_version/0` remains
  `1`, with no V2 upgrade, data conversion, session compatibility, or dual
  read/write path.
  """
end
