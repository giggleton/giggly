defmodule Giggly.Stat.CurveTest do
  use ExUnit.Case, async: true

  alias Giggly.Stat.Curve

  # Golden: R 4.6.1's seq(0, 1, length.out = 4) and seq.int(0.1, 0.7, length.out = 7), printed to
  # 17 significant digits: each step times its place added to the low end, so the third of the
  # second is 0.29999999999999999, the double 0.3, where steps added one by one give
  # 0.30000000000000004.
  test "places are R's seq(): the ends exactly, and the low end plus each step between" do
    assert Curve.places(0, 1, 4) === [0, 0.3333333333333333, 0.6666666666666666, 1]

    assert Curve.places(0.1, 0.7, 7) === [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]
  end

  test "places refuses a count below 1" do
    # Built as the test runs, since the type checker warns of a call it knows fails.
    count = String.to_integer("0")

    assert_raise FunctionClauseError, fn -> Curve.places(0.0, 1.0, count) end
  end

  test "one place is the low end, two the ends, and ends that meet repeat the low end" do
    assert {Curve.places(1.0, 2.0, 1), Curve.places(1.0, 2.0, 2), Curve.places(2, 2, 3)} ===
             {[1.0], [1.0, 2.0], [2, 2.0, 2]}
  end

  # Golden: R 4.6.1's approx(c(0, 1, 3), c(0.1, 0.7, 0.2), xout = c(-1, 0, 0.3, 1, 2, 3, 4))$y:
  # NA, 0.1, 0.28, 0.7, 0.45, 0.2 and NA, to 17 significant digits 0.28000000000000003 and
  # 0.44999999999999996.
  test "interpolate is R's approx(): a knot's y at its x, straight between, nil outside" do
    knots = [{0.0, 0.1}, {1.0, 0.7}, {3.0, 0.2}]

    assert Curve.interpolate(knots, [-1.0, 0.0, 0.3, 1.0, 2.0, 3.0, 4.0]) ===
             [nil, 0.1, 0.28, 0.7, 0.44999999999999996, 0.2, nil]
  end

  # Golden: R 4.6.1's approx(c(0, 1, 3), c(0.7, 0.1, 0.2), xout = c(0.5, 1, 2))$y, to 17
  # significant digits 0.39999999999999997, 0.10000000000000001 and 0.15000000000000002: at the
  # knot at 1 its y, 0.1, where the line from the knot before gives 0.09999999999999998.
  test "interpolate at a knot reads its y, not the line's rounding of it" do
    knots = [{0.0, 0.7}, {1.0, 0.1}, {3.0, 0.2}]

    assert Curve.interpolate(knots, [0.5, 1.0, 2.0]) === [
             0.39999999999999997,
             0.1,
             0.15000000000000002
           ]
  end

  test "interpolate reads nothing from a single knot" do
    assert Curve.interpolate([{1.0, 2.0}], [1.0]) == [nil]
  end
end
