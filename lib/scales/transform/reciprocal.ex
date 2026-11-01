defmodule Scales.Transform.Reciprocal do
  @moduledoc false

  # The reciprocal, R's `transform_reciprocal()`: one over each value, both ways. Use it through
  # `Scales.Transform`.
  #
  # One over each value in R's IEEE arithmetic (`Scales.Double`): zero becomes plus infinity and
  # `-0.0` minus infinity, as R's `1/0` is `Inf` and `1/-0` `-Inf`, and each infinity a zero of its
  # sign. Its domain is every number, which R's transformed domain, zero wide, leaves unsquished.
  # Its derivatives, both ways, are R's `-1 / x^2`. Its breaks are
  # extended Wilkinson's on the range in data units, a reciprocal's positions falling as they
  # rise; its minor breaks are R's regular ones on the breaks in that order, and its labels the
  # breaks in data units, plain decimals.

  @behaviour Scales.Transform

  alias Scales.{Breaks, Double, Labels, MinorBreaks}

  @impl Scales.Transform
  def transform(_transformation, values), do: Enum.map(values, &reciprocal/1)

  @impl Scales.Transform
  def inverse(_transformation, positions), do: Enum.map(positions, &reciprocal/1)

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  @impl Scales.Transform
  def derivative(_transformation, values) do
    Enum.map(values, fn
      nil -> nil
      value -> Double.divide(-1.0, Double.multiply(value, value))
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(transformation, positions), do: derivative(transformation, positions)

  @impl Scales.Transform
  def breaks(_transformation, {low, high}, options) do
    [low, high]
    |> Enum.map(&reciprocal/1)
    |> Enum.filter(&is_number/1)
    |> Enum.min_max()
    |> Breaks.extended(options)
    |> Enum.map(&reciprocal/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(_transformation, breaks, _extent, _options) do
    breaks
    |> Enum.map(&reciprocal/1)
    |> Labels.plain()
  end

  defp reciprocal(nil), do: nil
  defp reciprocal(value), do: Double.divide(1.0, value)
end
