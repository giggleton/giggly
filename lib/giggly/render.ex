defmodule Giggly.Render do
  @moduledoc """
  The rendering of an assembled plot: turning a `Giggly.Assembly` into a `Giggly.Scene`, as
  ggplot2's rendering stage (`ggplot_gtable()`, in its `plot-render.R`) turns a built plot into a
  table of grobs. A backend such as `Giggly.SVG` then draws the scene.

  Each layer is drawn by its geom (`Giggly.Geom`) in each panel, with that panel's params, in the
  order the layers were added, and each panel becomes a cell of the scene's table. Its axes
  (`Giggly.Guide`) become cells beside it, the y axis's column as wide as the axis and the x
  axis's row as tall, and the panel takes the rest of the drawing. Around the whole table is
  ggplot2's default plot margin, 5.5 TeX points (1/72.27 inch) on each side. Today a plot has one
  panel, at the layout's first row and column; titles and legends become cells around it as they
  arrive.

  Nothing outside Giggly calls this module: `Giggly.to_svg/1` assembles a plot and renders it
  here.
  """

  # Rendering reads the assembled plot and its layout, has each layer's geom draw and each axis's
  # guide, and builds the scene from what they draw.
  use Boundary,
    deps: [Giggly.Assembly, Giggly.DataFrame, Giggly.Geom, Giggly.Guide, Giggly.Scene],
    exports: []

  alias Giggly.{Assembly, DataFrame, Geom, Guide, Scene}
  alias Giggly.Scene.Cell

  # `theme_grey()`'s `plot.margin`: `half_line`, 5.5 TeX points, in the scene's points (1/72 inch).
  @plot_margin 5.5 * 72 / 72.27

  @doc """
  The scene that draws `assembly`.
  """
  @spec scene(Assembly.t()) :: Scene.t()
  def scene(%Assembly{
        layer_data: layer_data,
        layer_geoms: layer_geoms,
        layout: layout,
        panel_params: panel_params,
        titles: titles
      }) do
    # One panel, at the layout's first row and column, until `facet_wrap`, where this match fails
    # loudly until each layer's rows are split by panel and panels are placed among their axes.
    [{panel, 1, 1}] =
      [:panel, :row, :column]
      |> Enum.map(fn name -> DataFrame.pull(layout, name) end)
      |> Enum.zip()

    params = Map.fetch!(panel_params, panel)

    primitives =
      layer_geoms
      |> Enum.zip(layer_data)
      |> Enum.flat_map(fn {geom, frame} -> Geom.draw_panel(frame, geom, params) end)

    %{
      left: %{axis: {left_width, left_axis}, title: {left_title_width, left_title}},
      bottom: %{axis: {bottom_height, bottom_axis}, title: {bottom_title_height, bottom_title}}
    } = Guide.axes(params, titles)

    # Columns: margin, y title, y axis, panel, margin. Rows: margin, panel, x axis, x title,
    # margin. The axes are drawn after the panel, the y axis first, and then the titles, the x
    # title first, in ggplot2's order.
    %Scene{
      widths: [
        {:points, @plot_margin},
        {:points, left_title_width},
        {:points, left_width},
        :rest,
        {:points, @plot_margin}
      ],
      heights: [
        {:points, @plot_margin},
        :rest,
        {:points, bottom_height},
        {:points, bottom_title_height},
        {:points, @plot_margin}
      ],
      cells: [
        %Cell{row: 2, column: 4, primitives: primitives},
        %Cell{row: 2, column: 3, primitives: left_axis},
        %Cell{row: 3, column: 4, primitives: bottom_axis},
        %Cell{row: 4, column: 4, primitives: bottom_title},
        %Cell{row: 2, column: 2, primitives: left_title}
      ]
    }
  end
end
