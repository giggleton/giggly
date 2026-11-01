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

  describe "logarithm/2, power/2 and exponential/1" do
    # R's log(0, 3) is -Inf, log(-2, 3) and log(-Inf, 3) NaN, log(0.5, 3) -0.63092975357145742,
    # 3^-Inf 0, 3^0.5 1.7320508075688772, 3^800 Inf, exp(-Inf) 0, exp(2) 7.3890560989306504 and
    # exp(800) Inf (`inc4/step3/probe.R`)
    test "a logarithm is minus infinity at zero and NaN below it, in base 2 and 10 their own" do
      assert {Double.logarithm(0.0, 3), Double.logarithm(-0.0, 3), Double.logarithm(-2.0, 3),
              Double.logarithm(:neg_infinity, 3), Double.logarithm(:infinity, 3),
              Double.logarithm(:nan, 3), Double.logarithm(0.5, 3)} ===
               {:neg_infinity, :neg_infinity, :nan, :nan, :infinity, :nan, -0.63092975357145742}

      # log(1000, 10), where log(1000) / log(10) is 2.9999999999999996; log(3, 2), where
      # log(3) / log(2) is 1.5849625007211563
      assert {Double.logarithm(1000.0, 10), Double.logarithm(3.0, 2)} ===
               {3.0, 1.5849625007211561}
    end

    test "a power and an exponential are zero at minus infinity and infinite past the largest double" do
      assert {Double.power(3, :neg_infinity), Double.power(3, 0.5), Double.power(3, 800.0),
              Double.power(3, :infinity), Double.power(3, :nan)} ===
               {0.0, 1.7320508075688772, :infinity, :infinity, :nan}

      assert {Double.exponential(:neg_infinity), Double.exponential(2.0),
              Double.exponential(800.0), Double.exponential(:infinity), Double.exponential(:nan)} ===
               {0.0, 7.3890560989306504, :infinity, :infinity, :nan}
    end
  end

  describe "logarithm_of_one_plus/1 and exponential_minus_one/1" do
    # R's log1p(-1) is -Inf, log1p(-2) and log1p(-Inf) NaN, log1p(-0) +0 on a vector,
    # log1p(-1e-300) -1e-300, log1p(0.5) 0.40546510810816438; expm1(-Inf) -1, expm1(-1000) -1,
    # expm1(-0) +0, expm1(-1e-300) -1e-300, expm1(-2) -0.8646647167633873, expm1(800) Inf
    test "R's at each edge, a zero of either sign 0.0, and near zero the value itself" do
      assert {Double.logarithm_of_one_plus(-1.0), Double.logarithm_of_one_plus(-2.0),
              Double.logarithm_of_one_plus(:neg_infinity), Double.logarithm_of_one_plus(-0.0),
              Double.logarithm_of_one_plus(-1.0e-300), Double.logarithm_of_one_plus(0.5),
              Double.logarithm_of_one_plus(:infinity), Double.logarithm_of_one_plus(:nan)} ===
               {:neg_infinity, :nan, :nan, 0.0, -1.0e-300, 0.40546510810816438, :infinity, :nan}

      assert {Double.exponential_minus_one(:neg_infinity), Double.exponential_minus_one(-1000.0),
              Double.exponential_minus_one(-0.0), Double.exponential_minus_one(-1.0e-300),
              Double.exponential_minus_one(-2.0), Double.exponential_minus_one(800.0),
              Double.exponential_minus_one(:infinity), Double.exponential_minus_one(:nan)} ===
               {-1.0, -1.0, 0.0, -1.0e-300, -0.8646647167633873, :infinity, :infinity, :nan}
    end
  end

  describe "hyperbolic_sine/1, hyperbolic_cosine/1 and inverse_hyperbolic_sine/1" do
    # R's sinh(-0) and asinh(-0) are +0 on a vector, sinh(2) 3.626860407847019, sinh(-1000)
    # -Inf, cosh(2) 3.7621956910836314, cosh(-1000) and cosh(-Inf) Inf, asinh(2)
    # 1.4436354751788103
    test "R's at each edge, a zero of either sign 0.0, past the largest double an infinity" do
      assert {Double.hyperbolic_sine(-0.0), Double.hyperbolic_sine(2.0),
              Double.hyperbolic_sine(-1000.0), Double.hyperbolic_sine(1000.0),
              Double.hyperbolic_sine(:neg_infinity), Double.hyperbolic_sine(:nan)} ===
               {0.0, 3.626860407847019, :neg_infinity, :infinity, :neg_infinity, :nan}

      assert {Double.hyperbolic_cosine(2.0), Double.hyperbolic_cosine(-1000.0),
              Double.hyperbolic_cosine(:neg_infinity), Double.hyperbolic_cosine(:nan)} ===
               {3.7621956910836314, :infinity, :infinity, :nan}

      assert {Double.inverse_hyperbolic_sine(-0.0), Double.inverse_hyperbolic_sine(2.0),
              Double.inverse_hyperbolic_sine(:neg_infinity), Double.inverse_hyperbolic_sine(:nan)} ===
               {0.0, 1.4436354751788103, :neg_infinity, :nan}
    end

    # Golden: `fixtures/r_elementary_4.6.1.csv` is R 4.6.1's asinh(), log1p() and expm1() at
    # random doubles, from -1 up, tiny and huge (`inc4/step3/fixture.R`). R's asinh is correctly
    # rounded, the platform's within 1 ulp of it (369 of 3,000 off under glibc 2.39); Goldberg's
    # log1p is within 2 ulps of R's, Kahan's expm1 within 1.
    test "asinh, log1p and expm1 are within their measured ulps of R's" do
      bounds = %{"asinh" => 1, "log1p" => 2, "expm1" => 1}

      functions = %{
        "asinh" => &Double.inverse_hyperbolic_sine/1,
        "log1p" => &Double.logarithm_of_one_plus/1,
        "expm1" => &Double.exponential_minus_one/1
      }

      rows =
        __DIR__
        |> Path.join("fixtures/r_elementary_4.6.1.csv")
        |> File.stream!()
        |> Stream.drop(1)
        |> Enum.map(fn line ->
          [quoted, value, expected] =
            line
            |> String.trim()
            |> String.split(",")

          {String.trim(quoted, ~s(")), double(value), double(expected)}
        end)

      assert Enum.count(rows) == 1393

      far =
        Enum.reject(rows, fn {function, value, expected} ->
          ulps(functions[function].(value), expected) <= bounds[function]
        end)

      assert far == []
    end
  end

  # A number as R wrote it, `-1` among them.
  defp double(text) do
    {value, ""} = Float.parse(text)
    value
  end

  # How many doubles apart two finite doubles are, each read from its bits in their order.
  defp ulps(left, right), do: abs(ordinal(left) - ordinal(right))

  defp ordinal(value) do
    <<sign::1, magnitude::63>> = <<value::float>>
    if sign == 1, do: -magnitude, else: magnitude
  end
end
