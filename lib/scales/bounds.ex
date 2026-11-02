defmodule Scales.Bounds do
  @moduledoc """
  Values against the bounds of a range: values moved from one range to another (`rescale/3`,
  `rescale_mid/4`, `rescale_max/3`, or not at all, `rescale_none/1`), whether a range is zero
  wide (`zero_range?/1`), a range widened at its ends (`expand_range/2`), and what is done with
  values outside a range, R's `oob_*` family: censored (`censor/2`, `censor_any/2`), squished
  onto its ends (`squish/2`, `squish_any/2`, `squish_infinite/2`), dropped (`discard/2`) or kept
  (`keep/2`).

  Each takes values as R holds its doubles (`t:Scales.double/0`) and gives R's answer to the last
  digit, in R's order of operations, with IEEE arithmetic's infinities and NaN where R gives them:
  over a zero-wide range, an infinite one, or an infinite value.

  A range's end is a number or an infinity; for the `oob_*` family it may also be `nil`, which
  bounds nothing on its side.
  """

  # R's `bounds.R` and `oob.R`. R's functions are vectorised, and its arithmetic gives an
  # infinity or NaN where Elixir's raises, so each value goes through `Scales.Double`.

  import Scales.Double, only: [is_bound: 1]

  alias Scales.Double

  # R's `zero_range()` tolerance: 1000 times the double-precision machine epsilon.
  @zero_range_tolerance 1000 * 2.220446049250313e-16

  # An end of the range the `oob_*` family takes: a number, an infinity, or `nil` for none on its
  # side.
  defguardp is_end(value) when is_bound(value) or is_nil(value)

  # `expand_range/2`'s options, R's `expand_range()`'s `mul`, `add` and `zero_width` and their
  # defaults. An amount for each end is R's vector of two.
  @amount_type {:or,
                [
                  :integer,
                  :float,
                  {:tuple, [{:or, [:integer, :float]}, {:or, [:integer, :float]}]}
                ]}

  @expand_range_schema NimbleOptions.new!(
                         mult: [
                           type: @amount_type,
                           default: 0,
                           doc:
                             "The multiple of the width each end moves by, a number for both " <>
                               "or `{low_end, high_end}`."
                         ],
                         add: [
                           type: @amount_type,
                           default: 0,
                           doc:
                             "The constant each end moves by besides, a number for both or " <>
                               "`{low_end, high_end}`."
                         ],
                         zero_width: [
                           type: {:or, [:integer, :float]},
                           default: 1,
                           doc: "The width a zero-wide range is widened as though it had."
                         ]
                       )

  @typedoc "A range, its low end and its high end, each a number or an infinity."
  @type range :: {bound(), bound()}

  @typedoc "An end of a range: a number, `:infinity` or `:neg_infinity`."
  @type bound :: number() | :infinity | :neg_infinity

  @typedoc "A range values outside of are found by: its ends, either `nil` for none on its side."
  @type bounds :: {bound() | nil, bound() | nil}

  @doc """
  Moves each value linearly from the range `from` to the range `to`, R's `rescale()`.

  Where either range is zero wide (`zero_range?/1`), every value is put at the middle of `to`,
  but a missing one or NaN, which is `nil`, as R gives `NA`.

  ## Examples

      iex> Scales.Bounds.rescale([2, 4, nil, 10], {2, 10}, {0, 1})
      [0.0, 0.25, nil, 1.0]

      iex> Scales.Bounds.rescale([2, 6], {2, 10}, {10, -10})
      [10.0, 0.0]

      iex> Scales.Bounds.rescale([5, 5], {5, 5}, {0.1, 1.0})
      [0.55, 0.55]

      iex> Scales.Bounds.rescale([:infinity, 1, :nan], {0, :infinity}, {0, 1})
      [:nan, 0.0, :nan]
  """
  @spec rescale([Scales.double()], range(), range()) :: [Scales.double()]
  # An end that is not a number or an infinity is refused by `zero_range?/1`, which reads both.
  def rescale(values, {from_low, from_high} = from, {to_low, to_high} = to) do
    if zero_range?(from) or zero_range?(to) do
      middled(values, to)
    else
      each_value(values, fn value ->
        value
        |> Double.subtract(from_low)
        |> Double.divide(Double.subtract(from_high, from_low))
        |> Double.multiply(Double.subtract(to_high, to_low))
        |> Double.add(to_low)
      end)
    end
  end

  @doc """
  Moves each value from the range `from` to the range `to` about `midpoint`, R's
  `rescale_mid()`: `midpoint` goes to the middle of `to`, and the end of `from` further from
  `midpoint` to the end of `to` on its side, so the nearer end falls short of its own.

  Where either range is zero wide (`zero_range?/1`), every value is put at the middle of `to`,
  but a missing one or NaN, which is `nil`, as R gives `NA`.

  ## Examples

      iex> Scales.Bounds.rescale_mid([-1, 0, 3, nil], {-1, 3}, {0, 1}, 1)
      [0.0, 0.25, 1.0, nil]

      iex> Scales.Bounds.rescale_mid([-1, 0, 3], {-1, 3}, {10, 20}, 1)
      [10.0, 12.5, 20.0]
  """
  @spec rescale_mid([Scales.double()], range(), range(), bound()) :: [Scales.double()]
  # An end that is not a number or an infinity is refused by `zero_range?/1`, which reads both.
  def rescale_mid(values, {from_low, from_high} = from, {to_low, to_high} = to, midpoint)
      when is_bound(midpoint) do
    if zero_range?(from) or zero_range?(to) do
      middled(values, to)
    else
      # R's `2 * max(abs(from - mid))` and `mean(to)`.
      high_distance =
        from_high
        |> Double.subtract(midpoint)
        |> Double.absolute()

      extent =
        from_low
        |> Double.subtract(midpoint)
        |> Double.absolute()
        |> Double.maximum(high_distance)
        |> Double.multiply(2)

      middle = Double.mean(to_low, to_high)

      each_value(values, fn value ->
        value
        |> Double.subtract(midpoint)
        |> Double.divide(extent)
        |> Double.multiply(Double.subtract(to_high, to_low))
        |> Double.add(middle)
      end)
    end
  end

  @doc """
  Each value over the high end of `from`, times the high end of `to`, R's `rescale_max()`, so 0
  stays at 0; the low ends are not read.

  Over a high end of 0, a value other than 0 is an infinity, `:infinity` or `:neg_infinity`, a
  negative zero's sign counting, and 0 is NaN, `:nan`, as is any value whose infinity is
  multiplied by a high end of `to` of 0.

  ## Examples

      iex> Scales.Bounds.rescale_max([1, 2, nil], {0, 4}, {0, 6})
      [1.5, 3.0, nil]

      iex> Scales.Bounds.rescale_max([0, 1, -1], {-2, 0}, {0, 1})
      [:nan, :infinity, :neg_infinity]
  """
  @spec rescale_max([Scales.double()], range(), range()) :: [Scales.double()]
  def rescale_max(values, {_from_low, from_high}, {_to_low, to_high})
      when is_bound(from_high) and is_bound(to_high) do
    each_value(values, fn value ->
      value
      |> Double.divide(from_high)
      |> Double.multiply(to_high)
    end)
  end

  @doc """
  Each value as it is, R's `rescale_none()`, for a caller that rescales by a function and wants
  none.

  ## Examples

      iex> Scales.Bounds.rescale_none([-1, 0.5, :infinity, nil])
      [-1, 0.5, :infinity, nil]
  """
  @spec rescale_none([Scales.double()]) :: [Scales.double()]
  def rescale_none(values) when is_list(values), do: values

  @doc """
  Whether a range is zero wide, R's `zero_range()`: its ends are equal, or so close, relative to
  the smaller, that their difference is rounding error, under 1000 times the machine epsilon. A
  range with one infinite end is not, and one with both the same infinity is.

  ## Examples

      iex> Scales.Bounds.zero_range?({3, 3})
      true

      iex> Scales.Bounds.zero_range?({1.0, 1.0000000000002218})
      true

      iex> Scales.Bounds.zero_range?({1.0, 1.000000000000222})
      false

      iex> Scales.Bounds.zero_range?({0, :infinity})
      false
  """
  @spec zero_range?(range()) :: boolean()
  def zero_range?({low, high}) when is_bound(low) and is_bound(high) and low == high, do: true

  def zero_range?({low, high}) when is_number(low) and is_number(high) do
    smaller = min(abs(low), abs(high))
    smaller != 0 and abs((low - high) / smaller) < @zero_range_tolerance
  end

  def zero_range?({low, high}) when is_bound(low) and is_bound(high), do: false

  @doc """
  The range widened at each end by a multiple of its width plus a constant, R's
  `expand_range()`: the low end moved down by `width * mult + add`, the high end up, each end
  by its own where `{low_end, high_end}` gives two. A zero-wide range (`zero_range?/1`) takes
  `zero_width` as its width, so a single value is still widened by a multiple. A range high to
  low is widened outward as R's is, its width negative, and a negative multiple or constant
  narrows it, its ends crossing past the middle.

  An end may be an infinity, with IEEE arithmetic's answer, as R's gives: an infinite width
  times 0 is NaN, so a range reaching an infinity widened by no multiple gives `:nan` at both
  ends, as R does. An end of `nil` or NaN is refused, as R fails on one; so are an infinite
  multiple, constant or width, which R takes.

  ## Options

  #{NimbleOptions.docs(@expand_range_schema)}

  ## Examples

      iex> Scales.Bounds.expand_range({1, 3}, mult: 0.05)
      {0.9, 3.1}

      iex> Scales.Bounds.expand_range({1, 3}, mult: {0.05, 0.1}, add: {0, 2})
      {0.9, 5.2}

      iex> Scales.Bounds.expand_range({5, 5}, mult: 0.05, zero_width: 10)
      {4.5, 5.5}

      iex> Scales.Bounds.expand_range({1, :infinity}, mult: 0.05)
      {:neg_infinity, :infinity}
  """
  @spec expand_range(range(), keyword()) :: {Scales.double(), Scales.double()}
  # An end that is not a number or an infinity is refused by `zero_range?/1`, which reads both.
  def expand_range({low, high} = range, options \\ []) do
    options = NimbleOptions.validate!(options, @expand_range_schema)
    {mult_low, mult_high} = each_end(options[:mult])
    {add_low, add_high} = each_end(options[:add])
    width = if zero_range?(range), do: options[:zero_width], else: Double.subtract(high, low)

    {Double.subtract(low, widening(width, mult_low, add_low)),
     Double.add(high, widening(width, mult_high, add_high))}
  end

  defp each_end({low_end, high_end}), do: {low_end, high_end}
  defp each_end(amount), do: {amount, amount}

  # R's `width * mul + add`, in R's order.
  defp widening(width, mult, add) do
    width
    |> Double.multiply(mult)
    |> Double.add(add)
  end

  @doc """
  Each value, `nil` where it is a finite number outside `{low, high}`, R's `oob_censor()`.

  Only finite numbers are censored: `:infinity`, `:neg_infinity`, `:nan` and values that are not
  numbers are kept, and `nil` stays `nil`. An end of `nil` censors nothing on its side.

  ## Examples

      iex> Scales.Bounds.censor([1, 5, 10, nil, :infinity, :nan], {2, 8})
      [nil, 5, nil, nil, :infinity, :nan]

      iex> Scales.Bounds.censor([1, 5, 10], {nil, 8})
      [1, 5, nil]
  """
  @spec censor(list(), bounds()) :: list()
  def censor(values, {low, high}) when is_end(low) and is_end(high),
    do: Enum.map(values, fn value -> censored(value, low, high, &is_number/1) end)

  @doc """
  Each value, `nil` where it is a number or an infinity outside `{low, high}`, R's
  `oob_censor_any()`: as `censor/2`, the infinities censored too.

  ## Examples

      iex> Scales.Bounds.censor_any([1, 5, :infinity, :neg_infinity, :nan, nil], {2, 8})
      [nil, 5, nil, nil, :nan, nil]
  """
  @spec censor_any(list(), bounds()) :: list()
  def censor_any(values, {low, high}) when is_end(low) and is_end(high),
    do: Enum.map(values, fn value -> censored(value, low, high, &bound?/1) end)

  @doc """
  Each value, moved onto the nearer end of `{low, high}` where it is a finite number outside it,
  R's `oob_squish()`.

  Only finite numbers are squished: `:infinity`, `:neg_infinity`, `:nan` and values that are not
  numbers are kept, and `nil` stays `nil`. An end of `nil` squishes nothing on its side. A value
  below `low` is moved up to it first and one then above `high` down to it, as R moves them, so a
  range given high to low puts every number at `high`.

  ## Examples

      iex> Scales.Bounds.squish([1, 5, 10, nil, :infinity, :nan], {2, 8})
      [2, 5, 8, nil, :infinity, :nan]

      iex> Scales.Bounds.squish([1, 5, 10], {nil, 8})
      [1, 5, 8]

      iex> Scales.Bounds.squish([1, 5, 10], {8, 2})
      [2, 2, 2]
  """
  @spec squish(list(), bounds()) :: list()
  def squish(values, {low, high}) when is_end(low) and is_end(high),
    do: Enum.map(values, fn value -> squished(value, low, high, &is_number/1) end)

  @doc """
  Each value, moved onto the nearer end of `{low, high}` where it is a number or an infinity
  outside it, R's `oob_squish_any()`: as `squish/2`, the infinities moved too.

  ## Examples

      iex> Scales.Bounds.squish_any([1, 5, :infinity, :neg_infinity, :nan], {2, 8})
      [2, 5, 8, 2, :nan]
  """
  @spec squish_any(list(), bounds()) :: list()
  def squish_any(values, {low, high}) when is_end(low) and is_end(high),
    do: Enum.map(values, fn value -> squished(value, low, high, &bound?/1) end)

  @doc """
  Each infinity replaced by an end of `{low, high}`, R's `oob_squish_infinite()`: `:neg_infinity`
  by `low` first, then `:infinity` by `high`, as R replaces them, so a `low` of `:infinity` is
  replaced in turn. A finite number is kept, inside the range or not, and an end of `nil` puts
  `nil` in an infinity's place, as R puts `NA`.

  ## Examples

      iex> Scales.Bounds.squish_infinite([:neg_infinity, 5, 10, :infinity, nil], {2, 8})
      [2, 5, 10, 8, nil]

      iex> Scales.Bounds.squish_infinite([:neg_infinity, :infinity], {:infinity, :neg_infinity})
      [:neg_infinity, :neg_infinity]
  """
  @spec squish_infinite(list(), bounds()) :: list()
  def squish_infinite(values, {low, high}) when is_end(low) and is_end(high) do
    Enum.map(values, fn value ->
      value
      |> replaced(:neg_infinity, low)
      |> replaced(:infinity, high)
    end)
  end

  @doc """
  The values inside `{low, high}`, those outside dropped, R's `oob_discard()`, so fewer may come
  back than were given.

  A number or an infinity is kept when inside the range, its ends included; `nil` is kept, NaN
  is kept as `nil`, as R gives `NA` for both, and values that are not numbers are kept. An end of
  `nil` bounds nothing on its side, where R gives `NA` for every value the other end keeps.

  ## Examples

      iex> Scales.Bounds.discard([1, 5, 8, 10, :infinity, nil, :nan], {2, 8})
      [5, 8, nil, nil]

      iex> Scales.Bounds.discard([1, 5, 10, :infinity], {2, nil})
      [5, 10, :infinity]
  """
  @spec discard(list(), bounds()) :: list()
  def discard(values, {low, high}) when is_end(low) and is_end(high) do
    Enum.flat_map(values, fn
      :nan -> [nil]
      value -> if outside?(value, low, high, &bound?/1), do: [], else: [value]
    end)
  end

  @doc """
  Every value as it is, R's `oob_keep()`, for a caller that handles values outside a range by a
  function and wants none handled.

  ## Examples

      iex> Scales.Bounds.keep([1, 5, 10, :infinity], {2, 8})
      [1, 5, 10, :infinity]
  """
  @spec keep(list(), bounds()) :: list()
  def keep(values, {low, high}) when is_list(values) and is_end(low) and is_end(high), do: values

  defp censored(value, low, high, moved?) do
    if outside?(value, low, high, moved?), do: nil, else: value
  end

  defp squished(value, low, high, moved?) do
    value
    |> raised(low, moved?)
    |> lowered(high, moved?)
  end

  defp outside?(value, low, high, moved?) do
    moved?.(value) and (below?(value, low) or below?(high, value))
  end

  defp raised(value, low, moved?) do
    if moved?.(value) and below?(value, low), do: low, else: value
  end

  defp lowered(value, high, moved?) do
    if moved?.(value) and below?(high, value), do: high, else: value
  end

  # Whether `left` is below `right`, an end of `nil` below nothing and nothing below it.
  defp below?(left, right) when is_nil(left) or is_nil(right), do: false
  defp below?(left, right), do: Double.less?(left, right)

  defp replaced(value, value, replacement), do: replacement
  defp replaced(value, _infinity, _replacement), do: value

  defp bound?(value), do: is_bound(value)

  # Every value at the middle of `to`, R's `mean(to)`, but a missing value or NaN, which is
  # `nil`, as R's `ifelse(is.na(x), NA, mean(to))` gives `NA` for both.
  defp middled(values, {to_low, to_high}) do
    middle = Double.mean(to_low, to_high)

    Enum.map(values, fn
      value when value in [nil, :nan] -> nil
      value when is_bound(value) -> middle
    end)
  end

  # Each value through `function`, a missing value and NaN kept, as R's arithmetic keeps them.
  defp each_value(values, function) do
    Enum.map(values, fn
      value when value in [nil, :nan] -> value
      value when is_bound(value) -> function.(value)
    end)
  end
end
