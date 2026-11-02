defmodule Scales.Transform.Log do
  @moduledoc false

  # The logarithm in a base above 1, R's `transform_log(base)`, `transform_log2()` and
  # `transform_log10()`: `:log` in base e, `:log2`, `:log10` and `{:log, base}`. Use it through
  # `Scales.Transform`.
  #
  # A positive number becomes its logarithm, in base 2 and 10 by their own functions and in any
  # other by the ratio of natural ones, as R's `log(x, base)` (`Scales.Double.logarithm/2`), so
  # `{:log, 10}` places every value where `:log10` does; either zero minus infinity, as R's
  # `log(0)` is `-Inf`, and a negative number or minus infinity NaN, as R's; plus infinity and NaN
  # stay themselves. Turned back, a position is the base to its power, R's `base^x`, so `:log`'s
  # is `exp(1)^x`, which lands a bit away from `exp(x)` on some, as R's does. Its domain is R's,
  # 1e-100 up in every base. Its derivatives are R's, `1 / x / log(base)` and
  # `base^x * log(base)`, in R's IEEE arithmetic (`Scales.Double`).
  #
  # Its breaks are R's `breaks_log(base = base)`, five wanted unless a caller says
  # (`Scales.Breaks.log/2`), found on the extent turned back into data units and put back into
  # log space, so `:log`'s are powers of e. Its minor breaks are R's regular ones in log space, and
  # its labels the breaks in data units, plain decimals (`Scales.Labels.plain/1`), where R writes
  # them with `format()`.

  @behaviour Scales.Transform

  alias Scales.{Breaks, Double, Labels, MinorBreaks}

  @impl Scales.Transform
  def transform(transformation, values) do
    base = base(transformation)
    Enum.map(values, fn value -> logarithm(value, base) end)
  end

  @impl Scales.Transform
  def inverse(transformation, positions) do
    base = base(transformation)
    Enum.map(positions, fn position -> Double.power(base, position) end)
  end

  @impl Scales.Transform
  def domain(_transformation), do: {1.0e-100, :infinity}

  @impl Scales.Transform
  def derivative(transformation, values) do
    natural_log_of_base =
      transformation
      |> base()
      |> :math.log()

    Enum.map(values, fn
      nil ->
        nil

      value ->
        1.0
        |> Double.divide(value)
        |> Double.divide(natural_log_of_base)
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(transformation, positions) do
    base = base(transformation)
    natural_log_of_base = :math.log(base)

    Enum.map(positions, fn
      nil ->
        nil

      position ->
        base
        |> Double.power(position)
        |> Double.multiply(natural_log_of_base)
    end)
  end

  # The breaks found on the extent in data units, then put back into log space.
  @impl Scales.Transform
  def breaks(transformation, {low, high}, options) do
    base = base(transformation)

    {Double.power(base, low), Double.power(base, high)}
    |> Breaks.log([{:base, base} | options])
    |> Enum.map(fn break -> logarithm(break, base) end)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(transformation, breaks, _extent, _options) do
    base = base(transformation)

    breaks
    |> Enum.map(fn break -> Double.power(base, break) end)
    |> Labels.plain()
  end

  defp logarithm(nil, _base), do: nil
  defp logarithm(value, base), do: Double.logarithm(value, base)

  # R's `exp(1)`, the base of `:log`.
  defp base(:log), do: :math.exp(1)
  defp base(:log2), do: 2
  defp base(:log10), do: 10
  defp base({:log, base}), do: base
end
