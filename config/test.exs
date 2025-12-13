import Config

alias Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning

config :sql_dir, SqlDir, load_sql: :dynamic

config :sql_dir, SqlDir.Test.ClickHouseRepo,
  url: "http://localhost:8123/sql_dir_test",
  username: "default",
  password: "clickhouse",
  pool: Sandbox,
  pool_size: 10

config :sql_dir, SqlDir.Test.MySQLRepo,
  username: "root",
  password: "mysql",
  hostname: "localhost",
  database: "sql_dir_test",
  pool: Sandbox,
  pool_size: 10

config :sql_dir, SqlDir.Test.PostgresRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "sql_dir_test",
  pool: Sandbox,
  pool_size: 10

config :sql_dir, SqlDir.Test.SQLiteRepo,
  database: "test/support/sql_dir_test.db",
  pool: Sandbox,
  pool_size: 1

config :sql_dir, SqlDir.Test.TdsRepo,
  username: "sa",
  password: "SqlDir123!",
  hostname: "localhost",
  database: "sql_dir_test",
  pool: Sandbox,
  pool_size: 10
