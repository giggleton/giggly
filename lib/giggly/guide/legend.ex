defmodule Giggly.Guide.Legend do
  @moduledoc false

  # A legend, ggplot2's `guide_legend()`, a kind of guide (`Giggly.Guide`) whose one parameter,
  # `reverse`, is the assembly's to apply: it hands the keys over last break first, as ggplot2's
  # `extract_params()` turns the key table upside down before legends merge. Drawn as a table of
  # its own (`Giggly.Scene`) for the box of guides beside the panels, laid out as ggplot2's
  # `GuideLegend` lays one out at theme_gray()'s defaults, a vertical legend with its title above
  # and its labels right of its keys:
  #
  #   * the theme's legend margin inside the edge, each side its own;
  #   * the title, as deep as its lines (`Giggly.Guide.Parts`) and its margin above them,
  #     left-aligned its left margin in and centred down what its margin above leaves, as grid
  #     centres text, then its margin below it; a title of `:none` takes none of them;
  #   * a row for each key, the key on the key background, the glyph of each layer drawn over it,
  #     and its label right of it, the labels' left margin from the key, centred on it as the title
  #     is; each row as tall as the theme's key height, the tallest glyph drawn in it, or its label
  #     with the labels' margins above and below it, and the keys' column as wide as the theme's key
  #     width or the widest glyph drawn in any, as ggplot2's `measure_legend_keys()` sizes them from
  #     the room each glyph needs;
  #   * the label column as wide as the widest label and the labels' right margin, or wider when
  #     the title, its margins either side included, is wider than the keys and their labels, which
  #     leaves the room at the labels' right; with no labels, neither the column nor its margins,
  #     but the room a wider title needs right of the keys, as ggplot2 leaves them out for a scale
  #     with no labels.
  #
  # The legend's background spans the whole table, under everything; then the title, each key's
  # background and glyphs, and the labels, in ggplot2's drawing order.

  defstruct reverse: false

  @type t :: %__MODULE__{reverse: boolean()}

  defimpl Giggly.Guide, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Guide

    alias Giggly.Guide.Parts
    alias Giggly.{Scene, Theme}
    alias Giggly.Scene.{Cell, Rect}

    # The legend titled `title`, a key for each of `keys`, each its label and the glyphs drawn in
    # it, in `theme`'s look: its width in points, and its table, every size in points.
    @impl Giggly.Guide
    def draw(_guide, %{title: title, keys: keys}, %Theme{} = theme) do
      %Theme{
        legend_margin: margin,
        legend_key_width: key_width,
        legend_key_height: key_height,
        legend_title: title_look,
        legend_text: text_look
      } = theme

      labels = Enum.map(keys, fn key -> key.label end)
      label_widths = Parts.label_widths(labels, text_look)
      {label_margin, labels_width} = Parts.label_columns(labels, label_widths, text_look)
      title_width = Parts.legend_title_width(title, title_look)
      key_column = key_extent(keys, key_width, fn {width, _height} -> width end)
      label_column = max(labels_width, title_width - key_column - label_margin)
      {title_rows, title_cells} = Parts.title_rows(title, title_look, 2..4)
      first_key_row = 2 + length(title_rows)

      widths = [margin.left, key_column, label_margin, label_column, margin.right]

      # A row is as tall as its key or its label, whichever is taller, as ggplot2's are.
      key_rows =
        Enum.map(keys, fn key ->
          [key]
          |> key_extent(key_height, fn {_width, height} -> height end)
          |> max(Parts.label_height(key.label, text_look))
        end)

      heights = Enum.concat([[margin.top], title_rows, key_rows, [margin.bottom]])

      scene = %Scene{
        widths: Enum.map(widths, fn width -> {:points, width} end),
        heights: Enum.map(heights, fn height -> {:points, height} end),
        keep_proportions: false,
        cells:
          Enum.concat([
            [Parts.background(length(widths), length(heights), theme)],
            title_cells,
            key_cells(keys, first_key_row, theme),
            label_cells(labels, label_widths, text_look, first_key_row)
          ])
      }

      {Enum.sum(widths), scene}
    end

    # How far `keys` reach one way, `extent` of each glyph's room: the theme's key width or
    # height, `key_size`, or the largest glyph's where one needs more.
    defp key_extent(keys, key_size, extent) do
      keys
      |> Enum.flat_map(fn key -> Enum.map(key.sizes, extent) end)
      |> Enum.max(fn -> key_size end)
      |> max(key_size)
    end

    # Each key's cell, its background under its glyphs, in the key rows, which start at
    # `first_row`.
    defp key_cells(keys, first_row, %Theme{legend_key: look}) do
      keys
      |> Enum.with_index(first_row)
      |> Enum.map(fn {%{glyphs: glyphs}, row} ->
        %Cell{
          rows: row..row,
          columns: 2..2,
          clip: :off,
          hang: :none,
          primitives: [
            %Rect{fill: look.fill, color: look.color, stroke_width: look.line_width} | glyphs
          ]
        }
      end)
    end

    # Each key's label in its row, a key of no label drawing none.
    defp label_cells(labels, label_widths, text_look, first_row) do
      labels
      |> Enum.zip(label_widths)
      |> Enum.with_index(first_row)
      |> Enum.reject(fn {{label, _width}, _row} -> label == :none end)
      |> Enum.map(fn {{label, width}, row} ->
        Parts.text_cell(label, width, text_look, row, 4..4)
      end)
    end
  end
end
