defmodule Scales.Transform.Log10 do
  @moduledoc false

  # The base-10 logarithm, R's `transform_log10()`. Use it through `Scales.Transform`.
  #
  # A positive number becomes its logarithm, zero minus infinity, as R's `log10(0)` is `-Inf`, and
  # a negative number missing, R's NaN; plus infinity stays itself. Its domain is R's, 1e-100 up,
  # so an axis reaching below 10^-100 finds its breaks from there.
  #
  # Its breaks are R's `breaks_log()`, five wanted (`Scales.Breaks.log/2`), found on the extent
  # turned back into data units and put back into log space. Its minor breaks are R's regular
  # ones in log space, and its labels the breaks in data units, plain decimals
  # (`Scales.Labels.plain/1`).

  @behaviour Scales.Transform

  alias Scales.{Breaks, Labels, MinorBreaks}

  @impl Scales.Transform
  def transform(_transformation, values), do: Enum.map(values, &log10/1)

  @impl Scales.Transform
  def inverse(_transformation, positions), do: Enum.map(positions, &power/1)

  @impl Scales.Transform
  def domain(_transformation), do: {-100.0, :infinity}

  # The breaks found on the extent in data units, then put back into log space.
  @impl Scales.Transform
  def breaks(_transformation, {low, high}, []) do
    {power(low), power(high)}
    |> Breaks.log()
    |> Enum.map(&log10/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(_transformation, breaks, _extent) do
    breaks
    |> Enum.map(&power/1)
    |> Labels.plain()
  end

  defp log10(value) when is_number(value) and value > 0, do: :math.log10(value)
  defp log10(value) when value == 0, do: :neg_infinity
  defp log10(:infinity), do: :infinity
  defp log10(_negative_or_missing), do: nil

  defp power(exponent), do: :math.pow(10.0, exponent)
end
