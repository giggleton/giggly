defmodule Giggly.Guide.Axis do
  @moduledoc false

  # An axis, ggplot2's `guide_axis()`: a tick at each break, reaching out from the panel's edge,
  # and the break's label beyond it; and the axis's title, beyond the axis in a cell of its own, as
  # ggplot2 lays its axis titles out. Use it through `Giggly.Guide`.
  #
  # It looks as the theme says (`Giggly.Theme`): its ticks reach the theme's tick length out from
  # the panel's edge, and its labels sit the labels' margin beyond them. The labels below the panel
  # are centred on their ticks and hang from their tops; those to its left end at the margin and are
  # centred on their ticks. A radial panel's radius axis, to its left, is drawn in the radius
  # axis's look, ggplot2's `axis.text.r`: its labels are centred between the margin and a margin
  # as wide on their far side. The axis reaches as far from the panel as its tick, its margins and
  # its labels need; one with no breaks draws nothing and takes no room, as ggplot2's does.
  #
  # The order things are drawn in follows ggplot2's: below the panel the ticks and then the labels,
  # to its left the labels and then the ticks.
  #
  # A title sits the title's margin beyond its axis, centred on the panel's side: below the panel
  # hanging from the top of its cell, to its left turned 90 degrees with its top to the left, as
  # `theme_gray()` turns the y axis's title. Its cell is as deep as the margin and a line of text;
  # an axis with no title takes no room.

  alias Giggly.{Font, Theme}
  alias Giggly.Scene.{Polylines, Text}

  # Ticks are opaque, their ends cut square and their corners round, as `theme_gray()`'s `line`
  # element draws every line.

  # The axis drawn on `side` of the panel from `breaks`, each its place along that side, 0 to 1,
  # and its label, in `look` (an x axis's below the panel, a y axis's or a radius axis's to its
  # left) and `theme`'s: how far it reaches from the panel, in points, and its primitives, placed
  # in a cell that deep.
  @doc false
  @spec draw([{float(), String.t()}], :bottom | :left, :x | :y | :r, Theme.t()) ::
          Giggly.Guide.drawn()
  def draw([], _side, _look, _theme), do: {0.0, []}

  def draw(breaks, :bottom, :x, %Theme{
        axis_ticks: ticks_look,
        axis_ticks_length: tick_length,
        axis_text: text_look
      }) do
    {places, labels} = Enum.unzip(breaks)
    height = tick_length + text_look.margin + line_height(text_look.size)

    # A cell's y runs up from its bottom; the panel's edge is the cell's top.
    tick_end = 1 - tick_length / height
    label_top = 1 - (tick_length + text_look.margin) / height

    ticks = %Polylines{
      lines: Enum.map(places, fn place -> [{place, tick_end}, {place, 1.0}] end),
      offsets: :none,
      stroke_width: ticks_look.line_width,
      color: ticks_look.color,
      opacity: List.duplicate(1.0, length(places)),
      line_end: :butt,
      line_join: :round,
      mitre_limit: 10.0
    }

    text = %Text{
      x: places,
      y: List.duplicate(label_top, length(places)),
      labels: labels,
      widths: Enum.map(labels, fn label -> Font.width(label, text_look.size) end),
      size: text_look.size,
      color: text_look.color,
      angle: 0,
      hjust: 0.5,
      offset: {0.0, -Font.ascent(text_look.size)}
    }

    {height, [ticks, text]}
  end

  def draw(
        breaks,
        :left,
        :y,
        %Theme{axis_ticks_length: tick_length, axis_text: text_look} = theme
      ) do
    {places, labels} = Enum.unzip(breaks)
    label_widths = Enum.map(labels, fn label -> Font.width(label, text_look.size) end)
    width = Enum.max(label_widths) + text_look.margin + tick_length

    # The panel's edge is the cell's right; the labels end at the margin.
    label_end = 1 - (tick_length + text_look.margin) / width
    text = left_labels({places, labels, label_widths}, label_end, 1.0, theme)

    {width, [text, left_ticks(places, width, theme)]}
  end

  def draw(
        breaks,
        :left,
        :r,
        %Theme{axis_ticks_length: tick_length, axis_text: text_look} = theme
      ) do
    {places, labels} = Enum.unzip(breaks)
    label_widths = Enum.map(labels, fn label -> Font.width(label, text_look.size) end)
    label_width = Enum.max(label_widths)
    width = text_look.margin + label_width + text_look.margin + tick_length

    # The labels are centred on the middle of the widest, between the two margins.
    label_middle = 1 - (tick_length + text_look.margin + label_width / 2) / width
    text = left_labels({places, labels, label_widths}, label_middle, 0.5, theme)

    {width, [text, left_ticks(places, width, theme)]}
  end

  # The labels of an axis to the panel's left, anchored at `x_place` across the axis's cell by
  # `hjust` of their widths, each centred on its break.
  defp left_labels({places, labels, label_widths}, x_place, hjust, %Theme{axis_text: text_look}) do
    %Text{
      x: List.duplicate(x_place, length(places)),
      y: places,
      labels: labels,
      widths: label_widths,
      size: text_look.size,
      color: text_look.color,
      angle: 0,
      hjust: hjust,
      offset: {0.0, -Font.ascent(text_look.size) / 2}
    }
  end

  # The ticks of an axis `width` points wide to the panel's left, reaching in to the panel's edge,
  # the cell's right.
  defp left_ticks(places, width, %Theme{axis_ticks: ticks_look, axis_ticks_length: tick_length}) do
    tick_end = 1 - tick_length / width

    %Polylines{
      lines: Enum.map(places, fn place -> [{tick_end, place}, {1.0, place}] end),
      offsets: :none,
      stroke_width: ticks_look.line_width,
      color: ticks_look.color,
      opacity: List.duplicate(1.0, length(places)),
      line_end: :butt,
      line_join: :round,
      mitre_limit: 10.0
    }
  end

  # The title of the axis on `side` of the panel, in `theme`'s look: how far its cell reaches from
  # the axis, in points, and its primitives, placed in a cell that deep and as long as the panel's
  # side.
  @doc false
  @spec title(String.t() | :none, :bottom | :left, Theme.t()) :: Giggly.Guide.drawn()
  def title(:none, _side, _theme), do: {0.0, []}

  def title(text, :bottom, %Theme{axis_title: title_look}) do
    height = title_look.margin + line_height(title_look.size)
    {height, [title_text(text, {0.5, 1 - title_look.margin / height}, 0, title_look)]}
  end

  def title(text, :left, %Theme{axis_title: title_look}) do
    width = title_look.margin + line_height(title_look.size)
    {width, [title_text(text, {0.0, 0.5}, 90, title_look)]}
  end

  # A title hangs from its point, the top of the text's box, toward the axis.
  defp title_text(text, {x_place, y_place}, angle, title_look) do
    %Text{
      x: [x_place],
      y: [y_place],
      labels: [text],
      widths: [Font.width(text, title_look.size)],
      size: title_look.size,
      color: title_look.color,
      angle: angle,
      hjust: 0.5,
      offset: {0.0, -Font.ascent(title_look.size)}
    }
  end

  # How deep a line of text is, ggplot2's `titleGrob` measure: its ascent and its deepest descent.
  defp line_height(size), do: Font.ascent(size) + Font.descent(size)
end
