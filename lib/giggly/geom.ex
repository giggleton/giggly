defprotocol Giggly.Geom do
  @moduledoc false

  # Geoms: how a layer's rows are drawn. When a plot is rendered, each layer's geom draws the
  # layer's rows in each panel as `Giggly.Scene` primitives, placing them through the panel's
  # coordinate system (`Giggly.Coord.transform/3`), which it is handed with the panel's params as
  # ggplot2's `draw_panel()` is, and never reading a scale's range, a pixel, or the facet that put
  # the rows in the panel.
  #
  # A layer records its geom as a struct of its kind. Each geom is one module holding everything
  # about it, as ggplot2's `GeomPoint` does: its struct, whose fields are the geom's parameters; the
  # facts about it that a plot checks a layer's mapping against when the layer is added
  # (`accepted_aesthetics/0`, `required_aesthetics/0`); and its drawing, in a `defimpl Giggly.Geom`
  # whose first line classifies it into this boundary, since boundary checks nothing a protocol
  # implementation calls until it is classified. There is one so far, points
  # (`Giggly.Geom.Point`).

  # A geom places its rows through the coordinate system and draws them as scene primitives.
  # It exports its kinds, whose structs a plot records and whose facts it checks a layer against,
  # and nothing they draw with: that is in their protocol implementations, which no boundary
  # exports.
  use Boundary, deps: [Giggly.Coord, Giggly.DataFrame, Giggly.Scene], exports: [Point]

  alias Giggly.{Coord, DataFrame, Scene}

  # The primitives `geom` draws `frame`'s rows with, in the panel that `panel_params` describes
  # under `coord`: ggplot2's `draw_panel()`.
  @doc false
  @spec draw_panel(t(), DataFrame.t(), Coord.t(), Coord.panel_params()) :: [Scene.primitive()]
  def draw_panel(geom, frame, coord, panel_params)
end
