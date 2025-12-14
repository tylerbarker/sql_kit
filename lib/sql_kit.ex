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

  - `:otp_app` (required for file-based) - Your application name
  - `:repo` (required for file-based) - The Ecto repo module to use for queries
  - `:dirname` (required for file-based) - Subdirectory within root_sql_dir for this module's SQL files
  - `:files` (required for file-based) - List of SQL filenames to load
  """

  alias SqlKit.Config
  alias SqlKit.Helpers

  # ============================================================================
  # Standalone Query Functions
  # ============================================================================

  @doc """
  Executes a SQL query and returns all rows as a list of maps or structs.

  ## Options

  - `:as` - Struct module to cast results into
  - `:unsafe_atoms` - If `true`, uses `String.to_atom/1` instead of
    `String.to_existing_atom/1` for column names. Default: `false`

  ## Examples

      SqlKit.query_all!(MyApp.Repo, "SELECT * FROM users")
      # => [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

      SqlKit.query_all!(MyApp.Repo, "SELECT * FROM users WHERE age > $1", [21])
      # => [%{id: 1, name: "Alice", age: 30}]

      SqlKit.query_all!(MyApp.Repo, "SELECT * FROM users", [], as: User)
      # => [%User{id: 1, name: "Alice"}, %User{id: 2, name: "Bob"}]
  """
  @spec query_all!(Ecto.Repo.t(), String.t(), list() | map(), keyword()) :: [map() | struct()]
  def query_all!(repo, sql, params \\ [], opts \\ []) do
    SqlKit.Query.all!(repo, sql, params, opts)
  end

  @doc """
  Executes a SQL query and returns all rows as a list of maps or structs.

  Returns `{:ok, results}` on success, `{:error, exception}` on failure.

  ## Options

  - `:as` - Struct module to cast results into
  - `:unsafe_atoms` - If `true`, uses `String.to_atom/1` instead of
    `String.to_existing_atom/1` for column names. Default: `false`

  ## Examples

      SqlKit.query_all(MyApp.Repo, "SELECT * FROM users")
      # => {:ok, [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]}
  """
  @spec query_all(Ecto.Repo.t(), String.t(), list() | map(), keyword()) ::
          {:ok, [map() | struct()]} | {:error, term()}
  def query_all(repo, sql, params \\ [], opts \\ []) do
    SqlKit.Query.all(repo, sql, params, opts)
  end

  @doc """
  Executes a SQL query and returns exactly one row as a map or struct.

  Raises `SqlKit.NoResultsError` if no rows are returned.
  Raises `SqlKit.MultipleResultsError` if more than one row is returned.

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
  @spec query_one!(Ecto.Repo.t(), String.t(), list() | map(), keyword()) :: map() | struct()
  def query_one!(repo, sql, params \\ [], opts \\ []) do
    SqlKit.Query.one!(repo, sql, params, opts)
  end

  @doc """
  Executes a SQL query and returns one row as a map or struct.

  Returns `{:ok, result}` on exactly one result, `{:ok, nil}` on no results,
  or `{:error, exception}` on multiple results or other errors.

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
  @spec query_one(Ecto.Repo.t(), String.t(), list() | map(), keyword()) ::
          {:ok, map() | struct() | nil} | {:error, term()}
  def query_one(repo, sql, params \\ [], opts \\ []) do
    SqlKit.Query.one(repo, sql, params, opts)
  end

  @doc """
  Alias for `query_one!/4`. See `query_one!/4` documentation.
  """
  @spec query!(Ecto.Repo.t(), String.t(), list() | map(), keyword()) :: map() | struct()
  def query!(repo, sql, params \\ [], opts \\ []) do
    SqlKit.Query.one!(repo, sql, params, opts)
  end

  @doc """
  Alias for `query_one/4`. See `query_one/4` documentation.
  """
  @spec query(Ecto.Repo.t(), String.t(), list() | map(), keyword()) ::
          {:ok, map() | struct() | nil} | {:error, term()}
  def query(repo, sql, params \\ [], opts \\ []) do
    SqlKit.Query.one(repo, sql, params, opts)
  end

  # ============================================================================
  # File-Based Macro
  # ============================================================================

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    repo = Keyword.fetch!(opts, :repo)
    dirname = Keyword.fetch!(opts, :dirname)
    files = Keyword.fetch!(opts, :files)

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
      @repo unquote(repo)
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
        SqlKit.Query.all!(@repo, sql, params, opts)
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
