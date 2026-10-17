defmodule Giggly.Guide.Parts do
  @moduledoc false

  # The parts the guides of aesthetics other than position build their tables from, alike in a
  # legend (`Giggly.Guide.Legend`) and a colour bar (`Giggly.Guide.Colorbar`), as ggplot2's
  # `GuideColourbar` lays itself out through `GuideLegend`'s measuring and arranging: the
  # background over the whole table, a line of text left-aligned in its cell and centred down it,
  # and how tall a line of text is.

  alias Giggly.{Font, Theme}
  alias Giggly.Scene.{Cell, Rect, Text}

  # The guide's background, spanning a table of `columns` and `rows`, in `theme`'s look.
  @doc false
  @spec background(pos_integer(), pos_integer(), Theme.t()) :: Cell.t()
  def background(columns, rows, %Theme{legend_background: look}) do
    %Cell{
      rows: 1..rows,
      columns: 1..columns,
      clip: :off,
      hang: :none,
      primitives: [%Rect{fill: look.fill, color: look.color, stroke_width: look.line_width}]
    }
  end

  # `label`, `width` points wide, in `look`, left-aligned in a cell of `row` and `columns` and
  # centred down it, as grid centres text with `vjust = 0.5`: its baseline half its ascent below
  # the middle.
  @doc false
  @spec text_cell(String.t(), float(), Theme.text(), pos_integer(), Range.t()) :: Cell.t()
  def text_cell(label, width, look, row, columns) do
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
          family: "",
          color: [look.color],
          opacity: [1.0],
          angle: 0,
          hjust: [0.0],
          offset: [{0.0, -Font.ascent(look.size) / 2}],
          check_overlap: false,
          ascent: Font.ascent(look.size)
        }
      ]
    }
  end

  # How tall a line of text `size` points is: its ascent and its deepest descent.
  @doc false
  @spec line_height(float()) :: float()
  def line_height(size), do: Font.ascent(size) + Font.descent(size)
end
