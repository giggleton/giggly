defmodule Scales.Transform.Exp do
  @moduledoc false

  # A base above 1 to the power of each value, R's `transform_exp(base)`: `:exp` in base e and
  # `{:exp, base}`. Use it through `Scales.Transform`.
  #
  # A value becomes the base to its power, R's `base^x` (`Scales.Double.power/2`), so `:exp`'s is
  # `exp(1)^x`, which lands a bit away from `exp(x)` on some, as R's does; minus infinity's is
  # zero, and a power past the largest double plus infinity. Turned back, a position is its
  # logarithm in the base, as R's `log(x, base)` (`Scales.Double.logarithm/2`), zero's minus
  # infinity and one below zero NaN. Its domain is every number. Its derivatives are R's,
  # `base^x * log(base)` and `1 / x / log(base)`, in R's IEEE arithmetic (`Scales.Double`).
  #
  # Its breaks are extended Wilkinson's on the range in data units, where R's `extended_breaks()`
  # finds them, not `breaks_exp()`: an extent reaching zero or below has one finite end there,
  # which R's breaks give five times. Its minor breaks are R's regular ones in transformed space,
  # and its labels the breaks in data units, plain decimals of each rounded to 14 significant
  # digits (`Scales.Labels.plain_round_tripped/1`).

  @behaviour Scales.Transform

  alias Scales.{Breaks, Double, Labels, MinorBreaks}

  @impl Scales.Transform
  def transform(transformation, values) do
    base = base(transformation)

    Enum.map(values, fn
      nil -> nil
      value -> Double.power(base, value)
    end)
  end

  @impl Scales.Transform
  def inverse(transformation, positions) do
    base = base(transformation)
    Enum.map(positions, fn position -> Double.logarithm(position, base) end)
  end

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  @impl Scales.Transform
  def derivative(transformation, values) do
    base = base(transformation)
    natural_log_of_base = :math.log(base)

    Enum.map(values, fn
      nil ->
        nil

      value ->
        base
        |> Double.power(value)
        |> Double.multiply(natural_log_of_base)
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(transformation, positions) do
    natural_log_of_base =
      transformation
      |> base()
      |> :math.log()

    Enum.map(positions, fn
      nil ->
        nil

      position ->
        1.0
        |> Double.divide(position)
        |> Double.divide(natural_log_of_base)
    end)
  end

  # The extent's ends turned back, an end at zero or below dropped, as R's `extended_breaks()`
  # drops its NaN and minus infinity.
  @impl Scales.Transform
  def breaks(transformation, {low, high}, options) do
    base = base(transformation)

    [low, high]
    |> Enum.map(fn position -> Double.logarithm(position, base) end)
    |> Enum.filter(&is_number/1)
    |> Enum.min_max()
    |> Breaks.extended(options)
    |> Enum.map(fn break -> Double.power(base, break) end)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(transformation, breaks, _extent, _options) do
    base = base(transformation)

    breaks
    |> Enum.map(fn break -> Double.logarithm(break, base) end)
    |> Labels.plain_round_tripped()
  end

  # R's `exp(1)`, the base of `:exp`.
  defp base(:exp), do: :math.exp(1)
  defp base({:exp, base}), do: base
end
