defmodule Scales.Transform.BoxCox do
  @moduledoc false

  # The Box-Cox transformation, R's `transform_boxcox(p, offset)`: `{:boxcox, exponent}` and
  # `{:boxcox, exponent, offset: offset}`, an exponent any number and an offset from 0 up, R's
  # default 0. Use it through `Scales.Transform`.
  #
  # A value becomes `((x + offset)^exponent - 1) / exponent`, or `log(x + offset)` for an
  # exponent that counts as zero (`Transform.Power`), and one below minus the offset, minus
  # infinity among them, NaN, as a logarithm's negatives are, where R refuses the whole vector;
  # turned back, `(x * exponent + 1)^(1 / exponent) - offset`, or `exp(x) - offset`, wherever
  # it is, as R's. Its domain is R's, from 0 whatever the offset, so an axis finds no break below
  # 0 where values from minus the offset to 0 still transform (design-log §4, the entry beginning
  # "Box-Cox's domain"). Its derivatives are R's, `(x + offset)^(exponent - 1)` and
  # `(x * exponent + 1)^(1 / exponent - 1)`, or `1 / (x + offset)` and `exp(x)`, unchecked
  # below the domain as R's are, and 1 at a missing value where the power is 0, as R's `NA^0`.
  # Its breaks, minor breaks and labels are `Transform.Power`'s.

  @behaviour Scales.Transform

  alias Scales.{Double, MinorBreaks}
  alias Scales.Transform.Power

  @impl Scales.Transform
  def transform(transformation, values) do
    {exponent, offset} = parameters(transformation)
    Enum.map(values, fn value -> box_cox(value, exponent, offset) end)
  end

  @impl Scales.Transform
  def inverse(transformation, positions) do
    {exponent, offset} = parameters(transformation)
    Enum.map(positions, fn position -> inverse_box_cox(position, exponent, offset) end)
  end

  @impl Scales.Transform
  def domain(_transformation), do: {0.0, :infinity}

  @impl Scales.Transform
  def derivative(transformation, values) do
    {exponent, offset} = parameters(transformation)

    Enum.map(values, fn
      nil ->
        Power.missing_derivative(exponent)

      value ->
        value
        |> Double.add(offset)
        |> Power.derivative(exponent)
    end)
  end

  @impl Scales.Transform
  def inverse_derivative(transformation, positions) do
    {exponent, _offset} = parameters(transformation)

    Enum.map(positions, fn
      nil -> Power.missing_derivative(exponent)
      position -> Power.inverse_derivative(position, exponent)
    end)
  end

  @impl Scales.Transform
  def breaks(transformation, extent, options) do
    {exponent, offset} = parameters(transformation)

    Power.breaks(
      extent,
      fn position -> inverse_box_cox(position, exponent, offset) end,
      fn value -> box_cox(value, exponent, offset) end,
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
      fn position -> inverse_box_cox(position, exponent, offset) end,
      fn value -> box_cox(value, exponent, offset) end,
      options
    )
  end

  defp box_cox(nil, _exponent, _offset), do: nil

  defp box_cox(value, exponent, offset) do
    shifted = Double.add(value, offset)

    if shifted == :neg_infinity or (is_number(shifted) and shifted < 0),
      do: :nan,
      else: Power.transformed(shifted, exponent)
  end

  defp inverse_box_cox(nil, _exponent, _offset), do: nil

  defp inverse_box_cox(position, exponent, offset) do
    position
    |> Power.inverted(exponent)
    |> Double.subtract(offset)
  end

  # The exponent and the offset, R's default 0.
  defp parameters({:boxcox, exponent}), do: {exponent, 0.0}
  defp parameters({:boxcox, exponent, [offset: offset]}), do: {exponent, offset}
end
