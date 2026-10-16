defmodule Giggly.Scale.Transform.Date do
  @moduledoc false

  # The date transformation, R's `transform_date()`: a date as the days since 1970-01-01, as R
  # stores one, a missing date missing. It is what a continuous scale of dates records, ggplot2's
  # `scale_x_date()`. Use it through `Giggly.Scale.Transform`, and never alias it down to its last
  # segment, which is Elixir's `Date`.
  #
  # Its axis takes R's `pretty()` breaks for dates (`Giggly.Scale.DateBreaks`), on calendar
  # boundaries, each labelled in the format of the step chosen for the whole axis, which is why
  # its labels need the extent; and its minor breaks are R's regular ones on the days, midway
  # between them (`Giggly.Scale.MinorBreaks`), as `transform_date()` keeps the default.

  @behaviour Giggly.Scale.Transform

  alias Giggly.Scale.{DateBreaks, MinorBreaks}

  @epoch ~D[1970-01-01]

  @impl Giggly.Scale.Transform
  def transform(values), do: Enum.map(values, &days/1)

  @impl Giggly.Scale.Transform
  def breaks(extent) do
    {dates, _format} = DateBreaks.pretty(extent)
    Enum.map(dates, &days/1)
  end

  @impl Giggly.Scale.Transform
  def minor_breaks(breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Giggly.Scale.Transform
  def format(breaks, extent) do
    {_dates, format} = DateBreaks.pretty(extent)

    Enum.map(breaks, fn day ->
      @epoch
      |> Date.add(trunc(day))
      |> DateBreaks.label(format)
    end)
  end

  # A date's days since 1970-01-01, a double as R stores it.
  defp days(nil), do: nil
  defp days(%Date{} = date), do: Date.diff(date, @epoch) / 1
end
