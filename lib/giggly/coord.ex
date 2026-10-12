defmodule Giggly.Coord do
  @moduledoc """
  Coordinate systems: the only route from positions on the scales to the unit panel.

  After the stats and positions have run, the assembly asks the plot's coordinate system for each
  panel's params, from the extent of the panel's x and y scales (`Giggly.Scale.dimension/1`).
  When the plot is rendered, each geom hands its panel's rows and those params to `transform/2`,
  which places every x-family and y-family column in the panel, 0 to 1 across its width and
  height. A geom never sees a scale's range, and the params are opaque to everything but this
  namespace, so a coordinate system that places positions differently (flipped, polar) changes no
  geom.

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

  @typedoc "What a coordinate system needs to place one panel's positions."
  @type panel_params :: Coord.Cartesian.t()

  @doc "A panel's params from the extents of its x and y scales."
  @callback panel_params(x :: dimension(), y :: dimension()) :: panel_params()

  @doc "The frame with its x-family and y-family columns placed in the panel."
  @callback transform(DataFrame.t(), panel_params()) :: DataFrame.t()

  @doc """
  The params of a panel whose x and y scales span `x_dimension` and `y_dimension`, under the
  coordinate system named `name`: ggplot2's `setup_panel_params()`.
  """
  @spec panel_params(name(), dimension(), dimension()) :: panel_params()
  def panel_params(:cartesian, x_dimension, y_dimension),
    do: Coord.Cartesian.panel_params(x_dimension, y_dimension)

  @doc """
  The frame with every x-family and y-family column placed in the panel `panel_params`
  describes, 0 to 1 across it: ggplot2's `transform()`. Other columns are left as they are.

      iex> params = Giggly.Coord.panel_params(:cartesian, {0.0, 4.0}, {10.0, 20.0})
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
end
