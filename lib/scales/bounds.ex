defmodule Scales.Bounds do
  @moduledoc false

  # Values against the bounds of a range, R's `bounds.R`: a value moved from one range to another
  # (`rescale/3`), whether a range is zero wide (`zero_range?/2`), and values outside limits
  # censored (`censor/2`).

  # R's `zero_range()` tolerance: 1000 times the double-precision machine epsilon.
  @zero_range_tolerance 1000 * 2.220446049250313e-16

  # `value` moved from the range `from` to the range `to`, linearly: R's `scales::rescale()`,
  # `(value - from_low) / (from_high - from_low) * (to_high - to_low) + to_low`, in that order of
  # operations. A `from` of zero width, by R's `zero_range()`, puts every value at the middle of
  # `to`, as R does, so a column of one value maps to the middle of its palette.
  @doc false
  @spec rescale(number(), {number(), number()}, {number(), number()}) :: float()
  def rescale(value, {from_low, from_high}, {to_low, to_high}) do
    if zero_range?(from_low, from_high) do
      (to_low + to_high) / 2
    else
      (value - from_low) / (from_high - from_low) * (to_high - to_low) + to_low
    end
  end

  # R's `zero_range()`: equal ends, or ends so close, relative to the smaller, that their
  # difference is rounding error. A scale's extent and breaks both ask it, and so does
  # `Giggly.Resolution`, so the rule has one home.
  @doc false
  @spec zero_range?(number(), number()) :: boolean()
  def zero_range?(low, high) when low == high, do: true

  def zero_range?(low, high) do
    smaller = min(abs(low), abs(high))
    smaller != 0 and abs((low - high) / smaller) < @zero_range_tolerance
  end

  # Each value, `nil` where it is a number outside `{low, high}`, an end `nil` where the data
  # decides, as R's `oob_censor()` censors finite values only: an infinite end, `:infinity` or
  # `:neg_infinity`, is kept, so a rectangle reaching the panel's edge still does, and NaN becomes
  # `nil`, as ggplot2's position map gives `NA` for it.
  @doc false
  @spec censor(list(), {number() | nil, number() | nil}) :: list()
  def censor(values, {low, high}),
    do: Enum.map(values, fn value -> censored(value, low, high) end)

  defp censored(value, low, _high) when is_number(value) and is_number(low) and value < low,
    do: nil

  defp censored(value, _low, high) when is_number(value) and is_number(high) and value > high,
    do: nil

  defp censored(:nan, _low, _high), do: nil
  defp censored(value, _low, _high), do: value
end
