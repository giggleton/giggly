defmodule Scales.Transform.Log10 do
  @moduledoc false

  # The base-10 logarithm, R's `transform_log10()`. Use it through `Scales.Transform`.
  #
  # A positive number becomes its logarithm, either zero minus infinity, as R's `log10(0)` is
  # `-Inf`, and a negative number or minus infinity NaN, as R's; plus infinity and NaN stay
  # themselves. Its domain is R's, 1e-100 up, so an axis reaching below 10^-100 finds its breaks
  # from there. Its derivatives are R's, `1 / x / log(10)` and `10^x * log(10)`, in R's IEEE
  # arithmetic (`Scales.Double`).
  #
  # Its breaks are R's `breaks_log()`, five wanted unless a caller says (`Scales.Breaks.log/2`),
  # found on the extent turned back into data units and put back into log space. Its minor breaks are R's regular
  # ones in log space, and its labels the breaks in data units, plain decimals
  # (`Scales.Labels.plain/1`).

  @behaviour Scales.Transform

  alias Scales.{Breaks, Double, Labels, MinorBreaks}

  @natural_log_of_ten :math.log(10)

  @impl Scales.Transform
  def transform(_transformation, values), do: Enum.map(values, &log10/1)

  @impl Scales.Transform
  def inverse(_transformation, positions), do: Enum.map(positions, &power/1)

  @impl Scales.Transform
  def domain(_transformation), do: {1.0e-100, :infinity}

  @impl Scales.Transform
  def derivative(_transformation, values) do
    Enum.map(values, fn
      nil ->
        nil

      value ->
        1.0
        |> Double.divide(value)
        |> Double.divide(@natural_log_of_ten)
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(_transformation, positions) do
    Enum.map(positions, fn
      nil ->
        nil

      position ->
        position
        |> power()
        |> Double.multiply(@natural_log_of_ten)
    end)
  end

  # The breaks found on the extent in data units, then put back into log space.
  @impl Scales.Transform
  def breaks(_transformation, {low, high}, options) do
    {power(low), power(high)}
    |> Breaks.log(options)
    |> Enum.map(&log10/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(_transformation, breaks, _extent, _options) do
    breaks
    |> Enum.map(&power/1)
    |> Labels.plain()
  end

  defp log10(value) when is_number(value) and value > 0, do: :math.log10(value)
  defp log10(value) when value == 0, do: :neg_infinity
  defp log10(value) when value in [nil, :infinity], do: value
  defp log10(_negative_or_nan), do: :nan

  # Ten to a power, an infinity past the largest double, as R's `10^x`.
  defp power(:neg_infinity), do: 0.0
  defp power(exponent) when exponent in [:infinity, :nan], do: exponent

  defp power(exponent) do
    :math.pow(10.0, exponent)
  rescue
    ArithmeticError -> :infinity
  end
end
