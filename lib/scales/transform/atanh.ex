defmodule Scales.Transform.Atanh do
  @moduledoc false

  # The inverse hyperbolic tangent, R's `transform_atanh()`. Use it through `Scales.Transform`.
  #
  # A value from -1 to 1 becomes its inverse hyperbolic tangent
  # (`Scales.Double.inverse_hyperbolic_tangent/1`, the platform's, within 1 ulp of R's correctly
  # rounded one), -1 and 1 the infinities, a zero of either sign `0.0`, anything else NaN, as R's;
  # turned back by the hyperbolic tangent, each infinity 1 of its sign. Its derivatives are R's,
  # `1 / (1 - x * x)` and `1 / (cosh(x) * cosh(x))`, in R's IEEE arithmetic (`Scales.Double`),
  # exact against R on 3,000 random values.
  #
  # Its breaks are extended Wilkinson's on the range in data units, its minor breaks R's regular
  # ones in transformed space, and its labels the breaks in data units, plain decimals.

  @behaviour Scales.Transform

  alias Scales.{Breaks, Double, Labels, MinorBreaks}

  @impl Scales.Transform
  def transform(_transformation, values) do
    Enum.map(values, fn
      nil -> nil
      value -> Double.inverse_hyperbolic_tangent(value)
    end)
  end

  @impl Scales.Transform
  def inverse(_transformation, positions), do: Enum.map(positions, &Double.hyperbolic_tangent/1)

  @impl Scales.Transform
  def domain(_transformation), do: {-1.0, 1.0}

  @impl Scales.Transform
  def derivative(_transformation, values) do
    Enum.map(values, fn
      nil ->
        nil

      value ->
        1.0
        |> Double.subtract(Double.multiply(value, value))
        |> then(fn difference -> Double.divide(1.0, difference) end)
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(_transformation, positions) do
    Enum.map(positions, fn
      nil ->
        nil

      position ->
        cosine = Double.hyperbolic_cosine(position)
        Double.divide(1.0, Double.multiply(cosine, cosine))
    end)
  end

  @impl Scales.Transform
  def breaks(_transformation, {low, high}, options) do
    {Double.hyperbolic_tangent(low), Double.hyperbolic_tangent(high)}
    |> Breaks.extended(options)
    |> Enum.map(&Double.inverse_hyperbolic_tangent/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(_transformation, breaks, _extent, _options) do
    breaks
    |> Enum.map(&Double.hyperbolic_tangent/1)
    |> Labels.plain()
  end
end
