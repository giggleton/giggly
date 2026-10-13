defmodule Giggly.Scale.Transform.Identity do
  @moduledoc """
  The identity transformation, R's `transform_identity()`: every value as it is. It is what a
  continuous scale records when nothing transforms its axis. Use it through
  `Giggly.Scale.Transform`.

  Its axis takes R's default breaks for a transformation, extended Wilkinson
  (`Giggly.Scale.Breaks`), and writes them as plain decimals (`Giggly.Scale.Labels`).
  """

  @behaviour Giggly.Scale.Transform

  alias Giggly.Scale.{Breaks, Labels}

  @impl Giggly.Scale.Transform
  def transform(values), do: values

  @impl Giggly.Scale.Transform
  def breaks(extent), do: Breaks.extended(extent)

  @impl Giggly.Scale.Transform
  def format(breaks), do: Labels.numbers(breaks)
end
