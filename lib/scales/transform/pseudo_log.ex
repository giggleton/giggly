defmodule Scales.Transform.PseudoLog do
  @moduledoc false

  # The pseudo-logarithm, R's `transform_pseudo_log(sigma, base)`: `:pseudo_log`, with R's sigma
  # of 1 and base e, and `{:pseudo_log, options}`, either or both of `sigma:`, a number above 0,
  # and `base:`, a number above 1. Use it through `Scales.Transform`.
  #
  # Every value becomes `asinh(x / (2 * sigma)) / log(base)`, linear near zero and close to the
  # logarithm far from it, through the platform's inverse hyperbolic sine
  # (`Scales.Double.inverse_hyperbolic_sine/1`), within 2 ulps of R's; turned back,
  # `2 * sigma * sinh(x * log(base))`. Each infinity is its own and a zero of either sign `0.0`, as
  # R's are on a vector. Its domain is every number. Its derivatives are R's,
  # `1 / (sqrt(1 + x * x / (4 * sigma * sigma)) * 2 * sigma * log(base))` and
  # `2 * sigma * cosh(x * log(base)) * log(base)`, each in the order that gave R's doubles on all
  # of 3,000 random values, in R's IEEE arithmetic (`Scales.Double`).
  #
  # Its breaks are extended Wilkinson's on the range in data units, its minor breaks R's regular
  # ones in transformed space, and its labels the breaks in data units, plain decimals of each
  # rounded to 14 significant digits (`Scales.Labels.plain_round_tripped/1`).

  @behaviour Scales.Transform

  alias Scales.{Breaks, Double, Labels, MinorBreaks}

  @impl Scales.Transform
  def transform(transformation, values) do
    parameters = parameters(transformation)

    Enum.map(values, fn
      nil -> nil
      value -> pseudo_logarithm(value, parameters)
    end)
  end

  @impl Scales.Transform
  def inverse(transformation, positions) do
    parameters = parameters(transformation)
    Enum.map(positions, fn position -> inverse_pseudo_logarithm(position, parameters) end)
  end

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  @impl Scales.Transform
  def derivative(transformation, values) do
    {sigma, natural_log_of_base} = parameters(transformation)

    Enum.map(values, fn
      nil ->
        nil

      value ->
        value
        |> Double.multiply(value)
        |> Double.divide(4 * sigma * sigma)
        |> Double.add(1.0)
        |> Double.square_root()
        |> Double.multiply(2.0)
        |> Double.multiply(sigma)
        |> Double.multiply(natural_log_of_base)
        |> then(fn denominator -> Double.divide(1.0, denominator) end)
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(transformation, positions) do
    {sigma, natural_log_of_base} = parameters(transformation)

    Enum.map(positions, fn
      nil ->
        nil

      position ->
        position
        |> Double.multiply(natural_log_of_base)
        |> Double.hyperbolic_cosine()
        |> then(fn cosine -> Double.multiply(2 * sigma, cosine) end)
        |> Double.multiply(natural_log_of_base)
    end)
  end

  @impl Scales.Transform
  def breaks(transformation, {low, high}, options) do
    parameters = parameters(transformation)

    {inverse_pseudo_logarithm(low, parameters), inverse_pseudo_logarithm(high, parameters)}
    |> Breaks.extended(options)
    |> Enum.map(fn break -> pseudo_logarithm(break, parameters) end)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(transformation, breaks, _extent, _options) do
    parameters = parameters(transformation)

    breaks
    |> Enum.map(fn break -> inverse_pseudo_logarithm(break, parameters) end)
    |> Labels.plain_round_tripped()
  end

  defp pseudo_logarithm(value, {sigma, natural_log_of_base}) do
    value
    |> Double.divide(2 * sigma)
    |> Double.inverse_hyperbolic_sine()
    |> Double.divide(natural_log_of_base)
  end

  defp inverse_pseudo_logarithm(position, {sigma, natural_log_of_base}) do
    position
    |> Double.multiply(natural_log_of_base)
    |> Double.hyperbolic_sine()
    |> then(fn sine -> Double.multiply(2 * sigma, sine) end)
  end

  # Sigma and the natural logarithm of the base, R's defaults 1 and e.
  defp parameters(:pseudo_log), do: {1.0, 1.0}

  defp parameters({:pseudo_log, options}) do
    sigma = Keyword.get(options, :sigma, 1)
    base = Keyword.get(options, :base, :math.exp(1))
    {sigma, :math.log(base)}
  end
end
