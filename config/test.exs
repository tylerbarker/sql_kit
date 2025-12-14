import Config

alias Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning

config :sql_kit, SqlKit, load_sql: :dynamic

config :sql_kit, SqlKit.Test.ClickHouseRepo,
  url: "http://localhost:8123/sql_kit_test",
  username: "default",
  password: "clickhouse",
  pool: Sandbox,
  pool_size: 10

config :sql_kit, SqlKit.Test.MySQLRepo,
  username: "root",
  password: "mysql",
  hostname: "localhost",
  database: "sql_kit_test",
  pool: Sandbox,
  pool_size: 10

config :sql_kit, SqlKit.Test.PostgresRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "sql_kit_test",
  pool: Sandbox,
  pool_size: 10

config :sql_kit, SqlKit.Test.SQLiteRepo,
  database: "test/support/sql_kit_test.db",
  pool: Sandbox,
  pool_size: 1

config :sql_kit, SqlKit.Test.TdsRepo,
  username: "sa",
  password: "SqlKit123!",
  hostname: "localhost",
  database: "sql_kit_test",
  pool: Sandbox,
  pool_size: 10
