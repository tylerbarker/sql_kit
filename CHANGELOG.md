# Changelog

## Unreleased

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
