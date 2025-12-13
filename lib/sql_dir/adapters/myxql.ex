defmodule SqlDir.Adapters.MyXQL do
  @moduledoc """
  SqlDir adapter for MySQL via MyXQL.
  """

  @behaviour SqlDir.Adapter

  @impl true
  def extract_result(%MyXQL.Result{columns: columns, rows: rows}) do
    {columns, rows}
  end
end
