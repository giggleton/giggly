defmodule Giggly.FactorTest do
  use ExUnit.Case, async: true

  alias Giggly.Factor

  doctest Giggly.Factor

  describe "new/2" do
    test "a factor holds its values, its levels or :default, and whether they are ordered" do
      assert {Factor.new(["b", "a"]), Factor.new(["b"], levels: ["b", "a"], ordered: true)} ===
               {%Factor{values: ["b", "a"], levels: :default, ordered: false},
                %Factor{values: ["b"], levels: ["b", "a"], ordered: true}}
    end

    test "its options are levels:, a list, and ordered:, a boolean" do
      for options <- [[levels: "a"], [ordered: "yes"], [level: ["a"]]] do
        assert_raise NimbleOptions.ValidationError, fn -> Factor.new(["a"], options) end
      end
    end
  end

  describe "as an enumerable" do
    test "a factor enumerates as its values, in row order" do
      factor = Factor.new(["Ideal", "Fair", "Ideal"], levels: ["Fair", "Ideal"])

      assert {Enum.to_list(factor), Enum.count(factor), Enum.member?(factor, "Fair"),
              Enum.slice(factor, 1, 2)} ===
               {["Ideal", "Fair", "Ideal"], 3, true, ["Fair", "Ideal"]}
    end

    # Explorer's `DataFrame.new/1` and Kino's data table read a table through `Table.Reader`, which
    # takes any enumerable as a column, so they read a factor's values.
    test "a table holding a factor is read through Table.Reader as its values" do
      table = [cut: Factor.new(["Ideal", "Fair"], levels: ["Fair", "Ideal"]), price: [326, 327]]

      {:columns, %{columns: names}, columns} = Table.Reader.init(table)

      assert {names, Enum.map(columns, &Enum.to_list/1)} ===
               {[:cut, :price], [["Ideal", "Fair"], [326, 327]]}
    end
  end
end
