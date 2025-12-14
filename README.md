# SqlKit

[Hex](https://hex.pm/packages/sql_kit) | [GitHub](https://github.com/tylerbarker/sql_kit) | [Documentation](https://hexdocs.pm/sql_kit)

Execute raw SQL using files or strings, automatically get maps and structs back. Built on top of ecto_sql.

SqlKit provides two ways to execute raw SQL with automatic result transformation:

1. **Direct SQL execution** - Execute SQL strings directly with any Ecto repo
2. **File-based SQL** - Keep SQL in dedicated files with compile-time embedding

## Why?

Sometimes raw SQL is the right tool for the job. Complex analytical queries, reports with intricate joins, or database-specific features often demand SQL that's awkward to express through an ORM.

You can do this already with `Repo.query`, however `Repo.query` returns a result struct with separate `columns` and `rows` lists. Transforming this into usable maps requires boilerplate. SqlKit handles this automatically, returning maps `[%{id: 1, name: "Alice"}, ...]` or structs `[%User{id: 1, name: "Alice"}, ...]` directly.

For file-based SQL, keeping queries in dedicated `.sql` files brings practical benefits: proper syntax highlighting, SQL formatter support, and cleaner Elixir modules without large multi-line strings. It also makes your codebase more accessible to SQL-fluent team members who can read, review, and contribute queries without needing to learn Elixir first. How SQL is loaded is configurable by environment: Reading from disk in development for fast iteration, and embedding at compile time in production to eliminate unnecessary file I/O.

## Features

- **Just SQL**: No DSL or special syntax to learn.
- **Automatic result transformation**: Query results returned as maps or structs, not raw columns/rows
- **Two APIs**: Execute SQL strings directly or load from files
- **Compile-time embedding**: File-based SQL read once at compile time and stored as module attributes
- **Dynamic loading in dev/test**: Edit SQL files without recompiling
- **Multi-database support**: Works with PostgreSQL, MySQL/MariaDB, SQLite, SQL Server, and ClickHouse

## Supported Databases

| Database   | Ecto Adapter              | Driver   |
|------------|---------------------------|----------|
| PostgreSQL | Ecto.Adapters.Postgres    | Postgrex |
| SQLite     | Ecto.Adapters.SQLite3     | Exqlite  |
| MySQL      | Ecto.Adapters.MyXQL       | MyXQL    |
| MariaDB    | Ecto.Adapters.MyXQL       | MyXQL    |
| SQL Server | Ecto.Adapters.Tds         | Tds      |
| ClickHouse | Ecto.Adapters.ClickHouse  | Ch       |

## Installation

Add `sql_kit` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sql_kit, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Direct SQL Execution

Execute SQL strings directly with any Ecto repo:

```elixir
# Get all rows as a list of maps
SqlKit.query_all!(MyApp.Repo, "SELECT * FROM users WHERE age > $1", [21])
# => [%{id: 1, name: "Alice", age: 30}, %{id: 2, name: "Bob", age: 25}]

# Get a single row
SqlKit.query_one!(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [1])
# => %{id: 1, name: "Alice", age: 30}

# Cast results to structs
SqlKit.query_all!(MyApp.Repo, "SELECT * FROM users", [], as: User)
# => [%User{id: 1, name: "Alice", age: 30}, ...]

# Non-bang variants return {:ok, result} or {:error, reason}
SqlKit.query_one(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [1])
# => {:ok, %{id: 1, name: "Alice"}}

# ClickHouse uses named parameters as a map
SqlKit.query_all!(ClickHouseRepo, "SELECT * FROM users WHERE age > {age:UInt32}", %{age: 21})
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
# Get a single row as a map
MyApp.Reports.SQL.query_one!("stats.sql", [user_id])
# => %{id: 1, name: "Alice", total_sales: 1000}

# You can also use query!/3, which is an alias for query_one!/3
MyApp.Reports.SQL.query!("stats.sql", [user_id])
# => %{id: 1, name: "Alice", total_sales: 1000}

# Get all rows
MyApp.Reports.SQL.query_all!("activity.sql", [company_id])
# => [%{id: 1, ...}, %{id: 2, ...}]

# Cast results to structs
MyApp.Reports.SQL.query_one!("stats.sql", [id], as: UserStats)
# => %UserStats{id: 1, name: "Alice", total_sales: 1000}

# Load the raw SQL string
MyApp.Reports.SQL.load!("stats.sql")
# => "SELECT id, name, total_sales..."
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

## Parameter Syntax by Database

Each database uses different parameter placeholder syntax:

| Database   | Syntax            | Example                                    |
|------------|-------------------|--------------------------------------------|
| PostgreSQL | `$1`, `$2`, ...   | `WHERE id = $1 AND age > $2`               |
| MySQL      | `?`               | `WHERE id = ? AND age > ?`                 |
| SQLite     | `?`               | `WHERE id = ? AND age > ?`                 |
| SQL Server | `@1`, `@2`, ...   | `WHERE id = @1 AND age > @2`               |
| ClickHouse | `{name:Type}`     | `WHERE id = {id:UInt32} AND age > {age:UInt32}` |

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
defmodule MyApp.Users do
  alias MyApp.Users.User

  def get_active_users(company_id, min_age) do
    SqlKit.query_all!(MyApp.Repo, """
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
defmodule MyApp.Users do
  alias MyApp.Users.User

  def get_active_users(company_id, min_age) do
    MyApp.Users.SQL.query_all!("active_users.sql", [company_id, min_age], as: User)
  end
end

# Usage
MyApp.Users.get_active_users(123, 21)
# => [%User{id: 1, name: "Alice", email: "alice@example.com", age: 30}, ...]
```

This pattern gives you named parameters through Elixir function arguments while keeping queries as plain SQL.

## Use SqlKit Options

- `:otp_app` (required) - Your application name
- `:repo` (required) - The Ecto repo module to use for queries
- `:dirname` (required) - Subdirectory within root_sql_dir for this module's SQL files
- `:files` (required) - List of SQL filenames to load

## API Reference

### Standalone Functions

These functions are defined directly on the `SqlKit` module and work with any Ecto repo:

#### `SqlKit.query_all!(repo, sql, params \\ [], opts \\ [])`

Executes SQL and returns all rows as a list of maps.

```elixir
SqlKit.query_all!(MyApp.Repo, "SELECT * FROM users")
# => [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

SqlKit.query_all!(MyApp.Repo, "SELECT * FROM users WHERE age > $1", [21], as: User)
# => [%User{id: 1, name: "Alice"}, ...]

# ClickHouse uses named parameters as a map
SqlKit.query_all!(ClickHouseRepo, "SELECT * FROM users WHERE age > {age:UInt32}", %{age: 21})
# => [%{id: 1, name: "Alice"}, ...]
```

#### `SqlKit.query_one!(repo, sql, params \\ [], opts \\ [])`

Executes SQL and returns exactly one row as a map.

- Raises `SqlKit.NoResultsError` if no rows returned
- Raises `SqlKit.MultipleResultsError` if more than one row returned

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

#### `SqlKit.query_all(repo, sql, params \\ [], opts \\ [])`

Returns `{:ok, results}` on success, `{:error, exception}` on failure.

```elixir
SqlKit.query_all(MyApp.Repo, "SELECT * FROM users")
# => {:ok, [%{id: 1, name: "Alice"}, ...]}

# ClickHouse uses named parameters as a map
SqlKit.query_all(ClickHouseRepo, "SELECT * FROM users WHERE age > {age:UInt32}", %{age: 21})
# => {:ok, [%{id: 1, name: "Alice"}, ...]}
```

#### `SqlKit.query_one(repo, sql, params \\ [], opts \\ [])`

Returns `{:ok, result}` on one result, `{:ok, nil}` on no results, or `{:error, exception}` on multiple results or errors.

```elixir
SqlKit.query_one(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [1])
# => {:ok, %{id: 1, name: "Alice"}}

SqlKit.query_one(MyApp.Repo, "SELECT * FROM users WHERE id = $1", [999])
# => {:ok, nil}

# ClickHouse uses named parameters as a map
SqlKit.query_one(ClickHouseRepo, "SELECT * FROM users WHERE id = {id:UInt32}", %{id: 1})
# => {:ok, %{id: 1, name: "Alice"}}
```

#### `SqlKit.query(repo, sql, params \\ [], opts \\ [])`

Alias for `SqlKit.query_one/4`. See `SqlKit.query_one/4` documentation.

### File-Based Functions

These functions are generated by `use SqlKit` and available on your SQL modules:

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

#### `query_all!(filename, params \\ [], opts \\ [])`

Executes a query and returns all rows as a list of maps.

```elixir
SQL.query_all!("users.sql", [company_id])
# => [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

SQL.query_all!("users.sql", [company_id], as: User)
# => [%User{id: 1, name: "Alice"}, %User{id: 2, name: "Bob"}]

# ClickHouse uses named parameters as a map
ClickHouseSQL.query_all!("users.sql", %{company_id: 123})
# => [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
```

#### `load!(filename)`

Returns the SQL string for the given file.

```elixir
SQL.load!("users.sql")
# => "SELECT * FROM users"
```

#### `query_one(filename, params \\ [], opts \\ [])`

```elixir
SQL.query_one("user.sql", [user_id])
# => {:ok, %{id: 1, name: "Alice"}}

SQL.query_one("missing_user.sql", [999])
# => {:ok, nil}  # No results returns nil, not an error

SQL.query_one("all_users.sql", [])
# => {:error, %SqlKit.MultipleResultsError{count: 10}}

# ClickHouse uses named parameters as a map
ClickHouseSQL.query_one("user.sql", %{user_id: 1})
# => {:ok, %{id: 1, name: "Alice"}}
```

#### `query(filename, params \\ [], opts \\ [])`

Alias for `query_one/3`. See `query_one/3` documentation.

#### `query_all(filename, params \\ [], opts \\ [])`

```elixir
SQL.query_all("users.sql", [company_id])
# => {:ok, [%{id: 1, name: "Alice"}, ...]}

# ClickHouse uses named parameters as a map
ClickHouseSQL.query_all("users.sql", %{company_id: 123})
# => {:ok, [%{id: 1, name: "Alice"}, ...]}
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

The test suite runs against all supported databases (PostgreSQL, MySQL, SQLite, SQL Server, and ClickHouse). All databases must be running for the full test suite to pass.

### Database Ports

- PostgreSQL: 5432
- MySQL: 3306
- SQL Server: 1433
- ClickHouse: 8123, 9000

SQLite uses a local file and doesn't require Docker.

### Before Pull Request

Run `mix check`.

## License

MIT License. See LICENSE.md for details.
