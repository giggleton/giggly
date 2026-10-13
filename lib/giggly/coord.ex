defmodule Giggly.Coord do
  @moduledoc """
  Coordinate systems: the only route from positions on the scales to the unit panel.

  After the stats and positions have run, the assembly asks the plot's coordinate system for each
  panel's params, from the extent of the panel's x and y scales (`Giggly.Scale.dimension/1`) and
  each axis's breaks on that extent (`Giggly.Scale.breaks/2`). When the plot is rendered, each
  geom hands its panel's rows and those params to `transform/2`, which places every x-family and
  y-family column in the panel, 0 to 1 across its width and height, and each axis is drawn from
  `axes/1`, which places the breaks the same way and says which side of the panel each axis is
  drawn on. A geom never sees a scale's range, and the params are opaque to everything but this
  namespace, so a coordinate system that places positions differently (flipped, polar) changes no
  geom and no axis.

  A plot records its coordinate system by name, and the name is resolved here; each coordinate
  system is a module implementing this behaviour, whose struct is its panel params. There is one
  so far, cartesian coordinates (`Giggly.Coord.Cartesian`), which `ggplot()` defaults to.
  """

  # A coordinate system reads the aesthetic vocabulary (which columns are x and which y) and the
  # frames it places, and nothing else.
  use Boundary, deps: [Giggly.Aesthetics, Giggly.DataFrame], exports: []

  alias Giggly.{Coord, DataFrame}

  @typedoc "A coordinate system's name, as a plot records it."
  @type name :: :cartesian

  @typedoc "An axis's extent in positions, already widened: `{low, high}`."
  @type dimension :: {number(), number()}

  @typedoc "A break on an axis: its position, or once placed its place along the panel's side, and its label."
  @type break :: {number(), String.t()}

  @typedoc "An axis as the assembly hands it over: its extent and its breaks on that extent."
  @type axis :: {dimension(), [break()]}

  @typedoc "A side of the panel an axis is drawn on."
  @type side :: :bottom | :left

  @typedoc "What a coordinate system needs to place one panel's positions."
  @type panel_params :: Coord.Cartesian.t()

  @doc "A panel's params from its x and y axes."
  @callback panel_params(x :: axis(), y :: axis()) :: panel_params()

  @doc "The frame with its x-family and y-family columns placed in the panel."
  @callback transform(DataFrame.t(), panel_params()) :: DataFrame.t()

  @doc "Each axis's breaks placed along the side of the panel it is drawn on, by side."
  @callback axes(panel_params()) :: %{side() => [break()]}

  @doc """
  The params of a panel whose x and y axes are `x_axis` and `y_axis`, each its extent and its
  breaks, under the coordinate system named `name`: ggplot2's `setup_panel_params()`.
  """
  @spec panel_params(name(), axis(), axis()) :: panel_params()
  def panel_params(:cartesian, x_axis, y_axis), do: Coord.Cartesian.panel_params(x_axis, y_axis)

  @doc """
  The frame with every x-family and y-family column placed in the panel `panel_params`
  describes, 0 to 1 across it: ggplot2's `transform()`. Other columns are left as they are.

      iex> params = Giggly.Coord.panel_params(:cartesian, {{0.0, 4.0}, []}, {{10.0, 20.0}, []})
      iex> frame =
      ...>   Giggly.DataFrame.new(
      ...>     x: [1.0, :infinity, nil, :nan],
      ...>     xend: [3.0, 2.0, 0.0, 4.0],
      ...>     y: [15.0, :neg_infinity, 20.0, 10.0],
      ...>     group: [1, 1, 2, 2]
      ...>   )
      iex> placed = Giggly.Coord.transform(frame, params)
      iex> Giggly.DataFrame.pull(placed, :x)
      [0.25, 1.0, nil, :nan]
      iex> Giggly.DataFrame.pull(placed, :xend)
      [0.75, 0.5, 0.0, 1.0]
      iex> Giggly.DataFrame.pull(placed, :y)
      [0.5, 0.0, 1.0, 0.0]
      iex> Giggly.DataFrame.pull(placed, :group)
      [1, 1, 2, 2]
  """
  @spec transform(DataFrame.t(), panel_params()) :: DataFrame.t()
  def transform(frame, %Coord.Cartesian{} = panel_params),
    do: Coord.Cartesian.transform(frame, panel_params)

  @doc """
  Each axis's breaks placed along the side of the panel it is drawn on, 0 to 1 as `transform/2`
  places positions, keyed by that side: ggplot2's axis guides take their breaks through the same
  transformation as the data, so ticks and marks cannot disagree. A cartesian panel draws its x
  axis at the bottom and its y axis on the left.

      iex> params =
      ...>   Giggly.Coord.panel_params(
      ...>     :cartesian,
      ...>     {{0.0, 4.0}, [{1.0, "1"}, {3.0, "3"}]},
      ...>     {{10.0, 20.0}, [{15.0, "15"}]}
      ...>   )
      iex> Giggly.Coord.axes(params)
      %{bottom: [{0.25, "1"}, {0.75, "3"}], left: [{0.5, "15"}]}
  """
  @spec axes(panel_params()) :: %{side() => [break()]}
  def axes(%Coord.Cartesian{} = panel_params), do: Coord.Cartesian.axes(panel_params)
end
