defmodule SqlDir.Adapters.Tds do
  @moduledoc """
  SqlDir adapter for SQL Server via TDS.
  """

  @behaviour SqlDir.Adapter

  @impl true
  def extract_result(%Tds.Result{columns: columns, rows: rows}) do
    {columns, rows}
  end
end
