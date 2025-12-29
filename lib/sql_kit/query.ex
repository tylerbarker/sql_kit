defmodule SqlKit.Query do
  @moduledoc false
  # Internal module - users should use SqlKit.query_all, SqlKit.query_one, etc.

  @doc """
  Executes SQL and returns all rows as a list of maps or structs.

  Raises on query execution errors.
  """
  @spec all(backend :: term(), String.t(), list() | map(), keyword()) :: [map() | struct()]
  def all(backend, sql, params \\ [], opts \\ []) do
    {columns, rows} = execute!(backend, sql, params)
    SqlKit.transform_rows(columns, rows, opts)
  end

  @doc """
  Executes SQL and returns exactly one row as a map or struct.

  Raises `SqlKit.NoResultsError` if no rows are returned.
  Raises `SqlKit.MultipleResultsError` if more than one row is returned.
  """
  @spec one!(backend :: term(), String.t(), list() | map(), keyword()) :: map() | struct()
  def one!(backend, sql, params \\ [], opts \\ []) do
    query_name = Keyword.get(opts, :query_name) || truncate_sql(sql)

    case all(backend, sql, params, opts) do
      [] ->
        raise SqlKit.NoResultsError, query: query_name

      [row] ->
        row

      rows ->
        raise SqlKit.MultipleResultsError, query: query_name, count: length(rows)
    end
  end

  @doc """
  Executes SQL and returns one row as a map or struct, or nil if no results.

  Returns the result directly, or nil on no results.
  Raises `SqlKit.MultipleResultsError` if more than one row is returned.
  Raises on query execution errors.
  """
  @spec one(backend :: term(), String.t(), list() | map(), keyword()) :: map() | struct() | nil
  def one(backend, sql, params \\ [], opts \\ []) do
    query_name = Keyword.get(opts, :query_name) || truncate_sql(sql)

    case all(backend, sql, params, opts) do
      [] ->
        nil

      [row] ->
        row

      rows ->
        raise SqlKit.MultipleResultsError, query: query_name, count: length(rows)
    end
  end

  # ============================================================================
  # Backend Detection and Execution
  # ============================================================================

  # Execute query based on backend type
  defp execute!(backend, sql, params)

  # DuckDB direct connection and pool support (conditionally compiled)
  if Code.ensure_loaded?(Duckdbex) do
    alias SqlKit.DuckDB.Pool

    defp execute!(%SqlKit.DuckDB.Connection{} = conn, sql, params) do
      # Direct connections don't use caching (simpler, users manage their own)
      SqlKit.DuckDB.query!(conn, sql, params)
    end

    defp execute!(%Pool{} = pool, sql, params) do
      # Pool queries use prepared statement caching by default
      Pool.query!(pool, sql, params)
    end
  end

  # Fallback - assume Ecto repo
  defp execute!(repo, sql, params) do
    execute_ecto!(repo, sql, params)
  end

  # Execute against Ecto repo
  defp execute_ecto!(repo, sql, params) do
    result = repo.query!(sql, params)
    SqlKit.extract_result(result)
  end

  defp truncate_sql(sql) do
    if String.length(sql) > 50 do
      String.slice(sql, 0, 49) <> "..."
    else
      sql
    end
  end
end
