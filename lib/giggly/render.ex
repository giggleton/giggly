defmodule Giggly.Render do
  @moduledoc """
  The rendering of an assembled plot: turning a `Giggly.Assembly` into a `Giggly.Scene`, as
  ggplot2's rendering stage (`ggplot_gtable()`, in its `plot-render.R`) turns a built plot into a
  table of grobs. A backend such as `Giggly.SVG` then draws the scene.

  Each layer is drawn by its geom (`Giggly.Geom`) in each panel, with that panel's params, in the
  order the layers were added, and each panel becomes a cell of the scene's table at the row and
  column the layout gives it. Today a plot has one panel, so its scene is one cell, the whole
  table; axes, titles and legends become cells around it as they arrive.

  Nothing outside Giggly calls this module: `Giggly.to_svg/1` assembles a plot and renders it
  here.
  """

  # Rendering reads the assembled plot and its layout, has each layer's geom draw, and builds the
  # scene from what they draw.
  use Boundary,
    deps: [Giggly.Assembly, Giggly.DataFrame, Giggly.Geom, Giggly.Scene],
    exports: []

  alias Giggly.{Assembly, DataFrame, Geom, Scene}
  alias Giggly.Scene.Cell

  @doc """
  The scene that draws `assembly`.
  """
  @spec scene(Assembly.t()) :: Scene.t()
  def scene(%Assembly{
        layer_data: layer_data,
        layer_geoms: layer_geoms,
        layout: layout,
        panel_params: panel_params
      }) do
    # One panel until `facet_wrap`, where this match fails loudly until each layer's rows are
    # split by panel.
    [{panel, row, column}] =
      [:panel, :row, :column]
      |> Enum.map(fn name -> DataFrame.pull(layout, name) end)
      |> Enum.zip()

    params = Map.fetch!(panel_params, panel)

    primitives =
      layer_geoms
      |> Enum.zip(layer_data)
      |> Enum.flat_map(fn {geom, frame} -> Geom.draw_panel(frame, geom, params) end)

    %Scene{
      widths: [{:null, 1}],
      heights: [{:null, 1}],
      cells: [%Cell{row: row, column: column, primitives: primitives}]
    }
  end
end
