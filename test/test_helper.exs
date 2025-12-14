IO.puts("\nSetting up test databases...")
SqlKit.TestSetup.setup_all()
IO.puts("")

ExUnit.start()

ExUnit.after_suite(fn _ ->
  SqlKit.TestSetup.teardown_all()
end)
