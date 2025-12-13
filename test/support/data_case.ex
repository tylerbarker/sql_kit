defmodule SqlDir.DataCase do
  @moduledoc """
  Test case template for database tests.

  Sets up the sandbox for the specified repo.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import SqlDir.DataCase
    end
  end

  @doc """
  Sets up the sandbox for the given repo.
  """
  def setup_sandbox(repo) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
