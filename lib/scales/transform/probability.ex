defmodule Scales.Transform.Probability do
  @moduledoc false

  # A distribution's quantile, R's `transform_probability()`: `:probit`, the standard normal, R's
  # `transform_probit()`; `:logit`, the standard logistic, R's `transform_logit()`; and
  # `{:probability, :normal, options}` and `{:probability, :logistic, options}`, either or both of
  # `mean:` and `sd:`, or `location:` and `scale:`, a finite number and one above 0, R's defaults
  # 0 and 1. Use it through `Scales.Transform`.
  #
  # A probability from 0 to 1 becomes the distribution's quantile, `location + scale * q(p)`, 0
  # and 1 the infinities, anything else NaN; turned back, a position is the distribution below
  # `(x - location) / scale`. The standard normal's quantile and distribution are
  # `Scales.Double`'s, within 5 and 3 ulps of R's; the logistic's are `log(p / (1 - p))` and
  # `1 / (1 + exp(-z))`. Its derivatives are R's: turned back, the density at
  # `(x - location) / scale` over the scale, the normal's `Scales.Double.normal_density/1` and the
  # logistic's `e / (scale * f * f)` for `e = exp(-|z|)`, `f = 1 + e`; forward, 1 over that at the
  # value transformed. Every logistic double matched R's on 3,000 random values; the normal's
  # forward derivative at the far tail moves with the quantile's last bit, multiplied by about
  # `q * q` (5.2e-13 relatively from R's at 2.5e-293, where R's own is that far off the truth).
  #
  # Its breaks are extended Wilkinson's on the range in data units, 0 and 1 at the infinities,
  # its minor breaks R's regular ones in transformed space, and its labels the breaks in data
  # units, plain decimals of each rounded to 14 significant digits
  # (`Scales.Labels.plain_round_tripped/1`).

  @behaviour Scales.Transform

  alias Scales.{Breaks, Double, Labels, MinorBreaks}

  @natural_base :math.exp(1)

  @impl Scales.Transform
  def transform(transformation, values) do
    parameters = parameters(transformation)

    Enum.map(values, fn
      nil -> nil
      value -> quantile(value, parameters)
    end)
  end

  @impl Scales.Transform
  def inverse(transformation, positions) do
    parameters = parameters(transformation)
    Enum.map(positions, fn position -> distribution(position, parameters) end)
  end

  @impl Scales.Transform
  def domain(_transformation), do: {0.0, 1.0}

  @impl Scales.Transform
  def derivative(transformation, values) do
    parameters = parameters(transformation)

    Enum.map(values, fn
      nil ->
        nil

      value ->
        value
        |> quantile(parameters)
        |> density(parameters)
        |> then(fn slope -> Double.divide(1.0, slope) end)
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(transformation, positions) do
    parameters = parameters(transformation)

    Enum.map(positions, fn
      nil -> nil
      position -> density(position, parameters)
    end)
  end

  @impl Scales.Transform
  def breaks(transformation, {low, high}, options) do
    parameters = parameters(transformation)

    {distribution(low, parameters), distribution(high, parameters)}
    |> Breaks.extended(options)
    |> Enum.map(fn break -> quantile(break, parameters) end)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(transformation, breaks, _extent, _options) do
    parameters = parameters(transformation)

    breaks
    |> Enum.map(fn break -> distribution(break, parameters) end)
    |> Labels.plain_round_tripped()
  end

  defp quantile(probability, {distribution, location, scale}) do
    probability
    |> standard_quantile(distribution)
    |> then(fn standard -> Double.multiply(scale, standard) end)
    |> then(fn spread -> Double.add(location, spread) end)
  end

  defp distribution(position, {distribution, _location, _scale} = parameters) do
    position
    |> standardized(parameters)
    |> standard_distribution(distribution)
  end

  defp density(position, {distribution, _location, scale} = parameters) do
    position
    |> standardized(parameters)
    |> standard_density(distribution, scale)
  end

  defp standardized(position, {_distribution, location, scale}) do
    position
    |> Double.subtract(location)
    |> Double.divide(scale)
  end

  defp standard_quantile(probability, :normal), do: Double.normal_quantile(probability)

  defp standard_quantile(probability, :logistic) do
    probability
    |> Double.divide(Double.subtract(1.0, probability))
    |> Double.logarithm(@natural_base)
  end

  defp standard_distribution(standard, :normal), do: Double.normal_distribution(standard)

  defp standard_distribution(standard, :logistic) do
    standard
    |> Double.negate()
    |> Double.exponential()
    |> Double.add(1.0)
    |> then(fn denominator -> Double.divide(1.0, denominator) end)
  end

  defp standard_density(standard, :normal, scale) do
    standard
    |> Double.normal_density()
    |> Double.divide(scale)
  end

  # `e / (scale * f * f)` for `e = exp(-|z|)`, `f = 1 + e`, in that order.
  defp standard_density(standard, :logistic, scale) do
    power =
      standard
      |> Double.absolute()
      |> Double.negate()
      |> Double.exponential()

    sum = Double.add(1.0, power)
    Double.divide(power, Double.multiply(Double.multiply(scale, sum), sum))
  end

  # The distribution, its location and its scale, R's defaults 0 and 1.
  defp parameters(:probit), do: {:normal, 0.0, 1.0}
  defp parameters(:logit), do: {:logistic, 0.0, 1.0}

  defp parameters({:probability, :normal, options}),
    do: {:normal, Keyword.get(options, :mean, 0.0), Keyword.get(options, :sd, 1.0)}

  defp parameters({:probability, :logistic, options}),
    do: {:logistic, Keyword.get(options, :location, 0.0), Keyword.get(options, :scale, 1.0)}
end
