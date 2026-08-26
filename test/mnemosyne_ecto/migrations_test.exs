defmodule MnemosyneEcto.MigrationsTest do
  use MnemosyneEcto.DataCase, async: false, parameterize: MnemosyneEcto.DataCase.repos()

  alias MnemosyneEcto.Migrations

  describe "current_version/0" do
    test "returns the current migration version" do
      assert Migrations.current_version() == 1
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

  describe "mnemosyne_ingestions table" do
    test "has non-null durable receipt columns and a composite primary key", %{repo: repo} do
      {:ok, %{rows: rows}} =
        repo.query(
          "SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name = 'mnemosyne_ingestions' ORDER BY ordinal_position"
        )

      columns = Map.new(rows, fn [name, type, nullable] -> {name, {type, nullable}} end)

      assert columns == %{
               "tenant_id" => {"text", "NO"},
               "repo_id" => {"text", "NO"},
               "source_id" => {"text", "NO"},
               "payload_digest" => {"bytea", "NO"},
               "fingerprint_version" => {"integer", "NO"},
               "node_ids" => {"ARRAY", "NO"},
               "stored_at" => {"timestamp with time zone", "NO"}
             }

      {:ok, %{rows: primary_key}} =
        repo.query("""
        SELECT kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_name = 'mnemosyne_ingestions'
          AND tc.constraint_type = 'PRIMARY KEY'
        ORDER BY kcu.ordinal_position
        """)

      assert primary_key == [["tenant_id"], ["repo_id"], ["source_id"]]

      {:ok, %{rows: node_ids_type}} =
        repo.query("""
        SELECT format_type(attribute.atttypid, attribute.atttypmod)
        FROM pg_attribute attribute
        JOIN pg_class relation ON relation.oid = attribute.attrelid
        WHERE relation.relname = 'mnemosyne_ingestions'
          AND attribute.attname = 'node_ids'
          AND attribute.attnum > 0
          AND NOT attribute.attisdropped
        """)

      assert node_ids_type == [["text[]"]]
    end

    test "has no foreign keys", %{repo: repo} do
      {:ok, %{rows: rows}} =
        repo.query("""
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'mnemosyne_ingestions'
          AND constraint_type = 'FOREIGN KEY'
        """)

      assert rows == []
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
    {:ok, %{rows: ingestion_rows}} = repo.query("PRAGMA table_info(mnemosyne_ingestions)")
    {:ok, %{rows: [[1]]}} = repo.query("SELECT version FROM mnemosyne_schema_version")

    node_columns = MapSet.new(Enum.map(node_rows, &Enum.at(&1, 1)))
    metadata_columns = MapSet.new(Enum.map(metadata_rows, &Enum.at(&1, 1)))

    ingestion_columns =
      Map.new(ingestion_rows, fn [_, name, type, not_null, _, primary_key] ->
        {name, {type, not_null, primary_key}}
      end)

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

    assert ingestion_columns == %{
             "tenant_id" => {"TEXT", 1, 1},
             "repo_id" => {"TEXT", 1, 2},
             "source_id" => {"TEXT", 1, 3},
             "payload_digest" => {"BLOB", 1, 0},
             "fingerprint_version" => {"INTEGER", 1, 0},
             "node_ids" => {"TEXT", 1, 0},
             "stored_at" => {"TEXT", 1, 0}
           }

    {:ok, %{rows: foreign_keys}} = repo.query("PRAGMA foreign_key_list(mnemosyne_ingestions)")
    assert foreign_keys == []
  end
end
