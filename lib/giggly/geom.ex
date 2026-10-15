defprotocol Giggly.Geom do
  @moduledoc false

  # Geoms: how a layer's rows are drawn. A geom has a say twice. While the plot is assembled, after
  # the layer's stat and before its position, `setup_data/2` gives each row the extent it will be
  # drawn over in data space, as ggplot2's `setup_data()` turns a bar's x and y into its edges, so
  # the position can stack or dodge those edges and the scales, trained again after the position,
  # cover them. When the plot is rendered, each layer's geom draws the layer's rows in each panel
  # as `Giggly.Scene` primitives, placing them through the panel's coordinate system
  # (`Giggly.Coord.transform/3`), which it is handed with the panel's params as ggplot2's
  # `draw_panel()` is, and never reading a scale's range, a pixel, or the facet that put the rows in
  # the panel.
  #
  # A layer records its geom as a struct of its kind. Each geom is one module holding everything
  # about it, as ggplot2's `GeomPoint` does: its struct, whose fields are the geom's parameters; the
  # facts about it that a plot checks a layer's mapping against when the layer is added
  # (`accepted_aesthetics/0`, `required_aesthetics/0`); and its drawing, in a `defimpl Giggly.Geom`
  # whose first line classifies it into this boundary, since boundary checks nothing a protocol
  # implementation calls until it is classified. There are points (`Giggly.Geom.Point`) and bars
  # (`Giggly.Geom.Bar`), which `geom_col()` draws with as ggplot2's does.

  # A geom places its rows through the coordinate system and draws them as scene primitives, and
  # sizes a mark with no width given from the spacing of its positions (`Giggly.Resolution`).
  # It exports its kinds, whose structs a plot records and whose facts it checks a layer against,
  # and nothing they draw with: that is in their protocol implementations, which no boundary
  # exports.
  use Boundary,
    deps: [Giggly.Coord, Giggly.DataFrame, Giggly.Resolution, Giggly.Scene],
    exports: [Bar, Point]

  alias Giggly.{Coord, DataFrame, Scene}

  # `frame` with each row given the extent `geom` draws it over, in data space, after the layer's
  # stat and before its position: ggplot2's `setup_data()`. A geom that draws a row at its x and y
  # alone returns the frame as it is.
  @doc false
  @spec setup_data(t(), DataFrame.t()) :: DataFrame.t()
  def setup_data(geom, frame)

  # The primitives `geom` draws `frame`'s rows with, in the panel that `panel_params` describes
  # under `coord`: ggplot2's `draw_panel()`.
  @doc false
  @spec draw_panel(t(), DataFrame.t(), Coord.t(), Coord.panel_params()) :: [Scene.primitive()]
  def draw_panel(geom, frame, coord, panel_params)
end
