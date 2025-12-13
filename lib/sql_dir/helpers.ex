defmodule SqlDir.Helpers do
  @moduledoc """
  Compile-time helper functions for SqlDir.
  """

  @doc """
  Converts a SQL filename to an atom for module attribute storage.

  Replaces any non-alphanumeric characters (except underscores) with underscores
  to ensure valid atom names.

  ## Examples

      iex> SqlDir.Helpers.file_atom("stats_query.sql")
      :stats_query_sql

      iex> SqlDir.Helpers.file_atom("my-complex.query.sql")
      :my_complex_query_sql
  """
  @spec file_atom(String.t()) :: atom()
  def file_atom(filename) do
    filename
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> String.to_atom()
  end
end
