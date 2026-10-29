defmodule Scales.MinorBreaks do
  @moduledoc """
  Where a continuous axis's minor breaks go: between its breaks (`regular/3`), a number of them to
  each gap (`n/3`) or every multiple of a width in each (`width/4`), and the powers of ten and
  their multiples for a logarithmic axis (`log/2`).
  """

  # R's `scales::regular_minor_breaks()`, which a transformation carries as its `minor_breaks` and
  # ggplot2 calls asking for two intervals between neighbouring breaks; and R's
  # `minor_breaks_n()`, `minor_breaks_width()` and `minor_breaks_log()`, the functions a user
  # hands a scale. The first two lay each gap in turn as R's `loop_breaks()` does: from the low
  # limit to the first break, between each pair of neighbouring breaks, and from the last break to
  # the high limit, keeping each value the first time it is laid.

  alias Scales.{Breaks, Palette}

  @regular_options NimbleOptions.new!(
                     reverse: [
                       type: :boolean,
                       default: false,
                       doc:
                         "Whether the breaks run from high to low, as a reversing " <>
                           "transformation's do, so the step added before the first break goes " <>
                           "above it and the one after the last below it."
                     ]
                   )

  # The multiples of each power R's `minor_breaks_log()` gives at its finest detail: 1 to 9, less
  # those its `setdiff()` takes out, 1 and 5, which are the powers and their fives; no other
  # multiple of one power is a power or a power's five.
  @multiples [2, 3, 4, 6, 7, 8, 9]

  @log_options NimbleOptions.new!(
                 detail: [
                   type: {:in, [:auto, 1, 5, 10]},
                   default: :auto,
                   doc:
                     "Which values to give, R's `detail`: the powers of ten (`10`), those and " <>
                       "five times each (`5`), or every whole multiple of each from 1 to 9 " <>
                       "(`1`); `:auto` chooses by the powers the limits span, `1` over 8 or " <>
                       "fewer, `5` over 15 or fewer, else `10`."
                 ],
                 smallest: [
                   type: {:custom, __MODULE__, :validate_smallest, []},
                   default: :auto,
                   doc:
                     "Where limits reach 0 or below, the smallest size of value given either " <>
                       "side of 0, R's `smallest`, a finite number from 1.0e-100; `:auto` is " <>
                       "a tenth of the largest limit's size, 0.1 at most."
                 ]
               )

  @doc """
  The minor breaks between `breaks` on an axis showing the limits `{low, high}`, R's
  `regular_minor_breaks()`: each gap between neighbouring breaks, in the order given, gets a minor
  break at its middle, the gap's start plus half its width, as R's `seq()` finds it. Where the
  limits reach past the breaks at an end, the breaks are first extended by one more step there,
  the first gap's, so minor breaks can fall between the outermost break and the edge of the axis.

  The result holds the breaks themselves and the added steps too, as R's does, and may reach past
  the limits; which to keep is the caller's. Fewer than two breaks have no gap, and so no minor
  breaks.

  ## Options

  #{NimbleOptions.docs(@regular_options)}

  ## Examples

      iex> Scales.MinorBreaks.regular([10.0, 20.0, 30.0], {5.0, 35.0})
      [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0]

      iex> Scales.MinorBreaks.regular([30.0, 20.0, 10.0], {5.0, 35.0}, reverse: true)
      [40.0, 35.0, 30.0, 25.0, 20.0, 15.0, 10.0, 5.0, 0.0]
  """
  @spec regular([float()], {float(), float()}, keyword()) :: [float()]
  def regular(breaks, limits, options \\ []) do
    %{reverse: reverse} =
      options
      |> NimbleOptions.validate!(@regular_options)
      |> Map.new()

    regular_breaks(breaks, limits, reverse)
  end

  @doc """
  `count` minor breaks to each gap, its ends included, on an axis showing the limits
  `{low, high}` with `breaks`, R's `minor_breaks_n()`: from the low limit to the first break,
  between each pair of neighbouring breaks in the order given, and from the last break to the high
  limit, each gap spread evenly as R's `seq()` spreads it (`Scales.Palette.spread/2`), a value laid
  twice kept the first time.

  The result may reach past the limits, as breaks may; which to keep is the caller's. It takes
  numbers alone: a fraction of a day is no date.

  ## Examples

      iex> Scales.MinorBreaks.n({0.5, 9.5}, [2.0, 4.0, 6.0, 8.0], 3)
      [0.5, 1.25, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 8.75, 9.5]
  """
  @spec n({number(), number()}, [number(), ...], non_neg_integer()) :: [float()]
  def n({low, high} = limits, [_first | _rest] = breaks, count)
      when is_number(low) and is_number(high) and is_integer(count) and count >= 0 do
    unless Enum.all?(breaks, fn break -> is_number(break) end) do
      raise ArgumentError, "expected breaks that are numbers, got: #{inspect(breaks)}"
    end

    looped(limits, breaks, fn {from, to} -> Palette.spread({from / 1, to / 1}, count) end)
  end

  @doc """
  Minor breaks `width` apart in each gap, on an axis showing the limits `{low, high}` with
  `breaks`, R's `minor_breaks_width()`: `Scales.Breaks.width/3`'s breaks over the low limit and the
  first break, each pair of neighbouring breaks in the order given, and the last break and the high
  limit, a value laid twice kept the first time.

  It takes what `Scales.Breaks.width/3` takes, numbers, dates, date-times or times of day, with
  `width` a number or a step of one unit, and gives the same, where R gives a date's days or a
  date-time's seconds. Its options are `Scales.Breaks.width/3`'s, `offset:` 0 or no steps unless
  given, where R has no default. The result may reach past the limits, as breaks may; which to
  keep is the caller's.

  ## Examples

      iex> Scales.MinorBreaks.width({0.5, 9.5}, [2.0, 4.0, 6.0, 8.0], 2, offset: 0.5)
      [0.5, 2.5, 4.5, 6.5, 8.5, 10.5]

      iex> Scales.MinorBreaks.width({~D[2026-01-01], ~D[2026-01-25]}, [~D[2026-01-15]], week: 1)
      [~D[2025-12-29], ~D[2026-01-05], ~D[2026-01-12], ~D[2026-01-19], ~D[2026-01-26]]
  """
  @spec width(
          {Breaks.value(), Breaks.value()},
          [Breaks.value(), ...],
          number() | Breaks.step(),
          keyword()
        ) :: [Breaks.value()]
  def width(limits, [_first | _rest] = breaks, width, options \\ []) do
    looped(limits, breaks, fn gap -> Breaks.width(gap, width, options) end)
  end

  @doc """
  Minor breaks for a logarithmic axis over the limits `{low, high}`, R's `minor_breaks_log()`: the
  powers of ten from one below the low limit's to one above the high limit's, then five times each,
  then each whole multiple from 2 to 9 of each but 5, as `detail:` asks, in that order, as R gives
  them.

  Where a limit is 0 or below, the powers run from ten times `smallest:` to the larger limit's
  size, each kept from `smallest:` up and given either side of 0, the positive first, with 0
  itself after the powers. The result may reach past the limits; which to keep is the caller's.
  Limits both 0 have no powers to span, and are refused, where R fails.

  ## Options

  #{NimbleOptions.docs(@log_options)}

  ## Examples

      iex> Scales.MinorBreaks.log({1.0, 100.0}, detail: 5)
      [0.1, 1.0, 10.0, 100.0, 1000.0, 0.5, 5.0, 50.0, 500.0, 5000.0]

      iex> Scales.MinorBreaks.log({-10.0, 10.0}, detail: 10, smallest: 1)
      [1.0, 10.0, 100.0, -1.0, -10.0, -100.0, 0.0]
  """
  @spec log({number(), number()}, keyword()) :: [float()]
  def log({low, high}, options \\ []) when is_number(low) and is_number(high) do
    %{detail: detail, smallest: smallest} =
      options
      |> NimbleOptions.validate!(@log_options)
      |> Map.new()

    log_breaks({low, high}, detail, smallest)
  end

  @doc false
  @spec validate_smallest(term()) :: {:ok, :auto | number()} | {:error, String.t()}
  def validate_smallest(:auto), do: {:ok, :auto}

  def validate_smallest(smallest) when is_number(smallest) and smallest >= 1.0e-100,
    do: {:ok, smallest}

  def validate_smallest(smallest),
    do: {:error, "expected :auto or a finite number from 1.0e-100, got: #{inspect(smallest)}"}

  defp regular_breaks([first, second | _later] = breaks, limits, reverse) do
    step = second - first

    breaks
    |> extended(step, limits, reverse)
    |> Enum.chunk_every(2, 1)
    |> Enum.flat_map(fn
      [from, to] -> [from, from + (to - from) / 2]
      [final] -> [final]
    end)
  end

  defp regular_breaks(_breaks, _limits, _reverse), do: []

  # R adds the step before the first break, then asks of the breaks as they then stand whether to
  # add one after the last.
  defp extended(breaks, step, {low, high}, false) do
    breaks
    |> step_before(step, low < Enum.min(breaks))
    |> then(fn stepped -> step_after(stepped, step, high > Enum.max(stepped)) end)
  end

  defp extended(breaks, step, {low, high}, true) do
    breaks
    |> step_before(step, high > Enum.max(breaks))
    |> then(fn stepped -> step_after(stepped, step, low < Enum.min(stepped)) end)
  end

  defp step_before([first | _rest] = breaks, step, true), do: [first - step | breaks]
  defp step_before(breaks, _step, false), do: breaks

  defp step_after(breaks, step, true), do: Enum.concat(breaks, [List.last(breaks) + step])
  defp step_after(breaks, _step, false), do: breaks

  # R's `loop_breaks()`: each gap laid by `lay`, from the low limit to the first break, between
  # neighbours, and from the last break to the high limit, a value kept the first time it comes.
  defp looped({low, high}, breaks, lay) do
    [[low | breaks], Enum.concat(breaks, [high])]
    |> Enum.zip_with(fn [from, to] -> lay.({from, to}) end)
    |> Enum.concat()
    |> Enum.uniq_by(&unique/1)
  end

  # What R's `unique()` tells apart: 0 and -0 are one number.
  defp unique(value) when is_float(value), do: value + 0.0
  defp unique(value), do: value

  # R's `minor_breaks_log()` on limits both positive, or reaching 0 or below.
  defp log_breaks({low, high}, detail, _smallest) when low > 0 and high > 0 do
    {low, high}
    |> ladder(detail)
    |> Enum.concat()
  end

  defp log_breaks({low, high} = limits, detail, smallest) do
    large = max(abs(low), abs(high))

    if large == 0 do
      raise ArgumentError,
            "expected limits that are not both 0, as a logarithmic axis spans powers, got: " <>
              inspect(limits)
    end

    small = if smallest == :auto, do: min(0.1, large * 0.1), else: smallest
    [tens, fives, ones] = ladder({small * 10, large}, detail)

    Enum.concat([mirrored(tens, small), [0.0], mirrored(fives, small), mirrored(ones, small)])
  end

  # The powers of ten over the limits, a power either side, then five times each and the other
  # whole multiples, as `detail` asks.
  defp ladder({low, high}, detail) do
    [low, high] = Enum.sort([low, high])
    first = floor(:math.log10(low)) - 1
    last = ceil(:math.log10(high)) + 1
    tens = Enum.map(first..last, fn exponent -> :math.pow(10.0, exponent) end)

    case chosen(detail, last - first) do
      10 ->
        [tens, [], []]

      5 ->
        [tens, fives(tens), []]

      1 ->
        [tens, fives(tens), for(power <- tens, multiple <- @multiples, do: multiple * power)]
    end
  end

  defp fives(tens), do: Enum.map(tens, fn power -> 5 * power end)

  # The detail R chooses where none is given, by the powers spanned.
  defp chosen(:auto, span) when span <= 8, do: 1
  defp chosen(:auto, span) when span <= 15, do: 5
  defp chosen(:auto, _span), do: 10
  defp chosen(detail, _span), do: detail

  # The values from `small` up, then each negated.
  defp mirrored(values, small) do
    kept = Enum.filter(values, fn value -> value >= small end)
    Enum.concat(kept, Enum.map(kept, fn value -> -value end))
  end
end
