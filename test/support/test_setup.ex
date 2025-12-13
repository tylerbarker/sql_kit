defmodule SqlDir.TestSetup do
  @moduledoc """
  Handles test database setup and teardown.

  This module creates test databases, runs schema migrations,
  and seeds test data for each supported adapter.
  """

  @repos [
    {:postgres, SqlDir.Test.PostgresRepo},
    {:mysql, SqlDir.Test.MySQLRepo},
    {:sqlite, SqlDir.Test.SQLiteRepo},
    {:tds, SqlDir.Test.TdsRepo}
  ]

  @doc """
  Sets up all test databases.
  """
  def setup_all do
    for {adapter, repo} <- @repos do
      setup_repo(adapter, repo)
      IO.puts("  #{adapter}: OK")
    end

    :ok
  end

  @doc """
  Tears down all test databases.
  """
  def teardown_all do
    for {_adapter, repo} <- @repos do
      try do
        Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)
        repo.stop()
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end

    # Clean up SQLite files
    for postfix <- ["db", "db-shm", "db-wal"] do
      db_file = "test/support/sql_dir_test.#{postfix}"
      File.exists?(db_file) && File.rm(db_file)
    end

    :ok
  end

  defp setup_repo(adapter, repo) do
    # Create database if it doesn't exist (not needed for SQLite)
    if adapter != :sqlite do
      ensure_database_created(repo)
    end

    # Start the repo
    {:ok, _} = repo.start_link()

    # Run migrations
    run_migrations(adapter, repo)

    # Set sandbox mode
    Ecto.Adapters.SQL.Sandbox.mode(repo, :manual)
  end

  defp ensure_database_created(repo) do
    case repo.__adapter__().storage_up(repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      {:error, reason} -> raise "Failed to create database: #{inspect(reason)}"
    end
  end

  defp run_migrations(adapter, repo) do
    # Create the users table used in tests
    create_users_table(adapter, repo)
    # Seed test data
    seed_test_data(repo)
  end

  defp create_users_table(:postgres, repo) do
    repo.query!("""
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      email VARCHAR(255) NOT NULL,
      age INTEGER
    )
    """)
  end

  defp create_users_table(:mysql, repo) do
    repo.query!("""
    CREATE TABLE IF NOT EXISTS users (
      id INT AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      email VARCHAR(255) NOT NULL,
      age INT
    )
    """)
  end

  defp create_users_table(:sqlite, repo) do
    repo.query!("""
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      email TEXT NOT NULL,
      age INTEGER
    )
    """)
  end

  defp create_users_table(:tds, repo) do
    # Check if table exists first for TDS
    result =
      repo.query!("""
      SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_NAME = 'users'
      """)

    {_, [[count]]} = SqlDir.extract_result(result)

    if count == 0 do
      repo.query!("""
      CREATE TABLE users (
        id INT IDENTITY(1,1) PRIMARY KEY,
        name NVARCHAR(255) NOT NULL,
        email NVARCHAR(255) NOT NULL,
        age INT
      )
      """)
    end
  end

  defp truncate_table(Ecto.Adapters.Postgres, repo) do
    repo.query!("TRUNCATE TABLE users RESTART IDENTITY")
  end

  defp truncate_table(Ecto.Adapters.MyXQL, repo) do
    repo.query!("TRUNCATE TABLE users")
  end

  defp truncate_table(Ecto.Adapters.SQLite3, repo) do
    repo.query!("DELETE FROM users")
    repo.query!("DELETE FROM sqlite_sequence WHERE name = 'users'")
  end

  defp truncate_table(Ecto.Adapters.Tds, repo) do
    repo.query!("TRUNCATE TABLE users")
  end

  defp seed_test_data(repo) do
    # Clear existing data and reset auto-increment
    adapter = repo.__adapter__()
    truncate_table(adapter, repo)

    # Insert test users
    users = [
      {"Alice", "alice@example.com", 30},
      {"Bob", "bob@example.com", 25},
      {"Charlie", "charlie@example.com", 35}
    ]

    for {name, email, age} <- users do
      insert_user(adapter, repo, name, email, age)
    end
  end

  defp insert_user(Ecto.Adapters.Postgres, repo, name, email, age) do
    repo.query!(
      "INSERT INTO users (name, email, age) VALUES ($1, $2, $3)",
      [name, email, age]
    )
  end

  defp insert_user(Ecto.Adapters.MyXQL, repo, name, email, age) do
    repo.query!(
      "INSERT INTO users (name, email, age) VALUES (?, ?, ?)",
      [name, email, age]
    )
  end

  defp insert_user(Ecto.Adapters.SQLite3, repo, name, email, age) do
    repo.query!(
      "INSERT INTO users (name, email, age) VALUES (?, ?, ?)",
      [name, email, age]
    )
  end

  defp insert_user(Ecto.Adapters.Tds, repo, name, email, age) do
    repo.query!(
      "INSERT INTO users (name, email, age) VALUES (@1, @2, @3)",
      [name, email, age]
    )
  end
end
