defmodule MnemosyneEcto.DataCase do
  @moduledoc """
  Test case for the data layer, parameterized across both supported database
  engines.

  Test modules opt in to running against PostgreSQL and SQLite by passing the
  `:parameterize` option built by `repos/0`:

      use MnemosyneEcto.DataCase, async: false, parameterize: MnemosyneEcto.DataCase.repos()

  Each parameter set injects `:repo` into the test context; `setup/1` resolves
  the matching `:adapter`, starts the SQL sandbox for that repo, and exposes a
  ready-to-use `:state` map plus `:repo`/`:adapter`.
  """

  use ExUnit.CaseTemplate

  @doc "Parameter sets covering every supported database engine."
  def repos do
    [
      %{repo: MnemosyneEcto.TestRepo.Postgres},
      %{repo: MnemosyneEcto.TestRepo.SQLite}
    ]
  end

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import MnemosyneEcto.DataCase
      import MnemosyneEcto.Factory
    end
  end

  setup context do
    repo = Map.fetch!(context, :repo)
    adapter = MnemosyneEcto.Adapter.for_repo(repo)

    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(repo, shared: not context[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    state = %{
      repo: repo,
      adapter: adapter,
      tenant_id: "t1",
      repo_id: "r1",
      prefix: "mnemosyne_"
    }

    {:ok, repo: repo, adapter: adapter, state: state}
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
