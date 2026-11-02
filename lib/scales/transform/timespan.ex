defmodule Scales.Transform.Timespan do
  @moduledoc false

  # The span of time transformation, R's `transform_timespan(unit)`: `:timespan`, a number of
  # seconds, and `{:timespan, unit}`, a number counted in `unit`, `:second` to `:week`. Use it
  # through `Scales.Transform`.
  #
  # A value becomes its seconds, the value times the unit's seconds, as R's turns a `difftime`
  # into seconds; turned back, a position times one over the unit's seconds, as R converts a
  # `difftime`'s units, a number where R gives a `difftime`. Its domain is every number, and, as
  # R's, it has no derivatives. Its breaks are `Scales.Breaks.timespan/2`'s on the extent turned
  # back into the unit, seconds, so they fall on whole seconds, minutes, hours, days or weeks,
  # and, as R's, it counts none; its minor breaks are R's regular ones in seconds, and its labels
  # `Scales.Labels.timespan/2`'s, the breaks turned back, in the unit.

  @behaviour Scales.Transform

  alias Scales.{Breaks, Double, Labels, MinorBreaks}

  @impl Scales.Transform
  def transform(transformation, values) do
    seconds = seconds(transformation)

    Enum.map(values, fn
      nil -> nil
      value -> Double.multiply(value, seconds)
    end)
  end

  @impl Scales.Transform
  def inverse(transformation, positions) do
    per_second = 1 / seconds(transformation)

    Enum.map(positions, fn
      nil -> nil
      position -> Double.multiply(position, per_second)
    end)
  end

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  @impl Scales.Transform
  def breaks(transformation, extent, []) do
    [low, high] = inverse(transformation, Tuple.to_list(extent))
    Breaks.timespan({low, high}, unit: unit(transformation))
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(transformation, breaks, _extent, _options) do
    transformation
    |> inverse(breaks)
    |> Labels.timespan(unit: unit(transformation))
  end

  # A unit's seconds, as a double, as R holds them.
  defp seconds(transformation) do
    transformation
    |> unit()
    |> Breaks.unit_seconds()
    |> Kernel./(1)
  end

  # The unit, R's default seconds.
  defp unit(:timespan), do: :second
  defp unit({:timespan, unit}), do: unit
end
