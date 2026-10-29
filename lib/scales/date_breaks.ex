defmodule Scales.DateBreaks do
  @moduledoc false

  # A date or date-time axis's breaks: R's `pretty()` for dates and date-times (grDevices'
  # `prettyDate()`), which ggplot2's date and date-time scales take through
  # `scales::breaks_pretty()`, about five breaks on calendar or clock boundaries and the format
  # their labels are written in, used through `Scales.Transform`; a break every step of a width a
  # plot gives (`width/2`, `datetime_width/3`), as R's `breaks_width()` lays them; and a break moved
  # by an offset (`offset/3`), as R's `offset_by()` moves it, for `Scales.Breaks.width/3`.
  #
  # A date extent is in days since 1970-01-01, as R stores a date, and is worked in seconds, as R
  # turns a date into a time at midnight GMT; a date-time extent is in seconds since 1970-01-01
  # 00:00 UTC. Breaks are laid on a clock (`t:clock/0`): UTC's, which a date's and a naive
  # date-time's are too, or a time zone's, read by a time zone database. An extent
  # of dates of five days or less is every day it touches, widened by as many days as five less
  # its length, rounded half to even, labelled `"%b %d"`; an extent of date-times under a second is
  # widened to whole seconds two and a half seconds beyond each end. Otherwise the step, from a
  # second to a thousand years, that cuts it closest to five times lays breaks from its start
  # truncated to the step's unit (a minute, an hour, a day, a week starting on Monday, a month, a
  # year, a decade, a century) to the first at or past its end, keeping the last before the
  # extent and the first after it; the next coarser step is taken instead when the chosen one
  # cuts the extent more than five times and the coarser one's breaks come closer to five. Each
  # step names its labels' format: `"%S"` for seconds up to 15,
  # `"%H:%M:%S"` for 30, `"%H:%M"` for minutes and for one and three hours, `"%b %d %H:%M"` for six
  # and twelve, `"%b %d"` for days, weeks and half months (the 1st and 15th), `"%b"` for months
  # within a year and `"%b %Y"` beyond, `"%Y-%m"` for six months, and `"%Y"` for years. R writes
  # one and three hours `"%b %d %H:%M"` beyond a day, which neither step is taken for (none past
  # 18 hours on 20,000 random extents of 3 to 48), so that is left out. Seconds, minutes, hours
  # and weeks step by elapsed time and days, months and years on the calendar, as R's `seq()`
  # steps them, so across a change of a zone's offset hourly breaks keep their spacing and daily
  # ones their midnight.
  #
  # A time is truncated on the clock's wall, as R's `trunc_POSIXt()` truncates it. To a minute or
  # an hour, the start keeps the time's own offset from UTC, as R keeps its daylight-saving flag,
  # so an hour truncated in a repeated hour stays in the same pass of it. To a day or longer, the
  # start is the instant its wall-clock time names (`instant/2`), as R reads it again: a time a
  # change skips is read at the offset before the change, so a skipped midnight names the moment
  # the change ends, and a time a change repeats names the earlier of its two instants, where R's
  # choice depends on the offset its last conversion used (design-log §4, the entry beginning "A
  # local time a change of offset skips or repeats"). A calendar step advances the start's
  # wall-clock time before reading each, as R's `seq()` advances its unnormalised date-time, the
  # 15th of a half month taken from the 1st's wall-clock time once read; a width advances the
  # wall-clock time of its start once read, as R's `seq()` reads a `POSIXct` start, so a month
  # whose midnight a change skips moves every later month's break to the hour it ends.
  #
  # Three of R's branches are left out, none changing a break inside the extent: where even a
  # second cuts the extent fewer than twice, R adds ticks beyond it until it does, and here its
  # breaks are kept as they are, so R's ticks inside are all here (every one of 2,000 random
  # extents of one to two seconds); where the chosen step cuts it more than five times, R trims
  # breaks beyond the extent, which changes no break inside it or its label (every one of 9,000
  # extents under a second, where alone it fires); and where the chosen step cuts it fewer than
  # five times, R tries the next finer step, which never came closer on 16,400 of R's extents,
  # 6,300 of them clustered round the spans where two neighbouring steps are equally close to
  # five, so the chosen step's breaks are kept. A date extent never reaches a step under a day.

  @epoch ~N[1970-01-01 00:00:00]

  # R's units: a minute, an hour and a day in seconds, a year of 365.25 days and a twelfth of it.
  @minute 60
  @hour 3600
  @day 86_400
  @year @day * 365.25
  @month @year / 12

  # `pretty()`'s defaults: about five intervals, and no fewer than two.
  @wanted 5
  @fewest 2

  # How far `prettyDate()` widens an extent under a second beyond each end: half of five seconds.
  @short_widening @wanted / 2

  # Each step: its length in seconds, how a sequence of it advances (by elapsed seconds, calendar
  # days, half months, months or years), the unit its first break is truncated to, and its labels'
  # format, `:month` for one that depends on whether the extent spans a year.
  @steps [
    %{seconds: 1, by: {:seconds, 1}, start: :minutes, format: "%S"},
    %{seconds: 2, by: {:seconds, 2}, start: :minutes, format: "%S"},
    %{seconds: 5, by: {:seconds, 5}, start: :minutes, format: "%S"},
    %{seconds: 10, by: {:seconds, 10}, start: :minutes, format: "%S"},
    %{seconds: 15, by: {:seconds, 15}, start: :minutes, format: "%S"},
    %{seconds: 30, by: {:seconds, 30}, start: :minutes, format: "%H:%M:%S"},
    %{seconds: 1 * @minute, by: {:seconds, 1 * @minute}, start: :minutes, format: "%H:%M"},
    %{seconds: 2 * @minute, by: {:seconds, 2 * @minute}, start: :hours, format: "%H:%M"},
    %{seconds: 5 * @minute, by: {:seconds, 5 * @minute}, start: :hours, format: "%H:%M"},
    %{seconds: 10 * @minute, by: {:seconds, 10 * @minute}, start: :hours, format: "%H:%M"},
    %{seconds: 15 * @minute, by: {:seconds, 15 * @minute}, start: :hours, format: "%H:%M"},
    %{seconds: 30 * @minute, by: {:seconds, 30 * @minute}, start: :hours, format: "%H:%M"},
    %{seconds: 1 * @hour, by: {:seconds, 1 * @hour}, start: :hours, format: "%H:%M"},
    %{seconds: 3 * @hour, by: {:seconds, 3 * @hour}, start: :days, format: "%H:%M"},
    %{seconds: 6 * @hour, by: {:seconds, 6 * @hour}, start: :days, format: "%b %d %H:%M"},
    %{seconds: 12 * @hour, by: {:seconds, 12 * @hour}, start: :days, format: "%b %d %H:%M"},
    %{seconds: 1 * @day, by: {:days, 1}, start: :days, format: "%b %d"},
    %{seconds: 2 * @day, by: {:days, 2}, start: :days, format: "%b %d"},
    %{seconds: 7 * @day, by: {:seconds, 7 * @day}, start: :weeks, format: "%b %d"},
    %{seconds: @month / 2, by: :half_month, start: :months, format: "%b %d"},
    %{seconds: 1 * @month, by: {:months, 1}, start: :months, format: :month},
    %{seconds: 3 * @month, by: {:months, 3}, start: :years, format: :month},
    %{seconds: 6 * @month, by: {:months, 6}, start: :years, format: "%Y-%m"},
    %{seconds: 1 * @year, by: {:years, 1}, start: :years, format: "%Y"},
    %{seconds: 2 * @year, by: {:years, 2}, start: :decades, format: "%Y"},
    %{seconds: 5 * @year, by: {:years, 5}, start: :decades, format: "%Y"},
    %{seconds: 10 * @year, by: {:years, 10}, start: :decades, format: "%Y"},
    %{seconds: 20 * @year, by: {:years, 20}, start: :centuries, format: "%Y"},
    %{seconds: 50 * @year, by: {:years, 50}, start: :centuries, format: "%Y"},
    %{seconds: 100 * @year, by: {:years, 100}, start: :centuries, format: "%Y"},
    %{seconds: 200 * @year, by: {:years, 200}, start: :centuries, format: "%Y"},
    %{seconds: 500 * @year, by: {:years, 500}, start: :centuries, format: "%Y"},
    %{seconds: 1000 * @year, by: {:years, 1000}, start: :centuries, format: "%Y"}
  ]

  @last_step length(@steps) - 1

  # A width's units: the most seconds each holds, which `scales`' `ceiling_date()` and
  # `ceiling_time()` add before rounding down, the unit a date or date-time is truncated to, as
  # R's `cut()` truncates it, and how a sequence of it advances.
  @most_seconds %{
    second: 1,
    minute: @minute,
    hour: @hour,
    day: @day,
    week: 7 * @day,
    month: 31 * @day,
    year: 365 * @day
  }
  @truncations %{hour: :hours, day: :days, week: :weeks, month: :months, year: :years}

  # The seconds an offset of each unit of elapsed time moves a time.
  @unit_seconds %{second: 1, minute: @minute, hour: @hour, day: @day, week: 7 * @day}

  @typedoc """
  The clock breaks are laid on: `:utc`, UTC's wall clock, which a date's and a naive date-time's
  is too, or a time zone and the time zone database that reads it.
  """
  @type clock :: :utc | {String.t(), module()}

  # The breaks of an axis showing `extent`, in days, as dates in ascending order, some of them
  # outside it, and the format their labels are written in.
  @doc false
  @spec pretty({number(), number()}) :: {[Date.t()], String.t()}
  def pretty({low, high}) do
    # R's `as.POSIXct()` of a date: its days times the seconds in a day.
    limits = {low * @day, high * @day}

    case span(limits) do
      span when span <= @wanted * @day -> every_day(limits, span)
      span -> dates(stepped(limits, span, :utc))
    end
  end

  # The breaks of an axis showing `extent`, in seconds since 1970-01-01 00:00 UTC, laid on
  # `clock`, in ascending order, some of them outside it, and the format their labels are written
  # in: each a `NaiveDateTime` on UTC's clock, or a `DateTime` in the clock's zone. An extent
  # under a second is first widened to the whole seconds two and a half seconds beyond each end,
  # as R's `prettyDate()` widens it.
  @doc false
  @spec pretty_datetime({number(), number()}, clock()) ::
          {[NaiveDateTime.t() | DateTime.t()], String.t()}
  def pretty_datetime({low, high}, clock) when high - low < 1 do
    widened = {Float.floor(low - @short_widening), Float.ceil(high + @short_widening)}
    pretty_datetime(widened, clock)
  end

  def pretty_datetime(limits, clock), do: stepped(limits, span(limits), clock)

  defp dates({times, format}), do: {Enum.map(times, &NaiveDateTime.to_date/1), format}

  # Every day the extent touches, widened by as many days as five less its length, rounded half to
  # even, half on the left and the odd day on the right, as R's short-range branch widens it.
  defp every_day({low, high}, span) do
    widening = round_half_even(@wanted - span / @day)
    left = div(widening, 2)
    right = left + rem(widening, 2)
    days = (floor_day(low) - left)..(floor_day(high) + right)//1
    {Enum.map(days, fn day -> Date.add(~D[1970-01-01], day) end), "%b %d"}
  end

  # The chosen step's breaks on the clock and their labels' format.
  defp stepped(limits, span, clock) do
    first =
      Enum.min_by(0..@last_step, fn index ->
        abs(span / Enum.at(@steps, index).seconds - @wanted)
      end)

    {chosen, instants} = choose(first, steps_of(first, limits, clock), limits, clock)
    times = Enum.map(instants, fn instant -> on_clock(instant, clock) end)
    {times, format(Enum.at(@steps, chosen), span)}
  end

  # A break every step of `step`, one of a day, a week, a month or a year and how many of it
  # (`[week: 2]`), on an axis showing `extent`, in days, as dates in ascending order, some outside
  # it: R's `breaks_width()` for dates (`fullseq()`), from the extent's start rounded down to the
  # step's unit to its end rounded up, as `scales`' `floor_date()` and `ceiling_date()` round them.
  # A day count rounds to the nearest multiple of the step's days since 1970-01-01, half to even,
  # as R's `round_any()` rounds it; a week to the Monday on or before it, a month to its 1st and a
  # year to 1 January, as R's `cut()` truncates a date, whatever the count. Rounding up adds the
  # count of a unit's most days (a day, 7, 31, 365) before rounding down, as `ceiling_date()` adds
  # them, so 1 January of a leap year rounds up to itself.
  @doc false
  @spec width([{:day | :week | :month | :year, pos_integer()}], {number(), number()}) ::
          [Date.t()]
  def width([{unit, count}], {low, high}) do
    last = rounded_down(high + count * Map.fetch!(@most_seconds, unit) / @day, unit, count)

    low
    |> rounded_down(unit, count)
    |> read_start(:utc)
    |> sequence(last, stride(unit, count), :utc)
    |> Enum.map(&date/1)
  end

  # The date the instant `instant` falls on, on UTC's clock.
  defp date(instant) do
    instant
    |> on_clock(:utc)
    |> NaiveDateTime.to_date()
  end

  defp rounded_down(day, :day, count), do: round_half_even(day / count) * count * @day

  defp rounded_down(day, unit, _count),
    do: truncated_instant(day * @day, Map.fetch!(@truncations, unit), :utc)

  # A break every step of `step`, one of a second, a minute, an hour, a day, a week, a month or a
  # year and how many of it (`[hour: 6]`), on an axis showing `extent`, in seconds since
  # 1970-01-01 00:00 UTC, laid on `clock`, in ascending order, some outside it, each a
  # `NaiveDateTime` on UTC's clock or a `DateTime` in the clock's zone: R's `breaks_width()` for
  # date-times (`fullseq()`), from the extent's start rounded down to the step to its end rounded
  # up, as `scales`' `floor_time()` and `ceiling_time()` round them. Seconds and minutes round to
  # the nearest multiple of the step since 1970-01-01 00:00 UTC, half to even, as R's
  # `round_any()` rounds them; an hour to its start, a day to its midnight, a week to the Monday
  # on or before it, a month to its 1st and a year to 1 January, on the clock, as R's `cut()`
  # truncates a time, whatever the count. Rounding up adds the step's most seconds (a week's 7
  # days, a month's 31 and a year's 365) before rounding down, as `ceiling_time()` adds them.
  # Seconds, minutes, hours, days and weeks step by elapsed time, months and years on the calendar
  # from the start's wall-clock time, as R's `seq()` steps them.
  @doc false
  @spec datetime_width(
          [{:second | :minute | :hour | :day | :week | :month | :year, pos_integer()}],
          {number(), number()},
          clock()
        ) :: [NaiveDateTime.t() | DateTime.t()]
  def datetime_width([{unit, count}], {low, high}, clock) do
    size = count * Map.fetch!(@most_seconds, unit)
    last = time_rounded_down(high + size, unit, size, clock)

    low
    |> time_rounded_down(unit, size, clock)
    |> read_start(clock)
    |> sequence(last, stride(unit, count), clock)
    |> Enum.map(fn instant -> on_clock(instant, clock) end)
  end

  defp time_rounded_down(time, unit, size, _clock) when unit in [:second, :minute],
    do: round_half_even(time / size) * size

  defp time_rounded_down(time, unit, _size, clock),
    do: truncated_instant(time, Map.fetch!(@truncations, unit), clock)

  # The date-time `time` moved by each step of `offset` in turn (`[hour: 1, month: 1]`), as R's
  # `offset_by()` moves a `POSIXct` by each of a vector of offsets, a step `seq()`'s second value
  # from it: seconds, minutes, hours, days and weeks by elapsed time; months and years on its
  # wall-clock time, a day past the month's end carried into the next, as R normalises one (31
  # January and a month is 3 March), and read again on the clock (`instant/2`), a time a change
  # skips at the offset before it and one it repeats as the earlier. A `NaiveDateTime` is on UTC's
  # clock, a `DateTime` on its zone's.
  @doc false
  @spec offset(NaiveDateTime.t() | DateTime.t(), keyword(integer()), clock()) ::
          NaiveDateTime.t() | DateTime.t()
  def offset(time, offset, clock) do
    Enum.reduce(offset, time, fn {unit, count}, moved -> offset_by(moved, unit, count, clock) end)
  end

  defp offset_by(%NaiveDateTime{} = time, unit, count, _clock) when unit in [:month, :year],
    do: months_on(time, months(unit, count))

  defp offset_by(%DateTime{} = time, unit, count, clock) when unit in [:month, :year] do
    time
    |> DateTime.to_naive()
    |> months_on(months(unit, count))
    |> instant(clock)
    |> on_clock(clock)
  end

  defp offset_by(%NaiveDateTime{} = time, unit, count, _clock),
    do: NaiveDateTime.add(time, count * Map.fetch!(@unit_seconds, unit), :second)

  defp offset_by(%DateTime{} = time, unit, count, {_zone, database}),
    do: DateTime.add(time, count * Map.fetch!(@unit_seconds, unit), :second, database)

  defp months(:month, count), do: count
  defp months(:year, count), do: 12 * count

  # The wall-clock time `months` months on, its day counted on from the new month's 1st.
  defp months_on(wall, months) do
    index = wall.year * 12 + wall.month - 1 + months

    first = %{
      wall
      | year: Integer.floor_div(index, 12),
        month: Integer.mod(index, 12) + 1,
        day: 1
    }

    NaiveDateTime.add(first, (wall.day - 1) * @day, :second)
  end

  # A width's start: its instant and the wall-clock time it reads on the clock, which a calendar
  # step advances, as R's `seq()` advances a `POSIXct` start.
  defp read_start(instant, clock), do: {wall(instant, clock), instant}

  defp stride(:second, count), do: {:seconds, count}
  defp stride(:minute, count), do: {:seconds, count * @minute}
  defp stride(:hour, count), do: {:seconds, count * @hour}
  defp stride(:day, count), do: {:seconds, count * @day}
  defp stride(:week, count), do: {:seconds, count * 7 * @day}
  defp stride(:month, count), do: {:months, count}
  defp stride(:year, count), do: {:years, count}

  # The step's breaks, or, where they cut the extent more than five times, the next coarser
  # step's when they come closer to five intervals, as R's do.
  defp choose(index, breaks, limits, clock) do
    excess = intervals(breaks) - @wanted
    coarser = min(index + 1, @last_step)

    with true <- excess > 0,
         coarser_breaks = steps_of(coarser, limits, clock),
         true <- closer?(intervals(coarser_breaks), excess) do
      {coarser, coarser_breaks}
    else
      false -> {index, breaks}
    end
  end

  # Whether a count of intervals is closer to five than an excess of `excess` is; one with fewer
  # than two never is, as R counts it as minus infinity.
  defp closer?(count, excess), do: count >= @fewest and abs(count - @wanted) < abs(excess)

  # The step's breaks over the extent, as instants, R's `calcSteps()`: from its start truncated to
  # the step's unit to the end, keeping the last at or before the start and the first at or after
  # the end, one step more when none reaches it, advanced from the last break as read on the clock.
  defp steps_of(index, {low, high}, clock) do
    %{by: by, start: unit} = Enum.at(@steps, index)
    sequence = sequence(truncate(low, unit, clock), high, by, clock)
    reaching = Enum.count(sequence, fn instant -> instant >= high end)

    extended =
      if reaching == 0,
        do: Enum.concat(sequence, [advance(List.last(sequence), by, clock)]),
        else: sequence

    first = Enum.count(sequence, fn instant -> instant <= low end) - 1
    last = length(sequence) - reaching
    Enum.slice(extended, first..last//1)
  end

  # The step's instants from `start`, a wall-clock time and the instant it was read as, up to
  # `high`, as R's `seq()` lays them: by elapsed seconds from the instant; by calendar days,
  # months or years from the wall-clock time, each read on the clock; and half months the 1st of
  # each month, read so, and the 15th, at the 1st's wall-clock time once read.
  defp sequence({_wall, instant}, high, {:seconds, count}, _clock) do
    instant
    |> Stream.iterate(fn previous -> previous + count end)
    |> Enum.take_while(fn time -> time <= high end)
  end

  defp sequence({wall, _instant}, high, :half_month, clock) do
    wall
    |> Stream.iterate(fn first -> NaiveDateTime.shift(first, month: 1) end)
    |> Stream.flat_map(fn first -> half_months(first, clock) end)
    |> Enum.take_while(fn time -> time <= high end)
  end

  defp sequence({wall, _instant}, high, by, clock) do
    wall
    |> Stream.iterate(fn previous -> advance_wall(previous, by) end)
    |> Stream.map(fn time -> instant(time, clock) end)
    |> Enum.take_while(fn time -> time <= high end)
  end

  defp half_months(first, clock) do
    read = instant(first, clock)
    [read, instant(%{wall(read, clock) | day: 15}, clock)]
  end

  # The break a step after the instant `instant`, as R's `seq()` lays it from a `POSIXct`: elapsed
  # seconds later, or its wall-clock time on the clock advanced and read.
  defp advance(instant, {:seconds, count}, _clock), do: instant + count

  defp advance(instant, by, clock) do
    instant
    |> wall(clock)
    |> advance_wall(by)
    |> instant(clock)
  end

  defp advance_wall(time, {:days, count}), do: NaiveDateTime.add(time, count * @day, :second)
  defp advance_wall(time, {:months, count}), do: NaiveDateTime.shift(time, month: count)
  defp advance_wall(time, {:years, count}), do: NaiveDateTime.shift(time, year: count)
  defp advance_wall(%NaiveDateTime{day: 1} = time, :half_month), do: %{time | day: 15}

  defp advance_wall(%NaiveDateTime{day: 15} = time, :half_month),
    do: NaiveDateTime.shift(%{time | day: 1}, month: 1)

  # The time in seconds truncated to `unit` on the clock, as R's `trunc_POSIXt()` truncates it: its
  # wall-clock time truncated, a week starting on Monday, a decade and a century counted from year
  # 0, and the instant that names. To a minute or an hour, the instant keeps the time's own offset
  # from UTC, as R keeps its daylight-saving flag; to a day or longer, it is the instant the
  # truncated wall-clock time names (`instant/2`).
  defp truncate(time, unit, clock) do
    whole =
      time
      |> Float.floor()
      |> trunc()

    wall = wall(whole, clock)
    truncated = truncated(wall, unit)
    {truncated, start_instant({whole, wall}, truncated, unit, clock)}
  end

  defp start_instant({whole, wall}, truncated, unit, _clock) when unit in [:minutes, :hours],
    do: whole - NaiveDateTime.diff(wall, truncated, :second)

  defp start_instant(_time, truncated, _unit, clock), do: instant(truncated, clock)

  defp truncated_instant(time, unit, clock) do
    {_wall, instant} = truncate(time, unit, clock)
    instant
  end

  defp truncated(time, :minutes), do: %{time | second: 0}
  defp truncated(time, :hours), do: %{time | minute: 0, second: 0}
  defp truncated(time, :days), do: NaiveDateTime.beginning_of_day(time)

  defp truncated(time, :weeks) do
    midnight = NaiveDateTime.beginning_of_day(time)
    days_back = Date.day_of_week(midnight) - 1
    NaiveDateTime.add(midnight, -days_back * @day, :second)
  end

  defp truncated(time, :months), do: %{truncated(time, :days) | day: 1}
  defp truncated(time, :years), do: %{truncated(time, :days) | month: 1, day: 1}

  defp truncated(time, :decades),
    do: %{truncated(time, :years) | year: floor_by(time.year, 10)}

  defp truncated(time, :centuries),
    do: %{truncated(time, :years) | year: floor_by(time.year, 100)}

  defp floor_by(year, size), do: Integer.floor_div(year, size) * size

  # The instant, in seconds since 1970-01-01 00:00 UTC, a wall-clock time names on the clock, as
  # R's `mktime()` reads one with no daylight-saving flag: on UTC's clock, the one; in a zone, the
  # one it names there, a time a change of offset skips read at the offset before the change, as
  # R reads it, and a time a change repeats the earlier of its two, where R's choice depends on
  # the offset it last used.
  defp instant(wall, :utc), do: NaiveDateTime.diff(wall, @epoch, :second)

  defp instant(wall, {zone, database}) do
    case DateTime.from_naive(wall, zone, database) do
      {:ok, datetime} -> DateTime.to_unix(datetime)
      {:ambiguous, earlier, _later} -> DateTime.to_unix(earlier)
      {:gap, before, _after} -> instant(wall, :utc) - before.utc_offset - before.std_offset
    end
  end

  # The wall-clock time of the instant `instant` on the clock.
  defp wall(instant, :utc), do: NaiveDateTime.add(@epoch, instant, :second)

  defp wall(instant, clock) do
    instant
    |> on_clock(clock)
    |> DateTime.to_naive()
  end

  # The instant as a break on the clock: a `NaiveDateTime` on UTC's, a `DateTime` in a zone.
  defp on_clock(instant, :utc), do: wall(instant, :utc)

  defp on_clock(instant, {zone, database}) do
    instant
    |> DateTime.from_unix!()
    |> DateTime.shift_zone!(zone, database)
  end

  # A date's or date-time's label in `format`, as R's `format()` writes it in the C locale: English
  # month abbreviations, a day, month, hour, minute or second two digits, and a year as its number,
  # unpadded, so the year 900 is `"900"` where `Calendar.strftime/2` would write `"0900"`.
  @doc false
  @spec label(Date.t() | NaiveDateTime.t() | DateTime.t(), String.t()) :: String.t()
  def label(date, format) do
    format
    |> String.replace("%Y", Integer.to_string(date.year))
    |> then(fn unpadded -> Calendar.strftime(date, unpadded) end)
  end

  defp format(%{format: :month}, span) when span < @year, do: "%b"
  defp format(%{format: :month}, _span), do: "%b %Y"
  defp format(%{format: format}, _span), do: format

  defp intervals(breaks), do: length(breaks) - 1
  defp span({low, high}), do: high - low

  # The day a time in seconds falls on, as R's `as.Date()` of a time at GMT floors it.
  defp floor_day(time) do
    time
    |> Kernel./(@day)
    |> Float.floor()
    |> trunc()
  end

  # R's `round()`, which rounds a half to the even neighbour.
  defp round_half_even(value) do
    whole = Float.floor(value)
    fraction = value - whole

    cond do
      fraction < 0.5 -> trunc(whole)
      fraction > 0.5 -> trunc(whole) + 1
      rem(trunc(whole), 2) == 0 -> trunc(whole)
      true -> trunc(whole) + 1
    end
  end
end
