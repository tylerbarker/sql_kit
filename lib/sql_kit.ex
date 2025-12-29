# credo:disable-for-this-file Credo.Check.Refactor.LongQuoteBlocks
defmodule SqlKit do
  @moduledoc """
  Execute raw SQL in strings or .sql files, get maps and structs back.

  SqlKit provides two ways to execute SQL with automatic result transformation:

  ## Direct SQL Execution

  Execute SQL strings directly with any Ecto repo:

      SqlKit.query_all!(MyApp.Repo, "SELECT * FROM users WHERE age > $1", [21])
      # => [%{id: 1, name: "Alice", age: 30}, ...]

      SqlKit.query_one!(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [1], as: User)
      # => %User{id: 1, name: "Alice"}

  ## File-Based SQL

  For larger queries, keep SQL in dedicated files with compile-time embedding:

      defmodule MyApp.Reports.SQL do
        use SqlKit,
          otp_app: :my_app,
          repo: MyApp.Repo,
          dirname: "reports",
          files: ["stats.sql"]
      end

      MyApp.Reports.SQL.query_one!("stats.sql", [report_id])

  ### DuckDB File-Based SQL

  For DuckDB, use the `:backend` option instead of `:repo`. The pool must be
  started in your supervision tree with the database configuration:

      # In your application.ex supervision tree:
      children = [
        {SqlKit.DuckDB.Pool,
          name: MyApp.AnalyticsPool,
          database: "priv/analytics.duckdb",
          pool_size: 4}
      ]

      # Then define your SQL module:
      defmodule MyApp.Analytics.SQL do
        use SqlKit,
          otp_app: :my_app,
          backend: {:duckdb, pool: MyApp.AnalyticsPool},
          dirname: "analytics",
          files: ["daily_summary.sql"]
      end

      MyApp.Analytics.SQL.query_all!("daily_summary.sql", [~D[2024-01-01]])

  ## Supported Databases

  Any Ecto adapter returning a result map containing rows and columns should work.
  The test suite covers the following adapters:

  | Database   | Ecto Adapter              | Driver   |
  |------------|---------------------------|----------|
  | PostgreSQL | Ecto.Adapters.Postgres    | Postgrex |
  | SQLite     | Ecto.Adapters.SQLite3     | Exqlite  |
  | MySQL      | Ecto.Adapters.MyXQL       | MyXQL    |
  | MariaDB    | Ecto.Adapters.MyXQL       | MyXQL    |
  | SQL Server | Ecto.Adapters.Tds         | Tds      |
  | ClickHouse | Ecto.Adapters.ClickHouse  | Ch       |

  ## Configuration

      # config/config.exs
      config :my_app, SqlKit,
        root_sql_dir: "priv/repo/sql"  # default

      # config/dev.exs and config/test.exs
      config :my_app, SqlKit,
        load_sql: :dynamic  # read from disk at runtime

      # config/prod.exs (or rely on default)
      config :my_app, SqlKit,
        load_sql: :compiled  # use compile-time embedded SQL

  ## Options

  - `:otp_app` (required) - Your application name
  - `:repo` - The Ecto repo module to use for queries (required unless `:backend` is specified)
  - `:backend` - Alternative to `:repo` for non-Ecto databases. Currently supports:
    - `{:duckdb, pool: PoolName}` - Use a DuckDB connection pool
  - `:dirname` (required) - Subdirectory within root_sql_dir for this module's SQL files
  - `:files` (required) - List of SQL filenames to load

  Note: You must specify either `:repo` or `:backend`, but not both.
  """

  alias SqlKit.Config
  alias SqlKit.Helpers

  # ============================================================================
  # Standalone Query Functions
  # ============================================================================

  @typedoc """
  A backend for executing SQL queries.

  Can be:
  - An Ecto repo module (e.g., `MyApp.Repo`)
  - A `SqlKit.DuckDB.Connection` struct (for direct DuckDB connections)
  - A `SqlKit.DuckDB.Pool` name (atom) for pooled DuckDB connections
  """
  @type backend :: Ecto.Repo.t() | struct() | atom()

  @doc """
  Executes a SQL query and returns all rows as a list of maps or structs.

  ## Backend

  The first argument can be:
  - An Ecto repo module (e.g., `MyApp.Repo`)
  - A `SqlKit.DuckDB.Connection` struct
  - A `SqlKit.DuckDB.Pool` name (atom)

  ## Options

  - `:as` - Struct module to cast results into
  - `:unsafe_atoms` - If `true`, uses `String.to_atom/1` instead of
    `String.to_existing_atom/1` for column names. Default: `false`

  ## Examples

      # With Ecto repo
      SqlKit.query_all!(MyApp.Repo, "SELECT * FROM users")
      # => [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

      SqlKit.query_all!(MyApp.Repo, "SELECT * FROM users WHERE age > $1", [21])
      # => [%{id: 1, name: "Alice", age: 30}]

      SqlKit.query_all!(MyApp.Repo, "SELECT * FROM users", [], as: User)
      # => [%User{id: 1, name: "Alice"}, %User{id: 2, name: "Bob"}]

      # With DuckDB connection
      {:ok, conn} = SqlKit.DuckDB.connect(":memory:")
      SqlKit.query_all!(conn, "SELECT 1 as num", [])
      # => [%{num: 1}]

      # With DuckDB pool
      SqlKit.query_all!(MyApp.DuckDBPool, "SELECT * FROM events", [])
  """
  @spec query_all!(backend(), String.t(), list() | map(), keyword()) :: [map() | struct()]
  def query_all!(backend, sql, params \\ [], opts \\ []) do
    SqlKit.Query.all!(backend, sql, params, opts)
  end

  @doc """
  Executes a SQL query and returns all rows as a list of maps or structs.

  Returns `{:ok, results}` on success, `{:error, exception}` on failure.

  See `query_all!/4` for backend and options documentation.

  ## Examples

      SqlKit.query_all(MyApp.Repo, "SELECT * FROM users")
      # => {:ok, [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]}
  """
  @spec query_all(backend(), String.t(), list() | map(), keyword()) ::
          {:ok, [map() | struct()]} | {:error, term()}
  def query_all(backend, sql, params \\ [], opts \\ []) do
    SqlKit.Query.all(backend, sql, params, opts)
  end

  @doc """
  Executes a SQL query and returns exactly one row as a map or struct.

  Raises `SqlKit.NoResultsError` if no rows are returned.
  Raises `SqlKit.MultipleResultsError` if more than one row is returned.

  See `query_all!/4` for backend documentation.

  ## Options

  - `:as` - Struct module to cast result into
  - `:unsafe_atoms` - If `true`, uses `String.to_atom/1` instead of
    `String.to_existing_atom/1` for column names. Default: `false`
  - `:query_name` - Custom identifier for exceptions (defaults to truncated SQL)

  ## Examples

      SqlKit.query_one!(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [1])
      # => %{id: 1, name: "Alice"}

      SqlKit.query_one!(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [1], as: User)
      # => %User{id: 1, name: "Alice"}
  """
  @spec query_one!(backend(), String.t(), list() | map(), keyword()) :: map() | struct()
  def query_one!(backend, sql, params \\ [], opts \\ []) do
    SqlKit.Query.one!(backend, sql, params, opts)
  end

  @doc """
  Executes a SQL query and returns one row as a map or struct.

  Returns `{:ok, result}` on exactly one result, `{:ok, nil}` on no results,
  or `{:error, exception}` on multiple results or other errors.

  See `query_all!/4` for backend documentation.

  ## Options

  - `:as` - Struct module to cast result into
  - `:unsafe_atoms` - If `true`, uses `String.to_atom/1` instead of
    `String.to_existing_atom/1` for column names. Default: `false`
  - `:query_name` - Custom identifier for exceptions (defaults to truncated SQL)

  ## Examples

      SqlKit.query_one(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [1])
      # => {:ok, %{id: 1, name: "Alice"}}

      SqlKit.query_one(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [999])
      # => {:ok, nil}
  """
  @spec query_one(backend(), String.t(), list() | map(), keyword()) ::
          {:ok, map() | struct() | nil} | {:error, term()}
  def query_one(backend, sql, params \\ [], opts \\ []) do
    SqlKit.Query.one(backend, sql, params, opts)
  end

  @doc """
  Alias for `query_one!/4`. See `query_one!/4` documentation.
  """
  @spec query!(backend(), String.t(), list() | map(), keyword()) :: map() | struct()
  def query!(backend, sql, params \\ [], opts \\ []) do
    SqlKit.Query.one!(backend, sql, params, opts)
  end

  @doc """
  Alias for `query_one/4`. See `query_one/4` documentation.
  """
  @spec query(backend(), String.t(), list() | map(), keyword()) ::
          {:ok, map() | struct() | nil} | {:error, term()}
  def query(backend, sql, params \\ [], opts \\ []) do
    SqlKit.Query.one(backend, sql, params, opts)
  end

  # ============================================================================
  # File-Based Macro
  # ============================================================================

  # Validates backend configuration at compile time.
  # Returns {:ecto, repo_module} or {:duckdb, %{pool: pool_name}}
  @doc false
  def validate_backend_config!(opts, caller) do
    repo = Keyword.get(opts, :repo)
    backend = Keyword.get(opts, :backend)

    cond do
      repo != nil and backend != nil ->
        raise CompileError,
          description:
            "Cannot specify both :repo and :backend options. Use :repo for Ecto repos or :backend for DuckDB pools.",
          file: caller.file,
          line: caller.line

      repo != nil ->
        expanded_repo = Macro.expand(repo, caller)

        if not is_atom(expanded_repo) do
          raise CompileError,
            description: ":repo must be an atom (module name). Got: #{inspect(repo)}",
            file: caller.file,
            line: caller.line
        end

        {:ecto, expanded_repo}

      backend != nil ->
        validate_backend_option!(backend, caller)

      true ->
        raise CompileError,
          description: "Missing required option: either :repo or :backend must be specified.",
          file: caller.file,
          line: caller.line
    end
  end

  defp validate_backend_option!({:duckdb, duckdb_opts}, caller) when is_list(duckdb_opts) do
    pool = Keyword.get(duckdb_opts, :pool)

    if pool == nil do
      raise CompileError,
        description: "DuckDB backend requires :pool option. Example: backend: {:duckdb, pool: MyApp.DuckDBPool}",
        file: caller.file,
        line: caller.line
    end

    expanded_pool = Macro.expand(pool, caller)

    if not is_atom(expanded_pool) do
      raise CompileError,
        description: "DuckDB :pool must be an atom (module name). Got: #{inspect(pool)}",
        file: caller.file,
        line: caller.line
    end

    {:duckdb, %{pool: expanded_pool}}
  end

  defp validate_backend_option!(other, caller) do
    raise CompileError,
      description: "Invalid :backend option. Expected {:duckdb, pool: PoolName}, got: #{inspect(other)}",
      file: caller.file,
      line: caller.line
  end

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    dirname = Keyword.fetch!(opts, :dirname)
    files = Keyword.fetch!(opts, :files)

    # Validate backend configuration - either :repo or :backend required
    {backend_type, backend_config} = validate_backend_config!(opts, __CALLER__)

    # Build the SQL directory path at compile time
    root_sql_dir = Config.root_sql_dir(otp_app)
    sql_dir = Path.join(root_sql_dir, dirname)

    # Get the calling module for attribute registration
    calling_module = __CALLER__.module

    # Register and embed each SQL file as a module attribute
    for filename <- files do
      file_path = Path.join(sql_dir, filename)

      if File.exists?(file_path) do
        sql_atom = Helpers.file_atom(filename)
        sql_content = File.read!(file_path)

        Module.register_attribute(calling_module, sql_atom, persist: true)
        Module.put_attribute(calling_module, sql_atom, sql_content)
      else
        raise CompileError,
          description: "SQL file not found: #{filename} at #{file_path}",
          file: __CALLER__.file,
          line: __CALLER__.line
      end
    end

    quote do
      @otp_app unquote(otp_app)
      @backend_type unquote(backend_type)
      @backend_config unquote(Macro.escape(backend_config))
      @sql_dir unquote(sql_dir)

      @doc """
      Loads a SQL string from a file.

      In `:compiled` mode (default/production), returns the SQL embedded at compile time.
      In `:dynamic` mode (dev/test), reads the file from disk for latest changes.

      Returns `{:ok, sql}` on success, `{:error, reason}` on failure.
      """
      @spec load(filename :: String.t()) :: {:ok, String.t()} | {:error, term()}
      def load(filename) do
        {:ok, load!(filename)}
      rescue
        e -> {:error, e}
      end

      @doc """
      Loads a SQL string from a file.

      In `:compiled` mode (default/production), returns the SQL embedded at compile time.
      In `:dynamic` mode (dev/test), reads the file from disk for latest changes.

      Raises on error.
      """
      # sobelow_skip ["Traversal.FileModule"]
      @spec load!(filename :: String.t()) :: String.t()
      def load!(filename) do
        sql_atom = SqlKit.Helpers.file_atom(filename)

        # Verify the file was registered at compile time
        sql_content = __MODULE__.__info__(:attributes)[sql_atom]

        if sql_content == nil do
          raise "SQL file '#{filename}' was not included in the :files list for #{inspect(__MODULE__)}"
        end

        case SqlKit.Config.load_sql(@otp_app) do
          :compiled ->
            sql_content

          :dynamic ->
            path = Path.join(@sql_dir, filename)
            File.read!(path)
        end
      end

      @doc """
      Executes a SQL query and returns all rows as a list of maps.

      Returns `{:ok, results}` on success, `{:error, exception}` on failure.

      ## Options

      - `:as` - Struct module to cast results into
      - `:unsafe_atoms` - If `true`, uses `String.to_atom/1` instead of
        `String.to_existing_atom/1` for column names. Default: `false`

      ## Examples

          SQL.query_all("users.sql", [company_id])
          # => {:ok, [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]}

          # ClickHouse uses named parameters as a map
          ClickHouseSQL.query_all("users.sql", %{company_id: 123})
          # => {:ok, [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]}
      """
      @spec query_all(String.t(), list() | map(), keyword()) :: {:ok, [map() | struct()]} | {:error, term()}
      def query_all(filename, params \\ [], opts \\ []) do
        {:ok, query_all!(filename, params, opts)}
      rescue
        e -> {:error, e}
      end

      @doc """
      Executes a SQL query and returns all rows as a list of maps.

      Raises on error.

      ## Options

      - `:as` - Struct module to cast results into
      - `:unsafe_atoms` - If `true`, uses `String.to_atom/1` instead of
        `String.to_existing_atom/1` for column names. Default: `false`

      ## Examples

          SQL.query_all!("users.sql", [company_id])
          # => [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

          SQL.query_all!("users.sql", [company_id], as: User)
          # => [%User{id: 1, name: "Alice"}, %User{id: 2, name: "Bob"}]

          # ClickHouse uses named parameters as a map
          ClickHouseSQL.query_all!("users.sql", %{company_id: 123})
          # => [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
      """
      @spec query_all!(String.t(), list() | map(), keyword()) :: [map() | struct()]
      def query_all!(filename, params \\ [], opts \\ []) do
        sql = load!(filename)
        backend = get_backend()
        SqlKit.Query.all!(backend, sql, params, opts)
      end

      # Returns the configured backend for query execution.
      # For Ecto repos, returns the repo module.
      # For DuckDB pools, returns a pool reference struct.
      @doc false
      case @backend_type do
        :ecto ->
          def get_backend, do: @backend_config

        :duckdb ->
          @pool_name @backend_config.pool
          def get_backend, do: SqlKit.DuckDB.Pool.pool(@pool_name)
      end

      @doc """
      Executes a SQL query and returns a single row as a map or struct.

      Returns `{:ok, result}` on exactly one result, `{:ok, nil}` on no results,
      or `{:error, exception}` on multiple results or other errors.

      ## Options

      - `:as` - Struct module to cast result into
      - `:unsafe_atoms` - If `true`, uses `String.to_atom/1` instead of
        `String.to_existing_atom/1` for column names. Default: `false`

      ## Examples

          SQL.query_one("user.sql", [user_id])
          # => {:ok, %{id: 1, name: "Alice"}}

          SQL.query_one("missing.sql", [999])
          # => {:ok, nil}

          # ClickHouse uses named parameters as a map
          ClickHouseSQL.query_one("user.sql", %{user_id: 1})
          # => {:ok, %{id: 1, name: "Alice"}}
      """
      @spec query_one(String.t(), list() | map(), keyword()) ::
              {:ok, map() | struct() | nil} | {:error, term()}
      def query_one(filename, params \\ [], opts \\ []) do
        case query_all(filename, params, opts) do
          {:ok, []} ->
            {:ok, nil}

          {:ok, [row]} ->
            {:ok, row}

          {:ok, rows} ->
            {:error, SqlKit.MultipleResultsError.exception(filename: filename, count: length(rows))}

          {:error, _} = error ->
            error
        end
      end

      @doc """
      Executes a SQL query and returns a single row as a map or struct.

      Raises `SqlKit.NoResultsError` if no rows are returned.
      Raises `SqlKit.MultipleResultsError` if more than one row is returned.

      ## Options

      - `:as` - Struct module to cast result into
      - `:unsafe_atoms` - If `true`, uses `String.to_atom/1` instead of
        `String.to_existing_atom/1` for column names. Default: `false`

      ## Examples

          SQL.query_one!("user.sql", [user_id])
          # => %{id: 1, name: "Alice"}

          SQL.query_one!("user.sql", [user_id], as: User)
          # => %User{id: 1, name: "Alice"}

          # ClickHouse uses named parameters as a map
          ClickHouseSQL.query_one!("user.sql", %{user_id: 1})
          # => %{id: 1, name: "Alice"}
      """
      @spec query_one!(String.t(), list() | map(), keyword()) :: map() | struct()
      def query_one!(filename, params \\ [], opts \\ []) do
        case query_all!(filename, params, opts) do
          [] ->
            raise SqlKit.NoResultsError, filename: filename

          [row] ->
            row

          rows ->
            raise SqlKit.MultipleResultsError, filename: filename, count: length(rows)
        end
      end

      @doc """
      Alias for `query_one/3`. See `query_one/3` documentation.
      """
      @spec query(String.t(), list() | map(), keyword()) ::
              {:ok, map() | struct() | nil} | {:error, term()}
      defdelegate query(filename, params \\ [], opts \\ []), to: __MODULE__, as: :query_one

      @doc """
      Alias for `query_one!/3`. See `query_one!/3` documentation.
      """
      @spec query!(String.t(), list() | map(), keyword()) :: map() | struct()
      defdelegate query!(filename, params \\ [], opts \\ []), to: __MODULE__, as: :query_one!

      # DuckDB-specific streaming functions
      # Only defined when backend is :duckdb
      if @backend_type == :duckdb do
        @doc """
        Executes a SQL query and streams results through a callback function.

        Only available for DuckDB backends. The connection is held for the
        duration of the callback, which receives a stream of result chunks.

        ## Examples

            # Count rows without loading all into memory
            MyApp.Analytics.SQL.with_stream!("large_query.sql", [], fn stream ->
              stream
              |> Stream.flat_map(& &1)
              |> Enum.reduce(0, fn _row, count -> count + 1 end)
            end)

            # Process first 100 rows
            MyApp.Analytics.SQL.with_stream!("events.sql", [~D[2024-01-01]], fn stream ->
              stream
              |> Stream.flat_map(& &1)
              |> Enum.take(100)
            end)

        """
        @spec with_stream!(String.t(), list(), (Enumerable.t() -> result)) :: result
              when result: term()
        def with_stream!(filename, params \\ [], fun) do
          sql = load!(filename)
          pool = get_backend()
          SqlKit.DuckDB.Pool.with_stream!(pool, sql, params, fun)
        end

        @doc """
        Like `with_stream!/3` but also provides column names to the callback.

        The callback receives `{columns, stream}` where `columns` is a list of
        column names and `stream` is the chunk stream.

        ## Examples

            MyApp.Analytics.SQL.with_stream_and_columns!("users.sql", [], fn {cols, stream} ->
              IO.inspect(cols)  # => ["id", "name", "age"]
              stream |> Stream.flat_map(& &1) |> Enum.to_list()
            end)

        """
        @spec with_stream_and_columns!(
                String.t(),
                list(),
                ({[String.t()], Enumerable.t()} -> result)
              ) :: result
              when result: term()
        def with_stream_and_columns!(filename, params \\ [], fun) do
          sql = load!(filename)
          pool = get_backend()
          SqlKit.DuckDB.Pool.with_stream_and_columns!(pool, sql, params, fun)
        end
      end
    end
  end

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc false
  # Extracts columns and rows from an Ecto database driver result.
  @spec extract_result(struct() | map()) :: {[String.t()], [list()]}
  def extract_result(%{columns: columns, rows: rows}), do: {columns, rows}

  def extract_result(%{__struct__: struct}) do
    raise ArgumentError,
          "Unsupported query result type: #{inspect(struct)}."
  end

  def extract_result(other) do
    raise ArgumentError,
          "Unsupported query result type: #{inspect(other)}. "
  end

  @doc false
  # Transforms raw query result columns and rows into a list of maps or structs.
  # sobelow_skip ["DOS.StringToAtom"]
  @spec transform_rows([String.t()], [list()], keyword()) :: [map() | struct()]
  def transform_rows(columns, rows, opts \\ []) do
    unsafe_atoms = Keyword.get(opts, :unsafe_atoms, false)

    atom_columns =
      if unsafe_atoms do
        Enum.map(columns, &String.to_atom/1)
      else
        Enum.map(columns, &String.to_existing_atom/1)
      end

    struct_mod = Keyword.get(opts, :as)

    Enum.map(rows, fn row ->
      map =
        atom_columns
        |> Enum.zip(row)
        |> Map.new()

      if struct_mod do
        struct!(struct_mod, map)
      else
        map
      end
    end)
  end
end
