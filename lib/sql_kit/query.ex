defmodule SqlKit.Query do
  @moduledoc false
  # Internal module - users should use SqlKit.query_all!, SqlKit.query_one!, etc.

  @doc """
  Executes SQL and returns all rows as a list of maps or structs.
  """
  @spec all!(Ecto.Repo.t(), String.t(), list() | map(), keyword()) :: [map() | struct()]
  def all!(repo, sql, params \\ [], opts \\ []) do
    result = repo.query!(sql, params)
    {columns, rows} = SqlKit.extract_result(result)
    SqlKit.transform_rows(columns, rows, opts)
  end

  @doc """
  Executes SQL and returns all rows as a list of maps or structs.

  Returns `{:ok, results}` on success, `{:error, exception}` on failure.
  """
  @spec all(Ecto.Repo.t(), String.t(), list() | map(), keyword()) ::
          {:ok, [map() | struct()]} | {:error, term()}
  def all(repo, sql, params \\ [], opts \\ []) do
    {:ok, all!(repo, sql, params, opts)}
  rescue
    e -> {:error, e}
  end

  @doc """
  Executes SQL and returns exactly one row as a map or struct.

  Raises `SqlKit.NoResultsError` if no rows are returned.
  Raises `SqlKit.MultipleResultsError` if more than one row is returned.
  """
  @spec one!(Ecto.Repo.t(), String.t(), list() | map(), keyword()) :: map() | struct()
  def one!(repo, sql, params \\ [], opts \\ []) do
    query_name = Keyword.get(opts, :query_name) || truncate_sql(sql)

    case all!(repo, sql, params, opts) do
      [] ->
        raise SqlKit.NoResultsError, query: query_name

      [row] ->
        row

      rows ->
        raise SqlKit.MultipleResultsError, query: query_name, count: length(rows)
    end
  end

  @doc """
  Executes SQL and returns one row as a map or struct.

  Returns `{:ok, result}` on exactly one result, `{:ok, nil}` on no results,
  or `{:error, exception}` on multiple results or other errors.
  """
  @spec one(Ecto.Repo.t(), String.t(), list() | map(), keyword()) ::
          {:ok, map() | struct() | nil} | {:error, term()}
  def one(repo, sql, params \\ [], opts \\ []) do
    query_name = Keyword.get(opts, :query_name) || truncate_sql(sql)

    case all(repo, sql, params, opts) do
      {:ok, []} ->
        {:ok, nil}

      {:ok, [row]} ->
        {:ok, row}

      {:ok, rows} ->
        {:error, SqlKit.MultipleResultsError.exception(query: query_name, count: length(rows))}

      {:error, _} = error ->
        error
    end
  end

  defp truncate_sql(sql) do
    if String.length(sql) > 50 do
      String.slice(sql, 0, 49) <> "..."
    else
      sql
    end
  end
end
