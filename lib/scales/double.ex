defmodule Scales.Double do
  @moduledoc false

  # R's arithmetic on a double as the package holds one (`t:Scales.double/0`). Elixir's
  # arithmetic has no infinity and raises dividing by zero or past the largest double; here each
  # operator gives what IEEE arithmetic gives, as R's does: an infinity past the largest double,
  # NaN for zero over zero, an infinity times zero and an infinity less itself. A zero's sign is
  # read from its bit, so a quotient over `-0.0` is the infinity IEEE gives.
  #
  # The operators take a number, an infinity or `:nan` (`t:operand/0`), as their callers hand them
  # once a missing value has been set aside; the square root and the absolute value, which a
  # palette maps over its places, take `nil` too and keep it. The elementary functions R's
  # transformations are built from are here too, each R's at the infinities, NaN and zero, and
  # those Erlang lacks, log1p, expm1 and the normal distribution, quantile and density, by
  # measured methods, never ported from R's or C's source.

  @infinities [:infinity, :neg_infinity]

  @typedoc "A double an operator takes: a number, an infinity or NaN."
  @type operand :: number() | :infinity | :neg_infinity | :nan

  # A bound a value can be compared with: a number or an infinity.
  defguard is_bound(value) when is_number(value) or value in [:infinity, :neg_infinity]

  # `left + right`: an infinity wins over a number, two of opposite signs make NaN, and two numbers
  # past the largest double make the infinity of their sign.
  @doc false
  @spec add(operand(), operand()) :: operand()
  def add(left, right) when is_number(left) and is_number(right) do
    left + right
  rescue
    ArithmeticError -> infinity(sign(left))
  end

  def add(:nan, _right), do: :nan
  def add(_left, :nan), do: :nan

  def add(left, right) when left in @infinities and right in @infinities and left != right,
    do: :nan

  def add(left, _right) when left in @infinities, do: left
  def add(_left, right), do: right

  # `left - right`, as `left + -right`, which IEEE arithmetic makes the same.
  @doc false
  @spec subtract(operand(), operand()) :: operand()
  def subtract(left, right), do: add(left, negate(right))

  # `left * right`: an infinity times a zero is NaN, any other the infinity of the signs'
  # product, as is a product of numbers past the largest double.
  @doc false
  @spec multiply(operand(), operand()) :: operand()
  def multiply(left, right) when is_number(left) and is_number(right) do
    left * right
  rescue
    ArithmeticError -> infinity(sign(left) * sign(right))
  end

  def multiply(:nan, _right), do: :nan
  def multiply(_left, :nan), do: :nan

  def multiply(left, right) do
    if zero?(left) or zero?(right), do: :nan, else: infinity(sign(left) * sign(right))
  end

  # `left / right`: a zero over a zero and an infinity over an infinity are NaN; anything else
  # over a zero, or an infinity over a number, the infinity of the signs' product, a zero's sign
  # its bit's; a number over an infinity a zero of the signs' product.
  @doc false
  @spec divide(operand(), operand()) :: operand()
  def divide(:nan, _right), do: :nan
  def divide(_left, :nan), do: :nan
  def divide(left, right) when left in @infinities and right in @infinities, do: :nan

  def divide(left, right) when is_number(left) and is_number(right) do
    cond do
      not zero?(right) -> quotient(left, right)
      zero?(left) -> :nan
      true -> infinity(sign(left) * sign(right))
    end
  end

  def divide(left, right) when left in @infinities, do: infinity(sign(left) * sign(right))
  def divide(left, right), do: if(sign(left) * sign(right) > 0, do: 0.0, else: -0.0)

  # The square root, NaN below zero, as IEEE's: `-0.0`'s is `-0.0` and `:infinity`'s itself.
  @doc false
  @spec square_root(Scales.double()) :: Scales.double()
  def square_root(value) when value in [nil, :nan, :infinity], do: value
  def square_root(:neg_infinity), do: :nan
  def square_root(value) when value < 0, do: :nan
  def square_root(value), do: :math.sqrt(value)

  # The logarithm of `value` in `base`, a number above 1, as R's `log(x, base)`: in base 2 and
  # 10 their own functions, else the ratio of natural logarithms; zero's minus infinity, a value
  # below zero or minus infinity NaN.
  @doc false
  @spec logarithm(operand(), number()) :: operand()
  def logarithm(:infinity, _base), do: :infinity

  def logarithm(value, base) when is_number(value) and value > 0,
    do: positive_logarithm(value, base)

  def logarithm(value, _base) when value == 0, do: :neg_infinity
  def logarithm(_negative_or_nan, _base), do: :nan

  defp positive_logarithm(value, base) when base == 2, do: :math.log2(value)
  defp positive_logarithm(value, base) when base == 10, do: :math.log10(value)
  defp positive_logarithm(value, base), do: :math.log(value) / :math.log(base)

  # `base` to the power `exponent`, as R's `^` gives it: a square is `base * base`; 1 to any
  # power and anything to the power 0 are 1, NaN's too; zero to a positive power is 0 and to a
  # negative one plus infinity, whatever its sign; an infinite base or exponent goes where the
  # power tends, but a negative base to an infinite or fractional power is NaN, and minus infinity
  # to a whole power has that power's sign; past the largest double it is the infinity of its
  # sign. Each case as R 4.6.1 gives it.
  @doc false
  @spec power(operand(), operand()) :: operand()
  def power(base, exponent) when is_number(base) and is_number(exponent) and exponent == 2,
    do: multiply(base / 1, base)

  def power(base, exponent)
      when (is_number(base) and base == 1) or (is_number(exponent) and exponent == 0),
      do: 1.0

  def power(base, exponent) when base == :nan or exponent == :nan, do: :nan

  def power(base, exponent) when is_number(base) and base == 0,
    do: if(positive?(exponent), do: 0.0, else: :infinity)

  def power(:infinity, exponent), do: if(positive?(exponent), do: :infinity, else: 0.0)

  def power(:neg_infinity, exponent) when is_number(exponent) and exponent < 0,
    do: if(whole?(exponent), do: 0.0, else: :nan)

  def power(:neg_infinity, exponent) when is_number(exponent),
    do: if(whole?(exponent), do: odd_power(exponent), else: :nan)

  def power(base, exponent) when exponent in @infinities, do: infinite_power(base, exponent)

  def power(base, exponent) do
    :math.pow(base, exponent)
  rescue
    ArithmeticError -> finite_power_beyond(base, exponent)
  end

  defp positive?(exponent), do: exponent == :infinity or (is_number(exponent) and exponent > 0)

  defp whole?(exponent), do: exponent == Float.floor(exponent / 1)

  # Minus infinity, or a negative base past the largest double, to a whole power: its sign the
  # base's when the power is odd.
  defp odd_power(exponent) when rem(trunc(exponent), 2) == 0, do: :infinity
  defp odd_power(_exponent), do: :neg_infinity

  # A finite base to an infinite power, or minus infinity to one: NaN below zero, else the
  # infinity or zero the power tends to.
  defp infinite_power(base, _exponent) when base == :neg_infinity or base < 0, do: :nan
  defp infinite_power(base, :infinity), do: if(base > 1, do: :infinity, else: 0.0)
  defp infinite_power(base, :neg_infinity), do: if(base < 1, do: :infinity, else: 0.0)

  # What Erlang refuses: a negative base to a fractional power, NaN, and a power past the largest
  # double, the infinity of its sign. A power below the smallest double is Erlang's zero.
  defp finite_power_beyond(base, exponent) do
    cond do
      base < 0 and not whole?(exponent) -> :nan
      base < 0 -> odd_power(exponent)
      true -> :infinity
    end
  end

  # e to the power `value`, as R's `exp()`: minus infinity's zero, and a power past the largest
  # double plus infinity.
  @doc false
  @spec exponential(operand()) :: operand()
  def exponential(:neg_infinity), do: 0.0
  def exponential(value) when value in [:infinity, :nan], do: value

  def exponential(value) do
    :math.exp(value)
  rescue
    ArithmeticError -> :infinity
  end

  # `log(1 + value)`, as R's `log1p()`, accurate near zero, which Erlang has no function for:
  # Goldberg's method (1991, theorem 4), `log(u) * value / (u - 1)` for `u = 1 + value`, whose
  # rounding error cancels between the two; `value` itself where `u` rounds to 1. Minus one's is
  # minus infinity, below it NaN; a zero of either sign gives `0.0`, as R's gives `+0` on a vector.
  # Measured against R on 6,006 random values, within 2 ulps, nearly all exact.
  @doc false
  @spec logarithm_of_one_plus(operand()) :: operand()
  def logarithm_of_one_plus(value) when value in [:infinity, :nan], do: value
  def logarithm_of_one_plus(:neg_infinity), do: :nan
  def logarithm_of_one_plus(value) when value == 0, do: 0.0
  def logarithm_of_one_plus(value) when value == -1, do: :neg_infinity
  def logarithm_of_one_plus(value) when value < -1, do: :nan

  def logarithm_of_one_plus(value) do
    sum = 1.0 + value
    if sum == 1.0, do: value, else: :math.log(sum) * (value / (sum - 1.0))
  end

  # `exp(value) - 1`, as R's `expm1()`, accurate near zero, which Erlang has no function for:
  # Kahan's method, `(u - 1) * value / log(u)` for `u = exp(value)`, whose rounding error cancels
  # between the two; `value` itself where `u` rounds to 1, and -1 where `u - 1` does. Minus
  # infinity's is -1, a power past the largest double plus infinity, and a zero of either sign
  # gives `0.0`, as R's gives `+0` on a vector. Measured against R on 3,005 random values, within
  # 1 ulp, nearly all exact.
  @doc false
  @spec exponential_minus_one(operand()) :: operand()
  def exponential_minus_one(:nan), do: :nan
  def exponential_minus_one(value) when value == 0, do: 0.0

  def exponential_minus_one(value) do
    case exponential(value) do
      :infinity -> :infinity
      power when power == 1.0 -> value
      power when power - 1.0 == -1.0 -> -1.0
      power -> (power - 1.0) * (value / :math.log(power))
    end
  end

  # The hyperbolic sine, as R's `sinh()`: an infinity's itself, past the largest double the
  # infinity of the value's sign, and a zero of either sign `0.0`, as R's on a vector.
  @doc false
  @spec hyperbolic_sine(operand()) :: operand()
  def hyperbolic_sine(value) when value in @infinities or value == :nan, do: value
  def hyperbolic_sine(value) when value == 0, do: 0.0

  def hyperbolic_sine(value) do
    :math.sinh(value)
  rescue
    ArithmeticError -> infinity(sign(value))
  end

  # The hyperbolic cosine, as R's `cosh()`: an infinity's, and past the largest double, plus
  # infinity.
  @doc false
  @spec hyperbolic_cosine(operand()) :: operand()
  def hyperbolic_cosine(value) when value in @infinities, do: :infinity
  def hyperbolic_cosine(:nan), do: :nan

  def hyperbolic_cosine(value) do
    :math.cosh(value)
  rescue
    ArithmeticError -> :infinity
  end

  # The inverse hyperbolic sine, as R's `asinh()`: an infinity's itself, and a zero of either sign
  # `0.0`, as R's on a vector. The platform's (`:math.asinh/1`, its C library's): R's is correctly
  # rounded, and against it this one was 1 ulp off on 369 of 3,000 random values under glibc 2.39,
  # exact where the platform's is correctly rounded too.
  @doc false
  @spec inverse_hyperbolic_sine(operand()) :: operand()
  def inverse_hyperbolic_sine(value) when value in @infinities or value == :nan, do: value
  def inverse_hyperbolic_sine(value) when value == 0, do: 0.0
  def inverse_hyperbolic_sine(value), do: :math.asinh(value)

  # The hyperbolic tangent, as R's `tanh()`: an infinity's the one of its sign, and a zero of
  # either sign `0.0`, as R's. The platform's (`:math.tanh/1`), 1 ulp off R's on 1 of 3,000
  # random values.
  @doc false
  @spec hyperbolic_tangent(operand()) :: operand()
  def hyperbolic_tangent(:infinity), do: 1.0
  def hyperbolic_tangent(:neg_infinity), do: -1.0
  def hyperbolic_tangent(:nan), do: :nan
  def hyperbolic_tangent(value) when value == 0, do: 0.0
  def hyperbolic_tangent(value), do: :math.tanh(value)

  # The inverse hyperbolic tangent, as R's `atanh()`: 1's plus infinity and -1's minus, NaN past
  # them and at the infinities, and a zero of either sign `0.0`, as R's. The platform's
  # (`:math.atanh/1`): R's is correctly rounded, and against it this one was 1 ulp off on 368 of
  # 3,000 random values under glibc 2.39, exact where the platform's is correctly rounded too. An
  # infinity or NaN, an atom, sorts above every number, so it is not between -1 and 1.
  @doc false
  @spec inverse_hyperbolic_tangent(operand()) :: operand()
  def inverse_hyperbolic_tangent(value) when value == 1, do: :infinity
  def inverse_hyperbolic_tangent(value) when value == -1, do: :neg_infinity
  def inverse_hyperbolic_tangent(value) when value == 0, do: 0.0
  def inverse_hyperbolic_tangent(value) when value > -1 and value < 1, do: :math.atanh(value)
  def inverse_hyperbolic_tangent(_beyond_one_infinity_or_nan), do: :nan

  # The sine, as R's `sin()`: NaN at the infinities, and a zero of either sign `0.0`, as R's. The
  # platform's (`:math.sin/1`).
  @doc false
  @spec sine(operand()) :: operand()
  def sine(value) when value in @infinities or value == :nan, do: :nan
  def sine(value) when value == 0, do: 0.0
  def sine(value), do: :math.sin(value)

  # The arcsine, as R's `asin()`: NaN past -1 and 1 and at the infinities, and a zero of either
  # sign `0.0`, as R's. The platform's (`:math.asin/1`). An infinity or NaN, an atom, sorts above
  # every number, so it is not between -1 and 1.
  @doc false
  @spec arc_sine(operand()) :: operand()
  def arc_sine(value) when value == 0, do: 0.0
  def arc_sine(value) when value >= -1 and value <= 1, do: :math.asin(value)
  def arc_sine(_beyond_one_infinity_or_nan), do: :nan

  # 1 / sqrt(2), and its rounding error, 1 / sqrt(2) less the double nearest it.
  @reciprocal_square_root_of_two 0.7071067811865476
  @reciprocal_square_root_of_two_error -4.833646656726457e-17
  @two_over_square_root_of_pi 1.1283791670955126
  @reciprocal_square_root_of_two_pi 0.3989422804014327

  # The standard normal distribution below `value`, as R's `pnorm()`, which Erlang has no
  # function for: `erfc(z) / 2` for `z = -value / sqrt(2)`, the rounding error in `z` found
  # exactly (Dekker's product, and 1 / sqrt(2)'s own rounding) and `erfc` moved by its derivative,
  # `-2 / sqrt(pi) * exp(-z^2)`, across it. Beyond 40 either side it is 0 or 1, as every double
  # there is, and the arithmetic would pass the largest double far beyond; plus infinity, an
  # atom, sorts above every number, so is among those above 40. Measured on 3,000 random values
  # under glibc 2.39: within 3 ulps of R's, correctly rounded on 88% of them against a 60-digit
  # truth, R's on 86%. `erfc` is the platform's, where R's computes its own, so another C library
  # moves these within that bound (2.43 puts R's 0.40129367431707630 at -0.25 a double below).
  @doc false
  @spec normal_distribution(operand()) :: operand()
  def normal_distribution(:nan), do: :nan
  def normal_distribution(:neg_infinity), do: 0.0
  def normal_distribution(value) when value < -40, do: 0.0
  def normal_distribution(value) when value > 40, do: 1.0
  def normal_distribution(value), do: distribution_below(value)

  # The standard normal quantile of `probability`, as R's `qnorm()`, which Erlang has no function
  # for: bisected to neighbouring doubles, the nearer taken. To 0.25 on the distribution
  # (`normal_distribution/1`), which gives the quartile correctly rounded; above it to 0.5 on
  # `erf(q / sqrt(2)) / 2` against `probability - 0.5`, exact there, with the rounding of
  # `q / sqrt(2)` corrected as the distribution's is, since many quantiles near 0 share one
  # distribution value near 0.5 (correctly rounded on 218 of 300 from 0.25 to 0.45, where the
  # distribution's bisection is on 122); above 0.5 by symmetry, `1 - probability` exact there. 0's
  # and 1's are the infinities, NaN outside them. Measured under glibc 2.39, on 3,000 random values:
  # within 5 ulps of R's, correctly rounded on 86% of them against a 60-digit truth, R's on 31%.
  # Below the smallest normal double, where one distribution double stands for a stretch of
  # quantiles, it is one of them: at 5e-324, -38.475 where R gives -38.467; from about 1e-310 up,
  # the stretch is under a double wide. An infinity or NaN, an atom, sorts above every number, so it
  # is between none of them.
  @doc false
  @spec normal_quantile(operand()) :: operand()
  def normal_quantile(probability) when probability == 0, do: :neg_infinity
  def normal_quantile(probability) when probability == 1, do: :infinity
  def normal_quantile(probability) when probability == 0.5, do: 0.0

  def normal_quantile(probability) when probability > 0 and probability < 0.5,
    do: lower_quantile(probability)

  def normal_quantile(probability) when probability > 0.5 and probability < 1,
    do: -lower_quantile(1.0 - probability)

  def normal_quantile(_outside_or_nan), do: :nan

  # The standard normal density, as R's `dnorm()`: `exp(-value^2 / 2) / sqrt(2 * pi)`, the square
  # split exactly into two doubles (Dekker's product) so its rounding is not raised to the power,
  # `exp(-high / 2) * exp(-low / 2)`. 0 at the infinities and beyond 40 either side, as every double
  # there is. Measured under glibc 2.39, on 3,493 random values: within 7 ulps of R's, as often
  # correctly rounded against a 60-digit truth, and nearer it between 4 and 5 either side, where R's
  # is up to 6 off it and this one 2. The square would pass the largest double far beyond 40; an
  # infinity, an atom, sorts above every number, so is among those beyond it.
  @doc false
  @spec normal_density(operand()) :: operand()
  def normal_density(:nan), do: :nan
  def normal_density(value) when value > 40 or value < -40, do: 0.0

  def normal_density(value) do
    {high, low} = exact_product(value, value)
    @reciprocal_square_root_of_two_pi * (:math.exp(-high / 2) * :math.exp(-low / 2))
  end

  # Where erfc underflows to 0, its step does too, so the distribution is 0.
  defp distribution_below(value) do
    {argument, step} = error_function_argument(-value)
    0.5 * (:math.erfc(argument) - step)
  end

  defp half_error_function(quantile) do
    {argument, step} = error_function_argument(quantile)
    0.5 * (:math.erf(argument) + step)
  end

  # The double nearest `value / sqrt(2)`, and the error function's change across its rounding
  # error: that error, found exactly (the product's, and 1 / sqrt(2)'s own), times the
  # derivative, 2 / sqrt(pi) exp(-z^2).
  defp error_function_argument(value) do
    {argument, product_error} = exact_product(value, @reciprocal_square_root_of_two)
    error = product_error + value * @reciprocal_square_root_of_two_error
    {argument, error * @two_over_square_root_of_pi * :math.exp(-argument * argument)}
  end

  defp lower_quantile(probability) when probability > 0.25,
    do: bisect(&half_error_function/1, probability - 0.5, -0.7, 0.0)

  defp lower_quantile(probability), do: bisect(&distribution_below/1, probability, -40.0, 0.0)

  # The double between `low` and `high` whose image under the rising `function` is nearest
  # `target`, halving the interval until no double lies between its ends.
  defp bisect(function, target, low, high) do
    middle = (low + high) / 2

    cond do
      middle == low or middle == high ->
        if abs(function.(low) - target) <= abs(function.(high) - target), do: low, else: high

      function.(middle) < target ->
        bisect(function, target, middle, high)

      true ->
        bisect(function, target, low, middle)
    end
  end

  # `left * right` as the double nearest it and that double's error, exactly (Dekker's product,
  # each split into halves of 26 bits).
  defp exact_product(left, right) do
    product = left * right
    {left_high, left_low} = halves(left)
    {right_high, right_low} = halves(right)

    error =
      left_high * right_high - product + left_high * right_low + left_low * right_high +
        left_low * right_low

    {product, error}
  end

  defp halves(value) do
    scaled = 134_217_729.0 * value
    high = scaled - (scaled - value)
    {high, value - high}
  end

  # The absolute value, an infinity's `:infinity`.
  @doc false
  @spec absolute(Scales.double()) :: Scales.double()
  def absolute(value) when value in [nil, :nan], do: value
  def absolute(value) when value in @infinities, do: :infinity
  def absolute(value), do: abs(value)

  # `-value`: an infinity's the other, and a zero's the zero of the other sign.
  @doc false
  @spec negate(operand()) :: operand()
  def negate(:nan), do: :nan
  def negate(:infinity), do: :neg_infinity
  def negate(:neg_infinity), do: :infinity
  def negate(value), do: -value

  # The smaller of two, R's `min()` on a pair: NaN where either is, and `left` where neither is
  # below the other, so the smaller of `-0.0` and `0.0` is whichever comes first, as R's is.
  @doc false
  @spec minimum(operand(), operand()) :: operand()
  def minimum(:nan, _right), do: :nan
  def minimum(_left, :nan), do: :nan
  def minimum(left, right), do: if(less?(right, left), do: right, else: left)

  # The larger of two, R's `max()` on a pair: NaN where either is, and `left` where neither is
  # above the other.
  @doc false
  @spec maximum(operand(), operand()) :: operand()
  def maximum(:nan, _right), do: :nan
  def maximum(_left, :nan), do: :nan
  def maximum(left, right), do: if(less?(left, right), do: right, else: left)

  # The mean of two numbers or infinities, R's `mean()` of a pair, which sums in a long double
  # from 0: two numbers whose sum is past the largest double still have a mean, their halves added
  # then, and two negative zeros' mean is `0.0`, as R's sum starts from a positive zero. With an
  # infinity or NaN the sum is an infinity or NaN, which halving leaves as it is.
  @doc false
  @spec mean(operand(), operand()) :: operand()
  def mean(left, right) when is_number(left) and is_number(right) do
    (left + right) / 2 + 0.0
  rescue
    ArithmeticError -> left / 2 + right / 2
  end

  def mean(left, right), do: add(left, right)

  # Whether `left` is below `right`, each a number or an infinity.
  @doc false
  @spec less?(Scales.Bounds.bound(), Scales.Bounds.bound()) :: boolean()
  def less?(left, right) when is_number(left) and is_number(right), do: left < right
  def less?(left, right) when is_bound(left) and is_bound(right), do: rank(left) < rank(right)

  defp rank(:neg_infinity), do: -1
  defp rank(:infinity), do: 1
  defp rank(_number), do: 0

  defp quotient(left, right) do
    left / right
  rescue
    ArithmeticError -> infinity(sign(left) * sign(right))
  end

  defp zero?(value), do: value == 0

  # A sign, 1 or -1, a number's read from its bits as a double, so `-0.0` is negative, as IEEE
  # divides by it, and an integer's, which has no negative zero, as its float's. No comparison comes
  # first: OTP 29's compiler turns a float guards have shown equal to 0 into `0.0`, losing a
  # negative zero's sign.
  defp sign(:infinity), do: 1
  defp sign(:neg_infinity), do: -1

  defp sign(number) do
    <<sign_bit::1, _rest::63>> = <<number::float>>
    1 - 2 * sign_bit
  end

  defp infinity(1), do: :infinity
  defp infinity(-1), do: :neg_infinity
end
