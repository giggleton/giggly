defmodule Scales.Transform.Sqrt do
  @moduledoc false

  # The square root, R's `transform_sqrt()`. Use it through `Scales.Transform`.
  #
  # A number from zero up becomes its square root, `-0.0`'s `-0.0`, and a negative one or minus
  # infinity NaN, as R's; plus infinity and NaN stay themselves. Turned back, a position is
  # squared, one below zero, minus infinity among them, and NaN missing, as R's
  # `ifelse(x < 0, NA, x^2)`. Its derivatives are R's, `0.5 / sqrt(x)` and `2 * x`, in R's IEEE
  # arithmetic (`Scales.Double`). Its breaks are extended Wilkinson's on the range in data units,
  # its minor breaks R's regular ones in square-root space, and its labels the breaks in data
  # units, plain decimals.

  @behaviour Scales.Transform

  alias Scales.{Breaks, Double, Labels, MinorBreaks}

  @impl Scales.Transform
  def transform(_transformation, values), do: Enum.map(values, &Double.square_root/1)

  @impl Scales.Transform
  def inverse(_transformation, positions), do: Enum.map(positions, &squared/1)

  @impl Scales.Transform
  def domain(_transformation), do: {0.0, :infinity}

  @impl Scales.Transform
  def derivative(_transformation, values) do
    Enum.map(values, fn
      nil -> nil
      value -> Double.divide(0.5, Double.square_root(value))
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(_transformation, positions) do
    Enum.map(positions, fn
      nil -> nil
      position -> Double.multiply(2.0, position)
    end)
  end

  @impl Scales.Transform
  def breaks(_transformation, {low, high}, options) do
    [low, high]
    |> Enum.map(&squared/1)
    |> Enum.min_max()
    |> Breaks.extended(options)
    |> Enum.map(&Double.square_root/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(_transformation, breaks, _extent, _options) do
    breaks
    |> Enum.map(&squared/1)
    |> Labels.plain()
  end

  defp squared(position) when position in [:neg_infinity, :nan] or position < 0, do: nil
  defp squared(position), do: Double.multiply(position, position)
end
