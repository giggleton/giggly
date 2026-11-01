defmodule Scales.Transform.Asinh do
  @moduledoc false

  # The inverse hyperbolic sine, R's `transform_asinh()`. Use it through `Scales.Transform`.
  #
  # Every value becomes its inverse hyperbolic sine (`Scales.Double.inverse_hyperbolic_sine/1`,
  # the platform's, within 1 ulp of R's correctly rounded one), and is turned back by the
  # hyperbolic sine, each infinity its own and a zero of either sign `0.0`, as R's are on a
  # vector. Its domain is every number. Its derivatives are R's, `1 / sqrt(x^2 + 1)` and
  # `cosh(x)`, in R's IEEE arithmetic (`Scales.Double`).
  #
  # Its breaks are extended Wilkinson's on the range in data units, its minor breaks R's regular
  # ones in transformed space, and its labels the breaks in data units, plain decimals of each
  # rounded to 14 significant digits (`Scales.Labels.plain_round_tripped/1`).

  @behaviour Scales.Transform

  alias Scales.{Breaks, Double, Labels, MinorBreaks}

  @impl Scales.Transform
  def transform(_transformation, values), do: Enum.map(values, &inverse_hyperbolic_sine/1)

  @impl Scales.Transform
  def inverse(_transformation, positions), do: Enum.map(positions, &Double.hyperbolic_sine/1)

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  @impl Scales.Transform
  def derivative(_transformation, values) do
    Enum.map(values, fn
      nil ->
        nil

      value ->
        value
        |> Double.multiply(value)
        |> Double.add(1.0)
        |> Double.square_root()
        |> then(fn root -> Double.divide(1.0, root) end)
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(_transformation, positions) do
    Enum.map(positions, fn
      nil -> nil
      position -> Double.hyperbolic_cosine(position)
    end)
  end

  @impl Scales.Transform
  def breaks(_transformation, {low, high}, options) do
    {Double.hyperbolic_sine(low), Double.hyperbolic_sine(high)}
    |> Breaks.extended(options)
    |> Enum.map(&Double.inverse_hyperbolic_sine/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(_transformation, breaks, _extent, _options) do
    breaks
    |> Enum.map(&Double.hyperbolic_sine/1)
    |> Labels.plain_round_tripped()
  end

  defp inverse_hyperbolic_sine(nil), do: nil
  defp inverse_hyperbolic_sine(value), do: Double.inverse_hyperbolic_sine(value)
end
