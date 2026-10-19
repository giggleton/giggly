defprotocol Giggly.Coord do
  @moduledoc false

  # Coordinate systems: the only route from positions on the scales to the unit panel.
  #
  # After the stats and positions have run, the assembly asks the plot's coordinate system for each
  # panel's params, from the extent of the panel's x and y scales (`Giggly.Scale.dimension/1`) and
  # each axis's breaks and minor breaks on that extent (`Giggly.Scale.breaks/2`,
  # `Giggly.Scale.minor_breaks/3`). When the plot is rendered, each geom is handed the coordinate
  # system and its panel's params, and hands both with its rows to `transform/3`, which places
  # positions in the panel, 0 to 1 across its width and height, or, drawing lines, to `munch/3`,
  # which first cuts them into steps that follow the panel's curves; each axis is drawn from
  # `axes/2`, which places the breaks the same way and says where each axis is drawn and in whose
  # look; the panel's grid and background are drawn from `grid/2`, which runs a line through the
  # panel at each break and minor break and gives the background's shape; `clip/1` says whether
  # what is drawn in a panel is cut off at its edges; and `aspect/2` whether a panel keeps a shape
  # of its own. A geom never sees a scale's range, and the params are opaque to everything but the
  # coordinate system that built them, so a coordinate system that places positions differently
  # changes no geom.
  #
  # A plot records its coordinate system as a struct of its kind. Each coordinate system is one
  # module holding everything about it: its struct, whose fields are its parameters, and its
  # computing, in a `defimpl Giggly.Coord` whose first line classifies it into this boundary,
  # since boundary checks nothing a protocol implementation calls until it is classified. Its
  # panel params are a map it builds and alone reads, as ggplot2's are a list each coordinate
  # system fills in its own way. There are cartesian coordinates (`Giggly.Coord.Cartesian`), which
  # `ggplot()` defaults to, and radial ones (`Giggly.Coord.Radial`), ggplot2's `coord_radial()`.

  # A coordinate system reads the aesthetic vocabulary (which columns are x and which y) and the
  # frames it places, and nothing else.
  # It exports its kinds, whose structs a plot records, and nothing they compute with: that is in
  # their protocol implementations, which no boundary exports.
  use Boundary, deps: [Giggly.Aesthetics, Giggly.DataFrame], exports: [Cartesian, Radial]

  alias Giggly.{Coord, DataFrame}

  @typedoc "An axis's extent in positions, already widened: `{low, high}`."
  @type dimension :: {number(), number()}

  @typedoc """
  A break on an axis: its position, or once placed its place along the panel's side, and its label,
  `:none` where the scale has no labels.
  """
  @type break :: {number(), String.t() | :none}

  @typedoc """
  An axis as the assembly hands it over: its extent, and its breaks and the positions of its minor
  breaks on that extent.
  """
  @type axis :: {dimension(), [break()], [number()]}

  @typedoc "A side of the panel an axis is drawn on."
  @type side :: :bottom | :left

  @typedoc """
  Whose look an axis is drawn in, ggplot2's theme suffix: an x or y axis's, or a radial panel's
  radius axis's or angle axis's.
  """
  @type look :: :x | :y | :r | :theta

  @typedoc """
  A break on an axis drawn around a radial panel's circle: its place in the panel, `{x, y}`, its
  angle in radians clockwise from 12 o'clock, the way the axis faces out, and its label.
  """
  @type theta_break :: {{float(), float()}, float(), String.t() | :none}

  @typedoc """
  An axis as the coordinate system places it: the aesthetic it shows, whose title goes with it,
  the look it is drawn in, and its breaks, placed along its side, 0 to 1, or around the circle.
  """
  @type placed_axis :: {:x | :y, look(), [break()] | [theta_break()]}

  @typedoc "A line through points in the unit panel, each `{x, y}`."
  @type line :: [{float(), float()}]

  @typedoc """
  A panel's grid lines, major and minor, each by the aesthetic whose breaks they mark: the `:x`
  lines at the x axis's breaks, the `:y` lines at the y axis's; and its background, `:panel` when
  it fills the panel, or the outline of the shape it fills.
  """
  @type grid :: %{
          major: %{x: [line()], y: [line()]},
          minor: %{x: [line()], y: [line()]},
          background: :panel | line()
        }

  @typedoc """
  Whether what is drawn in a panel is cut off at its edges, `:on` or `:off`, ggplot2's `clip`.
  """
  @type clip :: :on | :off

  @typedoc """
  The shape a panel keeps, its height over its width, ggplot2's aspect ratio; `:none` for a panel
  that takes whatever shape the drawing leaves it.
  """
  @type aspect :: :none | float()

  @typedoc "What a coordinate system needs to place one panel's positions, built by its `panel_params/3`."
  @type panel_params :: Coord.Cartesian.panel_params() | Coord.Radial.panel_params()

  # The params of a panel whose x and y axes are `x_axis` and `y_axis`, each its extent, its breaks
  # and its minor breaks, under `coord`: ggplot2's `setup_panel_params()`.
  @doc false
  @spec panel_params(t(), axis(), axis()) :: panel_params()
  def panel_params(coord, x_axis, y_axis)

  # The frame with its positions placed in the panel `panel_params` describes, 0 to 1 across it:
  # ggplot2's `transform()`. Which columns a coordinate system places, and where, is its own; other
  # columns are left as they are.
  @doc false
  @spec transform(t(), DataFrame.t(), panel_params()) :: DataFrame.t()
  def transform(coord, frame, panel_params)

  # The frame's lines placed in the panel, each cut first into steps short enough to follow the
  # coordinate system's curves: ggplot2's `coord_munch()`, which a geom drawing lines calls in
  # place of `transform/3`. The rows are the lines' points in order, a change of `group` between
  # two rows ending one line and starting the next; each step added copies every column of the row
  # it starts from but its positions. A coordinate system whose straight lines stay straight places
  # the rows as `transform/3` does.
  @doc false
  @spec munch(t(), DataFrame.t(), panel_params()) :: DataFrame.t()
  def munch(coord, frame, panel_params)

  # Each axis by where it is drawn: on a side of the panel, or `:theta`, around a radial panel's
  # circle inside it. Each says the aesthetic it shows, whose title goes with it, the look it is
  # drawn in, and its breaks placed as `transform/3` places positions, so ticks and marks cannot
  # disagree, as ggplot2's axis guides take their breaks through the same transformation as the
  # data. Which axis goes where is the coordinate system's: a cartesian panel draws its x axis at
  # the bottom and its y axis on the left.
  @doc false
  @spec axes(t(), panel_params()) :: %{optional(side() | :theta) => placed_axis()}
  def axes(coord, panel_params)

  # The panel's grid lines, major lines at each axis's breaks and minor lines at its minor breaks,
  # each placed in the panel as `transform/3` places positions: ggplot2's `guide_grid()`, which
  # runs each line from minus to plus infinity through the coordinate system; and the panel's
  # background, which ggplot2 draws filling the panel, or munched into the shape the coordinate
  # system gives it.
  @doc false
  @spec grid(t(), panel_params()) :: grid()
  def grid(coord, panel_params)

  # Whether what is drawn in each panel under `coord` is cut off at its edges, ggplot2's `clip`: a
  # point at an infinite position, placed on the panel's edge, shows only its inner half when it
  # is.
  @doc false
  @spec clip(t()) :: clip()
  def clip(coord)

  # The shape every panel keeps under `coord`, its height over its width, from the first panel's
  # params, as ggplot2 asks `coord$aspect()`; `:none` when a panel takes whatever the drawing
  # leaves it.
  @doc false
  @spec aspect(t(), panel_params()) :: aspect()
  def aspect(coord, panel_params)
end
