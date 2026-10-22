defmodule Giggly.DataFrame.ArithmeticTest do
  use ExUnit.Case, async: true

  alias Giggly.DataFrame.Arithmetic

  # Golden: R 4.6.1's NA / 1, 1 / NA, NaN / 1, 1 / NaN, Inf / Inf, Inf / -Inf, Inf / -2, Inf / 2,
  # Inf / 0, -Inf / -2, -Inf / 2, 3 / Inf, -3 / Inf, 3 / -Inf, -3 / -Inf, 6 / 4, 1 / 0, -1 / 0 and
  # 0 / 0, NA / NaN and NaN / NA are NA, NA, NaN, NaN, NaN, NaN, -Inf, Inf, Inf, Inf, -Inf, 0,
  # -0, -0, 0, 1.5, Inf, -Inf, NaN, NA and NaN, a zero's sign read from its reciprocal, the first
  # missing operand kept.
  test "divide divides as R divides doubles, the non-finite ones and a zero's sign included" do
    divisions = [
      {nil, 1},
      {1, nil},
      {:nan, 1},
      {1, :nan},
      {:infinity, :infinity},
      {:infinity, :neg_infinity},
      {:infinity, -2},
      {:infinity, 2},
      {:infinity, 0},
      {:neg_infinity, -2},
      {:neg_infinity, 2},
      {3, :infinity},
      {-3, :infinity},
      {3, :neg_infinity},
      {-3, :neg_infinity},
      {6, 4},
      {1, 0},
      {-1, 0},
      {0, 0},
      {nil, :nan},
      {:nan, nil}
    ]

    quotients =
      Enum.map(divisions, fn {numerator, denominator} ->
        Arithmetic.divide(numerator, denominator)
      end)

    assert quotients === [
             nil,
             nil,
             :nan,
             :nan,
             :nan,
             :nan,
             :neg_infinity,
             :infinity,
             :infinity,
             :infinity,
             :neg_infinity,
             0.0,
             -0.0,
             -0.0,
             0.0,
             1.5,
             :infinity,
             :neg_infinity,
             :nan,
             nil,
             :nan
           ]
  end

  # Golden: R 4.6.1's 1.5 + 2, Inf + 1, 1 + -Inf, Inf + Inf, Inf + -Inf, NA + Inf, NaN + Inf,
  # NA + NaN and NaN + NA are 3.5, Inf, -Inf, Inf, NaN, NA, NaN, NA and NaN, the first missing
  # operand kept.
  test "add adds as R adds doubles" do
    pairs = [
      {1.5, 2},
      {:infinity, 1},
      {1, :neg_infinity},
      {:infinity, :infinity},
      {:infinity, :neg_infinity},
      {nil, :infinity},
      {:nan, :infinity},
      {nil, :nan},
      {:nan, nil}
    ]

    assert Enum.map(pairs, fn {left, right} -> Arithmetic.add(left, right) end) ===
             [3.5, :infinity, :neg_infinity, :infinity, :nan, nil, :nan, nil, :nan]
  end

  # Golden: R 4.6.1's 3 * 4, 0 * Inf, -2 * Inf, Inf * -Inf, -Inf * -3, NA * 0, NaN * 1, 0 * -2,
  # NA * NaN and NaN * NA are 12, NaN, -Inf, -Inf, Inf, NA, NaN, -0, NA and NaN.
  test "multiply multiplies as R multiplies doubles, 0 times an infinity NaN" do
    pairs =
      [{3, 4}, {0, :infinity}, {-2, :infinity}, {:infinity, :neg_infinity}] ++
        [{:neg_infinity, -3}, {nil, 0}, {:nan, 1}, {0, -2.0}, {nil, :nan}, {:nan, nil}]

    assert Enum.map(pairs, fn {left, right} -> Arithmetic.multiply(left, right) end) ===
             [12, :nan, :neg_infinity, :neg_infinity, :infinity, nil, :nan, -0.0, nil, :nan]
  end

  # Golden: R 4.6.1's pmin(Inf, 0), pmin(-Inf, 2), pmin(3, 1), pmin(NaN, 1), pmin(1, NaN),
  # pmin(NA, NaN) and pmin(NaN, NA) are 0, -Inf, 1, NaN, NaN, NaN and NA, and pmax() of the same
  # Inf, 2, 3, NaN, NaN, NaN and NA: the later missing operand kept.
  test "lesser and greater are R's pmin() and pmax()" do
    pairs = [
      {:infinity, 0},
      {:neg_infinity, 2},
      {3, 1},
      {:nan, 1},
      {1, :nan},
      {nil, :nan},
      {:nan, nil}
    ]

    assert Enum.map(pairs, fn {left, right} -> Arithmetic.lesser(left, right) end) ===
             [0, :neg_infinity, 1, :nan, :nan, :nan, nil]

    assert Enum.map(pairs, fn {left, right} -> Arithmetic.greater(left, right) end) ===
             [:infinity, 2, 3, :nan, :nan, :nan, nil]
  end

  # Golden: R 4.6.1's -Inf < 1, Inf < Inf, 1 < Inf, 2 < 1, NA < 1, NaN < 1 and 1 < NaN are TRUE,
  # FALSE, TRUE, FALSE, NA, NA and NA.
  test "less? is R's <, missing beside a missing value or NaN" do
    pairs =
      [{:neg_infinity, 1}, {:infinity, :infinity}, {1, :infinity}, {2, 1}, {nil, 1}] ++
        [{:nan, 1}, {1, :nan}]

    assert Enum.map(pairs, fn {left, right} -> Arithmetic.less?(left, right) end) ===
             [true, false, true, false, nil, nil, nil]
  end

  # Golden: R 4.6.1's abs() of -2.5, -Inf, Inf, NaN and NA is 2.5, Inf, Inf, NaN and NA.
  test "magnitude is R's abs(), an infinity's plus infinity" do
    magnitudes = Enum.map([-2.5, :neg_infinity, :infinity, :nan, nil], &Arithmetic.magnitude/1)

    assert magnitudes === [2.5, :infinity, :infinity, :nan, nil]
  end

  # Golden: R 4.6.1's max() of c(1, NA, NaN), c(NaN, NA), c(1, NaN), c(1, Inf, -Inf),
  # c(-Inf, -Inf) and c(2, -5, 1) is NA, NA, NaN, Inf, -Inf and 2.
  test "maximum is R's max(): missing before NaN in any order, an infinity beyond every number" do
    lists =
      [[1, nil, :nan], [:nan, nil], [1, :nan], [1, :infinity, :neg_infinity]] ++
        [[:neg_infinity, :neg_infinity], [2, -5, 1]]

    assert Enum.map(lists, &Arithmetic.maximum/1) === [
             nil,
             nil,
             :nan,
             :infinity,
             :neg_infinity,
             2
           ]
  end
end
