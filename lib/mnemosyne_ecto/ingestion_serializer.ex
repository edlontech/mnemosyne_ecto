defmodule MnemosyneEcto.IngestionSerializer do
  @moduledoc """
  Converts Mnemosyne ingestion records to and from durable database rows.
  """

  alias Mnemosyne.IngestionReceipt
  alias MnemosyneEcto.Schema.Ingestion

  @doc "Converts an ingestion record into a scoped row suitable for `Repo.insert_all/3`."
  @spec to_row(Mnemosyne.GraphBackend.ingestion_record(), String.t(), String.t()) :: map()
  def to_row(%{audience: audience} = record, tenant_id, repo_id) when not is_nil(audience) do
    record
    |> base_row(tenant_id, repo_id)
    |> Map.merge(%{audience: :erlang.term_to_binary(audience, [:deterministic])})
  end

  def to_row(record, tenant_id, repo_id), do: base_row(record, tenant_id, repo_id)

  defp base_row(record, tenant_id, repo_id) do
    %{
      tenant_id: tenant_id,
      repo_id: repo_id,
      source_id: record.source_id,
      payload_digest: record.payload_digest,
      fingerprint_version: record.fingerprint_version,
      node_ids: record.receipt.node_ids,
      stored_at: record.receipt.stored_at
    }
  end

  @doc "Reconstructs a Mnemosyne ingestion record from a durable database row."
  @spec from_row(Ingestion.t()) :: Mnemosyne.GraphBackend.ingestion_record()
  def from_row(%Ingestion{audience: nil} = row), do: base_record(row)

  # Decodes terms this module wrote via to_row/3; `:safe` blocks atom creation.
  # sobelow_skip ["Misc.BinToTerm"]
  def from_row(%Ingestion{audience: audience} = row) do
    Map.merge(base_record(row), %{audience: :erlang.binary_to_term(audience, [:safe])})
  end

  defp base_record(row) do
    %{
      source_id: row.source_id,
      payload_digest: row.payload_digest,
      fingerprint_version: row.fingerprint_version,
      receipt: %IngestionReceipt{
        source_id: row.source_id,
        node_ids: row.node_ids,
        stored_at: row.stored_at
      }
    }
  end
end
