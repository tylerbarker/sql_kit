defmodule SqlDir.Adapter do
  @moduledoc """
  Behaviour for extracting columns and rows from database driver results.

  SqlDir supports multiple database adapters. Each adapter implements this
  behaviour to normalize the result structure from different drivers.

  ## Supported Adapters

  | Database   | Ecto Adapter           | SqlDir Adapter          |
  |------------|------------------------|-------------------------|
  | PostgreSQL | Ecto.Adapters.Postgres | SqlDir.Adapters.Postgrex |
  | MySQL      | Ecto.Adapters.MyXQL    | SqlDir.Adapters.MyXQL    |
  | SQLite     | Ecto.Adapters.SQLite3  | SqlDir.Adapters.Exqlite  |
  | SQL Server | Ecto.Adapters.Tds      | SqlDir.Adapters.Tds      |

  ## Configuration

  The adapter is resolved in this order of precedence:

  1. Explicit `:adapter` option in `use SqlDir` macro
  2. Application config: `config :my_app, SqlDir, adapter: :postgrex`
  3. Auto-detect from the repo's Ecto adapter

  ## Custom Adapters

  To implement a custom adapter, define a module that implements this behaviour:

      defmodule MyApp.CustomAdapter do
        @behaviour SqlDir.Adapter

        @impl true
        def extract_result(%MyDriver.Result{columns: columns, rows: rows}) do
          {columns, rows}
        end
      end

  Then specify it in config or the macro:

      # In config
      config :my_app, SqlDir, adapter: MyApp.CustomAdapter

      # Or in the macro
      use SqlDir,
        adapter: MyApp.CustomAdapter,
        ...
  """

  @type result :: term()

  @doc """
  Extracts columns and rows from a database driver result.

  Returns a tuple of `{columns, rows}` where:
  - `columns` is a list of column name strings
  - `rows` is a list of row tuples/lists
  """
  @callback extract_result(result()) :: {columns :: [String.t()], rows :: [list()]}

  @doc """
  Resolves the adapter module based on macro option, app config, or repo detection.

  ## Resolution Order

  1. If `macro_adapter` is provided, use it
  2. If app config has `:adapter`, use it
  3. Auto-detect from the repo's Ecto adapter
  """
  @spec resolve(macro_adapter :: atom() | module() | nil, otp_app :: atom(), repo :: module()) ::
          module()
  def resolve(macro_adapter, otp_app, repo) do
    cond do
      macro_adapter != nil ->
        get(macro_adapter)

      config_adapter = get_config_adapter(otp_app) ->
        get(config_adapter)

      true ->
        detect_from_repo(repo)
    end
  end

  defp get_config_adapter(otp_app) do
    otp_app
    |> Application.get_env(SqlDir, [])
    |> Keyword.get(:adapter)
  end

  @doc """
  Detects the appropriate SqlDir adapter from a repo module.

  Inspects the repo's Ecto adapter and returns the corresponding SqlDir adapter module.

  Raises if the Ecto adapter is not recognized.
  """
  @spec detect_from_repo(module()) :: module()
  def detect_from_repo(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> SqlDir.Adapters.Postgrex
      Ecto.Adapters.MyXQL -> SqlDir.Adapters.MyXQL
      Ecto.Adapters.SQLite3 -> SqlDir.Adapters.Exqlite
      Ecto.Adapters.Tds -> SqlDir.Adapters.Tds
      other -> raise "Unknown Ecto adapter: #{inspect(other)}. Please specify :adapter option."
    end
  end

  @doc """
  Returns the adapter module for a given adapter atom or module.

  ## Examples

      iex> SqlDir.Adapter.get(:postgrex)
      SqlDir.Adapters.Postgrex

      iex> SqlDir.Adapter.get(MyApp.CustomAdapter)
      MyApp.CustomAdapter

  Raises if the adapter atom is not recognized.
  """
  @spec get(atom() | module()) :: module()
  def get(:postgrex), do: SqlDir.Adapters.Postgrex
  def get(:myxql), do: SqlDir.Adapters.MyXQL
  def get(:exqlite), do: SqlDir.Adapters.Exqlite
  def get(:tds), do: SqlDir.Adapters.Tds

  def get(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :extract_result, 1) do
      module
    else
      raise "Unknown adapter: #{inspect(module)}. " <>
              "Expected a module implementing SqlDir.Adapter behaviour or one of: :postgrex, :myxql, :exqlite, :tds"
    end
  end
end
