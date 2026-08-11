defmodule MnemosyneEcto.TestRepo.Postgres do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :mnemosyne_ecto,
    adapter: Ecto.Adapters.Postgres
end

defmodule MnemosyneEcto.TestRepo.SQLite do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :mnemosyne_ecto,
    adapter: Ecto.Adapters.SQLite3
end
