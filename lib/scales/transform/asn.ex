defmodule Scales.Transform.Asn do
  @moduledoc false

  # The arcsine square root, R's `transform_asn()`, the binomial distribution's variance-stabilising
  # transformation. Use it through `Scales.Transform`.
  #
  # A proportion from 0 to 1 becomes `2 * asin(sqrt(x))`, from 0 to pi, a zero of either sign
  # `0.0`, as R's on a vector; anything else NaN. Turned back, a position is `sin(x / 2)` squared,
  # which repeats beyond 0 and pi, as R's does. Its derivatives are R's, `1 / sqrt(x - x * x)`, so
  # `-0.0`'s minus infinity, and `sin(x) / 2`, in R's IEEE arithmetic (`Scales.Double`): exact
  # against R on 3,000 random values but where the platform's sine is not (within 2 ulps).
  #
  # Its breaks are extended Wilkinson's on the range in data units, its minor breaks R's regular
  # ones in transformed space, and its labels the breaks in data units, plain decimals.

  @behaviour Scales.Transform

  alias Scales.{Breaks, Double, Labels, MinorBreaks}

  @impl Scales.Transform
  def transform(_transformation, values) do
    Enum.map(values, fn
      nil -> nil
      value -> arc_sine_square_root(value)
    end)
  end

  @impl Scales.Transform
  def inverse(_transformation, positions), do: Enum.map(positions, &sine_of_half_squared/1)

  @impl Scales.Transform
  def domain(_transformation), do: {0.0, 1.0}

  @impl Scales.Transform
  def derivative(_transformation, values) do
    Enum.map(values, fn
      nil ->
        nil

      value ->
        value
        |> Double.subtract(Double.multiply(value, value))
        |> Double.square_root()
        |> then(fn root -> Double.divide(1.0, root) end)
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(_transformation, positions) do
    Enum.map(positions, fn
      nil -> nil
      position -> Double.divide(Double.sine(position), 2.0)
    end)
  end

  @impl Scales.Transform
  def breaks(_transformation, {low, high}, options) do
    {sine_of_half_squared(low), sine_of_half_squared(high)}
    |> Breaks.extended(options)
    |> Enum.map(&arc_sine_square_root/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(_transformation, breaks, _extent, _options) do
    breaks
    |> Enum.map(&sine_of_half_squared/1)
    |> Labels.plain()
  end

  defp arc_sine_square_root(value) do
    value
    |> Double.square_root()
    |> Double.arc_sine()
    |> then(fn angle -> Double.multiply(2.0, angle) end)
  end

  defp sine_of_half_squared(position) do
    sine =
      position
      |> Double.divide(2.0)
      |> Double.sine()

    Double.multiply(sine, sine)
  end
end
