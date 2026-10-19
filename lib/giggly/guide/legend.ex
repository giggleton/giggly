defmodule Giggly.Guide.Legend do
  @moduledoc false

  # A legend, ggplot2's `guide_legend()`, a kind of guide (`Giggly.Guide`) with no parameters yet,
  # drawn as a table of its own (`Giggly.Scene`) for the box of guides beside the panels, laid out
  # as ggplot2's `GuideLegend` lays one out at theme_gray()'s defaults, a vertical legend with its
  # title above and its labels right of its keys:
  #
  #   * the theme's legend margin inside the edge on every side;
  #   * the title, as deep as its lines (`Giggly.Guide.Parts`), left-aligned and centred down its
  #     row as grid centres text, then the title's margin below it; a title of `:none` takes
  #     neither;
  #   * a row for each key, as tall as a key, the key square and on the key background, the glyph
  #     of each layer drawn over it, and its label right of it, the labels' margin from the key,
  #     centred on it as the title is;
  #   * the label column as wide as the widest label, or wider when the title is wider than the
  #     keys and their labels, which leaves the room at the labels' right; with no labels, neither
  #     the column nor its margin, but the room a wider title needs right of the keys, as ggplot2
  #     leaves them out for a scale with no labels.
  #
  # The legend's background spans the whole table, under everything; then the title, each key's
  # background and glyphs, and the labels, in ggplot2's drawing order.

  defstruct []

  @type t :: %__MODULE__{}

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
        legend_key_size: key_size,
        legend_title: title_look,
        legend_text: text_look
      } = theme

      labels = Enum.map(keys, fn key -> key.label end)
      label_widths = Parts.label_widths(labels, text_look)
      label_margin = Parts.label_margin(labels, text_look)
      title_width = Parts.legend_title_width(title, title_look)
      label_column = max(Enum.max(label_widths), title_width - key_size - label_margin)
      {title_rows, title_cells} = Parts.title_rows(title, title_look, 2..4)
      first_key_row = 2 + length(title_rows)

      widths = [margin, key_size, label_margin, label_column, margin]
      key_rows = List.duplicate(key_size, length(keys))
      heights = Enum.concat([[margin], title_rows, key_rows, [margin]])

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
