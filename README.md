# SqlKit

[Hex](https://hex.pm/packages/sql_kit) | [GitHub](https://github.com/tylerbarker/sql_kit) | [Documentation](https://hexdocs.pm/sql_kit)

Execute raw SQL in strings or .sql files, get maps and structs back. Built on top of ecto_sql.

SqlKit provides two ways to execute SQL with automatic result transformation:

1. **Direct SQL execution** - Execute SQL strings directly with any Ecto repo
2. **File-based SQL** - Keep SQL in dedicated files with compile-time embedding

```elixir
# Direct SQL execution
defmodule MyApp.Accounts do
  alias MyApp.Accounts.User

  def get_active_users(company_id, min_age) do
    SqlKit.query_all(MyApp.Repo, """
      SELECT id, name, email, age
      FROM users
      WHERE company_id = $1
        AND age >= $2
        AND active = true
      ORDER BY name
    """, [company_id, min_age], as: User)
  end
end

# File-based SQL
defmodule MyApp.Accounts.SQL do
  use SqlKit,
    otp_app: :my_app,
    repo: MyApp.Repo,
    dirname: "accounts",
    files: ["active_users.sql", "another_query.sql"]
end

defmodule MyApp.Accounts do
  alias MyApp.Accounts.SQL
  alias MyApp.Accounts.User

  def get_active_users(company_id, min_age) do
    SQL.query_all("active_users.sql", [company_id, min_age], as: User)
  end
end

# Usage
MyApp.Accounts.get_active_users(123, 21)
# => [%User{id: 1, name: "Alice", email: "alice@example.com", age: 30}, ...]
```

## Why?

Sometimes raw SQL is the right tool for the job. Complex analytical queries, reports with intricate joins, or database-specific features often demand SQL that's awkward to express through an ORM.

You can do this already with `Repo.query`, however this returns a result struct with separate `columns` and `rows` lists. SqlKit handles this for you, returning maps `[%{id: 1, name: "Alice"}, ...]` or structs `[%User{id: 1, name: "Alice"}, ...]` directly.

For file-based SQL, keeping queries in `.sql` files brings other practical benefits like syntax highlighting, and SQL formatter support. It also makes your codebase more accessible to SQL-fluent team members who can read, review, and contribute queries without needing to learn Elixir first. How `.sql` files are loaded is configurable by environment: Reading from disk in development for fast iteration, and embedding at compile time in production to eliminate unnecessary I/O.

## Features

- **Just SQL**: No DSL or special syntax to learn.
- **Automatic result transformation**: Query results returned as maps or structs, not raw columns/rows
- **Two APIs**: Execute SQL strings directly or load from files
- **Compile-time embedding**: File-based SQL read once at compile time and stored as module attributes
- **Dynamic loading in dev/test**: Edit SQL files without recompiling
- **Multi-database support**: Works with PostgreSQL, MySQL/MariaDB, SQLite, SQL Server, ClickHouse, and DuckDB

## Supported Databases

| Database   | Ecto Adapter              | Driver   |
|------------|---------------------------|----------|
| PostgreSQL | Ecto.Adapters.Postgres    | Postgrex |
| SQLite     | Ecto.Adapters.SQLite3     | Exqlite  |
| MySQL      | Ecto.Adapters.MyXQL       | MyXQL    |
| MariaDB    | Ecto.Adapters.MyXQL       | MyXQL    |
| SQL Server | Ecto.Adapters.Tds         | Tds      |
| ClickHouse | Ecto.Adapters.ClickHouse  | Ch       |
| DuckDB     | N/A (direct driver)       | Duckdbex |

## Installation

Add `sql_kit` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sql_kit, "~> 0.2.0"}
  ]
end
```

For DuckDB support, also add `duckdbex`:

```elixir
def deps do
  [
    {:sql_kit, "~> 0.2.0"},
    {:duckdbex, "~> 0.3"}
  ]
end
```

## Configuration

```elixir
# config/config.exs
config :my_app, SqlKit,
  root_sql_dir: "priv/repo/sql"  # default

# config/dev.exs and config/test.exs
config :my_app, SqlKit,
  load_sql: :dynamic  # read from disk at runtime

# config/prod.exs (or rely on default)
config :my_app, SqlKit,
  load_sql: :compiled  # use compile-time embedded SQL
```

## Quick Start

### Direct SQL Execution

Execute SQL strings directly with any Ecto repo:

```elixir
# Get all rows as a list of maps
SqlKit.query_all(MyApp.Repo, "SELECT * FROM users WHERE age > $1", [21])
# => [%{id: 1, name: "Alice", age: 30}, %{id: 2, name: "Bob", age: 25}]

# Get a single row (raises if no results)
SqlKit.query_one!(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [1])
# => %{id: 1, name: "Alice", age: 30}

# Get a single row or nil (raises on multiple results)
SqlKit.query_one(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [1])
# => %{id: 1, name: "Alice", age: 30}

SqlKit.query_one(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [999])
# => nil

# Cast results to structs
SqlKit.query_all(MyApp.Repo, "SELECT * FROM users", [], as: User)
# => [%User{id: 1, name: "Alice", age: 30}, ...]

# ClickHouse uses named parameters as a map
SqlKit.query_all(ClickHouseRepo, "SELECT * FROM users WHERE age > {age:UInt32}", %{age: 21})
# => [%{id: 1, name: "Alice", age: 30}, ...]
```

### File-Based SQL

For larger queries or better organization, keep SQL in dedicated files:

#### 1. Create SQL files

SQL files are housed in subdirectories under the root SQL directory. This is `priv/repo/sql` by default but is configurable via `:root_sql_dir` config option. The `priv/` directory is recommended because these files are included in Mix releases by default.

```sql
-- priv/repo/sql/reports/stats.sql
SELECT id, name, total_sales
FROM users
WHERE id = $1
```

#### 2. Define a SQL module

```elixir
defmodule MyApp.Reports.SQL do
  use SqlKit,
    otp_app: :my_app,
    repo: MyApp.Repo,
    dirname: "reports",
    files: ["stats.sql", "activity.sql"]
end
```

#### 3. Execute queries

```elixir
# Get a single row as a map (raises if no results)
MyApp.Reports.SQL.query_one!("stats.sql", [user_id])
# => %{id: 1, name: "Alice", total_sales: 1000}

# Get a single row or nil (raises on multiple results)
MyApp.Reports.SQL.query_one("stats.sql", [user_id])
# => %{id: 1, name: "Alice", total_sales: 1000}

# You can also use query!/3 and query/3, which are aliases for query_one!/3 and query_one/3
MyApp.Reports.SQL.query!("stats.sql", [user_id])
# => %{id: 1, name: "Alice", total_sales: 1000}

# Get all rows
MyApp.Reports.SQL.query_all("activity.sql", [company_id])
# => [%{id: 1, ...}, %{id: 2, ...}]

# Cast results to structs
MyApp.Reports.SQL.query_one!("stats.sql", [id], as: UserStats)
# => %UserStats{id: 1, name: "Alice", total_sales: 1000}

# Load the raw SQL string
MyApp.Reports.SQL.load!("stats.sql")
# => "SELECT id, name, total_sales..."
```

## DuckDB

DuckDB is a high-performance analytical database. Unlike other supported databases, DuckDB is not an Ecto adapter—SqlKit provides direct integration via the `duckdbex` driver.

### Direct Connection

For scripts, one-off analysis, or simple use cases:

```elixir
# In-memory database
{:ok, conn} = SqlKit.DuckDB.connect(":memory:")
SqlKit.query_all(conn, "SELECT 1 as num", [])
# => [%{num: 1}]
SqlKit.DuckDB.disconnect(conn)

# File-based database
{:ok, conn} = SqlKit.DuckDB.connect("analytics.duckdb")
SqlKit.query_all(conn, "SELECT * FROM events", [])
SqlKit.DuckDB.disconnect(conn)

# With custom configuration
{:ok, conn} = SqlKit.DuckDB.connect("analytics.duckdb",
  config: %Duckdbex.Config{threads: 4})
```

### Pooled Connection (Recommended for Production)

For production use, add the pool to your supervision tree:

```elixir
# In your application.ex
def start(_type, _args) do
  children = [
    # ... other children
    {SqlKit.DuckDB.Pool,
      name: MyApp.AnalyticsPool,
      database: "priv/analytics.duckdb",
      pool_size: 4}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

Pool options:
- `:name` - Required. The name to register the pool under
- `:database` - Required. Path to database file or `":memory:"`
- `:pool_size` - Number of connections. Default: 4
- `:config` - Optional `Duckdbex.Config` struct for advanced configuration (threads, memory limits, etc.)

Then query using the pool:

```elixir
pool = SqlKit.DuckDB.Pool.pool(MyApp.AnalyticsPool)
SqlKit.query_all(pool, "SELECT * FROM events WHERE date > $1", [~D[2024-01-01]])
# => [%{id: 1, date: ~D[2024-01-15], ...}, ...]
```

### File-Based SQL with DuckDB

Use the `:backend` option instead of `:repo`:

```elixir
defmodule MyApp.Analytics.SQL do
  use SqlKit,
    otp_app: :my_app,
    backend: {:duckdb, pool: MyApp.AnalyticsPool},
    dirname: "analytics",
    files: ["daily_summary.sql", "user_activity.sql"]
end

# Usage
MyApp.Analytics.SQL.query_all("daily_summary.sql", [~D[2024-01-01]])
```

### Loading Extensions

DuckDB extensions (Parquet, JSON, HTTPFS, etc.) are loaded via SQL:

```elixir
pool = SqlKit.DuckDB.Pool.pool(MyApp.AnalyticsPool)
SqlKit.query_one!(pool, "INSTALL 'parquet';", [])
SqlKit.query_one!(pool, "LOAD 'parquet';", [])
SqlKit.query_all(pool, "SELECT * FROM 'data.parquet'", [])
```

### Streaming Large Results

For memory-efficient processing of large result sets:

```elixir
# Direct connection streaming
conn
|> SqlKit.DuckDB.stream!("SELECT * FROM large_table", [])
|> Stream.flat_map(& &1)
|> Enum.take(100)

# Pool streaming (callback-based)
SqlKit.DuckDB.Pool.with_stream!(pool, "SELECT * FROM events", [], fn stream ->
  stream |> Stream.flat_map(& &1) |> Enum.count()
end)

# File-based SQL streaming (DuckDB backends only)
MyApp.Analytics.SQL.with_stream!("large_query.sql", [], fn stream ->
  stream |> Stream.flat_map(& &1) |> Enum.take(1000)
end)
```

### Pool Options

Pool operations accept these options:
- `:timeout` - Checkout timeout in milliseconds (default: 5000)
- `:cache` - Enable prepared statement caching (default: true)

```elixir
SqlKit.DuckDB.Pool.query!(pool, sql, params, timeout: 10_000, cache: false)
```

### Key Differences from Ecto-Based Databases

- Uses PostgreSQL-style `$1, $2, ...` parameter placeholders
- In-memory database: use `":memory:"` string (not `:memory` atom)
- Pool uses NimblePool (connections share one database instance)
- Pool automatically caches prepared statements for repeated queries
- Hugeint values are automatically converted to Elixir integers
- Date/Time values are returned as tuples (e.g., `{2024, 1, 15}` for dates)

## Parameter Syntax by Database

Each database uses different parameter placeholder syntax:

| Database   | Syntax            | Example                                    |
|------------|-------------------|--------------------------------------------|
| PostgreSQL | `$1`, `$2`, ...   | `WHERE id = $1 AND age > $2`               |
| MySQL      | `?`               | `WHERE id = ? AND age > ?`                 |
| SQLite     | `?`               | `WHERE id = ? AND age > ?`                 |
| SQL Server | `@1`, `@2`, ...   | `WHERE id = @1 AND age > @2`               |
| ClickHouse | `{name:Type}`     | `WHERE id = {id:UInt32} AND age > {age:UInt32}` |
| DuckDB     | `$1`, `$2`, ...   | `WHERE id = $1 AND age > $2`               |

### ClickHouse Named Parameters

ClickHouse uses named parameters with explicit types. Pass parameters as a map:

```elixir
# SQL file: user_by_id.sql
# SELECT * FROM users WHERE id = {id:UInt32}

ClickHouseSQL.query_one!("user_by_id.sql", %{id: 1})
```

### Named Parameters for Other Databases

For databases using positional parameters, wrap SqlKit calls in functions to get named parameter ergonomics:

```elixir
# SQL string
defmodule MyApp.Accounts do
  alias MyApp.Accounts.User

  def get_active_users(company_id, min_age) do
    SqlKit.query_all(MyApp.Repo, """
      SELECT id, name, email, age
      FROM users
      WHERE company_id = $1
        AND age >= $2
        AND active = true
      ORDER BY name
    """, [company_id, min_age], as: User)
  end
end

# SQL file
defmodule MyApp.Accounts do
  alias MyApp.Accounts.SQL # `use SqlKit` module
  alias MyApp.Accounts.User

  def get_active_users(company_id, min_age) do
    SQL.query_all("active_users.sql", [company_id, min_age], as: User)
  end
end

# Usage
MyApp.Accounts.get_active_users(123, 21)
# => [%User{id: 1, name: "Alice", email: "alice@example.com", age: 30}, ...]
```

This pattern gives you named parameters through Elixir function arguments while keeping queries as plain SQL.

## Use SqlKit Options

- `:otp_app` (required) - Your application name
- `:repo` - The Ecto repo module to use for queries (required unless `:backend` is specified)
- `:backend` - Alternative to `:repo` for non-Ecto databases. Supports `{:duckdb, pool: PoolName}`
- `:dirname` (required) - Subdirectory within root_sql_dir for this module's SQL files
- `:files` (required) - List of SQL filenames to load

Note: You must specify either `:repo` or `:backend`, but not both.

## API Reference

### Standalone Functions

These functions are defined directly on the `SqlKit` module and work with any Ecto repo:

#### `SqlKit.query_all(repo, sql, params \\ [], opts \\ [])`

Executes SQL and returns all rows as a list of maps. Raises on query execution errors.
Matches [`Ecto.Repo.all/2`](https://hexdocs.pm/ecto/Ecto.Repo.html#c:all/2) semantics.

```elixir
SqlKit.query_all(MyApp.Repo, "SELECT * FROM users")
# => [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

SqlKit.query_all(MyApp.Repo, "SELECT * FROM users WHERE age > $1", [21], as: User)
# => [%User{id: 1, name: "Alice"}, ...]

# ClickHouse uses named parameters as a map
SqlKit.query_all(ClickHouseRepo, "SELECT * FROM users WHERE age > {age:UInt32}", %{age: 21})
# => [%{id: 1, name: "Alice"}, ...]
```

#### `SqlKit.query_one!(repo, sql, params \\ [], opts \\ [])`

Executes SQL and returns exactly one row as a map.

- Raises `SqlKit.NoResultsError` if no rows returned
- Raises `SqlKit.MultipleResultsError` if more than one row returned

Matches [`Ecto.Repo.one!/2`](https://hexdocs.pm/ecto/Ecto.Repo.html#c:one!/2) semantics.

```elixir
SqlKit.query_one!(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [1])
# => %{id: 1, name: "Alice"}

SqlKit.query_one!(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [1], as: User)
# => %User{id: 1, name: "Alice"}

# ClickHouse uses named parameters as a map
SqlKit.query_one!(ClickHouseRepo, "SELECT * FROM users WHERE id = {id:UInt32}", %{id: 1})
# => %{id: 1, name: "Alice"}
```

#### `SqlKit.query!(repo, sql, params \\ [], opts \\ [])`

Alias for `SqlKit.query_one!/4`. See `SqlKit.query_one!/4` documentation.

#### `SqlKit.query_one(repo, sql, params \\ [], opts \\ [])`

Executes SQL and returns one row or nil. Raises on query execution errors or multiple results.
Matches [`Ecto.Repo.one/2`](https://hexdocs.pm/ecto/Ecto.Repo.html#c:one/2) semantics.

- Returns `result` on exactly one result
- Returns `nil` on no results
- Raises `SqlKit.MultipleResultsError` if more than one row returned

```elixir
SqlKit.query_one(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [1])
# => %{id: 1, name: "Alice"}

SqlKit.query_one(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [999])
# => nil

# ClickHouse uses named parameters as a map
SqlKit.query_one(ClickHouseRepo, "SELECT * FROM users WHERE id = {id:UInt32}", %{id: 1})
# => %{id: 1, name: "Alice"}
```

#### `SqlKit.query(repo, sql, params \\ [], opts \\ [])`

Alias for `SqlKit.query_one/4`. See `SqlKit.query_one/4` documentation.

### File-Based Functions

These functions are generated by `use SqlKit` and available on your SQL modules:

#### `query_all(filename, params \\ [], opts \\ [])`

Executes a query and returns all rows as a list of maps. Raises on query execution errors.
Matches [`Ecto.Repo.all/2`](https://hexdocs.pm/ecto/Ecto.Repo.html#c:all/2) semantics.

```elixir
SQL.query_all("users.sql", [company_id])
# => [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

SQL.query_all("users.sql", [company_id], as: User)
# => [%User{id: 1, name: "Alice"}, %User{id: 2, name: "Bob"}]

# ClickHouse uses named parameters as a map
ClickHouseSQL.query_all("users.sql", %{company_id: 123})
# => [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
```

#### `query_one!(filename, params \\ [], opts \\ [])`

Executes a query and returns a single row as a map.

- Raises `SqlKit.NoResultsError` if no rows returned
- Raises `SqlKit.MultipleResultsError` if more than one row returned

```elixir
SQL.query_one!("user.sql", [user_id])
# => %{id: 1, name: "Alice"}

SQL.query_one!("user.sql", [user_id], as: User)
# => %User{id: 1, name: "Alice"}

# ClickHouse uses named parameters as a map
ClickHouseSQL.query_one!("user.sql", %{user_id: 1})
# => %{id: 1, name: "Alice"}
```

#### `query!(filename, params \\ [], opts \\ [])`

Alias for `query_one!/3`. See `query_one!/3` documentation.

#### `query_one(filename, params \\ [], opts \\ [])`

Executes a query and returns one row or nil. Raises on query execution errors or multiple results.
Matches [`Ecto.Repo.one/2`](https://hexdocs.pm/ecto/Ecto.Repo.html#c:one/2) semantics.

```elixir
SQL.query_one("user.sql", [user_id])
# => %{id: 1, name: "Alice"}

SQL.query_one("missing_user.sql", [999])
# => nil  # No results returns nil

# Raises SqlKit.MultipleResultsError on multiple results
SQL.query_one("all_users.sql", [])

# ClickHouse uses named parameters as a map
ClickHouseSQL.query_one("user.sql", %{user_id: 1})
# => %{id: 1, name: "Alice"}
```

#### `query(filename, params \\ [], opts \\ [])`

Alias for `query_one/3`. See `query_one/3` documentation.

#### `load!(filename)`

Returns the SQL string for the given file.

```elixir
SQL.load!("users.sql")
# => "SELECT * FROM users"
```

#### `load(filename)`

```elixir
SQL.load("users.sql")
# => {:ok, "SELECT * FROM users"}
```

### Options

- `:as` - Struct module to cast results into
- `:unsafe_atoms` - If `true`, uses `String.to_atom/1` instead of `String.to_existing_atom/1` for column names. Default: `false`
- `:query_name` - Custom identifier for exceptions (standalone API only; defaults to truncated SQL)

## Contributing

### Prerequisites

- [ASDF](https://asdf-vm.com) (Elixir + Erlang version management)
- [Docker](https://docs.docker.com) (for database containers via `docker compose up`)
- [SQLite3](https://sqlite.org) (installed locally)

### Setup

1. Clone the repository
2. Run `asdf install`
3. Install dependencies and compile:
   ```bash
   mix do deps.get, deps.compile, compile
   ```

4. Start the database containers:
   ```bash
   docker compose up
   ```

5. Run the tests:
   ```bash
   mix test
   ```

The test suite runs against all supported databases (PostgreSQL, MySQL, SQLite, SQL Server, ClickHouse, and DuckDB). All databases must be running for the full test suite to pass.

### Database Ports

- PostgreSQL: 5432
- MySQL: 3306
- SQL Server: 1433
- ClickHouse: 8123, 9000

SQLite and DuckDB use local files/memory and don't require Docker.

### Before Pull Request

Run `mix check`.

## License

MIT License. See LICENSE.md for details.
