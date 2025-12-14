import Config

config :sql_kit, SqlKit, root_sql_dir: "test/support/sql"

import_config "#{config_env()}.exs"
