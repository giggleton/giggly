defmodule Scales.Transform.Modulus do
  @moduledoc false

  # The modulus transformation, R's `transform_modulus(p, offset)`: `{:modulus, exponent}` and
  # `{:modulus, exponent, offset: offset}`, an exponent any number and an offset from 1 up, R's
  # default 1, below which it no longer rises. Use it through `Scales.Transform`.
  #
  # A value becomes `sign(x) * ((|x| + offset)^exponent - 1) / exponent`, or
  # `sign(x) * log(|x| + offset)` for an exponent that counts as zero (`Transform.Power`), so a
  # zero is zero, its sign R's IEEE product's, and an offset above 1 leaves a gap either side of
  # it; turned back, `sign(x) * ((|x| * exponent + 1)^(1 / exponent) - offset)`, or
  # `sign(x) * (exp(|x|) - offset)`, wherever it is, as R's. Its domain is every number; a negative
  # exponent bounds its values, and an axis squished there (`Scales.Transform.squish/2`). Its
  # derivatives are R's, `(|x| + offset)^(exponent - 1)` and
  # `(|x| * exponent + 1)^(1 / exponent - 1)`, or `1 / (|x| + offset)` and `exp(|x|)`, and 1 at a
  # missing value where the power is 0, as R's `NA^0`. Its breaks, minor breaks and labels are
  # `Transform.Power`'s.

  @behaviour Scales.Transform

  alias Scales.{Double, MinorBreaks}
  alias Scales.Transform.Power

  @impl Scales.Transform
  def transform(transformation, values) do
    {exponent, offset} = parameters(transformation)
    Enum.map(values, fn value -> modulus(value, exponent, offset) end)
  end

  @impl Scales.Transform
  def inverse(transformation, positions) do
    {exponent, offset} = parameters(transformation)
    Enum.map(positions, fn position -> inverse_modulus(position, exponent, offset) end)
  end

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  @impl Scales.Transform
  def derivative(transformation, values) do
    {exponent, offset} = parameters(transformation)

    Enum.map(values, fn
      nil ->
        Power.missing_derivative(exponent, :transform)

      value ->
        value
        |> Double.absolute()
        |> Double.add(offset)
        |> Power.derivative(exponent)
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(transformation, positions) do
    {exponent, _offset} = parameters(transformation)

    Enum.map(positions, fn
      nil ->
        Power.missing_derivative(exponent, :inverse)

      position ->
        position
        |> Double.absolute()
        |> Power.inverse_derivative(exponent)
    end)
  end

  @impl Scales.Transform
  def breaks(transformation, extent, options) do
    {exponent, offset} = parameters(transformation)

    Power.breaks(
      extent,
      fn position -> inverse_modulus(position, exponent, offset) end,
      fn value -> modulus(value, exponent, offset) end,
      options
    )
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(transformation, breaks, extent, options) do
    {exponent, offset} = parameters(transformation)

    Power.format(
      breaks,
      extent,
      fn position -> inverse_modulus(position, exponent, offset) end,
      fn value -> modulus(value, exponent, offset) end,
      options
    )
  end

  defp modulus(nil, _exponent, _offset), do: nil

  defp modulus(value, exponent, offset) do
    power =
      value
      |> Double.absolute()
      |> Double.add(offset)
      |> Power.transformed(exponent)

    value
    |> sign()
    |> Double.multiply(power)
  end

  defp inverse_modulus(nil, _exponent, _offset), do: nil

  defp inverse_modulus(position, exponent, offset) do
    shifted =
      position
      |> Double.absolute()
      |> Power.inverted(exponent)
      |> Double.subtract(offset)

    position
    |> sign()
    |> Double.multiply(shifted)
  end

  # R's `sign()`: 1, -1, or 0 for either zero, NaN's NaN; plus infinity, an atom, sorts above
  # every number, so it is above 0.
  defp sign(:nan), do: :nan
  defp sign(:neg_infinity), do: -1.0
  defp sign(value) when value > 0, do: 1.0
  defp sign(value) when value < 0, do: -1.0
  defp sign(_zero), do: 0.0

  # The exponent and the offset, R's default 1.
  defp parameters({:modulus, exponent}), do: {exponent, 1.0}
  defp parameters({:modulus, exponent, [offset: offset]}), do: {exponent, offset}
end
