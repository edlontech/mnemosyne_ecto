defmodule MnemosyneEcto.Schema.Ingestion do
  @moduledoc """
  Ecto schema for durable source ingestion records.

  Uses a composite primary key of `(tenant_id, repo_id, source_id)`.
  This schema is engine-agnostic.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}
  @primary_key false

  schema "mnemosyne_ingestions" do
    field :tenant_id, :string, primary_key: true
    field :repo_id, :string, primary_key: true
    field :source_id, :string, primary_key: true
    field :payload_digest, :binary
    field :fingerprint_version, :integer
    field :node_ids, {:array, :string}
    field :stored_at, :utc_datetime_usec
  end
end
