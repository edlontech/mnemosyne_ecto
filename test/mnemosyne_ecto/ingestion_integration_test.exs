defmodule MnemosyneEcto.IngestionIntegrationTest do
  use MnemosyneEcto.DataCase,
    async: false,
    parameterize: MnemosyneEcto.DataCase.repos()

  import Mimic

  alias Mnemosyne.Config
  alias Mnemosyne.Errors.Invalid.IngestionError
  alias Mnemosyne.Graph.Changeset
  alias Mnemosyne.Graph.Node.Semantic
  alias Mnemosyne.IngestionReceipt
  alias Mnemosyne.Trajectory
  alias MnemosyneEcto.Backend

  setup :set_mimic_global
  setup :verify_on_exit!

  defmodule UnusedLLM do
    @moduledoc false
    @behaviour Mnemosyne.LLM

    @impl true
    def chat(_messages, _opts), do: raise("LLM must not be called")

    @impl true
    def chat_structured(_messages, _schema, _opts), do: raise("LLM must not be called")
  end

  defmodule UnusedEmbedding do
    @moduledoc false
    @behaviour Mnemosyne.Embedding

    @impl true
    def embed(_text, _opts), do: raise("embedding must not be called")

    @impl true
    def embed_batch(_texts, _opts), do: raise("embedding must not be called")
  end

  test "public ingestion is immediately visible, durable, idempotent, and conflict-safe", %{
    repo: repo
  } do
    unique = System.unique_integer([:positive, :monotonic])
    supervisor = :"mnemosyne_ecto_ingestion_#{unique}"
    repo_id = "ingestion-repo-#{unique}"
    tenant_id = "ingestion-tenant-#{unique}"
    source_id = "ingestion-source-#{unique}"
    node_id = "ingestion-node-#{unique}"

    trajectory = %Trajectory{
      source_id: source_id,
      goal: "Persist a deterministic trajectory",
      steps: [%{observation: "Observed", action: "Acted"}],
      metadata: %{test: "public-ingestion"}
    }

    node = %Semantic{
      id: node_id,
      proposition: "A durable fact",
      confidence: 0.9,
      embedding: [0.1, 0.2, 0.3],
      created_at: ~U[2026-08-26 12:34:56.123456Z]
    }

    changeset = Changeset.add_node(Changeset.new(), node)

    expect(Mnemosyne.Pipeline.Ingestion, :run, fn ^trajectory, _opts ->
      {:ok, changeset}
    end)

    supervisor_opts = [
      name: supervisor,
      config: config(),
      llm: UnusedLLM,
      embedding: UnusedEmbedding,
      backend: {Backend, repo: repo, tenant_id: tenant_id}
    ]

    start_supervised!({Mnemosyne.Supervisor, supervisor_opts}, id: supervisor)
    assert {:ok, _pid} = Mnemosyne.open_repo(repo_id, supervisor: supervisor)

    assert {:ok, %IngestionReceipt{source_id: ^source_id, node_ids: [^node_id]} = receipt} =
             Mnemosyne.ingest(repo_id, trajectory, supervisor: supervisor)

    assert {:ok, %Semantic{id: ^node_id} = stored_node} =
             Mnemosyne.get_node(repo_id, node_id, supervisor: supervisor)

    stop_supervised!(supervisor)
    start_supervised!({Mnemosyne.Supervisor, supervisor_opts}, id: supervisor)
    assert {:ok, _pid} = Mnemosyne.open_repo(repo_id, supervisor: supervisor)

    assert {:ok, ^receipt} = Mnemosyne.ingest(repo_id, trajectory, supervisor: supervisor)

    changed_trajectory = %{trajectory | goal: "A conflicting trajectory"}

    assert {:error, %IngestionError{source_id: ^source_id, reason: :source_conflict}} =
             Mnemosyne.ingest(repo_id, changed_trajectory, supervisor: supervisor)

    assert {:ok, ^receipt} = Mnemosyne.ingest(repo_id, trajectory, supervisor: supervisor)

    assert {:ok, ^stored_node} =
             Mnemosyne.get_node(repo_id, node_id, supervisor: supervisor)
  end

  defp config do
    {:ok, config} =
      Zoi.parse(Config.t(), %{
        llm: %{model: "unused-llm", opts: %{}},
        embedding: %{model: "unused-embedding", opts: %{}}
      })

    config
  end
end
