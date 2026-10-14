defmodule Giggly.GroupTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Group, Scale}

  # The `:group` column `add/2` gives `frame`, ordered as the assembly orders it.
  defp group_ids(frame) do
    frame
    |> Group.add(&Scale.level_key/1)
    |> DataFrame.pull(:group)
  end

  describe "add/2" do
    test "discrete values are numbered in level order, nil last, and a float column is ignored" do
      frame = DataFrame.new(x: ["b", "a", "b", nil], y: [21.0, 22.8, 21.4, 18.7])

      assert group_ids(frame) === [2, 1, 2, 3]
    end

    test "two discrete columns are compared one at a time in column order" do
      frame =
        DataFrame.new(
          manual: [true, false, true, false],
          shape: [:circle, :square, :square, :circle]
        )

      assert group_ids(frame) === [3, 2, 4, 1]
    end

    test "a mapped group is renumbered on its own values and a discrete column is ignored" do
      frame = DataFrame.new(group: [10, 2, 10], x: ["a", "b", "c"])

      assert group_ids(frame) === [2, 1, 2]
    end

    test "with no discrete column every row is -1, no grouping" do
      frame = DataFrame.new(x: [2.62, 2.875], y: [21.0, 22.8])

      assert group_ids(frame) === [-1, -1]
    end
  end
end
