# MnemosyneEcto

Database-agnostic Ecto backend for [Mnemosyne](https://github.com/edlontech/mnemosyne), the task-agnostic agentic memory library.

This library implements the `Mnemosyne.GraphBackend` behaviour and runs on either of two vector-capable engines — you pick which one simply by configuring your `Ecto.Repo`:

| Engine | Ecto adapter | Vector support | Required dep |
|--------|--------------|----------------|--------------|
| **PostgreSQL** | `Ecto.Adapters.Postgres` | [pgvector](https://github.com/pgvector/pgvector) (HNSW / IVFFlat) | `:pgvector` |
| **SQLite** | `Ecto.Adapters.SQLite3` | [sqlite-vec](https://github.com/asg017/sqlite-vec) (brute-force cosine) | `:sqlite_vec` |

The active engine is resolved at runtime from `repo.__adapter__()`; all engine-specific behaviour (vector column type, similarity queries, migrations, extension setup) lives behind `MnemosyneEcto.Adapter`.

## Installation

Add `mnemosyne_ecto` plus the driver/vector deps for the database you intend to use:

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

Write a single migration — the correct DDL for your repo's adapter is emitted automatically:

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
| `:index_type` | `:hnsw` | **PostgreSQL only** — `:hnsw` or `:ivfflat` |
| `:hnsw_m` | pgvector default | **PostgreSQL only** — max connections per HNSW layer |
| `:hnsw_ef_construction` | pgvector default | **PostgreSQL only** — dynamic candidate list size for HNSW |
| `:ivfflat_lists` | pgvector default | **PostgreSQL only** — number of inverted lists for IVFFlat |

> SQLite uses a brute-force `vec_distance_cosine` scan (which honours the tenant/repo/type SQL filters), so the PostgreSQL-only index options are ignored for SQLite repos.

### 2. Configure the backend

Set the default backend in your supervision tree so you don't repeat it on every `open_repo` call:

```elixir
children = [
  {Mnemosyne.Supervisor,
    config: config,
    llm: MyApp.LLM,
    embedding: MyApp.Embedding,
    backend: {MnemosyneEcto.Backend, repo: MyApp.Repo}}
]
```

Then open repos — `repo_id` is injected automatically from the first argument:

```elixir
# Single-tenant (tenant_id defaults to "default")
{:ok, _pid} = Mnemosyne.open_repo("my-project")

# Multi-tenant
{:ok, _pid} = Mnemosyne.open_repo("my-project", tenant_id: "org-123")
```

#### Backend options

| Option | Default | Description |
|--------|---------|-------------|
| `:repo` | -- (required) | Your Ecto repo module (adapter selects the engine) |
| `:repo_id` | injected by `open_repo/1,2` | Logical repository identifier |
| `:tenant_id` | `"default"` | Tenant identifier for multi-tenant isolation |
| `:prefix` | `"mnemosyne_"` | Table name prefix (must match migration) |

## Storage Model

Nodes are stored in a single polymorphic `nodes` table with JSON `data`, a vector `embedding`, and JSON `links` maps. Metadata lives in a separate `node_metadata` table. The schema is identical across engines; only the embedding column type differs (`vector(N)` on PostgreSQL, `float[N]` float32 blob on SQLite).

```
nodes                          node_metadata
+-----------+-----------+      +-------------+----------+
| id (text) | type      |      | node_id     | accessed |
| data      | embedding |      | reward      | recency  |
| links     | tenant_id |      | frequency   |          |
| repo_id   | created   |      +-------------+----------+
+-----------+-----------+
```

On PostgreSQL, vector indexes (HNSW or IVFFlat) are created per node type via partial indexes, avoiding the performance penalty of post-filtering across the full table. On SQLite, similarity search is an exact brute-force scan.

## Versioned Migrations

When a new schema version is released, create a new migration pointing to the next version:

```elixir
defmodule MyApp.Repo.Migrations.UpgradeMnemosyneV2 do
  use Ecto.Migration

  def up, do: MnemosyneEcto.Migrations.up(version: 2, embedding_dimensions: 1536)
  def down, do: MnemosyneEcto.Migrations.down(version: 2)
end
```

The migration system tracks the current version (via a table comment on PostgreSQL, a `<prefix>schema_version` table on SQLite) and runs only the deltas.

## Telemetry

All backend operations emit `[:mnemosyne_ecto, ...]` telemetry events. See `MnemosyneEcto.Telemetry` for the full list of events and their measurements.

## License

MIT
