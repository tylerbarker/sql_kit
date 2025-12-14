[
  ## don't run tools concurrently
  parallel: false,

  ## don't print info about skipped tools
  # skipped: false,

  ## always run tools in fix mode (put it in ~/.check.exs locally, not in project config)
  # fix: true,

  ## don't retry automatically even if last run resulted in failures
  # retry: false,

  ## list of tools (see `mix check` docs for a list of default curated tools)
  tools: [
    {:formatter, "mix format"},
    {:compiler, "mix compile"},
    {:dialyzer, "mix dialyzer"},
    {:credo, "mix credo"},
    {:sobelow, "mix sobelow --skip"},
    {:ex_unit, "mix test"}
  ]
]
