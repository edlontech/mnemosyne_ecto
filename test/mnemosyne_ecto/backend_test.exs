defmodule MnemosyneEcto.BackendTest do
  use MnemosyneEcto.DataCase, async: false, parameterize: MnemosyneEcto.DataCase.repos()

  alias Mnemosyne.Errors.Framework.StorageError
  alias Mnemosyne.Errors.Invalid.IngestionError
  alias Mnemosyne.Graph.Changeset
  alias Mnemosyne.Graph.Edge
  alias Mnemosyne.Graph.Node.Episodic
  alias Mnemosyne.Graph.Node.Semantic
  alias Mnemosyne.Graph.Node.Tag
  alias Mnemosyne.IngestionReceipt
  alias Mnemosyne.NodeMetadata
  alias MnemosyneEcto.Backend

  @tenant_id "test-tenant"
  @repo_id "test-repo"
  @embedding [0.1, 0.2, 0.3]
  @created_at ~U[2025-01-01 00:00:00.000000Z]

  defp make_semantic(id, opts \\ []) do
    %Semantic{
      id: id,
      proposition: Keyword.get(opts, :proposition, "fact #{id}"),
      confidence: Keyword.get(opts, :confidence, 0.9),
      embedding: Keyword.get(opts, :embedding, @embedding),
      links: Keyword.get(opts, :links, Edge.empty_links()),
      created_at: Keyword.get(opts, :created_at, @created_at)
    }
  end

  defp make_episodic(id, opts \\ []) do
    %Episodic{
      id: id,
      observation: Keyword.get(opts, :observation, "saw something"),
      action: Keyword.get(opts, :action, "did something"),
      state: Keyword.get(opts, :state, "neutral"),
      subgoal: Keyword.get(opts, :subgoal, "learn"),
      reward: Keyword.get(opts, :reward, 1.0),
      trajectory_id: Keyword.get(opts, :trajectory_id, "traj-1"),
      embedding: Keyword.get(opts, :embedding, @embedding),
      links: Keyword.get(opts, :links, Edge.empty_links()),
      created_at: Keyword.get(opts, :created_at, @created_at)
    }
  end

  defp make_tag(id, opts \\ []) do
    %Tag{
      id: id,
      label: Keyword.get(opts, :label, "tag-#{id}"),
      embedding: Keyword.get(opts, :embedding, @embedding),
      links: Keyword.get(opts, :links, Edge.empty_links()),
      created_at: Keyword.get(opts, :created_at, @created_at)
    }
  end

  defp ingestion_record(source_id, node_ids, opts \\ []) do
    %{
      source_id: source_id,
      payload_digest: Keyword.get(opts, :payload_digest, <<0, 255, 42>>),
      fingerprint_version: Keyword.get(opts, :fingerprint_version, 1),
      receipt: %IngestionReceipt{
        source_id: source_id,
        node_ids: node_ids,
        stored_at: Keyword.get(opts, :stored_at, ~U[2026-08-26 12:34:56.123456Z])
      }
    }
  end

  describe "init/1" do
    test "succeeds with valid opts", %{repo: repo} do
      assert {:ok, state} =
               Backend.init(
                 repo: repo,
                 tenant_id: @tenant_id,
                 repo_id: @repo_id
               )

      assert state.repo == repo
      assert state.tenant_id == @tenant_id
      assert state.repo_id == @repo_id
      assert state.prefix == "mnemosyne_"
    end

    test "defaults tenant_id to \"default\"", %{repo: repo} do
      assert {:ok, state} =
               Backend.init(
                 repo: repo,
                 repo_id: @repo_id
               )

      assert state.tenant_id == "default"
    end

    test "accepts custom prefix", %{repo: repo} do
      assert {:ok, state} =
               Backend.init(
                 repo: repo,
                 tenant_id: @tenant_id,
                 repo_id: @repo_id,
                 prefix: "custom_"
               )

      assert state.prefix == "custom_"
    end

    test "fails when repo is missing" do
      assert {:error, _} = Backend.init(repo_id: @repo_id)
    end

    test "fails when repo_id is missing", %{repo: repo} do
      assert {:error, _} = Backend.init(repo: repo)
    end
  end

  describe "get_ingestion/2" do
    test "returns nil with unchanged state when the scoped source is missing", %{state: state} do
      assert {:ok, nil, ^state} = Backend.get_ingestion("missing-source", state)
    end

    test "normalizes database exceptions", %{state: state} do
      missing_table_state = %{state | prefix: "missing_"}

      assert {:error, %StorageError{operation: :get_ingestion}} =
               Backend.get_ingestion("source", missing_table_state)
    end
  end

  describe "commit_ingestion/3" do
    test "atomically stores graph changes and returns the durable receipt", %{state: state} do
      semantic = make_semantic("ingestion-semantic")
      tag = make_tag("ingestion-tag")
      metadata = NodeMetadata.new(access_count: 2, created_at: @created_at)

      changeset = %Changeset{
        additions: [semantic, tag],
        links: [{semantic.id, tag.id, :membership}],
        metadata: %{semantic.id => metadata}
      }

      record = ingestion_record("source-1", [tag.id, semantic.id])
      receipt = record.receipt

      assert {:ok, :inserted, ^receipt, ^state} =
               Backend.commit_ingestion(record, changeset, state)

      assert {:ok, ^record, ^state} = Backend.get_ingestion(record.source_id, state)
      assert {:ok, %Semantic{links: links}, ^state} = Backend.get_node(semantic.id, state)
      assert MapSet.member?(links.membership, tag.id)
      assert {:ok, stored_metadata, ^state} = Backend.get_metadata([semantic.id], state)
      assert stored_metadata == %{semantic.id => metadata}
    end

    test "equal retry returns the original receipt and ignores supplied graph", %{state: state} do
      winner = make_semantic("winner-node")
      original = ingestion_record("equal-source", [winner.id])
      winner_changeset = %Changeset{additions: [winner], links: [], metadata: %{}}

      assert {:ok, :inserted, original_receipt, ^state} =
               Backend.commit_ingestion(original, winner_changeset, state)

      loser = make_semantic("loser-node")

      supplied =
        ingestion_record("equal-source", [loser.id], stored_at: ~U[2026-08-26 13:00:00.654321Z])

      loser_metadata = NodeMetadata.new(access_count: 99, created_at: @created_at)

      loser_changeset = %Changeset{
        additions: [loser],
        links: [{winner.id, loser.id, :membership}],
        metadata: %{loser.id => loser_metadata}
      }

      assert {:ok, :existing, ^original_receipt, ^state} =
               Backend.commit_ingestion(supplied, loser_changeset, state)

      assert {:ok, nil, ^state} = Backend.get_node(loser.id, state)
      assert {:ok, %{}, ^state} = Backend.get_metadata([loser.id], state)
      assert {:ok, %Semantic{links: links}, ^state} = Backend.get_node(winner.id, state)
      refute MapSet.member?(links.membership, loser.id)
    end

    test "digest and fingerprint mismatches return exact source conflicts", %{state: state} do
      original = ingestion_record("conflict-source", [])
      empty_changeset = %Changeset{additions: [], links: [], metadata: %{}}

      assert {:ok, :inserted, _receipt, ^state} =
               Backend.commit_ingestion(original, empty_changeset, state)

      conflicts = [
        ingestion_record("conflict-source", ["digest-loser"], payload_digest: <<1, 2, 3>>),
        ingestion_record("conflict-source", ["version-loser"], fingerprint_version: 2)
      ]

      Enum.each(conflicts, fn conflicting ->
        [loser_id] = conflicting.receipt.node_ids

        loser_changeset = %Changeset{
          additions: [make_semantic(loser_id)],
          links: [],
          metadata: %{}
        }

        assert {:error, %IngestionError{source_id: "conflict-source", reason: :source_conflict}} =
                 Backend.commit_ingestion(conflicting, loser_changeset, state)

        assert {:ok, nil, ^state} = Backend.get_node(loser_id, state)
      end)
    end

    test "graph failure rolls back the provisional record and every mutation", %{state: state} do
      existing = make_semantic("duplicate-node", proposition: "original")
      seed_changeset = %Changeset{additions: [existing], links: [], metadata: %{}}
      assert {:ok, ^state} = Backend.apply_changeset(seed_changeset, state)

      leaked = make_tag("rolled-back-node")
      duplicate = make_semantic(existing.id, proposition: "replacement")
      leaked_metadata = NodeMetadata.new(access_count: 5, created_at: @created_at)

      failing_changeset = %Changeset{
        additions: [leaked, duplicate],
        links: [{existing.id, leaked.id, :membership}],
        metadata: %{leaked.id => leaked_metadata}
      }

      record = ingestion_record("rolled-back-source", [leaked.id, duplicate.id])

      assert {:error, %StorageError{operation: :commit_ingestion}} =
               Backend.commit_ingestion(record, failing_changeset, state)

      assert {:ok, nil, ^state} = Backend.get_ingestion(record.source_id, state)
      assert {:ok, nil, ^state} = Backend.get_node(leaked.id, state)
      assert {:ok, %{}, ^state} = Backend.get_metadata([leaked.id], state)

      assert {:ok, %Semantic{proposition: "original", links: links}, ^state} =
               Backend.get_node(existing.id, state)

      refute MapSet.member?(links.membership, leaked.id)
    end

    test "a fresh backend state reads the exact durable record", %{state: state} do
      record = ingestion_record("restart-source", ["historical-2", "historical-1"])
      empty_changeset = %Changeset{additions: [], links: [], metadata: %{}}

      assert {:ok, :inserted, _receipt, ^state} =
               Backend.commit_ingestion(record, empty_changeset, state)

      assert {:ok, restarted_state} =
               Backend.init(
                 repo: state.repo,
                 tenant_id: state.tenant_id,
                 repo_id: state.repo_id,
                 prefix: state.prefix
               )

      assert {:ok, ^record, ^restarted_state} =
               Backend.get_ingestion(record.source_id, restarted_state)
    end

    test "receipt survives graph deletion and equal retry does not recreate nodes", %{
      state: state
    } do
      node = make_semantic("deleted-ingestion-node")
      original = ingestion_record("deleted-source", [node.id])
      changeset = %Changeset{additions: [node], links: [], metadata: %{}}

      assert {:ok, :inserted, original_receipt, ^state} =
               Backend.commit_ingestion(original, changeset, state)

      assert {:ok, ^state} = Backend.delete_nodes([node.id], state)
      assert {:ok, nil, ^state} = Backend.get_node(node.id, state)

      retry_record =
        ingestion_record("deleted-source", ["different-receipt-node"],
          stored_at: ~U[2026-08-27 01:02:03.000004Z]
        )

      retry_changeset = %Changeset{additions: [node], links: [], metadata: %{}}

      assert {:ok, :existing, ^original_receipt, ^state} =
               Backend.commit_ingestion(retry_record, retry_changeset, state)

      assert {:ok, ^original, ^state} = Backend.get_ingestion(original.source_id, state)
      assert {:ok, nil, ^state} = Backend.get_node(node.id, state)
    end

    test "same source ID commits independently across tenants and repositories", %{state: state} do
      states = [
        state,
        %{state | tenant_id: "other-tenant"},
        %{state | repo_id: "other-repo"}
      ]

      records =
        Enum.with_index(states, 1)
        |> Enum.map(fn {scoped_state, index} ->
          node = make_semantic("scoped-node-#{index}")

          record =
            ingestion_record("shared-source", [node.id],
              payload_digest: <<index>>,
              fingerprint_version: index
            )

          changeset = %Changeset{additions: [node], links: [], metadata: %{}}

          assert {:ok, :inserted, _receipt, ^scoped_state} =
                   Backend.commit_ingestion(record, changeset, scoped_state)

          {scoped_state, record}
        end)

      Enum.each(records, fn {scoped_state, record} ->
        assert {:ok, ^record, ^scoped_state} =
                 Backend.get_ingestion("shared-source", scoped_state)
      end)
    end
  end

  describe "apply_changeset/2 + get_node/2" do
    test "inserts nodes and retrieves them", %{state: state} do
      node = make_semantic("sem-1")

      changeset = %Changeset{additions: [node], links: [], metadata: %{}}
      assert {:ok, state} = Backend.apply_changeset(changeset, state)

      assert {:ok, %Semantic{id: "sem-1", proposition: "fact sem-1"}, _state} =
               Backend.get_node("sem-1", state)
    end

    test "returns nil for nonexistent node", %{state: state} do
      assert {:ok, nil, _state} = Backend.get_node("nonexistent", state)
    end

    test "inserts multiple node types", %{state: state} do
      sem = make_semantic("sem-1")
      epi = make_episodic("epi-1")

      changeset = %Changeset{additions: [sem, epi], links: [], metadata: %{}}
      assert {:ok, state} = Backend.apply_changeset(changeset, state)

      assert {:ok, %Semantic{}, _} = Backend.get_node("sem-1", state)
      assert {:ok, %Episodic{}, _} = Backend.get_node("epi-1", state)
    end
  end

  describe "apply_changeset/2 links" do
    test "creates bidirectional links", %{state: state} do
      sem = make_semantic("sem-1")
      tag = make_tag("tag-1")

      changeset = %Changeset{
        additions: [sem, tag],
        links: [{"sem-1", "tag-1", :membership}],
        metadata: %{}
      }

      assert {:ok, state} = Backend.apply_changeset(changeset, state)

      {:ok, sem_node, _} = Backend.get_node("sem-1", state)
      {:ok, tag_node, _} = Backend.get_node("tag-1", state)

      assert MapSet.member?(sem_node.links.membership, "tag-1")
      assert MapSet.member?(tag_node.links.membership, "sem-1")
    end

    test "preserves existing links when adding new ones", %{state: state} do
      sem = make_semantic("sem-1")
      tag1 = make_tag("tag-1")
      tag2 = make_tag("tag-2")

      cs1 = %Changeset{
        additions: [sem, tag1],
        links: [{"sem-1", "tag-1", :membership}],
        metadata: %{}
      }

      assert {:ok, state} = Backend.apply_changeset(cs1, state)

      cs2 = %Changeset{
        additions: [tag2],
        links: [{"sem-1", "tag-2", :membership}],
        metadata: %{}
      }

      assert {:ok, state} = Backend.apply_changeset(cs2, state)

      {:ok, sem_node, _} = Backend.get_node("sem-1", state)
      assert MapSet.member?(sem_node.links.membership, "tag-1")
      assert MapSet.member?(sem_node.links.membership, "tag-2")
    end

    test "handles multiple edge types", %{state: state} do
      sem1 = make_semantic("sem-1")
      sem2 = make_semantic("sem-2")
      tag = make_tag("tag-1")

      changeset = %Changeset{
        additions: [sem1, sem2, tag],
        links: [
          {"sem-1", "tag-1", :membership},
          {"sem-1", "sem-2", :hierarchical}
        ],
        metadata: %{}
      }

      assert {:ok, state} = Backend.apply_changeset(changeset, state)

      {:ok, sem_node, _} = Backend.get_node("sem-1", state)
      assert MapSet.member?(sem_node.links.membership, "tag-1")
      assert MapSet.member?(sem_node.links.hierarchical, "sem-2")
    end
  end

  describe "apply_changeset/2 metadata" do
    test "upserts metadata", %{state: state} do
      sem = make_semantic("sem-1")

      meta = %NodeMetadata{
        access_count: 5,
        last_accessed_at: ~U[2025-06-01 12:00:00.000000Z],
        created_at: @created_at,
        cumulative_reward: 1.5,
        reward_count: 3
      }

      changeset = %Changeset{
        additions: [sem],
        links: [],
        metadata: %{"sem-1" => meta}
      }

      assert {:ok, state} = Backend.apply_changeset(changeset, state)

      {:ok, result, _} = Backend.get_metadata(["sem-1"], state)
      assert %NodeMetadata{access_count: 5, cumulative_reward: 1.5} = result["sem-1"]
    end
  end

  describe "delete_nodes/2" do
    test "removes nodes and their metadata", %{state: state} do
      sem = make_semantic("sem-1")

      meta = NodeMetadata.new(created_at: @created_at)

      cs = %Changeset{
        additions: [sem],
        links: [],
        metadata: %{"sem-1" => meta}
      }

      {:ok, state} = Backend.apply_changeset(cs, state)
      assert {:ok, state} = Backend.delete_nodes(["sem-1"], state)

      assert {:ok, nil, _} = Backend.get_node("sem-1", state)
      assert {:ok, empty, _} = Backend.get_metadata(["sem-1"], state)
      assert empty == %{}
    end

    test "cleans stale links from remaining nodes", %{state: state} do
      sem = make_semantic("sem-1")
      tag = make_tag("tag-1")

      cs = %Changeset{
        additions: [sem, tag],
        links: [{"sem-1", "tag-1", :membership}],
        metadata: %{}
      }

      {:ok, state} = Backend.apply_changeset(cs, state)
      assert {:ok, state} = Backend.delete_nodes(["tag-1"], state)

      {:ok, sem_node, _} = Backend.get_node("sem-1", state)
      refute MapSet.member?(sem_node.links.membership, "tag-1")
    end
  end

  describe "find_candidates/6" do
    test "returns scored nodes ordered by relevance", %{state: state} do
      close_node = make_semantic("close", embedding: [0.9, 0.1, 0.0])
      far_node = make_semantic("far", embedding: [0.0, 0.0, 1.0])

      cs = %Changeset{additions: [close_node, far_node], links: [], metadata: %{}}
      {:ok, state} = Backend.apply_changeset(cs, state)

      query_embedding = [1.0, 0.0, 0.0]
      vf_config = %{module: Mnemosyne.ValueFunction.Default, params: %{}}

      assert {:ok, candidates, _state} =
               Backend.find_candidates([:semantic], query_embedding, [], vf_config, [], state)

      assert [{first_node, first_score} | _] = candidates
      assert %Semantic{} = first_node
      assert is_float(first_score)
      assert first_score > 0.0
    end

    test "respects top_k parameter", %{state: state} do
      nodes =
        for i <- 1..5 do
          make_semantic("sem-#{i}", embedding: [0.1 * i, 0.2 * i, 0.3 * i])
        end

      cs = %Changeset{additions: nodes, links: [], metadata: %{}}
      {:ok, state} = Backend.apply_changeset(cs, state)

      query_embedding = [0.5, 0.5, 0.5]

      vf_config = %{
        module: Mnemosyne.ValueFunction.Default,
        params: %{semantic: %{top_k: 2}}
      }

      assert {:ok, candidates, _} =
               Backend.find_candidates([:semantic], query_embedding, [], vf_config, [], state)

      assert length(candidates) <= 2
    end

    test "respects threshold parameter", %{state: state} do
      node = make_semantic("sem-1", embedding: [1.0, 0.0, 0.0])

      cs = %Changeset{additions: [node], links: [], metadata: %{}}
      {:ok, state} = Backend.apply_changeset(cs, state)

      query_embedding = [0.0, 0.0, 1.0]

      vf_config = %{
        module: Mnemosyne.ValueFunction.Default,
        params: %{semantic: %{threshold: 0.99}}
      }

      assert {:ok, candidates, _} =
               Backend.find_candidates([:semantic], query_embedding, [], vf_config, [], state)

      assert candidates == []
    end

    test "handles tag embeddings in relevance", %{state: state} do
      node = make_semantic("sem-1", embedding: [1.0, 0.0, 0.0])

      cs = %Changeset{additions: [node], links: [], metadata: %{}}
      {:ok, state} = Backend.apply_changeset(cs, state)

      query_embedding = [0.0, 0.0, 1.0]
      tag_embedding = [1.0, 0.0, 0.0]

      vf_config = %{module: Mnemosyne.ValueFunction.Default, params: %{}}

      assert {:ok, candidates, _} =
               Backend.find_candidates(
                 [:semantic],
                 query_embedding,
                 [tag_embedding],
                 vf_config,
                 [],
                 state
               )

      assert [{_node, score}] = candidates
      assert score > 0.0
    end

    test "deduplicates across types", %{state: state} do
      sem = make_semantic("dual-1", embedding: [0.5, 0.5, 0.0])

      cs = %Changeset{additions: [sem], links: [], metadata: %{}}
      {:ok, state} = Backend.apply_changeset(cs, state)

      query_embedding = [0.5, 0.5, 0.0]
      vf_config = %{module: Mnemosyne.ValueFunction.Default, params: %{}}

      assert {:ok, candidates, _} =
               Backend.find_candidates(
                 [:semantic, :semantic],
                 query_embedding,
                 [],
                 vf_config,
                 [],
                 state
               )

      ids = Enum.map(candidates, fn {node, _} -> node.id end)
      assert ids == Enum.uniq(ids)
    end
  end

  describe "get_linked_nodes/3" do
    test "batch fetches nodes by IDs", %{state: state} do
      sem = make_semantic("sem-1")
      tag = make_tag("tag-1")

      cs = %Changeset{additions: [sem, tag], links: [], metadata: %{}}
      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, nodes, _} = Backend.get_linked_nodes(["sem-1", "tag-1"], nil, state)
      ids = Enum.map(nodes, & &1.id) |> Enum.sort()
      assert ids == ["sem-1", "tag-1"]
    end

    test "deduplicates results", %{state: state} do
      sem = make_semantic("sem-1")

      cs = %Changeset{additions: [sem], links: [], metadata: %{}}
      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, nodes, _} = Backend.get_linked_nodes(["sem-1", "sem-1"], nil, state)
      assert length(nodes) == 1
    end

    test "ignores nonexistent IDs", %{state: state} do
      assert {:ok, [], _} = Backend.get_linked_nodes(["nonexistent"], nil, state)
    end
  end

  describe "get_nodes_by_type/2" do
    test "returns nodes of requested types", %{state: state} do
      sem = make_semantic("sem-1")
      epi = make_episodic("epi-1")
      tag = make_tag("tag-1")

      cs = %Changeset{additions: [sem, epi, tag], links: [], metadata: %{}}
      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, nodes, _} = Backend.get_nodes_by_type([:semantic], state)
      assert [%Semantic{id: "sem-1"}] = nodes
    end

    test "returns multiple types", %{state: state} do
      sem = make_semantic("sem-1")
      epi = make_episodic("epi-1")

      cs = %Changeset{additions: [sem, epi], links: [], metadata: %{}}
      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, nodes, _} = Backend.get_nodes_by_type([:semantic, :episodic], state)
      assert length(nodes) == 2
    end
  end

  describe "metadata CRUD" do
    setup %{state: state} do
      node = make_semantic("node-1")
      cs = %Changeset{additions: [node], links: [], metadata: %{}}
      {:ok, state} = Backend.apply_changeset(cs, state)
      %{state: state}
    end

    test "update_metadata upserts entries", %{state: state} do
      meta = %NodeMetadata{
        access_count: 10,
        last_accessed_at: ~U[2025-06-01 12:00:00.000000Z],
        created_at: @created_at,
        cumulative_reward: 2.0,
        reward_count: 4
      }

      assert {:ok, state} = Backend.update_metadata(%{"node-1" => meta}, state)

      {:ok, result, _} = Backend.get_metadata(["node-1"], state)
      fetched = result["node-1"]
      assert fetched.access_count == 10
      assert fetched.cumulative_reward == 2.0
      assert fetched.reward_count == 4
    end

    test "update_metadata overwrites existing entries", %{state: state} do
      meta1 = NodeMetadata.new(access_count: 1, created_at: @created_at)
      {:ok, state} = Backend.update_metadata(%{"node-1" => meta1}, state)

      meta2 = NodeMetadata.new(access_count: 99, created_at: @created_at)
      {:ok, state} = Backend.update_metadata(%{"node-1" => meta2}, state)

      {:ok, result, _} = Backend.get_metadata(["node-1"], state)
      assert result["node-1"].access_count == 99
    end

    test "get_metadata returns empty map for unknown IDs", %{state: state} do
      assert {:ok, %{}, _} = Backend.get_metadata(["unknown"], state)
    end

    test "delete_metadata removes entries", %{state: state} do
      meta = NodeMetadata.new(created_at: @created_at)
      {:ok, state} = Backend.update_metadata(%{"node-1" => meta}, state)
      assert {:ok, state} = Backend.delete_metadata(["node-1"], state)

      {:ok, result, _} = Backend.get_metadata(["node-1"], state)
      assert result == %{}
    end
  end
end
