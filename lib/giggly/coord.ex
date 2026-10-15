defprotocol Giggly.Coord do
  @moduledoc false

  # Coordinate systems: the only route from positions on the scales to the unit panel.
  #
  # After the stats and positions have run, the assembly asks the plot's coordinate system for each
  # panel's params, from the extent of the panel's x and y scales (`Giggly.Scale.dimension/1`) and
  # each axis's breaks and minor breaks on that extent (`Giggly.Scale.breaks/2`,
  # `Giggly.Scale.minor_breaks/3`). When the plot is rendered, each geom is handed the coordinate
  # system and its panel's params, and hands both with its rows to `transform/3`, which places
  # every x-family and y-family column in the panel, 0 to 1 across its width and height; each axis
  # is drawn from `axes/2`, which places the breaks the same way and says which side of the panel
  # each axis is drawn on; the panel's grid is drawn from `grid/2`, which runs a line across the
  # panel at each break and minor break; and `clip/1` says whether what is drawn in a panel is cut
  # off at its edges. A geom never sees a scale's range, and the params are opaque to everything
  # but the coordinate system that built them, so a coordinate system that places positions
  # differently (radial, ggplot2's `coord_radial()`) changes no geom, no axis and no grid.
  #
  # A plot records its coordinate system as a struct of its kind. Each coordinate system is one
  # module holding everything about it: its struct, whose fields are its parameters, and its
  # computing, in a `defimpl Giggly.Coord` whose first line classifies it into this boundary,
  # since boundary checks nothing a protocol implementation calls until it is classified. Its
  # panel params are a map it builds and alone reads, as ggplot2's are a list each coordinate
  # system fills in its own way. There is one so far, cartesian coordinates
  # (`Giggly.Coord.Cartesian`), which `ggplot()` defaults to.

  # A coordinate system reads the aesthetic vocabulary (which columns are x and which y) and the
  # frames it places, and nothing else.
  # It exports its kinds, whose structs a plot records, and nothing they compute with: that is in
  # their protocol implementations, which no boundary exports.
  use Boundary, deps: [Giggly.Aesthetics, Giggly.DataFrame], exports: [Cartesian]

  alias Giggly.{Coord, DataFrame}

  @typedoc "An axis's extent in positions, already widened: `{low, high}`."
  @type dimension :: {number(), number()}

  @typedoc "A break on an axis: its position, or once placed its place along the panel's side, and its label."
  @type break :: {number(), String.t()}

  @typedoc """
  An axis as the assembly hands it over: its extent, and its breaks and the positions of its minor
  breaks on that extent.
  """
  @type axis :: {dimension(), [break()], [number()]}

  @typedoc "A side of the panel an axis is drawn on."
  @type side :: :bottom | :left

  @typedoc "The axis drawn on a side: the aesthetic it shows and its breaks, placed along the side."
  @type placed_axis :: {:x | :y, [break()]}

  @typedoc "A line through points in the unit panel, each `{x, y}`."
  @type line :: [{float(), float()}]

  @typedoc """
  A panel's grid lines, major and minor, each by the aesthetic whose breaks they mark: the `:x`
  lines at the x axis's breaks, the `:y` lines at the y axis's.
  """
  @type grid :: %{major: %{x: [line()], y: [line()]}, minor: %{x: [line()], y: [line()]}}

  @typedoc """
  Whether what is drawn in a panel is cut off at its edges: `:on`, ggplot2's default for every
  coordinate system; `:off` arrives with the option to turn it off.
  """
  @type clip :: :on

  @typedoc "What a coordinate system needs to place one panel's positions, built by its `panel_params/3`."
  @type panel_params :: Coord.Cartesian.panel_params()

  # The params of a panel whose x and y axes are `x_axis` and `y_axis`, each its extent, its breaks
  # and its minor breaks, under `coord`: ggplot2's `setup_panel_params()`.
  @doc false
  @spec panel_params(t(), axis(), axis()) :: panel_params()
  def panel_params(coord, x_axis, y_axis)

  # The frame with every x-family and y-family column placed in the panel `panel_params`
  # describes, 0 to 1 across it: ggplot2's `transform()`. Other columns are left as they are.
  #
  # On an axis whose extent has equal ends, which `Giggly.Scale.dimension/1` gives an extent R's
  # `zero_range()` calls zero wide, every position is placed at the middle, infinite ones too, as
  # `scales::rescale()` places them.
  @doc false
  @spec transform(t(), DataFrame.t(), panel_params()) :: DataFrame.t()
  def transform(coord, frame, panel_params)

  # Each axis on the side of the panel it is drawn on, keyed by that side: the aesthetic it shows,
  # whose title goes with it, and its breaks placed along the side, 0 to 1 as `transform/3` places
  # positions. ggplot2's axis guides take their breaks through the same transformation as the data,
  # so ticks and marks cannot disagree, and which axis goes on which side is the coordinate
  # system's: a cartesian panel draws its x axis at the bottom and its y axis on the left.
  @doc false
  @spec axes(t(), panel_params()) :: %{side() => placed_axis()}
  def axes(coord, panel_params)

  # The panel's grid lines, major lines at each axis's breaks and minor lines at its minor breaks,
  # each placed in the panel as `transform/3` places positions: ggplot2's `guide_grid()`, which
  # runs each line from minus to plus infinity through the coordinate system. A cartesian panel's
  # lines are straight and cross it from edge to edge: the x lines up from its bottom, the y lines
  # rightward from its left.
  #
  # Across an axis whose extent has equal ends, where every position is placed at the middle, a
  # line shrinks to a point there, as ggplot2's does.
  @doc false
  @spec grid(t(), panel_params()) :: grid()
  def grid(coord, panel_params)

  # Whether what is drawn in each panel under `coord` is cut off at its edges, ggplot2's `clip`: a
  # point at an infinite position, placed on the panel's edge, shows only its inner half. Cartesian
  # coordinates record ggplot2's default, `coord_cartesian(clip = "on")`, until the option to turn
  # it off arrives.
  @doc false
  @spec clip(t()) :: clip()
  def clip(coord)
end
