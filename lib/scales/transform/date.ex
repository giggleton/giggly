defmodule Scales.Transform.Date do
  @moduledoc false

  # The date transformation, R's `transform_date()`: a date as the days since 1970-01-01, as R
  # stores one, a missing date missing. It is what a continuous scale of dates records, ggplot2's
  # `scale_x_date()`. Use it through `Scales.Transform`, and never alias it down to its last
  # segment, which is Elixir's `Date`.
  #
  # Its axis takes R's `pretty()` breaks for dates (`Scales.DateBreaks`), on calendar
  # boundaries, each labelled in the format of the step chosen for the whole axis, which is why
  # its labels need the extent; breaks it did not choose, given or laid by a width, are written in
  # full, `2026-09-21`, as R's `format()` writes a date with no format; and its minor breaks are
  # R's regular ones on the days, midway between them (`Scales.MinorBreaks`), as
  # `transform_date()` keeps the default.

  @behaviour Scales.Transform

  alias Scales.{DateBreaks, MinorBreaks}

  @epoch ~D[1970-01-01]

  @impl Scales.Transform
  def transform(_transformation, values), do: Enum.map(values, &days/1)

  # A position's date, the day it falls on, rounded down, as R's `format()` writes a date.
  @impl Scales.Transform
  def inverse(_transformation, positions), do: Enum.map(positions, &date/1)

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  @impl Scales.Transform
  def breaks(_transformation, extent, []) do
    {dates, _format} = DateBreaks.pretty(extent)
    Enum.map(dates, &days/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(_transformation, breaks, :given) do
    Enum.map(breaks, fn day ->
      day
      |> date()
      |> DateBreaks.label("%Y-%m-%d")
    end)
  end

  def format(_transformation, breaks, extent) do
    {_dates, format} = DateBreaks.pretty(extent)

    Enum.map(breaks, fn day ->
      day
      |> date()
      |> DateBreaks.label(format)
    end)
  end

  # The breaks `step` lays on an axis showing `extent`, as `Scales.Transform.width/3`
  # describes.
  @doc false
  @spec width(Scales.Transform.name(), keyword(pos_integer()), {float(), float()}) ::
          [float()]
  def width(_transformation, step, extent) do
    step
    |> DateBreaks.width(extent)
    |> Enum.map(&days/1)
  end

  defp date(day), do: Date.add(@epoch, floor(day))

  # A date's days since 1970-01-01, a double as R stores it.
  defp days(nil), do: nil
  defp days(%Date{} = date), do: Date.diff(date, @epoch) / 1
end
