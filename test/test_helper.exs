ExUnit.start(exclude: [:integration], capture_log: true)

Ecto.Adapters.SQL.Sandbox.mode(MnemosyneEcto.TestRepo.Postgres, :manual)
Ecto.Adapters.SQL.Sandbox.mode(MnemosyneEcto.TestRepo.SQLite, :manual)
