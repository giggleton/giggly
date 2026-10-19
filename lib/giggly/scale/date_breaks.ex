defmodule Giggly.Scale.DateBreaks do
  @moduledoc false

  # A date axis's breaks: R's `pretty()` for dates (grDevices' `prettyDate()`), which ggplot2's
  # date scales take through `scales::breaks_pretty()`, about five breaks on calendar boundaries
  # and the format their labels are written in, used through `Giggly.Scale.Transform`; and a break
  # every step of a width a plot gives (`width/2`), as R's `breaks_width()` lays them, used by
  # `Giggly.Scale` for a scale's `{:width, step}`.
  #
  # The extent is in days since 1970-01-01, as R stores a date, and is worked in seconds, as R
  # turns a date into a time at midnight GMT. An extent of five days or less is every day it
  # touches, widened by as many days as five less its length, rounded half to even, labelled
  # `"%b %d"`. A longer one takes the step, from a day to a thousand years, that cuts it closest to
  # five times, and lays breaks from its start truncated to the step's unit (a day, a week starting
  # on Monday, a month, a year, a decade, a century) to the first at or past its end, keeping the
  # last before the extent and the first after it; the neighbouring step is taken instead when its
  # breaks come closer to five intervals. Each step names its labels' format: `"%b %d"` for days,
  # weeks and half months (the 1st and 15th), `"%b"` for months within a year and `"%b %Y"`
  # beyond, `"%Y-%m"` for six months, and `"%Y"` for years.
  #
  # What R does only for times is left out: its steps under a day, its widening of the five-day
  # case to three days, which always has five, its finer step for fewer than two intervals and its
  # trimming of breaks beyond the extent, neither of which the step closest to five ever needs for
  # a date, since it keeps one break outside each end and cuts at least two intervals. Reaching for
  # a step under a day fails, and so do fewer than two intervals.

  @epoch ~D[1970-01-01]

  # R's units: a day in seconds, a year of 365.25 days and a twelfth of it.
  @day 86_400
  @year @day * 365.25
  @month @year / 12

  # `pretty()`'s defaults for dates: about five intervals, and no fewer than two.
  @wanted 5
  @fewest 2

  # Each step: its length in seconds, how a sequence of it advances, the unit its first break is
  # truncated to, and its labels' format, `:month` for one that depends on the extent's span.
  @steps [
    %{seconds: 1 * @day, by: {:days, 1}, start: :days, format: "%b %d"},
    %{seconds: 2 * @day, by: {:days, 2}, start: :days, format: "%b %d"},
    %{seconds: 7 * @day, by: {:days, 7}, start: :weeks, format: "%b %d"},
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

  # A width's units: the most days each holds, which `scales`' `ceiling_date()` adds before
  # rounding down, and the unit a date is truncated to, as R's `cut()` truncates it.
  @most_days %{day: 1, week: 7, month: 31, year: 365}
  @truncations %{week: :weeks, month: :months, year: :years}

  # The breaks of an axis showing `extent`, in days, as dates in ascending order, some of them
  # outside it, and the format their labels are written in.
  @doc false
  @spec pretty({number(), number()}) :: {[Date.t()], String.t()}
  def pretty({low, high}) do
    # R's `as.POSIXct()` of a date: its days times the seconds in a day.
    limits = {low * @day, high * @day}

    case span(limits) do
      span when span <= @wanted * @day -> every_day(limits, span)
      span -> stepped(limits, span)
    end
  end

  # Every day the extent touches, widened by as many days as five less its length, rounded half to
  # even, half on the left and the odd day on the right, as R's short-range branch widens it.
  defp every_day({low, high}, span) do
    widening = round_half_even(@wanted - span / @day)
    left = div(widening, 2)
    right = left + rem(widening, 2)
    days = (floor_day(low) - left)..(floor_day(high) + right)//1
    {Enum.map(days, fn day -> Date.add(@epoch, day) end), "%b %d"}
  end

  defp stepped(limits, span) do
    first =
      Enum.min_by(0..@last_step, fn index ->
        abs(span / Enum.at(@steps, index).seconds - @wanted)
      end)

    # The step closest to five intervals always cuts a date extent at least twice.
    [_start, _middle, _end | _rest] = breaks = steps_of(first, limits)
    {chosen, dates} = choose(first, breaks, limits)
    {dates, format(Enum.at(@steps, chosen), span)}
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
    last = rounded_down(high + count * Map.fetch!(@most_days, unit), unit, count)

    low
    |> rounded_down(unit, count)
    |> sequence(seconds(last), stride(unit, count))
  end

  defp rounded_down(day, :day, count), do: Date.add(@epoch, round_half_even(day / count) * count)
  defp rounded_down(day, unit, _count), do: truncate(day * @day, Map.fetch!(@truncations, unit))

  defp stride(:day, count), do: {:days, count}
  defp stride(:week, count), do: {:days, 7 * count}
  defp stride(:month, count), do: {:months, count}
  defp stride(:year, count), do: {:years, count}

  # The step's breaks, or the neighbouring step's where they come closer to five intervals: a
  # coarser one for too many, a finer one for too few.
  defp choose(index, breaks, limits) do
    excess = intervals(breaks) - @wanted

    if excess == 0 do
      {index, breaks}
    else
      neighbour = if excess > 0, do: min(index + 1, @last_step), else: finer(index)
      neighbour_breaks = steps_of(neighbour, limits)

      if closer?(intervals(neighbour_breaks), excess),
        do: {neighbour, neighbour_breaks},
        else: {index, breaks}
    end
  end

  # Whether a count of intervals is closer to five than an excess of `excess` is; one with fewer
  # than two never is, as R counts it as minus infinity.
  defp closer?(count, excess), do: count >= @fewest and abs(count - @wanted) < abs(excess)

  # R would take a step under a day, which no date extent reaches.
  defp finer(index) when index > 0, do: index - 1

  # The step's breaks over the extent, R's `calcSteps()`: from its start truncated to the step's
  # unit to the end, keeping the last at or before the start and the first at or after the end,
  # one step more when none reaches it.
  defp steps_of(index, {low, high}) do
    %{by: by, start: unit} = Enum.at(@steps, index)
    sequence = sequence(truncate(low, unit), high, by)
    reaching = Enum.count(sequence, fn date -> seconds(date) >= high end)

    extended =
      if reaching == 0,
        do: Enum.concat(sequence, [advance(List.last(sequence), by)]),
        else: sequence

    first = Enum.count(sequence, fn date -> seconds(date) <= low end) - 1
    last = length(sequence) - reaching
    Enum.slice(extended, first..last//1)
  end

  # The step's dates from `start` up to `high`, as R's `seq()` lays them, half months the 1st and
  # 15th of each month.
  defp sequence(start, high, by) do
    start
    |> Stream.iterate(fn date -> advance(date, by) end)
    |> Enum.take_while(fn date -> seconds(date) <= high end)
  end

  defp advance(date, {:days, count}), do: Date.add(date, count)
  defp advance(date, {:months, count}), do: Date.shift(date, month: count)
  defp advance(date, {:years, count}), do: Date.shift(date, year: count)
  defp advance(%Date{day: 1} = date, :half_month), do: %{date | day: 15}
  defp advance(%Date{day: 15} = date, :half_month), do: Date.shift(%{date | day: 1}, month: 1)

  # The date of a time in seconds truncated to `unit`, as R's `trunc_POSIXt()` truncates it, a
  # week starting on Monday, a decade and a century counted from year 0.
  defp truncate(time, unit) do
    time
    |> floor_day()
    |> then(fn day -> Date.add(@epoch, day) end)
    |> truncated(unit)
  end

  defp truncated(date, :days), do: date
  defp truncated(date, :weeks), do: Date.add(date, 1 - Date.day_of_week(date))
  defp truncated(date, :months), do: %{date | day: 1}
  defp truncated(date, :years), do: %{date | month: 1, day: 1}
  defp truncated(date, :decades), do: %{date | year: floor_by(date.year, 10), month: 1, day: 1}
  defp truncated(date, :centuries), do: %{date | year: floor_by(date.year, 100), month: 1, day: 1}

  defp floor_by(year, size), do: Integer.floor_div(year, size) * size

  # A date's label in `format`, as R's `format()` writes it in the C locale: English month
  # abbreviations, a day or month two digits, and a year as its number, unpadded, so the year 900
  # is `"900"` where `Calendar.strftime/2` would write `"0900"`.
  @doc false
  @spec label(Date.t(), String.t()) :: String.t()
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
  defp seconds(date), do: Date.diff(date, @epoch) * @day

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
