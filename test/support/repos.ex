defmodule SqlKit.Test.PostgresRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :sql_kit,
    adapter: Ecto.Adapters.Postgres
end

defmodule SqlKit.Test.MySQLRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :sql_kit,
    adapter: Ecto.Adapters.MyXQL
end

defmodule SqlKit.Test.SQLiteRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :sql_kit,
    adapter: Ecto.Adapters.SQLite3
end

defmodule SqlKit.Test.TdsRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :sql_kit,
    adapter: Ecto.Adapters.Tds
end

defmodule SqlKit.Test.ClickHouseRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :sql_kit,
    adapter: Ecto.Adapters.ClickHouse
end
