defmodule Scales.DoubleTest do
  use ExUnit.Case, async: true

  alias Scales.Double

  # Golden: R 4.6.1's arithmetic on each pair, `NaN` as `:nan`, `Inf` as `:infinity`, a zero's
  # sign read in R as `1 / x`. Moves only with IEEE arithmetic, which it is.

  describe "add/2 and subtract/2" do
    # R's `Inf + -Inf`, `-Inf + Inf`, `Inf - Inf` and `-Inf - -Inf` are NaN.
    test "two infinities of opposite signs added, or one less itself, make NaN" do
      assert {Double.add(:infinity, :neg_infinity), Double.add(:neg_infinity, :infinity),
              Double.subtract(:infinity, :infinity),
              Double.subtract(:neg_infinity, :neg_infinity)} === {:nan, :nan, :nan, :nan}
    end

    test "an infinity wins over a number, and two alike stay" do
      assert {Double.add(:infinity, -1.0e308), Double.add(5, :neg_infinity),
              Double.add(:infinity, :infinity), Double.subtract(5, :infinity),
              Double.subtract(:neg_infinity, 5)} ===
               {:infinity, :neg_infinity, :infinity, :neg_infinity, :neg_infinity}
    end

    # R's `1.5e308 + 1.5e308` is `Inf` and `-1.5e308 - 1.5e308` is `-Inf`.
    test "a sum past the largest double is the infinity of its sign" do
      assert {Double.add(1.5e308, 1.5e308), Double.subtract(-1.5e308, 1.5e308)} ===
               {:infinity, :neg_infinity}
    end

    test "NaN in either place is NaN" do
      assert {Double.add(:nan, 1), Double.add(:infinity, :nan), Double.subtract(:nan, :infinity),
              Double.subtract(1, :nan)} === {:nan, :nan, :nan, :nan}
    end

    test "two numbers are added and subtracted as Elixir does" do
      assert {Double.add(0.1, 0.2), Double.subtract(0.3, 0.1)} ===
               {0.30000000000000004, 0.19999999999999998}
    end
  end

  describe "multiply/2" do
    # R's `Inf * 0` and `-Inf * -0` are NaN, `Inf * -2` is `-Inf`.
    test "an infinity times a zero is NaN, any other number the infinity of the signs' product" do
      assert {Double.multiply(:infinity, 0), Double.multiply(:neg_infinity, -0.0),
              Double.multiply(0.0, :infinity), Double.multiply(:infinity, -2),
              Double.multiply(-2, :neg_infinity), Double.multiply(:neg_infinity, :infinity)} ===
               {:nan, :nan, :nan, :neg_infinity, :infinity, :neg_infinity}
    end

    # R's `1e308 * 10` is `Inf` and `-1e308 * 10` is `-Inf`.
    test "a product past the largest double is the infinity of the signs' product" do
      assert {Double.multiply(1.0e308, 10), Double.multiply(-1.0e308, 10),
              Double.multiply(-1.0e308, -10)} === {:infinity, :neg_infinity, :infinity}
    end

    test "NaN in either place is NaN" do
      assert {Double.multiply(:nan, 0), Double.multiply(:infinity, :nan)} === {:nan, :nan}
    end
  end

  describe "divide/2" do
    # R's `0/0`, `0/-0` and `Inf/Inf` are NaN; `1/0` is `Inf`, `1/-0` and `-1/0` are `-Inf`.
    test "a zero over a zero and an infinity over an infinity are NaN, a number over a zero infinite" do
      assert {Double.divide(0, 0), Double.divide(0.0, -0.0), Double.divide(:infinity, :infinity),
              Double.divide(1, 0), Double.divide(1, -0.0), Double.divide(-1, 0.0)} ===
               {:nan, :nan, :nan, :infinity, :neg_infinity, :neg_infinity}
    end

    # R's `Inf/-0` and `-Inf/2` are `-Inf`.
    test "an infinity over a number is the infinity of the signs' product, a zero's sign its bit's" do
      assert {Double.divide(:infinity, -0.0), Double.divide(:neg_infinity, 2),
              Double.divide(:neg_infinity, -0.5)} === {:neg_infinity, :neg_infinity, :infinity}
    end

    # R's `1 / (-1/Inf)` and `1 / (1/-Inf)` are `-Inf`, `1 / (1/Inf)` and `1 / (0/Inf)` `Inf`.
    test "a number over an infinity is a zero of the signs' product" do
      assert {Double.divide(-1, :infinity), Double.divide(1, :neg_infinity),
              Double.divide(1, :infinity), Double.divide(0, :infinity),
              Double.divide(-0.0, :neg_infinity)} === {-0.0, -0.0, 0.0, 0.0, 0.0}
    end

    # R's `1e308 / 1e-10` is `Inf`.
    test "a quotient past the largest double is the infinity of the signs' product" do
      assert {Double.divide(1.0e308, 1.0e-10), Double.divide(1.0e308, -1.0e-10)} ===
               {:infinity, :neg_infinity}
    end

    test "NaN in either place is NaN" do
      assert {Double.divide(:nan, 0), Double.divide(0, :nan)} === {:nan, :nan}
    end
  end

  describe "square_root/1 and absolute/1" do
    # R's `sqrt(-0)` is `-0`, `sqrt(-1)` and `sqrt(-Inf)` NaN, `sqrt(Inf)` `Inf`.
    test "a square root is NaN below zero, a negative zero's its own" do
      assert Enum.map(
               [-0.0, 0, -1, :neg_infinity, :infinity, 4, nil, :nan],
               &Double.square_root/1
             ) ===
               [-0.0, 0.0, :nan, :nan, :infinity, 2.0, nil, :nan]
    end

    # R's `abs(-Inf)` is `Inf` and `1 / abs(-0)` `Inf`.
    test "an absolute value is an infinity's infinity, a negative zero's a zero" do
      assert Enum.map([:neg_infinity, :infinity, -0.0, -3, nil, :nan], &Double.absolute/1) ===
               [:infinity, :infinity, 0.0, 3, nil, :nan]
    end
  end

  describe "minimum/2, maximum/2 and mean/2" do
    # R's `min(NaN, 1)` and `min(1, NaN)` are NaN, `min(-Inf, 1)` `-Inf` and `min(Inf, 1)` 1.
    test "the smaller of two, NaN where either is" do
      assert {Double.minimum(:nan, 1), Double.minimum(1, :nan), Double.minimum(:neg_infinity, 1),
              Double.minimum(:infinity, 1), Double.minimum(1, 2)} ===
               {:nan, :nan, :neg_infinity, 1, 1}
    end

    # R's `1 / min(-0, 0)` and `1 / max(-0, 0)` are `-Inf`, `1 / min(0, -0)` and `1 / max(0, -0)`
    # `Inf`: of two equals, the first.
    test "of two equals, the first, so a zero's sign is the first's" do
      assert {Double.minimum(-0.0, 0.0), Double.maximum(-0.0, 0.0), Double.minimum(0.0, -0.0),
              Double.maximum(0.0, -0.0)} === {-0.0, -0.0, 0.0, 0.0}
    end

    # R's `max(NaN, 1)` and `max(1, NaN)` are NaN, `max(-Inf, 1)` 1 and `max(Inf, 1)` `Inf`.
    test "the larger of two, NaN where either is" do
      assert {Double.maximum(:nan, 1), Double.maximum(1, :nan), Double.maximum(:neg_infinity, 1),
              Double.maximum(:infinity, 1), Double.maximum(2, 1)} ===
               {:nan, :nan, 1, :infinity, 2}
    end

    # R's `mean(c(Inf, -Inf))` is NaN, `mean(c(Inf, 1))` `Inf`, `mean(c(1.7e308, 1.7e308))`
    # `1.6999999999999999e+308`, and `1 / mean(c(-0, -0))` `Inf`.
    test "the mean of two, past the largest double's sum too, two negative zeros' a zero" do
      assert {Double.mean(:infinity, :neg_infinity), Double.mean(:infinity, 1),
              Double.mean(-1, :neg_infinity), Double.mean(1.7e308, 1.7e308),
              Double.mean(-1.7e308, -1.7e308), Double.mean(-0.0, -0.0), Double.mean(:nan, 1)} ===
               {:nan, :infinity, :neg_infinity, 1.7e308, -1.7e308, 0.0, :nan}
    end
  end

  describe "less?/2" do
    test "an infinity is below or above every number, and each is not below itself" do
      assert {Double.less?(:neg_infinity, -1.0e308), Double.less?(1.0e308, :infinity),
              Double.less?(:infinity, 1), Double.less?(1, :neg_infinity),
              Double.less?(:infinity, :infinity), Double.less?(:neg_infinity, :infinity),
              Double.less?(1, 2)} === {true, true, false, false, false, true, true}
    end

    # Its callers set NaN aside first; one handed in is refused, never ranked. Built as the test
    # runs: a literal the guard refuses fails the type checker.
    test "NaN is refused" do
      nan = Enum.at([:nan], 0)

      assert_raise FunctionClauseError, fn -> Double.less?(nan, :infinity) end
      assert_raise FunctionClauseError, fn -> Double.less?(:neg_infinity, nan) end
    end
  end
end
