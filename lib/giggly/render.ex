defmodule Giggly.Render do
  @moduledoc false

  # The rendering of an assembled plot: turning a `Giggly.Assembly` into a `Giggly.Scene`, as
  # ggplot2's rendering stage (`ggplot_gtable()`, in its `plot-render.R`) turns a built plot into a
  # table of grobs. A backend such as `Giggly.SVG` then draws the scene.
  #
  # The plot's complete theme, which the assembly worked out (`Giggly.Theme`), gives everything
  # drawn here other than the marks its look; the marks take theirs from their rows, which hold the
  # theme's defaults for the layers where a layer leaves its look unset. Each layer's rows are split
  # by panel, and each panel is drawn by itself: its background and grid lines (`Giggly.Guide`),
  # then each layer's rows in it, drawn by the layer's geom (`Giggly.Geom`), in the order the layers
  # were added, each handed the plot's coordinate system and that panel's params, then its
  # foreground, any axis inside it and its border, never filled, as ggplot2's coordinate system
  # draws `panel.border`; where the theme puts the panel on top, its background and grid lines are
  # drawn after the layers, under the foreground. The panel's axes and strips (`Giggly.Guide`) are
  # drawn beside it.
  #
  # The panels are arranged as the layout table says, which is the facet's say: each at its row and
  # column, the axes it draws, and the strips above it and right of it. They are laid out as
  # ggplot2's facets lay them out: the panels share what the fixed sizes leave equally, the theme's
  # panel spacing between them; above each row of panels are its strips, right of the last column
  # the strips right of the panels, against them, and below each row a row as tall as its tallest
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
  # several merged, places them where the theme puts them (`legend_position`), as ggplot2's
  # `table_add_legends()` does: in a column right of the panels or left of the y title, or a row
  # above the panels below the plot's title or below the x title above the caption, the theme's
  # legend spacing from the panels; or inside the panels; or nowhere. Each legend is a table of
  # its own, its keys running down or across, its keys' glyphs drawn by the geom of each layer that
  # maps one of its aesthetics (`Giggly.Geom`), and the legends are stacked in a box
  # (`Giggly.Guide`), nested in a cell spanning the panels' rows or columns, or the whole plot's
  # where the theme lines them up with it, or every panel for a box inside them, and placed in it
  # by the theme's justification, at its point of the cell or, inside, at the theme's point of the
  # panels, as grid places a viewport (`Giggly.Scene.Cell`'s `hang`).
  #
  # Cells are drawn in ggplot2's order, the order its facets add grobs to the table: the panels
  # column by column; the strips, from the last row of panels to the first, left to right; the
  # strips right of the panels, top to bottom, left to right; the bottom axes as the strips above;
  # the left axes, from the last column to the first, top to bottom; then the x title and the y
  # title, the legends, and the plot's subtitle, title, caption and tag. ggplot2's plot without a
  # facet draws its y axis before its x axis; Giggly draws every plot in its facets' order.
  #
  # Nothing outside Giggly calls this module: `Giggly.to_svg/2` assembles a plot and renders it
  # here.

  # Rendering reads the assembled plot, its layout and its complete theme, has each layer's geom
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
          theme: theme
        } = assembly
      ) do
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
    heights = heights(panels, grid, {bottom_title, labels}, legend, theme)

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
           drawn_data: drawn_data,
           layer_geoms: layer_geoms,
           layout: layout,
           coord: coord,
           panel_params: panel_params
         },
         theme
       ) do
    layers_by_panel = Enum.map(drawn_data, fn frame -> DataFrame.split(frame, :panel) end)

    [:panel, :row, :column, :axis_bottom, :axis_left, :strip_top, :strip_right]
    |> Enum.map(fn name -> DataFrame.pull(layout, name) end)
    |> Enum.zip_with(fn [panel, row, column, axis_bottom, axis_left, strip_top, strip_right] ->
      params = Map.fetch!(panel_params, panel)
      %{bottom: bottom_axis, left: left_axis} = Guide.Axis.draw(coord, params, theme)

      layer_primitives =
        layer_geoms
        |> Enum.zip_with(layers_by_panel, fn geom, frames ->
          draw_layer(geom, Map.fetch(frames, panel), coord, params)
        end)
        |> Enum.concat()

      background = Guide.Grid.draw(coord, params, theme)

      foreground =
        coord
        |> Guide.Axis.draw_inside(params, theme)
        |> Enum.concat(border_rect(theme.panel_border))

      %{
        panel: panel,
        row: row,
        column: column,
        primitives: panel_primitives({background, layer_primitives, foreground}, theme),
        bottom: if(axis_bottom, do: bottom_axis, else: :none),
        left: if(axis_left, do: left_axis, else: :none),
        strips: Guide.Strip.draw(strip_top, :top, theme),
        right_strips: Guide.Strip.draw(strip_right, :right, theme)
      }
    end)
  end

  # A panel's background and grid under its layers, and its foreground, any axis inside it and its
  # border, over them, as ggplot2's coordinate system draws them; or, where the theme puts the
  # panel on top, the background and grid over the layers, under the foreground.
  defp panel_primitives({background, layers, foreground}, %Theme{panel_ontop: false}),
    do: Enum.concat([background, layers, foreground])

  defp panel_primitives({background, layers, foreground}, %Theme{panel_ontop: true}),
    do: Enum.concat([layers, background, foreground])

  # A layer's rows in one panel drawn by its geom; a panel where the layer has none, as one whose
  # own table holds no row there, draws nothing of it, as ggplot2's `draw_layer()` gives such a
  # panel an empty grob.
  defp draw_layer(geom, {:ok, frame}, coord, params),
    do: Geom.draw_panel(geom, frame, coord, params)

  defp draw_layer(_geom, :error, _coord, _params), do: []

  # The plot's legends stacked in their box (`Giggly.Guide.Box`), `:none` for none or where the
  # theme puts them nowhere (`legend_position: :none`), or where the box goes, its width and height
  # and its table: each legend drawn by its guide (`Giggly.Guide.draw/3`), its keys running as the
  # theme says, or across above or below the panels and down elsewhere, as ggplot2's guides run,
  # each key handed the glyphs drawn by the geom of every layer that maps one of the legend's
  # aesthetics and draws in that key, in the order the layers were added, at the key's values of
  # the aesthetics it maps and with what the layer sets, as ggplot2 draws each such layer's
  # `draw_key` in the keys it keeps, and the room each glyph needs (`Geom.key_size/2`), which the
  # guide sizes the key by.
  defp draw_legend([], _theme), do: :none
  defp draw_legend(_legends, %Theme{legend_position: :none}), do: :none

  defp draw_legend(legends, %Theme{legend_position: position} = theme) do
    box_direction = if position in [:top, :bottom], do: :horizontal, else: :vertical

    direction =
      if theme.legend_direction == :none, do: box_direction, else: theme.legend_direction

    {width, height, box} =
      legends
      |> Enum.map(fn %{guide: guide, keys: keys, layers: layers} = legend ->
        drawn_keys = Enum.with_index(keys, fn key, index -> draw_key(key, index, layers) end)
        Guide.draw(guide, Map.merge(legend, %{keys: drawn_keys, direction: direction}), theme)
      end)
      |> Guide.Box.draw(box_direction, theme)

    %{position: position, width: width, height: height, box: box}
  end

  # A key with the glyphs each layer drawing in it draws, with the key's values of the aesthetics
  # the layer maps and what the layer sets laid over its geom's defaults, as ggplot2 fills a key's
  # data from the layer's `default_aes`, and whether its marks are horizontal, in `flipped_aes`, as
  # ggplot2 hands `draw_key` the layer's, and the room each layer's glyph needs.
  defp draw_key(%{values: values} = key, index, layers) do
    {glyphs, sizes} =
      for %{
            geom: geom,
            aesthetics: aesthetics,
            defaults: defaults,
            fixed: fixed,
            flipped: flipped,
            draws: draws
          } <- layers,
          Enum.at(draws, index) do
        key_values =
          defaults
          |> Map.merge(fixed)
          |> Map.merge(Map.take(values, aesthetics))
          |> Map.put(:flipped_aes, flipped)

        {Geom.draw_key(geom, key_values), Geom.key_size(geom, key_values)}
      end
      |> Enum.unzip()

    key
    |> Map.put(:glyphs, Enum.concat(glyphs))
    |> Map.put(:sizes, sizes)
  end

  # The columns, left to right, each named and sized: the margin's left side, the tag, any legends
  # on the left and the theme's spacing from the panels, the y title, then for each column of
  # panels its left axes and its panels, the panel spacing across between, then the strips right of
  # the last column, a column per strip, the nearest first, then any legends on the right beyond
  # the theme's spacing from the panels, then the margin's right side, as ggplot2's
  # `table_add_legends()` adds them outside the axes' titles.
  defp widths(panels, grid, {{title_width, _title}, labels}, legend, theme) do
    %{tag: {{tag_width, _tag_height}, _tag}} = labels
    right_strips = Enum.map(panels, fn panel -> panel.right_strips end)

    # Every strip is as wide as the widest, as ggplot2's `assemble_strips()` makes them.
    right_strip_columns =
      Enum.map(1..strip_layers(right_strips)//1, fn layer ->
        {{:strip_right, layer}, {:points, strip_depth(right_strips)}}
      end)

    panel_columns =
      Enum.map(1..grid.columns//1, fn column ->
        [
          {{:axis_left, column}, {:points, left_axis_width(panels, column)}},
          {{:panel_column, column}, {:rest, 1}}
        ]
      end)

    Enum.concat([
      [{:margin_left, {:points, theme.plot_margin.left}}, {:tag, {:points, tag_width}}],
      beside(legend, :left, theme),
      [{:title_left, {:points, title_width}}],
      spaced(panel_columns, theme.panel_spacing_x),
      right_strip_columns,
      beside(legend, :right, theme),
      [{:margin_right, {:points, theme.plot_margin.right}}]
    ])
  end

  # The legends' column or row on `side`, the theme's spacing between it and the panels, where the
  # legends go on that side: as wide or as tall as their box, and none elsewhere.
  defp beside(%{position: side} = legend, side, theme) do
    size = if side in [:left, :right], do: legend.width, else: legend.height
    spacing = {:legend_spacing, {:points, theme.legend_box_spacing}}
    legend = {:legend, {:points, size}}
    if side in [:left, :top], do: [legend, spacing], else: [spacing, legend]
  end

  defp beside(_legend, _side, _theme), do: []

  # The rows, top to bottom, each named and sized: the margin's top, the tag, the plot's title and
  # its subtitle, any legends above the panels and the theme's spacing from them, then for each row
  # of panels its strips, its panels and its bottom axes, the panel spacing down between, then the
  # x title, any legends below the panels beyond the theme's spacing from them, the plot's caption
  # and the margin's bottom, as ggplot2 adds the legends' rows before the plot's labels'.
  defp heights(panels, grid, {{title_height, _title}, labels}, legend, theme) do
    %{
      tag: {{_tag_width, tag_height}, _tag},
      title: {plot_title_height, _plot_title},
      subtitle: {subtitle_height, _subtitle},
      caption: {caption_height, _caption}
    } = labels

    # Every strip is as tall as the tallest, as ggplot2's `assemble_strips()` makes them.
    strip_height =
      panels
      |> Enum.map(fn panel -> panel.strips end)
      |> strip_depth()

    panel_rows =
      Enum.map(1..grid.rows//1, fn row ->
        layers =
          panels
          |> Enum.filter(fn panel -> panel.row == row end)
          |> Enum.map(fn panel -> panel.strips end)
          |> strip_layers()

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
        {:margin_top, {:points, theme.plot_margin.top}},
        {:tag, {:points, tag_height}},
        {:plot_title, {:points, plot_title_height}},
        {:plot_subtitle, {:points, subtitle_height}}
      ],
      beside(legend, :top, theme),
      spaced(panel_rows, theme.panel_spacing_y),
      [{:title_bottom, {:points, title_height}}],
      beside(legend, :bottom, theme),
      [
        {:plot_caption, {:points, caption_height}},
        {:margin_bottom, {:points, theme.plot_margin.bottom}}
      ]
    ])
  end

  # How many strips deep the deepest of the panels' strips on one side is.
  defp strip_layers(strips) do
    strips
    |> Enum.map(&length/1)
    |> Enum.max(fn -> 0 end)
  end

  # How deep the deepest of the panels' strips on one side is, in points.
  defp strip_depth(strips) do
    strips
    |> Enum.concat()
    |> Enum.map(fn {depth, _primitives} -> depth end)
    |> Enum.max(fn -> 0.0 end)
  end

  # Groups of columns or rows with `spacing` points between each group and the next.
  defp spaced(groups, spacing) do
    groups
    |> Enum.intersperse([{:spacing, {:points, spacing}}])
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
      primitives: background_rect(theme.plot_background)
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

    right_strip_cells =
      panels
      |> Enum.sort_by(fn panel -> {panel.row, panel.column} end)
      |> Enum.flat_map(fn panel ->
        panel.right_strips
        |> Enum.with_index(1)
        |> Enum.map(fn {{_width, primitives}, layer} ->
          cell(rows, {:panel_row, panel.row}, columns, {:strip_right, layer},
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
      right_strip_cells,
      bottom_axis_cells,
      left_axis_cells,
      titles,
      legend_cells(Keyword.fetch!(options, :legend), grid, {columns, rows}, theme),
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

  # The legends' cell, as ggplot2 adds its guide box (`table_add_legends()`): beside the panels,
  # spanning their rows or columns, or, where the theme lines legends up with the plot
  # (`legend_location: :plot`), the axes and their titles too, every row from the first strip to the
  # x title or every column from the legends on the left to those on the right; inside the panels,
  # spanning them all, from the first row's top to the last's bottom, the strips above the first
  # left out, whatever the location. The box is placed as a viewport of its own size: beside the
  # panels, its justification's point at the same point of its cell, and inside, its
  # justification's point at the theme's point of the panels.
  defp legend_cells(:none, _grid, _indexes, _theme), do: []

  defp legend_cells(%{position: position} = legend, grid, {columns, rows}, theme) do
    {cell_rows, cell_columns} =
      legend_span(position, grid, {columns, rows}, theme.legend_location)

    {place, justification} = legend_place(position, theme)

    [
      %Cell{
        rows: cell_rows,
        columns: cell_columns,
        clip: :off,
        hang: {:at, place, justification, {legend.width, legend.height}},
        primitives: [legend.box]
      }
    ]
  end

  defp legend_span(position, grid, {columns, rows}, location) when position in [:left, :right] do
    column = Map.fetch!(columns, :legend)
    {side_span(rows, grid.rows, :row, location), column..column}
  end

  defp legend_span(position, grid, {columns, rows}, location) when position in [:top, :bottom] do
    row = Map.fetch!(rows, :legend)
    {row..row, side_span(columns, grid.columns, :column, location)}
  end

  defp legend_span(:inside, grid, {columns, rows}, _location),
    do:
      {side_span(rows, grid.rows, :row, :panel),
       side_span(columns, grid.columns, :column, :panel)}

  # The rows or columns a box beside the panels spans: the panels', or the whole table's between
  # the plot's labels, the margins and the tag.
  defp side_span(indexes, count, :row, :panel),
    do: Map.fetch!(indexes, {:panel_row, 1})..Map.fetch!(indexes, {:panel_row, count})

  defp side_span(indexes, _count, :row, :plot),
    do: (Map.fetch!(indexes, :plot_subtitle) + 1)..Map.fetch!(indexes, :title_bottom)

  defp side_span(indexes, count, :column, :panel),
    do: Map.fetch!(indexes, {:panel_column, 1})..Map.fetch!(indexes, {:panel_column, count})

  defp side_span(indexes, _count, :column, :plot),
    do: (Map.fetch!(indexes, :tag) + 1)..(Map.fetch!(indexes, :margin_right) - 1)

  # The point of its cell the box is placed at, and the point of the box placed there.
  defp legend_place(:right, theme), do: both(theme.legend_justification_right)
  defp legend_place(:left, theme), do: both(theme.legend_justification_left)
  defp legend_place(:top, theme), do: both(theme.legend_justification_top)
  defp legend_place(:bottom, theme), do: both(theme.legend_justification_bottom)

  defp legend_place(:inside, theme),
    do: {theme.legend_position_inside, theme.legend_justification_inside}

  defp both(justification), do: {justification, justification}

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

  # The panel's border, never filled, as ggplot2's coordinate system draws `panel.border` with no
  # fill; none where the theme removes it.
  defp border_rect(:none), do: []

  defp border_rect(look) do
    [
      %Rect{
        fill: :none,
        fill_opacity: 0.0,
        color: look.color,
        color_opacity: look.color_opacity,
        stroke_width: look.line_width,
        dashes: look.dashes
      }
    ]
  end

  # The plot's background, none where the theme removes it; its cell stays, empty, as svglite
  # writes ggplot2's clipping of a background that draws nothing.
  defp background_rect(:none), do: []

  defp background_rect(look),
    do: [
      %Rect{
        fill: look.fill,
        fill_opacity: look.fill_opacity,
        color: look.color,
        color_opacity: look.color_opacity,
        stroke_width: look.line_width,
        dashes: look.dashes
      }
    ]
end
