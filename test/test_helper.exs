IO.puts("\nSetting up test databases...")
SqlDir.TestSetup.setup_all()
IO.puts("")

ExUnit.start()

ExUnit.after_suite(fn _ ->
  SqlDir.TestSetup.teardown_all()
end)
