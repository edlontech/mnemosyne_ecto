import Config

config :mnemosyne_ecto, MnemosyneEcto.TestRepo.Postgres,
  username: "postgres",
  password: "postgres",
  database: "mnemosyne_ecto_dev",
  hostname: "localhost",
  pool_size: 10,
  priv: "priv/repo/postgres"

config :mnemosyne_ecto, MnemosyneEcto.TestRepo.SQLite,
  database: Path.expand("../priv/sqlite/mnemosyne_ecto_dev.db", __DIR__),
  pool_size: 5,
  priv: "priv/repo/sqlite"
