defmodule SqlDirTest do
  use SqlDir.DataCase, async: false

  alias SqlDir.Test.{PostgresSQL, MySQLSQL, SQLiteSQL, TdsSQL, ClickHouseSQL, User}
  alias SqlDir.Test.{PostgresRepo, MySQLRepo, SQLiteRepo, TdsRepo, ClickHouseRepo}

  # Define atoms used in queries so to_existing_atom works
  _ = [:id, :name, :email, :age]

  # Adapters that support Ecto sandbox
  @sandbox_adapters [
    {:postgres, PostgresSQL, PostgresRepo},
    {:mysql, MySQLSQL, MySQLRepo},
    {:sqlite, SQLiteSQL, SQLiteRepo},
    {:tds, TdsSQL, TdsRepo}
  ]

  # All adapters including those without sandbox support
  @all_adapters @sandbox_adapters ++ [{:clickhouse, ClickHouseSQL, ClickHouseRepo}]

  describe "load!/1" do
    for {adapter, sql_module, _repo} <- @all_adapters do
      @sql_module sql_module

      test "#{adapter}: returns SQL string from file" do
        sql = @sql_module.load!("all_users.sql")
        assert sql =~ "SELECT"
        assert sql =~ "FROM users"
      end

      test "#{adapter}: raises for unknown file" do
        assert_raise RuntimeError, ~r/was not included in the :files list/, fn ->
          @sql_module.load!("nonexistent.sql")
        end
      end
    end
  end

  describe "query_all!/3" do
    # Tests for adapters that support sandbox
    for {adapter, sql_module, repo} <- @sandbox_adapters do
      @sql_module sql_module
      @repo repo

      setup do
        setup_sandbox(@repo)
      end

      test "#{adapter}: returns list of maps" do
        results = @sql_module.query_all!("all_users.sql")

        assert length(results) == 3
        assert Enum.all?(results, &is_map/1)

        first = hd(results)
        assert first.id == 1
        assert first.name == "Alice"
      end

      test "#{adapter}: casts to struct with :as option" do
        results = @sql_module.query_all!("all_users.sql", [], as: User)

        assert length(results) == 3
        assert Enum.all?(results, &match?(%User{}, &1))
      end

      test "#{adapter}: returns empty list when no results" do
        results = @sql_module.query_all!("no_users.sql")
        assert results == []
      end

      test "#{adapter}: passes parameters to query" do
        results = @sql_module.query_all!("user_by_id.sql", [1])

        assert length(results) == 1
        assert hd(results).name == "Alice"
      end
    end

    # ClickHouse tests (no sandbox support)
    test "clickhouse: returns list of maps" do
      results = ClickHouseSQL.query_all!("all_users.sql")

      assert length(results) == 3
      assert Enum.all?(results, &is_map/1)

      first = hd(results)
      assert first.id == 1
      assert first.name == "Alice"
    end

    test "clickhouse: casts to struct with :as option" do
      results = ClickHouseSQL.query_all!("all_users.sql", [], as: User)

      assert length(results) == 3
      assert Enum.all?(results, &match?(%User{}, &1))
    end

    test "clickhouse: returns empty list when no results" do
      results = ClickHouseSQL.query_all!("no_users.sql")
      assert results == []
    end

    test "clickhouse: passes parameters to query" do
      results = ClickHouseSQL.query_all!("user_by_id.sql", %{id: 1})

      assert length(results) == 1
      assert hd(results).name == "Alice"
    end
  end

  describe "query_one!/3" do
    # Tests for adapters that support sandbox
    for {adapter, sql_module, repo} <- @sandbox_adapters do
      @sql_module sql_module
      @repo repo

      setup do
        setup_sandbox(@repo)
      end

      test "#{adapter}: returns single map" do
        result = @sql_module.query_one!("first_user.sql")

        assert result.id == 1
        assert result.name == "Alice"
      end

      test "#{adapter}: returns result with parameterized query" do
        result = @sql_module.query_one!("user_by_id.sql", [2])

        assert result.id == 2
        assert result.name == "Bob"
      end

      test "#{adapter}: raises NoResultsError when no rows" do
        assert_raise SqlDir.NoResultsError, ~r/expected at least one result/, fn ->
          @sql_module.query_one!("no_users.sql")
        end
      end

      test "#{adapter}: raises MultipleResultsError when multiple rows" do
        assert_raise SqlDir.MultipleResultsError, ~r/got 3/, fn ->
          @sql_module.query_one!("all_users.sql")
        end
      end

      test "#{adapter}: casts to struct with :as option" do
        result = @sql_module.query_one!("first_user.sql", [], as: User)

        assert %User{} = result
        assert result.name == "Alice"
      end
    end

    # ClickHouse tests (no sandbox support)
    test "clickhouse: returns single map" do
      result = ClickHouseSQL.query_one!("first_user.sql")

      assert result.id == 1
      assert result.name == "Alice"
    end

    test "clickhouse: returns result with parameterized query" do
      result = ClickHouseSQL.query_one!("user_by_id.sql", %{id: 2})

      assert result.id == 2
      assert result.name == "Bob"
    end

    test "clickhouse: raises NoResultsError when no rows" do
      assert_raise SqlDir.NoResultsError, ~r/expected at least one result/, fn ->
        ClickHouseSQL.query_one!("no_users.sql")
      end
    end

    test "clickhouse: raises MultipleResultsError when multiple rows" do
      assert_raise SqlDir.MultipleResultsError, ~r/got 3/, fn ->
        ClickHouseSQL.query_one!("all_users.sql")
      end
    end

    test "clickhouse: casts to struct with :as option" do
      result = ClickHouseSQL.query_one!("first_user.sql", [], as: User)

      assert %User{} = result
      assert result.name == "Alice"
    end
  end

  describe "extract_result/1" do
    setup do
      setup_sandbox(PostgresRepo)
      setup_sandbox(MySQLRepo)
      setup_sandbox(SQLiteRepo)
      setup_sandbox(TdsRepo)
    end

    test "extracts columns and rows from Postgrex.Result" do
      result = PostgresRepo.query!("SELECT id, name FROM users WHERE id = $1", [1])
      assert %Postgrex.Result{} = result

      {columns, rows} = SqlDir.extract_result(result)
      assert columns == ["id", "name"]
      assert [[1, "Alice"]] = rows
    end

    test "extracts columns and rows from MyXQL.Result" do
      result = MySQLRepo.query!("SELECT id, name FROM users WHERE id = ?", [1])
      assert %MyXQL.Result{} = result

      {columns, rows} = SqlDir.extract_result(result)
      assert columns == ["id", "name"]
      assert [[1, "Alice"]] = rows
    end

    test "extracts columns and rows from Exqlite.Result" do
      result = SQLiteRepo.query!("SELECT id, name FROM users WHERE id = ?", [1])
      assert %Exqlite.Result{} = result

      {columns, rows} = SqlDir.extract_result(result)
      assert columns == ["id", "name"]
      assert [[1, "Alice"]] = rows
    end

    test "extracts columns and rows from Tds.Result" do
      result = TdsRepo.query!("SELECT id, name FROM users WHERE id = @1", [1])
      assert %Tds.Result{} = result

      {columns, rows} = SqlDir.extract_result(result)
      assert columns == ["id", "name"]
      assert [[1, "Alice"]] = rows
    end

    test "extracts columns and rows from Ch.Result" do
      result = ClickHouseRepo.query!("SELECT id, name FROM users WHERE id = {id:UInt32}", %{id: 1})

      {columns, rows} = SqlDir.extract_result(result)
      assert columns == ["id", "name"]
      assert [[1, "Alice"]] = rows
    end

    test "raises for unsupported result type" do
      assert_raise ArgumentError, ~r/Unsupported query result type/, fn ->
        SqlDir.extract_result(%{cols: [], rows: []})
      end
    end
  end

  describe "load/1 (non-bang)" do
    for {adapter, sql_module, _repo} <- @all_adapters do
      @sql_module sql_module

      test "#{adapter}: returns {:ok, sql} on success" do
        assert {:ok, sql} = @sql_module.load("all_users.sql")
        assert sql =~ "SELECT"
        assert sql =~ "FROM users"
      end

      test "#{adapter}: returns {:error, reason} for unknown file" do
        assert {:error, %RuntimeError{}} = @sql_module.load("nonexistent.sql")
      end
    end
  end

  describe "query_all/3 (non-bang)" do
    for {adapter, sql_module, repo} <- @sandbox_adapters do
      @sql_module sql_module
      @repo repo

      setup do
        setup_sandbox(@repo)
      end

      test "#{adapter}: returns {:ok, results} on success" do
        assert {:ok, results} = @sql_module.query_all("all_users.sql")
        assert length(results) == 3
        assert hd(results).name == "Alice"
      end

      test "#{adapter}: returns {:ok, []} when no results" do
        assert {:ok, []} = @sql_module.query_all("no_users.sql")
      end

      test "#{adapter}: returns {:error, exception} on query error" do
        assert {:error, %RuntimeError{}} = @sql_module.query_all("nonexistent.sql")
      end
    end

    # ClickHouse tests (no sandbox support)
    test "clickhouse: returns {:ok, results} on success" do
      assert {:ok, results} = ClickHouseSQL.query_all("all_users.sql")
      assert length(results) == 3
      assert hd(results).name == "Alice"
    end

    test "clickhouse: returns {:ok, []} when no results" do
      assert {:ok, []} = ClickHouseSQL.query_all("no_users.sql")
    end

    test "clickhouse: returns {:error, exception} on query error" do
      assert {:error, %RuntimeError{}} = ClickHouseSQL.query_all("nonexistent.sql")
    end
  end

  describe "query_one/3 (non-bang)" do
    for {adapter, sql_module, repo} <- @sandbox_adapters do
      @sql_module sql_module
      @repo repo

      setup do
        setup_sandbox(@repo)
      end

      test "#{adapter}: returns {:ok, result} on exactly one result" do
        assert {:ok, result} = @sql_module.query_one("first_user.sql")
        assert result.id == 1
        assert result.name == "Alice"
      end

      test "#{adapter}: returns {:ok, nil} when no results" do
        assert {:ok, nil} = @sql_module.query_one("no_users.sql")
      end

      test "#{adapter}: returns {:error, MultipleResultsError} when multiple results" do
        assert {:error, %SqlDir.MultipleResultsError{count: 3}} =
                 @sql_module.query_one("all_users.sql")
      end

      test "#{adapter}: returns {:error, exception} on query error" do
        assert {:error, %RuntimeError{}} = @sql_module.query_one("nonexistent.sql")
      end

      test "#{adapter}: casts to struct with :as option" do
        assert {:ok, %User{name: "Alice"}} = @sql_module.query_one("first_user.sql", [], as: User)
      end
    end

    # ClickHouse tests (no sandbox support)
    test "clickhouse: returns {:ok, result} on exactly one result" do
      assert {:ok, result} = ClickHouseSQL.query_one("first_user.sql")
      assert result.id == 1
      assert result.name == "Alice"
    end

    test "clickhouse: returns {:ok, nil} when no results" do
      assert {:ok, nil} = ClickHouseSQL.query_one("no_users.sql")
    end

    test "clickhouse: returns {:error, MultipleResultsError} when multiple results" do
      assert {:error, %SqlDir.MultipleResultsError{count: 3}} =
               ClickHouseSQL.query_one("all_users.sql")
    end

    test "clickhouse: returns {:error, exception} on query error" do
      assert {:error, %RuntimeError{}} = ClickHouseSQL.query_one("nonexistent.sql")
    end

    test "clickhouse: casts to struct with :as option" do
      assert {:ok, %User{name: "Alice"}} = ClickHouseSQL.query_one("first_user.sql", [], as: User)
    end
  end

  describe "multi-parameter queries" do
    # Test data: Alice (30), Bob (25), Charlie (35)
    # Query: age >= min AND age <= max

    # Sandbox adapters
    for {adapter, sql_module, repo} <- @sandbox_adapters do
      @sql_module sql_module
      @repo repo

      setup do
        setup_sandbox(@repo)
      end

      test "#{adapter}: query_all! with multiple parameters" do
        # age >= 26 AND age <= 32 should return only Alice (30)
        results = @sql_module.query_all!("users_by_age_range.sql", [26, 32])
        assert length(results) == 1
        assert hd(results).name == "Alice"
      end

      test "#{adapter}: query_all with multiple parameters" do
        # age >= 24 AND age <= 31 should return Alice (30) and Bob (25)
        assert {:ok, results} = @sql_module.query_all("users_by_age_range.sql", [24, 31])
        assert length(results) == 2
        names = Enum.map(results, & &1.name)
        assert "Alice" in names
        assert "Bob" in names
      end

      test "#{adapter}: query_one! with multiple parameters" do
        # age >= 34 AND age <= 36 should return only Charlie (35)
        result = @sql_module.query_one!("users_by_age_range.sql", [34, 36])
        assert result.name == "Charlie"
        assert result.age == 35
      end

      test "#{adapter}: query_one with multiple parameters" do
        # age >= 29 AND age <= 31 should return only Alice (30)
        assert {:ok, result} = @sql_module.query_one("users_by_age_range.sql", [29, 31])
        assert result.name == "Alice"
      end
    end

    # ClickHouse tests (no sandbox, uses map params)
    test "clickhouse: query_all! with multiple parameters" do
      results = ClickHouseSQL.query_all!("users_by_age_range.sql", %{min_age: 26, max_age: 32})
      assert length(results) == 1
      assert hd(results).name == "Alice"
    end

    test "clickhouse: query_all with multiple parameters" do
      assert {:ok, results} = ClickHouseSQL.query_all("users_by_age_range.sql", %{min_age: 24, max_age: 31})
      assert length(results) == 2
      names = Enum.map(results, & &1.name)
      assert "Alice" in names
      assert "Bob" in names
    end

    test "clickhouse: query_one! with multiple parameters" do
      result = ClickHouseSQL.query_one!("users_by_age_range.sql", %{min_age: 34, max_age: 36})
      assert result.name == "Charlie"
      assert result.age == 35
    end

    test "clickhouse: query_one with multiple parameters" do
      assert {:ok, result} = ClickHouseSQL.query_one("users_by_age_range.sql", %{min_age: 29, max_age: 31})
      assert result.name == "Alice"
    end
  end

  describe "compile-time validation" do
    test "raises CompileError for missing SQL file" do
      assert_raise CompileError, fn ->
        defmodule BadSQL do
          use SqlDir,
            otp_app: :sql_dir,
            repo: SqlDir.Test.PostgresRepo,
            dirname: "test_postgres",
            files: ["does_not_exist.sql"]
        end
      end
    end
  end
end
