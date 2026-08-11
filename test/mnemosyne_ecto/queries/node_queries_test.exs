defmodule MnemosyneEcto.Queries.NodeQueriesTest do
  use MnemosyneEcto.DataCase, async: false, parameterize: MnemosyneEcto.DataCase.repos()

  alias MnemosyneEcto.Queries.NodeQueries

  setup %{state: state} do
    insert_node(state, %{
      id: "n1",
      type: "semantic",
      data: %{"proposition" => "test", "confidence" => 0.9},
      embedding: [0.1, 0.2, 0.3]
    })

    insert_node(state, %{
      id: "n2",
      type: "episodic",
      data: %{
        "observation" => "obs",
        "action" => "act",
        "state" => "s",
        "subgoal" => "sg",
        "reward" => 1.0,
        "trajectory_id" => "tr1"
      },
      embedding: [0.4, 0.5, 0.6]
    })

    insert_node(%{state | tenant_id: "t2"}, %{
      id: "n3",
      tenant_id: "t2",
      type: "semantic",
      data: %{"proposition" => "other tenant", "confidence" => 0.5},
      embedding: [0.7, 0.8, 0.9]
    })

    :ok
  end

  describe "scoped/1" do
    test "returns only nodes matching tenant_id and repo_id", %{state: state, repo: repo} do
      results = state |> NodeQueries.scoped() |> repo.all()

      assert length(results) == 2
      assert Enum.all?(results, &(&1.tenant_id == "t1"))
      assert Enum.all?(results, &(&1.repo_id == "r1"))
    end

    test "excludes nodes from other tenants", %{state: state, repo: repo} do
      ids = state |> NodeQueries.scoped() |> repo.all() |> Enum.map(& &1.id)

      refute "n3" in ids
    end
  end

  describe "by_types/2" do
    test "filters nodes by type", %{state: state, repo: repo} do
      results =
        state
        |> NodeQueries.scoped()
        |> NodeQueries.by_types([:semantic])
        |> repo.all()

      assert [%{id: "n1", type: "semantic"}] = results
    end

    test "returns multiple types when requested", %{state: state, repo: repo} do
      results =
        state
        |> NodeQueries.scoped()
        |> NodeQueries.by_types([:semantic, :episodic])
        |> repo.all()

      assert length(results) == 2
    end
  end

  describe "by_ids/2" do
    test "filters nodes by specific IDs", %{state: state, repo: repo} do
      results =
        state
        |> NodeQueries.scoped()
        |> NodeQueries.by_ids(["n1"])
        |> repo.all()

      assert [%{id: "n1"}] = results
    end

    test "returns multiple nodes for multiple IDs", %{state: state, repo: repo} do
      results =
        state
        |> NodeQueries.scoped()
        |> NodeQueries.by_ids(["n1", "n2"])
        |> repo.all()

      assert length(results) == 2
    end

    test "ignores IDs not in scope", %{state: state, repo: repo} do
      results =
        state
        |> NodeQueries.scoped()
        |> NodeQueries.by_ids(["n3"])
        |> repo.all()

      assert results == []
    end
  end

  describe "vector_search/4" do
    test "returns nodes ordered by cosine distance", %{state: state, repo: repo} do
      results = state.adapter.vector_search(state, :semantic, [0.1, 0.2, 0.3], 10) |> repo.all()

      assert [%{id: "n1"}] = results
    end

    test "returns nodes ordered by embedding proximity", %{state: state, repo: repo} do
      results = state.adapter.vector_search(state, :semantic, [0.1, 0.2, 0.3], 10) |> repo.all()

      assert [%{id: "n1"}] = results
    end

    test "respects the limit parameter", %{state: state, repo: repo} do
      results = state.adapter.vector_search(state, :episodic, [0.1, 0.2, 0.3], 1) |> repo.all()

      assert length(results) <= 1
    end

    test "filters by type", %{state: state, repo: repo} do
      semantic_results =
        state.adapter.vector_search(state, :semantic, [0.4, 0.5, 0.6], 10) |> repo.all()

      episodic_results =
        state.adapter.vector_search(state, :episodic, [0.4, 0.5, 0.6], 10) |> repo.all()

      assert Enum.all?(semantic_results, &(&1.type == "semantic"))
      assert Enum.all?(episodic_results, &(&1.type == "episodic"))
    end
  end
end
