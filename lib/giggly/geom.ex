defmodule Giggly.Geom do
  @moduledoc false

  # Geoms: how a layer's rows are drawn. When a plot is rendered, each layer's geom draws the
  # layer's rows in each panel as `Giggly.Scene` primitives, placing them through the panel's
  # coordinate system (`Giggly.Coord.transform/2`) and never reading a scale's range, a pixel, or
  # the facet that put the rows in the panel.
  #
  # A layer records its geom by name, and the name is resolved here; each geom is a module
  # implementing this behaviour. There is one so far, points (`Giggly.Geom.Point`).

  # A geom places its rows through the coordinate system and draws them as scene primitives.
  use Boundary, deps: [Giggly.Coord, Giggly.DataFrame, Giggly.Scene], exports: []

  alias Giggly.{Coord, DataFrame, Geom, Scene}

  @typedoc "A geom's name, as a layer records it."
  @type name :: :point

  # The primitives that draw one panel's rows, given that panel's params.
  @doc false
  @callback draw_panel(DataFrame.t(), Coord.panel_params()) :: [Scene.primitive()]

  # The primitives the geom named `name` draws `frame`'s rows with, in the panel `panel_params`
  # describes: ggplot2's `draw_panel()`.
  @doc false
  @spec draw_panel(DataFrame.t(), name(), Coord.panel_params()) :: [Scene.primitive()]
  def draw_panel(frame, :point, panel_params), do: Geom.Point.draw_panel(frame, panel_params)
end
