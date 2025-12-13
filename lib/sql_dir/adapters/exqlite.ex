defmodule SqlDir.Adapters.Exqlite do
  @moduledoc """
  SqlDir adapter for SQLite via Exqlite.
  """

  @behaviour SqlDir.Adapter

  @impl true
  def extract_result(%Exqlite.Result{columns: columns, rows: rows}) do
    {columns, rows}
  end
end
