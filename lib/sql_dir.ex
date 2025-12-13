defmodule SqlDir do
  @moduledoc """
  Load SQL files at compile-time for production, read from disk in dev/test.

  SqlDir provides a clean API for working with raw SQL files in Phoenix/Ecto
  applications. SQL files are embedded in module attributes at compile time
  to avoid file I/O when calling query functions in production, while reading
  from disk in dev/test for rapid iteration.

  ## Supported Databases

  Any Ecto adapter returning a result map containing rows and columns should work.
  The test suite covers the following adapters:

  | Database   | Ecto Adapter              | Driver   |
  |------------|---------------------------|----------|
  | PostgreSQL | Ecto.Adapters.Postgres    | Postgrex |
  | MySQL      | Ecto.Adapters.MyXQL       | MyXQL    |
  | SQLite     | Ecto.Adapters.SQLite3     | Exqlite  |
  | SQL Server | Ecto.Adapters.Tds         | Tds      |
  | ClickHouse | Ecto.Adapters.ClickHouse  | Ch       |

  ## Usage

      defmodule MyApp.Reports.SQL do
        use SqlDir,
          otp_app: :my_app,
          repo: MyApp.Repo,
          dirname: "reports",
          files: ["stats.sql", "activity.sql"]
      end

      # Get raw SQL string
      MyApp.Reports.SQL.load!("stats.sql")

      # Execute and get single row as map
      MyApp.Reports.SQL.query_one!("stats.sql", [report_id])

      # Execute and get all rows as list of maps
      MyApp.Reports.SQL.query_all!("activity.sql", [company_id])

      # Cast results to structs
      MyApp.Reports.SQL.query_one!("stats.sql", [id], as: ReportStats)
      MyApp.Reports.SQL.query_all!("activity.sql", [id], as: Activity)

  ## Configuration

      # config/config.exs
      config :my_app, SqlDir,
        root_sql_dir: "priv/repo/sql"  # default

      # config/dev.exs and config/test.exs
      config :my_app, SqlDir,
        load_sql: :dynamic  # read from disk at runtime

      # config/prod.exs (or rely on default)
      config :my_app, SqlDir,
        load_sql: :compiled  # use compile-time embedded SQL

  ## Options

  - `:otp_app` (required) - Your application name
  - `:repo` (required) - The Ecto repo module to use for queries
  - `:dirname` (required) - Subdirectory within root_sql_dir for this module's SQL files
  - `:files` (required) - List of SQL filenames to load
  """

  alias SqlDir.Config
  alias SqlDir.Helpers

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
      @spec load!(filename :: String.t()) :: String.t()
      def load!(filename) do
        sql_atom = SqlDir.Helpers.file_atom(filename)

        # Verify the file was registered at compile time
        sql_content = __MODULE__.__info__(:attributes)[sql_atom]

        if sql_content == nil do
          raise "SQL file '#{filename}' was not included in the :files list for #{inspect(__MODULE__)}"
        end

        case SqlDir.Config.load_sql(@otp_app) do
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
      """
      @spec query_all(String.t(), list(), keyword()) :: {:ok, [map() | struct()]} | {:error, term()}
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
      """
      @spec query_all!(String.t(), list(), keyword()) :: [map() | struct()]
      def query_all!(filename, params \\ [], opts \\ []) do
        sql = load!(filename)
        result = @repo.query!(sql, params)
        {columns, rows} = SqlDir.extract_result(result)

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
      """
      @spec query_one(String.t(), list(), keyword()) ::
              {:ok, map() | struct() | nil} | {:error, term()}
      def query_one(filename, params \\ [], opts \\ []) do
        case query_all(filename, params, opts) do
          {:ok, []} ->
            {:ok, nil}

          {:ok, [row]} ->
            {:ok, row}

          {:ok, rows} ->
            {:error, SqlDir.MultipleResultsError.exception(filename: filename, count: length(rows))}

          {:error, _} = error ->
            error
        end
      end

      @doc """
      Executes a SQL query and returns a single row as a map or struct.

      Raises `SqlDir.NoResultsError` if no rows are returned.
      Raises `SqlDir.MultipleResultsError` if more than one row is returned.

      ## Options

      - `:as` - Struct module to cast result into
      - `:unsafe_atoms` - If `true`, uses `String.to_atom/1` instead of
        `String.to_existing_atom/1` for column names. Default: `false`

      ## Examples

          SQL.query_one!("user.sql", [user_id])
          # => %{id: 1, name: "Alice"}

          SQL.query_one!("user.sql", [user_id], as: User)
          # => %User{id: 1, name: "Alice"}
      """
      @spec query_one!(String.t(), list(), keyword()) :: map() | struct()
      def query_one!(filename, params \\ [], opts \\ []) do
        case query_all!(filename, params, opts) do
          [] ->
            raise SqlDir.NoResultsError, filename: filename

          [row] ->
            row

          rows ->
            raise SqlDir.MultipleResultsError, filename: filename, count: length(rows)
        end
      end
    end
  end

  @doc """
  Extracts columns and rows from an Ecto database driver result.
  """
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
end
