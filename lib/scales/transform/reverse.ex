defmodule Scales.Transform.Reverse do
  @moduledoc false

  # The reversal, R's `transform_reverse()`: each value negated, so the axis runs from high to low.
  # Use it through `Scales.Transform`.
  #
  # Plus and minus infinity swap. Its breaks are extended Wilkinson's on the range in data units,
  # negated, so they descend; its minor breaks are R's regular ones with `reverse = TRUE`, which
  # adds the step above the first break and below the last; and its labels are the breaks in data
  # units, plain decimals.

  @behaviour Scales.Transform

  alias Scales.{Breaks, Labels, MinorBreaks}

  @impl Scales.Transform
  def transform(_transformation, values), do: Enum.map(values, &negated/1)

  @impl Scales.Transform
  def inverse(_transformation, positions), do: Enum.map(positions, &negated/1)

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  @impl Scales.Transform
  def breaks(_transformation, {low, high}) do
    [low, high]
    |> Enum.map(&negated/1)
    |> Enum.min_max()
    |> Breaks.extended()
    |> Enum.map(&negated/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent, true)

  @impl Scales.Transform
  def format(_transformation, breaks, _extent) do
    breaks
    |> Enum.map(&negated/1)
    |> Labels.plain()
  end

  defp negated(value) when is_number(value), do: -value
  defp negated(:infinity), do: :neg_infinity
  defp negated(:neg_infinity), do: :infinity
  defp negated(_missing), do: nil
end
