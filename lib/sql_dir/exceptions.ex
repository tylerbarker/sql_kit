defmodule SqlDir.NoResultsError do
  @moduledoc """
  Raised when a query expected to return one result returns none.

  Similar to `Ecto.NoResultsError` but for SqlDir queries.
  """

  defexception [:message, :filename]

  @impl true
  def exception(opts) do
    filename = Keyword.fetch!(opts, :filename)
    message = "expected at least one result but got none for query: #{filename}"
    %__MODULE__{message: message, filename: filename}
  end
end

defmodule SqlDir.MultipleResultsError do
  @moduledoc """
  Raised when a query expected to return one result returns more than one.

  Similar to `Ecto.MultipleResultsError` but for SqlDir queries.
  """

  defexception [:message, :filename, :count]

  @impl true
  def exception(opts) do
    filename = Keyword.fetch!(opts, :filename)
    count = Keyword.fetch!(opts, :count)
    message = "expected at most one result but got #{count} for query: #{filename}"
    %__MODULE__{message: message, filename: filename, count: count}
  end
end
