import Config

config :sql_dir, SqlDir, root_sql_dir: "test/support/sql"

import_config "#{config_env()}.exs"
