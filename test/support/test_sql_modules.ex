defmodule SqlDir.Test.PostgresSQL do
  use SqlDir,
    otp_app: :sql_dir,
    repo: SqlDir.Test.PostgresRepo,
    dirname: "test_postgres",
    files: ["all_users.sql", "first_user.sql", "no_users.sql", "user_by_id.sql", "users_by_age_range.sql"]
end

defmodule SqlDir.Test.MySQLSQL do
  use SqlDir,
    otp_app: :sql_dir,
    repo: SqlDir.Test.MySQLRepo,
    dirname: "test_mysql",
    files: ["all_users.sql", "first_user.sql", "no_users.sql", "user_by_id.sql", "users_by_age_range.sql"]
end

defmodule SqlDir.Test.SQLiteSQL do
  use SqlDir,
    otp_app: :sql_dir,
    repo: SqlDir.Test.SQLiteRepo,
    dirname: "test_sqlite",
    files: ["all_users.sql", "first_user.sql", "no_users.sql", "user_by_id.sql", "users_by_age_range.sql"]
end

defmodule SqlDir.Test.TdsSQL do
  use SqlDir,
    otp_app: :sql_dir,
    repo: SqlDir.Test.TdsRepo,
    dirname: "test_tds",
    files: ["all_users.sql", "first_user.sql", "no_users.sql", "user_by_id.sql", "users_by_age_range.sql"]
end

defmodule SqlDir.Test.ClickHouseSQL do
  use SqlDir,
    otp_app: :sql_dir,
    repo: SqlDir.Test.ClickHouseRepo,
    dirname: "test_clickhouse",
    files: ["all_users.sql", "first_user.sql", "no_users.sql", "user_by_id.sql", "users_by_age_range.sql"]
end

# Test struct for casting
defmodule SqlDir.Test.User do
  defstruct [:id, :name, :email, :age]
end
