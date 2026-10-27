defmodule Scales.Transform.Datetime do
  @moduledoc false

  # The date-time transformation, R's `transform_time()`: a date-time as its seconds since
  # 1970-01-01 00:00 UTC, a double, as R's `POSIXct` stores one, its whole microseconds divided
  # once by a million, so it is the double nearest the instant; a naive date-time as its seconds
  # since the same wall-clock time, as if its clock were UTC's; a missing one missing. It is what
  # a scale of date-times records, ggplot2's `scale_x_datetime()`, with its time zone and the time
  # zone database that reads it, `{:datetime, zone, database}`, as R's `transform_time(tz)` holds
  # its zone: `:default` until a column settles it, `:naive` for naive date-times, else a zone's
  # name, which the database must know. Use it through `Scales.Transform`.
  #
  # Its axis takes R's `pretty()` breaks for date-times (`Scales.DateBreaks`), on clock and
  # calendar boundaries in its zone, UTC's for `:default`, and a naive date-time's own, as UTC's,
  # each labelled in the format of the step chosen for the whole axis; breaks it did not choose,
  # given or laid by a width, are written as R's `format()` writes them, the date alone where every
  # one is at midnight, else the date and the time to the second; and its minor breaks are R's
  # regular ones on the seconds, midway between them (`Scales.MinorBreaks`), as
  # `transform_time()` keeps the default. A break turned back is a `DateTime` in the zone, UTC for
  # `:default`, or a `NaiveDateTime`, to the second where it is a whole second and else to the
  # microsecond, so its label is written in the zone's wall-clock time.

  @behaviour Scales.Transform

  alias Scales.{DateBreaks, MinorBreaks}

  @epoch ~N[1970-01-01 00:00:00]
  @microseconds 1_000_000

  @impl Scales.Transform
  def transform({:datetime, zone, _database}, values),
    do: Enum.map(values, fn value -> placed(zone, value) end)

  @impl Scales.Transform
  def inverse({:datetime, zone, database}, positions),
    do: Enum.map(positions, fn position -> datetime({zone, database}, position) end)

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  @impl Scales.Transform
  def breaks(transformation, extent) do
    {times, _format} = DateBreaks.pretty_datetime(extent, clock(transformation))
    Enum.map(times, &seconds/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(transformation, breaks, :given) do
    datetimes = inverse(transformation, breaks)
    format = if Enum.all?(datetimes, &midnight?/1), do: "%Y-%m-%d", else: "%Y-%m-%d %H:%M:%S"
    Enum.map(datetimes, fn datetime -> DateBreaks.label(datetime, format) end)
  end

  def format(transformation, breaks, extent) do
    {_times, format} = DateBreaks.pretty_datetime(extent, clock(transformation))

    transformation
    |> inverse(breaks)
    |> Enum.map(fn datetime -> DateBreaks.label(datetime, format) end)
  end

  # The breaks `step` lays on an axis showing `extent`, as `Scales.Transform.width/3`
  # describes.
  @doc false
  @spec width(Scales.Transform.name(), keyword(pos_integer()), {float(), float()}) ::
          [float()]
  def width(transformation, step, extent) do
    step
    |> DateBreaks.datetime_width(extent, clock(transformation))
    |> Enum.map(&seconds/1)
  end

  # The clock a scale's breaks are laid on: UTC's for a naive scale, as a naive date-time is placed
  # as though its clock were UTC's, and for one no column has settled; else its zone's.
  defp clock({:datetime, zone, _database}) when zone in [:naive, :default], do: :utc
  defp clock({:datetime, zone, database}), do: {zone, database}

  # A date-time's seconds since 1970-01-01 00:00 UTC, or a naive one's since the same wall-clock
  # time, a double as R's `POSIXct` stores it.
  @doc false
  @spec seconds(DateTime.t() | NaiveDateTime.t()) :: float()
  def seconds(%DateTime{} = datetime),
    do: DateTime.to_unix(datetime, :microsecond) / @microseconds

  def seconds(%NaiveDateTime{} = datetime),
    do: NaiveDateTime.diff(datetime, @epoch, :microsecond) / @microseconds

  # A value a scale places: a date-time on a scale in a zone, a naive one on a naive scale, either
  # on one no column has settled. A plot's limits or breaks of the other kind are refused, as the
  # column's would be.
  defp placed(_zone, nil), do: nil
  defp placed(zone, %DateTime{} = datetime) when zone != :naive, do: seconds(datetime)

  defp placed(zone, %NaiveDateTime{} = datetime) when zone in [:naive, :default],
    do: seconds(datetime)

  defp placed(:naive, value) do
    raise ArgumentError,
          "a scale of naive date-times cannot place #{inspect(value)}, a date-time in a time " <>
            "zone; give it naive date-times"
  end

  defp placed(zone, value) do
    raise ArgumentError,
          "a scale of date-times in #{inspect(zone)} cannot place #{inspect(value)}, a naive " <>
            "date-time, which has no time zone; give it date-times in a time zone"
  end

  # The date-time at `seconds`: a naive one on a naive scale, else one in the scale's zone, UTC
  # where no column has settled it.
  defp datetime(zone_and_database, seconds) do
    microseconds = round(seconds * @microseconds)

    zone_and_database
    |> at(microseconds)
    |> precise(microseconds)
  end

  defp at({:naive, _database}, microseconds),
    do: NaiveDateTime.add(@epoch, microseconds, :microsecond)

  defp at({:default, _database}, microseconds),
    do: DateTime.from_unix!(microseconds, :microsecond)

  defp at({zone, database}, microseconds) do
    microseconds
    |> DateTime.from_unix!(:microsecond)
    |> DateTime.shift_zone!(zone, database)
  end

  defp precise(datetime, microseconds) when rem(microseconds, @microseconds) == 0,
    do: %{datetime | microsecond: {0, 0}}

  defp precise(datetime, _microseconds), do: datetime

  defp midnight?(%{hour: 0, minute: 0, second: 0, microsecond: {0, _precision}}), do: true
  defp midnight?(_datetime), do: false
end
