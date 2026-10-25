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

  # Golden: R 4.6.1's order(c(3, NA, -Inf, NaN, Inf, -1, 0, NA)) is 3, 6, 7, 1, 5, 2, 4, 8: minus
  # infinity, the numbers, infinity, and the missing values, NA and NaN alike, last in the order
  # they came.
  test "sort_key sorts as R's order() does, the missing values last in their order" do
    order =
      [3, nil, :neg_infinity, :nan, :infinity, -1, 0, nil]
      |> Enum.with_index(1)
      |> Enum.sort_by(fn {value, _index} -> Arithmetic.sort_key(value) end)
      |> Enum.map(fn {_value, index} -> index end)

    assert order === [3, 6, 7, 1, 5, 2, 4, 8]
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

  # Golden: R 4.6.1's 1e308 + 1e308, -1e308 - 1e308, 1e308 * 10, 1e308 * -10, 1e308 / 1e-10,
  # 1e308 / -1e-10, xmax + 1e292 and xmax + 9.9e291, for the largest double xmax, are Inf, -Inf,
  # Inf, -Inf, Inf, -Inf, Inf and xmax: past the largest double by half its last place or more is
  # an infinity of the result's sign.
  test "add, subtract, multiply and divide give an infinity past the largest double" do
    largest = 1.797_693_134_862_315_7e308

    assert [
             Arithmetic.add(1.0e308, 1.0e308),
             Arithmetic.subtract(-1.0e308, 1.0e308),
             Arithmetic.multiply(1.0e308, 10),
             Arithmetic.multiply(1.0e308, -10),
             Arithmetic.divide(1.0e308, 1.0e-10),
             Arithmetic.divide(1.0e308, -1.0e-10),
             Arithmetic.add(largest, 1.0e292),
             Arithmetic.add(largest, 9.9e291)
           ] === [
             :infinity,
             :neg_infinity,
             :infinity,
             :neg_infinity,
             :infinity,
             :neg_infinity,
             :infinity,
             largest
           ]
  end

  # Golden: R 4.6.1's sum() of c(xmax, xmax, -xmax), c(-xmax, -xmax, xmax), c(1e308, 1e308),
  # c(-1e308, -1e308), c(xmax, 1e291) and c(-xmax, -1e291), for the largest double xmax, is xmax,
  # -xmax, Inf, -Inf, Inf and -Inf: its long double passes the largest double and comes back, and
  # a sum past it by any amount is an infinity, though 1e291 is less than half xmax's last place;
  # rowsum() of c(xmax, xmax, -xmax) and c(-1e308, -1e308) is Inf and -Inf, adding in doubles.
  test "sum adds past the largest double and back, as R's long double does" do
    largest = 1.797_693_134_862_315_7e308

    extended =
      Enum.map(
        [
          [largest, largest, -largest],
          [-largest, -largest, largest],
          [1.0e308, 1.0e308],
          [-1.0e308, -1.0e308],
          [largest, 1.0e291],
          [-largest, -1.0e291]
        ],
        &Arithmetic.sum/1
      )

    plain =
      Enum.map([[largest, largest, -largest], [-1.0e308, -1.0e308]], fn values ->
        Arithmetic.sum(values, :plain)
      end)

    assert {extended, plain} ===
             {[largest, -largest, :infinity, :neg_infinity, :infinity, :neg_infinity],
              [:infinity, :neg_infinity]}
  end

  # Golden: R 4.6.1's cumsum() of c(1e308, 1e308, -1e308), c(-1e308, -1e308, 1e308), c(xmax,
  # 1e292) and c(xmax, 1e291), for the largest double xmax, is 1e308, Inf, 1e308; -1e308, -Inf,
  # -1e308; xmax, Inf; and xmax, xmax: each running sum rounded to a double, its long double
  # carried on.
  test "cumulative_sum rounds each running sum to a double, an infinity past the largest" do
    largest = 1.797_693_134_862_315_7e308

    sums =
      Enum.map(
        [
          [1.0e308, 1.0e308, -1.0e308],
          [-1.0e308, -1.0e308, 1.0e308],
          [largest, 1.0e292],
          [largest, 1.0e291]
        ],
        &Arithmetic.cumulative_sum/1
      )

    assert sums === [
             [1.0e308, :infinity, 1.0e308],
             [-1.0e308, :neg_infinity, -1.0e308],
             [largest, :infinity],
             [largest, largest]
           ]
  end

  # Golden: R 4.6.1's var() of c(1, NA), c(1, NaN), 1, numeric(0), c(1, Inf), c(Inf, Inf),
  # c(-Inf, Inf), c(1L, 2L, 4L), c(1e154, 3e154) and c(1e-200, 3e-200): NA, NA, NA, NA, NaN, NaN,
  # NaN, 2.3333333333333335, Inf and 0, the last two squared past a double's range in R's long
  # double and rounded back.
  test "variance is R's var(): missing where a value is or for fewer than two, NaN for an infinity" do
    variances =
      Enum.map(
        [
          [1.0, nil],
          [1.0, :nan],
          [1.0],
          [],
          [1.0, :infinity],
          [:infinity, :infinity],
          [:neg_infinity, :infinity],
          [1, 2, 4],
          [1.0e154, 3.0e154],
          [1.0e-200, 3.0e-200]
        ],
        &Arithmetic.variance/1
      )

    assert variances === [
             nil,
             nil,
             nil,
             nil,
             :nan,
             :nan,
             :nan,
             2.3333333333333335,
             :infinity,
             0.0
           ]
  end

  # Golden: R 4.6.1's var() of c(3758990132.12738, -3902233189.5651264) and of
  # c(100000000.16079396, 100000000.18124922), from a run of 3,000 random vectors all of which
  # this matched digit for digit: 2.934717139242258e19 and 2.092087511498253e-4. Squaring each
  # distance in doubles gives 2.9347171392422584e19 for the first, and taking the distances from
  # the mean before it is rounded to a double gives 2.0920875114971427e-4 for the second.
  test "variance squares each distance from R's mean, a double, in R's long double" do
    variances =
      Enum.map(
        [
          [3_758_990_132.12738, -3_902_233_189.5651264],
          [100_000_000.16079396, 100_000_000.18124922]
        ],
        &Arithmetic.variance/1
      )

    assert variances === [2.934_717_139_242_258e19, 2.092087511498253e-4]
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

  # Golden: R 4.6.1's mean() of c(63.9, 61, 62), c(0.2, 0.1, 0.3), c(0.1, 0.2), c(1e16, 1,
  # -1e16), 318315.3026679394 and c(0.2, 1/3, 0.15, 0.15, 1/3, 1/3), printed to 17 significant
  # digits: 62.299999999999997, 0.20000000000000001, 0.15000000000000002, 0.33365885416666669,
  # 318315.3026679394 and 0.25, the last rounded up to a power of two. Their
  # sums in extended precision divided by the count are 62.300000000000004, 0.19999999999999998,
  # 0.15000000000000002 and 0.33333333333333331: R's correction pass, run in a long double, moves
  # the first two to the nearest double and the fourth away from a third.
  test "mean works a double's mean out in R's long double, its correction pass included" do
    means =
      Enum.map(
        [
          [63.9, 61.0, 62.0],
          [0.2, 0.1, 0.3],
          [0.1, 0.2],
          [1.0e16, 1.0, -1.0e16],
          [318_315.3026679394],
          [0.2, 1 / 3, 0.15, 0.15, 1 / 3, 1 / 3]
        ],
        &Arithmetic.mean/1
      )

    assert means === [
             62.3,
             0.2,
             0.15000000000000002,
             0.33365885416666669,
             318_315.3026679394,
             0.25
           ]
  end

  # Golden: R 4.6.1's mean() of c(-63.9, -61, -62), c(-40L, -1L), c(-3L, 2L) and c(-20L, 19L,
  # 943L, 658L) is -62.299999999999997, -20.5, -0.5 and 400, the last two summing through -1.
  test "mean of negative numbers, and of numbers whose sum passes through minus one" do
    means =
      Enum.map(
        [[-63.9, -61.0, -62.0], [-40, -1], [-3, 2], [-20, 19, 943, 658]],
        &Arithmetic.mean/1
      )

    assert means === [-62.3, -20.5, -0.5, 400.0]
  end

  # Golden: R 4.6.1's mean() of c(1e308, 1e308), c(xmax, xmax, -xmax) for the largest double xmax,
  # c(-1e308, -1e308, -1e308) and four groups more is 1e308, 5.9923104495410527e307, -1e308,
  # 6.9897163132118515e307, 7.0402622397762528e307, 2.3338916697571253e307 and
  # 8.6468525515221684e307, where a sum in doubles is past the largest.
  test "mean of doubles whose sum is past the largest double divides each by the count first" do
    largest = 1.797_693_134_862_315_7e308

    groups = [
      [1.0e308, 1.0e308],
      [largest, largest, -largest],
      [-1.0e308, -1.0e308, -1.0e308],
      [4.168_599_793_333_291e307, 1.765_594_128_393_718_4e308, -8.553_921_376_349_224e306],
      [1.464_632_171_521_229_2e308, 5.489_737_992_779_053e307, 9.847_270_113_374_125e306],
      [9.037_815_588_600_006e307, 1.503_107_267_045_453_3e308, -1.706_721_324_978_316_3e308],
      [
        4.988_551_670_890_670_5e307,
        1.667_861_330_012_879_3e308,
        1.075_487_726_028_560_3e308,
        2.165_367_974_783_605e307
      ]
    ]

    assert Enum.map(groups, &Arithmetic.mean/1) === [
             1.0e308,
             5.992_310_449_541_052_7e307,
             -1.0e308,
             6.989_716_313_211_851_5e307,
             7.040_262_239_776_252_8e307,
             2.333_891_669_757_125_3e307,
             8.646_852_551_522_168_4e307
           ]
  end

  # Golden: R 4.6.1's mean() of c(5e-324, 5e-324), c(5e-324, 0), -5e-324, c(-2.1e-322, 2.27e-322)
  # and c(7.4e-323, -1e-323) is 4.9406564584124654e-324, 0, -4.9406564584124654e-324,
  # 9.8813129168249309e-324 and 2.9643938750474793e-323, rounded to a multiple of the least
  # double, half of it a tie rounded to even; and 1 / mean(-0) is Inf, its sum begun from plus
  # zero.
  test "mean rounds to a double last, below the least normal one too, and has no minus zero" do
    groups = [
      [5.0e-324, 5.0e-324],
      [5.0e-324, 0.0],
      [-5.0e-324],
      [-2.1e-322, 2.27e-322],
      [7.4e-323, -1.0e-323],
      [-0.0],
      [-0.0, -0.0]
    ]

    assert Enum.map(groups, &Arithmetic.mean/1) === [
             5.0e-324,
             0.0,
             -5.0e-324,
             1.0e-323,
             3.0e-323,
             0.0,
             0.0
           ]
  end

  # Golden: R 4.6.1's mean(c(1L, 2L)) is 1.5 and mean(c(640883879L, integer(4094))) is
  # 156503.99975579977, the exact sum divided once in a long double and rounded to a double, where
  # dividing in doubles gives 156503.99975579974.
  test "mean of integers divides their exact sum once in R's long double" do
    many = [640_883_879 | List.duplicate(0, 4094)]

    assert {Arithmetic.mean([1, 2]), Arithmetic.mean(many)} === {1.5, 156_503.99975579977}
  end

  # Golden: R 4.6.1's mean() of c(988267548L, integer(2046)), c(958952461L, integer(2046)) and
  # c(1689158812L, integer(2046)) is 482788.25012212998, 468467.25012212998 and
  # 825187.49975574005: each quotient's 64th bit is decided by whether anything is left below
  # it, and that bit decides the double.
  test "mean of integers rounds its quotient as the exact quotient would be rounded" do
    sums = [988_267_548, 958_952_461, 1_689_158_812]

    means = Enum.map(sums, fn sum -> Arithmetic.mean([sum | List.duplicate(0, 2046)]) end)

    assert means === [482_788.25012212998, 468_467.25012212998, 825_187.49975574005]
  end
end
