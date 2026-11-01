defmodule Scales.Transform.Log1p do
  @moduledoc false

  # The logarithm of one plus each value, R's `transform_log1p()`. Use it through
  # `Scales.Transform`.
  #
  # A value from minus one up becomes `log(1 + x)`, accurate near zero
  # (`Scales.Double.logarithm_of_one_plus/1`), minus one minus infinity and a value below it or
  # minus infinity NaN, as R's `log1p()`; a zero of either sign becomes `0.0`, as R's does on a
  # vector. Turned back, a position is `exp(x) - 1` (`Scales.Double.exponential_minus_one/1`),
  # minus infinity's -1. Its domain is R's, from `-1 + .Machine$double.eps`. Its derivatives are
  # R's, `1 / (1 + x)` and `exp(x)`, in R's IEEE arithmetic (`Scales.Double`).
  #
  # Its breaks are extended Wilkinson's on the range in data units, its minor breaks R's regular
  # ones in log space, and its labels the breaks in data units, plain decimals of each rounded to
  # 14 significant digits (`Scales.Labels.plain_round_tripped/1`).

  @behaviour Scales.Transform

  alias Scales.{Breaks, Double, Labels, MinorBreaks}

  # R's `-1 + .Machine$double.eps`.
  @domain_low -1 + 2.220446049250313e-16

  @impl Scales.Transform
  def transform(_transformation, values), do: Enum.map(values, &logarithm_of_one_plus/1)

  @impl Scales.Transform
  def inverse(_transformation, positions),
    do: Enum.map(positions, &Double.exponential_minus_one/1)

  @impl Scales.Transform
  def domain(_transformation), do: {@domain_low, :infinity}

  @impl Scales.Transform
  def derivative(_transformation, values) do
    Enum.map(values, fn
      nil -> nil
      value -> Double.divide(1.0, Double.add(1.0, value))
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(_transformation, positions) do
    Enum.map(positions, fn
      nil -> nil
      position -> Double.exponential(position)
    end)
  end

  @impl Scales.Transform
  def breaks(_transformation, {low, high}, options) do
    {Double.exponential_minus_one(low), Double.exponential_minus_one(high)}
    |> Breaks.extended(options)
    |> Enum.map(&logarithm_of_one_plus/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(_transformation, breaks, _extent, _options) do
    breaks
    |> Enum.map(&Double.exponential_minus_one/1)
    |> Labels.plain_round_tripped()
  end

  defp logarithm_of_one_plus(nil), do: nil
  defp logarithm_of_one_plus(value), do: Double.logarithm_of_one_plus(value)
end
