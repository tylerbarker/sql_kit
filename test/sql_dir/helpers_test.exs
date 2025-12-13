defmodule SqlDir.HelpersTest do
  use ExUnit.Case, async: true

  alias SqlDir.Helpers

  describe "file_atom/1" do
    test "converts simple filename to atom" do
      assert Helpers.file_atom("stats.sql") == :stats_sql
    end

    test "converts filename with underscores" do
      assert Helpers.file_atom("stats_query.sql") == :stats_query_sql
    end

    test "replaces hyphens with underscores" do
      assert Helpers.file_atom("my-query.sql") == :my_query_sql
    end

    test "replaces multiple dots with underscores" do
      assert Helpers.file_atom("my.complex.query.sql") == :my_complex_query_sql
    end

    test "replaces mixed special characters" do
      assert Helpers.file_atom("my-complex.query.sql") == :my_complex_query_sql
    end

    test "handles numbers in filename" do
      assert Helpers.file_atom("query_v2.sql") == :query_v2_sql
    end

    test "handles consecutive special characters" do
      assert Helpers.file_atom("my--query..sql") == :my__query__sql
    end
  end
end
