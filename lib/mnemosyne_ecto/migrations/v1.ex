defmodule MnemosyneEcto.Migrations.V1 do
  @moduledoc false
  use Ecto.Migration

  alias MnemosyneEcto.Adapter

  @doc "Runs the V1 up migration creating nodes and metadata tables."
  @spec up(keyword()) :: any()
  def up(opts) do
    prefix = Keyword.get(opts, :prefix, "mnemosyne_")
    dimensions = Keyword.fetch!(opts, :embedding_dimensions)
    adapter = Adapter.for_repo(repo())

    datetime_type = adapter.timestamp_column_type()

    nodes_table = :"#{prefix}nodes"
    metadata_table = :"#{prefix}node_metadata"

    adapter.setup(opts)

    create table(nodes_table, primary_key: false) do
      add :id, :text, primary_key: true, null: false
      add :tenant_id, :text, null: false
      add :repo_id, :text, null: false
      add :type, :text, null: false
      add :data, :map, null: false
      add :embedding, adapter.embedding_column_type(dimensions)
      add :links, :map, null: false
      add :created_at, datetime_type, null: false
    end

    create table(metadata_table, primary_key: false) do
      add :tenant_id, :text, null: false, primary_key: true

      add(
        :node_id,
        references(nodes_table, type: :text, column: :id, on_delete: :delete_all),
        null: false,
        primary_key: true
      )

      add :access_count, :integer, null: false, default: 0
      add :last_accessed_at, datetime_type
      add :created_at, datetime_type, null: false
      add :cumulative_reward, :float, null: false, default: 0.0
      add :reward_count, :integer, null: false, default: 0
    end

    create index(nodes_table, [:tenant_id, :repo_id, :type])

    adapter.create_vector_indexes(nodes_table, opts)
  end

  @doc "Rolls back the V1 migration, dropping nodes and metadata tables."
  @spec down(keyword()) :: any()
  def down(opts) do
    prefix = Keyword.get(opts, :prefix, "mnemosyne_")

    drop_if_exists table(:"#{prefix}node_metadata")
    drop_if_exists table(:"#{prefix}nodes")
  end
end
