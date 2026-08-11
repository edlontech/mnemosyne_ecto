defmodule MnemosyneEcto do
  @moduledoc """
  Database-agnostic Ecto backend for the Mnemosyne agentic memory library.

  Provides a `Mnemosyne.GraphBackend` implementation (`MnemosyneEcto.Backend`)
  that runs on either of two vector-capable database engines, selected purely by
  the Ecto adapter of the repository you configure:

    * **PostgreSQL + pgvector** — `Ecto.Adapters.Postgres` (requires `:pgvector`)
    * **SQLite + sqlite-vec** — `Ecto.Adapters.SQLite3` (requires `:sqlite_vec`)

  Memory graph nodes, edges, and metadata are stored via Ecto schemas with
  multi-tenant isolation through a configurable table prefix. All engine-specific
  behaviour (vector column type, similarity queries, migrations, extension setup)
  lives behind `MnemosyneEcto.Adapter` and is resolved at runtime from the repo.

  ## Choosing a database

  You choose the database by configuring your own `Ecto.Repo` with the desired
  adapter — nothing else changes:

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

      # Set as default backend in your supervision tree
      {Mnemosyne.Supervisor,
        config: config,
        llm: MyApp.LLM,
        embedding: MyApp.Embedding,
        backend: {MnemosyneEcto.Backend, repo: MyApp.Repo}}

      # Open repos -- repo_id is injected from the first argument
      Mnemosyne.open_repo("my-project")
      Mnemosyne.open_repo("my-project", tenant_id: "org-123")

  ## Migrations

  Write a single migration; `MnemosyneEcto.Migrations` emits the correct DDL for
  whichever adapter your repo uses:

      defmodule MyApp.Repo.Migrations.SetupMnemosyne do
        use Ecto.Migration

        def up, do: MnemosyneEcto.Migrations.up(version: 1, embedding_dimensions: 1536)
        def down, do: MnemosyneEcto.Migrations.down(version: 1)
      end
  """
end
