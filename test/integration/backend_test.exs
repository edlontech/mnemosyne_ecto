defmodule MnemosyneEcto.Integration.BackendTest do
  use MnemosyneEcto.IntegrationCase, async: false

  alias Mnemosyne.Graph.Changeset
  alias Mnemosyne.Graph.Edge
  alias Mnemosyne.Graph.Node.Episodic
  alias Mnemosyne.Graph.Node.Semantic
  alias Mnemosyne.Graph.Node.Tag
  alias Mnemosyne.NodeMetadata
  alias MnemosyneEcto.Backend
  alias Sycophant.EmbeddingRequest
  alias Sycophant.EmbeddingResponse

  @tenant_id "integration-tenant"
  @repo_id "integration-repo"

  defp init_backend(%{repo: repo, prefix: prefix}) do
    {:ok, state} =
      Backend.init(
        repo: repo,
        tenant_id: @tenant_id,
        repo_id: @repo_id,
        prefix: prefix
      )

    state
  end

  defp embed_texts(texts, %{openai_key: api_key, embedding_model: model}) do
    request = %EmbeddingRequest{inputs: texts, model: model}

    {:ok, %EmbeddingResponse{embeddings: %{float: vectors}}} =
      Sycophant.embed(request, credentials: %{api_key: api_key})

    vectors
  end

  defp embed_text(text, ctx), do: hd(embed_texts([text], ctx))

  @moduletag timeout: 120_000

  describe "vector search with real embeddings" do
    test "find_candidates returns semantically relevant nodes ranked by similarity", ctx do
      state = init_backend(ctx)

      texts = [
        "GenServer is an OTP behaviour for implementing stateful server processes in Elixir",
        "Supervisors restart child processes according to a restart strategy",
        "The French Revolution began in 1789 with the storming of the Bastille",
        "Ecto is a database toolkit for Elixir with query composition and changesets"
      ]

      embeddings = embed_texts(texts, ctx)

      nodes =
        Enum.zip(texts, embeddings)
        |> Enum.with_index()
        |> Enum.map(fn {{text, embedding}, i} ->
          %Semantic{
            id: "sem-#{i}",
            proposition: text,
            confidence: 0.95,
            embedding: embedding,
            links: Edge.empty_links(),
            created_at: DateTime.utc_now()
          }
        end)

      changeset = %Changeset{additions: nodes, links: [], metadata: %{}}
      assert {:ok, _state} = Backend.apply_changeset(changeset, state)

      query_embedding = embed_text("how do GenServers work in Elixir?", ctx)

      assert {:ok, candidates, _state} =
               Backend.find_candidates(
                 [:semantic],
                 query_embedding,
                 [],
                 %{params: %{semantic: %{top_k: 4, threshold: 0.0}}},
                 [],
                 state
               )

      assert [_ | _] = candidates

      {top_node, _score} = hd(candidates)
      assert top_node.proposition =~ "GenServer"
    end

    test "find_candidates with tag embeddings boosts related nodes", ctx do
      state = init_backend(ctx)

      texts = [
        "Pattern matching in Elixir destructures data and controls function dispatch",
        "The Sahara is the largest hot desert in the world",
        "Phoenix LiveView enables real-time server-rendered UIs without JavaScript"
      ]

      embeddings = embed_texts(texts, ctx)

      nodes =
        Enum.zip(texts, embeddings)
        |> Enum.with_index()
        |> Enum.map(fn {{text, embedding}, i} ->
          %Semantic{
            id: "tag-sem-#{i}",
            proposition: text,
            confidence: 0.9,
            embedding: embedding,
            links: Edge.empty_links(),
            created_at: DateTime.utc_now()
          }
        end)

      changeset = %Changeset{additions: nodes, links: [], metadata: %{}}
      assert {:ok, _state} = Backend.apply_changeset(changeset, state)

      query_embedding = embed_text("how does Elixir handle data?", ctx)
      tag_embedding = embed_text("functional programming web framework", ctx)

      assert {:ok, candidates, _state} =
               Backend.find_candidates(
                 [:semantic],
                 query_embedding,
                 [tag_embedding],
                 %{params: %{semantic: %{top_k: 3, threshold: 0.0}}},
                 [],
                 state
               )

      {last_node, _last_score} = List.last(candidates)
      assert last_node.proposition =~ "Sahara"

      {top_node, _top_score} = hd(candidates)
      refute top_node.proposition =~ "Sahara"
    end
  end

  describe "full lifecycle with real embeddings" do
    test "store, retrieve, update metadata, and delete nodes", ctx do
      state = init_backend(ctx)

      [sem_emb, epi_emb, tag_emb] =
        embed_texts(
          [
            "Elixir processes are lightweight and isolated",
            "Explored process isolation by crashing a child without affecting the parent",
            "concurrency"
          ],
          ctx
        )

      semantic = %Semantic{
        id: "life-sem-1",
        proposition: "Elixir processes are lightweight and isolated",
        confidence: 0.95,
        embedding: sem_emb,
        links: Edge.empty_links(),
        created_at: DateTime.utc_now()
      }

      episodic = %Episodic{
        id: "life-epi-1",
        observation:
          "Explored process isolation by crashing a child without affecting the parent",
        action: "spawned a process and let it crash",
        state: "learning",
        subgoal: "understand fault tolerance",
        reward: 1.0,
        trajectory_id: "traj-integration",
        embedding: epi_emb,
        links: Edge.empty_links(),
        created_at: DateTime.utc_now()
      }

      tag = %Tag{
        id: "life-tag-1",
        label: "concurrency",
        embedding: tag_emb,
        links: Edge.empty_links(),
        created_at: DateTime.utc_now()
      }

      metadata = %{
        "life-sem-1" => NodeMetadata.new(),
        "life-epi-1" => NodeMetadata.new()
      }

      links = [
        {"life-sem-1", "life-epi-1", :provenance},
        {"life-sem-1", "life-tag-1", :tagged}
      ]

      changeset = %Changeset{
        additions: [semantic, episodic, tag],
        links: links,
        metadata: metadata
      }

      assert {:ok, state} = Backend.apply_changeset(changeset, state)

      assert {:ok, %Semantic{id: "life-sem-1"} = fetched, _state} =
               Backend.get_node("life-sem-1", state)

      assert fetched.proposition == "Elixir processes are lightweight and isolated"
      assert is_list(fetched.embedding)
      assert length(fetched.embedding) == 1536

      assert {:ok, linked_nodes, _state} =
               Backend.get_linked_nodes(["life-sem-1", "life-epi-1"], :provenance, state)

      assert length(linked_nodes) == 2

      assert {:ok, nodes, _state} = Backend.get_nodes_by_type([:semantic, :tag], state)
      types = Enum.map(nodes, & &1.__struct__) |> Enum.uniq() |> MapSet.new()
      assert Semantic in types
      assert Tag in types

      now = DateTime.utc_now()

      updated_metadata = %{
        "life-sem-1" =>
          NodeMetadata.new(
            access_count: 5,
            last_accessed_at: now,
            cumulative_reward: 3.5,
            reward_count: 5
          )
      }

      assert {:ok, _state} = Backend.update_metadata(updated_metadata, state)

      assert {:ok, meta_map, _state} = Backend.get_metadata(["life-sem-1"], state)
      assert %NodeMetadata{access_count: 5, cumulative_reward: 3.5} = meta_map["life-sem-1"]

      query_embedding = embed_text("how do Elixir processes handle isolation?", ctx)

      assert {:ok, candidates, _state} =
               Backend.find_candidates(
                 [:semantic, :episodic],
                 query_embedding,
                 [],
                 %{
                   params: %{
                     semantic: %{top_k: 5, threshold: 0.0},
                     episodic: %{top_k: 5, threshold: 0.0}
                   }
                 },
                 [],
                 state
               )

      assert [_ | _] = candidates

      assert {:ok, _state} =
               Backend.delete_nodes(["life-sem-1", "life-epi-1", "life-tag-1"], state)

      assert {:ok, nil, _state} = Backend.get_node("life-sem-1", state)
      assert {:ok, meta_map, _state} = Backend.get_metadata(["life-sem-1"], state)
      assert meta_map == %{}
    end
  end

  describe "multi-tenant isolation with real embeddings" do
    test "nodes from different tenants do not appear in each other's searches", ctx do
      embeddings =
        embed_texts(
          [
            "Elixir macros enable compile-time metaprogramming",
            "Rust ownership system prevents data races at compile time"
          ],
          ctx
        )

      [elixir_emb, rust_emb] = embeddings

      {:ok, tenant_a_state} =
        Backend.init(
          repo: ctx.repo,
          tenant_id: "tenant-a",
          repo_id: @repo_id,
          prefix: ctx.prefix
        )

      {:ok, tenant_b_state} =
        Backend.init(
          repo: ctx.repo,
          tenant_id: "tenant-b",
          repo_id: @repo_id,
          prefix: ctx.prefix
        )

      changeset_a = %Changeset{
        additions: [
          %Semantic{
            id: "tenant-a-sem",
            proposition: "Elixir macros enable compile-time metaprogramming",
            confidence: 0.9,
            embedding: elixir_emb,
            links: Edge.empty_links(),
            created_at: DateTime.utc_now()
          }
        ],
        links: [],
        metadata: %{}
      }

      changeset_b = %Changeset{
        additions: [
          %Semantic{
            id: "tenant-b-sem",
            proposition: "Rust ownership system prevents data races at compile time",
            confidence: 0.9,
            embedding: rust_emb,
            links: Edge.empty_links(),
            created_at: DateTime.utc_now()
          }
        ],
        links: [],
        metadata: %{}
      }

      assert {:ok, _} = Backend.apply_changeset(changeset_a, tenant_a_state)
      assert {:ok, _} = Backend.apply_changeset(changeset_b, tenant_b_state)

      query_emb = embed_text("metaprogramming in Elixir", ctx)

      assert {:ok, candidates_a, _} =
               Backend.find_candidates(
                 [:semantic],
                 query_emb,
                 [],
                 %{params: %{semantic: %{top_k: 10, threshold: 0.0}}},
                 [],
                 tenant_a_state
               )

      assert {:ok, candidates_b, _} =
               Backend.find_candidates(
                 [:semantic],
                 query_emb,
                 [],
                 %{params: %{semantic: %{top_k: 10, threshold: 0.0}}},
                 [],
                 tenant_b_state
               )

      ids_a = Enum.map(candidates_a, fn {node, _} -> node.id end)
      ids_b = Enum.map(candidates_b, fn {node, _} -> node.id end)

      assert "tenant-a-sem" in ids_a
      refute "tenant-b-sem" in ids_a
      assert "tenant-b-sem" in ids_b
      refute "tenant-a-sem" in ids_b
    end
  end

  describe "LLM-driven node content with real embeddings" do
    test "generate node propositions via LLM and store with embeddings for retrieval", ctx do
      state = init_backend(ctx)

      messages = [
        Sycophant.Message.system(
          "You are a knowledge extraction assistant. Given a topic, produce exactly 3 short factual statements about it, one per line. No numbering, no bullets."
        ),
        Sycophant.Message.user("Elixir's concurrency model")
      ]

      assert {:ok, %Sycophant.Response{text: text}} =
               Sycophant.generate_text(ctx.llm_model, messages,
                 credentials: %{api_key: ctx.openrouter_key},
                 temperature: 0.3
               )

      propositions =
        text
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      assert length(propositions) >= 2

      embeddings = embed_texts(propositions, ctx)

      nodes =
        Enum.zip(propositions, embeddings)
        |> Enum.with_index()
        |> Enum.map(fn {{prop, emb}, i} ->
          %Semantic{
            id: "llm-sem-#{i}",
            proposition: prop,
            confidence: 0.85,
            embedding: emb,
            links: Edge.empty_links(),
            created_at: DateTime.utc_now()
          }
        end)

      changeset = %Changeset{additions: nodes, links: [], metadata: %{}}
      assert {:ok, _state} = Backend.apply_changeset(changeset, state)

      query_embedding = embed_text("how does Elixir handle concurrent processes?", ctx)

      assert {:ok, candidates, _state} =
               Backend.find_candidates(
                 [:semantic],
                 query_embedding,
                 [],
                 %{params: %{semantic: %{top_k: 5, threshold: 0.0}}},
                 [],
                 state
               )

      assert [_ | _] = candidates

      {top_node, top_score} = hd(candidates)
      assert is_binary(top_node.proposition)
      assert top_score > 0.0
    end
  end
end
