defmodule Giggly.Scale.Transform.Reciprocal do
  @moduledoc false

  # The reciprocal, R's `transform_reciprocal()`: one over each value, both ways. Use it through
  # `Giggly.Scale.Transform`.
  #
  # Zero becomes plus infinity, as R's `1/0` is `Inf`, and either infinity zero. Its domain is
  # every number, which R's transformed domain, zero wide, leaves unsquished. Its breaks are
  # extended Wilkinson's on the range in data units, a reciprocal's positions falling as they
  # rise; its minor breaks are R's regular ones on the breaks in that order, and its labels the
  # breaks in data units, plain decimals.

  @behaviour Giggly.Scale.Transform

  alias Giggly.Scale.{Breaks, Labels, MinorBreaks}

  @impl Giggly.Scale.Transform
  def transform(values), do: Enum.map(values, &reciprocal/1)

  @impl Giggly.Scale.Transform
  def inverse(positions), do: Enum.map(positions, &reciprocal/1)

  @impl Giggly.Scale.Transform
  def domain, do: {:neg_infinity, :infinity}

  @impl Giggly.Scale.Transform
  def breaks({low, high}) do
    [low, high]
    |> inverse()
    |> Enum.filter(&is_number/1)
    |> Enum.min_max()
    |> Breaks.extended()
    |> transform()
  end

  @impl Giggly.Scale.Transform
  def minor_breaks(breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Giggly.Scale.Transform
  def format(breaks, _extent) do
    breaks
    |> inverse()
    |> Labels.numbers()
  end

  defp reciprocal(value) when is_number(value) and value == 0, do: :infinity
  defp reciprocal(value) when is_number(value), do: 1 / value
  defp reciprocal(infinity) when infinity in [:infinity, :neg_infinity], do: 0.0
  defp reciprocal(_missing), do: nil
end
