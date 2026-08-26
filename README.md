# MnemosyneEcto

**NOTE**: Mnemosyne is on heavy development, expect breaking changes

Database-agnostic Ecto backend for [Mnemosyne](https://github.com/edlontech/mnemosyne), the task-agnostic agentic memory library.

This library implements the `Mnemosyne.GraphBackend` behaviour and runs on either of two vector-capable engines. Configure your `Ecto.Repo` to choose the engine:

| Engine | Ecto adapter | Vector support | Required dep |
|--------|--------------|----------------|--------------|
| **PostgreSQL** | `Ecto.Adapters.Postgres` | [pgvector](https://github.com/pgvector/pgvector) (HNSW / IVFFlat) | `:pgvector` |
| **SQLite** | `Ecto.Adapters.SQLite3` | [sqlite-vec](https://github.com/asg017/sqlite-vec) (brute-force cosine) | `:sqlite_vec` |

The active engine is resolved at runtime from `repo.__adapter__()`. Engine-specific vector columns, similarity queries, migrations, and extension setup live behind `MnemosyneEcto.Adapter`.

## Installation

```elixir
def deps do
  [
    {:mnemosyne_ecto, "~> 0.1.0"}, # x-release-please-version

    # For PostgreSQL:
    {:postgrex, ">= 0.0.0"},
    {:pgvector, "~> 0.3"},

    # For SQLite:
    {:ecto_sqlite3, "~> 0.24"},
    {:sqlite_vec, "~> 0.1"}
  ]
end
```

`:pgvector` and `:sqlite_vec` are optional dependencies of `mnemosyne_ecto`; include only the ones for the engine you use.

## Choosing a database

You choose the database purely by which adapter your repo uses.

### PostgreSQL

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres
end
```

Ensure the `pgvector` extension is available in your PostgreSQL instance (v0.5+). The migration runs `CREATE EXTENSION IF NOT EXISTS vector` for you.

### SQLite

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.SQLite3
end
```

The `sqlite-vec` extension must be loaded on **every** connection via the repo's `:load_extensions` option:

```elixir
config :my_app, MyApp.Repo,
  database: "my_app.db",
  load_extensions: [SqliteVec.path()]
```

## Setup

### 1. Create a migration

Write a single migration. The correct DDL for your repo's adapter is emitted automatically, creating graph nodes, node metadata, and permanent ingestion records:

```elixir
defmodule MyApp.Repo.Migrations.AddMnemosyne do
  use Ecto.Migration

  def up, do: MnemosyneEcto.Migrations.up(version: 1, embedding_dimensions: 1536)
  def down, do: MnemosyneEcto.Migrations.down(version: 1)
end
```

#### Migration options

| Option | Default | Description |
|--------|---------|-------------|
| `:version` | `1` | Target migration version |
| `:embedding_dimensions` | -- (required) | Dimensionality of your embedding vectors |
| `:prefix` | `"mnemosyne_"` | Table name prefix |
| `:index_type` | `:hnsw` | **PostgreSQL only**: `:hnsw` or `:ivfflat` |
| `:hnsw_m` | pgvector default | **PostgreSQL only**: max connections per HNSW layer |
| `:hnsw_ef_construction` | pgvector default | **PostgreSQL only**: dynamic candidate list size for HNSW |
| `:ivfflat_lists` | pgvector default | **PostgreSQL only**: number of inverted lists for IVFFlat |

> SQLite uses a brute-force `vec_distance_cosine` scan that honors tenant, repository, and type SQL filters. PostgreSQL-only index options are ignored for SQLite repos.

### 2. Configure the backend

Set the default backend in your supervision tree so you do not repeat it on every `open_repo` call:

```elixir
children = [
  {Mnemosyne.Supervisor,
    config: config,
    llm: MyApp.LLM,
    embedding: MyApp.Embedding,
    backend: {MnemosyneEcto.Backend, repo: MyApp.Repo}}
]
```

Then open a repo. `repo_id` is injected automatically from the first argument:

```elixir
# Single-tenant (the configured backend defaults tenant_id to "default")
{:ok, _pid} = Mnemosyne.open_repo("my-project")

# Multi-tenant (override the backend for this repository)
{:ok, _pid} =
  Mnemosyne.open_repo("my-project",
    backend: {MnemosyneEcto.Backend, repo: MyApp.Repo, tenant_id: "org-123"}
  )
```

#### Backend options

| Option | Default | Description |
|--------|---------|-------------|
| `:repo` | -- (required) | Your Ecto repo module (adapter selects the engine) |
| `:repo_id` | injected by `open_repo/1,2` | Logical repository identifier |
| `:tenant_id` | `"default"` | Tenant identifier for multi-tenant isolation |
| `:prefix` | `"mnemosyne_"` | Table name prefix (must match migration) |

## Trajectory ingestion

Use the public `Mnemosyne.ingest/3` API with a caller-owned completed `%Mnemosyne.Trajectory{}`. Through ordinary `MnemosyneEcto.Backend` configuration, it is a blocking stored-or-error boundary. On success, every returned node ID is immediately visible:

```elixir
trajectory = %Mnemosyne.Trajectory{
  source_id: "deploy-2026-08-26",
  goal: "Deploy the service",
  steps: [%{observation: "Health checks passed", action: "Completed deployment"}]
}

{:ok, receipt} = Mnemosyne.ingest("my-project", trajectory)

Enum.each(receipt.node_ids, fn node_id ->
  {:ok, _node} = Mnemosyne.get_node("my-project", node_id)
end)
```

The source key is scoped to the tenant, repository, and `source_id`. An equal retry returns the exact original receipt. Reusing that source ID with a different payload returns an ingestion conflict error without changing stored memory. The database is authoritative for concurrent callers: one writer stores the graph and receipt, and equal callers receive that stored receipt. Receipts survive repository restarts and graph-node deletion; an equal retry after deletion returns the historical receipt without recreating nodes. The same source ID remains independent across tenants and repositories.

PostgreSQL and SQLite expose the same behavior. SQLite internally retries one complete rolled-back transaction only when Exqlite raises its locked `"Database busy"` error. A second busy error or any nonmatching error remains a `StorageError`.

## Storage model

The configured prefix creates three tables:

| Table | Purpose |
|-------|---------|
| `#{prefix}nodes` | Graph nodes with JSON data, vector embedding, and JSON links. |
| `#{prefix}node_metadata` | Access and reward metadata for graph nodes. |
| `#{prefix}ingestions` | Permanent ingestion records keyed by `tenant_id`, `repo_id`, and `source_id`. |

Each ingestion record stores the payload digest, fingerprint version, ordered node IDs, and a microsecond-precision stored timestamp. It intentionally has no graph foreign key: receipt node IDs are historical output, so the receipt remains valid when graph nodes are deleted, decayed, consolidated, or repaired.

On PostgreSQL, vector indexes (HNSW or IVFFlat) are created per node type via partial indexes, avoiding the performance penalty of post-filtering across the full table. On SQLite, similarity search is an exact brute-force scan.

## Telemetry

`MnemosyneEcto.Telemetry` documents `get_ingestion` and `commit_ingestion` spans. They include tenant, repository, and source correlation; status metadata; and numeric record and node counts without payload or receipt contents.

## License

MIT
