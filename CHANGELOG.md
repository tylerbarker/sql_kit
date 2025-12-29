# Changelog

## 0.2.0

### Breaking Changes

- **API aligned with Ecto Repo conventions** - This is a breaking change that simplifies the API to match [`Ecto.Repo.all/2`](https://hexdocs.pm/ecto/Ecto.Repo.html#c:all/2) and [`Ecto.Repo.one/2`](https://hexdocs.pm/ecto/Ecto.Repo.html#c:one/2) semantics.

  **`query_all/4` now returns list directly** (was `{:ok, list}`)
  ```elixir
  # Before
  {:ok, users} = SqlKit.query_all(Repo, "SELECT * FROM users")

  # After
  users = SqlKit.query_all(Repo, "SELECT * FROM users")
  ```

  **`query_all!/4` removed** (use `query_all/4` instead)
  ```elixir
  # Before
  users = SqlKit.query_all!(Repo, "SELECT * FROM users")

  # After
  users = SqlKit.query_all(Repo, "SELECT * FROM users")
  ```

  **`query_one/4` now returns result or nil directly** (was `{:ok, result | nil}`)
  ```elixir
  # Before
  {:ok, user} = SqlKit.query_one(Repo, "SELECT * FROM users WHERE id = $1", [1])
  {:ok, nil} = SqlKit.query_one(Repo, "SELECT * FROM users WHERE id = $1", [999])

  # After
  user = SqlKit.query_one(Repo, "SELECT * FROM users WHERE id = $1", [1])
  nil = SqlKit.query_one(Repo, "SELECT * FROM users WHERE id = $1", [999])
  ```

  **`query_one/4` now raises on multiple results** (was `{:error, MultipleResultsError}`)
  ```elixir
  # Before
  {:error, %SqlKit.MultipleResultsError{}} =
    SqlKit.query_one(Repo, "SELECT * FROM users")

  # After
  # Raises SqlKit.MultipleResultsError
  SqlKit.query_one(Repo, "SELECT * FROM users")
  ```

  **File-based API follows same changes:**
  - `MyModule.query_all/3` returns list directly
  - `MyModule.query_all!/3` removed
  - `MyModule.query_one/3` returns result or nil, raises on multiple

### Added

- **DuckDB support** via `duckdbex` driver
  - `SqlKit.DuckDB.connect/2` and `disconnect/1` for direct connections
  - `SqlKit.DuckDB.Pool` - NimblePool-based connection pool with supervision
  - File-based SQL support via `:backend` option (`backend: {:duckdb, pool: PoolName}`)
  - Automatic hugeint to integer conversion
  - PostgreSQL-style `$1, $2, ...` parameter placeholders

- **Prepared statement caching** for DuckDB pools
  - Automatic caching of prepared statements per connection
  - Configurable via `:cache` option (default: true)

- **Streaming support** for DuckDB large result sets
  - `SqlKit.DuckDB.stream!/3` and `stream_with_columns!/3` for direct connections
  - `SqlKit.DuckDB.Pool.with_stream!/5` and `with_stream_and_columns!/6` for pools
  - `with_stream!/3` and `with_stream_and_columns!/4` for file-based SQL modules

- **Pool tuning options**
  - `:timeout` option for checkout operations (default: 5000ms)
  - Lazy connection initialization
  - Documented pool behavior and configuration

## 0.1.0

- Initial release
