defmodule MnemosyneEcto.Ecto.Links do
  @moduledoc """
  Ecto type that stores graph edge links as a JSON map.

  On the Elixir side, links are `%{atom() => MapSet.t(String.t())}`.
  On the DB side, they are `%{String.t() => [String.t()]}` stored as JSON
  (`jsonb` on PostgreSQL, `TEXT`/JSON on SQLite). Portable across both engines
  because it relies only on Ecto's `:map` base type.
  """
  use Ecto.Type

  alias Mnemosyne.Graph.Edge

  @impl Ecto.Type
  def type, do: :map

  @impl Ecto.Type
  def cast(links) when is_map(links), do: {:ok, links}
  def cast(_), do: :error

  @impl Ecto.Type
  def dump(links) when is_map(links) do
    json =
      Map.new(links, fn {edge_type, id_set} ->
        {Atom.to_string(edge_type), MapSet.to_list(id_set)}
      end)

    {:ok, json}
  end

  def dump(_), do: :error

  @impl Ecto.Type
  def load(nil), do: {:ok, Edge.empty_links()}

  def load(json) when is_map(json) do
    links =
      Enum.reduce(json, Edge.empty_links(), fn {key, ids}, acc ->
        edge_type = String.to_existing_atom(key)
        Map.put(acc, edge_type, MapSet.new(ids))
      end)

    {:ok, links}
  end

  def load(_), do: :error

  @impl Ecto.Type
  def equal?(a, b), do: a == b
end
