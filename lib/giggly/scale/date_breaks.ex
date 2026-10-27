defmodule Giggly.Scale.DateBreaks do
  @moduledoc false

  # A date or date-time axis's breaks: R's `pretty()` for dates and date-times (grDevices'
  # `prettyDate()`), which ggplot2's date and date-time scales take through
  # `scales::breaks_pretty()`, about five breaks on calendar or clock boundaries and the format
  # their labels are written in, used through `Giggly.Scale.Transform`; and a break every step of
  # a width a plot gives (`width/2`, `datetime_width/2`), as R's `breaks_width()` lays them.
  #
  # A date extent is in days since 1970-01-01, as R stores a date, and is worked in seconds, as R
  # turns a date into a time at midnight GMT; a date-time extent is in seconds since 1970-01-01
  # 00:00, its breaks laid on the wall clock of UTC, which a naive date-time's is too. An extent
  # of dates of five days or less is every day it touches, widened by as many days as five less
  # its length, rounded half to even, labelled `"%b %d"`; an extent of date-times under a second is
  # widened to whole seconds two and a half seconds beyond each end. Otherwise the step, from a
  # second to a thousand years, that cuts it closest to five times lays breaks from its start
  # truncated to the step's unit (a minute, an hour, a day, a week starting on Monday, a month, a
  # year, a decade, a century) to the first at or past its end, keeping the last before the
  # extent and the first after it; the neighbouring step is taken instead when its breaks come
  # closer to five intervals. Each step names its labels' format: `"%S"` for seconds up to 15,
  # `"%H:%M:%S"` for 30, `"%H:%M"` for minutes and for one and three hours, `"%b %d %H:%M"` for six
  # and twelve, `"%b %d"` for days, weeks and half months (the 1st and 15th), `"%b"` for months
  # within a year and `"%b %Y"` beyond, `"%Y-%m"` for six months, and `"%Y"` for years. R writes
  # one and three hours `"%b %d %H:%M"` beyond a day, which neither step is taken for (none past
  # 18 hours on 20,000 random extents of 3 to 48), so that is left out. Seconds, minutes, hours
  # and weeks step by elapsed time and days, months and years on the calendar, as R's `seq()`
  # steps them.
  #
  # Two of R's branches are left out, neither changing a break inside the extent: where even a
  # second cuts the extent fewer than twice, R adds ticks beyond it until it does, and here its
  # breaks are kept as they are, so R's ticks inside are all here (every one of 2,000 random
  # extents of one to two seconds); and where the chosen step cuts it more than five times, R
  # trims breaks beyond the extent, which changes no break inside it or its label (every one of
  # 9,000 extents under a second, where alone it fires). Its finer step for fewer than two
  # intervals no step closest to five needs above a second, so reaching for one fails; and a date
  # extent never takes a step under a day, which fails too.

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

  # The first step of a day or more, the finest a date's breaks take.
  @day_step Enum.find_index(@steps, fn step -> step.seconds == @day end)

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

  # The breaks of an axis showing `extent`, in days, as dates in ascending order, some of them
  # outside it, and the format their labels are written in.
  @doc false
  @spec pretty({number(), number()}) :: {[Date.t()], String.t()}
  def pretty({low, high}) do
    # R's `as.POSIXct()` of a date: its days times the seconds in a day.
    limits = {low * @day, high * @day}

    case span(limits) do
      span when span <= @wanted * @day -> every_day(limits, span)
      span -> dates(stepped(limits, span))
    end
  end

  # The breaks of an axis showing `extent`, in seconds since 1970-01-01 00:00, as date-times on
  # the wall clock of UTC in ascending order, some of them outside it, and the format their labels
  # are written in. An extent under a second is first widened to the whole seconds two and a half
  # seconds beyond each end, as R's `prettyDate()` widens it.
  @doc false
  @spec pretty_datetime({number(), number()}) :: {[NaiveDateTime.t()], String.t()}
  def pretty_datetime({low, high}) when high - low < 1 do
    widened = {Float.floor(low - @short_widening), Float.ceil(high + @short_widening)}
    pretty_datetime(widened)
  end

  def pretty_datetime(limits) do
    {_chosen, times, format} = stepped(limits, span(limits))
    {times, format}
  end

  # A date's breaks are the breaks of a step of a day or more, as dates.
  defp dates({chosen, times, format}) when chosen >= @day_step,
    do: {Enum.map(times, &NaiveDateTime.to_date/1), format}

  # Every day the extent touches, widened by as many days as five less its length, rounded half to
  # even, half on the left and the odd day on the right, as R's short-range branch widens it.
  defp every_day({low, high}, span) do
    widening = round_half_even(@wanted - span / @day)
    left = div(widening, 2)
    right = left + rem(widening, 2)
    days = (floor_day(low) - left)..(floor_day(high) + right)//1
    {Enum.map(days, fn day -> Date.add(~D[1970-01-01], day) end), "%b %d"}
  end

  # The chosen step's index, its breaks and their labels' format.
  defp stepped(limits, span) do
    first =
      Enum.min_by(0..@last_step, fn index ->
        abs(span / Enum.at(@steps, index).seconds - @wanted)
      end)

    breaks = steps_of(first, limits)
    cuts_twice(first, breaks)
    {chosen, times} = choose(first, breaks, limits)
    {chosen, times, format(Enum.at(@steps, chosen), span)}
  end

  # The step closest to five intervals cuts an extent at least twice, a second's excepted, which
  # may cut a short one once; R then adds ticks beyond the extent, and its breaks are kept as they
  # are here.
  defp cuts_twice(0, _breaks), do: :ok
  defp cuts_twice(_index, [_start, _middle, _end | _rest]), do: :ok

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
    |> sequence(seconds(last), stride(unit, count))
    |> Enum.map(&NaiveDateTime.to_date/1)
  end

  defp rounded_down(day, :day, count),
    do: NaiveDateTime.add(@epoch, round_half_even(day / count) * count * @day, :second)

  defp rounded_down(day, unit, _count), do: truncate(day * @day, Map.fetch!(@truncations, unit))

  # A break every step of `step`, one of a second, a minute, an hour, a day, a week, a month or a
  # year and how many of it (`[hour: 6]`), on an axis showing `extent`, in seconds since
  # 1970-01-01 00:00, as date-times on the wall clock of UTC in ascending order, some outside it:
  # R's `breaks_width()` for date-times (`fullseq()`), from the extent's start rounded down to the
  # step to its end rounded up, as `scales`' `floor_time()` and `ceiling_time()` round them. Seconds
  # and minutes round to the nearest multiple of the step since 1970-01-01, half to even, as R's
  # `round_any()` rounds them; an hour to its start, a day to its midnight, a week to the Monday on
  # or before it, a month to its 1st and a year to 1 January, as R's `cut()` truncates a time,
  # whatever the count. Rounding up adds the step's most seconds (a week's 7 days, a month's 31
  # and a year's 365) before rounding down, as `ceiling_time()` adds them. Seconds, minutes, hours,
  # days and weeks step by elapsed time, months and years on the calendar, as R's `seq()` steps
  # them.
  @doc false
  @spec datetime_width(
          [{:second | :minute | :hour | :day | :week | :month | :year, pos_integer()}],
          {number(), number()}
        ) :: [NaiveDateTime.t()]
  def datetime_width([{unit, count}], {low, high}) do
    size = count * Map.fetch!(@most_seconds, unit)
    last = time_rounded_down(high + size, unit, size)

    low
    |> time_rounded_down(unit, size)
    |> sequence(seconds(last), stride(unit, count))
  end

  defp time_rounded_down(time, unit, size) when unit in [:second, :minute],
    do: NaiveDateTime.add(@epoch, round_half_even(time / size) * size, :second)

  defp time_rounded_down(time, unit, _size), do: truncate(time, Map.fetch!(@truncations, unit))

  defp stride(:second, count), do: {:seconds, count}
  defp stride(:minute, count), do: {:seconds, count * @minute}
  defp stride(:hour, count), do: {:seconds, count * @hour}
  defp stride(:day, count), do: {:seconds, count * @day}
  defp stride(:week, count), do: {:seconds, count * 7 * @day}
  defp stride(:month, count), do: {:months, count}
  defp stride(:year, count), do: {:years, count}

  # The step's breaks, or the neighbouring step's where they come closer to five intervals: a
  # coarser one for too many, a finer one for too few, but for the finest step, a second, which
  # keeps its own, as R's does.
  defp choose(index, breaks, limits) do
    excess = intervals(breaks) - @wanted

    case neighbour(index, excess) do
      :none ->
        {index, breaks}

      neighbour ->
        neighbour_breaks = steps_of(neighbour, limits)

        if closer?(intervals(neighbour_breaks), excess),
          do: {neighbour, neighbour_breaks},
          else: {index, breaks}
    end
  end

  defp neighbour(_index, 0), do: :none
  defp neighbour(index, excess) when excess > 0, do: min(index + 1, @last_step)
  defp neighbour(0, _excess), do: :none
  defp neighbour(index, _excess), do: index - 1

  # Whether a count of intervals is closer to five than an excess of `excess` is; one with fewer
  # than two never is, as R counts it as minus infinity.
  defp closer?(count, excess), do: count >= @fewest and abs(count - @wanted) < abs(excess)

  # The step's breaks over the extent, R's `calcSteps()`: from its start truncated to the step's
  # unit to the end, keeping the last at or before the start and the first at or after the end,
  # one step more when none reaches it.
  defp steps_of(index, {low, high}) do
    %{by: by, start: unit} = Enum.at(@steps, index)
    sequence = sequence(truncate(low, unit), high, by)
    reaching = Enum.count(sequence, fn time -> seconds(time) >= high end)

    extended =
      if reaching == 0,
        do: Enum.concat(sequence, [advance(List.last(sequence), by)]),
        else: sequence

    first = Enum.count(sequence, fn time -> seconds(time) <= low end) - 1
    last = length(sequence) - reaching
    Enum.slice(extended, first..last//1)
  end

  # The step's times from `start` up to `high`, as R's `seq()` lays them, half months the 1st and
  # 15th of each month.
  defp sequence(start, high, by) do
    start
    |> Stream.iterate(fn time -> advance(time, by) end)
    |> Enum.take_while(fn time -> seconds(time) <= high end)
  end

  defp advance(time, {:seconds, count}), do: NaiveDateTime.add(time, count, :second)
  defp advance(time, {:days, count}), do: NaiveDateTime.add(time, count * @day, :second)
  defp advance(time, {:months, count}), do: NaiveDateTime.shift(time, month: count)
  defp advance(time, {:years, count}), do: NaiveDateTime.shift(time, year: count)
  defp advance(%NaiveDateTime{day: 1} = time, :half_month), do: %{time | day: 15}

  defp advance(%NaiveDateTime{day: 15} = time, :half_month),
    do: NaiveDateTime.shift(%{time | day: 1}, month: 1)

  # The time in seconds truncated to `unit`, on the wall clock of UTC, as R's `trunc_POSIXt()`
  # truncates it, a week starting on Monday, a decade and a century counted from year 0.
  defp truncate(time, unit) do
    whole =
      time
      |> Float.floor()
      |> trunc()

    @epoch
    |> NaiveDateTime.add(whole, :second)
    |> truncated(unit)
  end

  defp truncated(time, :minutes), do: %{time | second: 0, microsecond: {0, 0}}
  defp truncated(time, :hours), do: %{time | minute: 0, second: 0, microsecond: {0, 0}}
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
  defp seconds(time), do: NaiveDateTime.diff(time, @epoch, :second)

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
