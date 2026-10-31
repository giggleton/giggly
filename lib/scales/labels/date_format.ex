defmodule Scales.Labels.DateFormat do
  @moduledoc false

  # Dates, date-times and times of day written in a `Calendar.strftime/3` format, as scales
  # 1.4.0's `label_date()`, `label_date_short()` and `label_time()` write them through R's
  # `format()`, for `Scales.Labels`.
  #
  # A value is written on a clock, the zone `tz:` names and the database that reads it. R writes a
  # `Date` at midnight UTC whatever its `tz` (`%H` is `00`, `%Z` `UTC`), so a `Date` is written as
  # the UTC `DateTime` at its midnight and a `NaiveDateTime` as the UTC `DateTime` it names,
  # neither shifted (design-log §4, the entry beginning "The date labellers take"); a `DateTime`
  # is shifted into the zone, as R's `format()` shifts a `POSIXct`; a `Time` is written as it is,
  # where R shifts an hms's seconds from midnight UTC. Each is written by `DateBreaks.label/2`, a
  # year unpadded. `%s` is the instant's Unix time in every zone, where R's, outside UTC, counts
  # the wall clock's seconds as though it were UTC's (`1970-01-01 05:30` in Kolkata, `19800`), a
  # count of nothing.
  #
  # `short/5` is `label_date_short()`. Each value's year, month and day are compared with the
  # last value's on its own clock, as R reads `as.POSIXlt(x)` in `x`'s own zone, and a part is
  # shown where it or a coarser one changed; the first value, and one after a missing one, show
  # every part. Before that the time is dropped where every value is at midnight, its hour and
  # minute 0 (R's `Date` test and its midnight test in one, since a `Date` is at midnight on its
  # own clock); then the day where every one is a 1st; then the month where every one is in
  # January, as R drops them in turn, a missing value taking no part. The parts shown are written
  # finest first, each on its own: `leading:` replaces a `0` at the start of each part, then
  # `sep:` joins them. R writes the joined format at once and replaces `^0` and `sep` followed by
  # `0` in the text, which is the same but where `sep` is `""` (every `0` after the first is
  # replaced), where a part's own text holds `sep` and then `0`, or where `sep` or `leading`
  # holds what R reads as a conversion or an escape; there, `sep:` and `leading:` are text.
  #
  # A value with no part to write (a value repeated where the time is dropped, or every part it
  # would show `nil`) takes R's format `""`, `format()`'s default, chosen over those values alone
  # on the zone's clock: `"%Y-%m-%d"` where each is exactly midnight, to the microsecond, and
  # `"%Y-%m-%d %H:%M:%S"` otherwise, as R's `format.POSIXlt()` chooses with no `digits.secs`; no
  # `leading:` touches it.

  alias Scales.DateBreaks

  @typedoc "A date, a date-time, a time of day or a missing one."
  @type value :: Date.t() | NaiveDateTime.t() | DateTime.t() | Time.t() | nil

  @typedoc "The zone a `DateTime` is written in and the database that reads it."
  @type clock :: {String.t(), module()}

  @typedoc "`label_date_short()`'s formats, each a format or `nil` for a part never written."
  @type parts :: [
          year: String.t() | nil,
          month: String.t() | nil,
          day: String.t() | nil,
          time: String.t() | nil
        ]

  # The parts R may drop, in the order it drops them, each only once the last is gone.
  @drops [:time, :day, :month]

  # Each value in `format` on `clock`, a missing one `nil`.
  @doc false
  @spec write([value()], String.t(), clock()) :: [String.t() | nil]
  def write(values, format, clock) do
    Enum.map(values, fn
      nil -> nil
      value -> written(on_clock(value, clock), format)
    end)
  end

  # Each value in the parts that changed from the last, joined by `sep`, as `label_date_short()`
  # writes them.
  @doc false
  @spec short([value()], parts(), String.t(), String.t(), clock()) :: [String.t() | nil]
  def short(values, parts, sep, leading, clock) do
    walls = Enum.map(values, fn value -> value && wall(value) end)
    kept = dropped(parts, Enum.reject(walls, &is_nil/1))
    previous = [nil | Enum.drop(walls, -1)]

    formats =
      Enum.zip_with(walls, previous, fn
        nil, _previous -> nil
        wall, previous -> shown(kept, wall, previous)
      end)

    default = default_format(values, formats, clock)

    Enum.zip_with(values, formats, fn
      nil, _formats ->
        nil

      value, [] ->
        written(on_clock(value, clock), default)

      value, formats ->
        on_clock = on_clock(value, clock)

        Enum.map_join(formats, sep, fn format ->
          on_clock
          |> written(format)
          |> String.replace_prefix("0", leading)
        end)
    end)
  end

  # Raises unless `database` knows `zone`, checked by shifting an instant into it.
  @doc false
  @spec check_zone!(String.t(), String.t(), module()) :: :ok
  def check_zone!(function, zone, database) do
    case DateTime.shift_zone(~U[1970-01-01 00:00:00Z], zone, database) do
      {:ok, _shifted} ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "#{function} writes in tz: #{inspect(zone)}, which #{inspect(database)} cannot " <>
                "read (#{inspect(reason)}); give a time zone database that knows it as " <>
                "time_zone_database:, such as Tz.TimeZoneDatabase"
    end
  end

  defp on_clock(%Date{} = date, _clock),
    do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC", Calendar.UTCOnlyTimeZoneDatabase)

  defp on_clock(%NaiveDateTime{} = naive, _clock),
    do: DateTime.from_naive!(naive, "Etc/UTC", Calendar.UTCOnlyTimeZoneDatabase)

  defp on_clock(%DateTime{} = datetime, {zone, database}),
    do: DateTime.shift_zone!(datetime, zone, database)

  defp on_clock(%Time{} = time, _clock), do: time

  # A time of day has no date for a format to write: `Calendar.strftime/3` raises a `KeyError` or
  # a `FunctionClauseError` reaching for one.
  defp written(%Time{} = time, format) do
    DateBreaks.label(time, format)
  rescue
    error in [KeyError, FunctionClauseError] ->
      reraise ArgumentError,
              "Labels.time/2 cannot write a time of day, #{inspect(time)}, in " <>
                "#{inspect(format)}, which writes a part of a date; give a format of the " <>
                "time alone, such as \"%H:%M:%S\" (#{Exception.message(error)})",
              __STACKTRACE__
  end

  defp written(datetime, format), do: DateBreaks.label(datetime, format)

  # A value's year, month, day, hour and minute on its own clock.
  defp wall(%Date{} = date),
    do: %{year: date.year, month: date.month, day: date.day, hour: 0, minute: 0}

  defp wall(datetime), do: Map.take(datetime, [:year, :month, :day, :hour, :minute])

  # The parts left once R's drops are made, each in turn while every value allows it.
  defp dropped(parts, walls) do
    @drops
    |> Enum.take_while(fn part -> Enum.all?(walls, fn wall -> droppable?(part, wall) end) end)
    |> Enum.reduce(parts, fn part, kept -> Keyword.put(kept, part, nil) end)
  end

  defp droppable?(:time, wall), do: wall.hour == 0 and wall.minute == 0
  defp droppable?(:day, wall), do: wall.day == 1
  defp droppable?(:month, wall), do: wall.month == 1

  # A value's formats, finest first: the time where kept, then each part where it or a coarser
  # one changed from the last value; every part after a missing value or none.
  defp shown(parts, wall, previous) do
    year = previous == nil or wall.year != previous.year
    month = year or wall.month != previous.month
    day = month or wall.day != previous.day

    [time: true, day: day, month: month, year: year]
    |> Enum.filter(fn {_part, changed} -> changed end)
    |> Enum.map(fn {part, _changed} -> Keyword.fetch!(parts, part) end)
    |> Enum.reject(&is_nil/1)
  end

  # R's `format()` default for the values with no part to write, on the zone's clock.
  defp default_format(values, formats, clock) do
    unwritten = for {value, []} <- Enum.zip(values, formats), do: on_clock(value, clock)

    if Enum.all?(unwritten, &midnight?/1), do: "%Y-%m-%d", else: "%Y-%m-%d %H:%M:%S"
  end

  defp midnight?(datetime) do
    {microsecond, _precision} = datetime.microsecond
    datetime.hour == 0 and datetime.minute == 0 and datetime.second == 0 and microsecond == 0
  end
end
