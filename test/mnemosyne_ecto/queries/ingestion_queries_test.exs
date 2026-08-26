defmodule MnemosyneEcto.Queries.IngestionQueriesTest do
  use MnemosyneEcto.DataCase, async: false, parameterize: MnemosyneEcto.DataCase.repos()

  alias MnemosyneEcto.Queries.IngestionQueries
  alias MnemosyneEcto.Schema.Ingestion

  describe "source/1" do
    test "uses the configured table prefix" do
      assert {"custom_ingestions", Ingestion} = IngestionQueries.source(%{prefix: "custom_"})
    end
  end

  describe "for_source/2" do
    test "scopes rows by tenant, repository, and source", %{repo: repo, state: state} do
      stored_at = ~U[2026-08-26 12:34:56.123456Z]

      rows = [
        %{tenant_id: "t1", repo_id: "r1", source_id: "source-1"},
        %{tenant_id: "t1", repo_id: "r1", source_id: "source-2"},
        %{tenant_id: "t1", repo_id: "r2", source_id: "source-1"},
        %{tenant_id: "t2", repo_id: "r1", source_id: "source-1"}
      ]

      repo.insert_all(
        IngestionQueries.source(state),
        Enum.map(rows, fn row ->
          Map.merge(row, %{
            payload_digest: <<0, 255>>,
            fingerprint_version: 1,
            node_ids: ["node-1", "node-2"],
            stored_at: stored_at
          })
        end)
      )

      assert [
               %{
                 tenant_id: "t1",
                 repo_id: "r1",
                 source_id: "source-1",
                 node_ids: ["node-1", "node-2"],
                 stored_at: ~U[2026-08-26 12:34:56.123456Z]
               }
             ] = state |> IngestionQueries.for_source("source-1") |> repo.all()
    end
  end
end
