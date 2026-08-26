defmodule MnemosyneEcto.BackendIngestionConcurrencyTest do
  use ExUnit.Case,
    async: false,
    parameterize: MnemosyneEcto.DataCase.repos()

  alias Ecto.Adapters.SQL.Sandbox
  alias Mnemosyne.Errors.Invalid.IngestionError
  alias Mnemosyne.Graph.Changeset
  alias Mnemosyne.Graph.Edge
  alias Mnemosyne.Graph.Node.Semantic
  alias Mnemosyne.Graph.Node.Tag
  alias Mnemosyne.IngestionReceipt
  alias Mnemosyne.NodeMetadata
  alias MnemosyneEcto.Backend
  alias MnemosyneEcto.Queries.IngestionQueries
  alias MnemosyneEcto.Queries.MetadataQueries
  alias MnemosyneEcto.Queries.NodeQueries

  @iterations 10
  @created_at ~U[2026-08-26 00:00:00.000000Z]
  @stored_at ~U[2026-08-26 12:00:00.000000Z]

  setup %{repo: repo} do
    {:ok, state} =
      Backend.init(
        repo: repo,
        tenant_id: unique_id(repo, :setup, 0) <> "-tenant",
        repo_id: unique_id(repo, :setup, 0) <> "-repo"
      )

    {:ok, state: state}
  end

  test "equal payloads elect one graph and return its exact receipt", %{state: base_state} do
    Enum.each(1..@iterations, fn iteration ->
      state = unique_state(base_state, :equal, iteration)
      source_id = unique_id(state.repo, :equal_source, iteration)

      contenders = [
        contender(source_id, unique_id(state.repo, :equal_a, iteration), 1, <<0, 255, 42>>, 1),
        contender(source_id, unique_id(state.repo, :equal_b, iteration), 2, <<0, 255, 42>>, 1)
      ]

      run_iteration(state, source_id, contenders, fn results ->
        winner_receipt = assert_equal_results(results, state)
        assert_winner_graph(state, contenders, winner_receipt)
      end)
    end)
  end

  test "conflicting payloads elect one graph and reject the other source", %{state: base_state} do
    Enum.each(1..@iterations, fn iteration ->
      state = unique_state(base_state, :conflict, iteration)
      source_id = unique_id(state.repo, :conflict_source, iteration)

      {second_digest, second_version} =
        if rem(iteration, 2) == 0, do: {<<1, 2, 3>>, 2}, else: {<<3, 2, 1>>, 1}

      contenders = [
        contender(source_id, unique_id(state.repo, :conflict_a, iteration), 1, <<1, 2, 3>>, 1),
        contender(
          source_id,
          unique_id(state.repo, :conflict_b, iteration),
          2,
          second_digest,
          second_version
        )
      ]

      run_iteration(state, source_id, contenders, fn results ->
        winner_receipt = assert_conflict_results(results, state, source_id)
        assert_winner_graph(state, contenders, winner_receipt)
      end)
    end)
  end

  defp run_iteration(state, source_id, contenders, assertion) do
    node_ids = Enum.flat_map(contenders, & &1.record.receipt.node_ids)

    try do
      results = race(state, contenders)
      assertion.(results)
    after
      cleanup(state, source_id, node_ids)
    end
  end

  defp race(state, contenders) do
    parent = self()
    barrier = make_ref()

    tasks =
      Enum.map(contenders, fn contender ->
        Task.async(fn ->
          Sandbox.unboxed_run(state.repo, fn ->
            send(parent, {:ready, self(), barrier})

            receive do
              {:go, ^barrier} ->
                Backend.commit_ingestion(contender.record, contender.changeset, state)
            end
          end)
        end)
      end)

    readiness =
      Enum.map(tasks, fn task ->
        receive do
          {:ready, pid, ^barrier} when pid == task.pid -> :ready
        after
          5_000 -> {:checkout_timeout, task.pid}
        end
      end)

    Enum.each(tasks, &send(&1.pid, {:go, barrier}))
    results = Enum.map(tasks, &Task.await(&1, 15_000))

    assert Enum.all?(readiness, &(&1 == :ready)),
           "all contenders must obtain independent checkouts before release, got: #{inspect(readiness)}"

    results
  end

  defp assert_equal_results(results, state) do
    assert length(results) == 2

    assert [{:ok, :inserted, winner_receipt, ^state}] =
             Enum.filter(results, &match?({:ok, :inserted, _, _}, &1))

    assert [{:ok, :existing, existing_receipt, ^state}] =
             Enum.filter(results, &match?({:ok, :existing, _, _}, &1))

    assert existing_receipt == winner_receipt
    winner_receipt
  end

  defp assert_conflict_results(results, state, source_id) do
    assert length(results) == 2

    assert [{:ok, :inserted, winner_receipt, ^state}] =
             Enum.filter(results, &match?({:ok, :inserted, _, _}, &1))

    assert [
             {:error,
              %IngestionError{
                source_id: ^source_id,
                reason: :source_conflict
              }}
           ] = Enum.filter(results, &match?({:error, %IngestionError{}}, &1))

    winner_receipt
  end

  defp assert_winner_graph(state, contenders, winner_receipt) do
    winner =
      Enum.find(contenders, fn contender ->
        contender.record.receipt.node_ids == winner_receipt.node_ids
      end)

    assert winner
    loser = Enum.find(contenders, &(&1 != winner))
    assert loser

    Sandbox.unboxed_run(state.repo, fn ->
      winner_record = winner.record
      source_id = winner_record.source_id
      semantic_id = winner.semantic_id
      tag_id = winner.tag_id

      assert {:ok, ^winner_record, ^state} = Backend.get_ingestion(source_id, state)

      assert {:ok, %Semantic{id: ^semantic_id, links: semantic_links}, ^state} =
               Backend.get_node(semantic_id, state)

      assert {:ok, %Tag{id: ^tag_id, links: tag_links}, ^state} =
               Backend.get_node(tag_id, state)

      assert semantic_links.membership == MapSet.new([tag_id])
      assert tag_links.membership == MapSet.new([semantic_id])

      Enum.each(loser.record.receipt.node_ids, fn node_id ->
        assert {:ok, nil, ^state} = Backend.get_node(node_id, state)
      end)

      all_node_ids = Enum.flat_map(contenders, & &1.record.receipt.node_ids)
      assert {:ok, metadata, ^state} = Backend.get_metadata(all_node_ids, state)
      assert metadata == %{semantic_id => winner.metadata}
    end)
  end

  defp contender(source_id, id_prefix, caller, payload_digest, fingerprint_version) do
    semantic_id = id_prefix <> "-semantic"
    tag_id = id_prefix <> "-tag"

    semantic = %Semantic{
      id: semantic_id,
      proposition: "contender #{caller}",
      confidence: 0.9,
      embedding: [0.1, 0.2, 0.3],
      links: Edge.empty_links(),
      created_at: @created_at
    }

    tag = %Tag{
      id: tag_id,
      label: "contender-#{caller}",
      embedding: [0.1, 0.2, 0.3],
      links: Edge.empty_links(),
      created_at: @created_at
    }

    metadata =
      NodeMetadata.new(
        access_count: caller,
        created_at: @created_at,
        cumulative_reward: caller / 10,
        reward_count: caller
      )

    receipt = %IngestionReceipt{
      source_id: source_id,
      node_ids: [tag_id, semantic_id],
      stored_at: DateTime.add(@stored_at, caller, :microsecond)
    }

    %{
      record: %{
        source_id: source_id,
        payload_digest: payload_digest,
        fingerprint_version: fingerprint_version,
        receipt: receipt
      },
      changeset: %Changeset{
        additions: [semantic, tag],
        links: [{semantic_id, tag_id, :membership}],
        metadata: %{semantic_id => metadata}
      },
      semantic_id: semantic_id,
      tag_id: tag_id,
      metadata: metadata
    }
  end

  defp cleanup(state, source_id, node_ids) do
    Sandbox.unboxed_run(state.repo, fn ->
      state
      |> IngestionQueries.for_source(source_id)
      |> state.repo.delete_all()

      state
      |> MetadataQueries.base()
      |> MetadataQueries.by_node_ids(node_ids)
      |> state.repo.delete_all()

      state
      |> NodeQueries.scoped()
      |> NodeQueries.by_ids(node_ids)
      |> state.repo.delete_all()
    end)
  end

  defp unique_state(state, matrix, iteration) do
    unique = unique_id(state.repo, matrix, iteration)
    %{state | tenant_id: unique <> "-tenant", repo_id: unique <> "-repo"}
  end

  defp unique_id(repo, label, iteration) do
    repo_name = repo |> Module.split() |> List.last() |> String.downcase()
    unique = System.unique_integer([:positive, :monotonic])
    "ingestion-race-#{repo_name}-#{label}-#{iteration}-#{unique}"
  end
end
