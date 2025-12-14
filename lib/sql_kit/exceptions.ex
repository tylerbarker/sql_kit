defmodule SqlKit.NoResultsError do
  @moduledoc """
  Raised when a query expected to return one result returns none.

  Similar to `Ecto.NoResultsError` but for SqlKit queries.
  """

  defexception [:message, :query]

  @impl true
  def exception(opts) do
    # :filename takes precedence (file-based API), falls back to :query (standalone API)
    query = Keyword.get(opts, :filename) || Keyword.get(opts, :query, "unknown")
    message = "expected at least one result but got none for query: #{query}"
    %__MODULE__{message: message, query: query}
  end
end

defmodule SqlKit.MultipleResultsError do
  @moduledoc """
  Raised when a query expected to return one result returns more than one.

  Similar to `Ecto.MultipleResultsError` but for SqlKit queries.
  """

  defexception [:message, :query, :count]

  @impl true
  def exception(opts) do
    # :filename takes precedence (file-based API), falls back to :query (standalone API)
    query = Keyword.get(opts, :filename) || Keyword.get(opts, :query, "unknown")
    count = Keyword.fetch!(opts, :count)
    message = "expected at most one result but got #{count} for query: #{query}"
    %__MODULE__{message: message, query: query, count: count}
  end
end
