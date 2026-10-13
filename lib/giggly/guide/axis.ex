defmodule Giggly.Guide.Axis do
  @moduledoc """
  An axis, ggplot2's `guide_axis()`: a tick at each break, reaching out from the panel's edge,
  and the break's label beyond it; and the axis's title, beyond the axis in a cell of its own, as
  ggplot2 lays its axis titles out. Use it through `Giggly.Guide`.

  It looks as ggplot2's default theme draws an axis (`theme_grey()`), until a theme can be set:
  ticks 2.75 points long in dark grey (#333333), 0.5 mm thick; labels in 8.8-point text in grey
  (#4D4D4D), 2.2 points beyond the ticks. ggplot2 gives those lengths in TeX points, 1/72.27 inch,
  so each is converted here to the scene's points, 1/72 inch. The labels below the panel are
  centred on their ticks and hang from their tops; those to its left end at the gap and are
  centred on their ticks. The axis reaches as far from the panel as its tick, its gap and its
  labels need; one with no breaks draws nothing and takes no room, as ggplot2's does.

  The order things are drawn in follows ggplot2's: below the panel the ticks and then the labels,
  to its left the labels and then the ticks.

  A title is 11-point black text, 2.75 points beyond its axis, centred on the panel's side: below
  the panel hanging from the top of its cell, to its left turned 90 degrees with its top to the
  left. Its cell is as deep as the gap and a line of text; an axis with no title takes no room.
  """

  alias Giggly.Font
  alias Giggly.Scene.{Polylines, Text}

  # Scene points per TeX point (grid's "pt"), the unit ggplot2's theme gives lengths in.
  @points_per_theme_point 72 / 72.27

  # ggplot2's line widths are millimetres, which grid draws as `.pt` line-width units each, and a
  # line-width unit is 1/96 inch.
  @line_width_units_per_millimetre 72.27 / 25.4
  @points_per_line_width_unit 72 / 96

  # `theme_grey()`: `axis.ticks.length` (half of `half_line`, 5.5), `axis.ticks` (ink mixed 20%
  # toward paper, `base_line_size` 11 / 22 mm), `axis.text` (0.8 of `base_size` 11, ink mixed
  # 30.2% toward paper) and its margin (0.8 of half of `half_line`).
  @tick_length 2.75 * @points_per_theme_point
  @tick_color "#333333"
  @tick_width 11 / 22 * @line_width_units_per_millimetre * @points_per_line_width_unit
  @label_size 0.8 * 11
  @label_color "#4D4D4D"
  @label_gap 2.2 * @points_per_theme_point

  # `axis.title.x` and `axis.title.y`: `base_size` 11 in ink, with a margin of half of `half_line`
  # toward the axis.
  @title_size 11.0
  @title_color "#000000"
  @title_gap 2.75 * @points_per_theme_point

  @doc """
  The axis drawn on `side` of the panel from `breaks`, each its place along that side, 0 to 1,
  and its label: how far it reaches from the panel, in points, and its primitives, placed in a
  cell that deep.
  """
  @spec draw([{float(), String.t()}], :bottom | :left) :: Giggly.Guide.drawn_axis()
  def draw([], _side), do: {0.0, []}

  def draw(breaks, :bottom) do
    {places, labels} = Enum.unzip(breaks)
    height = @tick_length + @label_gap + Font.ascent(@label_size) + Font.descent(@label_size)

    # A cell's y runs up from its bottom; the panel's edge is the cell's top.
    tick_end = 1 - @tick_length / height
    label_top = 1 - (@tick_length + @label_gap) / height

    ticks = %Polylines{
      lines: Enum.map(places, fn place -> [{place, tick_end}, {place, 1.0}] end),
      stroke_width: @tick_width,
      color: @tick_color
    }

    text = %Text{
      x: places,
      y: List.duplicate(label_top, length(places)),
      labels: labels,
      widths: Enum.map(labels, fn label -> Font.width(label, @label_size) end),
      size: @label_size,
      color: @label_color,
      angle: 0,
      anchor: :middle,
      baseline_offset: -Font.ascent(@label_size)
    }

    {height, [ticks, text]}
  end

  def draw(breaks, :left) do
    {places, labels} = Enum.unzip(breaks)
    label_widths = Enum.map(labels, fn label -> Font.width(label, @label_size) end)
    width = Enum.max(label_widths) + @label_gap + @tick_length

    # The panel's edge is the cell's right.
    tick_end = 1 - @tick_length / width
    label_end = 1 - (@tick_length + @label_gap) / width

    text = %Text{
      x: List.duplicate(label_end, length(places)),
      y: places,
      labels: labels,
      widths: label_widths,
      size: @label_size,
      color: @label_color,
      angle: 0,
      anchor: :end,
      baseline_offset: -Font.ascent(@label_size) / 2
    }

    ticks = %Polylines{
      lines: Enum.map(places, fn place -> [{tick_end, place}, {1.0, place}] end),
      stroke_width: @tick_width,
      color: @tick_color
    }

    {width, [text, ticks]}
  end

  @doc """
  The title of the axis on `side` of the panel: how far its cell reaches from the axis, in points,
  and its primitives, placed in a cell that deep and as long as the panel's side.
  """
  @spec title(String.t() | :none, :bottom | :left) :: Giggly.Guide.drawn_axis()
  def title(:none, _side), do: {0.0, []}

  def title(text, :bottom) do
    height = @title_gap + Font.ascent(@title_size) + Font.descent(@title_size)
    {height, [title_text(text, {0.5, 1 - @title_gap / height}, 0)]}
  end

  def title(text, :left) do
    width = @title_gap + Font.ascent(@title_size) + Font.descent(@title_size)
    {width, [title_text(text, {0.0, 0.5}, 90)]}
  end

  # A title hangs from its point, the top of the text's box, toward the axis.
  defp title_text(text, {x_place, y_place}, angle) do
    %Text{
      x: [x_place],
      y: [y_place],
      labels: [text],
      widths: [Font.width(text, @title_size)],
      size: @title_size,
      color: @title_color,
      angle: angle,
      anchor: :middle,
      baseline_offset: -Font.ascent(@title_size)
    }
  end
end
