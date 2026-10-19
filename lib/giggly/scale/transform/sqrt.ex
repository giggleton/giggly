defmodule Giggly.Scale.Transform.Sqrt do
  @moduledoc false

  # The square root, R's `transform_sqrt()`. Use it through `Giggly.Scale.Transform`.
  #
  # A number from zero up becomes its square root, a negative one missing, R's NaN; plus infinity
  # stays itself. Turned back, a position below zero is missing, as R's inverse,
  # `ifelse(x < 0, NA, x^2)`, makes it, though the domain, zero up, squishes an extent's ends there
  # first. Its breaks are extended Wilkinson's on the range in data units, its minor breaks R's
  # regular ones in square-root space, and its labels the breaks in data units, plain decimals.

  @behaviour Giggly.Scale.Transform

  alias Giggly.Scale.{Breaks, Labels, MinorBreaks}

  @impl Giggly.Scale.Transform
  def transform(values), do: Enum.map(values, &root/1)

  @impl Giggly.Scale.Transform
  def inverse(positions), do: Enum.map(positions, &square/1)

  @impl Giggly.Scale.Transform
  def domain, do: {0.0, :infinity}

  @impl Giggly.Scale.Transform
  def breaks({low, high}) do
    ends =
      [low, high]
      |> inverse()
      |> Enum.reject(&is_nil/1)

    case ends do
      [] ->
        []

      _placed ->
        ends
        |> Enum.min_max()
        |> Breaks.extended()
        |> transform()
    end
  end

  @impl Giggly.Scale.Transform
  def minor_breaks(breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Giggly.Scale.Transform
  def format(breaks, _extent) do
    breaks
    |> inverse()
    |> Labels.numbers()
  end

  defp root(value) when is_number(value) and value >= 0, do: :math.sqrt(value)
  defp root(:infinity), do: :infinity
  defp root(_negative_or_missing), do: nil

  defp square(position) when position < 0, do: nil
  defp square(position), do: position * position
end
