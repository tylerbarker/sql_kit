defmodule SqlDir.MixProject do
  use Mix.Project

  def project do
    [
      app: :sql_dir,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:postgrex, "~> 0.17", optional: true},
      {:myxql, "~> 0.6", optional: true},
      {:ecto_sqlite3, "~> 0.13", optional: true},
      {:tds, "~> 2.3", optional: true},
      {:ecto_ch, "~> 0.3", optional: true},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end
end
