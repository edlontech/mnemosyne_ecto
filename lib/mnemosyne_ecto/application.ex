defmodule MnemosyneEcto.Application do
  @moduledoc false

  use Application

  @impl true
  @doc false
  def start(_type, _args) do
    children = test_repo() ++ dev_children()
    opts = [strategy: :one_for_one, name: MnemosyneEcto.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc false
  if Mix.env() in [:dev, :test] do
    def test_repo do
      [
        MnemosyneEcto.TestRepo.Postgres,
        MnemosyneEcto.TestRepo.SQLite
      ]
    end
  else
    def test_repo, do: []
  end

  @doc false
  if Mix.env() == :dev do
    def dev_children do
      if System.get_env("TIDEWAVE_REPL") == "true" and Code.ensure_loaded?(Bandit) do
        ensure_tidewave_started()
        port = String.to_integer(System.get_env("TIDEWAVE_PORT", "10005"))
        [{Bandit, plug: Tidewave, port: port}]
      else
        []
      end
    end

    defp ensure_tidewave_started do
      case Application.ensure_all_started(:tidewave) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  else
    def dev_children, do: []
  end
end
