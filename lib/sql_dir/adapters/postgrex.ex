defmodule SqlDir.Adapters.Postgrex do
  @moduledoc """
  SqlDir adapter for PostgreSQL via Postgrex.
  """

  @behaviour SqlDir.Adapter

  @impl true
  def extract_result(%Postgrex.Result{columns: columns, rows: rows}) do
    {columns, rows}
  end
end
