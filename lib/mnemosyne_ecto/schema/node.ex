defmodule MnemosyneEcto.Schema.Node do
  @moduledoc """
  Shared definition for the polymorphic `mnemosyne_nodes` table schema.

  All node types (semantic, episodic, procedural, etc.) live in a single table
  with JSON `data`/`links` fields and a vector `embedding` column. The embedding
  column type is the only thing that differs between database engines, so the
  concrete schema modules (`MnemosyneEcto.Schema.Node.Postgres` and
  `MnemosyneEcto.Schema.Node.SQLite`) inject it via `use`.

      use MnemosyneEcto.Schema.Node, embedding_type: Pgvector.Ecto.Vector
  """

  @doc false
  defmacro __using__(opts) do
    embedding_type = Keyword.fetch!(opts, :embedding_type)

    quote do
      use Ecto.Schema

      @type t :: %__MODULE__{}
      @primary_key {:id, :string, autogenerate: false}
      @timestamps_opts false

      schema "mnemosyne_nodes" do
        field :tenant_id, :string
        field :repo_id, :string
        field :type, :string
        field :data, :map, default: %{}
        field :embedding, unquote(embedding_type)
        field :links, MnemosyneEcto.Ecto.Links, default: %{}
        field :created_at, :utc_datetime_usec
      end
    end
  end
end
