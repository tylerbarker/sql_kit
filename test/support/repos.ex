defmodule SqlDir.Test.PostgresRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :sql_dir,
    adapter: Ecto.Adapters.Postgres
end

defmodule SqlDir.Test.MySQLRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :sql_dir,
    adapter: Ecto.Adapters.MyXQL
end

defmodule SqlDir.Test.SQLiteRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :sql_dir,
    adapter: Ecto.Adapters.SQLite3
end

defmodule SqlDir.Test.TdsRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :sql_dir,
    adapter: Ecto.Adapters.Tds
end

defmodule SqlDir.Test.ClickHouseRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :sql_dir,
    adapter: Ecto.Adapters.ClickHouse
end
