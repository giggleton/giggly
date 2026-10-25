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
  # implementation calls until it is classified. There are points (`Giggly.Geom.Point`),
  # rectangles (`Giggly.Geom.Rect`), bars (`Giggly.Geom.Bar`), which `geom_col()` draws with as
  # ggplot2's does and which are drawn as rectangles, as ggplot2's `GeomBar` is a `GeomRect`, paths
  # (`Giggly.Geom.Path`) and lines (`Giggly.Geom.Line`), which draw as paths once their rows are in
  # order, as ggplot2's `GeomLine` is a `GeomPath`, text (`Giggly.Geom.Text`), box plots
  # (`Giggly.Geom.Boxplot`), which draw their outliers as points, ribbons (`Giggly.Geom.Ribbon`)
  # and areas (`Giggly.Geom.Area`), which draw as ribbons from 0 to their y, as ggplot2's
  # `GeomArea` is a `GeomRibbon`, and smooths (`Giggly.Geom.Smooth`), each group a ribbon under a
  # line, as ggplot2's `GeomSmooth` draws one. A geom drawing lines places its rows with
  # `Giggly.Coord.munch/3`, which cuts them to follow the panel's curves.

  # A geom places its rows through the coordinate system and draws them as scene primitives, sizes
  # a mark with no width given from the spacing of its positions (`Giggly.Resolution`), writes a
  # text's label as R's `as.character()` writes it (`Giggly.AsCharacter`), measures the text it
  # draws (`Giggly.Font`), which the scene draws at the width measured, and mixes its default
  # colours from the theme's ink and paper (`Giggly.ColorOperations`).
  # It exports its kinds, whose structs a plot records and whose facts it checks a layer against,
  # and nothing they draw with: that is in their protocol implementations, which no boundary
  # exports.
  use Boundary,
    deps: [
      Giggly.Aesthetics,
      Giggly.AsCharacter,
      Giggly.ColorOperations,
      Giggly.Coord,
      Giggly.DataFrame,
      Giggly.Font,
      Giggly.Resolution,
      Giggly.Scene
    ],
    exports: [Area, Bar, Boxplot, Line, Path, Point, Rect, Ribbon, Smooth, Text]

  alias Giggly.{Coord, DataFrame, Scene}

  @typedoc "Whether each axis's scale is discrete or continuous."
  @type axis_kinds :: %{x: :continuous | :discrete, y: :continuous | :discrete}

  @typedoc """
  The layers' defaults a plot's complete theme gives, `Giggly.Theme`'s `geom`, ggplot2's
  `element_geom()`: its `ink` and `paper`, its lines' and borders' widths and line types, its
  text's family and size and its points' size and shape.
  """
  @type element :: %{required(atom()) => term()}

  # The aesthetics `geom` draws with, each with the value it takes where the layer neither maps nor
  # sets it, worked out from `element`, the layers' defaults the plot's complete theme gives:
  # ggplot2's `default_aes`, its `from_theme()` values read from the theme's `element_geom()`, in
  # the order it lists them, so the columns a layer's table gains end it as R's do. A value R gives
  # as `NA` is `nil`, the table's missing value.
  @doc false
  @spec default_aesthetics(t(), element()) :: keyword()
  def default_aesthetics(geom, element)

  # `frame` with each row given the extent `geom` draws it over, in data space, after the layer's
  # stat and before its position: ggplot2's `setup_data()`. `axis_kinds` says whether each axis is
  # discrete or continuous, which ggplot2's geoms read from a position's `mapped_discrete` class to
  # decide their orientation; a geom sees whether an axis is discrete, never its range. A geom that
  # draws a row at its x and y alone returns the frame as it is.
  @doc false
  @spec setup_data(t(), DataFrame.t(), axis_kinds()) :: DataFrame.t()
  def setup_data(geom, frame, axis_kinds)

  # The primitives `geom` draws `frame`'s rows with, in the panel that `panel_params` describes
  # under `coord`: ggplot2's `draw_panel()`.
  @doc false
  @spec draw_panel(t(), DataFrame.t(), Coord.t(), Coord.panel_params()) :: [Scene.primitive()]
  def draw_panel(geom, frame, coord, panel_params)

  # The primitives `geom` draws a legend's key with, in the key's cell, its aesthetics' values in
  # `key`, such as `%{alpha: 0.2}`, `nil` for none, and whether its layer's marks are horizontal,
  # `flipped_aes`, which the legend always gives: ggplot2's `draw_key`, each geom's glyph for what
  # it draws, handed the layer's `flipped_aes` as ggplot2 hands it the layer's params. The glyph is
  # placed by fractions of the cell and offsets in points, as grid places one by `npc` and absolute
  # units, so it is drawn right in a cell of any size: a legend sizes its keys to their glyphs
  # (`key_size/2`) before any is drawn.
  @doc false
  @spec draw_key(t(), %{optional(atom()) => term()}) :: [Scene.primitive()]
  def draw_key(geom, key)

  # The room, `{width, height}` in points, that the glyph `draw_key/2` draws for `key` needs in its
  # key: the width and height ggplot2's `draw_key` gives its glyph, or else, as its legend's
  # `set_key_size()` reads the key, its `size` and `linewidth` in millimetres added, a missing one
  # counting 0. A legend makes each key at least as big as the theme's key size.
  @doc false
  @spec key_size(t(), %{optional(atom()) => term()}) :: {float(), float()}
  def key_size(geom, key)
end
