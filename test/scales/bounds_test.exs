defmodule Scales.BoundsTest do
  use ExUnit.Case, async: true

  alias Scales.Bounds

  doctest Scales.Bounds

  # Golden: R 4.6.1's `scales::rescale()`, `rescale_mid()`, `rescale_max()`, `rescale_none()`,
  # `zero_range()` and `oob_*()` (scales 1.4.0) on each case, R's figures to the last digit, `NA`
  # as `nil`, `NaN` as `:nan` and `Inf` as `:infinity`.

  # R's `c(-Inf, -1, 0, 0.5, 1, 2, Inf, NA, NaN)`, every kind of double either side of 0 to 1.
  @doubles [:neg_infinity, -1, 0, 0.5, 1, 2, :infinity, nil, :nan]
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

    # Where every value goes to the middle, none is read, so only the check refuses one; elsewhere
    # the check refuses it before the arithmetic does.
    test "a value that is not a double is refused, even onto a range's middle" do
      assert_raise FunctionClauseError, fn -> Bounds.rescale(["a"], {3, 3}, {0, 1}) end
      assert_raise FunctionClauseError, fn -> Bounds.rescale(["a"], {0, 1}, {0, 1}) end
    end

    # R's `rescale()` fails on an `NA` end, as `zero_range()` gives `NA`. The end is built as the
    # test runs: a literal the guard refuses fails the type checker.
    test "an end that is not a number or an infinity is refused" do
      nan = Enum.at([:nan], 0)

      assert_raise FunctionClauseError, fn -> Bounds.rescale([], {0, nan}, {0, 1}) end
      assert_raise FunctionClauseError, fn -> Bounds.rescale([], {0, 1}, {nan, 1}) end
    end

    # R's `rescale(x, c(0, 1), c(0, 1))` and `rescale(x, c(0, 10), c(0, 2))`.
    test "an infinity and NaN go through R's arithmetic, a missing value left missing" do
      assert {Bounds.rescale(@doubles, {0, 1}, {0, 1}), Bounds.rescale(@doubles, {0, 2}, {0, 10})} ===
               {[:neg_infinity, -1.0, 0.0, 0.5, 1.0, 2.0, :infinity, nil, :nan],
                [:neg_infinity, -5.0, 0.0, 2.5, 5.0, 10.0, :infinity, nil, :nan]}
    end

    # R's `rescale(x, c(0, 1), c(0, Inf))`, `c(-Inf, Inf)`, and onto `c(0, Inf)` from `c(0, 2)`:
    # a number over an infinite width is 0, an infinity over one NaN, and 0 times one NaN. R's
    # `1 / rescale(-1, c(0, 1), c(0, Inf))` is `Inf`: the zero is positive once 0 is added.
    test "a range with an infinite end rescales by IEEE arithmetic" do
      assert {Bounds.rescale(@doubles, {0, :infinity}, {0, 1}),
              Bounds.rescale(@doubles, {:neg_infinity, :infinity}, {0, 1}),
              Bounds.rescale(@doubles, {0, 2}, {0, :infinity})} ===
               {[:nan, 0.0, 0.0, 0.0, 0.0, 0.0, :nan, nil, :nan],
                [:nan, :nan, :nan, :nan, :nan, :nan, :nan, nil, :nan],
                [
                  :neg_infinity,
                  :neg_infinity,
                  :nan,
                  :infinity,
                  :infinity,
                  :infinity,
                  :infinity,
                  nil,
                  :nan
                ]}
    end

    # R's `rescale(x, c(0, 1), c(1, 1))` and `c(Inf, Inf)`: both ranges are zero wide, so every
    # value is the middle, but `NA` for `NA` and `NaN`, as `ifelse(is.na(x), NA, mean(to))`; and
    # `rescale(c(-Inf, Inf), c(-Inf, Inf), c(Inf, Inf))` is `NaN NaN`, the infinities' mean.
    test "over a zero-wide range every value is the middle, but NA and NaN are NA" do
      assert {Bounds.rescale(@doubles, {1, 1}, {0, 1}),
              Bounds.rescale(@doubles, {:infinity, :infinity}, {0, 1}),
              Bounds.rescale(
                [:neg_infinity, :infinity],
                {:infinity, :infinity},
                {:neg_infinity, :infinity}
              )} ===
               {[0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, nil, nil],
                [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, nil, nil], [:nan, :nan]}
    end

    # R's `rescale(c(1e308, -1e308), c(0, 10), c(0, 1))` is `Inf -Inf`, and over a zero-wide
    # range onto `c(1e308, 1.7e308)` every value is `0x1.807e25b31820bp+1023`, R's long-double
    # mean, where the doubles' sum is past the largest.
    test "a result past the largest double is an infinity, and a middle past it still found" do
      assert {Bounds.rescale([1.0e308, -1.0e308], {0, 1}, {0, 10}),
              Bounds.rescale([5, nil], {5, 5}, {1.0e308, 1.7e308})} ===
               {[:infinity, :neg_infinity], [1.35e308, nil]}
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

    # R's `rescale_mid(x, c(0, 1), c(-1, 2), 0)`, `c(0, Inf)` about 1, and about `Inf`: an
    # infinite end makes the extent infinite, so a number is the middle and an infinity NaN; an
    # infinite midpoint makes every value NaN.
    test "an infinity, an infinite end and an infinite midpoint go through R's arithmetic" do
      assert {Bounds.rescale_mid(@doubles, {-1, 2}, {0, 1}, 0),
              Bounds.rescale_mid(@doubles, {0, :infinity}, {0, 1}, 1),
              Bounds.rescale_mid(@doubles, {-1, 2}, {0, 1}, :infinity)} ===
               {[:neg_infinity, 0.25, 0.5, 0.625, 0.75, 1.0, :infinity, nil, :nan],
                [:nan, 0.5, 0.5, 0.5, 0.5, 0.5, :nan, nil, :nan],
                [:nan, :nan, :nan, :nan, :nan, :nan, :nan, nil, :nan]}
    end

    # R's `rescale_mid(c(1, 3), c(1e308, 1.7e308), c(1, 3), 2)`: the middle of `to` is R's
    # long-double mean, `0x1.807e25b31820bp+1023`, where the doubles' sum is past the largest.
    # R's `rescale_mid(c(0, 1, 3), c(0, 1), c(3, 0), 2)`: the further end is the low one, 0, two
    # from the midpoint, as `abs()` measures it.
    test "the end further from the midpoint is found by distance, a range given high to low too" do
      assert Bounds.rescale_mid([0, 1, 3], {3, 0}, {0, 1}, 2) === [0.0, 0.25, 0.75]
    end

    # The midpoint is built as the test runs: a literal the guard refuses fails the type checker.
    # R's `rescale_mid()` with an `NA` midpoint gives `NA` for every value; here it is refused, as
    # an end is.
    test "a midpoint that is not a number or an infinity is refused" do
      nan = Enum.at([:nan], 0)

      assert_raise FunctionClauseError, fn -> Bounds.rescale_mid([1], {0, 2}, {0, 1}, nan) end
    end

    test "the middle of a range whose ends sum past the largest double is still found" do
      assert Bounds.rescale_mid([1, 2, 3], {1, 3}, {1.0e308, 1.7e308}, 2) ===
               [1.0e308, 1.35e308, 1.7e308]
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
               {[:nan, :infinity, :neg_infinity, nil], [:infinity, :neg_infinity, :nan],
                [:neg_infinity, :infinity], [:nan, :nan]}
    end

    # R's `rescale_max(x, c(0, 1), c(0, 2))`, `c(0, Inf)`, and onto `c(0, Inf)` from `c(0, 2)`;
    # R's `1 / rescale_max(c(-1, 1), c(0, 1), c(0, Inf))` is `-Inf Inf`, a zero of each sign.
    test "an infinity, an infinite end and NaN go through R's arithmetic" do
      assert {Bounds.rescale_max(@doubles, {0, 2}, {0, 1}),
              Bounds.rescale_max(@doubles, {0, :infinity}, {0, 1}),
              Bounds.rescale_max(@doubles, {0, 2}, {0, :infinity})} ===
               {[:neg_infinity, -0.5, 0.0, 0.25, 0.5, 1.0, :infinity, nil, :nan],
                [:nan, -0.0, 0.0, 0.0, 0.0, 0.0, :nan, nil, :nan],
                [
                  :neg_infinity,
                  :neg_infinity,
                  :nan,
                  :infinity,
                  :infinity,
                  :infinity,
                  :infinity,
                  nil,
                  :nan
                ]}
    end
  end

  describe "rescale_max/3's ends" do
    # The ends are built as the test runs: a literal the guard refuses fails the type checker.
    test "a high end that is not a number or an infinity is refused, the low ends unread" do
      nan = Enum.at([:nan], 0)

      assert_raise FunctionClauseError, fn -> Bounds.rescale_max([1], {0, nan}, {0, 1}) end
      assert_raise FunctionClauseError, fn -> Bounds.rescale_max([1], {0, 2}, {0, nan}) end
      assert Bounds.rescale_max([1], {nan, 2}, {nan, 1}) === [0.5]
    end
  end

  describe "rescale_none/1" do
    test "every value is given back as it is" do
      assert Bounds.rescale_none(@doubles) === @doubles
    end

    # Built as the test runs: a literal the guard refuses fails the type checker.
    test "values that are not a list are refused" do
      values = Enum.at(["not a list"], 0)

      assert_raise FunctionClauseError, fn -> Bounds.rescale_none(values) end
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

    # R's `zero_range()` of `c(Inf, Inf)`, `c(-Inf, -Inf)`, `c(0, Inf)`, `c(-Inf, Inf)` and
    # `c(1, -Inf)`.
    test "both ends the same infinity are zero wide, one infinite end is not" do
      assert {Bounds.zero_range?({:infinity, :infinity}),
              Bounds.zero_range?({:neg_infinity, :neg_infinity}),
              Bounds.zero_range?({0, :infinity}), Bounds.zero_range?({:neg_infinity, :infinity}),
              Bounds.zero_range?({1, :neg_infinity})} === {true, true, false, false, false}
    end

    # R's `zero_range(c(1, NA))` is `NA`, which `rescale()` then fails on. The end is built as the
    # test runs: a literal the guard refuses fails the type checker.
    test "an end that is not a number or an infinity is refused" do
      missing = Enum.at([nil], 0)

      assert_raise FunctionClauseError, fn -> Bounds.zero_range?({1, missing}) end
    end
  end

  describe "expand_range/2" do
    # Golden: R 4.6.1's `scales::expand_range()` (scales 1.4.0) on each range and options,
    # `mul` as `mult:`.
    test "each end moves by the width times the multiple plus the constant, in R's order" do
      assert {Bounds.expand_range({1, 3}, mult: 0.05), Bounds.expand_range({1, 3}, add: 0.6),
              Bounds.expand_range({1, 3}, mult: 0.05, add: 1)} ===
               {{0.9, 3.1}, {0.4, 3.6}, {-0.10000000000000009, 4.1}}
    end

    # R's `mul = c(0.05, 0.1)` and `add = c(0, 2)`, a vector of two.
    test "a pair moves each end by its own" do
      assert {Bounds.expand_range({1, 3}, mult: {0.05, 0.1}),
              Bounds.expand_range({1, 3}, mult: {0.05, 0.1}, add: {0, 2})} ===
               {{0.9, 3.2}, {0.9, 5.2}}
    end

    test "no options leave the range as it is" do
      assert Bounds.expand_range({1, 3}) === {1, 3}
    end

    # `c(1, 1 + 1e-14)` is zero wide by R's tolerance, so widened as though 1 wide.
    test "a zero-wide range is widened as though its width were zero_width" do
      assert {Bounds.expand_range({5, 5}, mult: 0.05), Bounds.expand_range({0, 0}, mult: 0.05),
              Bounds.expand_range({1, 1 + 1.0e-14}, mult: 0.05),
              Bounds.expand_range({5, 5}, mult: 0.05, zero_width: 10),
              Bounds.expand_range({5, 5}, mult: 1, zero_width: 0)} ===
               {{4.95, 5.05}, {-0.05, 0.05}, {0.95, 1.05000000000001}, {4.5, 5.5}, {5, 5}}
    end

    test "a range high to low widens outward, and a negative multiple narrows one past its middle" do
      assert {Bounds.expand_range({3, 1}, mult: 0.05), Bounds.expand_range({1, 3}, mult: -0.5),
              Bounds.expand_range({1, 3}, mult: -1)} === {{3.1, 0.9}, {2.0, 2.0}, {3, 1}}
    end

    # R's `c(-Inf, 1)`, `c(1, Inf)`, `c(Inf, Inf)` and `c(-Inf, Inf)`: an infinite width times 0 is
    # NaN, and a sum past the largest double an infinity.
    test "an infinite end gives R's IEEE answer, NaN where no multiple meets an infinite width" do
      assert {Bounds.expand_range({:neg_infinity, 1}, mult: 0.05),
              Bounds.expand_range({1, :infinity}), Bounds.expand_range({1, :infinity}, add: 1),
              Bounds.expand_range({:infinity, :infinity}, mult: 0.05),
              Bounds.expand_range({:neg_infinity, :infinity}),
              Bounds.expand_range({1.0e308, 1.7e308}, mult: 1)} ===
               {{:neg_infinity, :infinity}, {:nan, :nan}, {:nan, :nan}, {:infinity, :infinity},
                {:nan, :nan}, {3.000_000_000_000_001e307, :infinity}}
    end

    # R fails on `c(NA, 1)` and `c(NaN, 1)`. The ends are built as the test runs: a literal the
    # guard refuses fails the type checker.
    test "a missing or NaN end is refused" do
      [missing, nan] = Enum.take([nil, :nan], 2)

      assert_raise FunctionClauseError, fn -> Bounds.expand_range({missing, 1}) end
      assert_raise FunctionClauseError, fn -> Bounds.expand_range({1, nan}, mult: 0.05) end
    end

    # R takes `mul = Inf` (`-Inf Inf`) and `mul = NA` (`NA NA`); a departure.
    test "a multiple, constant or width but a finite number or a pair of them is refused" do
      for options <- [
            [mult: :infinity],
            [mult: nil],
            [add: {1, :infinity}],
            [mult: {1, 2, 3}],
            [zero_width: :infinity],
            [zero_width: {1, 2}],
            [mul: 0.05]
          ] do
        assert_raise NimbleOptions.ValidationError, fn -> Bounds.expand_range({1, 3}, options) end
      end
    end
  end

  describe "censor/2" do
    # R's `oob_censor(c(1, 5, 10, NA, Inf, -Inf, NaN, 2, 8), c(2, 8))` is `NA 5 NA NA Inf -Inf NaN
    # 2 8`: the ends themselves are kept, and so is NaN.
    test "a finite number outside the range is nil, the ends, the infinities and NaN kept" do
      assert Bounds.censor([1, 5, 10, nil, :infinity, :neg_infinity, :nan, 2, 8], {2, 8}) ===
               [nil, 5, nil, nil, :infinity, :neg_infinity, :nan, 2, 8]
    end

    # R's `oob_censor(x, c(1, 0))` and `c(0.5, 0.5)`.
    test "a range given high to low censors every finite number, a zero-wide one all but itself" do
      assert {Bounds.censor(@doubles, {1, 0}), Bounds.censor(@doubles, {0.5, 0.5})} ===
               {[:neg_infinity, nil, nil, nil, nil, nil, :infinity, nil, :nan],
                [:neg_infinity, nil, nil, 0.5, nil, nil, :infinity, nil, :nan]}
    end

    test "an end of nil censors nothing on its side" do
      assert {Bounds.censor([1, 10], {nil, 8}), Bounds.censor([1, 10], {2, nil})} ===
               {[1, nil], [nil, 10]}
    end

    # R's `oob_censor(c(2, 8), c(2, -Inf))` is `NA NA`, and `oob_censor(x, c(-Inf, 1))` and
    # `c(0, Inf)` censor a finite number only on the finite end's side.
    test "an infinite end is compared as R compares it" do
      assert {Bounds.censor([2, 8], {2, :neg_infinity}),
              Bounds.censor(@doubles, {:neg_infinity, 1}),
              Bounds.censor(@doubles, {0, :infinity})} ===
               {[nil, nil], [:neg_infinity, -1, 0, 0.5, 1, nil, :infinity, nil, :nan],
                [:neg_infinity, nil, 0, 0.5, 1, 2, :infinity, nil, :nan]}
    end

    # The end is built as the test runs: a literal the guard refuses fails the type checker.
    test "an end that is not a number, an infinity or nil is refused" do
      nan = Enum.at([:nan], 0)

      assert_raise FunctionClauseError, fn -> Bounds.censor([], {2, nan}) end
      assert_raise FunctionClauseError, fn -> Bounds.censor([], {nan, 8}) end
    end
  end

  describe "censor_any/2" do
    # R's `oob_censor_any(x, c(0, 1))`, `c(1, 0)`, `c(NA, 1)` and `c(Inf, Inf)`: an infinity is
    # censored as a number is, NaN and `NA` kept.
    test "a number or an infinity outside the range is nil, NaN kept" do
      assert {Bounds.censor_any(@doubles, {0, 1}), Bounds.censor_any(@doubles, {1, 0}),
              Bounds.censor_any(@doubles, {nil, 1}),
              Bounds.censor_any(@doubles, {:infinity, :infinity})} ===
               {[nil, nil, 0, 0.5, 1, nil, nil, nil, :nan],
                [nil, nil, nil, nil, nil, nil, nil, nil, :nan],
                [:neg_infinity, -1, 0, 0.5, 1, nil, nil, nil, :nan],
                [nil, nil, nil, nil, nil, nil, :infinity, nil, :nan]}
    end

    test "values that are not numbers are kept" do
      assert Bounds.censor_any(["a", :b], {0, 1}) === ["a", :b]
    end

    test "an end that is not a number, an infinity or nil is refused" do
      nan = Enum.at([:nan], 0)

      assert_raise FunctionClauseError, fn -> Bounds.censor_any([], {2, nan}) end
      assert_raise FunctionClauseError, fn -> Bounds.censor_any([], {nan, 8}) end
    end
  end

  describe "squish/2" do
    # R's `oob_squish(c(1, 5, 10, NA, Inf, -Inf, NaN, 2, 8), c(2, 8))` is `2 5 8 NA Inf -Inf NaN 2
    # 8`: only finite numbers move, a value at an end not moved, so 2.0 stays a float.
    test "a finite number outside the range moves onto the nearer end, the rest kept" do
      assert Bounds.squish([1, 5, 10, nil, :infinity, :neg_infinity, :nan, 2.0, 8.0], {2, 8}) ===
               [2, 5, 8, nil, :infinity, :neg_infinity, :nan, 2.0, 8.0]
    end

    # R's `oob_squish(c(1, 5, 10, Inf), c(5, 5))` is `5 5 5 Inf`.
    test "a range zero wide puts every finite number at it" do
      assert Bounds.squish([1, 5, 10, :infinity], {5, 5}) === [5, 5, 5, :infinity]
    end

    # R's `oob_squish(c(1, 5, 10, NA, Inf), c(8, 2))` is `2 2 2 NA Inf`: 1 and 5 are moved up to 8
    # first, then down to 2 with 10.
    test "a range given high to low puts every finite number at its high end" do
      assert Bounds.squish([1, 5, 10, nil, :infinity], {8, 2}) === [2, 2, 2, nil, :infinity]
    end

    # R's `oob_squish(c(1, 5, 10), c(NA, 8))` is `1 5 8`, and with `c(2, NA)` `2 5 10`.
    test "an end of nil squishes nothing on its side" do
      assert {Bounds.squish([1, 5, 10], {nil, 8}), Bounds.squish([1, 5, 10], {2, nil})} ===
               {[1, 5, 8], [2, 5, 10]}
    end

    # R's `1 / oob_squish(c(-1, 0), c(-0, 1))` is `-Inf Inf`: -1 takes the end's sign, and 0, not
    # below it, keeps its own.
    test "a value moved takes the end as given, a negative zero's sign included" do
      assert Bounds.squish([-1, 0.0], {-0.0, 1}) === [-0.0, 0.0]
    end

    # R's `is.finite()` is false on values that are not numbers, so none is moved.
    test "values that are not numbers are kept" do
      assert Bounds.squish(["a", :b, nil], {2, 8}) === ["a", :b, nil]
    end

    # R's `oob_squish(c(2, 8), c(2, -Inf))` is `-Inf -Inf`: 8 is above the high end, and 2 too.
    test "a finite number moves onto an infinite end" do
      assert {Bounds.squish([2, 8], {2, :neg_infinity}),
              Bounds.squish(@doubles, {:neg_infinity, 1})} ===
               {[:neg_infinity, :neg_infinity],
                [:neg_infinity, -1, 0, 0.5, 1, 1, :infinity, nil, :nan]}
    end

    # The end is built as the test runs: a literal the guard refuses fails the type checker.
    test "an end that is not a number, an infinity or nil is refused" do
      nan = Enum.at([:nan], 0)

      assert_raise FunctionClauseError, fn -> Bounds.squish([], {2, nan}) end
      assert_raise FunctionClauseError, fn -> Bounds.squish([], {nan, 8}) end
    end
  end

  describe "squish_any/2" do
    # R's `oob_squish_any(x, c(0, 1))`, `c(1, 0)`, `c(0, NA)` and `c(-Inf, -Inf)`: an infinity is
    # moved as a number is, NaN and `NA` kept.
    test "a number or an infinity outside the range moves onto the nearer end, NaN kept" do
      assert {Bounds.squish_any(@doubles, {0, 1}), Bounds.squish_any(@doubles, {1, 0}),
              Bounds.squish_any(@doubles, {0, nil}),
              Bounds.squish_any(@doubles, {:neg_infinity, :neg_infinity})} ===
               {[0, 0, 0, 0.5, 1, 1, 1, nil, :nan], [0, 0, 0, 0, 0, 0, 0, nil, :nan],
                [0, 0, 0, 0.5, 1, 2, :infinity, nil, :nan],
                [
                  :neg_infinity,
                  :neg_infinity,
                  :neg_infinity,
                  :neg_infinity,
                  :neg_infinity,
                  :neg_infinity,
                  :neg_infinity,
                  nil,
                  :nan
                ]}
    end

    test "values that are not numbers are kept" do
      assert Bounds.squish_any(["a", :b], {0, 1}) === ["a", :b]
    end

    test "an end that is not a number, an infinity or nil is refused" do
      nan = Enum.at([:nan], 0)

      assert_raise FunctionClauseError, fn -> Bounds.squish_any([], {2, nan}) end
      assert_raise FunctionClauseError, fn -> Bounds.squish_any([], {nan, 8}) end
    end
  end

  describe "squish_infinite/2" do
    # R's `oob_squish_infinite(x, c(0, 1))`, `c(1, 0)`, `c(0, NA)` and `c(NA, NA)`: only the
    # infinities move, a finite number outside the range kept, and an end of `NA` puts `NA`.
    test "each infinity is replaced by the end on its side, the rest kept" do
      assert {Bounds.squish_infinite(@doubles, {0, 1}), Bounds.squish_infinite(@doubles, {1, 0}),
              Bounds.squish_infinite(@doubles, {0, nil}),
              Bounds.squish_infinite(@doubles, {nil, nil})} ===
               {[0, -1, 0, 0.5, 1, 2, 1, nil, :nan], [1, -1, 0, 0.5, 1, 2, 0, nil, :nan],
                [0, -1, 0, 0.5, 1, 2, nil, nil, :nan], [nil, -1, 0, 0.5, 1, 2, nil, nil, :nan]}
    end

    # R's `oob_squish_infinite(x, c(Inf, -Inf))`: `-Inf` is replaced by `Inf` first, which is
    # then replaced by `-Inf` with the `Inf` given; with `c(-Inf, Inf)` nothing moves.
    test "the low end replaces minus infinity first, and is replaced in turn when infinite" do
      assert {Bounds.squish_infinite(@doubles, {:infinity, :neg_infinity}),
              Bounds.squish_infinite(@doubles, {:neg_infinity, :infinity})} ===
               {[:neg_infinity, -1, 0, 0.5, 1, 2, :neg_infinity, nil, :nan], @doubles}
    end

    # R's `1 / oob_squish_infinite(c(-Inf, Inf), c(-0, 1))` is `-Inf 1`.
    test "an infinity takes the end as given, a negative zero's sign included" do
      assert Bounds.squish_infinite([:neg_infinity, :infinity], {-0.0, 1}) === [-0.0, 1]
    end

    test "an end that is not a number, an infinity or nil is refused" do
      nan = Enum.at([:nan], 0)

      assert_raise FunctionClauseError, fn -> Bounds.squish_infinite([], {2, nan}) end
      assert_raise FunctionClauseError, fn -> Bounds.squish_infinite([], {nan, 8}) end
    end
  end

  describe "discard/2" do
    # R's `oob_discard(x, c(0, 1))`, `c(1, 0)`, `c(-Inf, 1)`, `c(0, Inf)` and `c(-Inf, Inf)`:
    # values outside the range dropped, an infinity among them, `NA` kept and NaN made `NA`.
    test "values outside the range are dropped, NA kept and NaN made NA" do
      assert {Bounds.discard(@doubles, {0, 1}), Bounds.discard(@doubles, {1, 0}),
              Bounds.discard(@doubles, {:neg_infinity, 1}),
              Bounds.discard(@doubles, {0, :infinity}),
              Bounds.discard(@doubles, {:neg_infinity, :infinity})} ===
               {[0, 0.5, 1, nil, nil], [nil, nil], [:neg_infinity, -1, 0, 0.5, 1, nil, nil],
                [0, 0.5, 1, 2, :infinity, nil, nil],
                [:neg_infinity, -1, 0, 0.5, 1, 2, :infinity, nil, nil]}
    end

    # R's `oob_discard(x, c(0, NA))` is seven `NA`s, from its logical index; here an end of `nil`
    # bounds nothing on its side, as `censor/2`'s does (design-log §4).
    test "an end of nil bounds nothing on its side" do
      assert {Bounds.discard(@doubles, {0, nil}), Bounds.discard(@doubles, {nil, 1}),
              Bounds.discard(@doubles, {nil, nil})} ===
               {[0, 0.5, 1, 2, :infinity, nil, nil], [:neg_infinity, -1, 0, 0.5, 1, nil, nil],
                [:neg_infinity, -1, 0, 0.5, 1, 2, :infinity, nil, nil]}
    end

    # R's `oob_discard(c(-0, 0, 1e-320), c(0, 0))` is `0 0`: a negative zero is at an end of 0.
    test "the ends are inside, a negative zero at an end of 0" do
      assert Bounds.discard([-0.0, 0.0, 1.0e-320], {0, 0}) === [-0.0, 0.0]
    end

    test "values that are not numbers are kept" do
      assert Bounds.discard(["a", :b], {0, 1}) === ["a", :b]
    end

    test "an end that is not a number, an infinity or nil is refused" do
      nan = Enum.at([:nan], 0)

      assert_raise FunctionClauseError, fn -> Bounds.discard([], {2, nan}) end
      assert_raise FunctionClauseError, fn -> Bounds.discard([], {nan, 8}) end
    end
  end

  describe "keep/2" do
    test "every value is given back as it is" do
      assert Bounds.keep(@doubles, {0, 1}) === @doubles
    end

    test "an end that is not a number, an infinity or nil is refused" do
      nan = Enum.at([:nan], 0)

      assert_raise FunctionClauseError, fn -> Bounds.keep([], {2, nan}) end
      assert_raise FunctionClauseError, fn -> Bounds.keep([], {nan, 8}) end
    end
  end
end
