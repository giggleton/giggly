defmodule Scales.Transform.Sqrt do
  @moduledoc false

  # The square root, R's `transform_sqrt()`. Use it through `Scales.Transform`.
  #
  # A number from zero up becomes its square root, a negative one missing, R's NaN; plus infinity
  # stays itself. Turned back, a position is squared; R's inverse makes one below zero missing,
  # `ifelse(x < 0, NA, x^2)`, but the domain, zero up, squishes an extent's ends there before
  # breaks are found, and no break falls below it, so none reaches the inverse here. Its breaks are
  # extended Wilkinson's on the range in data units, its minor breaks R's regular ones in
  # square-root space, and its labels the breaks in data units, plain decimals.

  @behaviour Scales.Transform

  alias Scales.{Breaks, Labels, MinorBreaks}

  @impl Scales.Transform
  def transform(_transformation, values), do: Enum.map(values, &root/1)

  @impl Scales.Transform
  def inverse(_transformation, positions), do: Enum.map(positions, &squared/1)

  @impl Scales.Transform
  def domain(_transformation), do: {0.0, :infinity}

  @impl Scales.Transform
  def breaks(_transformation, {low, high}, options) do
    [low, high]
    |> Enum.map(&squared/1)
    |> Enum.min_max()
    |> Breaks.extended(options)
    |> Enum.map(&root/1)
  end

  @impl Scales.Transform
  def minor_breaks(_transformation, breaks, extent), do: MinorBreaks.regular(breaks, extent)

  @impl Scales.Transform
  def format(_transformation, breaks, _extent) do
    breaks
    |> Enum.map(&squared/1)
    |> Labels.plain()
  end

  defp root(value) when is_number(value) and value >= 0, do: :math.sqrt(value)
  defp root(:infinity), do: :infinity
  defp root(_negative_or_missing), do: nil

  defp squared(position), do: position * position
end
