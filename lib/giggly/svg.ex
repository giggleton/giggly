defmodule Giggly.SVG do
  @moduledoc """
  Writes a `Giggly.Scene` as SVG.

  The table is laid out at the size it is given, in points (1/72 inch), and each cell's primitives
  are placed in the cell's box; today the one cell, the panel, is the whole drawing. The document's user unit is the point, as svglite writes it: the
  `viewBox` is the size in points and `width` and `height` carry `pt`, so a radius of 1.95 is 1.95
  points at the size the plot is shown. Numbers are written with two decimals, as svglite writes
  them, so output can be set beside the SVG ggplot2's own tests snapshot.
  """

  # The SVG backend reads the scene and nothing else.
  use Boundary, deps: [Giggly.Scene], exports: []

  alias Giggly.Scene
  alias Giggly.Scene.{Cell, Points}

  @doc """
  The SVG document that draws `scene` at `width` by `height` points, as grid's `grid.draw()` puts a
  finished table on a device.

  Today a scene is one cell in one flexible row and column, the panel, which fills the drawing; a
  scene of more tracks or cells is refused (`FunctionClauseError`) until the first cell beside the
  panel, an axis, brings tracks to share the drawing between.
  """
  @spec draw(Scene.t(), number(), number()) :: iodata()
  def draw(
        %Scene{
          widths: [{:null, _width_weight}],
          heights: [{:null, _height_weight}],
          cells: [%Cell{row: 1, column: 1, primitives: primitives}]
        },
        width,
        height
      ) do
    [
      "<svg xmlns='http://www.w3.org/2000/svg' width='",
      number(width),
      "pt' height='",
      number(height),
      "pt' viewBox='0 0 ",
      number(width),
      " ",
      number(height),
      "'>\n",
      Enum.map(primitives, fn primitive -> primitive(primitive, width, height) end),
      "</svg>\n"
    ]
  end

  # A cell's y runs up from its bottom edge; SVG's runs down from the top.
  defp primitive(%Points{} = points, width, height) do
    style = [
      "style='stroke-width: ",
      number(points.stroke_width),
      "; stroke: ",
      points.color,
      "; fill: ",
      points.color,
      ";'"
    ]

    points.x
    |> Enum.zip(points.y)
    |> Enum.map(fn {x_position, y_position} ->
      [
        "<circle cx='",
        number(x_position * width),
        "' cy='",
        number((1 - y_position) * height),
        "' r='",
        number(points.radius),
        "' ",
        style,
        " />\n"
      ]
    end)
  end

  defp number(value), do: :erlang.float_to_binary(value / 1, decimals: 2)
end
