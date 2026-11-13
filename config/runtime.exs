import Config

# The sqlite-vec extension must be loaded on every SQLite connection. Its path is
# only resolvable at runtime (after deps are compiled/available), so we configure
# it here rather than in the compile-time config files.
if config_env() in [:dev, :test] do
  config :mnemosyne_ecto, MnemosyneEcto.TestRepo.SQLite,
    load_extensions: [MnemosyneEcto.SqliteVec.path()]
end
