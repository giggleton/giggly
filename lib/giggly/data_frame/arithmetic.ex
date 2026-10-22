defmodule Giggly.DataFrame.Arithmetic do
  @moduledoc false

  # R's arithmetic on the doubles a frame holds, which hold what R's do: `nil`, R's `NA`; `:nan`;
  # `:infinity` and `:neg_infinity`; and every finite float, minus zero among them. The frame owns
  # these values, so it owns their arithmetic: what a stat works out from its summarised table (a
  # share, a density, a count over the largest) and what stacking adds up, once a weight or a
  # height is infinite, follows IEEE arithmetic and R's `pmin()`, `pmax()`, `max()` and `<` here,
  # rather than Elixir's, which has no infinity and raises dividing by zero. Where a missing value
  # (`nil`) and NaN meet, the one R keeps wins: an operator's first operand, `pmin()`'s and
  # `pmax()`'s later one, and `max()`'s missing value.

  @typedoc "A double as the frame holds it."
  @type double :: number() | :nan | :infinity | :neg_infinity | nil

  @infinities [:infinity, :neg_infinity]

  # `left + right`: an infinity wins over any number, and two of opposite signs make NaN.
  @doc false
  @spec add(double(), double()) :: double()
  def add(left, right) when is_number(left) and is_number(right), do: left + right
  def add(left, _right) when left in [nil, :nan], do: left
  def add(_left, right) when right in [nil, :nan], do: right

  def add(left, right) when left in @infinities and right in @infinities and left != right,
    do: :nan

  def add(left, _right) when left in @infinities, do: left
  def add(_left, right), do: right

  # `left - right`, as `left + -right`.
  @doc false
  @spec subtract(double(), double()) :: double()
  def subtract(left, right), do: add(left, multiply(right, -1))

  # `left * right`: an infinity times 0 is NaN, and otherwise an infinity of the two signs' product.
  @doc false
  @spec multiply(double(), double()) :: double()
  def multiply(left, right) when is_number(left) and is_number(right), do: left * right
  def multiply(left, _right) when left in [nil, :nan], do: left
  def multiply(_left, right) when right in [nil, :nan], do: right

  def multiply(left, right) do
    case sign(left) * sign(right) do
      0 -> :nan
      positive when positive > 0 -> :infinity
      _negative -> :neg_infinity
    end
  end

  defp sign(:infinity), do: 1
  defp sign(:neg_infinity), do: -1
  defp sign(number) when number > 0, do: 1
  defp sign(number) when number < 0, do: -1
  defp sign(_zero), do: 0

  # `numerator / denominator`: missing where either is, NaN where either is NaN, or for 0 over 0
  # and an infinity over an infinity; an infinity of the right sign for a number other than 0
  # over 0, or an infinity over a number; and 0 of the right sign for a number over an infinity.
  @doc false
  @spec divide(double(), double()) :: double()
  def divide(numerator, _denominator) when numerator in [nil, :nan], do: numerator
  def divide(_numerator, denominator) when denominator in [nil, :nan], do: denominator

  def divide(numerator, denominator) when is_atom(numerator) and is_atom(denominator),
    do: :nan

  def divide(:infinity, denominator) when denominator < 0, do: :neg_infinity
  def divide(:infinity, _denominator), do: :infinity
  def divide(:neg_infinity, denominator) when denominator < 0, do: :infinity
  def divide(:neg_infinity, _denominator), do: :neg_infinity
  def divide(numerator, :infinity), do: numerator * 0.0
  def divide(numerator, :neg_infinity), do: numerator * -0.0
  def divide(numerator, denominator) when denominator != 0, do: numerator / denominator
  def divide(numerator, _zero) when numerator > 0, do: :infinity
  def divide(numerator, _zero) when numerator < 0, do: :neg_infinity
  def divide(_zero, _also_zero), do: :nan

  # A value's magnitude, R's `abs()`: an infinity's is plus infinity.
  @doc false
  @spec magnitude(double()) :: double()
  def magnitude(value) when is_number(value), do: abs(value)
  def magnitude(:neg_infinity), do: :infinity
  def magnitude(value), do: value

  # The lesser and the greater of two, R's `pmin()` and `pmax()`: missing or NaN where either is,
  # the later where both are, else by value, minus infinity below every number and infinity above.
  @doc false
  @spec lesser(double(), double()) :: double()
  def lesser(_left, right) when right in [nil, :nan], do: right
  def lesser(left, _right) when left in [nil, :nan], do: left
  def lesser(left, right), do: if(rank(right) < rank(left), do: right, else: left)

  @doc false
  @spec greater(double(), double()) :: double()
  def greater(_left, right) when right in [nil, :nan], do: right
  def greater(left, _right) when left in [nil, :nan], do: left
  def greater(left, right), do: if(rank(right) > rank(left), do: right, else: left)

  # Whether `left` is below `right`, R's `<`: missing where either is missing or NaN.
  @doc false
  @spec less?(double(), double()) :: boolean() | nil
  def less?(left, right) when nil in [left, right] or :nan in [left, right], do: nil
  def less?(left, right), do: rank(left) < rank(right)

  # The largest of `values`, R's `max()`: missing where any is, else NaN where any is NaN, else
  # an infinity beats every number.
  @doc false
  @spec maximum([double(), ...]) :: double()
  def maximum([first | rest] = values) do
    if nil in values, do: nil, else: Enum.reduce(rest, first, &greater/2)
  end

  # Where a double that is neither missing nor NaN falls among the others.
  defp rank(:neg_infinity), do: {0, 0}
  defp rank(:infinity), do: {2, 0}
  defp rank(number), do: {1, number}
end
