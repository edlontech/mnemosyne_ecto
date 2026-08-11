defmodule MnemosyneEcto.NodeSerializerTest do
  use ExUnit.Case,
    async: true,
    parameterize: [
      %{adapter: MnemosyneEcto.Adapter.Postgres},
      %{adapter: MnemosyneEcto.Adapter.SQLite}
    ]

  alias MnemosyneEcto.NodeSerializer

  alias Mnemosyne.Graph.Edge
  alias Mnemosyne.Graph.Node.Episodic
  alias Mnemosyne.Graph.Node.Intent
  alias Mnemosyne.Graph.Node.Procedural
  alias Mnemosyne.Graph.Node.Semantic
  alias Mnemosyne.Graph.Node.Source
  alias Mnemosyne.Graph.Node.Subgoal
  alias Mnemosyne.Graph.Node.Tag

  @tenant_id "tenant-1"
  @repo_id "repo-1"
  @embedding [0.5, 0.25, 0.125]
  @created_at ~U[2025-01-01 00:00:00.000000Z]

  defp links_with_data do
    Edge.empty_links()
    |> Map.put(:membership, MapSet.new(["node-a", "node-b"]))
    |> Map.put(:hierarchical, MapSet.new(["node-c"]))
  end

  describe "semantic node round-trip" do
    test "preserves all fields", %{adapter: adapter} do
      node = %Semantic{
        id: "sem-1",
        proposition: "the sky is blue",
        confidence: 0.95,
        embedding: @embedding,
        links: links_with_data(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      result = NodeSerializer.from_row(row, adapter)

      assert row.embedding == adapter.encode_embedding(@embedding)
      assert %Semantic{} = result
      assert result.id == node.id
      assert result.proposition == "the sky is blue"
      assert result.confidence == 0.95
      assert result.embedding == @embedding
      assert result.links == node.links
      assert result.created_at == @created_at
    end
  end

  describe "episodic node round-trip" do
    test "preserves all fields", %{adapter: adapter} do
      node = %Episodic{
        id: "epi-1",
        observation: "saw a cat",
        action: "pet the cat",
        state: "happy",
        subgoal: "interact with animals",
        reward: 1.0,
        trajectory_id: "traj-1",
        embedding: @embedding,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      result = NodeSerializer.from_row(row, adapter)

      assert %Episodic{} = result
      assert result.id == node.id
      assert result.observation == "saw a cat"
      assert result.action == "pet the cat"
      assert result.state == "happy"
      assert result.subgoal == "interact with animals"
      assert result.reward == 1.0
      assert result.trajectory_id == "traj-1"
    end
  end

  describe "procedural node round-trip" do
    test "preserves all fields including nil return_score", %{adapter: adapter} do
      node = %Procedural{
        id: "proc-1",
        instruction: "do the thing",
        condition: "when ready",
        expected_outcome: "thing done",
        return_score: nil,
        embedding: @embedding,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      result = NodeSerializer.from_row(row, adapter)

      assert %Procedural{} = result
      assert result.instruction == "do the thing"
      assert result.condition == "when ready"
      assert result.expected_outcome == "thing done"
      assert result.return_score == nil
    end

    test "preserves non-nil return_score", %{adapter: adapter} do
      node = %Procedural{
        id: "proc-2",
        instruction: "do it",
        condition: "now",
        expected_outcome: "done",
        return_score: 0.75,
        embedding: @embedding,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      result = NodeSerializer.from_row(row, adapter)

      assert result.return_score == 0.75
    end
  end

  describe "subgoal node round-trip" do
    test "preserves fields with nil parent_goal", %{adapter: adapter} do
      node = %Subgoal{
        id: "sg-1",
        description: "learn elixir",
        parent_goal: nil,
        embedding: @embedding,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      result = NodeSerializer.from_row(row, adapter)

      assert %Subgoal{} = result
      assert result.description == "learn elixir"
      assert result.parent_goal == nil
    end

    test "preserves non-nil parent_goal", %{adapter: adapter} do
      node = %Subgoal{
        id: "sg-2",
        description: "learn OTP",
        parent_goal: "learn elixir",
        embedding: @embedding,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      result = NodeSerializer.from_row(row, adapter)

      assert result.parent_goal == "learn elixir"
    end
  end

  describe "source node round-trip" do
    test "preserves fields with nil plain_text", %{adapter: adapter} do
      node = %Source{
        id: "src-1",
        episode_id: "ep-1",
        step_index: 3,
        plain_text: nil,
        embedding: @embedding,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      result = NodeSerializer.from_row(row, adapter)

      assert %Source{} = result
      assert result.episode_id == "ep-1"
      assert result.step_index == 3
      assert result.plain_text == nil
    end

    test "preserves non-nil plain_text", %{adapter: adapter} do
      node = %Source{
        id: "src-2",
        episode_id: "ep-2",
        step_index: 0,
        plain_text: "some text",
        embedding: @embedding,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      result = NodeSerializer.from_row(row, adapter)

      assert result.plain_text == "some text"
    end
  end

  describe "tag node round-trip" do
    test "preserves all fields", %{adapter: adapter} do
      node = %Tag{
        id: "tag-1",
        label: "important",
        embedding: @embedding,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      result = NodeSerializer.from_row(row, adapter)

      assert %Tag{} = result
      assert result.label == "important"
    end
  end

  describe "intent node round-trip" do
    test "preserves all fields", %{adapter: adapter} do
      node = %Intent{
        id: "int-1",
        description: "find food",
        embedding: @embedding,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      result = NodeSerializer.from_row(row, adapter)

      assert %Intent{} = result
      assert result.description == "find food"
    end
  end

  describe "to_row/4" do
    test "includes tenant_id and repo_id", %{adapter: adapter} do
      node = %Tag{
        id: "tag-1",
        label: "x",
        embedding: nil,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, "t-1", "r-1", adapter)

      assert row.tenant_id == "t-1"
      assert row.repo_id == "r-1"
    end

    test "serializes type as string", %{adapter: adapter} do
      node = %Semantic{
        id: "sem-1",
        proposition: "test",
        confidence: 0.5,
        embedding: nil,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)

      assert row.type == "semantic"
    end

    test "serializes data as string-keyed map", %{adapter: adapter} do
      node = %Semantic{
        id: "sem-1",
        proposition: "test",
        confidence: 0.5,
        embedding: nil,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)

      assert row.data == %{"proposition" => "test", "confidence" => 0.5}
    end
  end

  describe "links serialization" do
    test "round-trips links with data", %{adapter: adapter} do
      node = %Tag{
        id: "tag-1",
        label: "x",
        embedding: nil,
        links: links_with_data(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)

      assert is_map(row.links)
      assert row.links.membership == MapSet.new(["node-a", "node-b"])
      assert row.links.hierarchical == MapSet.new(["node-c"])

      result = NodeSerializer.from_row(row, adapter)
      assert result.links == node.links
    end

    test "round-trips empty links", %{adapter: adapter} do
      node = %Tag{
        id: "tag-1",
        label: "x",
        embedding: nil,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      result = NodeSerializer.from_row(row, adapter)

      assert result.links == Edge.empty_links()
    end
  end

  describe "embedding handling" do
    test "nil embedding round-trips", %{adapter: adapter} do
      node = %Tag{
        id: "tag-1",
        label: "x",
        embedding: nil,
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      assert row.embedding == nil

      result = NodeSerializer.from_row(row, adapter)
      assert result.embedding == nil
    end

    test "list embedding round-trips", %{adapter: adapter} do
      node = %Tag{
        id: "tag-1",
        label: "x",
        embedding: [1.0, 2.0, 3.0],
        links: Edge.empty_links(),
        created_at: @created_at
      }

      row = NodeSerializer.to_row(node, @tenant_id, @repo_id, adapter)
      result = NodeSerializer.from_row(row, adapter)

      assert result.embedding == [1.0, 2.0, 3.0]
    end

    test "from_row handles adapter embedding", %{adapter: adapter} do
      row = %{
        id: "tag-1",
        type: "tag",
        data: %{"label" => "x"},
        embedding: adapter.encode_embedding([1.0, 2.0, 3.0]),
        links: %{},
        created_at: @created_at
      }

      result = NodeSerializer.from_row(row, adapter)

      assert result.embedding == [1.0, 2.0, 3.0]
    end
  end

  describe "from_row/2 with string-keyed data" do
    test "handles string-keyed data maps from DB", %{adapter: adapter} do
      row = %{
        id: "sem-1",
        type: "semantic",
        data: %{"proposition" => "hello", "confidence" => 0.8},
        embedding: nil,
        links: %{},
        created_at: @created_at
      }

      result = NodeSerializer.from_row(row, adapter)

      assert %Semantic{} = result
      assert result.proposition == "hello"
      assert result.confidence == 0.8
    end

    test "coerces integer step_index from JSONB", %{adapter: adapter} do
      row = %{
        id: "src-1",
        type: "source",
        data: %{"episode_id" => "ep-1", "step_index" => 5, "plain_text" => nil},
        embedding: nil,
        links: %{},
        created_at: @created_at
      }

      result = NodeSerializer.from_row(row, adapter)

      assert %Source{} = result
      assert result.step_index == 5
    end
  end
end
