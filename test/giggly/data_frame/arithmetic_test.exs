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

  # Golden: R 4.6.1's 1 + NA, Inf + NaN, 1 * NA, Inf * NaN, -0.5 * Inf, Inf / -0.5, -Inf / 0,
  # -Inf / 0.5 and -Inf / -0.5 are NA, NaN, NA, NaN, -Inf, -Inf, -Inf, -Inf and Inf: a missing
  # second operand, and a fraction's sign beside an infinity.
  test "a missing second operand and a fraction beside an infinity follow R" do
    assert {Arithmetic.add(1, nil), Arithmetic.add(:infinity, :nan)} === {nil, :nan}

    assert {Arithmetic.multiply(1, nil), Arithmetic.multiply(:infinity, :nan),
            Arithmetic.multiply(-0.5, :infinity)} === {nil, :nan, :neg_infinity}

    quotients =
      Enum.map(
        [{:infinity, -0.5}, {:neg_infinity, 0}, {:neg_infinity, 0.5}, {:neg_infinity, -0.5}],
        fn {numerator, denominator} -> Arithmetic.divide(numerator, denominator) end
      )

    assert quotients === [:neg_infinity, :neg_infinity, :neg_infinity, :infinity]
  end

  # Golden: R 4.6.1's 3 - 1.5, 1 - -Inf, Inf - Inf, NA - NaN, NaN - NA and -Inf - 2 are 1.5, Inf,
  # NaN, NA, NaN and -Inf.
  test "subtract subtracts as R subtracts doubles" do
    pairs = [
      {3, 1.5},
      {1, :neg_infinity},
      {:infinity, :infinity},
      {nil, :nan},
      {:nan, nil},
      {:neg_infinity, 2}
    ]

    assert Enum.map(pairs, fn {left, right} -> Arithmetic.subtract(left, right) end) ===
             [1.5, :infinity, :nan, nil, :nan, :neg_infinity]
  end

  # Golden: R 4.6.1's 1 / pmin(0, -0) is Inf and 1 / pmax(-0, 0) is -Inf, a tie keeping the first;
  # pmax(NA, Inf), pmax(NaN, Inf) and pmin(NA, -Inf) are NA, NaN and NA.
  test "lesser and greater keep the first of a tie, and a missing value beats an infinity" do
    assert {Arithmetic.lesser(0.0, -0.0), Arithmetic.greater(-0.0, 0.0)} === {0.0, -0.0}

    assert {Arithmetic.greater(nil, :infinity), Arithmetic.greater(:nan, :infinity),
            Arithmetic.lesser(nil, :neg_infinity)} === {nil, :nan, nil}
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

  # Golden: R 4.6.1's sum(c(1e16, 1, 1)) is 10000000000000002, where adding in doubles gives 1e16,
  # and sum(c(1, NA, NaN)), sum(c(NaN, NA)) and sum(c(1, Inf, -Inf)) are NA, NaN and NaN.
  test "sum is R's sum(): in extended precision, the first missing value kept, infinities met NaN" do
    assert Arithmetic.sum([1.0e16, 1.0, 1.0]) === 10_000_000_000_000_002.0
    assert Arithmetic.sum([1.0e16, 1.0, 1.0], :plain) === 1.0e16

    assert Enum.map([[1.0, nil, :nan], [:nan, nil], [1.0, :infinity, :neg_infinity]], fn values ->
             Arithmetic.sum(values)
           end) === [nil, :nan, :nan]
  end

  # Golden: R 4.6.1's cumsum() of c(1e16, 1, 1), c(0.1, 0.2), c(1, Inf, 2, -Inf, 3) and c(1, NA, 2),
  # printed to 17 significant digits: 1e16, 1e16, 10000000000000002 (adding in doubles keeps 1e16);
  # 0.10000000000000001, 0.30000000000000004; 1, Inf, Inf, NaN, NaN; and 1, NA, NA.
  test "cumulative_sum is R's cumsum(): each sum in extended precision, a missing one carried on" do
    sums =
      Enum.map(
        [
          [1.0e16, 1.0, 1.0],
          [0.1, 0.2],
          [1.0, :infinity, 2.0, :neg_infinity, 3.0],
          [1.0, nil, 2.0]
        ],
        &Arithmetic.cumulative_sum/1
      )

    assert sums === [
             [1.0e16, 1.0e16, 10_000_000_000_000_002.0],
             [0.1, 0.30000000000000004],
             [1.0, :infinity, :infinity, :nan, :nan],
             [1.0, nil, nil]
           ]
  end

  # Golden: R 4.6.1's cumsum() of c(NaN, NA), c(NA, NaN), c(Inf, -Inf, NA) and c(NA, Inf): NaN, NA;
  # NA, NA; Inf, NaN, NA; and NA, NA. Its long double keeps NA over NaN whichever comes first,
  # where R's `+` keeps its first operand.
  test "cumulative_sum keeps NA from where it is met, NaN before it or after" do
    sums =
      Enum.map(
        [[:nan, nil], [nil, :nan], [:infinity, :neg_infinity, nil], [nil, :infinity]],
        &Arithmetic.cumulative_sum/1
      )

    assert sums === [[:nan, nil], [nil, nil], [:infinity, :nan, nil], [nil, nil]]
  end

  # Golden: R 4.6.1's mean() of c(NA, NaN), c(NaN, NA), c(1, NaN, NA), c(Inf, NA), c(NA_integer_,
  # 1L), c(1, NaN), c(Inf, NaN), c(Inf, 1), c(-Inf, 1) and c(Inf, -Inf) is NA, NA, NA, NA, NA,
  # NaN, NaN, Inf, -Inf and NaN: NA wherever it is, where R's sum() keeps the first missing value.
  test "mean is R's mean(): missing wherever a value is, else NaN, infinities as they add" do
    means =
      Enum.map(
        [
          [nil, :nan],
          [:nan, nil],
          [1.0, :nan, nil],
          [:infinity, nil],
          [nil, 1],
          [1.0, :nan],
          [:infinity, :nan],
          [:infinity, 1.0],
          [:neg_infinity, 1.0],
          [:infinity, :neg_infinity]
        ],
        &Arithmetic.mean/1
      )

    assert means === [nil, nil, nil, nil, nil, :nan, :nan, :infinity, :neg_infinity, :nan]
  end

  # Golden: R 4.6.1's mean() of c(63.9, 61, 62), c(0.2, 0.1, 0.3), c(0.1, 0.2) and c(1e16, 1,
  # -1e16), printed to 17 significant digits: 62.299999999999997, 0.20000000000000001,
  # 0.15000000000000002 and 0.33365885416666669. Their sums in extended precision divided by the
  # count are 62.300000000000004, 0.19999999999999998, 0.15000000000000002 and
  # 0.33333333333333331: R's correction pass, run in a long double, moves the first two to the
  # nearest double and the last away from a third.
  test "mean works a double's mean out in R's long double, its correction pass included" do
    means =
      Enum.map(
        [[63.9, 61.0, 62.0], [0.2, 0.1, 0.3], [0.1, 0.2], [1.0e16, 1.0, -1.0e16]],
        &Arithmetic.mean/1
      )

    assert means === [62.3, 0.2, 0.15000000000000002, 0.33365885416666669]
  end

  # Golden: R 4.6.1's mean() of c(1e308, 1e308), c(xmax, xmax, -xmax) for the largest double xmax,
  # and c(-1e308, -1e308, -1e308) is 1e308, 5.9923104495410527e307 and -1e308, where a sum in
  # doubles is past the largest.
  test "mean of doubles whose sum is past the largest double divides each by the count first" do
    largest = 1.797_693_134_862_315_7e308

    means =
      Enum.map(
        [[1.0e308, 1.0e308], [largest, largest, -largest], [-1.0e308, -1.0e308, -1.0e308]],
        &Arithmetic.mean/1
      )

    assert means === [1.0e308, 5.992_310_449_541_052_7e307, -1.0e308]
  end

  # Golden: R 4.6.1's mean() of c(5e-324, 5e-324) and c(5e-324, 0) is 4.9406564584124654e-324
  # and 0, half the least double a tie rounded to even, and 1 / mean(-0) is Inf, its sum begun
  # from plus zero.
  test "mean rounds to a double last, below the least normal one too, and has no minus zero" do
    means =
      Enum.map([[5.0e-324, 5.0e-324], [5.0e-324, 0.0], [-0.0], [-0.0, -0.0]], &Arithmetic.mean/1)

    assert means === [5.0e-324, 0.0, 0.0, 0.0]
  end

  # Golden: R 4.6.1's mean(c(1L, 2L)) is 1.5 and mean(c(640883879L, integer(4094))) is
  # 156503.99975579977, the exact sum divided once in a long double and rounded to a double, where
  # dividing in doubles gives 156503.99975579974.
  test "mean of integers divides their exact sum once in R's long double" do
    many = [640_883_879 | List.duplicate(0, 4094)]

    assert {Arithmetic.mean([1, 2]), Arithmetic.mean(many)} === {1.5, 156_503.99975579977}
  end
end
