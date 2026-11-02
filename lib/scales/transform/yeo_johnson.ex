defmodule Scales.Transform.YeoJohnson do
  @moduledoc false

  # The Yeo-Johnson transformation, R's `transform_yj(p)`: `{:yj, exponent}`, any number. Use it
  # through `Scales.Transform`.
  #
  # A value from zero up becomes `((x + 1)^exponent - 1) / exponent` (`Transform.Power`), or
  # `log1p(x)` for an exponent that counts as zero, and one below it
  # `-((1 - x)^(2 - exponent) - 1) / (2 - exponent)`, or `-log1p(-x)` where `2 - exponent` counts
  # as zero, as scales' documentation writes the four; either zero becomes `0.0`, as R's does.
  # Turned back, a position from zero up is `(x * exponent + 1)^(1 / exponent) - 1`, or `expm1(x)`,
  # and one below it `1 - (1 - (2 - exponent) * x)^(1 / (2 - exponent))`, or `1 - exp(-x)`, as R
  # gives them. NaN and a missing value are missing, as R's are `NA`. Its domain is every number; an
  # exponent below 0 or above 2 bounds its values on one side, and an axis squished there
  # (`Scales.Transform.squish/2`). Its derivatives are R's, `(x + 1)^(exponent - 1)` and
  # `(1 - x)^(1 - exponent)`, and their inverses' `(x * exponent + 1)^(1 / exponent - 1)` and
  # `(1 - (2 - exponent) * x)^(1 / (2 - exponent) - 1)`, a quotient or an exponential where the
  # exponent or `2 - exponent` counts as zero, as `Transform.Power`'s; at an exponent of 2 the
  # inverse's below zero is `exp(-x)`, the slope, where R's fails (a typo in scales 1.4.0). Its
  # breaks, minor breaks and labels are `Transform.Power`'s.

  @behaviour Scales.Transform

  alias Scales.{Double, MinorBreaks}
  alias Scales.Transform.Power

  @impl Scales.Transform
  def transform({:yj, exponent}, values),
    do: Enum.map(values, fn value -> yeo_johnson(value, exponent) end)

  @impl Scales.Transform
  def inverse({:yj, exponent}, positions),
    do: Enum.map(positions, fn position -> inverse_yeo_johnson(position, exponent) end)

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  # Minus infinity, an atom, sorts above every number, so it is caught before the comparisons.
  @impl Scales.Transform
  def derivative({:yj, exponent}, values) do
    Enum.map(values, fn
      value when value in [nil, :nan] ->
        nil

      value when value == :neg_infinity or value < 0 ->
        1.0
        |> Double.subtract(value)
        |> negative_derivative(exponent)

      value ->
        value
        |> Double.add(1.0)
        |> Power.derivative(exponent)
    end)
  end

  @impl Scales.Transform
  def inverse_derivative({:yj, exponent}, positions) do
    Enum.map(positions, fn
      position when position in [nil, :nan] ->
        nil

      position when position == :neg_infinity or position < 0 ->
        position
        |> Double.negate()
        |> Power.inverse_derivative(2 - exponent)

      position ->
        Power.inverse_derivative(position, exponent)
    end)
  end

  @impl Scales.Transform
  def breaks({:yj, exponent}, extent, options) do
    Power.breaks(
      extent,
      fn position -> inverse_yeo_johnson(position, exponent) end,
      fn value -> yeo_johnson(value, exponent) end,
      options
    )
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format({:yj, exponent}, breaks, extent, options) do
    Power.format(
      breaks,
      extent,
      fn position -> inverse_yeo_johnson(position, exponent) end,
      fn value -> yeo_johnson(value, exponent) end,
      options
    )
  end

  # `(1 - x)^(1 - exponent)`, its power `1 - exponent` as R's, which `(2 - exponent) - 1` misses
  # in the last bit, or `1 / (1 - x)` where `2 - exponent` counts as zero.
  defp negative_derivative(complement_base, exponent) do
    if Power.near_zero?(2 - exponent),
      do: Double.divide(1.0, complement_base),
      else: Double.power(complement_base, 1 - exponent)
  end

  defp yeo_johnson(value, _exponent) when value in [nil, :nan], do: nil
  defp yeo_johnson(value, _exponent) when value == 0, do: 0.0

  defp yeo_johnson(value, exponent) when value == :neg_infinity or value < 0 do
    value
    |> Double.negate()
    |> one_plus_power(2 - exponent)
    |> Double.negate()
  end

  defp yeo_johnson(value, exponent), do: one_plus_power(value, exponent)

  # `((1 + x)^exponent - 1) / exponent`, or `log1p(x)`.
  defp one_plus_power(value, exponent) do
    if Power.near_zero?(exponent) do
      Double.logarithm_of_one_plus(value)
    else
      value
      |> Double.add(1.0)
      |> Power.transformed(exponent)
    end
  end

  defp inverse_yeo_johnson(position, _exponent) when position in [nil, :nan], do: nil

  defp inverse_yeo_johnson(position, exponent) when position == :neg_infinity or position < 0 do
    power =
      position
      |> Double.negate()
      |> Power.inverted(2 - exponent)

    Double.subtract(1.0, power)
  end

  defp inverse_yeo_johnson(position, exponent) do
    if Power.near_zero?(exponent) do
      Double.exponential_minus_one(position)
    else
      position
      |> Power.inverted(exponent)
      |> Double.subtract(1.0)
    end
  end
end
