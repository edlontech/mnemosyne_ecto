defmodule MnemosyneEcto.Queries.MetadataQueriesTest do
  use MnemosyneEcto.DataCase, async: false, parameterize: MnemosyneEcto.DataCase.repos()

  alias MnemosyneEcto.Queries.MetadataQueries

  setup %{state: state} do
    insert_node(state, %{id: "n1", tenant_id: "t1", repo_id: "r1"})
    insert_node(state, %{id: "n2", tenant_id: "t1", repo_id: "r1"})
    insert_node(%{state | tenant_id: "t2"}, %{id: "n3", tenant_id: "t2", repo_id: "r1"})

    insert_node_metadata(state, %{tenant_id: "t1", node_id: "n1", access_count: 5})
    insert_node_metadata(state, %{tenant_id: "t1", node_id: "n2", access_count: 3})

    insert_node_metadata(%{state | tenant_id: "t2"}, %{
      tenant_id: "t2",
      node_id: "n3",
      access_count: 1
    })

    :ok
  end

  describe "base/1" do
    test "returns metadata scoped to tenant_id", %{state: state, repo: repo} do
      results = state |> MetadataQueries.base() |> repo.all()

      assert length(results) == 2
      assert Enum.all?(results, &(&1.tenant_id == "t1"))
    end

    test "excludes metadata from other tenants", %{state: state, repo: repo} do
      node_ids = state |> MetadataQueries.base() |> repo.all() |> Enum.map(& &1.node_id)

      refute "n3" in node_ids
    end
  end

  describe "by_node_ids/2" do
    test "filters metadata by specific node IDs", %{state: state, repo: repo} do
      results =
        state
        |> MetadataQueries.base()
        |> MetadataQueries.by_node_ids(["n1"])
        |> repo.all()

      assert [%{node_id: "n1"}] = results
    end

    test "returns multiple entries for multiple node IDs", %{state: state, repo: repo} do
      results =
        state
        |> MetadataQueries.base()
        |> MetadataQueries.by_node_ids(["n1", "n2"])
        |> repo.all()

      assert length(results) == 2
    end

    test "returns empty list for non-existent node IDs", %{state: state, repo: repo} do
      results =
        state
        |> MetadataQueries.base()
        |> MetadataQueries.by_node_ids(["nonexistent"])
        |> repo.all()

      assert results == []
    end
  end
end
