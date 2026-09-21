defmodule MnemosyneEcto.MetadataConcurrencyTest do
  use ExUnit.Case, async: false, parameterize: MnemosyneEcto.DataCase.repos()

  alias Ecto.Adapters.SQL.Sandbox
  alias Mnemosyne.Errors.Invalid.AccessError
  alias Mnemosyne.Graph.Changeset
  alias Mnemosyne.Graph.Node.Semantic
  alias Mnemosyne.NodeMetadata
  alias MnemosyneEcto.Backend

  test "concurrent first classifications cannot overwrite the winning audience", %{repo: repo} do
    id = "audience-race-#{System.unique_integer([:positive, :monotonic])}"
    {:ok, state} = Backend.init(repo: repo, tenant_id: id, repo_id: id)
    node = %Semantic{id: id, proposition: "legacy", confidence: 1.0}
    metadata = NodeMetadata.new()

    Sandbox.unboxed_run(repo, fn ->
      changeset =
        Changeset.new()
        |> Changeset.add_node(node)
        |> Changeset.put_metadata(id, metadata)

      assert {:ok, ^state} = Backend.apply_changeset(changeset, state)
    end)

    try do
      parent = self()
      barrier = make_ref()

      tasks =
        Enum.map([:repo, [{"org", "private"}]], fn audience ->
          Task.async(fn ->
            Sandbox.unboxed_run(repo, fn ->
              send(parent, {:ready, self(), barrier})

              receive do
                {:go, ^barrier} ->
                  updated = %{
                    metadata
                    | audience: audience,
                      custom: %{"winner" => inspect(audience)}
                  }

                  {updated, Backend.update_metadata(%{id => updated}, state)}
              after
                5_000 -> flunk("classification race was not released")
              end
            end)
          end)
        end)

      Enum.each(tasks, fn task ->
        pid = task.pid
        assert_receive {:ready, ^pid, ^barrier}, 5_000
      end)

      Enum.each(tasks, &send(&1.pid, {:go, barrier}))
      results = Enum.map(tasks, &Task.await(&1, 15_000))

      assert [{winner, {:ok, ^state}}] = Enum.filter(results, &match?({_, {:ok, _}}, &1))

      assert [{_, {:error, %AccessError{reason: :immutable_audience}}}] =
               Enum.filter(results, &match?({_, {:error, _}}, &1))

      Sandbox.unboxed_run(repo, fn ->
        assert {:ok, stored, ^state} = Backend.get_metadata([id], state)
        assert stored[id] == winner
      end)
    after
      Sandbox.unboxed_run(repo, fn -> Backend.delete_nodes([id], state) end)
    end
  end
end
