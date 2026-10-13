defmodule Giggly.Guide.Axis do
  @moduledoc """
  An axis, ggplot2's `guide_axis()`: a tick at each break, reaching out from the panel's edge,
  and the break's label beyond it. Use it through `Giggly.Guide`.

  It looks as ggplot2's default theme draws an axis (`theme_grey()`), until a theme can be set:
  ticks 2.75 points long in dark grey (#333333), 0.5 mm thick; labels in 8.8-point text in grey
  (#4D4D4D), 2.2 points beyond the ticks. ggplot2 gives those lengths in TeX points, 1/72.27 inch,
  so each is converted here to the scene's points, 1/72 inch. The labels below the panel are
  centred on their ticks and hang from their tops; those to its left end at the gap and are
  centred on their ticks. The axis reaches as far from the panel as its tick, its gap and its
  labels need; one with no breaks draws nothing and takes no room, as ggplot2's does.

  The order things are drawn in follows ggplot2's: below the panel the ticks and then the labels,
  to its left the labels and then the ticks.
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
end
