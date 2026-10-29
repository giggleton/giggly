defmodule Scales.Breaks do
  @moduledoc """
  Where a continuous axis's breaks go, given its limits: evenly spaced numbers, nice to read, that
  cover them (`extended/2`), round steps that cover them (`pretty/2`), or every multiple of a
  width (`fullseq/3`), moved by an offset (`width/3`), between numbers, dates, date-times or
  times of day; powers of a base and their
  multiples for a logarithmic axis (`log/2`), whole numbers for an axis of exponentials
  (`exp/2`), and whole seconds, minutes, hours, days or weeks for spans of time (`timespan/2`).
  The breaks may fall outside the limits; which to keep is the caller's.
  """

  # The extended Wilkinson algorithm of Talbot, Lin and Hanrahan (2010), as R's
  # `labeling::extended()` implements it and `scales::breaks_extended()` calls it, with five
  # breaks wanted unless a caller asks for another number, five being ggplot2's default for a
  # continuous axis.
  #
  # It searches for the evenly spaced sequence that scores best on four counts, weighted 0.25,
  # 0.2, 0.5 and 0.05 unless a caller gives other weights: simplicity (a step from the nice
  # numbers times a power of ten, early in their list, and zero among the breaks), coverage (the
  # sequence spans the range without overshooting it far), density (close to the number of breaks
  # wanted) and legibility (which `labeling` scores as 1 for every sequence). The nice numbers are
  # `labeling`'s, 1, 5, 2, 2.5, 4 and 3, unless a caller gives others, as
  # `scales::breaks_timespan()` gives 1, 2, 1.5, 4 and 3. The breaks may fall outside the range;
  # the caller decides what to keep. A sequence wins only by scoring above -2, where `labeling`
  # starts, and, where the caller asks for breaks that reach the limits, only by reaching both;
  # where none does, which only weights other than the defaults bring about, R fails, and so does
  # this.
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

  alias Scales.{Bounds, DateBreaks, Palette, Transform}

  # The number of breaks wanted unless a caller says: `scales::breaks_extended()`'s `n`.
  @wanted 5

  # `labeling::extended()`'s defaults: the nice numbers, in order of preference, and the weights of
  # simplicity, coverage, density and legibility.
  @nice_numbers [1, 5, 2, 2.5, 4, 3]
  @weights [0.25, 0.2, 0.5, 0.05]

  # The score `labeling` starts its search from: a sequence must beat it to be chosen.
  @starting_score -2

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
                      ],
                      only_loose: [
                        type: :boolean,
                        default: false,
                        doc:
                          "Whether the breaks must reach the limits, the first at or below the " <>
                            "low one and the last at or above the high one, " <>
                            "`labeling::extended()`'s `only.loose`."
                      ],
                      weights: [
                        type: {:custom, __MODULE__, :validate_weights, []},
                        default: @weights,
                        doc:
                          "The weights of simplicity, coverage, density and legibility, four " <>
                            "numbers, the first three positive, `labeling::extended()`'s `w`."
                      ]
                    )

  @log_options NimbleOptions.new!(
                 n: [
                   type: :pos_integer,
                   default: @wanted,
                   doc:
                     "The number of breaks wanted, R's `n`: a step is enough when it leaves " <>
                       "that many less two inside the limits."
                 ],
                 base: [
                   type: {:custom, __MODULE__, :validate_base, []},
                   default: 10,
                   doc: "The logarithm's base, a number above 1, R's `base`."
                 ]
               )

  # `scales::breaks_timespan()`'s nice numbers, in order of preference, and the seconds in each
  # unit a span of time may be counted in.
  @timespan_nice_numbers [1, 2, 1.5, 4, 3]
  @unit_seconds %{second: 1, minute: 60, hour: 3600, day: 86_400, week: 604_800}

  @timespan_options NimbleOptions.new!(
                      unit: [
                        type: {:in, Map.keys(@unit_seconds)},
                        default: :second,
                        doc:
                          "The unit the limits are counted in, one of `:second`, `:minute`, " <>
                            "`:hour`, `:day` and `:week`, R's `unit`; the breaks are seconds."
                      ],
                      n: [
                        type: {:custom, __MODULE__, :validate_wanted, []},
                        default: @wanted,
                        doc: "The number of breaks wanted, 2 or more, R's `n`."
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

  @pretty_options NimbleOptions.new!(
                    n: [
                      type: :non_neg_integer,
                      default: @wanted,
                      doc:
                        "The number of intervals wanted, R's `n`; the breaks found may cut " <>
                          "the limits a few more or fewer times."
                    ],
                    time_zone_database: @time_zone_database_spec
                  )

  # The nice numbers, each a step's multiple of a power of ten, and the most of that power a width
  # over the intervals wanted is rounded to it from: R's own switches, found by bisecting its
  # `pretty()` at three powers of ten, since its documentation leaves them out.
  @nice_fractions [{1, 1.4}, {2, 2.8}, {5, 7}]

  # The largest limits `pretty/2` breaks, and the smallest step: beyond them its arithmetic
  # would pass the largest double or reach the subnormal ones.
  @largest_pretty 1.0e307
  @smallest_double 2.2250738585072014e-308

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
    options
    |> NimbleOptions.validate!(@extended_options)
    |> Map.new()
    |> then(fn problem -> extended_breaks(limits, problem) end)
  end

  # NimbleOptions' check of `n:`: a whole number from 2, since R's search finds no sequence for
  # one break wanted and fails, and never ends for none.
  @doc false
  @spec validate_wanted(term()) :: {:ok, pos_integer()} | {:error, String.t()}
  def validate_wanted(wanted) when is_integer(wanted) and wanted >= 2, do: {:ok, wanted}

  def validate_wanted(other),
    do: {:error, "expected a whole number of breaks, 2 or more, got: #{inspect(other)}"}

  # NimbleOptions' check of `nice_numbers:`: a list of positive numbers, at least two, since the
  # search stops only on a nice number that cannot win, and a nice number's preference is its
  # place in the list over the list's length less one, which R takes to NaN for one and fails.
  @doc false
  @spec validate_nice_numbers(term()) :: {:ok, [number(), ...]} | {:error, String.t()}
  def validate_nice_numbers([_first, _second | _rest] = numbers) do
    if Enum.all?(numbers, fn number -> is_number(number) and number > 0 end),
      do: {:ok, numbers},
      else: nice_numbers_error(numbers)
  end

  def validate_nice_numbers(numbers), do: nice_numbers_error(numbers)

  defp nice_numbers_error(numbers),
    do: {:error, "expected a list of positive numbers, at least two, got: #{inspect(numbers)}"}

  # NimbleOptions' check of `weights:`: four numbers, the first three positive, since the search
  # ends only where simplicity falls with the skip, coverage with the power and density with the
  # count, and R's never ends where one of them is weighted 0.
  @doc false
  @spec validate_weights(term()) :: {:ok, [number()]} | {:error, String.t()}
  def validate_weights([simplicity, coverage, density, legibility] = weights)
      when is_number(simplicity) and simplicity > 0 and is_number(coverage) and coverage > 0 and
             is_number(density) and density > 0 and is_number(legibility),
      do: {:ok, weights}

  def validate_weights(weights) do
    {:error,
     "expected four weights, of simplicity, coverage, density and legibility, the first " <>
       "three positive, got: #{inspect(weights)}"}
  end

  # NimbleOptions' check of `base:`: a number above 1, since below it a logarithm falls as its
  # value rises and R's search fails on most limits, and at 1 R gives the one break 1.
  @doc false
  @spec validate_base(term()) :: {:ok, number()} | {:error, String.t()}
  def validate_base(base) when is_number(base) and base > 1, do: {:ok, base}
  def validate_base(base), do: {:error, "expected a number above 1, got: #{inspect(base)}"}

  @doc """
  Breaks for a logarithmic axis over the limits `{low, high}`, positive numbers in either order,
  R's `breaks_log()`.

  It takes every power of `base:` from the low limit's logarithm rounded down to the high one's
  rounded up, or every second, third and so on, the widest step that leaves `n:` breaks less two
  inside the limits. Where every power leaves too few, it adds multiples of each power, one
  multiple at a time, each the whole number below the base that keeps the steps evenest on the
  logarithm (3 first for base 10), until enough fall inside, and keeps those inside with one more
  either side; and where even every whole multiple leaves too few, `extended/2`'s breaks on the
  limits, `n:` wanted. A base of 2 or less adds no multiples: its powers are the breaks, however
  few fall inside. Limits whose logarithms lie between the same two whole numbers but round to
  one give that power alone.

  ## Options

  #{NimbleOptions.docs(@log_options)}

  ## Examples

      iex> Scales.Breaks.log({1.0, 1.0e5})
      [1.0, 100.0, 1.0e4]

      iex> Scales.Breaks.log({2000.0, 9000.0})
      [2000.0, 3000.0, 5000.0, 7000.0, 10000.0]

      iex> Scales.Breaks.log({3.0, 5.0}, base: 2)
      [2.0, 4.0, 8.0]
  """
  @spec log({number(), number()}, keyword()) :: [float()]
  def log(limits, options \\ []) do
    %{n: wanted, base: base} =
      options
      |> NimbleOptions.validate!(@log_options)
      |> Map.new()

    log_breaks(limits, wanted, base)
  end

  @doc """
  Breaks for an axis of exponentials over the limits `{low, high}`, in either order, R's
  `breaks_exp()`.

  Each limit below 0 is taken as 0. Where the high limit reaches 3 and the limits are 3 or more
  apart, the breaks are the high limit rounded down and the whole numbers below it, `n:` less one
  of them at most, then 0, in that order, high to low, as R gives them; otherwise they are
  `extended/2`'s breaks on the limits, which every option here reaches.

  ## Options

  #{NimbleOptions.docs(@extended_options)}

  ## Examples

      iex> Scales.Breaks.exp({0.0, 100.0}, n: 4)
      [100.0, 99.0, 98.0, 0.0]

      iex> Scales.Breaks.exp({100.0, 102.0})
      [100.0, 100.5, 101.0, 101.5, 102.0]
  """
  @spec exp({number(), number()}, keyword()) :: [float()]
  def exp({low, high}, options \\ []) when is_number(low) and is_number(high) do
    validated =
      options
      |> NimbleOptions.validate!(@extended_options)
      |> Map.new()

    [low, high] = Enum.sort([max(low / 1, 0.0), max(high / 1, 0.0)])
    top = Float.floor(high)

    # Limits 3 apart from 0 or above take `top` to 3 or more, which R checks as well.
    if high - low >= 3 do
      count = min(trunc(top), validated.n - 1)

      1..count
      |> Enum.map(fn below -> top - below + 1 end)
      |> Enum.concat([0.0])
    else
      extended_breaks({low, high}, validated)
    end
  end

  @doc """
  Breaks for an axis of spans of time over the limits `{low, high}`, in either order, counted in
  `unit:`, in seconds, R's `breaks_timespan()`.

  The limits are measured in the unit that suits their span: seconds over two minutes or less,
  minutes over two hours or less, hours over two days or less, days over two weeks or less, else
  weeks; there they take `extended/2`'s breaks with the nice numbers 1, 2, 1.5, 4 and 3, `n:`
  wanted, which are then measured in seconds, so they fall on whole seconds, minutes, hours, days
  or weeks. R gives them as a `difftime` of seconds; here they are numbers.

  ## Options

  #{NimbleOptions.docs(@timespan_options)}

  ## Examples

      iex> Scales.Breaks.timespan({0.0, 100.0}, unit: :minute)
      [0.0, 1200.0, 2400.0, 3600.0, 4800.0, 6000.0]

      iex> Scales.Breaks.timespan({0.0, 100.0}, n: 3)
      [0.0, 100.0]
  """
  @spec timespan({number(), number()}, keyword()) :: [float()]
  def timespan({low, high}, options \\ []) when is_number(low) and is_number(high) do
    %{unit: unit, n: wanted} =
      options
      |> NimbleOptions.validate!(@timespan_options)
      |> Map.new()

    seconds = Map.fetch!(@unit_seconds, unit)
    [low, high] = Enum.sort([low / 1 * seconds, high / 1 * seconds])
    scale = timespan_scale(high - low)

    {low / scale, high / scale}
    |> extended(n: wanted, nice_numbers: @timespan_nice_numbers)
    |> Enum.map(fn break -> break * scale end)
  end

  # The seconds in the unit a span of `span` seconds is broken in.
  defp timespan_scale(span) when span <= 2 * 60, do: 1
  defp timespan_scale(span) when span <= 2 * 3600, do: 60
  defp timespan_scale(span) when span <= 2 * 86_400, do: 3600
  defp timespan_scale(span) when span <= 2 * 604_800, do: 86_400
  defp timespan_scale(_span), do: 604_800

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

  @doc """
  About `n:` intervals of round values covering the limits `{low, high}`, in either order, R's
  `breaks_pretty()`, its `pretty()`.

  On numbers each step is 1, 2, 5 or 10 times a power of ten: the limits' width over the number
  wanted, rounded to the nearest of those, and the breaks every multiple of it from the low limit
  rounded down to one to the high limit rounded up. On dates and date-times they are R's calendar
  and clock steps, from a second to a thousand years, the one that cuts the limits closest to
  `n:` times, a `DateTime` broken on its zone's clock, read by `time_zone_database:`; on times of
  day the numbers' breaks on their seconds since midnight, as R breaks an `hms`, each a `Time`,
  wrapped past midnight. Limits that are one value, as R's `zero_range()` judges them, give the
  first alone.

  R's documentation describes its numbers' steps but for the rule that rounds the width over the
  number wanted, which it leaves out; this rounds it to the nearest nice number as Heckbert's
  nice numbers do (Graphics Gems, 1990), but up from R's own switches, measured from its output:
  above 1.4, 2.8 and 7 times its power of ten.

  ## Options

  #{NimbleOptions.docs(@pretty_options)}

  ## Examples

      iex> Scales.Breaks.pretty({1.0, 15.0})
      [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0]

      iex> Scales.Breaks.pretty({1.0, 20.0}, n: 2)
      [0.0, 10.0, 20.0]

      iex> Scales.Breaks.pretty({~D[2020-01-01], ~D[2022-01-01]})
      [~D[2020-01-01], ~D[2020-07-01], ~D[2021-01-01], ~D[2021-07-01], ~D[2022-01-01]]

      iex> Scales.Breaks.pretty({~T[00:00:00], ~T[01:00:00]})
      [~T[00:00:00], ~T[00:16:40], ~T[00:33:20], ~T[00:50:00], ~T[01:06:40]]
  """
  @spec pretty({value(), value()}, keyword()) :: [value()]
  def pretty(limits, options \\ []) do
    validated = NimbleOptions.validate!(options, @pretty_options)
    pretty_breaks(limits, validated)
  end

  defp pretty_breaks({low, high} = limits, options) when is_number(low) and is_number(high) do
    if abs(low) > @largest_pretty or abs(high) > @largest_pretty do
      raise ArgumentError,
            "expected limits no larger than #{@largest_pretty}, beyond which the breaks " <>
              "would pass the largest float, got: #{inspect(limits)}"
    end

    if Bounds.zero_range?(limits),
      do: [low / 1],
      else: nice_breaks(Enum.min_max([low / 1, high / 1]), Keyword.fetch!(options, :n))
  end

  defp pretty_breaks({first, _last} = limits, options) do
    name = transformation(limits, options)
    wanted = Keyword.fetch!(options, :n)

    positions =
      name
      |> Transform.transform(Tuple.to_list(limits))
      |> Enum.min_max()

    cond do
      Bounds.zero_range?(positions) -> [first]
      name == :time -> Transform.inverse(:time, nice_breaks(positions, wanted))
      true -> Transform.inverse(name, Transform.breaks(name, positions, n: wanted))
    end
  end

  # The multiples of the nice step nearest the width over the intervals wanted, one wanted for
  # none, as R takes it, from the low limit rounded down to one to the high limit rounded up,
  # spread from the first to the last as R's `seq()` spreads them, the multiple zero exactly 0.
  defp nice_breaks({low, high} = limits, wanted) do
    cell = (high - low) / max(wanted, 1)

    if cell < @smallest_double do
      raise ArgumentError,
            "expected limits at least the smallest normal float apart for each interval " <>
              "wanted, got: #{inspect(limits)} and #{wanted} wanted"
    end

    power = :math.pow(10.0, Float.floor(:math.log10(cell)))
    step = nice_fraction(cell / power) * power
    first = multiple_below(low, step)
    last = multiple_above(high, step)

    {first * step, last * step}
    |> Palette.spread(last - first + 1)
    |> Enum.zip_with(first..last//1, fn break, multiple ->
      if multiple == 0, do: 0.0, else: break
    end)
  end

  # The multiple of `step` at or below `value`, and at or above it, judged by the multiple itself,
  # since the quotient's rounding can put a value on a multiple a hair to its other side.
  defp multiple_below(value, step) do
    multiple = trunc(Float.floor(value / step))

    cond do
      (multiple + 1) * step <= value -> multiple + 1
      multiple * step > value -> multiple - 1
      true -> multiple
    end
  end

  defp multiple_above(value, step) do
    multiple = trunc(Float.ceil(value / step))

    cond do
      (multiple - 1) * step >= value -> multiple - 1
      multiple * step < value -> multiple + 1
      true -> multiple
    end
  end

  defp nice_fraction(fraction) do
    Enum.find_value(@nice_fractions, 10, fn {nice, most} -> if fraction <= most, do: nice end)
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
    |> DateBreaks.offset(offset)
    |> NaiveDateTime.to_date()
  end

  defp moved(%Time{} = time, offset, :time) do
    seconds =
      Enum.sum_by(offset, fn {unit, count} -> count * Map.fetch!(@clock_seconds, unit) end)

    Time.add(time, seconds, :second)
  end

  defp moved(datetime, offset, {:datetime, :naive, _database}),
    do: DateBreaks.offset(datetime, offset)

  defp moved(datetime, offset, {:datetime, _zone, database}),
    do: DateBreaks.offset(datetime, offset, database)

  # R's `breaks_log()` on positive limits: the powers that leave enough inside, else
  # `log_sub_breaks()`'s multiples of them. R's own check is that both limits are finite; on one of
  # 0 or below it fails.
  defp log_breaks({low, high}, wanted, base)
       when is_number(low) and low > 0 and is_number(high) and high > 0 do
    [low, high] = Enum.sort([low, high])
    range = {logarithm(low, base), logarithm(high, base)}
    {log_low, log_high} = range
    exponents = {Float.floor(log_low), Float.ceil(log_high)}

    case exponents do
      {first, first} ->
        [power(base, first)]

      {first, last} ->
        every_power(exponents, floor((last - first) / wanted) + 1, {range, wanted, base})
    end
  end

  defp log_breaks(limits, _wanted, _base) do
    raise ArgumentError,
          "expected limits of two positive numbers, as a logarithm takes, got: #{inspect(limits)}"
  end

  # Every `step`th power over the exponents, or a smaller step's, while it leaves too few inside
  # the limits; with a step of one too few, the multiples in between.
  defp every_power({first, last} = exponents, step, {range, wanted, base} = problem) do
    breaks = powers(first, last, step, base)

    cond do
      inside_count(breaks, range, base) >= wanted - 2 -> breaks
      step > 1 -> every_power(exponents, step - 1, problem)
      true -> sub_breaks(exponents, problem)
    end
  end

  # R's `base^seq(first, last, by = step)`, whole numbers apart.
  defp powers(first, last, step, base) do
    count = trunc((last - first) / step)
    Enum.map(0..count, fn index -> power(base, first + index * step) end)
  end

  # R's `log_sub_breaks()`: for a base of 2 or less every power; else multiples added to each
  # power, one at a time, until enough fall inside the limits, sorted and those inside kept with
  # one more either side; or, failing that, extended breaks on the limits.
  defp sub_breaks({first, last}, {_range, _wanted, base}) when base <= 2,
    do: powers(first, last, 1, base)

  defp sub_breaks(exponents, {range, wanted, base} = problem) do
    {log_low, log_high} = range

    # The whole numbers from 2 below the base, as R's `seq_len(base)` counts to it rounded down.
    candidates = Enum.filter(2..trunc(base)//1, fn candidate -> candidate < base end)

    case add_multiples([1], candidates, exponents, problem) do
      {:enough, breaks} ->
        breaks
        |> Enum.sort()
        |> trimmed(range, base)

      :too_few ->
        extended({power(base, log_low), power(base, log_high)}, n: wanted)
    end
  end

  defp add_multiples(_steps, [], _exponents, _problem), do: :too_few

  defp add_multiples(steps, candidates, {first, last} = exponents, problem) do
    {range, wanted, base} = problem
    best = Enum.max_by(candidates, fn candidate -> evenness([candidate | steps], base) end)
    added = Enum.concat(steps, [best])
    every = powers(first, last, 1, base)
    breaks = for multiple <- added, power <- every, do: power * multiple

    if inside_count(breaks, range, base) >= wanted - 2,
      do: {:enough, breaks},
      else: add_multiples(added, List.delete(candidates, best), exponents, problem)
  end

  # The smallest gap on the logarithm between the multiples and the base, R's `delta()`.
  defp evenness(multiples, base) do
    [base | multiples]
    |> Enum.sort()
    |> Enum.map(fn multiple -> logarithm(multiple, base) end)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [lower, upper] -> upper - lower end)
    |> Enum.min()
  end

  # The sorted breaks inside the limits, with one more either side where there is one: a slice
  # stops at the list's end, so only its start needs bounding.
  defp trimmed(breaks, {log_low, log_high}, base) do
    low = power(base, log_low)
    high = power(base, log_high)
    first = Enum.find_index(breaks, fn break -> low <= break end)

    last =
      breaks
      |> Enum.reverse()
      |> Enum.find_index(fn break -> break <= high end)
      |> then(fn from_end -> length(breaks) - 1 - from_end end)

    Enum.slice(breaks, max(first - 1, 0)..(last + 1))
  end

  defp inside_count(breaks, {log_low, log_high}, base) do
    low = power(base, log_low)
    high = power(base, log_high)
    Enum.count(breaks, fn break -> low <= break and break <= high end)
  end

  # R's `log(x, base)`: base 10's and base 2's own functions, else the ratio of natural logarithms.
  defp logarithm(value, base) when base == 10, do: :math.log10(value)
  defp logarithm(value, base) when base == 2, do: :math.log2(value)
  defp logarithm(value, base), do: :math.log(value) / :math.log(base)

  defp power(base, exponent), do: :math.pow(base / 1, exponent)

  # On an ordinary range a nice number of nice steps, and on the degenerate ranges what the
  # opening comment describes.
  defp extended_breaks({low, high}, %{n: wanted})
       when high - low < @epsilon or high - low > @widest_searched,
       do: spaced_evenly(low, high, wanted)

  defp extended_breaks(range, options) do
    %{nice_numbers: nice_numbers, weights: weights} = options
    preferred = preferences(nice_numbers)
    problem = Map.merge(options, %{range: range, weights: List.to_tuple(weights)})

    case search(problem, 1, preferred, %{score: @starting_score}) do
      %{first: first, last: last, step: step} ->
        sequence(first, last, step)

      _none ->
        raise ArgumentError,
              "no sequence of breaks over #{inspect(range)} scores above #{@starting_score}, " <>
                "where labeling::extended() starts, under the weights #{inspect(weights)}"
    end
  end

  # The outer loop, over `j`, the number of steps a nice number is skipped by: it stops when no
  # nice number at this `j` could beat the best sequence so far even with perfect coverage and
  # density.
  # The search runs over `problem`: the range, the number of breaks wanted (`n`), the weights and
  # whether the breaks must reach the limits.
  defp search(problem, skip, preferred, best) do
    case search_nice_numbers(problem, skip, preferred, best) do
      {:halt, best} -> best
      {:cont, best} -> search(problem, skip + 1, preferred, best)
    end
  end

  defp search_nice_numbers(_problem, _skip, [], best), do: {:cont, best}

  defp search_nice_numbers(problem, skip, [nice | rest], %{score: best_score} = best) do
    simplicity_bound = simplicity_max(nice, skip)

    if bound(problem, simplicity_bound, 1, 1) < best_score do
      {:halt, best}
    else
      best = search_counts(problem, skip, nice, simplicity_bound, 2, best)
      search_nice_numbers(problem, skip, rest, best)
    end
  end

  # Over `k`, the number of breaks, until no count this large could win on density.
  defp search_counts(problem, skip, nice, simplicity_bound, count, best) do
    %{range: {low, high}, n: wanted} = problem
    %{score: best_score} = best
    density_bound = density_max(count, wanted)

    if bound(problem, simplicity_bound, 1, density_bound) < best_score do
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
  defp search_powers(%{range: range} = problem, candidate, power, best) do
    {skip, {number, _preference}, simplicity_bound, count, density_bound} = candidate
    %{score: best_score} = best
    step = skip * number * :math.pow(10, power)
    coverage_bound = coverage_max(range, step * (count - 1))

    if bound(problem, simplicity_bound, coverage_bound, density_bound) < best_score do
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

  defp consider(problem, candidate, step, start, best) do
    %{range: range, n: wanted, weights: weights} = problem
    {simplicity_weight, coverage_weight, density_weight, legibility_weight} = weights
    {skip, nice, _simplicity_bound, count, _density_bound} = candidate
    %{score: best_score} = best
    first = start * (step / skip)
    last = first + step * (count - 1)

    score =
      simplicity_weight * simplicity(nice, skip, first, last, step) +
        coverage_weight * coverage(range, first, last) +
        density_weight * density(count, wanted, range, first, last) +
        legibility_weight * @legibility

    if score > best_score and reaches?(problem, first, last),
      do: %{score: score, first: first, last: last, step: step},
      else: best
  end

  # Whether a sequence may win: any may, unless the breaks must reach the limits.
  defp reaches?(%{only_loose: false}, _first, _last), do: true
  defp reaches?(%{range: {low, high}}, first, last), do: first <= low and last >= high

  defp bound(%{weights: weights}, simplicity, coverage, density) do
    {simplicity_weight, coverage_weight, density_weight, legibility_weight} = weights

    simplicity_weight * simplicity + coverage_weight * coverage + density_weight * density +
      legibility_weight
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
    1 - 0.5 * (square(high - last) + square(low - first)) / square(0.1 * range)
  rescue
    ArithmeticError -> @minus_infinity
  end

  defp coverage_max({low, high}, span) do
    range = high - low

    if span > range do
      half = (span - range) / 2
      1 - 0.5 * (square(half) + square(half)) / square(0.1 * range)
    else
      1
    end
  rescue
    ArithmeticError -> @minus_infinity
  end

  # A number times itself, as R squares one, rounded once; `** 2`, through `:math.pow/2`, can land
  # a bit away, which turns a tie between two sequences' scores.
  defp square(number), do: number * number

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
