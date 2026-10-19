defmodule Giggly.Scale.Transform.Identity do
  @moduledoc false

  # The identity transformation, R's `transform_identity()`: every value as it is. It is what a
  # continuous scale records when nothing transforms its axis. Use it through
  # `Giggly.Scale.Transform`.
  #
  # Its axis takes R's default breaks for a transformation, extended Wilkinson
  # (`Giggly.Scale.Breaks`), and its default minor breaks, midway between them
  # (`Giggly.Scale.MinorBreaks`), and writes the breaks as plain decimals (`Giggly.Scale.Labels`).

  @behaviour Giggly.Scale.Transform

  alias Giggly.Scale.{Breaks, Labels, MinorBreaks}

  @impl Giggly.Scale.Transform
  def transform(values), do: values

  @impl Giggly.Scale.Transform
  def inverse(positions), do: positions

  @impl Giggly.Scale.Transform
  def domain, do: {:neg_infinity, :infinity}

  @impl Giggly.Scale.Transform
  def breaks(extent), do: Breaks.extended(extent)

  @impl Giggly.Scale.Transform
  def minor_breaks(breaks, extent), do: MinorBreaks.regular(breaks, extent)

  # A number's label is its own, whatever the extent.
  @impl Giggly.Scale.Transform
  def format(breaks, _extent), do: Labels.numbers(breaks)
end
