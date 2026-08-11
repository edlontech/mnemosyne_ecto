import Config

# The sqlite-vec extension must be loaded on every SQLite connection. Its path is
# only resolvable at runtime (after deps are compiled/available), so we configure
# it here rather than in the compile-time config files.
if config_env() in [:dev, :test] and Code.ensure_loaded?(SqliteVec) do
  config :mnemosyne_ecto, MnemosyneEcto.TestRepo.SQLite, load_extensions: [SqliteVec.path()]
end
