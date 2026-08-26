defmodule MnemosyneEcto.IngestionSerializerTest do
  use ExUnit.Case, async: true

  alias Mnemosyne.IngestionReceipt
  alias MnemosyneEcto.IngestionSerializer
  alias MnemosyneEcto.Schema.Ingestion

  @stored_at ~U[2026-08-26 12:34:56.123456Z]

  test "converts an ingestion record to a scoped portable row" do
    record = ingestion_record()

    assert IngestionSerializer.to_row(record, "tenant-1", "repo-1") == %{
             tenant_id: "tenant-1",
             repo_id: "repo-1",
             source_id: "source-1",
             payload_digest: <<0, 255, 1, 128, 42>>,
             fingerprint_version: 3,
             node_ids: ["node-2", "node-1"],
             stored_at: @stored_at
           }
  end

  test "reconstructs the exact record and keeps storage scope private" do
    row =
      struct!(Ingestion, %{
        tenant_id: "tenant-1",
        repo_id: "repo-1",
        source_id: "source-1",
        payload_digest: <<0, 255, 1, 128, 42>>,
        fingerprint_version: 3,
        node_ids: ["node-2", "node-1"],
        stored_at: @stored_at
      })

    assert IngestionSerializer.from_row(row) == ingestion_record()
  end

  defp ingestion_record do
    %{
      source_id: "source-1",
      payload_digest: <<0, 255, 1, 128, 42>>,
      fingerprint_version: 3,
      receipt: %IngestionReceipt{
        source_id: "source-1",
        node_ids: ["node-2", "node-1"],
        stored_at: @stored_at
      }
    }
  end
end
