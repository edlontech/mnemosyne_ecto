defmodule MnemosyneEcto.TelemetryTest do
  use MnemosyneEcto.DataCase, async: false, parameterize: MnemosyneEcto.DataCase.repos()

  alias Mnemosyne.Errors.Framework.StorageError
  alias Mnemosyne.Errors.Invalid.IngestionError
  alias Mnemosyne.Graph.Changeset
  alias Mnemosyne.Graph.Edge
  alias Mnemosyne.Graph.Node.Semantic
  alias Mnemosyne.IngestionReceipt
  alias MnemosyneEcto.Backend
  alias MnemosyneEcto.Telemetry

  test "get_ingestion emits correlated missing telemetry", %{state: state} do
    attach_events([
      [:mnemosyne_ecto, :get_ingestion, :start],
      [:mnemosyne_ecto, :get_ingestion, :stop]
    ])

    assert {:ok, nil, ^state} = Backend.get_ingestion("missing-source", state)

    assert_receive {:telemetry, [:mnemosyne_ecto, :get_ingestion, :start], start_measurements,
                    start_metadata}

    assert %{system_time: system_time, monotonic_time: monotonic_time} = start_measurements
    assert is_integer(system_time)
    assert is_integer(monotonic_time)
    assert_correlation(start_metadata, state, "missing-source")

    assert_receive {:telemetry, [:mnemosyne_ecto, :get_ingestion, :stop], stop_measurements,
                    stop_metadata}

    assert %{duration: duration, record_count: 0} = stop_measurements
    assert is_integer(duration)
    assert %{status: :missing} = stop_metadata
    assert_correlation(stop_metadata, state, "missing-source")
  end

  test "get_ingestion emits found telemetry without private receipt data", %{state: state} do
    record = ingestion_record("found-source", ["private-node-id"])
    changeset = %Changeset{additions: [], links: [], metadata: %{}}
    assert {:ok, :inserted, _receipt, ^state} = Backend.commit_ingestion(record, changeset, state)

    attach_events([
      [:mnemosyne_ecto, :get_ingestion, :start],
      [:mnemosyne_ecto, :get_ingestion, :stop]
    ])

    assert {:ok, ^record, ^state} = Backend.get_ingestion(record.source_id, state)

    assert_receive {:telemetry, [:mnemosyne_ecto, :get_ingestion, :start], start_measurements,
                    start_metadata}

    assert_correlation(start_metadata, state, record.source_id)
    refute_private_data(start_measurements, start_metadata, record)

    assert_receive {:telemetry, [:mnemosyne_ecto, :get_ingestion, :stop], stop_measurements,
                    stop_metadata}

    assert %{record_count: 1} = stop_measurements
    assert %{status: :found} = stop_metadata
    assert_correlation(stop_metadata, state, record.source_id)
    refute_private_data(stop_measurements, stop_metadata, record)
  end

  test "get_ingestion emits an error stop for normalized storage failures", %{state: state} do
    source_id = "storage-error-source"
    missing_table_state = %{state | prefix: "missing_"}

    attach_events([
      [:mnemosyne_ecto, :get_ingestion, :start],
      [:mnemosyne_ecto, :get_ingestion, :stop],
      [:mnemosyne_ecto, :get_ingestion, :exception]
    ])

    assert {:error, _storage_error} = Backend.get_ingestion(source_id, missing_table_state)

    assert_receive {:telemetry, [:mnemosyne_ecto, :get_ingestion, :start], _, start_metadata}
    assert_correlation(start_metadata, state, source_id)

    assert_receive {:telemetry, [:mnemosyne_ecto, :get_ingestion, :stop], stop_measurements,
                    stop_metadata}

    assert %{record_count: 0} = stop_measurements
    assert %{status: :error} = stop_metadata
    assert_correlation(stop_metadata, state, source_id)
    refute_private_data(stop_measurements, stop_metadata)
    refute_receive {:telemetry, [:mnemosyne_ecto, :get_ingestion, :exception], _, _}
  end

  test "commit_ingestion emits inserted counts and private-safe correlation", %{state: state} do
    nodes = [semantic_node("inserted-private-node-1"), semantic_node("inserted-private-node-2")]
    record = ingestion_record("inserted-source", Enum.map(nodes, & &1.id))
    changeset = %Changeset{additions: nodes, links: [], metadata: %{}}

    attach_events([
      [:mnemosyne_ecto, :commit_ingestion, :start],
      [:mnemosyne_ecto, :commit_ingestion, :stop]
    ])

    assert {:ok, :inserted, _receipt, ^state} =
             Backend.commit_ingestion(record, changeset, state)

    assert_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :start], start_measurements,
                    start_metadata}

    assert_correlation(start_metadata, state, record.source_id)
    refute_private_data(start_measurements, start_metadata, record)

    assert_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :stop], stop_measurements,
                    stop_metadata}

    assert %{record_inserted: 1, nodes_inserted: 2} = stop_measurements
    assert %{status: :inserted} = stop_metadata
    assert_correlation(stop_metadata, state, record.source_id)
    refute_private_data(stop_measurements, stop_metadata, record)
  end

  test "commit_ingestion emits zero insertion counts for an existing source", %{state: state} do
    record = ingestion_record("existing-source", ["winner-private-node"])
    empty_changeset = %Changeset{additions: [], links: [], metadata: %{}}

    assert {:ok, :inserted, original_receipt, ^state} =
             Backend.commit_ingestion(record, empty_changeset, state)

    losing_node = semantic_node("loser-private-node")
    retry = %{record | receipt: %{record.receipt | node_ids: [losing_node.id]}}
    retry_changeset = %Changeset{additions: [losing_node], links: [], metadata: %{}}

    attach_events([
      [:mnemosyne_ecto, :commit_ingestion, :start],
      [:mnemosyne_ecto, :commit_ingestion, :stop]
    ])

    assert {:ok, :existing, ^original_receipt, ^state} =
             Backend.commit_ingestion(retry, retry_changeset, state)

    assert_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :start], start_measurements,
                    start_metadata}

    assert_correlation(start_metadata, state, record.source_id)
    refute_private_data(start_measurements, start_metadata, retry)

    assert_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :stop], stop_measurements,
                    stop_metadata}

    assert %{record_inserted: 0, nodes_inserted: 0} = stop_measurements
    assert %{status: :existing} = stop_metadata
    assert_correlation(stop_metadata, state, record.source_id)
    refute_private_data(stop_measurements, stop_metadata, retry)
  end

  test "commit_ingestion emits a conflict stop for a returned ingestion conflict", %{state: state} do
    record = ingestion_record("conflict-source", [])
    empty_changeset = %Changeset{additions: [], links: [], metadata: %{}}

    assert {:ok, :inserted, _receipt, ^state} =
             Backend.commit_ingestion(record, empty_changeset, state)

    conflicting =
      ingestion_record(record.source_id, ["conflict-private-node"], payload_digest: <<1>>)

    attach_events([
      [:mnemosyne_ecto, :commit_ingestion, :start],
      [:mnemosyne_ecto, :commit_ingestion, :stop],
      [:mnemosyne_ecto, :commit_ingestion, :exception]
    ])

    assert {:error, %IngestionError{reason: :source_conflict}} =
             Backend.commit_ingestion(conflicting, empty_changeset, state)

    assert_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :start], start_measurements,
                    start_metadata}

    assert_correlation(start_metadata, state, record.source_id)
    refute_private_data(start_measurements, start_metadata, conflicting)

    assert_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :stop], stop_measurements,
                    stop_metadata}

    assert %{record_inserted: 0, nodes_inserted: 0} = stop_measurements
    assert %{status: :conflict} = stop_metadata
    assert_correlation(stop_metadata, state, record.source_id)
    refute_private_data(stop_measurements, stop_metadata, conflicting)
    refute_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :exception], _, _}
  end

  test "commit_ingestion emits an error stop for normalized storage failures", %{state: state} do
    node = semantic_node("duplicate-node")
    seed_changeset = %Changeset{additions: [node], links: [], metadata: %{}}
    assert {:ok, ^state} = Backend.apply_changeset(seed_changeset, state)

    record = ingestion_record("commit-error-source", [node.id])

    attach_events([
      [:mnemosyne_ecto, :commit_ingestion, :start],
      [:mnemosyne_ecto, :commit_ingestion, :stop],
      [:mnemosyne_ecto, :commit_ingestion, :exception]
    ])

    assert {:error, %StorageError{operation: :commit_ingestion}} =
             Backend.commit_ingestion(record, seed_changeset, state)

    assert_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :start], start_measurements,
                    start_metadata}

    assert_correlation(start_metadata, state, record.source_id)
    refute_private_data(start_measurements, start_metadata, record)

    assert_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :stop], stop_measurements,
                    stop_metadata}

    assert %{record_inserted: 0, nodes_inserted: 0} = stop_measurements
    assert %{status: :error} = stop_metadata
    assert_correlation(stop_metadata, state, record.source_id)
    refute_private_data(stop_measurements, stop_metadata, record)
    refute_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :exception], _, _}
  end

  test "span preserves two-tuple stop maps as metadata" do
    attach_events([[:mnemosyne_ecto, :legacy_two_tuple, :stop]])

    assert :result =
             Telemetry.span(:legacy_two_tuple, %{correlation: "start"}, fn ->
               {:result, %{candidate_count: 7, correlation: "stop"}}
             end)

    assert_receive {:telemetry, [:mnemosyne_ecto, :legacy_two_tuple, :stop], measurements,
                    metadata}

    refute Map.has_key?(measurements, :candidate_count)
    assert %{candidate_count: 7, correlation: "stop"} = metadata
  end

  test "span emits an exception event and re-raises uncaught exceptions", %{state: state} do
    source_id = "uncaught-source"
    metadata = %{tenant_id: state.tenant_id, repo_id: state.repo_id, source_id: source_id}

    attach_events([
      [:mnemosyne_ecto, :commit_ingestion, :start],
      [:mnemosyne_ecto, :commit_ingestion, :stop],
      [:mnemosyne_ecto, :commit_ingestion, :exception]
    ])

    assert_raise RuntimeError, "uncaught telemetry test", fn ->
      Telemetry.span(:commit_ingestion, metadata, fn ->
        raise "uncaught telemetry test"
      end)
    end

    assert_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :start], _, start_metadata}
    assert_correlation(start_metadata, state, source_id)

    assert_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :exception], measurements,
                    exception_metadata}

    assert %{duration: duration} = measurements
    assert is_integer(duration)

    assert %{kind: :error, reason: %RuntimeError{message: "uncaught telemetry test"}} =
             exception_metadata

    assert_correlation(exception_metadata, state, source_id)
    refute_private_data(measurements, exception_metadata)
    refute_receive {:telemetry, [:mnemosyne_ecto, :commit_ingestion, :stop], _, _}
  end

  @doc false
  def handle_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry, event, measurements, metadata})
  end

  defp attach_events(events) do
    handler_id = {__MODULE__, self(), make_ref()}
    :ok = :telemetry.attach_many(handler_id, events, &__MODULE__.handle_event/4, self())
    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp assert_correlation(metadata, state, source_id) do
    assert metadata.tenant_id == state.tenant_id
    assert metadata.repo_id == state.repo_id
    assert metadata.source_id == source_id
  end

  defp ingestion_record(source_id, node_ids, opts \\ []) do
    %{
      source_id: source_id,
      payload_digest: Keyword.get(opts, :payload_digest, <<0, 255, 42>>),
      fingerprint_version: Keyword.get(opts, :fingerprint_version, 1),
      receipt: %IngestionReceipt{
        source_id: source_id,
        node_ids: node_ids,
        stored_at: ~U[2026-08-26 12:34:56.123456Z]
      }
    }
  end

  defp semantic_node(id) do
    %Semantic{
      id: id,
      proposition: "private proposition",
      confidence: 0.9,
      embedding: [0.1, 0.2, 0.3],
      links: Edge.empty_links(),
      created_at: ~U[2026-08-26 12:34:56.123456Z]
    }
  end

  defp refute_private_data(measurements, metadata, record \\ nil) do
    Enum.each([measurements, metadata], fn payload ->
      refute Map.has_key?(payload, :payload_digest)
      refute Map.has_key?(payload, :receipt)
      refute Map.has_key?(payload, :node_ids)

      if record do
        values = Map.values(payload)
        refute record.payload_digest in values
        refute record.receipt in values
        refute record.receipt.node_ids in values
      end
    end)
  end
end
