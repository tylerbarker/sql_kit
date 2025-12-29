if Code.ensure_loaded?(Duckdbex) do
  defmodule SqlKit.DuckDB.Pool do
    @moduledoc """
    A supervised connection pool for DuckDB.

    This module manages a pool of DuckDB connections with proper lifecycle
    management. The database is opened once and shared across all connections
    in the pool, and is properly released when the pool terminates.

    ## Usage

    Add the pool to your application's supervision tree:

        children = [
          {SqlKit.DuckDB.Pool,
            name: MyApp.AnalyticsPool,
            database: "priv/analytics.duckdb",
            pool_size: 4}
        ]

    Then use the pool with SqlKit functions using the pool reference:

        pool = SqlKit.DuckDB.Pool.pool(MyApp.AnalyticsPool)
        SqlKit.query_all!(pool, "SELECT * FROM events", [])

    Or get the pool reference from start_link:

        {:ok, pool} = SqlKit.DuckDB.Pool.start_link(name: MyPool, database: ":memory:")
        SqlKit.query_all!(pool, "SELECT * FROM events", [])

    ## Options

    - `:name` - Required. The name to register the pool under (atom)
    - `:database` - Required. Path to database file or `":memory:"`
    - `:pool_size` - Number of connections. Default: 4
    - `:config` - Optional `Duckdbex.Config` struct for advanced configuration

    ## Architecture

    The pool is implemented as a supervision tree:
    - A Supervisor manages the overall lifecycle
    - A Database GenServer holds the database reference and releases it on terminate
    - A NimblePool manages the individual connections

    This ensures the database is properly released when the pool stops, avoiding
    resource leaks.

    ## Why Pool Connections?

    Based on DuckDB's concurrency model:
    - Each connection locks during query execution
    - Multiple connections enable parallel query execution
    - Connection reuse is critical - disconnecting loses the in-memory cache
    - Recommended: Pool of ~4 connections for typical workloads

    ## Pool Behavior

    - **Lazy initialization**: Connections are created on-demand when first checked out,
      not at pool startup. This avoids startup latency.
    - **Prepared statement caching**: The pool caches prepared statements per connection.
      Repeated queries with the same SQL skip the prepare step.
    - **Checkout timeout**: All checkout operations have a configurable timeout
      (default: 5000ms). If no connection is available within the timeout,
      a `NimblePool.TimeoutError` is raised.
    """

    use Supervisor

    alias SqlKit.DuckDB.Connection

    defstruct [:name, :pid]

    @type t :: %__MODULE__{name: atom(), pid: pid()}

    @default_pool_size 4

    @doc """
    Creates a pool reference struct from a pool name.

    Use this to get a reference that can be passed to SqlKit functions.

    ## Example

        pool = SqlKit.DuckDB.Pool.pool(MyApp.AnalyticsPool)
        SqlKit.query_all!(pool, "SELECT * FROM events", [])
    """
    @spec pool(atom()) :: t()
    def pool(name) when is_atom(name) do
      case Process.whereis(sup_name(name)) do
        nil -> raise "DuckDB pool #{inspect(name)} is not started"
        pid -> %__MODULE__{name: name, pid: pid}
      end
    end

    @doc """
    Returns a child specification for the pool.

    Used by supervisors to start the pool as part of a supervision tree.
    """
    def child_spec(opts) do
      name = Keyword.fetch!(opts, :name)

      %{
        id: name,
        start: {__MODULE__, :start_link, [opts]},
        type: :supervisor
      }
    end

    @doc """
    Starts the connection pool.

    Returns `{:ok, pool}` where `pool` is a struct that can be passed
    directly to SqlKit functions.

    ## Options

    - `:name` - Required. The name to register the pool under
    - `:database` - Required. Path to database file or `":memory:"`
    - `:pool_size` - Number of connections. Default: 4
    - `:config` - Optional `Duckdbex.Config` struct

    ## Note on In-Memory Databases

    For in-memory databases, all pool connections share the same database
    instance. This ensures data created on one connection is visible to others.
    """
    @spec start_link(keyword()) :: {:ok, t()} | {:error, term()}
    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)

      case Supervisor.start_link(__MODULE__, opts, name: sup_name(name)) do
        {:ok, sup_pid} ->
          {:ok, %__MODULE__{name: name, pid: sup_pid}}

        {:error, _} = error ->
          error
      end
    end

    @impl Supervisor
    def init(opts) do
      name = Keyword.fetch!(opts, :name)
      database = Keyword.fetch!(opts, :database)
      pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
      config = Keyword.get(opts, :config)

      children = [
        # Database holder - opens db and releases on terminate
        {__MODULE__.Database, name: db_name(name), database: database, config: config},
        # NimblePool for connection management
        %{
          id: name,
          start:
            {NimblePool, :start_link,
             [
               [
                 worker: {__MODULE__.Worker, db_name(name)},
                 pool_size: pool_size,
                 name: name
               ]
             ]}
        }
      ]

      # rest_for_one: if Database crashes, restart NimblePool too
      # This ensures workers always have a valid db reference
      Supervisor.init(children, strategy: :rest_for_one)
    end

    @doc """
    Executes a SQL query using prepared statement caching.

    Prepared statements are cached per connection in the pool. Repeated queries
    with the same SQL will reuse the prepared statement, skipping the prepare step.

    ## Options

    - `:cache` - Whether to use prepared statement caching. Default: `true`
    - `:timeout` - Checkout timeout in milliseconds. Default: `5000`

    ## Examples

        pool = SqlKit.DuckDB.Pool.pool(MyPool)
        SqlKit.DuckDB.Pool.query!(pool, "SELECT * FROM events WHERE id = $1", [1])
        # => {["id", "name"], [[1, "click"]]}

        # With custom timeout
        SqlKit.DuckDB.Pool.query!(pool, sql, params, timeout: 10_000)

    """
    @spec query!(t() | atom(), String.t(), list(), keyword()) ::
            {[String.t()], [[term()]]}
    def query!(pool, sql, params, opts \\ [])

    def query!(%__MODULE__{name: name}, sql, params, opts), do: query!(name, sql, params, opts)

    def query!(pool_name, sql, params, opts) when is_atom(pool_name) do
      cache_enabled = Keyword.get(opts, :cache, true)
      timeout = Keyword.get(opts, :timeout, 5000)

      # NimblePool.checkout!/4 callback must return {result, checkin_status} where:
      # - result: returned to caller
      # - checkin_status: :ok (healthy), :error (remove), or {:ok, new_state} (update)
      NimblePool.checkout!(
        pool_name,
        :checkout,
        fn _from, conn_state ->
          if cache_enabled do
            execute_cached!(conn_state, sql, params)
          else
            execute_uncached!(conn_state, sql, params)
          end
        end,
        timeout
      )
    end

    @doc """
    Executes a SQL query using prepared statement caching.

    Returns `{:ok, {columns, rows}}` on success, `{:error, reason}` on failure.

    See `query!/4` for options.
    """
    @spec query(t() | atom(), String.t(), list(), keyword()) ::
            {:ok, {[String.t()], [[term()]]}} | {:error, term()}
    def query(pool, sql, params, opts \\ []) do
      {:ok, query!(pool, sql, params, opts)}
    rescue
      e -> {:error, e}
    end

    # Execute with prepared statement caching.
    # Returns {result, {:ok, updated_state}} to update the worker's cache.
    defp execute_cached!(conn_state, sql, params) do
      %{conn: conn, prepared_cache: cache} = conn_state

      {stmt, updated_cache} =
        case Map.fetch(cache, sql) do
          {:ok, stmt} ->
            {stmt, cache}

          :error ->
            {:ok, stmt} = Duckdbex.prepare_statement(conn, sql)
            {stmt, Map.put(cache, sql, stmt)}
        end

      {:ok, result_ref} = execute_statement(stmt, params)
      columns = Duckdbex.columns(result_ref)
      rows = Duckdbex.fetch_all(result_ref)
      result = {columns, SqlKit.DuckDB.convert_hugeints(rows)}

      updated_state = %{conn_state | prepared_cache: updated_cache}
      {result, {:ok, updated_state}}
    end

    # Execute without caching.
    # Returns {result, :ok} to return connection unchanged.
    defp execute_uncached!(conn_state, sql, params) do
      %{conn: conn} = conn_state

      {:ok, result_ref} =
        if params == [] do
          Duckdbex.query(conn, sql)
        else
          Duckdbex.query(conn, sql, params)
        end

      columns = Duckdbex.columns(result_ref)
      rows = Duckdbex.fetch_all(result_ref)
      result = {columns, SqlKit.DuckDB.convert_hugeints(rows)}

      {result, :ok}
    end

    defp execute_statement(stmt, []), do: Duckdbex.execute_statement(stmt)
    defp execute_statement(stmt, params), do: Duckdbex.execute_statement(stmt, params)

    @doc """
    Checks out a connection from the pool and executes a function.

    The connection is automatically returned to the pool after the function
    completes, even if it raises an exception.

    Note: For queries, prefer using `query!/4` which supports prepared statement
    caching. Use `checkout!/2` for operations that need direct connection access.

    ## Options

    - `:timeout` - Checkout timeout in milliseconds. Default: `5000`

    ## Examples

        pool = SqlKit.DuckDB.Pool.pool(MyPool)
        SqlKit.DuckDB.Pool.checkout!(pool, fn conn ->
          SqlKit.DuckDB.query!(conn, "SELECT * FROM events", [])
        end)

    """
    @spec checkout!(t() | atom(), (Connection.t() -> result), keyword()) :: result
          when result: term()
    def checkout!(pool, fun, opts \\ [])

    def checkout!(%__MODULE__{name: name}, fun, opts), do: checkout!(name, fun, opts)

    def checkout!(pool_name, fun, opts) when is_atom(pool_name) and is_function(fun, 1) do
      timeout = Keyword.get(opts, :timeout, 5000)

      # NimblePool callback returns {result, checkin_status}
      # :ok means connection is healthy, return to pool unchanged
      NimblePool.checkout!(
        pool_name,
        :checkout,
        fn _from, conn_state ->
          conn = %Connection{db: conn_state.db, conn: conn_state.conn}
          result = fun.(conn)
          {result, :ok}
        end,
        timeout
      )
    end

    @doc """
    Executes a SQL query and streams results through a callback function.

    The connection is held for the duration of the callback, which receives
    a stream of result chunks. This is useful for processing large result
    sets without loading everything into memory.

    ## Options

    - `:timeout` - Checkout timeout in milliseconds. Default: `5000`

    ## Examples

        pool = SqlKit.DuckDB.Pool.pool(MyPool)

        # Process large result set in chunks
        SqlKit.DuckDB.Pool.with_stream!(pool, "SELECT * FROM large_table", [], fn stream ->
          stream
          |> Stream.flat_map(& &1)
          |> Enum.reduce(0, fn _row, count -> count + 1 end)
        end)
        # => 1000000

        # Take first 100 rows
        SqlKit.DuckDB.Pool.with_stream!(pool, "SELECT * FROM events", [], fn stream ->
          stream
          |> Stream.flat_map(& &1)
          |> Enum.take(100)
        end)

    ## Notes

    - The connection is checked out for the entire duration of the callback
    - The callback must fully consume or abandon the stream before returning
    - Hugeint values are automatically converted to Elixir integers

    """
    @spec with_stream!(t() | atom(), String.t(), list(), (Enumerable.t() -> result), keyword()) ::
            result
          when result: term()
    def with_stream!(pool, sql, params, fun, opts \\ [])

    def with_stream!(%__MODULE__{name: name}, sql, params, fun, opts) do
      with_stream!(name, sql, params, fun, opts)
    end

    def with_stream!(pool_name, sql, params, fun, opts) when is_atom(pool_name) and is_function(fun, 1) do
      timeout = Keyword.get(opts, :timeout, 5000)

      NimblePool.checkout!(
        pool_name,
        :checkout,
        fn _from, conn_state ->
          %{conn: conn} = conn_state

          {:ok, result_ref} =
            if params == [] do
              Duckdbex.query(conn, sql)
            else
              Duckdbex.query(conn, sql, params)
            end

          stream = build_chunk_stream(result_ref)
          result = fun.(stream)
          {result, :ok}
        end,
        timeout
      )
    end

    @doc """
    Like `with_stream!/5` but also provides column names to the callback.

    The callback receives `{columns, stream}` where `columns` is a list of
    column names and `stream` is the chunk stream.

    ## Options

    - `:timeout` - Checkout timeout in milliseconds. Default: `5000`

    ## Examples

        SqlKit.DuckDB.Pool.with_stream_and_columns!(pool, "SELECT * FROM users", [], fn {cols, stream} ->
          IO.inspect(cols)  # => ["id", "name", "age"]
          stream |> Stream.flat_map(& &1) |> Enum.to_list()
        end)

    """
    @spec with_stream_and_columns!(
            t() | atom(),
            String.t(),
            list(),
            ({[String.t()], Enumerable.t()} -> result),
            keyword()
          ) :: result
          when result: term()
    def with_stream_and_columns!(pool, sql, params, fun, opts \\ [])

    def with_stream_and_columns!(%__MODULE__{name: name}, sql, params, fun, opts) do
      with_stream_and_columns!(name, sql, params, fun, opts)
    end

    def with_stream_and_columns!(pool_name, sql, params, fun, opts) when is_atom(pool_name) and is_function(fun, 1) do
      timeout = Keyword.get(opts, :timeout, 5000)

      NimblePool.checkout!(
        pool_name,
        :checkout,
        fn _from, conn_state ->
          %{conn: conn} = conn_state

          {:ok, result_ref} =
            if params == [] do
              Duckdbex.query(conn, sql)
            else
              Duckdbex.query(conn, sql, params)
            end

          columns = Duckdbex.columns(result_ref)
          stream = build_chunk_stream(result_ref)
          result = fun.({columns, stream})
          {result, :ok}
        end,
        timeout
      )
    end

    # Builds a stream that fetches chunks from a result reference
    defp build_chunk_stream(result_ref) do
      Stream.resource(
        fn -> result_ref end,
        fn ref ->
          case Duckdbex.fetch_chunk(ref) do
            [] -> {:halt, ref}
            chunk -> {[SqlKit.DuckDB.convert_hugeints(chunk)], ref}
          end
        end,
        fn _ref -> :ok end
      )
    end

    # Private helpers for naming
    defp sup_name(name), do: Module.concat(name, Supervisor)
    defp db_name(name), do: Module.concat(name, Database)
  end

  defmodule SqlKit.DuckDB.Pool.Database do
    @moduledoc false
    # Internal GenServer that holds the DuckDB database reference.
    # Releases the database properly on terminate to avoid resource leaks.

    use GenServer

    def start_link(opts) do
      name = Keyword.fetch!(opts, :name)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    @doc """
    Gets the database reference from the holder.
    """
    def get_db(name), do: GenServer.call(name, :get_db)

    @impl GenServer
    def init(opts) do
      database = Keyword.fetch!(opts, :database)
      config = Keyword.get(opts, :config)

      case open_database(database, config) do
        {:ok, db} -> {:ok, db}
        {:error, reason} -> {:stop, reason}
      end
    end

    @impl GenServer
    def handle_call(:get_db, _from, db) do
      {:reply, db, db}
    end

    @impl GenServer
    def terminate(_reason, db) do
      Duckdbex.release(db)
    end

    defp open_database(database, nil), do: Duckdbex.open(database)
    defp open_database(database, config), do: Duckdbex.open(database, config)
  end

  defmodule SqlKit.DuckDB.Pool.Worker do
    @moduledoc false
    # NimblePool worker behaviour implementation.
    # Creates connections to the shared database managed by Database GenServer.
    #
    # Each worker maintains a prepared statement cache for repeated queries.
    # The cache stores SQL -> stmt_ref mappings, allowing subsequent executions
    # of the same SQL to skip the prepare step.

    @behaviour NimblePool

    alias SqlKit.DuckDB.Pool.Database

    @impl NimblePool
    def init_worker(db_name) do
      # Async initialization to avoid blocking pool startup
      {:async,
       fn ->
         db = Database.get_db(db_name)
         {:ok, conn} = Duckdbex.connection(db)
         %{db: db, conn: conn, prepared_cache: %{}}
       end, db_name}
    end

    @impl NimblePool
    def handle_checkout(:checkout, _from, conn_state, pool_state) do
      {:ok, conn_state, conn_state, pool_state}
    end

    @impl NimblePool
    def handle_checkin({:ok, updated_state}, _from, _conn_state, pool_state) do
      # Accept updated state (e.g., with new cached statements)
      {:ok, updated_state, pool_state}
    end

    def handle_checkin(:ok, _from, conn_state, pool_state) do
      {:ok, conn_state, pool_state}
    end

    def handle_checkin(:error, _from, _conn_state, pool_state) do
      # Connection had an error - remove it and let NimblePool create a new one
      {:remove, :connection_error, pool_state}
    end

    @impl NimblePool
    def terminate_worker(_reason, _conn_state, pool_state) do
      # Individual connections don't need explicit cleanup
      # The database is released by the Database GenServer
      # Prepared statement refs are cleaned up with the connection
      {:ok, pool_state}
    end
  end
end
