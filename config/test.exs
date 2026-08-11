import Config

config :mnemosyne_ecto, MnemosyneEcto.TestRepo.Postgres,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  database: System.get_env("POSTGRES_DB", "mnemosyne_ecto_test"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 30,
  priv: "priv/repo/postgres",
  types: MnemosyneEcto.PostgrexTypes

config :mnemosyne_ecto, MnemosyneEcto.TestRepo.SQLite,
  database: Path.expand("../priv/sqlite/mnemosyne_ecto_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1,
  priv: "priv/repo/sqlite",
  journal_mode: :wal
