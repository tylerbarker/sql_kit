# SqlDir

[Hex](https://hex.pm) | [Documentation](https://hexdocs.pm/sql_dir)

Execute raw SQL files like Ecto queries with automatic result transformation to maps and structs.

SqlDir lets you write queries as `.sql` files and execute them with results automatically transformed into maps or structs. SQL files are embedded at compile time for production performance, while reading from disk in dev/test to facilitate rapid iteration.

## Why?

Sometimes raw SQL is the right tool for the job. Complex analytical queries, reports with intricate joins, or database-specific features often demand SQL that's awkward to express through an ORM.

Keeping SQL in dedicated `.sql` files brings other practical benefits: Proper syntax highlighting, SQL formatter support, and cleaner Elixir modules without large multi-line strings. It also makes your codebase more accessible to SQL-fluent team members: Product managers, analysts, or DBAs can read, review, and contribute queries without needing to learn Elixir first.

You can do this already with `File.read` and `Repo.query`, however:
1. `Repo.query` returns a result struct with separate `columns` and `rows` lists. Transforming this into usable maps requires boilerplate. SqlDir handles this automatically, returning maps `[%{id: 1, name: "Alice"}, ...]` or structs `[%User{id: 1, name: "Alice"}, ...]` directly.
2. Reading a file from disk whenever you call a function querying the database is unnecessary I/O overhead.

## Features

- **Automatic result transformation**: Query results returned as maps or structs, not raw columns/rows
- **Compile-time embedding**: SQL read once at compile time and stored as module attributes
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

Add `sql_dir` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sql_dir, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Create SQL files

SQL files are house in subdirectories under the root SQL directory. This is `priv/repo/sql` by default but it is configurable via `:root_sql_dir` config option. Note that whatever you choose must be in `priv` for SQL files to be shipped with your application.

Create a new directory for some SQL:

```sql
-- priv/repo/sql/reports/stats.sql
SELECT id, name, total_sales
FROM users
WHERE id = $1
```

### 2. Define a SQL module

```elixir
defmodule MyApp.Reports.SQL do
  @moduledoc """
  This module would expect stats.sql and activity.sql to be in priv/repo/sql/reports.
  """
  use SqlDir,
    otp_app: :my_app,
    repo: MyApp.Repo,
    dirname: "reports",
    files: ["stats.sql", "activity.sql"]
end
```

### 3. Execute queries

```elixir
# Execute and get a single row as a map
MyApp.Reports.SQL.query_one!("stats.sql", [user_id])
# => %{id: 1, name: "Alice", total_sales: 1000}

# You can also just call query!/3 (or query/3), which is an alias for query_one!/3
MyApp.Reports.SQL.query!("stats.sql", [user_id])
# => %{id: 1, name: "Alice", total_sales: 1000}

# Execute and get all rows
MyApp.Reports.SQL.query_all!("activity.sql", [company_id])
# => [%{id: 1, ...}, %{id: 2, ...}]

# Cast results to structs
MyApp.Reports.SQL.query_one!("stats.sql", [id], as: UserStats)
# => %UserStats{id: 1, name: "Alice", total_sales: 1000}

# If you need, you can load the SQL string too
MyApp.Reports.SQL.load!("stats.sql")
```

## Configuration

```elixir
# config/config.exs
config :my_app, SqlDir,
  root_sql_dir: "priv/repo/sql"  # default

# config/dev.exs and config/test.exs (of course, you can use :compiled for tests if you like)
config :my_app, SqlDir,
  load_sql: :dynamic  # read from disk at runtime

# config/prod.exs (or rely on default)
config :my_app, SqlDir,
  load_sql: :compiled  # use compile-time embedded SQL
```

## API Reference

### `query!(filename, params \\ [], opts \\ [])`

Alias for `query_one!/3`. See `query_one!/3` documentation.

### `query_one!(filename, params \\ [], opts \\ [])`

Executes a query and returns a single row as a map.

- Raises `SqlDir.NoResultsError` if no rows returned
- Raises `SqlDir.MultipleResultsError` if more than one row returned

```elixir
SQL.query_one!("user.sql", [user_id])
# => %{id: 1, name: "Alice"}

SQL.query_one!("user.sql", [user_id], as: User)
# => %User{id: 1, name: "Alice"}

# ClickHouse uses named parameters as a map
ClickHouseSQL.query_one!("user.sql", %{user_id: 1})
# => %{id: 1, name: "Alice"}
```

### `query_all!(filename, params \\ [], opts \\ [])`

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

### `load!(filename)`

Returns the SQL string for the given file.

```elixir
SQL.load!("users.sql")
# => "SELECT * FROM users"
```

### `query(filename, params \\ [], opts \\ [])`

Alias for `query_one/3`. See `query_one/3` documentation.

### `query_one(filename, params \\ [], opts \\ [])`

```elixir
SQL.query_one("user.sql", [user_id])
# => {:ok, %{id: 1, name: "Alice"}}

SQL.query_one("missing_user.sql", [999])
# => {:ok, nil}  # No results returns nil, not an error

SQL.query_one("all_users.sql", [])
# => {:error, %SqlDir.MultipleResultsError{count: 10}}

# ClickHouse uses named parameters as a map
ClickHouseSQL.query_one("user.sql", %{user_id: 1})
# => {:ok, %{id: 1, name: "Alice"}}
```

### `query_all(filename, params \\ [], opts \\ [])`

```elixir
SQL.query_all("users.sql", [company_id])
# => {:ok, [%{id: 1, name: "Alice"}, ...]}

SQL.query_all("bad_query.sql", [])
# => {:error, %Postgrex.Error{...}}

# ClickHouse uses named parameters as a map
ClickHouseSQL.query_all("users.sql", %{company_id: 123})
# => {:ok, [%{id: 1, name: "Alice"}, ...]}
```

### `load(filename)`

```elixir
SQL.load("users.sql")
# => {:ok, "SELECT * FROM users"}

SQL.load("missing.sql")
# => {:error, %RuntimeError{...}}
```

### Options

- `:as` - Struct module to cast results into
- `:unsafe_atoms` - If `true`, uses `String.to_atom/1` instead of `String.to_existing_atom/1` for column names. Default: `false`

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

## Use SqlDir Options

- `:otp_app` (required) - Your application name
- `:repo` (required) - The Ecto repo module to use for queries
- `:dirname` (required) - Subdirectory within root_sql_dir for this module's SQL files
- `:files` (required) - List of SQL filenames to load

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
