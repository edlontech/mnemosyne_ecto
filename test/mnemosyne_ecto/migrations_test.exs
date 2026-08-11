defmodule MnemosyneEcto.MigrationsTest do
  use MnemosyneEcto.DataCase, async: false, parameterize: MnemosyneEcto.DataCase.repos()

  alias MnemosyneEcto.Migrations

  describe "current_version/0" do
    test "returns the current migration version" do
      assert Migrations.current_version() >= 1
    end
  end

  describe "migrated_version/2" do
    test "returns the version stored by the active adapter", %{repo: repo} do
      assert Migrations.migrated_version(repo) >= 1
    end
  end
end

defmodule MnemosyneEcto.Migrations.PostgresTest do
  use MnemosyneEcto.DataCase,
    async: false,
    parameterize: [%{repo: MnemosyneEcto.TestRepo.Postgres}]

  @node_types ~W(semantic episodic procedural subgoal source tag intent)

  describe "mnemosyne_nodes table" do
    test "has the expected columns", %{repo: repo} do
      {:ok, %{rows: rows}} =
        repo.query(
          "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'mnemosyne_nodes' ORDER BY ordinal_position"
        )

      column_map = Map.new(rows, fn [name, type] -> {name, type} end)

      assert column_map["id"] == "text"
      assert column_map["tenant_id"] == "text"
      assert column_map["repo_id"] == "text"
      assert column_map["type"] == "text"
      assert column_map["data"] == "jsonb"
      assert column_map["embedding"] == "USER-DEFINED"
      assert column_map["links"] == "jsonb"
      assert column_map["created_at"] == "timestamp with time zone"
    end
  end

  describe "mnemosyne_node_metadata table" do
    test "has the expected columns", %{repo: repo} do
      {:ok, %{rows: rows}} =
        repo.query(
          "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'mnemosyne_node_metadata' ORDER BY ordinal_position"
        )

      column_map = Map.new(rows, fn [name, type] -> {name, type} end)

      assert column_map["tenant_id"] == "text"
      assert column_map["node_id"] == "text"
      assert column_map["access_count"] == "integer"
      assert column_map["last_accessed_at"] == "timestamp with time zone"
      assert column_map["created_at"] == "timestamp with time zone"
      assert column_map["cumulative_reward"] == "double precision"
      assert column_map["reward_count"] == "integer"
    end

    test "has a foreign key on node_id referencing mnemosyne_nodes", %{repo: repo} do
      {:ok, %{rows: rows}} =
        repo.query("""
        SELECT tc.constraint_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_name = 'mnemosyne_node_metadata'
          AND tc.constraint_type = 'FOREIGN KEY'
          AND kcu.column_name = 'node_id'
        """)

      assert length(rows) == 1
    end
  end

  describe "indexes" do
    test "has a btree index on tenant_id, repo_id, type", %{repo: repo} do
      {:ok, %{rows: rows}} =
        repo.query("""
        SELECT indexname FROM pg_indexes
        WHERE tablename = 'mnemosyne_nodes'
        AND indexdef LIKE '%btree%'
        AND indexdef LIKE '%tenant_id%'
        AND indexdef LIKE '%repo_id%'
        AND indexdef LIKE '%type%'
        """)

      assert length(rows) == 1
    end

    test "has a partial HNSW index per node type", %{repo: repo} do
      for node_type <- @node_types do
        {:ok, %{rows: rows}} =
          repo.query(
            """
            SELECT indexname FROM pg_indexes
            WHERE tablename = 'mnemosyne_nodes'
            AND indexdef LIKE '%hnsw%'
            AND indexdef LIKE $1
            """,
            ["%type = '#{node_type}'%"]
          )

        assert [_] = rows, "expected one HNSW index for type #{node_type}"
      end
    end
  end
end

defmodule MnemosyneEcto.Migrations.SQLiteTest do
  use MnemosyneEcto.DataCase,
    async: false,
    parameterize: [%{repo: MnemosyneEcto.TestRepo.SQLite}]

  test "has the expected tables, columns, and schema version", %{repo: repo} do
    {:ok, %{rows: node_rows}} = repo.query("PRAGMA table_info(mnemosyne_nodes)")
    {:ok, %{rows: metadata_rows}} = repo.query("PRAGMA table_info(mnemosyne_node_metadata)")
    {:ok, %{rows: [[1]]}} = repo.query("SELECT version FROM mnemosyne_schema_version")

    node_columns = MapSet.new(Enum.map(node_rows, &Enum.at(&1, 1)))
    metadata_columns = MapSet.new(Enum.map(metadata_rows, &Enum.at(&1, 1)))

    assert MapSet.subset?(
             MapSet.new(~W(id tenant_id repo_id type data embedding links created_at)),
             node_columns
           )

    assert MapSet.subset?(
             MapSet.new(
               ~W(tenant_id node_id access_count last_accessed_at created_at cumulative_reward reward_count)
             ),
             metadata_columns
           )
  end
end
