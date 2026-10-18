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
  # left. The plot's title and subtitle are drawn above the panels and its caption below the x
  # title, each spanning the panels' columns, and its tag in a row and a column of its own at the
  # table's top left (`Giggly.Guide.Title`). Around the whole table is the theme's plot margin,
  # and the plot's background is drawn first, under everything, over the whole table, margin
  # included, as ggplot2 adds it (`table_add_background()`), cut off at the table's edges as it is.
  # Each panel's cell is cut off at its edges when the coordinate system clips panels, and each
  # strip's always, as `theme_gray()`'s `strip.clip` says.
  #
  # A plot with legends, one for each aesthetic other than position that a layer maps, or for
  # several merged, gives them a column right of the panels, the theme's legend spacing from them:
  # each legend is a table of its own, its keys' glyphs drawn by the geom of each layer that maps
  # one of its aesthetics (`Giggly.Geom`), and the legends are stacked in a box (`Giggly.Guide`),
  # nested in a cell spanning the panels' rows and centred down them, as ggplot2 places its guide
  # box to the right, and drawn last.
  #
  # Cells are drawn in ggplot2's order, the order its facets add grobs to the table: the panels
  # column by column; the strips, from the last row of panels to the first, left to right; the
  # bottom axes in the same order; the left axes, from the last column to the first, top to
  # bottom; then the x title and the y title, the legends, and the plot's subtitle, title, caption
  # and tag. ggplot2's plot without a facet draws its y axis before its x axis; Giggly draws every
  # plot in its facets' order.
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
          plot_labels: plot_labels,
          theme: theme_name
        } = assembly
      ) do
    theme = Theme.complete(theme_name)
    panels = draw_panels(assembly, theme)
    labels = Guide.Title.draw(plot_labels, theme)

    # Every panel puts the same aesthetic on each side, so any panel's params title the axes.
    %{bottom: bottom_title, left: left_title} =
      Guide.Axis.titles(coord, Map.fetch!(panel_params, hd(panels).panel), guide_titles, theme)

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

    legend = draw_legend(assembly.legends, theme)
    widths = widths(panels, grid, {left_title, labels}, legend, theme)
    heights = heights(panels, grid, {bottom_title, labels}, theme)

    %Scene{
      widths: Enum.map(widths, fn {_name, size} -> size end),
      heights: Enum.map(heights, fn {_name, size} -> size end),
      keep_proportions: keep_proportions,
      cells:
        cells(panels, grid, indexes(widths), indexes(heights), {bottom_title, left_title}, theme,
          clip: assembly.clip,
          extent: {length(widths), length(heights)},
          legend: legend,
          labels: labels
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
      %{bottom: bottom_axis, left: left_axis} = Guide.Axis.draw(coord, params, theme)

      layer_primitives =
        layer_geoms
        |> Enum.zip_with(layers_by_panel, fn geom, frames ->
          draw_layer(geom, Map.fetch(frames, panel), coord, params)
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
            Guide.Grid.draw(coord, params, theme),
            layer_primitives,
            Guide.Axis.draw_inside(coord, params, theme)
          ]),
        bottom: if(axis_bottom, do: bottom_axis, else: :none),
        left: if(axis_left, do: left_axis, else: :none),
        strips: Guide.Strip.draw(strip, theme)
      }
    end)
  end

  # A layer's rows in one panel drawn by its geom; a panel where the layer has none, as one whose
  # own table holds no row there, draws nothing of it, as ggplot2's `draw_layer()` gives such a
  # panel an empty grob.
  defp draw_layer(geom, {:ok, frame}, coord, params),
    do: Geom.draw_panel(geom, frame, coord, params)

  defp draw_layer(_geom, :error, _coord, _params), do: []

  # The plot's legends stacked in their box (`Giggly.Guide.Box`), `:none` for none, or its width
  # and table: each legend drawn by its guide (`Giggly.Guide.draw/3`), each key handed the glyphs
  # drawn by the geom of every layer that maps one of the legend's aesthetics and draws in that
  # key, in the order the layers were added, at the key's values of the aesthetics it maps and with
  # what the layer sets, as ggplot2 draws each such layer's `draw_key` in the keys it keeps.
  defp draw_legend([], _theme), do: :none

  defp draw_legend(legends, theme) do
    size = {theme.legend_key_size, theme.legend_key_size}

    legends
    |> Enum.map(fn %{guide: guide, keys: keys, layers: layers} = legend ->
      drawn_keys = Enum.with_index(keys, fn key, index -> draw_key(key, index, layers, size) end)
      Guide.draw(guide, %{legend | keys: drawn_keys}, theme)
    end)
    |> Guide.Box.draw(theme)
  end

  # A key with the glyphs each layer drawing in it draws, with the key's values of the aesthetics
  # the layer maps and what the layer sets.
  defp draw_key(%{values: values} = key, index, layers, size) do
    glyphs =
      for %{geom: geom, aesthetics: aesthetics, fixed: fixed, draws: draws} <- layers,
          Enum.at(draws, index),
          glyph <- Geom.draw_key(geom, Map.merge(fixed, Map.take(values, aesthetics)), size),
          do: glyph

    Map.put(key, :glyphs, glyphs)
  end

  # The columns, left to right, each named and sized: the margin, the tag, the y title, then for
  # each column of panels its left axes and its panels, the panel spacing between, then any legend
  # beyond the theme's spacing from the panels, then the margin.
  defp widths(panels, grid, {{title_width, _title}, labels}, legend, theme) do
    %{tag: {{tag_width, _tag_height}, _tag}} = labels

    panel_columns =
      Enum.map(1..grid.columns//1, fn column ->
        [
          {{:axis_left, column}, {:points, left_axis_width(panels, column)}},
          {{:panel_column, column}, {:rest, 1}}
        ]
      end)

    legend_columns =
      case legend do
        :none ->
          []

        {legend_width, _scene} ->
          [
            {:legend_spacing, {:points, theme.legend_box_spacing}},
            {:legend, {:points, legend_width}}
          ]
      end

    Enum.concat([
      [
        {:margin, {:points, theme.plot_margin}},
        {:tag, {:points, tag_width}},
        {:title_left, {:points, title_width}}
      ],
      spaced(panel_columns, theme),
      legend_columns,
      [{:margin, {:points, theme.plot_margin}}]
    ])
  end

  # The rows, top to bottom, each named and sized: the margin, the tag, the plot's title and its
  # subtitle, then for each row of panels its strips, its panels and its bottom axes, the panel
  # spacing between, then the x title, the plot's caption and the margin.
  defp heights(panels, grid, {{title_height, _title}, labels}, theme) do
    %{
      tag: {{_tag_width, tag_height}, _tag},
      title: {plot_title_height, _plot_title},
      subtitle: {subtitle_height, _subtitle},
      caption: {caption_height, _caption}
    } = labels

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
      [
        {:margin, {:points, theme.plot_margin}},
        {:tag, {:points, tag_height}},
        {:plot_title, {:points, plot_title_height}},
        {:plot_subtitle, {:points, subtitle_height}}
      ],
      spaced(panel_rows, theme),
      [
        {:title_bottom, {:points, title_height}},
        {:plot_caption, {:points, caption_height}},
        {:margin, {:points, theme.plot_margin}}
      ]
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

    # Clipped to its cell, as `table_add_background()` adds it: when the table keeps its
    # proportions and fills the drawing only one way, the border's outer half is cut off at the
    # table's edge.
    background = %Cell{
      rows: 1..row_count,
      columns: 1..column_count,
      clip: :on,
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

    Enum.concat([
      [background],
      panel_cells,
      strip_cells,
      bottom_axis_cells,
      left_axis_cells,
      titles,
      legend_cells(Keyword.fetch!(options, :legend), grid, columns, rows),
      label_cells(Keyword.fetch!(options, :labels), grid, columns, rows)
    ])
  end

  # The plot's own labels, after the legends, as ggplot2 adds them to its table: the subtitle, the
  # title and the caption, each spanning the panels' columns, then the tag in its corner.
  defp label_cells(labels, grid, columns, rows) do
    %{
      title: {_title_height, title},
      subtitle: {_subtitle_height, subtitle},
      caption: {_caption_height, caption},
      tag: {_tag_size, tag}
    } = labels

    panel_columns =
      Map.fetch!(columns, {:panel_column, 1})..Map.fetch!(columns, {:panel_column, grid.columns})

    spanning =
      Enum.map([plot_subtitle: subtitle, plot_title: title, plot_caption: caption], fn {row,
                                                                                        drawn} ->
        row_index = Map.fetch!(rows, row)

        %Cell{
          rows: row_index..row_index,
          columns: panel_columns,
          clip: :off,
          hang: :none,
          primitives: drawn
        }
      end)

    Enum.concat(spanning, [cell(rows, :tag, columns, :tag, primitives: tag)])
  end

  # The legend's cell, last, as ggplot2 adds its guide box: right of the panels, spanning their
  # rows, from the first's top to the last's bottom, its table centred down them.
  defp legend_cells(:none, _grid, _columns, _rows), do: []

  defp legend_cells({_width, scene}, grid, columns, rows) do
    [
      %Cell{
        rows: Map.fetch!(rows, {:panel_row, 1})..Map.fetch!(rows, {:panel_row, grid.rows}),
        columns: Map.fetch!(columns, :legend)..Map.fetch!(columns, :legend),
        clip: :off,
        hang: :none,
        primitives: [scene]
      }
    ]
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
