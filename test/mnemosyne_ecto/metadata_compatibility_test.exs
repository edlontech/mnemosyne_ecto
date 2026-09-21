defmodule MnemosyneEcto.MetadataCompatibilityTest do
  use MnemosyneEcto.DataCase, async: false, parameterize: MnemosyneEcto.DataCase.repos()

  alias Mnemosyne.Errors.Invalid.AccessError
  alias Mnemosyne.Graph.Changeset
  alias Mnemosyne.Graph.Node.Semantic
  alias Mnemosyne.IngestionReceipt
  alias Mnemosyne.NodeMetadata
  alias MnemosyneEcto.Backend

  test "ingestion audiences and custom metadata survive reopening and historical retries", %{
    state: state
  } do
    for {audience, index} <- Enum.with_index([:repo, [{"org", "private"}]]) do
      node = %Semantic{id: "ingested-#{index}", proposition: "fact", confidence: 1.0}
      metadata = NodeMetadata.new(audience: audience, custom: %{"source" => "caller"})

      changeset =
        Changeset.new()
        |> Changeset.add_node(node)
        |> Changeset.put_metadata(node.id, metadata)

      receipt = %IngestionReceipt{
        source_id: "source-#{index}",
        node_ids: [node.id],
        stored_at: DateTime.utc_now()
      }

      record = %{
        source_id: receipt.source_id,
        audience: audience,
        payload_digest: <<index>>,
        fingerprint_version: 1,
        receipt: receipt
      }

      assert {:ok, :inserted, ^receipt, ^state} =
               Backend.commit_ingestion(record, changeset, state)

      assert {:ok, reopened} = Backend.init(Map.to_list(state))
      assert {:ok, ^record, ^reopened} = Backend.get_ingestion(record.source_id, reopened)
      assert {:ok, stored, ^reopened} = Backend.get_metadata([node.id], reopened)
      assert stored[node.id] == metadata

      assert {:ok, ^reopened} = Backend.delete_nodes([node.id], reopened)

      assert {:ok, :existing, ^receipt, ^reopened} =
               Backend.commit_ingestion(record, changeset, reopened)

      assert {:ok, ^record, ^reopened} = Backend.get_ingestion(record.source_id, reopened)
      assert {:ok, nil, ^reopened} = Backend.get_node(node.id, reopened)
    end
  end

  test "graph and ingestion commits roll back nodes, links, metadata and receipts on relabeling",
       %{state: state} do
    node = %Semantic{id: "protected", proposition: "private", confidence: 1.0}
    metadata = NodeMetadata.new(audience: :repo, custom: %{"original" => true})

    original =
      Changeset.new()
      |> Changeset.add_node(node)
      |> Changeset.put_metadata(node.id, metadata)

    assert {:ok, ^state} = Backend.apply_changeset(original, state)

    addition = %Semantic{id: "rolled-back", proposition: "new", confidence: 1.0}

    changeset =
      Changeset.new()
      |> Changeset.add_node(addition)
      |> Changeset.add_link(node.id, addition.id, :sibling)
      |> Changeset.put_metadata(node.id, %{metadata | audience: [{"org", "private"}]})

    record = %{
      source_id: "rejected",
      audience: [{"org", "private"}],
      payload_digest: <<1, 2, 3>>,
      fingerprint_version: 1,
      receipt: %IngestionReceipt{
        source_id: "rejected",
        node_ids: [addition.id],
        stored_at: DateTime.utc_now()
      }
    }

    for operation <- [
          fn -> Backend.apply_changeset(changeset, state) end,
          fn -> Backend.commit_ingestion(record, changeset, state) end
        ] do
      assert {:error, %AccessError{reason: :immutable_audience}} = operation.()
      assert {:ok, nil, ^state} = Backend.get_node(addition.id, state)
      assert {:ok, stored_node, ^state} = Backend.get_node(node.id, state)
      assert stored_node.links.sibling == MapSet.new()
      assert {:ok, stored, ^state} = Backend.get_metadata([node.id], state)
      assert stored[node.id] == metadata
      assert {:ok, nil, ^state} = Backend.get_ingestion(record.source_id, state)
    end
  end

  test "metadata batches reject audience changes and removals without partial updates", %{
    state: state
  } do
    protected = %Semantic{id: "protected", proposition: "private", confidence: 1.0}
    legacy = %Semantic{id: "legacy", proposition: "unclassified", confidence: 1.0}
    metadata = NodeMetadata.new(audience: [{"org", "private"}], custom: %{"ticket" => 42})
    legacy_metadata = NodeMetadata.new()

    changeset =
      Changeset.new()
      |> Changeset.add_node(protected)
      |> Changeset.add_node(legacy)
      |> Changeset.put_metadata(protected.id, metadata)
      |> Changeset.put_metadata(legacy.id, legacy_metadata)

    assert {:ok, ^state} = Backend.apply_changeset(changeset, state)

    for audience <- [:repo, nil, [{"org", "different"}]] do
      assert {:error, %AccessError{reason: :immutable_audience}} =
               Backend.update_metadata(
                 %{
                   protected.id => %{metadata | audience: audience},
                   legacy.id => %{legacy_metadata | audience: :repo, custom: %{"changed" => true}}
                 },
                 state
               )

      assert {:ok, stored, ^state} = Backend.get_metadata([protected.id, legacy.id], state)
      assert stored == %{protected.id => metadata, legacy.id => legacy_metadata}
    end

    classified = %{legacy_metadata | audience: :repo}
    assert {:ok, ^state} = Backend.update_metadata(%{legacy.id => classified}, state)
    assert {:ok, stored, ^state} = Backend.get_metadata([legacy.id], state)
    assert stored[legacy.id] == classified
  end

  test "audiences and caller metadata survive graph persistence and usage updates", %{
    state: state
  } do
    custom = %{
      "ticket" => "PROJ-42",
      "details" => %{"labels" => ["important"], "attempt" => 42, "resolved" => true}
    }

    for {audience, index} <- Enum.with_index([nil, :repo, [{"org", "private"}]]) do
      node = %Semantic{id: "metadata-#{index}", proposition: "fact", confidence: 1.0}
      metadata = NodeMetadata.new(audience: audience, custom: custom)

      changeset =
        Changeset.new()
        |> Changeset.add_node(node)
        |> Changeset.put_metadata(node.id, metadata)

      assert {:ok, ^state} = Backend.apply_changeset(changeset, state)
      assert {:ok, stored, ^state} = Backend.get_metadata([node.id], state)
      assert stored[node.id] == metadata

      updated = metadata |> NodeMetadata.record_access() |> NodeMetadata.update_reward(0.5)
      assert {:ok, ^state} = Backend.update_metadata(%{node.id => updated}, state)
      assert {:ok, stored, ^state} = Backend.get_metadata([node.id], state)
      assert stored[node.id] == updated
    end
  end
end
