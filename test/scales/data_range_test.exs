defmodule Scales.DataRangeTest do
  use ExUnit.Case, async: true

  alias Scales.DataRange

  doctest Scales.DataRange

  describe "train_continuous/2" do
    # R 4.6.1's `train_continuous(c(NA, 3, Inf, -2, -Inf, NaN))` is `-2 3`, and 7 then `-2 7`.
    test "a range spans the finite numbers only, across trainings" do
      range = DataRange.train_continuous(:none, [nil, 3, :infinity, -2, :neg_infinity, :nan])

      assert {range, DataRange.train_continuous(range, [7])} === {{-2, 3}, {-2, 7}}
    end

    test "no finite number leaves the range as it was, none among them" do
      assert {DataRange.train_continuous(:none, [nil, :infinity]),
              DataRange.train_continuous({1.5, 2}, [:nan, nil])} === {:none, {1.5, 2}}
    end
  end

  # Golden, each training a layer's `x` in turn: `layer_scales()` in R 4.6.1 with ggplot2 4.0.3
  # and scales 1.4.0, whose `DiscreteRange` trains it, `drop = TRUE`; a missing value `nil`.
  describe "train_discrete/3" do
    # Golden: R 4.6.1's `levels(factor(c(10, 9, 100, NA)))` is `9 10 100`, `NA` kept last.
    test "numbers are levels in order of value, nil last" do
      assert levels_after([{[10, 9, nil, 100, 9], :none}]) === [9, 10, 100, nil]
    end

    # Golden: R 4.6.1's `levels(factor(c(0, 1e-20)))`, and a `DiscreteRange` trained on that factor
    # (scales 1.4.0), are two levels, `0` and `1e-20`: numbers are matched as floats, so however
    # close two are, they are one level only when equal.
    test "numbers however close are distinct levels unless equal" do
      assert DataRange.train_discrete({[], :none}, [1.0e-20, 0], :none) === {[0, 1.0e-20], false}
    end

    test "a factor's levels lead the values without levels, in either order" do
      factor = {["b", "a"], ["b", "a"]}
      text = {["c", "a"], :none}

      assert {levels_after([factor, text]), levels_after([text, factor])} ===
               {["b", "a", "c"], ["b", "a", "c"]}
    end

    # The range remembers whether its first values were a factor's.
    test "past two trainings, a range whose first values were a factor's keeps their order" do
      factor = {["b", "a"], ["b", "a"]}
      text = {["c", "a"], :none}
      more_text = {["d", "0"], :none}

      assert {levels_after([factor, text, more_text]), levels_after([text, factor, more_text])} ===
               {["b", "a", "c", "0", "d"], ["0", "a", "b", "c", "d"]}
    end

    # Factors with levels `c("b", "a")` and `c("z", "a")`, and levels `c("c", "b", "a")` over the
    # values `b` and `a`, which drop `c`.
    test "two factors' levels follow each other, and a level no value holds is dropped" do
      assert {levels_after([{["b", "a"], ["b", "a"]}, {["z", "a"], ["z", "a"]}]),
              levels_after([{["b", "a"], ["c", "b", "a"]}])} === {["b", "a", "z"], ["b", "a"]}
    end

    # The factor's values `b`, `NA` and `a` beside the text `c` and `a`, and its values `b` and `a`
    # beside the text `c` and `NA`.
    test "a missing value follows a factor's levels, and the values after it follow it" do
      factor_missing = {["b", nil, "a"], ["b", "a"]}
      text = {["c", "a"], :none}
      factor = {["b", "a"], ["b", "a"]}
      text_missing = {["c", nil], :none}

      assert {levels_after([factor_missing, text]), levels_after([text, factor_missing]),
              levels_after([factor, text_missing]), levels_after([text_missing, factor])} ===
               {["b", "a", nil, "c"], ["b", "a", nil, "c"], ["b", "a", "c", nil],
                ["b", "a", "c", nil]}
    end

    # The factor's values `b`, `NA` and `a`, then the text `c` and `a`, then `d`: each training
    # reads the levels held as a factor's, which moves the missing value last.
    test "where the first values were a factor's, the missing value moves last before each merge" do
      steps = [{["b", nil, "a"], ["b", "a"]}, {["c", "a"], :none}, {["d"], :none}]

      assert levels_after(steps) === ["b", "a", "c", nil, "d"]
    end

    # A first layer with no rows, a factor's, then the text `c` and `a`, then `d` and `0`, sorts
    # them: no rows train nothing, so the factor sets nothing.
    test "values that are none train nothing, so a factor with no rows sets nothing" do
      steps = [{[], ["z"]}, {["c", "a"], :none}, {["d", "0"], :none}]

      assert levels_after(steps) === ["0", "a", "c", "d"]
    end

    # R writes a factor's levels as text, so its `4` and `4.0` are one level, "4".
    test "two factors' levels equal as numbers are one level" do
      assert levels_after([{[4], [4]}, {[4.0, 6.0], [4.0, 6.0]}]) === [4, 6.0]
    end
  end

  describe "level_key/1 and key/1" do
    test "nil sorts after every value, the rest in Erlang's term order" do
      assert Enum.sort_by([nil, "b", 2, :c, "a", false, 1.5], &DataRange.level_key/1) ===
               [1.5, 2, :c, false, "a", "b", nil]
    end

    test "a number is matched as a float, a negative zero as zero, and any other value as it is" do
      assert {DataRange.key(4), DataRange.key(4.0), DataRange.key(-0.0), DataRange.key(nil),
              DataRange.key("4")} === {4.0, 4.0, 0.0, nil, "4"}
    end
  end

  # The levels of a range once trained on each `{values, levels}` in turn, `levels` the factor's
  # the values are of, or `:none`.
  defp levels_after(steps) do
    {levels, _factor} =
      Enum.reduce(steps, {[], :none}, fn {values, levels}, range ->
        DataRange.train_discrete(range, values, levels)
      end)

    levels
  end
end
