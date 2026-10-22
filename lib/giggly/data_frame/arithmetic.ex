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

  # The sum of `values`, R's `sum()`: missing where one is, `nil` (R's `NA`) or NaN, the first in
  # order, as R's running sum keeps the first; an infinity as IEEE adds one, so the sum is that
  # infinity, or NaN where the two meet; and otherwise the numbers added in extended precision, as
  # R's `sum()` adds them in a long double (`:compensated`, the default), or in order in doubles, as
  # R's `rowsum()` adds them (`:plain`).
  @doc false
  @spec sum([double()], :compensated | :plain) :: double()
  def sum(values, summation \\ :compensated) when summation in [:compensated, :plain] do
    case Enum.find(values, :none, fn value -> value in [nil, :nan] end) do
      :none -> added(values, summation)
      missing -> missing
    end
  end

  defp added(values, summation) do
    cond do
      :infinity in values and :neg_infinity in values -> :nan
      :infinity in values -> :infinity
      :neg_infinity in values -> :neg_infinity
      true -> finite_sum(values, summation)
    end
  end

  defp finite_sum(values, :plain), do: Enum.reduce(values, 0.0, &+/2)

  # Neumaier's compensated sum: each addition's rounding error, found exactly from the two values
  # and their rounded sum, is kept apart and added back once at the end, which gives the sum a long
  # double gives.
  defp finite_sum(values, :compensated) do
    {total, compensation} = Enum.reduce(values, {0.0, 0.0}, &compensated/2)
    total + compensation
  end

  # The running sums of `values`, R's `cumsum()`: each the sum of the values up to it, in extended
  # precision, as R's `cumsum()` adds in a long double and rounds each sum to a double, which a
  # running compensated sum gives. From a missing value or an infinity on, each is what `add/2`
  # makes of the sum before it and the value, but that once a value is `nil` (R's `NA`) every sum
  # after it is, NaN met before or after, as R's long double keeps `NA` over NaN.
  @doc false
  @spec cumulative_sum([double()]) :: [double()]
  def cumulative_sum(values) do
    {sums, _running} = Enum.map_reduce(values, {0.0, 0.0}, &running/2)
    sums
  end

  # The next running sum and what the one after it adds to: a compensated sum while every value
  # has been a number, and the non-finite sum once one has not, which is the first value not a
  # number itself, as `add/2` makes a number's sum with it.
  defp running(value, {_total, _compensation} = sum) when is_number(value) do
    {total, compensation} = compensated(value, sum)
    {total + compensation, {total, compensation}}
  end

  defp running(value, {_total, _compensation}), do: {value, value}
  defp running(nil, _sum), do: {nil, nil}

  defp running(value, sum) do
    next = add(sum, value)
    {next, next}
  end

  defp compensated(value, {total, compensation}) do
    sum = total + value
    {sum, compensation + rounding_error(total, value, sum)}
  end

  defp rounding_error(total, value, sum) when abs(total) >= abs(value), do: total - sum + value
  defp rounding_error(total, value, sum), do: value - sum + total

  # Where a double that is neither missing nor NaN falls among the others.
  defp rank(:neg_infinity), do: {0, 0}
  defp rank(:infinity), do: {2, 0}
  defp rank(number), do: {1, number}
end
