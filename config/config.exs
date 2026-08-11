import Config

if config_env() in [:test, :dev] do
  config :mnemosyne_ecto,
    ecto_repos: [MnemosyneEcto.TestRepo.Postgres, MnemosyneEcto.TestRepo.SQLite]
end

import_config "#{config_env()}.exs"
