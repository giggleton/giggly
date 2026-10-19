defmodule Giggly.Guide.Parts do
  @moduledoc false

  # The parts the guides of aesthetics other than position build their tables from, alike in a
  # legend (`Giggly.Guide.Legend`) and a colour bar (`Giggly.Guide.Colorbar`), as ggplot2's
  # `GuideColourbar` lays itself out through `GuideLegend`'s measuring and arranging: the
  # background over the whole table, the title's rows above the keys, a line of text left-aligned
  # in its cell and centred down it, how wide the labels are and how far from the keys, and how
  # tall a line of text is.
  #
  # And a title, which every guide and the plot's own titles (`Giggly.Guide.Title`) draw alike: a
  # label that may run over several lines, split where it breaks, each line drawn by itself as R's
  # graphics engine draws one, a line spacing below the one before. A title is as deep as its lines
  # spaced out, the last a line of text tall, as ggplot2's `titleGrob` measures it, and as wide as
  # its widest line. Its lines are anchored at one place and stacked as the engine stacks them,
  # `vjust` of the way down from their top: the baseline of line `i` of `n`, counting from 0, is
  # `((1 - vjust)(n - 1) - i)` line spacings above the place, less `vjust` of a line's ascent, so a
  # title hangs from its place at 1 and is centred on it at 0.5; each line is justified along its
  # baseline by `hjust`, as wide as itself.

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

  # A legend's title rows, top down, and its cell, in `look`, left-aligned in the second row across
  # `columns` and centred down it as grid centres text: none for a title of `:none`, which takes
  # no room, as ggplot2's legend leaves out a title it is given as `NULL`; otherwise the title's
  # depth and its margin below it.
  @doc false
  @spec title_rows(String.t() | :none, Theme.title(), Range.t()) :: {[float()], [Cell.t()]}
  def title_rows(:none, _look, _columns), do: {[], []}

  def title_rows(title, look, columns) do
    cell = %Cell{
      rows: 2..2,
      columns: columns,
      clip: :off,
      hang: :none,
      primitives: [title_text(title, {0.0, 0.5}, 0, {0.0, 0.5}, look)]
    }

    {[title_height(title, look), look.margin], [cell]}
  end

  # How wide a legend's title is, in points: none for `:none`.
  @doc false
  @spec legend_title_width(String.t() | :none, Theme.title()) :: float()
  def legend_title_width(:none, _look), do: 0.0
  def legend_title_width(title, look), do: title_width(title, look)

  # How deep `title` is, set in `look`, in points: a line spacing for each line after the first,
  # then a line of text.
  @doc false
  @spec title_height(String.t(), Theme.title()) :: float()
  def title_height(title, look) do
    (length(lines(title)) - 1) * look.line_spacing + line_height(look.size)
  end

  # How wide `title` is, set in `look`, in points: its widest line.
  @doc false
  @spec title_width(String.t(), Theme.title()) :: float()
  def title_width(title, look) do
    title
    |> lines()
    |> Enum.map(fn line -> Font.width(line, look.size) end)
    |> Enum.max()
  end

  # `title` set in `look`, each of its lines a label anchored at `place` in its cell, turned
  # `angle` degrees, justified `hjust` along its baseline and stacked `vjust` of the way down from
  # its top.
  @doc false
  @spec title_text(String.t(), {float(), float()}, number(), {float(), float()}, Theme.title()) ::
          Text.t()
  def title_text(title, {x_place, y_place}, angle, {hjust, vjust}, look) do
    lines = lines(title)
    count = length(lines)
    ascent = Font.ascent(look.size)

    %Text{
      x: List.duplicate(x_place, count),
      y: List.duplicate(y_place, count),
      labels: lines,
      widths: Enum.map(lines, fn line -> Font.width(line, look.size) end),
      size: look.size,
      family: "",
      color: List.duplicate(look.color, count),
      opacity: List.duplicate(1.0, count),
      angle: angle,
      hjust: List.duplicate(hjust, count),
      offset:
        Enum.with_index(lines, fn _line, index ->
          {0.0, ((1 - vjust) * (count - 1) - index) * look.line_spacing - vjust * ascent}
        end),
      check_overlap: false,
      ascent: ascent
    }
  end

  defp lines(title), do: String.split(title, "\n")

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

  # Each of a guide's `labels`' width in points, set in `look`, a label of `:none` taking none.
  @doc false
  @spec label_widths([String.t() | :none], Theme.text()) :: [float()]
  def label_widths(labels, look) do
    Enum.map(labels, fn
      :none -> 0.0
      label -> Font.width(label, look.size)
    end)
  end

  # The margin between a guide's keys and its labels, in `look`: none when every label is `:none`,
  # as ggplot2 leaves out the labels' column and its margin for a scale with no labels.
  @doc false
  @spec label_margin([String.t() | :none], Theme.text()) :: float()
  def label_margin(labels, look) do
    if Enum.all?(labels, fn label -> label == :none end), do: 0.0, else: look.margin
  end

  # How tall a line of text `size` points is: its ascent and its deepest descent.
  @doc false
  @spec line_height(float()) :: float()
  def line_height(size), do: Font.ascent(size) + Font.descent(size)
end
