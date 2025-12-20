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
    Checks out a connection from the pool and executes a function.

    The connection is automatically returned to the pool after the function
    completes, even if it raises an exception.

    ## Examples

        pool = SqlKit.DuckDB.Pool.pool(MyPool)
        SqlKit.DuckDB.Pool.checkout!(pool, fn conn ->
          SqlKit.DuckDB.query!(conn, "SELECT * FROM events", [])
        end)

    """
    @spec checkout!(t() | atom(), (Connection.t() -> result)) :: result
          when result: term()
    def checkout!(%__MODULE__{name: name}, fun), do: checkout!(name, fun)

    def checkout!(pool_name, fun) when is_atom(pool_name) and is_function(fun, 1) do
      NimblePool.checkout!(pool_name, :checkout, fn _from, conn_state ->
        conn = %Connection{db: conn_state.db, conn: conn_state.conn}

        try do
          result = fun.(conn)
          {result, :ok}
        rescue
          e ->
            # Return connection as healthy - query errors don't mean connection is bad
            reraise e, __STACKTRACE__
        end
      end)
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

    @behaviour NimblePool

    alias SqlKit.DuckDB.Pool.Database

    @impl NimblePool
    def init_worker(db_name) do
      # Async initialization to avoid blocking pool startup
      {:async,
       fn ->
         db = Database.get_db(db_name)
         {:ok, conn} = Duckdbex.connection(db)
         %{db: db, conn: conn}
       end, db_name}
    end

    @impl NimblePool
    def handle_checkout(:checkout, _from, conn_state, pool_state) do
      {:ok, conn_state, conn_state, pool_state}
    end

    @impl NimblePool
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
      {:ok, pool_state}
    end
  end
end
