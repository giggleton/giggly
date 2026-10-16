defmodule Giggly.Guide.Legend do
  @moduledoc false

  # A legend, ggplot2's `guide_legend()` for one aesthetic, as a table of its own (`Giggly.Scene`)
  # for rendering to place beside the panels, laid out as ggplot2's `GuideLegend` lays one out at
  # theme_gray()'s defaults, a vertical legend with its title above and its labels right of its
  # keys:
  #
  #   * the theme's legend margin inside the edge on every side;
  #   * the title, as tall as a line of its text, left-aligned and centred down its row as grid
  #     centres text, by half its ascent, then the title's margin below it;
  #   * a row for each key, as tall as a key, the key square and on the key background, the glyph
  #     of each layer drawn over it, and its label right of it, the labels' margin from the key,
  #     centred on it as the title is;
  #   * the label column as wide as the widest label, or wider when the title is wider than the
  #     keys and their labels, which leaves the room at the labels' right.
  #
  # The legend's background spans the whole table, under everything; then the title, each key's
  # background and glyphs, and the labels, in ggplot2's drawing order.

  alias Giggly.{Font, Theme}
  alias Giggly.Scene
  alias Giggly.Scene.{Cell, Rect, Text}

  # The legend titled `title`, a key for each of `keys`, each its label and the glyphs drawn in it,
  # in `theme`'s look: its width in points, and its table, every size in points.
  @doc false
  @spec draw(String.t(), [{String.t(), [Scene.primitive()]}], Theme.t()) ::
          {float(), Scene.t()}
  def draw(title, keys, %Theme{} = theme) do
    %Theme{
      legend_margin: margin,
      legend_key_size: key_size,
      legend_title: title_look,
      legend_text: text_look
    } = theme

    labels = Enum.map(keys, fn {label, _glyphs} -> label end)
    label_widths = Enum.map(labels, fn label -> Font.width(label, text_look.size) end)
    title_width = Font.width(title, title_look.size)
    label_column = max(Enum.max(label_widths), title_width - key_size - text_look.margin)

    widths = [margin, key_size, text_look.margin, label_column, margin]
    key_rows = List.duplicate(key_size, length(keys))

    heights =
      Enum.concat([[margin, line_height(title_look.size), title_look.margin], key_rows, [margin]])

    scene = %Scene{
      widths: Enum.map(widths, fn width -> {:points, width} end),
      heights: Enum.map(heights, fn height -> {:points, height} end),
      keep_proportions: false,
      cells:
        Enum.concat([
          [background(length(widths), length(heights), theme)],
          [text_cell(title, title_width, title_look, 2, 2..4)],
          key_cells(keys, theme),
          label_cells(labels, label_widths, text_look)
        ])
    }

    {Enum.sum(widths), scene}
  end

  defp background(columns, rows, %Theme{legend_background: look}) do
    %Cell{
      rows: 1..rows,
      columns: 1..columns,
      clip: :off,
      hang: :none,
      primitives: [%Rect{fill: look.fill, color: look.color, stroke_width: look.line_width}]
    }
  end

  # Each key's cell, its background under its glyphs, in the key rows, which start at the fourth.
  defp key_cells(keys, %Theme{legend_key: look}) do
    keys
    |> Enum.with_index(4)
    |> Enum.map(fn {{_label, glyphs}, row} ->
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

  defp label_cells(labels, label_widths, text_look) do
    labels
    |> Enum.zip(label_widths)
    |> Enum.with_index(4)
    |> Enum.map(fn {{label, width}, row} -> text_cell(label, width, text_look, row, 4..4) end)
  end

  # Text left-aligned in its cell and centred down it, as grid centres text with `vjust = 0.5`: its
  # baseline half its ascent below the middle.
  defp text_cell(label, width, look, row, columns) do
    %Cell{
      rows: row..row,
      columns: columns,
      clip: :off,
      hang: :none,
      primitives: [
        %Text{
          x: [0.0],
          y: [0.5],
          labels: [label],
          widths: [width],
          size: look.size,
          color: look.color,
          angle: 0,
          hjust: 0.0,
          offset: {0.0, -Font.ascent(look.size) / 2}
        }
      ]
    }
  end

  defp line_height(size), do: Font.ascent(size) + Font.descent(size)
end
