defmodule Scales.Transform.Identity do
  @moduledoc false

  # The identity transformation, R's `transform_identity()`: every value as it is, a date at its
  # days since 1970-01-01, a date-time at its seconds (`Transform.Datetime.seconds/1`) and a time
  # at its seconds since midnight (`Transform.Time.seconds/1`), as R stores each and its
  # untransformed continuous scale places one. It is what a continuous scale records when nothing
  # transforms its axis. Use it through `Scales.Transform`.
  #
  # Its axis takes R's default breaks for a transformation, extended Wilkinson
  # (`Scales.Breaks`), and its default minor breaks, midway between them
  # (`Scales.MinorBreaks`), and writes the breaks as plain decimals (`Scales.Labels.plain/1`).

  @behaviour Scales.Transform

  alias Scales.{Breaks, Labels, MinorBreaks, Transform}

  @epoch ~D[1970-01-01]

  @impl Scales.Transform
  def transform(_transformation, values), do: Enum.map(values, &placed/1)

  @impl Scales.Transform
  def inverse(_transformation, positions), do: positions

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  @impl Scales.Transform
  def breaks(_transformation, extent), do: Breaks.extended(extent)

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  # A number's label is its own, whatever the extent.
  @impl Scales.Transform
  def format(_transformation, breaks, _extent), do: Labels.plain(breaks)

  defp placed(%Date{} = date), do: Date.diff(date, @epoch) / 1

  defp placed(%struct{} = datetime) when struct in [DateTime, NaiveDateTime],
    do: Transform.Datetime.seconds(datetime)

  defp placed(%Time{} = time), do: Transform.Time.seconds(time)

  defp placed(value), do: value
end
