defmodule Giggly.DataFrame.Arithmetic do
  @moduledoc false

  # R's arithmetic on the doubles a frame holds, which hold what R's do: `nil`, R's `NA`; `:nan`;
  # `:infinity` and `:neg_infinity`; and every finite float, minus zero among them. The frame owns
  # these values, so it owns their arithmetic: what a stat works out from its summarised table (a
  # share, a density, a count over the largest) and what stacking adds up, once a weight or a
  # height is infinite, and a mean, follow IEEE arithmetic and R's `pmin()`, `pmax()`, `max()`,
  # `mean()` and `<` here, rather than Elixir's, which has no infinity and raises dividing by zero
  # or past the largest double. Where a missing value (`nil`) and NaN meet, the one R keeps wins:
  # an operator's first operand, `pmin()`'s and `pmax()`'s later one, and `max()`'s and `mean()`'s
  # missing value.

  alias Giggly.DataFrame.LongDouble

  @typedoc "A double as the frame holds it."
  @type double :: number() | :nan | :infinity | :neg_infinity | nil

  @infinities [:infinity, :neg_infinity]

  # The largest double, past which R's `sum()` reads its long double as an infinity.
  @largest 1.797_693_134_862_315_7e308

  # `left + right`: an infinity wins over any number, and two of opposite signs make NaN; two
  # numbers whose sum is past the largest double make an infinity of their sign.
  @doc false
  @spec add(double(), double()) :: double()
  def add(left, right) when is_number(left) and is_number(right) do
    left + right
  rescue
    ArithmeticError -> infinity(sign(left))
  end

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

  # `left * right`: an infinity times 0 is NaN, and otherwise an infinity of the two signs' product,
  # as is a product of numbers past the largest double.
  @doc false
  @spec multiply(double(), double()) :: double()
  def multiply(left, right) when is_number(left) and is_number(right) do
    left * right
  rescue
    ArithmeticError -> infinity(sign(left) * sign(right))
  end

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

  # The infinity of a sign: IEEE rounds a result past the largest double to it, where Erlang
  # raises `ArithmeticError`, which a finite operand's sum, product or quotient raises for nothing
  # else.
  defp infinity(1), do: :infinity
  defp infinity(-1), do: :neg_infinity

  # `numerator / denominator`: missing where either is, NaN where either is NaN, or for 0 over 0
  # and an infinity over an infinity; an infinity of the right sign for a number other than 0
  # over 0, an infinity over a number, or a quotient past the largest double; and 0 of the right
  # sign for a number over an infinity.
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

  def divide(numerator, denominator) when denominator != 0 do
    numerator / denominator
  rescue
    ArithmeticError -> infinity(sign(numerator) * sign(denominator))
  end

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
  # infinity, or NaN where the two meet; and otherwise the numbers added in extended precision, in
  # R's long double (`Giggly.DataFrame.LongDouble`), which no sum of doubles overflows, a sum past
  # the largest double either way an infinity, as R's `sum()` reads it, and the rest rounded to a
  # double (`:extended`, the default); or in order in doubles, as R's `rowsum()` adds them, a sum
  # past the largest double an infinity from there on (`:plain`).
  @doc false
  @spec sum([double()], :extended | :plain) :: double()
  def sum(values, summation \\ :extended) when summation in [:extended, :plain] do
    case Enum.find(values, :none, fn value -> value in [nil, :nan] end) do
      :none -> added(values, summation)
      missing -> missing
    end
  end

  defp added(values, summation) do
    case infinite(values) do
      :none -> finite_sum(values, summation)
      infinite -> infinite
    end
  end

  # What numbers with an infinity among them add up to, as IEEE adds them: NaN where the two
  # infinities meet, else the infinity; `:none` where there is none.
  defp infinite(values) do
    cond do
      :infinity in values and :neg_infinity in values -> :nan
      :infinity in values -> :infinity
      :neg_infinity in values -> :neg_infinity
      true -> :none
    end
  end

  defp finite_sum(values, :plain), do: Enum.reduce(values, 0.0, &add/2)

  defp finite_sum(values, :extended) do
    sum = long_double_sum(values)

    cond do
      LongDouble.compare(sum, LongDouble.from_double(@largest)) == :gt -> :infinity
      LongDouble.compare(sum, LongDouble.from_double(-@largest)) == :lt -> :neg_infinity
      true -> LongDouble.to_double(sum)
    end
  end

  # Numbers added in R's long double, each an integer or a double.
  defp long_double_sum(values) do
    Enum.reduce(values, LongDouble.zero(), fn value, sum ->
      LongDouble.add(sum, long_double(value))
    end)
  end

  defp long_double(integer) when is_integer(integer), do: LongDouble.from_integer(integer)
  defp long_double(double), do: LongDouble.from_double(double)

  # The mean of `values`, R's `mean()`: missing where one is `nil` (R's `NA`), wherever it is, as
  # R's long double keeps `NA` over NaN; else NaN where one is NaN; else an infinity, or NaN, as
  # they add; and otherwise worked out as R works it out in a long double
  # (`Giggly.DataFrame.LongDouble`), each step rounded to 64 bits and the mean to a double last.
  # Integers are summed and divided once by their count. Doubles are summed and divided, and the
  # sum of their distances from that mean, divided by the count, is added to it, R's correction,
  # which can leave it further from the exact mean: 1e16, 1 and -1e16 have the mean
  # 0.33365885416666669, as R's has. Where their sum is past the largest double, each is divided
  # by the count first, in doubles, and so is each distance, as R does.
  @doc false
  @spec mean([double(), ...]) :: double()
  def mean([_first | _rest] = values) do
    cond do
      nil in values -> nil
      :nan in values -> :nan
      true -> averaged(values)
    end
  end

  defp averaged(values) do
    case infinite(values) do
      :none -> finite_mean(values)
      infinite -> infinite
    end
  end

  defp finite_mean([first | _rest] = integers) when is_integer(first) do
    integers
    |> long_double_sum()
    |> LongDouble.divide(length(integers))
    |> LongDouble.to_double()
  end

  defp finite_mean(doubles) do
    count = length(doubles)
    long_doubles = Enum.map(doubles, &LongDouble.from_double/1)
    sum = Enum.reduce(long_doubles, LongDouble.zero(), &LongDouble.add/2)

    mean =
      if is_float(LongDouble.to_double(sum)) do
        mean = LongDouble.divide(sum, count)

        correction =
          Enum.reduce(long_doubles, LongDouble.zero(), fn long_double, total ->
            LongDouble.add(total, LongDouble.subtract(long_double, mean))
          end)

        LongDouble.add(mean, LongDouble.divide(correction, count))
      else
        mean =
          Enum.reduce(doubles, LongDouble.zero(), fn double, sum ->
            LongDouble.add(sum, LongDouble.from_double(double / count))
          end)

        correction =
          Enum.reduce(long_doubles, LongDouble.zero(), fn long_double, total ->
            distance = LongDouble.subtract(long_double, mean)
            LongDouble.add(total, LongDouble.divide(distance, count))
          end)

        LongDouble.add(mean, correction)
      end

    LongDouble.to_double(mean)
  end

  # The running sums of `values`, R's `cumsum()`: each the sum of the values up to it, added in
  # R's long double and rounded to a double, as R's `cumsum()` rounds each, so a running sum past
  # the largest double is an infinity there and a number again once later values bring it back.
  # From a missing value or an infinity on, each is what `add/2` makes of the sum before it and the
  # value, but that once a value is `nil` (R's `NA`) every sum after it is, NaN met before or
  # after, as R's long double keeps `NA` over NaN.
  @doc false
  @spec cumulative_sum([double()]) :: [double()]
  def cumulative_sum(values) do
    {sums, _running} = Enum.map_reduce(values, LongDouble.zero(), &running/2)
    sums
  end

  # The next running sum and what the one after it adds to: a long double while every value has
  # been a number, and the non-finite sum once one has not, which is the first value not a number
  # itself, as `add/2` makes a number's sum with it.
  defp running(value, sum) when is_number(value) and is_tuple(sum) do
    next = LongDouble.add(sum, long_double(value))
    {LongDouble.to_double(next), next}
  end

  defp running(value, sum) when is_tuple(sum), do: {value, value}
  defp running(nil, _sum), do: {nil, nil}

  defp running(value, sum) do
    next = add(sum, value)
    {next, next}
  end

  # Where a double that is neither missing nor NaN falls among the others.
  defp rank(:neg_infinity), do: {0, 0}
  defp rank(:infinity), do: {2, 0}
  defp rank(number), do: {1, number}
end
