defmodule Giggly.Scale.Transform.Reverse do
  @moduledoc false

  # The reversal, R's `transform_reverse()`: each value negated, so the axis runs from high to low.
  # Use it through `Giggly.Scale.Transform`.
  #
  # Plus and minus infinity swap. Its breaks are extended Wilkinson's on the range in data units,
  # negated, so they descend; its minor breaks are R's regular ones with `reverse = TRUE`, which
  # adds the step above the first break and below the last; and its labels are the breaks in data
  # units, plain decimals.

  @behaviour Giggly.Scale.Transform

  alias Giggly.Scale.{Breaks, Labels, MinorBreaks}

  @impl Giggly.Scale.Transform
  def transform(values), do: Enum.map(values, &negated/1)

  @impl Giggly.Scale.Transform
  def inverse(positions), do: Enum.map(positions, &negated/1)

  @impl Giggly.Scale.Transform
  def domain, do: {:neg_infinity, :infinity}

  @impl Giggly.Scale.Transform
  def breaks({low, high}) do
    [low, high]
    |> inverse()
    |> Enum.min_max()
    |> Breaks.extended()
    |> transform()
  end

  @impl Giggly.Scale.Transform
  def minor_breaks(breaks, extent), do: MinorBreaks.regular(breaks, extent, true)

  @impl Giggly.Scale.Transform
  def format(breaks, _extent) do
    breaks
    |> inverse()
    |> Labels.numbers()
  end

  defp negated(value) when is_number(value), do: -value
  defp negated(:infinity), do: :neg_infinity
  defp negated(:neg_infinity), do: :infinity
  defp negated(_missing), do: nil
end
