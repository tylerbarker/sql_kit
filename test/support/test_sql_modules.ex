defmodule SqlKit.Test.PostgresSQL do
  @moduledoc false
  use SqlKit,
    otp_app: :sql_kit,
    repo: SqlKit.Test.PostgresRepo,
    dirname: "test_postgres",
    files: ["all_users.sql", "first_user.sql", "no_users.sql", "user_by_id.sql", "users_by_age_range.sql"]
end

defmodule SqlKit.Test.MySQLSQL do
  @moduledoc false
  use SqlKit,
    otp_app: :sql_kit,
    repo: SqlKit.Test.MySQLRepo,
    dirname: "test_mysql",
    files: ["all_users.sql", "first_user.sql", "no_users.sql", "user_by_id.sql", "users_by_age_range.sql"]
end

defmodule SqlKit.Test.SQLiteSQL do
  @moduledoc false
  use SqlKit,
    otp_app: :sql_kit,
    repo: SqlKit.Test.SQLiteRepo,
    dirname: "test_sqlite",
    files: ["all_users.sql", "first_user.sql", "no_users.sql", "user_by_id.sql", "users_by_age_range.sql"]
end

defmodule SqlKit.Test.TdsSQL do
  @moduledoc false
  use SqlKit,
    otp_app: :sql_kit,
    repo: SqlKit.Test.TdsRepo,
    dirname: "test_tds",
    files: ["all_users.sql", "first_user.sql", "no_users.sql", "user_by_id.sql", "users_by_age_range.sql"]
end

defmodule SqlKit.Test.ClickHouseSQL do
  @moduledoc false
  use SqlKit,
    otp_app: :sql_kit,
    repo: SqlKit.Test.ClickHouseRepo,
    dirname: "test_clickhouse",
    files: ["all_users.sql", "first_user.sql", "no_users.sql", "user_by_id.sql", "users_by_age_range.sql"]
end

defmodule SqlKit.Test.DuckDBSQL do
  @moduledoc false
  use SqlKit,
    otp_app: :sql_kit,
    backend: {:duckdb, pool: SqlKit.Test.DuckDBPool},
    dirname: "test_duckdb",
    files: ["all_users.sql", "first_user.sql", "no_users.sql", "user_by_id.sql", "users_by_age_range.sql"]
end

# Test struct for casting
defmodule SqlKit.Test.User do
  @moduledoc false
  defstruct [:id, :name, :email, :age]
end
