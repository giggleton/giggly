defmodule Scales.BoundsTest do
  use ExUnit.Case, async: true

  alias Scales.Bounds

  doctest Scales.Bounds

  # Golden: R 4.6.1's `scales::rescale()`, `rescale_mid()`, `rescale_max()` and `oob_censor()`
  # (scales 1.4.0) on each case, R's figures to the last digit, `NA` and `NaN` as `nil`.
  describe "rescale/3" do
    test "a value moves linearly from one range to another, in R's order of operations" do
      assert Bounds.rescale([2, 4, 10, 6, 3.3], {2, 10}, {0, 1}) ===
               [0.0, 0.25, 1.0, 0.5, 0.16249999999999998]
    end

    test "a range onto a reversed one, and a missing value left missing" do
      assert {Bounds.rescale([2, 6, 3.3], {2, 10}, {10, -10}),
              Bounds.rescale([2, nil, 10], {2, 10}, {0, 1})} ===
               {[10.0, 0.0, 6.75], [0.0, nil, 1.0]}
    end

    test "a range of zero width puts every value at the middle of the other" do
      assert {Bounds.rescale([5], {5, 5}, {0, 1}), Bounds.rescale([5], {5, 5}, {0.1, 1.0}),
              Bounds.rescale([3, nil], {3, 3}, {0, 1})} === {[0.5], [0.55], [0.5, nil]}
    end

    # R's `rescale(c(0, 5, 10, NA), to = c(1, 1 + 1e-15), from = c(0, 10))`: `to` is zero wide by
    # `zero_range()`, so every value is its middle, where the formula would spread them.
    test "a range rescaled onto one of zero width puts every value at its middle" do
      assert Bounds.rescale([0, 5, 10, nil], {0, 10}, {1.0, 1.0 + 1.0e-15}) ===
               [1.0000000000000004, 1.0000000000000004, 1.0000000000000004, nil]
    end

    # Where every value goes to the middle, none is read, so only the check refuses one.
    test "a value that is neither a number nor nil is refused, even onto a range's middle" do
      assert_raise FunctionClauseError, fn -> Bounds.rescale([:infinity], {3, 3}, {0, 1}) end
    end
  end

  describe "rescale_mid/4" do
    test "the midpoint goes to the middle and the further end to its end, in R's order" do
      assert {Bounds.rescale_mid([-1, 0, 3, nil], {-1, 3}, {0, 1}, 1),
              Bounds.rescale_mid([-1, 0, 3, 0.3], {-1, 3}, {10, 20}, 1)} ===
               {[0.0, 0.25, 1.0, nil], [10.0, 12.5, 20.0, 13.25]}
    end

    test "either range of zero width puts every value at the middle of the other" do
      assert {Bounds.rescale_mid([2, nil], {2, 2}, {0.2, 0.6}, 1),
              Bounds.rescale_mid([-1, 3], {-1, 3}, {1.0, 1.0 + 1.0e-15}, 1)} ===
               {[0.4, nil], [1.0000000000000004, 1.0000000000000004]}
    end
  end

  describe "rescale_max/3" do
    test "a value over the high end, times the other's high end, the low ends unread" do
      assert {Bounds.rescale_max([110, 93, 52, nil], {52, 335}, {0, 1}),
              Bounds.rescale_max([1, 2, 0.3], {0, 4}, {5, 6})} ===
               {[0.32835820895522388, 0.27761194029850744, 0.15522388059701492, nil],
                [1.5, 3.0, 0.44999999999999996]}
    end

    # R's IEEE division: a value over zero is an infinity of its sign, a negative zero turning it,
    # and zero over zero is NaN; an infinity times a high end of 0 is NaN too.
    test "over a high end of 0, a value is an infinity of the signs' product, or NaN" do
      assert {Bounds.rescale_max([0, 1, -1, nil], {-2, 0}, {0, 1}),
              Bounds.rescale_max([-1, 1, 0], {-2, -0.0}, {0, 1}),
              Bounds.rescale_max([1, -1], {0, 0.0}, {0, -1}),
              Bounds.rescale_max([1, -1], {0, 0}, {0, 0})} ===
               {[nil, :infinity, :neg_infinity, nil], [:infinity, :neg_infinity, nil],
                [:neg_infinity, :infinity], [nil, nil]}
    end
  end

  describe "zero_range?/1" do
    # Golden: R 4.6.1's `scales::zero_range()` (scales 1.4.0) on each pair: ends 1000 machine
    # epsilons apart, relative to the smaller, are not zero wide and 999 are, either sign. Moves
    # only with R's tolerance, `1000 * .Machine$double.eps`.
    test "ends closer than R's tolerance relative to the smaller are zero wide, ends at it are not" do
      assert {Bounds.zero_range?({1.0, 1.000000000000222}),
              Bounds.zero_range?({1.0, 1.0000000000002218}),
              Bounds.zero_range?({-1.000000000000222, -1.0}),
              Bounds.zero_range?({-1.0000000000002218, -1.0})} === {false, true, false, true}
    end
  end

  describe "censor/2" do
    # R's `oob_censor(c(1, 5, 10, NA, Inf, -Inf, NaN, 2, 8), c(2, 8))` is `NA 5 NA NA Inf -Inf NaN
    # 2 8`: the ends themselves are kept, and NaN, here `:nan`, becomes `nil`.
    test "a finite number outside the range is nil, the ends and the infinities kept" do
      assert Bounds.censor([1, 5, 10, nil, :infinity, :neg_infinity, :nan, 2, 8], {2, 8}) ===
               [nil, 5, nil, nil, :infinity, :neg_infinity, nil, 2, 8]
    end

    test "an end of nil censors nothing on its side" do
      assert {Bounds.censor([1, 10], {nil, 8}), Bounds.censor([1, 10], {2, nil})} ===
               {[1, nil], [nil, 10]}
    end
  end
end
