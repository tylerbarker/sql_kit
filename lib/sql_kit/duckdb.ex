if Code.ensure_loaded?(Duckdbex) do
  defmodule SqlKit.DuckDB do
    @moduledoc """
    DuckDB support for SqlKit.

    Provides two ways to use DuckDB with SqlKit:

    ## Direct Connection (BYO)

    For simple use cases, scripts, or explicit control:

        {:ok, conn} = SqlKit.DuckDB.connect(":memory:")
        SqlKit.query_all(conn, "SELECT 1 as num", [])
        # => [%{num: 1}]
        SqlKit.DuckDB.disconnect(conn)

    ## Pooled Connection (Recommended for Production)

    For production use, add the pool to your supervision tree:

        children = [
          {SqlKit.DuckDB.Pool,
            name: MyApp.AnalyticsPool,
            database: "priv/analytics.duckdb",
            pool_size: 4}
        ]

        # Then use the pool name with SqlKit functions
        SqlKit.query_all(MyApp.AnalyticsPool, "SELECT * FROM events", [])

    ## Loading Extensions

    DuckDB extensions are loaded via SQL (SQL-first philosophy):

        SqlKit.query!(conn, "INSTALL 'parquet';", [])
        SqlKit.query!(conn, "LOAD 'parquet';", [])
        SqlKit.query_all(conn, "SELECT * FROM 'data.parquet'", [])

    ## Notes

    - Uses PostgreSQL-style `$1, $2, ...` parameter placeholders
    - In-memory database: use `":memory:"` string (not `:memory` atom)
    - Hugeint values are automatically converted to Elixir integers
    """

    defmodule Connection do
      @moduledoc """
      Struct representing a DuckDB connection.

      Contains references to the database and connection that are managed
      by duckdbex NIFs. Use `SqlKit.DuckDB.connect/1,2` to create and
      `SqlKit.DuckDB.disconnect/1` to close.
      """
      defstruct [:db, :conn]

      @type t :: %__MODULE__{
              db: reference(),
              conn: reference()
            }
    end

    @type connect_opts :: [config: struct()]

    @doc """
    Opens a DuckDB database and creates a connection.

    ## Arguments

    - `database` - Path to database file or `":memory:"` for in-memory database

    ## Options

    - `:config` - A `Duckdbex.Config` struct for advanced configuration

    ## Examples

        # In-memory database
        {:ok, conn} = SqlKit.DuckDB.connect(":memory:")

        # File-based database
        {:ok, conn} = SqlKit.DuckDB.connect("analytics.duckdb")

        # With configuration
        {:ok, conn} = SqlKit.DuckDB.connect("analytics.duckdb",
          config: %Duckdbex.Config{threads: 4})

    """
    @spec connect(String.t(), connect_opts()) :: {:ok, Connection.t()} | {:error, term()}
    def connect(database, opts \\ []) do
      config = Keyword.get(opts, :config)

      with {:ok, db} <- open_database(database, config),
           {:ok, conn} <- Duckdbex.connection(db) do
        {:ok, %Connection{db: db, conn: conn}}
      end
    end

    @doc """
    Opens a DuckDB database and creates a connection. Raises on error.

    See `connect/2` for options.
    """
    @spec connect!(String.t(), connect_opts()) :: Connection.t()
    def connect!(database, opts \\ []) do
      case connect(database, opts) do
        {:ok, conn} -> conn
        {:error, reason} -> raise "Failed to connect to DuckDB: #{inspect(reason)}"
      end
    end

    @doc """
    Closes a DuckDB connection and releases the database.

    ## Examples

        {:ok, conn} = SqlKit.DuckDB.connect(":memory:")
        :ok = SqlKit.DuckDB.disconnect(conn)

    """
    @spec disconnect(Connection.t()) :: :ok
    def disconnect(%Connection{db: db}) do
      # Release the database (this releases associated connections)
      Duckdbex.release(db)
      :ok
    end

    @doc """
    Executes a SQL query and returns columns and rows.

    This is a low-level function. Users should typically use
    `SqlKit.query_all/3`, `SqlKit.query_one!/3`, etc. instead.

    ## Examples

        {:ok, {columns, rows}} = SqlKit.DuckDB.query(conn, "SELECT 1 as num", [])
        # => {:ok, {["num"], [[1]]}}

    """
    @spec query(Connection.t(), String.t(), list()) ::
            {:ok, {[String.t()], [[term()]]}} | {:error, term()}
    def query(%Connection{conn: conn}, sql, params) do
      with {:ok, result_ref} <- execute_query(conn, sql, params) do
        columns = Duckdbex.columns(result_ref)
        rows = Duckdbex.fetch_all(result_ref)
        {:ok, {columns, convert_hugeints(rows)}}
      end
    end

    @doc """
    Executes a SQL query and returns columns and rows. Raises on error.

    See `query/3` for details.
    """
    # sobelow_skip ["SQL.Query"]
    @spec query!(Connection.t(), String.t(), list()) :: {[String.t()], [[term()]]}
    def query!(%Connection{} = conn, sql, params) do
      case query(conn, sql, params) do
        {:ok, result} -> result
        {:error, reason} -> raise "DuckDB query failed: #{inspect(reason)}"
      end
    end

    # ============================================================================
    # Streaming (Large Result Sets)
    # ============================================================================

    @doc """
    Executes a SQL query and returns a stream of result chunks.

    Unlike `query!/3` which loads all results into memory, `stream!/3` returns
    a lazy `Stream` that fetches results in chunks. This is useful for large
    result sets that would otherwise consume too much memory.

    Each chunk is a list of rows (each row is a list of values). Use
    `Stream.flat_map/2` to iterate over individual rows.

    ## Examples

        # Stream large result set
        conn
        |> SqlKit.DuckDB.stream!("SELECT * FROM large_table", [])
        |> Stream.flat_map(& &1)
        |> Enum.take(100)

        # With column names (first element of tuple)
        {columns, row_stream} = SqlKit.DuckDB.stream_with_columns!(conn, sql, [])
        rows = row_stream |> Stream.flat_map(& &1) |> Enum.to_list()

    ## Notes

    - The connection is held for the duration of stream consumption
    - Hugeint values are automatically converted to Elixir integers
    - For pooled connections, use `SqlKit.DuckDB.Pool.with_stream!/5`

    """
    @spec stream!(Connection.t(), String.t(), list()) :: Enumerable.t()
    def stream!(%Connection{conn: conn}, sql, params) do
      {:ok, result_ref} = execute_query(conn, sql, params)
      build_chunk_stream(result_ref)
    end

    @doc """
    Like `stream!/3` but also returns column names.

    Returns `{columns, row_chunk_stream}` where `columns` is a list of column
    names and `row_chunk_stream` is a stream of row chunks.

    ## Examples

        {columns, stream} = SqlKit.DuckDB.stream_with_columns!(conn, "SELECT * FROM users", [])
        # columns => ["id", "name", "age"]
        rows = stream |> Stream.flat_map(& &1) |> Enum.to_list()

    """
    @spec stream_with_columns!(Connection.t(), String.t(), list()) ::
            {[String.t()], Enumerable.t()}
    def stream_with_columns!(%Connection{conn: conn}, sql, params) do
      {:ok, result_ref} = execute_query(conn, sql, params)
      columns = Duckdbex.columns(result_ref)
      {columns, build_chunk_stream(result_ref)}
    end

    # Builds a stream that fetches chunks from a result reference
    defp build_chunk_stream(result_ref) do
      Stream.resource(
        fn -> result_ref end,
        fn ref ->
          case Duckdbex.fetch_chunk(ref) do
            # Empty chunk means end of results
            [] -> {:halt, ref}
            chunk -> {[convert_hugeints(chunk)], ref}
          end
        end,
        fn _ref -> :ok end
      )
    end

    # ============================================================================
    # Hugeint Conversion (Public - used by Pool)
    # ============================================================================

    @doc """
    Converts hugeint tuples to integers in result rows.

    Duckdbex represents HUGEINT (128-bit integers) as `{upper, lower}` tuples.
    This function recursively converts all such tuples to Elixir integers.

    This is safe because other duckdbex tuple types have different arities:
    - DATE: `{year, month, day}`
    - TIME: `{hour, minute, second, microsecond}`
    - DECIMAL: `{value, precision, scale}`
    - TIMESTAMP: `{{y, m, d}, {h, m, s, us}}`

    If duckdbex adds another 2-integer-tuple type in the future, this would
    need to be updated. Check duckdbex changelog on upgrades.
    """
    @spec convert_hugeints([[term()]]) :: [[term()]]
    def convert_hugeints(rows) do
      Enum.map(rows, fn row ->
        Enum.map(row, &convert_value/1)
      end)
    end

    @doc """
    Converts a single value, handling hugeint tuples.

    See `convert_hugeints/1` for details.
    """
    @spec convert_value(term()) :: term()
    def convert_value({upper, lower}) when is_integer(upper) and is_integer(lower) do
      Duckdbex.hugeint_to_integer({upper, lower})
    end

    def convert_value(value), do: value

    # ============================================================================
    # Private Functions
    # ============================================================================

    defp open_database(database, nil), do: Duckdbex.open(database)
    defp open_database(database, config), do: Duckdbex.open(database, config)

    defp execute_query(conn, sql, []), do: Duckdbex.query(conn, sql)
    defp execute_query(conn, sql, params), do: Duckdbex.query(conn, sql, params)
  end
end
