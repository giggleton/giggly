defmodule Giggly.Render do
  @moduledoc false

  # The rendering of an assembled plot: turning a `Giggly.Assembly` into a `Giggly.Scene`, as
  # ggplot2's rendering stage (`ggplot_gtable()`, in its `plot-render.R`) turns a built plot into a
  # table of grobs. A backend such as `Giggly.SVG` then draws the scene.
  #
  # The plot's theme, recorded by name, is resolved first into its complete form
  # (`Giggly.Theme`), which everything drawn here other than the marks takes its look from. Each
  # layer's rows are split by panel, and each panel is drawn by itself: its background and grid
  # lines (`Giggly.Guide`), then each layer's rows in it, drawn by the layer's geom
  # (`Giggly.Geom`), in the order the layers were added, each handed the plot's coordinate system
  # and that panel's params; the panel's axes and strips (`Giggly.Guide`) are drawn beside it.
  #
  # The panels are arranged as the layout table says, which is the facet's say: each at its row and
  # column, the axes it draws, and the strips above it. They are laid out as ggplot2's facets lay
  # them out: the panels share what the fixed sizes leave equally, the theme's panel spacing
  # between them; above each row of panels are its strips, below it a row as tall as its tallest
  # bottom axis, and left of each column of panels a column as wide as its widest left axis. An
  # axis below a panel with an empty cell under it is not measured, as ggplot2 measures it, so it
  # hangs into the empty space and the rest of the row takes no room for it. The axes' titles are
  # drawn once, centred on the span of panels, the x title below them and the y title to their
  # left; around the whole table is the theme's plot margin, and the plot's background is drawn
  # first, under everything, over the whole table, margin included, as ggplot2 adds it
  # (`table_add_background()`). Each panel's cell is cut off at its edges when the coordinate
  # system clips panels, and each strip's always, as `theme_gray()`'s `strip.clip` says.
  #
  # Cells are drawn in ggplot2's order, the order its facets add grobs to the table: the panels
  # column by column; the strips, from the last row of panels to the first, left to right; the
  # bottom axes in the same order; the left axes, from the last column to the first, top to
  # bottom; then the x title and the y title. ggplot2's plot without a facet draws its y axis
  # before its x axis; Giggly draws every plot in its facets' order.
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
  def scene(
        %Assembly{
          layout: layout,
          coord: coord,
          panel_params: panel_params,
          guide_titles: guide_titles,
          theme: theme_name
        } = assembly
      ) do
    theme = Theme.complete(theme_name)
    panels = draw_panels(assembly, theme)

    # Every panel puts the same aesthetic on each side, so any panel's params title the axes.
    %{bottom: bottom_title, left: left_title} =
      Guide.titles(coord, Map.fetch!(panel_params, hd(panels).panel), guide_titles, theme)

    panel_rows = DataFrame.pull(layout, :row)
    panel_columns = DataFrame.pull(layout, :column)

    # A panel that keeps an aspect ratio is that many times as tall as it is wide, and the table
    # keeps its proportions, as ggplot2's facets give the panels' rows the ratio in null units and
    # have the table respected.
    {panel_height, keep_proportions} =
      case assembly.aspect_ratio do
        :none -> {1, false}
        ratio -> {ratio, true}
      end

    grid = %{
      rows: Enum.max(panel_rows),
      columns: Enum.max(panel_columns),
      occupied: MapSet.new(panels, fn panel -> {panel.row, panel.column} end),
      panel_height: panel_height
    }

    widths = widths(panels, grid, left_title, theme)
    heights = heights(panels, grid, bottom_title, theme)

    %Scene{
      widths: Enum.map(widths, fn {_name, size} -> size end),
      heights: Enum.map(heights, fn {_name, size} -> size end),
      keep_proportions: keep_proportions,
      cells:
        cells(panels, grid, indexes(widths), indexes(heights), {bottom_title, left_title}, theme,
          clip: assembly.clip,
          extent: {length(widths), length(heights)}
        )
    }
  end

  # Each panel of the layout drawn: where it sits, its primitives, its axes and its strips.
  defp draw_panels(
         %Assembly{
           layer_data: layer_data,
           layer_geoms: layer_geoms,
           layout: layout,
           coord: coord,
           panel_params: panel_params
         },
         theme
       ) do
    layers_by_panel = Enum.map(layer_data, fn frame -> DataFrame.split(frame, :panel) end)

    [:panel, :row, :column, :axis_bottom, :axis_left, :strip]
    |> Enum.map(fn name -> DataFrame.pull(layout, name) end)
    |> Enum.zip_with(fn [panel, row, column, axis_bottom, axis_left, strip] ->
      params = Map.fetch!(panel_params, panel)
      %{bottom: bottom_axis, left: left_axis} = Guide.axes(coord, params, theme)

      layer_primitives =
        layer_geoms
        |> Enum.zip_with(layers_by_panel, fn geom, frames ->
          Geom.draw_panel(geom, Map.fetch!(frames, panel), coord, params)
        end)
        |> Enum.concat()

      %{
        panel: panel,
        row: row,
        column: column,
        # The panel's background and grid under its layers, and any axis inside it over them, as
        # ggplot2's coordinate system draws its background and foreground.
        primitives:
          Enum.concat([
            Guide.grid(coord, params, theme),
            layer_primitives,
            Guide.axes_inside(coord, params, theme)
          ]),
        bottom: if(axis_bottom, do: bottom_axis, else: :none),
        left: if(axis_left, do: left_axis, else: :none),
        strips: Guide.strips(strip, theme)
      }
    end)
  end

  # The columns, left to right, each named and sized: the margin, the y title, then for each
  # column of panels its left axes and its panels, the panel spacing between, then the margin.
  defp widths(panels, grid, {title_width, _title}, theme) do
    panel_columns =
      Enum.map(1..grid.columns//1, fn column ->
        [
          {{:axis_left, column}, {:points, left_axis_width(panels, column)}},
          {{:panel_column, column}, {:rest, 1}}
        ]
      end)

    Enum.concat([
      [{:margin, {:points, theme.plot_margin}}, {:title_left, {:points, title_width}}],
      spaced(panel_columns, theme),
      [{:margin, {:points, theme.plot_margin}}]
    ])
  end

  # The rows, top to bottom, each named and sized: the margin, then for each row of panels its
  # strips, its panels and its bottom axes, the panel spacing between, then the x title and the
  # margin.
  defp heights(panels, grid, {title_height, _title}, theme) do
    layers =
      panels
      |> Enum.map(fn panel -> length(panel.strips) end)
      |> Enum.max()

    # Every strip is as tall as the tallest, as ggplot2's `assemble_strips()` makes them.
    strip_height =
      panels
      |> Enum.flat_map(fn panel -> panel.strips end)
      |> Enum.map(fn {height, _primitives} -> height end)
      |> Enum.max(fn -> 0.0 end)

    panel_rows =
      Enum.map(1..grid.rows//1, fn row ->
        strips =
          Enum.map(1..layers//1, fn layer ->
            {{:strip, row, layer}, {:points, strip_height}}
          end)

        strips ++
          [
            {{:panel_row, row}, {:rest, grid.panel_height}},
            {{:axis_bottom, row}, {:points, bottom_axis_height(panels, grid, row)}}
          ]
      end)

    Enum.concat([
      [{:margin, {:points, theme.plot_margin}}],
      spaced(panel_rows, theme),
      [{:title_bottom, {:points, title_height}}, {:margin, {:points, theme.plot_margin}}]
    ])
  end

  defp spaced(groups, theme) do
    groups
    |> Enum.intersperse([{:spacing, {:points, theme.panel_spacing}}])
    |> Enum.concat()
  end

  # Where each named column or row is, counting from 1.
  defp indexes(sizes) do
    sizes
    |> Enum.with_index(1)
    |> Map.new(fn {{name, _size}, index} -> {name, index} end)
  end

  # A row's bottom axes take the room of the tallest one measured: one with an empty cell under it
  # is not, as ggplot2's `measure_axes()` sets it to nothing, so it hangs into the empty space.
  defp bottom_axis_height(panels, grid, row) do
    panels
    |> Enum.filter(fn panel -> panel.row == row and panel.bottom != :none end)
    |> Enum.reject(fn panel ->
      panel.row < grid.rows and {panel.row + 1, panel.column} not in grid.occupied
    end)
    |> Enum.map(fn %{bottom: {height, _primitives}} -> height end)
    |> Enum.max(fn -> 0.0 end)
  end

  # A column's left axes take the room of the widest one, and a narrower one hangs from its panel's
  # edge. Panels fill the layout a row at a time, so none has an empty cell to its left, which
  # ggplot2 would not measure.
  defp left_axis_width(panels, column) do
    panels
    |> Enum.filter(fn panel -> panel.column == column and panel.left != :none end)
    |> Enum.map(fn %{left: {width, _primitives}} -> width end)
    |> Enum.max(fn -> 0.0 end)
  end

  # The cells, in ggplot2's drawing order.
  defp cells(panels, grid, columns, rows, {bottom_title, left_title}, theme, options) do
    clip = Keyword.fetch!(options, :clip)
    {column_count, row_count} = Keyword.fetch!(options, :extent)
    {_title_height, bottom_title_primitives} = bottom_title
    {_title_width, left_title_primitives} = left_title

    background = %Cell{
      rows: 1..row_count,
      columns: 1..column_count,
      clip: :off,
      hang: :none,
      primitives: [background_rect(theme.plot_background)]
    }

    panel_cells =
      panels
      |> Enum.sort_by(fn panel -> {panel.column, panel.row} end)
      |> Enum.map(fn panel ->
        cell(rows, {:panel_row, panel.row}, columns, {:panel_column, panel.column},
          clip: clip,
          primitives: panel.primitives
        )
      end)

    strip_cells =
      panels
      |> Enum.sort_by(fn panel -> {-panel.row, panel.column} end)
      |> Enum.flat_map(fn panel ->
        panel.strips
        |> Enum.with_index(1)
        |> Enum.map(fn {{_height, primitives}, layer} ->
          cell(rows, {:strip, panel.row, layer}, columns, {:panel_column, panel.column},
            clip: :on,
            primitives: primitives
          )
        end)
      end)

    bottom_axis_cells =
      panels
      |> Enum.reject(fn panel -> panel.bottom == :none end)
      |> Enum.sort_by(fn panel -> {-panel.row, panel.column} end)
      |> Enum.map(fn %{bottom: {height, primitives}} = panel ->
        cell(rows, {:axis_bottom, panel.row}, columns, {:panel_column, panel.column},
          hang: {:top, height},
          primitives: primitives
        )
      end)

    left_axis_cells =
      panels
      |> Enum.reject(fn panel -> panel.left == :none end)
      |> Enum.sort_by(fn panel -> {-panel.column, panel.row} end)
      |> Enum.map(fn %{left: {width, primitives}} = panel ->
        cell(rows, {:panel_row, panel.row}, columns, {:axis_left, panel.column},
          hang: {:right, width},
          primitives: primitives
        )
      end)

    titles = [
      %Cell{
        rows: Map.fetch!(rows, :title_bottom)..Map.fetch!(rows, :title_bottom),
        columns:
          Map.fetch!(columns, {:panel_column, 1})..Map.fetch!(
            columns,
            {:panel_column, grid.columns}
          ),
        clip: :off,
        hang: :none,
        primitives: bottom_title_primitives
      },
      %Cell{
        rows: Map.fetch!(rows, {:panel_row, 1})..Map.fetch!(rows, {:panel_row, grid.rows}),
        columns: Map.fetch!(columns, :title_left)..Map.fetch!(columns, :title_left),
        clip: :off,
        hang: :none,
        primitives: left_title_primitives
      }
    ]

    [background] ++ panel_cells ++ strip_cells ++ bottom_axis_cells ++ left_axis_cells ++ titles
  end

  # A cell in one named row and one named column.
  defp cell(rows, row_name, columns, column_name, options) do
    row = Map.fetch!(rows, row_name)
    column = Map.fetch!(columns, column_name)

    %Cell{
      rows: row..row,
      columns: column..column,
      clip: Keyword.get(options, :clip, :off),
      hang: Keyword.get(options, :hang, :none),
      primitives: Keyword.fetch!(options, :primitives)
    }
  end

  defp background_rect(%{fill: fill, color: color, line_width: line_width}),
    do: %Rect{fill: fill, color: color, stroke_width: line_width}
end
