defmodule Scales.Bounds do
  @moduledoc """
  Values against the bounds of a range: values moved from one range to another (`rescale/3`,
  `rescale_mid/4`, `rescale_max/3`), whether a range is zero wide (`zero_range?/1`), and values
  outside a range censored (`censor/2`).

  The rescaling functions take numbers and `nil`, a missing value, which stays `nil`, and give
  R's answer to the last digit, in R's order of operations.
  """

  # R's `bounds.R`. R's rescaling functions are vectorised and leave `NA` as `NA`, which
  # `each_number/2` does here; R's `NaN` is `nil` too.

  # R's `zero_range()` tolerance: 1000 times the double-precision machine epsilon.
  @zero_range_tolerance 1000 * 2.220446049250313e-16

  @typedoc "A range, its low end and its high end."
  @type range :: {number(), number()}

  @doc """
  Moves each value linearly from the range `from` to the range `to`, R's `rescale()`.

  Where either range is zero wide (`zero_range?/1`), every value is put at the middle of `to`.

  ## Examples

      iex> Scales.Bounds.rescale([2, 4, nil, 10], {2, 10}, {0, 1})
      [0.0, 0.25, nil, 1.0]

      iex> Scales.Bounds.rescale([2, 6], {2, 10}, {10, -10})
      [10.0, 0.0]

      iex> Scales.Bounds.rescale([5, 5], {5, 5}, {0.1, 1.0})
      [0.55, 0.55]
  """
  @spec rescale([number() | nil], range(), range()) :: [float() | nil]
  def rescale(values, {from_low, from_high} = from, {to_low, to_high} = to) do
    if zero_range?(from) or zero_range?(to) do
      middled(values, to)
    else
      each_number(values, fn value ->
        (value - from_low) / (from_high - from_low) * (to_high - to_low) + to_low
      end)
    end
  end

  @doc """
  Moves each value from the range `from` to the range `to` about `midpoint`, R's
  `rescale_mid()`: `midpoint` goes to the middle of `to`, and the end of `from` further from
  `midpoint` to the end of `to` on its side, so the nearer end falls short of its own.

  Where either range is zero wide (`zero_range?/1`), every value is put at the middle of `to`.

  ## Examples

      iex> Scales.Bounds.rescale_mid([-1, 0, 3, nil], {-1, 3}, {0, 1}, 1)
      [0.0, 0.25, 1.0, nil]

      iex> Scales.Bounds.rescale_mid([-1, 0, 3], {-1, 3}, {10, 20}, 1)
      [10.0, 12.5, 20.0]
  """
  @spec rescale_mid([number() | nil], range(), range(), number()) :: [float() | nil]
  def rescale_mid(values, {from_low, from_high} = from, {to_low, to_high} = to, midpoint) do
    if zero_range?(from) or zero_range?(to) do
      middled(values, to)
    else
      # R's `2 * max(abs(from - mid))` and `mean(to)`.
      extent = 2 * max(abs(from_low - midpoint), abs(from_high - midpoint))
      middle = (to_low + to_high) / 2

      each_number(values, fn value ->
        (value - midpoint) / extent * (to_high - to_low) + middle
      end)
    end
  end

  @doc """
  Each value over the high end of `from`, times the high end of `to`, R's `rescale_max()`, so 0
  stays at 0; the low ends are not read.

  Over a high end of 0, a value other than 0 is an infinity, `:infinity` or `:neg_infinity`, and
  0 is R's `NaN`, `nil`, as is any value whose infinity is multiplied by a high end of `to` of 0.

  ## Examples

      iex> Scales.Bounds.rescale_max([1, 2, nil], {0, 4}, {0, 6})
      [1.5, 3.0, nil]

      iex> Scales.Bounds.rescale_max([0, 1, -1], {-2, 0}, {0, 1})
      [nil, :infinity, :neg_infinity]
  """
  @spec rescale_max([number() | nil], range(), range()) ::
          [float() | :infinity | :neg_infinity | nil]
  def rescale_max(values, {_from_low, from_high}, {_to_low, to_high}),
    do: each_number(values, fn value -> maximum_place(value, from_high, to_high) end)

  @doc """
  Whether a range is zero wide, R's `zero_range()`: its ends are equal, or so close, relative to
  the smaller, that their difference is rounding error, under 1000 times the machine epsilon.

  ## Examples

      iex> Scales.Bounds.zero_range?({3, 3})
      true

      iex> Scales.Bounds.zero_range?({1.0, 1.0000000000002218})
      true

      iex> Scales.Bounds.zero_range?({1.0, 1.000000000000222})
      false
  """
  @spec zero_range?(range()) :: boolean()
  def zero_range?({low, high}) when low == high, do: true

  def zero_range?({low, high}) do
    smaller = min(abs(low), abs(high))
    smaller != 0 and abs((low - high) / smaller) < @zero_range_tolerance
  end

  @doc """
  Each value, `nil` where it is a number outside `{low, high}`, R's `oob_censor()`.

  Only finite numbers are censored: `:infinity` and `:neg_infinity` are kept, as are values that
  are not numbers, but for `:nan`, which becomes `nil`. An end of `nil` censors nothing on its
  side.

  ## Examples

      iex> Scales.Bounds.censor([1, 5, 10, nil, :infinity, :nan], {2, 8})
      [nil, 5, nil, nil, :infinity, nil]

      iex> Scales.Bounds.censor([1, 5, 10], {nil, 8})
      [1, 5, nil]
  """
  @spec censor(list(), {number() | nil, number() | nil}) :: list()
  def censor(values, {low, high}),
    do: Enum.map(values, fn value -> censored(value, low, high) end)

  defp censored(value, low, _high) when is_number(value) and is_number(low) and value < low,
    do: nil

  defp censored(value, _low, high) when is_number(value) and is_number(high) and value > high,
    do: nil

  defp censored(:nan, _low, _high), do: nil
  defp censored(value, _low, _high), do: value

  # Every number at the middle of `to`, R's `mean(to)`, a `nil` left `nil`.
  defp middled(values, {to_low, to_high}) do
    middle = (to_low + to_high) / 2
    each_number(values, fn _value -> middle end)
  end

  # Each number through `function`, a `nil` left `nil`, as R's arithmetic leaves `NA`.
  defp each_number(values, function) do
    Enum.map(values, fn
      nil -> nil
      value when is_number(value) -> function.(value)
    end)
  end

  # `value / high * to_high` as R's IEEE arithmetic gives it, where Elixir's raises: over a zero,
  # an infinity of the signs' product, a negative zero's sign counting, or NaN, `nil`, for zero
  # over zero; an infinity times zero is NaN too.
  defp maximum_place(value, high, to_high) when high != 0, do: value / high * to_high
  defp maximum_place(value, _high, _to_high) when value == 0, do: nil
  defp maximum_place(_value, _high, to_high) when to_high == 0, do: nil

  defp maximum_place(value, high, to_high),
    do: infinity(sign(value) * sign(high) * sign(to_high))

  # A number's sign, read from its sign bit as a double, so `-0.0` is negative, as IEEE divides by
  # it. No comparison comes before it: OTP 29's compiler turns a float that guards have shown
  # equal to 0 into `0.0`, losing a negative zero's sign.
  defp sign(number) do
    <<sign_bit::1, _rest::63>> = <<number::float>>
    1 - 2 * sign_bit
  end

  defp infinity(1), do: :infinity
  defp infinity(-1), do: :neg_infinity
end
