defmodule Giggly.Guide.Legend do
  @moduledoc false

  # A legend, ggplot2's `guide_legend()`, a kind of guide (`Giggly.Guide`) whose one parameter,
  # `reverse`, is the assembly's to apply: it hands the keys over last break first, as ggplot2's
  # `extract_params()` turns the key table upside down before legends merge. Drawn as a table of
  # its own (`Giggly.Scene`) for the box of guides beside or inside the panels, laid out as
  # ggplot2's `GuideLegend` lays one out at theme_gray()'s defaults, its keys running down
  # (`:vertical`) or across (`:horizontal`) as rendering says, its labels right of its keys:
  #
  #   * the theme's legend margin inside the edge, each side its own;
  #   * the keys in a grid filled a column at a time, top down, as ggplot2 fills one unless told
  #     to fill it by rows: one column down to twenty keys, another for each twenty more, rows
  #     shared out evenly, as ggplot2 makes `ceiling(n / 20)` columns; across, a row for each five
  #     keys, `ceiling(n / 5)`, the keys shared out evenly among the columns;
  #   * each key on the key background, the glyph of each layer drawn over it, and its label right
  #     of it, the labels' left margin from the key, centred on it; each row as tall as the theme's
  #     key height, the tallest glyph drawn in it, or its tallest label with the labels' margins
  #     above and below it, and each column of keys as wide as the theme's key width or the widest
  #     glyph drawn in it, as ggplot2's `measure_legend_keys()` sizes them from the room each glyph
  #     needs; each column of labels as wide as its widest label and the labels' right margin, or
  #     with no labels, neither the column nor its margin, as ggplot2 leaves them out for a scale
  #     with no labels;
  #   * the keys' spacing (`legend_key_spacing`) between one key and its label and the next column,
  #     and between rows of keys running across; none between rows running down, as ggplot2 gives
  #     a vertical legend none unless `legend.key.spacing.y` is set;
  #   * the title, keys down, above the keys (`legend_title_top`), as deep as its lines
  #     (`Giggly.Guide.Parts`) and its margin above them, left-aligned its left margin in and
  #     centred down what its margin above leaves, as grid centres text, then its margin below it,
  #     a title wider than the keys and their labels leaving the room right of the last column;
  #     keys across, left of the keys (`legend_title_left`), as wide as it and its margins,
  #     centred down the rows of keys, a title taller than the keys leaving half the room above
  #     them and half below, as ggplot2's `add_title()` lays it out; a title of `:none` takes no
  #     room.
  #
  # The legend's background spans the whole table, under everything; then the title, each key's
  # background and glyphs, and the labels, in ggplot2's drawing order. A title or labels the theme
  # removes draw as none given; a background or a key's background it removes draws nothing.

  defstruct reverse: false

  @type t :: %__MODULE__{reverse: boolean()}

  defimpl Giggly.Guide, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Guide

    alias Giggly.Guide.Parts
    alias Giggly.{Scene, Theme}
    alias Giggly.Scene.{Cell, Rect}

    # A legend running down takes a column for each twenty keys, and one running across a row for
    # each five, as ggplot2's `GuideLegend` shares its keys out.
    @keys_per_column 20
    @keys_per_row 5

    # The legend titled `title`, its keys running `direction`, a key for each of `keys`, each its
    # label and the glyphs drawn in it, in `theme`'s look: its width in points, and its table,
    # every size in points.
    @impl Giggly.Guide
    def draw(_guide, %{title: title, keys: keys, direction: direction}, %Theme{} = theme) do
      %Theme{legend_margin: margin, legend_text_right: text_look} = theme
      title_look = title_look(direction, theme)
      title = Parts.title(title, title_look)
      labels = Parts.labels(keys, text_look)
      label_widths = Parts.label_widths(labels, text_look)
      rows = rows(length(keys), direction)

      # Each key beside its label and the label's width, in the grid's columns, top down.
      columns =
        [keys, labels, label_widths]
        |> Enum.zip_with(fn [key, label, width] -> {key, label, width} end)
        |> Enum.chunk_every(rows)

      grid = %{
        rows: rows,
        widths: column_widths(columns, theme),
        heights: row_heights(columns, rows, direction, theme)
      }

      {widths, heights, first, title_cells} = with_title(grid, title, title_look, direction)
      widths = Enum.concat([[margin.left], widths, [margin.right]])
      heights = Enum.concat([[margin.top], heights, [margin.bottom]])

      scene = %Scene{
        widths: Enum.map(widths, fn width -> {:points, width} end),
        heights: Enum.map(heights, fn height -> {:points, height} end),
        keep_proportions: false,
        cells:
          Enum.concat([
            Parts.background(length(widths), length(heights), theme),
            title_cells,
            key_cells(keys, rows, first, theme),
            label_cells(labels, label_widths, {rows, first}, text_look)
          ])
      }

      {Enum.sum(widths), scene}
    end

    # The title's look: above keys running down, left of keys running across.
    defp title_look(:vertical, theme), do: theme.legend_title_top
    defp title_look(:horizontal, theme), do: theme.legend_title_left

    # How many rows `count` keys take running `direction`.
    defp rows(count, :vertical), do: ceiling_div(count, ceiling_div(count, @keys_per_column))
    defp rows(count, :horizontal), do: ceiling_div(count, @keys_per_row)

    defp ceiling_div(dividend, divisor), do: div(dividend + divisor - 1, divisor)

    # The grid's widths, left to right: for each column its keys, the labels' margin and its labels,
    # the keys' spacing before the next.
    defp column_widths(columns, %Theme{legend_key_width: key_width} = theme) do
      columns
      |> Enum.map(fn column ->
        {column_keys, column_labels, label_widths} = unzip3(column)

        {label_margin, label_width} =
          Parts.label_columns(column_labels, label_widths, theme.legend_text_right)

        [
          key_extent(column_keys, key_width, fn {width, _height} -> width end),
          label_margin,
          label_width
        ]
      end)
      |> Enum.intersperse([theme.legend_key_spacing])
      |> Enum.concat()
    end

    # The grid's heights, top down: each row as tall as its tallest key or label, the rows spaced
    # apart when the keys run across.
    defp row_heights(columns, rows, direction, theme) do
      0..(rows - 1)//1
      |> Enum.map(fn row ->
        columns
        |> Enum.flat_map(fn column -> Enum.slice(column, row, 1) end)
        |> Enum.map(fn key_and_label -> row_height(key_and_label, theme) end)
        |> Enum.max()
      end)
      |> Enum.intersperse(row_spacing(direction, theme))
    end

    # How tall a key's row must be for it and its label: the theme's key height, its tallest
    # glyph, or its label and the labels' margins above and below.
    defp row_height({key, label, _width}, %Theme{legend_key_height: key_height} = theme) do
      [key]
      |> key_extent(key_height, fn {_width, height} -> height end)
      |> max(Parts.label_height(label, theme.legend_text_right))
    end

    defp row_spacing(:vertical, _theme), do: 0.0
    defp row_spacing(:horizontal, theme), do: theme.legend_key_spacing

    # The grid's widths and heights with the title's room, where its first key's cell is, and the
    # title's cell. Above the keys, a title wider than them leaves the rest of its room right of the
    # last column; left of them, a title taller than them leaves half the rest above and half
    # below.
    defp with_title(grid, title, look, :vertical) do
      {title_rows, title_cells} = Parts.title_rows(title, look, 2..(length(grid.widths) + 1))
      {before_last, [last]} = Enum.split(grid.widths, -1)

      last =
        before_last
        |> Enum.reduce(Parts.legend_title_width(title, look), fn width, left -> left - width end)
        |> max(last)

      {List.replace_at(grid.widths, -1, last), title_rows ++ grid.heights,
       {2 + length(title_rows), 2}, title_cells}
    end

    defp with_title(grid, title, look, :horizontal) do
      {title_widths, heights, first, title_cells} = Parts.title_column(title, look, grid.heights)
      {title_widths ++ grid.widths, heights, {first, first}, title_cells}
    end

    # How far `keys` reach one way, `extent` of each glyph's room: the theme's key width or
    # height, `key_size`, or the largest glyph's where one needs more.
    defp key_extent(keys, key_size, extent) do
      keys
      |> Enum.flat_map(fn key -> Enum.map(key.sizes, extent) end)
      |> Enum.max(fn -> key_size end)
      |> max(key_size)
    end

    # Each key's cell, its background under its glyphs, in the grid filled a column at a time from
    # `first`, the first key's row and column, rows and columns of spacing between.
    defp key_cells(keys, rows, {first_row, first_column}, %Theme{legend_key: look}) do
      keys
      |> Enum.with_index()
      |> Enum.map(fn {%{glyphs: glyphs}, index} ->
        {row, column} = place(index, rows, {first_row, first_column})

        %Cell{
          rows: row..row,
          columns: column..column,
          clip: :off,
          hang: :none,
          primitives: key_background(look) ++ glyphs
        }
      end)
    end

    # Where the key `index` goes in a grid of `rows` filled a column at a time from `first`: a row
    # of spacing below each row of keys, and the labels' margin, the labels and the spacing right
    # of each column of keys.
    defp place(index, rows, {first_row, first_column}),
      do: {first_row + 2 * rem(index, rows), first_column + 4 * div(index, rows)}

    # A key's background, none where the theme removes it.
    defp key_background(:none), do: []

    defp key_background(look),
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

    # Each key's label two columns right of its key, a key of no label drawing none.
    defp label_cells(labels, label_widths, {rows, first}, text_look) do
      labels
      |> Enum.zip(label_widths)
      |> Enum.with_index()
      |> Enum.reject(fn {{label, _width}, _index} -> label == :none end)
      |> Enum.map(fn {{label, width}, index} ->
        {row, column} = place(index, rows, first)
        Parts.text_cell(label, width, text_look, row, (column + 2)..(column + 2))
      end)
    end

    defp unzip3(triples) do
      {Enum.map(triples, fn {first, _second, _third} -> first end),
       Enum.map(triples, fn {_first, second, _third} -> second end),
       Enum.map(triples, fn {_first, _second, third} -> third end)}
    end
  end
end
