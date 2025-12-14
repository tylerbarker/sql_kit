defmodule SqlKitTest do
  use SqlKit.DataCase, async: false

  alias SqlKit.Test.ClickHouseRepo
  alias SqlKit.Test.ClickHouseSQL
  alias SqlKit.Test.MySQLRepo
  alias SqlKit.Test.MySQLSQL
  alias SqlKit.Test.PostgresRepo
  alias SqlKit.Test.PostgresSQL
  alias SqlKit.Test.SQLiteRepo
  alias SqlKit.Test.SQLiteSQL
  alias SqlKit.Test.TdsRepo
  alias SqlKit.Test.TdsSQL
  alias SqlKit.Test.User

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

        # query!/3 is an alias for query_one!/3
        assert @sql_module.query!("first_user.sql") == result
      end

      test "#{adapter}: returns result with parameterized query" do
        result = @sql_module.query_one!("user_by_id.sql", [2])

        assert result.id == 2
        assert result.name == "Bob"

        # query!/3 is an alias for query_one!/3
        assert @sql_module.query!("user_by_id.sql", [2]) == result
      end

      test "#{adapter}: raises NoResultsError when no rows" do
        assert_raise SqlKit.NoResultsError, ~r/expected at least one result/, fn ->
          @sql_module.query_one!("no_users.sql")
        end

        # query!/3 is an alias for query_one!/3
        assert_raise SqlKit.NoResultsError, fn ->
          @sql_module.query!("no_users.sql")
        end
      end

      test "#{adapter}: raises MultipleResultsError when multiple rows" do
        assert_raise SqlKit.MultipleResultsError, ~r/got 3/, fn ->
          @sql_module.query_one!("all_users.sql")
        end

        # query!/3 is an alias for query_one!/3
        assert_raise SqlKit.MultipleResultsError, fn ->
          @sql_module.query!("all_users.sql")
        end
      end

      test "#{adapter}: casts to struct with :as option" do
        result = @sql_module.query_one!("first_user.sql", [], as: User)

        assert %User{} = result
        assert result.name == "Alice"

        # query!/3 is an alias for query_one!/3
        assert @sql_module.query!("first_user.sql", [], as: User) == result
      end
    end

    # ClickHouse tests (no sandbox support)
    test "clickhouse: returns single map" do
      result = ClickHouseSQL.query_one!("first_user.sql")

      assert result.id == 1
      assert result.name == "Alice"

      # query!/3 is an alias for query_one!/3
      assert ClickHouseSQL.query!("first_user.sql") == result
    end

    test "clickhouse: returns result with parameterized query" do
      result = ClickHouseSQL.query_one!("user_by_id.sql", %{id: 2})

      assert result.id == 2
      assert result.name == "Bob"

      # query!/3 is an alias for query_one!/3
      assert ClickHouseSQL.query!("user_by_id.sql", %{id: 2}) == result
    end

    test "clickhouse: raises NoResultsError when no rows" do
      assert_raise SqlKit.NoResultsError, ~r/expected at least one result/, fn ->
        ClickHouseSQL.query_one!("no_users.sql")
      end

      # query!/3 is an alias for query_one!/3
      assert_raise SqlKit.NoResultsError, fn ->
        ClickHouseSQL.query!("no_users.sql")
      end
    end

    test "clickhouse: raises MultipleResultsError when multiple rows" do
      assert_raise SqlKit.MultipleResultsError, ~r/got 3/, fn ->
        ClickHouseSQL.query_one!("all_users.sql")
      end

      # query!/3 is an alias for query_one!/3
      assert_raise SqlKit.MultipleResultsError, fn ->
        ClickHouseSQL.query!("all_users.sql")
      end
    end

    test "clickhouse: casts to struct with :as option" do
      result = ClickHouseSQL.query_one!("first_user.sql", [], as: User)

      assert %User{} = result
      assert result.name == "Alice"

      # query!/3 is an alias for query_one!/3
      assert ClickHouseSQL.query!("first_user.sql", [], as: User) == result
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

      {columns, rows} = SqlKit.extract_result(result)
      assert columns == ["id", "name"]
      assert [[1, "Alice"]] = rows
    end

    test "extracts columns and rows from MyXQL.Result" do
      result = MySQLRepo.query!("SELECT id, name FROM users WHERE id = ?", [1])
      assert %MyXQL.Result{} = result

      {columns, rows} = SqlKit.extract_result(result)
      assert columns == ["id", "name"]
      assert [[1, "Alice"]] = rows
    end

    test "extracts columns and rows from Exqlite.Result" do
      result = SQLiteRepo.query!("SELECT id, name FROM users WHERE id = ?", [1])
      assert %Exqlite.Result{} = result

      {columns, rows} = SqlKit.extract_result(result)
      assert columns == ["id", "name"]
      assert [[1, "Alice"]] = rows
    end

    test "extracts columns and rows from Tds.Result" do
      result = TdsRepo.query!("SELECT id, name FROM users WHERE id = @1", [1])
      assert %Tds.Result{} = result

      {columns, rows} = SqlKit.extract_result(result)
      assert columns == ["id", "name"]
      assert [[1, "Alice"]] = rows
    end

    test "extracts columns and rows from Ch.Result" do
      result = ClickHouseRepo.query!("SELECT id, name FROM users WHERE id = {id:UInt32}", %{id: 1})

      {columns, rows} = SqlKit.extract_result(result)
      assert columns == ["id", "name"]
      assert [[1, "Alice"]] = rows
    end

    test "raises for unsupported result type" do
      assert_raise ArgumentError, ~r/Unsupported query result type/, fn ->
        SqlKit.extract_result(%{cols: [], rows: []})
      end
    end
  end

  describe "transform_rows/3" do
    test "transforms columns and rows into list of maps" do
      columns = ["id", "name"]
      rows = [[1, "Alice"], [2, "Bob"]]

      result = SqlKit.transform_rows(columns, rows)

      assert result == [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    end

    test "returns empty list for empty rows" do
      columns = ["id", "name"]
      rows = []

      result = SqlKit.transform_rows(columns, rows)

      assert result == []
    end

    test "casts to struct with :as option" do
      columns = ["id", "name", "email", "age"]
      rows = [[1, "Alice", "alice@example.com", 30]]

      result = SqlKit.transform_rows(columns, rows, as: User)

      assert result == [%User{id: 1, name: "Alice", email: "alice@example.com", age: 30}]
    end

    test "raises ArgumentError for non-existent atoms by default" do
      columns = ["nonexistent_column_xyz"]
      rows = [["value"]]

      assert_raise ArgumentError, fn ->
        SqlKit.transform_rows(columns, rows)
      end
    end

    test "creates atoms dynamically with unsafe_atoms: true" do
      columns = ["dynamic_column_abc"]
      rows = [["value"]]

      result = SqlKit.transform_rows(columns, rows, unsafe_atoms: true)

      assert result == [%{dynamic_column_abc: "value"}]
    end

    test "handles multiple rows with struct casting" do
      columns = ["id", "name", "email", "age"]

      rows = [
        [1, "Alice", "alice@example.com", 30],
        [2, "Bob", "bob@example.com", 25]
      ]

      result = SqlKit.transform_rows(columns, rows, as: User)

      assert length(result) == 2
      assert Enum.all?(result, &match?(%User{}, &1))
      assert hd(result).name == "Alice"
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

        # query/3 is an alias for query_one/3
        assert {:ok, ^result} = @sql_module.query("first_user.sql")
      end

      test "#{adapter}: returns {:ok, nil} when no results" do
        assert {:ok, nil} = @sql_module.query_one("no_users.sql")

        # query/3 is an alias for query_one/3
        assert {:ok, nil} = @sql_module.query("no_users.sql")
      end

      test "#{adapter}: returns {:error, MultipleResultsError} when multiple results" do
        assert {:error, %SqlKit.MultipleResultsError{count: 3}} =
                 @sql_module.query_one("all_users.sql")

        # query/3 is an alias for query_one/3
        assert {:error, %SqlKit.MultipleResultsError{count: 3}} =
                 @sql_module.query("all_users.sql")
      end

      test "#{adapter}: returns {:error, exception} on query error" do
        assert {:error, %RuntimeError{}} = @sql_module.query_one("nonexistent.sql")

        # query/3 is an alias for query_one/3
        assert {:error, %RuntimeError{}} = @sql_module.query("nonexistent.sql")
      end

      test "#{adapter}: casts to struct with :as option" do
        assert {:ok, %User{name: "Alice"}} = @sql_module.query_one("first_user.sql", [], as: User)

        # query/3 is an alias for query_one/3
        assert {:ok, %User{name: "Alice"}} = @sql_module.query("first_user.sql", [], as: User)
      end
    end

    # ClickHouse tests (no sandbox support)
    test "clickhouse: returns {:ok, result} on exactly one result" do
      assert {:ok, result} = ClickHouseSQL.query_one("first_user.sql")
      assert result.id == 1
      assert result.name == "Alice"

      # query/3 is an alias for query_one/3
      assert {:ok, ^result} = ClickHouseSQL.query("first_user.sql")
    end

    test "clickhouse: returns {:ok, nil} when no results" do
      assert {:ok, nil} = ClickHouseSQL.query_one("no_users.sql")

      # query/3 is an alias for query_one/3
      assert {:ok, nil} = ClickHouseSQL.query("no_users.sql")
    end

    test "clickhouse: returns {:error, MultipleResultsError} when multiple results" do
      assert {:error, %SqlKit.MultipleResultsError{count: 3}} =
               ClickHouseSQL.query_one("all_users.sql")

      # query/3 is an alias for query_one/3
      assert {:error, %SqlKit.MultipleResultsError{count: 3}} =
               ClickHouseSQL.query("all_users.sql")
    end

    test "clickhouse: returns {:error, exception} on query error" do
      assert {:error, %RuntimeError{}} = ClickHouseSQL.query_one("nonexistent.sql")

      # query/3 is an alias for query_one/3
      assert {:error, %RuntimeError{}} = ClickHouseSQL.query("nonexistent.sql")
    end

    test "clickhouse: casts to struct with :as option" do
      assert {:ok, %User{name: "Alice"}} = ClickHouseSQL.query_one("first_user.sql", [], as: User)

      # query/3 is an alias for query_one/3
      assert {:ok, %User{name: "Alice"}} = ClickHouseSQL.query("first_user.sql", [], as: User)
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
          @moduledoc false
          use SqlKit,
            otp_app: :sql_kit,
            repo: PostgresRepo,
            dirname: "test_postgres",
            files: ["does_not_exist.sql"]
        end
      end
    end
  end

  # ============================================================================
  # Standalone Query Function Tests
  # ============================================================================

  # Helper to get the correct parameter placeholder for each adapter
  defp param_placeholder(:postgres, n), do: "$#{n}"
  defp param_placeholder(:mysql, _n), do: "?"
  defp param_placeholder(:sqlite, _n), do: "?"
  defp param_placeholder(:tds, n), do: "@#{n}"

  describe "SqlKit.query_all!/4 (standalone)" do
    for {adapter, _sql_module, repo} <- @sandbox_adapters do
      @repo repo
      @adapter adapter

      setup do
        setup_sandbox(@repo)
      end

      test "#{adapter}: executes SQL string directly" do
        results = SqlKit.query_all!(@repo, "SELECT * FROM users ORDER BY id")

        assert length(results) == 3
        assert hd(results).name == "Alice"
      end

      test "#{adapter}: supports parameterized queries" do
        placeholder = param_placeholder(@adapter, 1)
        results = SqlKit.query_all!(@repo, "SELECT * FROM users WHERE id = #{placeholder}", [1])

        assert length(results) == 1
        assert hd(results).name == "Alice"
      end

      test "#{adapter}: supports :as option for struct casting" do
        results = SqlKit.query_all!(@repo, "SELECT * FROM users ORDER BY id", [], as: User)

        assert length(results) == 3
        assert Enum.all?(results, &match?(%User{}, &1))
      end
    end
  end

  describe "SqlKit.query_one!/4 (standalone)" do
    for {adapter, _sql_module, repo} <- @sandbox_adapters do
      @repo repo
      @adapter adapter

      setup do
        setup_sandbox(@repo)
      end

      test "#{adapter}: returns single row as map" do
        placeholder = param_placeholder(@adapter, 1)
        result = SqlKit.query_one!(@repo, "SELECT * FROM users WHERE id = #{placeholder}", [1])

        assert result.id == 1
        assert result.name == "Alice"
      end

      test "#{adapter}: raises NoResultsError when no rows" do
        placeholder = param_placeholder(@adapter, 1)

        assert_raise SqlKit.NoResultsError, fn ->
          SqlKit.query_one!(@repo, "SELECT * FROM users WHERE id = #{placeholder}", [999])
        end
      end

      test "#{adapter}: raises MultipleResultsError when multiple rows" do
        assert_raise SqlKit.MultipleResultsError, fn ->
          SqlKit.query_one!(@repo, "SELECT * FROM users")
        end
      end

      test "#{adapter}: supports custom query_name in exceptions" do
        placeholder = param_placeholder(@adapter, 1)

        error =
          assert_raise SqlKit.NoResultsError, fn ->
            SqlKit.query_one!(@repo, "SELECT * FROM users WHERE id = #{placeholder}", [999], query_name: "get_user")
          end

        assert error.query == "get_user"
      end
    end
  end

  describe "SqlKit.query_all/4 (standalone non-bang)" do
    for {adapter, _sql_module, repo} <- @sandbox_adapters do
      @repo repo

      setup do
        setup_sandbox(@repo)
      end

      test "#{adapter}: returns {:ok, results} on success" do
        assert {:ok, results} = SqlKit.query_all(@repo, "SELECT * FROM users ORDER BY id")
        assert length(results) == 3
      end

      test "#{adapter}: returns {:error, exception} on query error" do
        assert {:error, _} = SqlKit.query_all(@repo, "SELECT * FROM nonexistent_table")
      end
    end
  end

  describe "SqlKit.query_one/4 (standalone non-bang)" do
    for {adapter, _sql_module, repo} <- @sandbox_adapters do
      @repo repo
      @adapter adapter

      setup do
        setup_sandbox(@repo)
      end

      test "#{adapter}: returns {:ok, result} on exactly one result" do
        placeholder = param_placeholder(@adapter, 1)
        assert {:ok, result} = SqlKit.query_one(@repo, "SELECT * FROM users WHERE id = #{placeholder}", [1])
        assert result.name == "Alice"
      end

      test "#{adapter}: returns {:ok, nil} when no results" do
        placeholder = param_placeholder(@adapter, 1)
        assert {:ok, nil} = SqlKit.query_one(@repo, "SELECT * FROM users WHERE id = #{placeholder}", [999])
      end

      test "#{adapter}: returns {:error, MultipleResultsError} when multiple results" do
        assert {:error, %SqlKit.MultipleResultsError{}} =
                 SqlKit.query_one(@repo, "SELECT * FROM users")
      end
    end
  end

  describe "SqlKit.query!/4 and SqlKit.query/4 aliases" do
    setup do
      setup_sandbox(PostgresRepo)
    end

    test "query!/4 is an alias for query_one!/4" do
      result1 = SqlKit.query!(PostgresRepo, "SELECT * FROM users WHERE id = $1", [1])
      result2 = SqlKit.query_one!(PostgresRepo, "SELECT * FROM users WHERE id = $1", [1])
      assert result1 == result2
    end

    test "query/4 is an alias for query_one/4" do
      {:ok, result1} = SqlKit.query(PostgresRepo, "SELECT * FROM users WHERE id = $1", [1])
      {:ok, result2} = SqlKit.query_one(PostgresRepo, "SELECT * FROM users WHERE id = $1", [1])
      assert result1 == result2
    end
  end
end
