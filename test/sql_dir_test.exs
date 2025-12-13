defmodule SqlDirTest do
  use ExUnit.Case
  doctest SqlDir

  test "greets the world" do
    assert SqlDir.hello() == :world
  end
end
