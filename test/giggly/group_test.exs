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

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 groups `colour = factor(v)` over
    # `v = c(10, 9, 100, NA)` 2, 1, 3, 4: the levels in order of value, `NA` last.
    test "a category's values are discrete, numbers among them, in order of value" do
      frame = DataFrame.new([{:color, [10, 9, 100, nil], :category}, {:y, [1.0, 2.0, 3.0, 4.0]}])

      assert group_ids(frame) === [2, 1, 3, 4]
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 groups `colour = factor(cyl, levels =
    # c(8, 4, 6))` over `mtcars` 3 for a 6, 2 for a 4 and 1 for an 8: the levels' order, not the
    # values'.
    test "a category with levels is numbered in its levels' order, nil after them" do
      levelled = {:category, levels: [8, 4, 6]}

      frame =
        DataFrame.new([{:color, [6.0, 4.0, 8.0, nil, 4.0], levelled}, {:y, [1, 2, 3, 4, 5]}])

      assert group_ids(frame) === [3, 2, 1, 4, 2]
    end

    test "a category's levels order it beside a column without levels" do
      frame =
        DataFrame.new([
          {:fill, ["a", "b", "a", "b"], {:category, levels: ["b", "a"]}},
          {:shape, ["q", "q", "p", "p"]}
        ])

      assert group_ids(frame) === [4, 2, 3, 1]
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

    # ggplot2's `add_group()` leaves `label` out of the key, so each label is not a group of its own.
    test "a text's labels never group, while another discrete column beside them does" do
      frame = DataFrame.new(label: ["Mazda", "Fiat", "Mazda"], color: ["b", "a", "a"])

      assert group_ids(frame) === [2, 1, 1]
    end

    test "with no discrete column every row is -1, no grouping" do
      frame = DataFrame.new(x: [2.62, 2.875], y: [21.0, 22.8])

      assert group_ids(frame) === [-1, -1]
    end
  end
end
