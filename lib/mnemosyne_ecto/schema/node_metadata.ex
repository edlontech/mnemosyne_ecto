defmodule MnemosyneEcto.Schema.NodeMetadata do
  @moduledoc """
  Ecto schema for the `mnemosyne_node_metadata` table.

  Tracks access statistics and reinforcement learning rewards per node,
  scoped by tenant. Uses a composite primary key of `(tenant_id, node_id)`.
  This schema is engine-agnostic (no vector column).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}
  @primary_key false
  @timestamps_opts false

  schema "mnemosyne_node_metadata" do
    field :tenant_id, :string, primary_key: true
    field :node_id, :string, primary_key: true
    field :access_count, :integer, default: 0
    field :last_accessed_at, :utc_datetime_usec
    field :created_at, :utc_datetime_usec
    field :cumulative_reward, :float, default: 0.0
    field :reward_count, :integer, default: 0
  end
end
