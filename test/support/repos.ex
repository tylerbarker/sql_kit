defmodule SqlDir.Test.PostgresRepo do
  use Ecto.Repo,
    otp_app: :sql_dir,
    adapter: Ecto.Adapters.Postgres
end

defmodule SqlDir.Test.MySQLRepo do
  use Ecto.Repo,
    otp_app: :sql_dir,
    adapter: Ecto.Adapters.MyXQL
end

defmodule SqlDir.Test.SQLiteRepo do
  use Ecto.Repo,
    otp_app: :sql_dir,
    adapter: Ecto.Adapters.SQLite3
end

defmodule SqlDir.Test.TdsRepo do
  use Ecto.Repo,
    otp_app: :sql_dir,
    adapter: Ecto.Adapters.Tds
end
