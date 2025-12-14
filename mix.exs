defmodule SqlDir.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :sql_dir,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      docs: docs(),
      package: package(),
      homepage_url: "https://hex.pm/packages/sql_dir",
      source_url: "https://github.com/tylerbarker/sql_dir",
      description: """
      Execute raw SQL files like Ecto queries with automatic result transformation to maps and structs.
      """
    ]
  end

  defp package do
    [
      maintainers: ["Tyler Barker"],
      licenses: ["MIT"],
      links: %{
        Changelog: "https://github.com/tylerbarker/sql_dir/blob/main/CHANGELOG.md",
        GitHub: "https://github.com/tylerbarker/sql_dir"
      },
      files: ~w(mix.exs lib README.md LICENSE.md CHANGELOG.md)
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      name: "SqlDir",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/sql_dir",
      source_url: "https://github.com/tylerbarker/sql_dir",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ]
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:postgrex, "~> 0.19", optional: true},
      {:myxql, "~> 0.7", optional: true},
      {:ecto_sqlite3, "~> 0.18", optional: true},
      {:tds, "~> 2.3", optional: true},
      {:ecto_ch, "~> 0.7", optional: true},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false, warn_if_outdated: true},
      {:ex_check, "~> 0.16.0", only: [:dev], runtime: false},
      {:styler, "~> 1.10", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false, warn_if_outdated: true}
    ]
  end
end
