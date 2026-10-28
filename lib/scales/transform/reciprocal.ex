defmodule Scales.Transform.Reciprocal do
  @moduledoc false

  # The reciprocal, R's `transform_reciprocal()`: one over each value, both ways. Use it through
  # `Scales.Transform`.
  #
  # Zero becomes plus infinity, as R's `1/0` is `Inf`, and either infinity zero. Its domain is
  # every number, which R's transformed domain, zero wide, leaves unsquished. Its breaks are
  # extended Wilkinson's on the range in data units, a reciprocal's positions falling as they
  # rise; its minor breaks are R's regular ones on the breaks in that order, and its labels the
  # breaks in data units, plain decimals.

  @behaviour Scales.Transform

  alias Scales.{Breaks, Format, MinorBreaks}

  @impl Scales.Transform
  def transform(_transformation, values), do: Enum.map(values, &reciprocal/1)

  @impl Scales.Transform
  def inverse(_transformation, positions), do: Enum.map(positions, &reciprocal/1)

  @impl Scales.Transform
  def domain(_transformation), do: {:neg_infinity, :infinity}

  @impl Scales.Transform
  def breaks(_transformation, {low, high}) do
    [low, high]
    |> Enum.map(&reciprocal/1)
    |> Enum.filter(&is_number/1)
    |> Enum.min_max()
    |> Breaks.extended()
    |> Enum.map(&reciprocal/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(_transformation, breaks, _extent) do
    breaks
    |> Enum.map(&reciprocal/1)
    |> Format.plain()
  end

  defp reciprocal(value) when is_number(value) and value == 0, do: :infinity
  defp reciprocal(value) when is_number(value), do: 1 / value
  defp reciprocal(infinity) when infinity in [:infinity, :neg_infinity], do: 0.0
  defp reciprocal(_missing), do: nil
end
