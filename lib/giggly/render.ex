defmodule Giggly.Render do
  @moduledoc false

  # The rendering of an assembled plot: turning a `Giggly.Assembly` into a `Giggly.Scene`, as
  # ggplot2's rendering stage (`ggplot_gtable()`, in its `plot-render.R`) turns a built plot into a
  # table of grobs. A backend such as `Giggly.SVG` then draws the scene.
  #
  # The plot's theme, recorded by name, is resolved first into its complete form
  # (`Giggly.Theme`), which everything drawn here other than the marks takes its look from. Each
  # layer is drawn by its geom (`Giggly.Geom`) in each panel, with that panel's params, in the order
  # the layers were added, over the panel's background and grid lines (`Giggly.Guide`), and each
  # panel becomes a cell of the scene's table, cut off at its edges when the coordinate system
  # clips it, as every ggplot2 coordinate system does by default. Its axes and their
  # titles (`Giggly.Guide`) become cells beside it, the y axis's column as wide as the axis and the
  # x axis's row as tall, and the panel takes the rest of the drawing. Around the whole table is the
  # theme's plot margin, and the plot's background is drawn first, under everything, over the whole
  # table, margin included, as ggplot2 adds it (`table_add_background()`). Today a plot has one
  # panel, at the layout's first row and column; legends become cells around it as they arrive.
  #
  # Nothing outside Giggly calls this module: `Giggly.to_svg/2` assembles a plot and renders it
  # here.

  # Rendering reads the assembled plot and its layout, resolves its theme, has each layer's geom
  # draw and each axis's guide, and builds the scene from what they draw.
  use Boundary,
    deps: [
      Giggly.Assembly,
      Giggly.DataFrame,
      Giggly.Geom,
      Giggly.Guide,
      Giggly.Scene,
      Giggly.Theme
    ],
    exports: []

  alias Giggly.{Assembly, DataFrame, Geom, Guide, Scene, Theme}
  alias Giggly.Scene.{Cell, Rect}

  # The scene that draws `assembly`.
  @doc false
  @spec scene(Assembly.t()) :: Scene.t()
  def scene(%Assembly{
        layer_data: layer_data,
        layer_geoms: layer_geoms,
        layout: layout,
        panel_params: panel_params,
        panel_clips: panel_clips,
        titles: titles,
        theme: theme_name
      }) do
    theme = Theme.complete(theme_name)

    # One panel, at the layout's first row and column, until `facet_wrap`, where this match fails
    # loudly until each layer's rows are split by panel and panels are placed among their axes.
    [{panel, 1, 1}] =
      [:panel, :row, :column]
      |> Enum.map(fn name -> DataFrame.pull(layout, name) end)
      |> Enum.zip()

    params = Map.fetch!(panel_params, panel)

    layer_primitives =
      layer_geoms
      |> Enum.zip(layer_data)
      |> Enum.flat_map(fn {geom, frame} -> Geom.draw_panel(frame, geom, params) end)

    # The panel's background and grid under its layers, as ggplot2's coordinate system draws them.
    panel_primitives = Guide.grid(params, theme) ++ layer_primitives

    %{
      left: %{axis: {left_width, left_axis}, title: {left_title_width, left_title}},
      bottom: %{axis: {bottom_height, bottom_axis}, title: {bottom_title_height, bottom_title}}
    } = Guide.axes(params, titles, theme)

    %Theme{plot_margin: margin, plot_background: background} = theme

    # Columns: margin, y title, y axis, panel, margin. Rows: margin, panel, x axis, x title,
    # margin. The background is drawn first, over all of them; then the panel, then the axes, the
    # y axis first, and then the titles, the x title first, in ggplot2's order.
    %Scene{
      widths: [
        {:points, margin},
        {:points, left_title_width},
        {:points, left_width},
        :rest,
        {:points, margin}
      ],
      heights: [
        {:points, margin},
        :rest,
        {:points, bottom_height},
        {:points, bottom_title_height},
        {:points, margin}
      ],
      cells: [
        %Cell{rows: 1..5, columns: 1..5, clip: :off, primitives: [background_rect(background)]},
        %Cell{
          rows: 2..2,
          columns: 4..4,
          clip: Map.fetch!(panel_clips, panel),
          primitives: panel_primitives
        },
        %Cell{rows: 2..2, columns: 3..3, clip: :off, primitives: left_axis},
        %Cell{rows: 3..3, columns: 4..4, clip: :off, primitives: bottom_axis},
        %Cell{rows: 4..4, columns: 4..4, clip: :off, primitives: bottom_title},
        %Cell{rows: 2..2, columns: 2..2, clip: :off, primitives: left_title}
      ]
    }
  end

  defp background_rect(%{fill: fill, color: color, line_width: line_width}),
    do: %Rect{fill: fill, color: color, stroke_width: line_width}
end
