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
  # palette maps over its places, take `nil` too and keep it.

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

  # The absolute value, an infinity's `:infinity`.
  @doc false
  @spec absolute(Scales.double()) :: Scales.double()
  def absolute(value) when value in [nil, :nan], do: value
  def absolute(value) when value in @infinities, do: :infinity
  def absolute(value), do: abs(value)

  # The larger of two, R's `max()` on a pair: NaN where either is.
  @doc false
  @spec maximum(operand(), operand()) :: operand()
  def maximum(:nan, _right), do: :nan
  def maximum(_left, :nan), do: :nan
  def maximum(left, right), do: if(less?(left, right), do: right, else: left)

  # The mean of two numbers or infinities, R's `mean()` of a pair, which sums in a long double
  # from 0: two numbers whose sum is past the largest double still have a mean, their halves added
  # then, and two negative zeros' mean is `0.0`, as R's sum starts from a positive zero.
  @doc false
  @spec mean(operand(), operand()) :: operand()
  def mean(left, right) when is_number(left) and is_number(right) do
    (left + right) / 2 + 0.0
  rescue
    ArithmeticError -> left / 2 + right / 2
  end

  def mean(left, right) do
    left
    |> add(right)
    |> divide(2)
  end

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

  # A sign, 1 or -1; a zero's is its bit's, so `-0.0` is negative, as IEEE divides by it. A float
  # is read as a double's bits before any comparison: OTP 29's compiler turns a float guards have
  # shown equal to 0 into `0.0`, losing a negative zero's sign.
  defp sign(:infinity), do: 1
  defp sign(:neg_infinity), do: -1

  defp sign(number) when is_float(number) do
    <<sign_bit::1, _rest::63>> = <<number::float>>
    1 - 2 * sign_bit
  end

  defp sign(number) when number < 0, do: -1
  defp sign(_number), do: 1

  defp infinity(1), do: :infinity
  defp infinity(-1), do: :neg_infinity
end
