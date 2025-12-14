defmodule SqlKit.Config do
  @moduledoc """
  Runtime configuration access for SqlKit.

  Users configure SqlKit in their application's config:

      # config/config.exs
      config :my_app, SqlKit,
        root_sql_dir: "priv/repo/sql"

      # config/dev.exs and config/test.exs
      config :my_app, SqlKit,
        load_sql: :dynamic  # Read from disk at runtime

      # config/prod.exs (or just rely on the default)
      config :my_app, SqlKit,
        load_sql: :compiled  # Use compile-time embedded SQL

  ## Configuration Options

  - `:root_sql_dir` - The root directory for SQL files. Defaults to "priv/repo/sql".
  - `:load_sql` - How to load SQL files at runtime:
    - `:compiled` (default) - Use SQL embedded at compile time in module attributes.
    - `:dynamic` - Read SQL files from disk at runtime (useful for dev/test).
  """

  @default_root_sql_dir "priv/repo/sql"

  @doc """
  Returns the root directory for SQL files.

  Looks up the `:root_sql_dir` key in the application's SqlKit config.
  Defaults to "priv/repo/sql" if not configured.
  """
  @spec root_sql_dir(atom()) :: String.t()
  def root_sql_dir(otp_app) do
    otp_app
    |> Application.get_env(SqlKit, [])
    |> Keyword.get(:root_sql_dir, @default_root_sql_dir)
  end

  @doc """
  Returns the SQL loading mode for the application.

  - `:compiled` (default) - Use SQL embedded at compile time.
  - `:dynamic` - Read SQL files from disk at runtime.
  """
  @spec load_sql(atom()) :: :compiled | :dynamic
  def load_sql(otp_app) do
    otp_app
    |> Application.get_env(SqlKit, [])
    |> Keyword.get(:load_sql, :compiled)
  end
end
