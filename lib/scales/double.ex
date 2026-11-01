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
  # transformations are built from are here too, each R's at the infinities, NaN and zero, and the
  # two Erlang lacks, log1p and expm1, by measured methods, never ported from R's or C's source.

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
  def logarithm(value, _base) when value in [:infinity, :nan], do: value

  def logarithm(value, base) when is_number(value) and value > 0,
    do: positive_logarithm(value, base)

  def logarithm(value, _base) when value == 0, do: :neg_infinity
  def logarithm(_negative, _base), do: :nan

  defp positive_logarithm(value, base) when base == 2, do: :math.log2(value)
  defp positive_logarithm(value, base) when base == 10, do: :math.log10(value)
  defp positive_logarithm(value, base), do: :math.log(value) / :math.log(base)

  # `base` to the power `exponent`, `base` a number above 1, as R's `base^x`: minus infinity's
  # zero, and a power past the largest double plus infinity.
  @doc false
  @spec power(number(), operand()) :: operand()
  def power(_base, :neg_infinity), do: 0.0
  def power(_base, exponent) when exponent in [:infinity, :nan], do: exponent

  def power(base, exponent) do
    :math.pow(base, exponent)
  rescue
    ArithmeticError -> :infinity
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
  def exponential_minus_one(value) when value in [:infinity, :nan], do: value
  def exponential_minus_one(:neg_infinity), do: -1.0
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

  # The absolute value, an infinity's `:infinity`.
  @doc false
  @spec absolute(Scales.double()) :: Scales.double()
  def absolute(value) when value in [nil, :nan], do: value
  def absolute(value) when value in @infinities, do: :infinity
  def absolute(value), do: abs(value)

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

  defp negate(:nan), do: :nan
  defp negate(:infinity), do: :neg_infinity
  defp negate(:neg_infinity), do: :infinity
  defp negate(value), do: -value

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
