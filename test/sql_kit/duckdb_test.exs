defmodule SqlKit.DuckDBTest do
  use ExUnit.Case, async: true

  alias SqlKit.DuckDB
  alias SqlKit.DuckDB.Connection
  alias SqlKit.DuckDB.Pool
  alias SqlKit.Test.DuckDBSQL
  alias SqlKit.Test.User

  # Define atoms used in queries so to_existing_atom works
  _ = [:num, :name, :age, :value, :id, :greeting, :email]

  describe "SqlKit.DuckDB.connect/1" do
    test "connects to in-memory database" do
      assert {:ok, %Connection{}} = DuckDB.connect(":memory:")
    end

    test "connect! returns connection directly" do
      conn = DuckDB.connect!(":memory:")
      assert %Connection{} = conn
      assert :ok = DuckDB.disconnect(conn)
    end

    test "connects to file-based database" do
      path = Path.join(System.tmp_dir!(), "test_#{:erlang.unique_integer([:positive])}.duckdb")

      try do
        assert {:ok, %Connection{}} = DuckDB.connect(path)
        assert File.exists?(path)
      after
        File.rm(path)
      end
    end
  end

  describe "SqlKit.DuckDB.disconnect/1" do
    test "closes connection cleanly" do
      {:ok, conn} = DuckDB.connect(":memory:")
      assert :ok = DuckDB.disconnect(conn)
    end
  end

  describe "SqlKit.DuckDB.query/3" do
    setup do
      {:ok, conn} = DuckDB.connect(":memory:")
      on_exit(fn -> DuckDB.disconnect(conn) end)
      %{conn: conn}
    end

    test "executes simple SELECT", %{conn: conn} do
      assert {:ok, {["num"], [[1]]}} = DuckDB.query(conn, "SELECT 1 as num", [])
    end

    test "executes SELECT with multiple columns", %{conn: conn} do
      assert {:ok, {columns, rows}} = DuckDB.query(conn, "SELECT 1 as id, 'hello' as greeting", [])
      assert columns == ["id", "greeting"]
      assert rows == [[1, "hello"]]
    end

    test "executes parameterized query with integer", %{conn: conn} do
      # Note: DuckDB requires explicit cast for integer literals in params
      assert {:ok, {["num"], [[42]]}} = DuckDB.query(conn, "SELECT $1::INTEGER as num", [42])
    end

    test "handles multiple parameters", %{conn: conn} do
      assert {:ok, {columns, [[3, 2]]}} =
               DuckDB.query(conn, "SELECT $1::INTEGER + $2::INTEGER as sum, $1::INTEGER * $2::INTEGER as product", [1, 2])

      assert "sum" in columns
      assert "product" in columns
    end

    test "returns empty rows for no results", %{conn: conn} do
      DuckDB.query!(conn, "CREATE TABLE empty_test (id INTEGER)", [])
      assert {:ok, {["id"], []}} = DuckDB.query(conn, "SELECT id FROM empty_test", [])
    end

    test "handles NULL values", %{conn: conn} do
      assert {:ok, {["value"], [[nil]]}} = DuckDB.query(conn, "SELECT NULL as value", [])
    end

    test "handles boolean values", %{conn: conn} do
      assert {:ok, {_, [[true, false]]}} =
               DuckDB.query(conn, "SELECT true as t, false as f", [])
    end

    test "handles float values", %{conn: conn} do
      # DuckDB returns literal decimals as DECIMAL tuples {value, precision, scale}
      # Use CAST to get a proper DOUBLE
      assert {:ok, {["num"], [[3.14]]}} = DuckDB.query(conn, "SELECT CAST(3.14 AS DOUBLE) as num", [])
    end

    test "returns error for invalid SQL", %{conn: conn} do
      assert {:error, _} = DuckDB.query(conn, "INVALID SQL", [])
    end
  end

  describe "SqlKit.DuckDB.query!/3" do
    setup do
      {:ok, conn} = DuckDB.connect(":memory:")
      on_exit(fn -> DuckDB.disconnect(conn) end)
      %{conn: conn}
    end

    test "returns result directly on success", %{conn: conn} do
      assert {["num"], [[1]]} = DuckDB.query!(conn, "SELECT 1 as num", [])
    end

    test "raises on error", %{conn: conn} do
      assert_raise RuntimeError, ~r/DuckDB query failed/, fn ->
        DuckDB.query!(conn, "INVALID SQL", [])
      end
    end
  end

  describe "SqlKit standalone functions with DuckDB connection" do
    setup do
      {:ok, conn} = DuckDB.connect(":memory:")

      # Create and populate test table
      DuckDB.query!(conn, "CREATE TABLE users (id INTEGER, name VARCHAR, age INTEGER)", [])
      DuckDB.query!(conn, "INSERT INTO users VALUES (1, 'Alice', 30)", [])
      DuckDB.query!(conn, "INSERT INTO users VALUES (2, 'Bob', 25)", [])
      DuckDB.query!(conn, "INSERT INTO users VALUES (3, 'Charlie', 35)", [])

      on_exit(fn -> DuckDB.disconnect(conn) end)
      %{conn: conn}
    end

    test "query_all! returns list of maps", %{conn: conn} do
      results = SqlKit.query_all!(conn, "SELECT * FROM users ORDER BY id", [])

      assert length(results) == 3
      assert hd(results).id == 1
      assert hd(results).name == "Alice"
    end

    test "query_all! with parameters", %{conn: conn} do
      results = SqlKit.query_all!(conn, "SELECT * FROM users WHERE age > $1", [26])

      assert length(results) == 2
      names = Enum.map(results, & &1.name)
      assert "Alice" in names
      assert "Charlie" in names
    end

    test "query_all! with :as option", %{conn: conn} do
      results = SqlKit.query_all!(conn, "SELECT id, name, age FROM users ORDER BY id", [], as: User)

      assert length(results) == 3
      assert %User{id: 1, name: "Alice", age: 30} = hd(results)
    end

    test "query_all returns {:ok, results}", %{conn: conn} do
      assert {:ok, results} = SqlKit.query_all(conn, "SELECT * FROM users ORDER BY id", [])
      assert length(results) == 3
    end

    test "query_all returns {:error, _} on error", %{conn: conn} do
      assert {:error, _} = SqlKit.query_all(conn, "SELECT * FROM nonexistent", [])
    end

    test "query_one! returns single map", %{conn: conn} do
      result = SqlKit.query_one!(conn, "SELECT * FROM users WHERE id = $1", [1])

      assert result.id == 1
      assert result.name == "Alice"
    end

    test "query_one! raises NoResultsError", %{conn: conn} do
      assert_raise SqlKit.NoResultsError, fn ->
        SqlKit.query_one!(conn, "SELECT * FROM users WHERE id = $1", [999])
      end
    end

    test "query_one! raises MultipleResultsError", %{conn: conn} do
      assert_raise SqlKit.MultipleResultsError, fn ->
        SqlKit.query_one!(conn, "SELECT * FROM users", [])
      end
    end

    test "query_one returns {:ok, result}", %{conn: conn} do
      assert {:ok, result} = SqlKit.query_one(conn, "SELECT * FROM users WHERE id = $1", [1])
      assert result.name == "Alice"
    end

    test "query_one returns {:ok, nil} when no results", %{conn: conn} do
      assert {:ok, nil} = SqlKit.query_one(conn, "SELECT * FROM users WHERE id = $1", [999])
    end

    test "query!/4 is alias for query_one!/4", %{conn: conn} do
      result = SqlKit.query!(conn, "SELECT * FROM users WHERE id = $1", [1])
      assert result.name == "Alice"
    end

    test "query/4 is alias for query_one/4", %{conn: conn} do
      assert {:ok, result} = SqlKit.query(conn, "SELECT * FROM users WHERE id = $1", [1])
      assert result.name == "Alice"
    end
  end

  describe "SqlKit.DuckDB.Pool" do
    test "starts pool with in-memory database" do
      pool_name = :"test_pool_#{:erlang.unique_integer([:positive])}"

      {:ok, pool} = Pool.start_link(name: pool_name, database: ":memory:", pool_size: 2)
      assert %Pool{name: ^pool_name, pid: pid} = pool
      assert Process.alive?(pid)

      # Clean up - pid is the supervisor
      Supervisor.stop(pid)
    end

    test "checkout! executes function with connection" do
      pool_name = :"test_pool_#{:erlang.unique_integer([:positive])}"
      {:ok, pool} = Pool.start_link(name: pool_name, database: ":memory:", pool_size: 2)

      result =
        Pool.checkout!(pool, fn conn ->
          DuckDB.query!(conn, "SELECT 42 as num", [])
        end)

      assert {["num"], [[42]]} = result

      Supervisor.stop(pool.pid)
    end

    test "pool returns connection after checkout" do
      pool_name = :"test_pool_#{:erlang.unique_integer([:positive])}"
      {:ok, pool} = Pool.start_link(name: pool_name, database: ":memory:", pool_size: 1)

      # First checkout should work
      Pool.checkout!(pool, fn conn ->
        DuckDB.query!(conn, "SELECT 1", [])
      end)

      # Second checkout should also work (connection was returned)
      Pool.checkout!(pool, fn conn ->
        DuckDB.query!(conn, "SELECT 2", [])
      end)

      Supervisor.stop(pool.pid)
    end

    test "database is properly released when pool stops" do
      pool_name = :"test_pool_#{:erlang.unique_integer([:positive])}"
      {:ok, pool} = Pool.start_link(name: pool_name, database: ":memory:", pool_size: 1)

      # Use the pool
      Pool.checkout!(pool, fn conn ->
        DuckDB.query!(conn, "SELECT 1", [])
      end)

      # Stop the pool - this should release the database via terminate callback
      Supervisor.stop(pool.pid)

      # Verify the supervisor is stopped
      refute Process.alive?(pool.pid)

      # Verify the database holder is stopped
      db_holder_name = Module.concat(pool_name, Database)
      assert Process.whereis(db_holder_name) == nil
    end
  end

  describe "SqlKit standalone functions with DuckDB pool" do
    setup do
      pool_name = :"test_pool_#{:erlang.unique_integer([:positive])}"
      {:ok, pool} = Pool.start_link(name: pool_name, database: ":memory:", pool_size: 2)

      # Set up test data
      Pool.checkout!(pool, fn conn ->
        DuckDB.query!(conn, "CREATE TABLE users (id INTEGER, name VARCHAR, age INTEGER)", [])
        DuckDB.query!(conn, "INSERT INTO users VALUES (1, 'Alice', 30)", [])
        DuckDB.query!(conn, "INSERT INTO users VALUES (2, 'Bob', 25)", [])
        DuckDB.query!(conn, "INSERT INTO users VALUES (3, 'Charlie', 35)", [])
      end)

      on_exit(fn ->
        try do
          if Process.alive?(pool.pid), do: Supervisor.stop(pool.pid)
        catch
          :exit, _ -> :ok
        end
      end)

      %{pool: pool}
    end

    test "query_all! with pool", %{pool: pool} do
      results = SqlKit.query_all!(pool, "SELECT * FROM users ORDER BY id", [])

      assert length(results) == 3
      assert hd(results).name == "Alice"
    end

    test "query_all! with pool and parameters", %{pool: pool} do
      results = SqlKit.query_all!(pool, "SELECT * FROM users WHERE age > $1", [26])

      assert length(results) == 2
    end

    test "query_all! with pool and :as option", %{pool: pool} do
      results = SqlKit.query_all!(pool, "SELECT id, name, age FROM users ORDER BY id", [], as: User)

      assert length(results) == 3
      assert %User{id: 1, name: "Alice", age: 30} = hd(results)
    end

    test "query_one! with pool and :as option", %{pool: pool} do
      result = SqlKit.query_one!(pool, "SELECT id, name, age FROM users WHERE id = $1", [1], as: User)

      assert %User{id: 1, name: "Alice", age: 30} = result
    end

    test "query_one! with pool", %{pool: pool} do
      result = SqlKit.query_one!(pool, "SELECT * FROM users WHERE id = $1", [1])

      assert result.name == "Alice"
    end

    test "query_one! with pool raises NoResultsError", %{pool: pool} do
      assert_raise SqlKit.NoResultsError, fn ->
        SqlKit.query_one!(pool, "SELECT * FROM users WHERE id = $1", [999])
      end
    end

    test "query_all with pool returns {:ok, results}", %{pool: pool} do
      assert {:ok, results} = SqlKit.query_all(pool, "SELECT * FROM users ORDER BY id", [])
      assert length(results) == 3
    end

    test "query_one with pool returns {:ok, result}", %{pool: pool} do
      assert {:ok, result} = SqlKit.query_one(pool, "SELECT * FROM users WHERE id = $1", [1])
      assert result.name == "Alice"
    end

    test "query_one with pool returns {:ok, nil} when no results", %{pool: pool} do
      assert {:ok, nil} = SqlKit.query_one(pool, "SELECT * FROM users WHERE id = $1", [999])
    end
  end

  describe "DuckDB-specific features" do
    setup do
      {:ok, conn} = DuckDB.connect(":memory:")
      on_exit(fn -> DuckDB.disconnect(conn) end)
      %{conn: conn}
    end

    test "handles DATE type", %{conn: conn} do
      DuckDB.query!(conn, "CREATE TABLE dates (d DATE)", [])
      DuckDB.query!(conn, "INSERT INTO dates VALUES ('2024-01-15')", [])

      result = SqlKit.query_one!(conn, "SELECT d FROM dates", [])
      # DuckDB returns dates as tuples
      assert result.d == {2024, 1, 15}
    end

    test "handles TIMESTAMP type", %{conn: conn} do
      DuckDB.query!(conn, "CREATE TABLE timestamps (ts TIMESTAMP)", [])
      DuckDB.query!(conn, "INSERT INTO timestamps VALUES ('2024-01-15 10:30:00')", [])

      result = SqlKit.query_one!(conn, "SELECT ts FROM timestamps", [])
      # DuckDB returns timestamps as nested tuples
      assert {{2024, 1, 15}, {10, 30, 0, 0}} = result.ts
    end

    test "handles LIST type", %{conn: conn} do
      result = SqlKit.query_one!(conn, "SELECT [1, 2, 3] as nums", [], unsafe_atoms: true)
      assert result.nums == [1, 2, 3]
    end

    test "handles STRUCT type", %{conn: conn} do
      result =
        SqlKit.query_one!(conn, "SELECT {'name': 'Alice', 'age': 30} as person", [], unsafe_atoms: true)

      assert result.person == %{"age" => 30, "name" => "Alice"}
    end

    test "loads extensions via SQL", %{conn: conn} do
      # This just verifies the SQL-first approach works
      # INSTALL may fail if extension already installed, that's ok
      DuckDB.query(conn, "INSTALL 'json'", [])
      assert {:ok, _} = DuckDB.query(conn, "LOAD 'json'", [])
    end
  end

  describe "file-based database persistence" do
    setup do
      # Create a unique temp file path for each test
      path = Path.join(System.tmp_dir!(), "sqlkit_test_#{:erlang.unique_integer([:positive])}.duckdb")

      on_exit(fn ->
        # Clean up database files (DuckDB may create .wal files too)
        File.rm(path)
        File.rm(path <> ".wal")
      end)

      %{db_path: path}
    end

    test "data persists across direct connections", %{db_path: path} do
      # First connection: create table and insert data
      {:ok, conn1} = DuckDB.connect(path)
      DuckDB.query!(conn1, "CREATE TABLE persistence_test (id INTEGER, value VARCHAR)", [])
      DuckDB.query!(conn1, "INSERT INTO persistence_test VALUES (1, 'hello')", [])
      DuckDB.query!(conn1, "INSERT INTO persistence_test VALUES (2, 'world')", [])
      DuckDB.disconnect(conn1)

      # Second connection: verify data persisted
      {:ok, conn2} = DuckDB.connect(path)
      results = SqlKit.query_all!(conn2, "SELECT * FROM persistence_test ORDER BY id", [])

      assert length(results) == 2
      assert Enum.at(results, 0).id == 1
      assert Enum.at(results, 0).value == "hello"
      assert Enum.at(results, 1).id == 2
      assert Enum.at(results, 1).value == "world"

      DuckDB.disconnect(conn2)
    end

    test "queries work with file-based pool", %{db_path: path} do
      pool_name = :"file_pool_#{:erlang.unique_integer([:positive])}"
      {:ok, pool} = Pool.start_link(name: pool_name, database: path, pool_size: 2)

      # Create table and insert data via pool
      Pool.checkout!(pool, fn conn ->
        DuckDB.query!(conn, "CREATE TABLE pool_file_test (id INTEGER, name VARCHAR)", [])
        DuckDB.query!(conn, "INSERT INTO pool_file_test VALUES (1, 'Alice')", [])
        DuckDB.query!(conn, "INSERT INTO pool_file_test VALUES (2, 'Bob')", [])
      end)

      # Query via SqlKit API
      results = SqlKit.query_all!(pool, "SELECT * FROM pool_file_test ORDER BY id", [])

      assert length(results) == 2
      assert hd(results).name == "Alice"

      Supervisor.stop(pool.pid)
    end

    test "pool data persists across restarts", %{db_path: path} do
      pool_name = :"persist_pool_#{:erlang.unique_integer([:positive])}"

      # First pool: create and populate
      {:ok, pool1} = Pool.start_link(name: pool_name, database: path, pool_size: 2)

      Pool.checkout!(pool1, fn conn ->
        DuckDB.query!(conn, "CREATE TABLE restart_test (id INTEGER, data VARCHAR)", [])
        DuckDB.query!(conn, "INSERT INTO restart_test VALUES (1, 'persisted')", [])
      end)

      # Verify data is there
      result1 = SqlKit.query_one!(pool1, "SELECT * FROM restart_test WHERE id = $1", [1])
      assert result1.data == "persisted"

      # Stop the pool completely
      Supervisor.stop(pool1.pid)

      # Verify pool is stopped
      refute Process.alive?(pool1.pid)

      # Start a new pool with the same database file
      {:ok, pool2} = Pool.start_link(name: pool_name, database: path, pool_size: 2)

      # Data should still be there
      result2 = SqlKit.query_one!(pool2, "SELECT * FROM restart_test WHERE id = $1", [1])
      assert result2.data == "persisted"

      # Can also insert more data
      Pool.checkout!(pool2, fn conn ->
        DuckDB.query!(conn, "INSERT INTO restart_test VALUES (2, 'new_data')", [])
      end)

      results = SqlKit.query_all!(pool2, "SELECT * FROM restart_test ORDER BY id", [])
      assert length(results) == 2

      Supervisor.stop(pool2.pid)
    end

    test "file-based pool with :as option", %{db_path: path} do
      pool_name = :"as_pool_#{:erlang.unique_integer([:positive])}"
      {:ok, pool} = Pool.start_link(name: pool_name, database: path, pool_size: 2)

      Pool.checkout!(pool, fn conn ->
        DuckDB.query!(conn, "CREATE TABLE users (id INTEGER, name VARCHAR, age INTEGER)", [])
        DuckDB.query!(conn, "INSERT INTO users VALUES (1, 'Alice', 30)", [])
      end)

      result = SqlKit.query_one!(pool, "SELECT id, name, age FROM users WHERE id = $1", [1], as: User)
      assert %User{id: 1, name: "Alice", age: 30} = result

      Supervisor.stop(pool.pid)
    end
  end

  describe "file-based SQL with DuckDB" do
    # These tests use the SqlKit.Test.DuckDBSQL module defined in test_sql_modules.ex
    # which uses `backend: {:duckdb, pool: SqlKit.Test.DuckDBPool}`

    setup do
      pool_name = SqlKit.Test.DuckDBPool
      {:ok, pool} = Pool.start_link(name: pool_name, database: ":memory:", pool_size: 2)

      # Set up test data matching the other database tests
      Pool.checkout!(pool, fn conn ->
        DuckDB.query!(conn, "CREATE TABLE users (id INTEGER, name VARCHAR, email VARCHAR, age INTEGER)", [])
        DuckDB.query!(conn, "INSERT INTO users VALUES (1, 'Alice', 'alice@test.com', 30)", [])
        DuckDB.query!(conn, "INSERT INTO users VALUES (2, 'Bob', 'bob@test.com', 25)", [])
        DuckDB.query!(conn, "INSERT INTO users VALUES (3, 'Charlie', 'charlie@test.com', 35)", [])
      end)

      on_exit(fn ->
        try do
          if Process.alive?(pool.pid), do: Supervisor.stop(pool.pid)
        catch
          :exit, _ -> :ok
        end
      end)

      %{pool: pool}
    end

    test "load! returns SQL content", _context do
      sql = DuckDBSQL.load!("all_users.sql")
      assert sql =~ "SELECT"
      assert sql =~ "FROM users"
    end

    test "load returns {:ok, sql}", _context do
      assert {:ok, sql} = DuckDBSQL.load("all_users.sql")
      assert sql =~ "SELECT"
    end

    test "query_all! returns all rows", _context do
      results = DuckDBSQL.query_all!("all_users.sql")

      assert length(results) == 3
      assert hd(results).name == "Alice"
    end

    test "query_all! with :as option", _context do
      results = DuckDBSQL.query_all!("all_users.sql", [], as: User)

      assert length(results) == 3
      assert %User{id: 1, name: "Alice", email: "alice@test.com", age: 30} = hd(results)
    end

    test "query_all! with parameters", _context do
      results = DuckDBSQL.query_all!("users_by_age_range.sql", [26, 40])

      assert length(results) == 2
      names = Enum.map(results, & &1.name)
      assert "Alice" in names
      assert "Charlie" in names
    end

    test "query_all returns {:ok, results}", _context do
      assert {:ok, results} = DuckDBSQL.query_all("all_users.sql")
      assert length(results) == 3
    end

    test "query_one! returns single row", _context do
      result = DuckDBSQL.query_one!("first_user.sql")

      assert result.id == 1
      assert result.name == "Alice"
    end

    test "query_one! with parameter", _context do
      result = DuckDBSQL.query_one!("user_by_id.sql", [2])

      assert result.id == 2
      assert result.name == "Bob"
    end

    test "query_one! with :as option", _context do
      result = DuckDBSQL.query_one!("user_by_id.sql", [1], as: User)

      assert %User{id: 1, name: "Alice", email: "alice@test.com", age: 30} = result
    end

    test "query_one! raises NoResultsError for no matches", _context do
      assert_raise SqlKit.NoResultsError, fn ->
        DuckDBSQL.query_one!("no_users.sql")
      end
    end

    test "query_one! raises MultipleResultsError for multiple matches", _context do
      assert_raise SqlKit.MultipleResultsError, fn ->
        DuckDBSQL.query_one!("all_users.sql")
      end
    end

    test "query_one returns {:ok, result}", _context do
      assert {:ok, result} = DuckDBSQL.query_one("first_user.sql")
      assert result.name == "Alice"
    end

    test "query_one returns {:ok, nil} for no results", _context do
      assert {:ok, nil} = DuckDBSQL.query_one("no_users.sql")
    end

    test "query!/3 is alias for query_one!/3", _context do
      result = DuckDBSQL.query!("user_by_id.sql", [1])
      assert result.name == "Alice"
    end

    test "query/3 is alias for query_one/3", _context do
      assert {:ok, result} = DuckDBSQL.query("user_by_id.sql", [1])
      assert result.name == "Alice"
    end
  end

  describe "file-based SQL with persistent database" do
    setup do
      path = Path.join(System.tmp_dir!(), "sqlkit_filebased_#{:erlang.unique_integer([:positive])}.duckdb")

      on_exit(fn ->
        File.rm(path)
        File.rm(path <> ".wal")
      end)

      %{db_path: path}
    end

    test "queries work with file-based pool and data persists across restarts", %{db_path: path} do
      pool_name = SqlKit.Test.DuckDBPool

      # Start pool with file-based database
      {:ok, pool} = Pool.start_link(name: pool_name, database: path, pool_size: 2)

      # Set up test data
      Pool.checkout!(pool, fn conn ->
        DuckDB.query!(conn, "CREATE TABLE users (id INTEGER, name VARCHAR, email VARCHAR, age INTEGER)", [])
        DuckDB.query!(conn, "INSERT INTO users VALUES (1, 'Alice', 'alice@test.com', 30)", [])
        DuckDB.query!(conn, "INSERT INTO users VALUES (2, 'Bob', 'bob@test.com', 25)", [])
        DuckDB.query!(conn, "INSERT INTO users VALUES (3, 'Charlie', 'charlie@test.com', 35)", [])
      end)

      # Query using file-based SQL module
      results = DuckDBSQL.query_all!("all_users.sql")
      assert length(results) == 3
      assert hd(results).name == "Alice"

      # Query with parameters
      result = DuckDBSQL.query_one!("user_by_id.sql", [2])
      assert result.name == "Bob"

      # Stop the pool completely
      Supervisor.stop(pool.pid)
      refute Process.alive?(pool.pid)

      # Start a new pool with the same database file
      {:ok, pool2} = Pool.start_link(name: pool_name, database: path, pool_size: 2)

      # Data should still be there - query using file-based SQL module
      results2 = DuckDBSQL.query_all!("all_users.sql")
      assert length(results2) == 3

      # Verify specific queries still work
      result2 = DuckDBSQL.query_one!("user_by_id.sql", [3])
      assert result2.name == "Charlie"

      # Test with :as option after restart
      users = DuckDBSQL.query_all!("all_users.sql", [], as: User)
      assert length(users) == 3
      assert %User{id: 1, name: "Alice"} = hd(users)

      Supervisor.stop(pool2.pid)
    end
  end
end
