defmodule MnemosyneEcto.IngestionSerializer do
  @moduledoc """
  Converts Mnemosyne ingestion records to and from durable database rows.
  """

  alias Mnemosyne.IngestionReceipt
  alias MnemosyneEcto.Schema.Ingestion

  @doc "Converts an ingestion record into a scoped row suitable for `Repo.insert_all/3`."
  @spec to_row(Mnemosyne.GraphBackend.ingestion_record(), String.t(), String.t()) :: map()
  def to_row(record, tenant_id, repo_id) do
    row = %{
      tenant_id: tenant_id,
      repo_id: repo_id,
      source_id: record.source_id,
      payload_digest: record.payload_digest,
      fingerprint_version: record.fingerprint_version,
      node_ids: record.receipt.node_ids,
      stored_at: record.receipt.stored_at
    }

    case Map.get(record, :audience) do
      nil -> row
      audience -> Map.put(row, :audience, :erlang.term_to_binary(audience, [:deterministic]))
    end
  end

  @doc "Reconstructs a Mnemosyne ingestion record from a durable database row."
  @spec from_row(Ingestion.t()) :: Mnemosyne.GraphBackend.ingestion_record()
  def from_row(row) do
    record = %{
      source_id: row.source_id,
      payload_digest: row.payload_digest,
      fingerprint_version: row.fingerprint_version,
      receipt: %IngestionReceipt{
        source_id: row.source_id,
        node_ids: row.node_ids,
        stored_at: row.stored_at
      }
    }

    case row.audience do
      nil -> record
      audience -> Map.put(record, :audience, :erlang.binary_to_term(audience, [:safe]))
    end
  end
end
