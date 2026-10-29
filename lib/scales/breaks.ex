defmodule Scales.Breaks do
  @moduledoc """
  Where a continuous axis's breaks go, given its limits: evenly spaced numbers, nice to read, that
  cover them (`extended/2`), or every multiple of a width (`fullseq/3`), moved by an offset
  (`width/3`), between numbers, dates, date-times or times of day. The breaks may fall outside the
  limits; which to keep is the caller's.
  """

  # The extended Wilkinson algorithm of Talbot, Lin and Hanrahan (2010), as R's
  # `labeling::extended()` implements it and `scales::breaks_extended()` calls it, with five
  # breaks wanted unless a caller asks for another number, five being ggplot2's default for a
  # continuous axis.
  #
  # It searches for the evenly spaced sequence that scores best on four counts, weighted 0.25,
  # 0.2, 0.5 and 0.05: simplicity (a step from the nice numbers times a power of ten, early in
  # their list, and zero among the breaks), coverage (the sequence spans the range without
  # overshooting it far), density (close to the number of breaks wanted) and legibility (which
  # `labeling` scores as 1 for every sequence). The nice numbers are `labeling`'s, 1, 5, 2, 2.5, 4
  # and 3, unless a caller gives others, as `scales::breaks_timespan()` gives 1, 2, 1.5, 4 and 3.
  # The breaks may fall outside the range; the caller decides what to keep.
  #
  # Three ranges are handled as R handles them. One narrower than 100 times the machine epsilon,
  # or wider than the square root of the largest float (where Elixir's arithmetic would overflow
  # rather than reach infinity), gets the number of breaks wanted spaced evenly from end to end. And
  # a best sequence whose span is within that tolerance of its ends' size, as on a narrow range of
  # large numbers, is its first break alone, as R's `seq()` returns it. Where R's scores reach
  # minus infinity and Elixir's arithmetic raises instead, a sequence whose first and last breaks
  # are one number, or a square past the largest double at the widest range searched, the score
  # is the most negative double, so the sequence never wins and a bound there stops the search.
  #
  # R computes some intermediate steps in extended precision; here every step is a double, which
  # can differ only where a sum lands within rounding error of a whole multiple of the step. Over
  # 3,505 ranges, random and degenerate, those boundaries included, it gives exactly R's breaks.
  # Its modulus is one: past 10^22 a step and its breaks are rounded, and R's long-double
  # remainder of a break through zero is that rounding, which denies it the bonus for zero that
  # the remainder in doubles, exactly 0, grants; so on ranges over about 3e23 wide reaching zero,
  # about one in six, Giggly's breaks may pass through zero where R's do not.

  alias Scales.{Bounds, DateBreaks, Transform}

  # The number of breaks wanted unless a caller says: `scales::breaks_extended()`'s `n`.
  @wanted 5

  # `labeling::extended()`'s defaults: the nice numbers, in order of preference, and the weights of
  # simplicity, coverage, density and legibility.
  @nice_numbers [1, 5, 2, 2.5, 4, 3]
  @simplicity_weight 0.25
  @coverage_weight 0.2
  @density_weight 0.5
  @legibility_weight 0.05

  # `labeling`'s legibility score, the same for every sequence.
  @legibility 1

  # `labeling`'s tolerance: 100 times the double-precision machine epsilon.
  @epsilon 100 * 2.220446049250313e-16

  # R's `sqrt(.Machine$double.xmax)`, beyond which `labeling` stops searching.
  @widest_searched 1.340_780_792_994_259_6e154

  # The most negative double, standing in for R's minus infinity, which Elixir's floats cannot
  # hold: a score R's arithmetic takes there, where Elixir's raises, never wins, and a bound there
  # stops the search, as in R.
  @minus_infinity -1.797_693_134_862_315_7e308

  @extended_options NimbleOptions.new!(
                      n: [
                        type: {:custom, __MODULE__, :validate_wanted, []},
                        default: @wanted,
                        doc:
                          "The number of breaks wanted, 2 or more, `labeling::extended()`'s " <>
                            "`m`; the breaks found may number a few more or fewer."
                      ],
                      nice_numbers: [
                        type: {:custom, __MODULE__, :validate_nice_numbers, []},
                        default: @nice_numbers,
                        doc:
                          "The steps a sequence may take, each times a power of ten, in order " <>
                            "of preference, `labeling::extended()`'s `Q`."
                      ]
                    )

  @time_zone_database_spec [
    type: :atom,
    default: Calendar.UTCOnlyTimeZoneDatabase,
    doc:
      "The time zone database that reads a `DateTime`'s zone, such as `Tz.TimeZoneDatabase`; " <>
        "Elixir's own, which knows UTC alone, when not given."
  ]

  @fullseq_options NimbleOptions.new!(
                     pad: [
                       type: :boolean,
                       default: false,
                       doc:
                         "Whether a sequence of numbers gains a step before it and one after, " <>
                           "R's `pad`; refused for dates, date-times and times."
                     ],
                     time_zone_database: @time_zone_database_spec
                   )

  @width_options NimbleOptions.new!(
                   offset: [
                     type: {:or, [:integer, :float, :keyword_list]},
                     doc:
                       "How far each break is moved: a number for numbers, 0 when not given; " <>
                         "a list of steps for dates, date-times and times, each a unit and a " <>
                         "whole count, negative to move back (`[month: 1, day: 8]`)."
                   ],
                   time_zone_database: @time_zone_database_spec
                 )

  # The units a date's step may take, and the clock's a time of day's, which a date-time's take
  # too, with the seconds each of the clock's holds.
  @date_units [:day, :week, :month, :year]
  @clock_units [:second, :minute, :hour]
  @clock_seconds %{second: 1, minute: 60, hour: 3600}

  @typedoc "A value broken: a number, or a date, date-time or time of day."
  @type value :: number() | Date.t() | NaiveDateTime.t() | DateTime.t() | Time.t()

  @typedoc """
  A step on a calendar or a clock, as `Date.shift/2` writes one: units and their counts
  (`[month: 1]`).
  """
  @type step :: keyword(integer())

  @doc """
  The breaks of the extended Wilkinson sequence that scores best over the limits `{low, high}`,
  `low` below `high`, in ascending order, R's `breaks_extended()`, `n:` breaks wanted.

  It searches for the evenly spaced sequence that scores best on simplicity (a step from the nice
  numbers times a power of ten, early in their list, and zero among the breaks), coverage (the
  sequence spans the limits without overshooting them far), density (close to the number of breaks
  wanted) and legibility, weighted as R weights them. Limits narrower than 100 times the machine
  epsilon, or wider than the square root of the largest float, get the number wanted spaced evenly
  from end to end.

  ## Options

  #{NimbleOptions.docs(@extended_options)}

  ## Examples

      iex> Scales.Breaks.extended({9.225, 35.075})
      [10.0, 15.0, 20.0, 25.0, 30.0, 35.0]

      iex> Scales.Breaks.extended({0.0, 10.0})
      [0.0, 2.5, 5.0, 7.5, 10.0]

      iex> Scales.Breaks.extended({0.0, 10.0}, nice_numbers: [1, 2, 1.5, 4, 3])
      [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]

      iex> Scales.Breaks.extended({52.0, 335.0}, n: 2)
      [0.0, 300.0]
  """
  @spec extended({float(), float()}, keyword()) :: [float()]
  def extended(limits, options \\ []) do
    %{n: wanted, nice_numbers: nice_numbers} =
      options
      |> NimbleOptions.validate!(@extended_options)
      |> Map.new()

    extended_breaks(limits, wanted, nice_numbers)
  end

  # NimbleOptions' check of `n:`: a whole number from 2, since R's search finds no sequence for
  # one break wanted and fails, and never ends for none.
  @doc false
  @spec validate_wanted(term()) :: {:ok, pos_integer()} | {:error, String.t()}
  def validate_wanted(wanted) when is_integer(wanted) and wanted >= 2, do: {:ok, wanted}

  def validate_wanted(other),
    do: {:error, "expected a whole number of breaks, 2 or more, got: #{inspect(other)}"}

  # NimbleOptions' check of `nice_numbers:`: a list of positive numbers, at least one, since the
  # search stops only on a nice number that cannot win.
  @doc false
  @spec validate_nice_numbers(term()) :: {:ok, [number(), ...]} | {:error, String.t()}
  def validate_nice_numbers([_first | _rest] = numbers) do
    if Enum.all?(numbers, fn number -> is_number(number) and number > 0 end),
      do: {:ok, numbers},
      else: nice_numbers_error(numbers)
  end

  def validate_nice_numbers(numbers), do: nice_numbers_error(numbers)

  defp nice_numbers_error(numbers),
    do: {:error, "expected a list of positive numbers, at least one, got: #{inspect(numbers)}"}

  @doc """
  Every multiple of `size` from the low limit rounded down to one to the high limit rounded up,
  R's `fullseq()`, the limits in either order.

  On numbers `size` is a positive number; limits that are one number, as R's `zero_range()` judges
  them, give that number half a `size` either side. On dates, date-times and times it is a step of
  one unit, as `Date.shift/2` writes one (`[month: 1]`), where R takes `"1 month"`, and the
  sequence is `Date`s, date-times or `Time`s laid as R lays them: from the low limit rounded down
  to the step's unit (a week to its Monday, a month to its 1st, seconds and minutes to the nearest
  multiple of the step since 1970-01-01 00:00 UTC, or since midnight for a time) to the high one
  rounded up, a date's units a day, a week, a month or a year, a time's a second, a minute or an
  hour, a date-time's any of the seven. A `DateTime` is broken on its zone's clock, read by
  `time_zone_database:`; months and years step on the calendar, the rest by elapsed time, as R's
  `seq()` steps them.

  ## Options

  #{NimbleOptions.docs(@fullseq_options)}

  ## Examples

      iex> Scales.Breaks.fullseq({1.6, 7.0}, 2)
      [0.0, 2.0, 4.0, 6.0, 8.0]

      iex> Scales.Breaks.fullseq({1.6, 7.0}, 2, pad: true)
      [-2.0, 0.0, 2.0, 4.0, 6.0, 8.0, 10.0]

      iex> Scales.Breaks.fullseq({~D[2026-01-10], ~D[2026-04-20]}, month: 1)
      [~D[2026-01-01], ~D[2026-02-01], ~D[2026-03-01], ~D[2026-04-01], ~D[2026-05-01]]
  """
  @spec fullseq({value(), value()}, number() | step(), keyword()) :: [value()]
  def fullseq(limits, size, options \\ []) do
    validated = NimbleOptions.validate!(options, @fullseq_options)
    sequenced(limits, size, validated)
  end

  @doc """
  Breaks `width` apart, R's `breaks_width()`: `fullseq/3`'s sequence over the limits, each moved
  by `offset:`.

  On numbers the offset is a number added to each. On dates, date-times and times it is a list of
  steps (`[month: 1, day: 8]`), each moving every break in turn, as R moves them by each of a
  vector of offsets: seconds, minutes, hours, days and weeks by elapsed time, months and years on
  the calendar, a day past the end of a month carried into the next, as R carries it, so 31
  January and a month is 3 March. The breaks stay in the order the offset leaves them, unsorted
  where it moves two onto one day, as R's are. A time of day wraps past midnight, where R's `hms`
  runs on past 24 hours.

  ## Options

  #{NimbleOptions.docs(@width_options)}

  ## Examples

      iex> Scales.Breaks.width({1.6, 7.0}, 1, offset: 0.5)
      [1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5]

      iex> Scales.Breaks.width({~D[2026-01-10], ~D[2026-04-20]}, [month: 1], offset: [day: 8])
      [~D[2026-01-09], ~D[2026-02-09], ~D[2026-03-09], ~D[2026-04-09], ~D[2026-05-09]]
  """
  @spec width({value(), value()}, number() | step(), keyword()) :: [value()]
  def width(limits, width, options \\ []) do
    validated = NimbleOptions.validate!(options, @width_options)

    limits
    |> sequenced(width, validated)
    |> offset(limits, validated)
  end

  defp sequenced({low, high}, size, options)
       when is_number(low) and is_number(high) and is_number(size) and size > 0 do
    [low, high] = Enum.sort([low / 1, high / 1])

    if Bounds.zero_range?({low, high}) do
      [low - size / 2, high + size / 2]
    else
      sequence =
        sequence(:math.floor(low / size) * size, :math.ceil(high / size) * size, size / 1)

      if Keyword.get(options, :pad, false), do: padded(sequence, size), else: sequence
    end
  end

  defp sequenced({_low, _high} = limits, step, options) do
    name = transformation(limits, options)
    check_step!(step, name)

    if Keyword.get(options, :pad, false) do
      raise ArgumentError,
            "pad: widens a sequence of numbers alone, as R's `fullseq()` reads it; " <>
              "got limits #{inspect(limits)}"
    end

    values = Tuple.to_list(limits)

    positions =
      name
      |> Transform.transform(values)
      |> Enum.sort()

    stepped = Transform.width(name, step, List.to_tuple(positions))
    Transform.inverse(name, stepped)
  end

  # R's `fullseq(pad = TRUE)`: a step more before the sequence and after it.
  defp padded(sequence, size) do
    Enum.concat([[hd(sequence) - size], sequence, [List.last(sequence) + size]])
  end

  # The transformation that places the limits: dates, naive date-times on UTC's clock, date-times
  # in the zone they share, read by `time_zone_database:`, or times of day.
  defp transformation({%Date{}, %Date{}}, _options), do: :date
  defp transformation({%Time{}, %Time{}}, _options), do: :time

  defp transformation({%NaiveDateTime{}, %NaiveDateTime{}}, options),
    do: {:datetime, :naive, Keyword.fetch!(options, :time_zone_database)}

  defp transformation({%DateTime{time_zone: zone}, %DateTime{time_zone: zone}}, options) do
    database = Keyword.fetch!(options, :time_zone_database)

    if zone != "Etc/UTC" and database == Calendar.UTCOnlyTimeZoneDatabase do
      raise ArgumentError,
            "date-times in #{inspect(zone)} need a time zone database that knows it; give " <>
              "one as time_zone_database:"
    end

    {:datetime, zone, database}
  end

  defp check_step!([{unit, count}], name) when is_integer(count) and count > 0 do
    unless unit in units(name), do: raise(ArgumentError, step_message([{unit, count}], name))
  end

  defp check_step!(step, name), do: raise(ArgumentError, step_message(step, name))

  defp step_message(step, name) do
    "expected a step of one unit and a positive whole count, the unit one of " <>
      "#{inspect(units(name))} for #{kind(name)}, got: #{inspect(step)}"
  end

  defp units(:date), do: @date_units
  defp units(:time), do: @clock_units
  defp units({:datetime, _zone, _database}), do: Enum.concat(@clock_units, @date_units)

  defp kind(:date), do: "dates"
  defp kind(:time), do: "times"
  defp kind({:datetime, _zone, _database}), do: "date-times"

  # Each break moved by the offset: a number added, or each of a list of steps in turn.
  defp offset(breaks, {low, _high}, options) when is_number(low) do
    case Keyword.get(options, :offset, 0) do
      offset when is_number(offset) ->
        Enum.map(breaks, fn break -> break + offset end)

      offset ->
        raise ArgumentError,
              "expected a number as the offset of breaks between numbers, got: #{inspect(offset)}"
    end
  end

  defp offset(breaks, limits, options) do
    name = transformation(limits, options)
    offset = Keyword.get(options, :offset, [])
    check_offset!(offset, name)
    Enum.map(breaks, fn break -> moved(break, offset, name) end)
  end

  defp check_offset!(offset, name) do
    valid =
      Keyword.keyword?(offset) and
        Enum.all?(offset, fn {unit, count} -> unit in units(name) and is_integer(count) end)

    unless valid do
      raise ArgumentError,
            "expected the offset of breaks between #{kind(name)} as a list of steps, each a " <>
              "unit of #{inspect(units(name))} and a whole count, got: #{inspect(offset)}"
    end
  end

  defp moved(%Date{} = date, offset, :date) do
    date
    |> NaiveDateTime.new!(~T[00:00:00])
    |> DateBreaks.offset(offset, :utc)
    |> NaiveDateTime.to_date()
  end

  defp moved(%Time{} = time, offset, :time) do
    seconds =
      Enum.sum_by(offset, fn {unit, count} -> count * Map.fetch!(@clock_seconds, unit) end)

    Time.add(time, seconds, :second)
  end

  defp moved(datetime, offset, {:datetime, :naive, _database}),
    do: DateBreaks.offset(datetime, offset, :utc)

  defp moved(datetime, offset, {:datetime, zone, database}),
    do: DateBreaks.offset(datetime, offset, {zone, database})

  # On an ordinary range a nice number of nice steps, and on the degenerate ranges what the
  # opening comment describes.
  defp extended_breaks({low, high}, wanted, _nice_numbers)
       when high - low < @epsilon or high - low > @widest_searched,
       do: spaced_evenly(low, high, wanted)

  defp extended_breaks(range, wanted, nice_numbers) do
    preferred = preferences(nice_numbers)
    best = search({range, wanted}, 1, preferred, %{score: -2})
    %{first: first, last: last, step: step} = best
    sequence(first, last, step)
  end

  # The outer loop, over `j`, the number of steps a nice number is skipped by: it stops when no
  # nice number at this `j` could beat the best sequence so far even with perfect coverage and
  # density.
  # The search runs over the range and the number of breaks wanted, `problem`.
  defp search(problem, skip, preferred, best) do
    case search_nice_numbers(problem, skip, preferred, best) do
      {:halt, best} -> best
      {:cont, best} -> search(problem, skip + 1, preferred, best)
    end
  end

  defp search_nice_numbers(_problem, _skip, [], best), do: {:cont, best}

  defp search_nice_numbers(problem, skip, [nice | rest], %{score: best_score} = best) do
    simplicity_bound = simplicity_max(nice, skip)

    if bound(simplicity_bound, 1, 1) < best_score do
      {:halt, best}
    else
      best = search_counts(problem, skip, nice, simplicity_bound, 2, best)
      search_nice_numbers(problem, skip, rest, best)
    end
  end

  # Over `k`, the number of breaks, until no count this large could win on density.
  defp search_counts(problem, skip, nice, simplicity_bound, count, best) do
    {{low, high}, wanted} = problem
    %{score: best_score} = best
    density_bound = density_max(count, wanted)

    if bound(simplicity_bound, 1, density_bound) < best_score do
      best
    else
      {number, _preference} = nice
      delta = (high - low) / (count + 1) / skip / number
      power = ceil(:math.log10(delta))
      candidate = {skip, nice, simplicity_bound, count, density_bound}
      best = search_powers(problem, candidate, power, best)
      search_counts(problem, skip, nice, simplicity_bound, count + 1, best)
    end
  end

  # Over `z`, the power of ten the nice number is scaled by, until the step overshoots the range
  # by too much to cover it well.
  defp search_powers({range, _wanted} = problem, candidate, power, best) do
    {skip, {number, _preference}, simplicity_bound, count, density_bound} = candidate
    %{score: best_score} = best
    step = skip * number * :math.pow(10, power)
    coverage_bound = coverage_max(range, step * (count - 1))

    if bound(simplicity_bound, coverage_bound, density_bound) < best_score do
      best
    else
      best =
        range
        |> starts(step, skip, count)
        |> Enum.reduce(best, fn start, best_so_far ->
          consider(problem, candidate, step, start, best_so_far)
        end)

      search_powers(problem, candidate, power + 1, best)
    end
  end

  # Where the sequence may start, counted in steps of `step / skip`, so that it can still reach the
  # range's top and start at or below its bottom.
  defp starts({low, high}, step, skip, count) do
    first = trunc(:math.floor(high / step) * skip - (count - 1) * skip)
    last = trunc(:math.ceil(low / step) * skip)
    if first > last, do: [], else: Enum.to_list(first..last//1)
  end

  defp consider({range, wanted}, candidate, step, start, best) do
    {skip, nice, _simplicity_bound, count, _density_bound} = candidate
    %{score: best_score} = best
    first = start * (step / skip)
    last = first + step * (count - 1)

    score =
      @simplicity_weight * simplicity(nice, skip, first, last, step) +
        @coverage_weight * coverage(range, first, last) +
        @density_weight * density(count, wanted, range, first, last) +
        @legibility_weight * @legibility

    if score > best_score, do: %{score: score, first: first, last: last, step: step}, else: best
  end

  defp bound(simplicity, coverage, density) do
    @simplicity_weight * simplicity + @coverage_weight * coverage + @density_weight * density +
      @legibility_weight
  end

  # `.simplicity()`: earlier nice numbers and fewer skips score higher, and a sequence through zero
  # scores 1 more.
  defp simplicity({_number, preference}, skip, first, last, step) do
    remainder = modulo(first, step)

    through_zero =
      if (remainder < @epsilon or step - remainder < @epsilon) and first <= 0 and last >= 0,
        do: 1,
        else: 0

    1 - preference - skip + through_zero
  end

  defp simplicity_max({_number, preference}, skip), do: 1 - preference - skip + 1

  # Each nice number with its place in the list, from 0 for the first to 1 for the last.
  defp preferences(nice_numbers) do
    last = length(nice_numbers) - 1
    Enum.with_index(nice_numbers, fn number, index -> {number, index / last} end)
  end

  # `.coverage()` and its bound, minus infinity where a square passes the largest double, on a
  # range as wide as `labeling` searches, as R's reaches infinity there.
  defp coverage({low, high}, first, last) do
    range = high - low
    1 - 0.5 * ((high - last) ** 2 + (low - first) ** 2) / (0.1 * range) ** 2
  rescue
    ArithmeticError -> @minus_infinity
  end

  defp coverage_max({low, high}, span) do
    range = high - low

    if span > range do
      half = (span - range) / 2
      1 - 0.5 * (half ** 2 + half ** 2) / (0.1 * range) ** 2
    else
      1
    end
  rescue
    ArithmeticError -> @minus_infinity
  end

  # `.density()`, minus infinity for a sequence whose first and last breaks are one number, its
  # step rounding error beside them, as R's division by zero gives.
  defp density(_count, _wanted, _range, first, last) when first == last, do: @minus_infinity

  defp density(count, wanted, {low, high}, first, last) do
    ratio = (count - 1) / (last - first)
    target = (wanted - 1) / (max(last, high) - min(low, first))
    2 - max(ratio / target, target / ratio)
  end

  defp density_max(count, wanted) when count >= wanted, do: 2 - (count - 1) / (wanted - 1)
  defp density_max(_count, _wanted), do: 1

  # R's `%%` on doubles: the remainder with the sign of the divisor.
  defp modulo(dividend, divisor), do: dividend - :math.floor(dividend / divisor) * divisor

  # R's `seq(from, to, by = step)`: whole steps from `first`, none past `last`; just `first` when
  # the span is within 100 epsilons of the ends' size, where R's steps would be rounding error.
  defp sequence(first, last, step) do
    if abs(last - first) / max(abs(last), abs(first)) < @epsilon do
      [first]
    else
      steps = trunc((last - first) / step + 1.0e-10)
      Enum.map(0..steps//1, fn index -> min(first + index * step, last) end)
    end
  end

  # R's `seq(from, to, length.out = wanted)`: `wanted` values from end to end, the ends exact.
  defp spaced_evenly(low, high, wanted) do
    width = (high - low) / (wanted - 1)
    inner = Enum.map(1..(wanted - 2)//1, fn index -> low + index * width end)
    Enum.concat([[low], inner, [high]])
  end
end
