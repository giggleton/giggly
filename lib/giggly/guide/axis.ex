defmodule Giggly.Guide.Axis do
  @moduledoc false

  # An axis, ggplot2's `guide_axis()`: a tick at each break, reaching out from the panel's edge,
  # and the break's label beyond it; and the axis's title, beyond the axis in a cell of its own, as
  # ggplot2 lays its axis titles out.
  #
  # When a plot is rendered, `draw/3` takes the plot's coordinate system, a panel's params and the
  # plot's complete theme, and draws an axis on each side of the panel that the coordinate system
  # puts one, from that axis's breaks already placed along the side (`Giggly.Coord.axes/2`), in
  # the look the coordinate system names, so ticks and marks are placed by one rule;
  # `draw_inside/3` draws the axes the coordinate system puts inside the panel, over its layers, a
  # radial panel's angle axis (`Giggly.Guide.AxisTheta`), as ggplot2's coordinate system draws its
  # foreground (`render_fg()`); and `titles/4` draws the title of the aesthetic the coordinate
  # system says each side shows, once for the plot, however many panels it has.
  #
  # It looks as the theme says (`Giggly.Theme`): its ticks reach the theme's tick length out from
  # the panel's edge, and its labels sit the labels' margin beyond them. Ticks the theme removes
  # draw nothing and count as no length, as ggplot2's axis counts them; labels it removes draw as a
  # scale with no labels does, and so does a title. The labels below the panel
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
  # `theme_gray()` turns the y axis's title. Its cell is as deep as the margin and its lines
  # (`Giggly.Guide.Parts`), each line centred on the side, the first nearest the cell's far edge;
  # an axis with no title takes no room.

  alias Giggly.{Coord, Font, Guide, Scene, Theme}
  alias Giggly.Guide.Parts
  alias Giggly.Scene.{Polylines, Text}

  # Ticks are opaque, their ends as the theme's ticks say and their corners round, as
  # `theme_gray()`'s `line` element draws every line.

  # The axis drawn on each side of the panel that `panel_params` describes under `coord`, by side,
  # in the look the coordinate system names and `theme`'s. An axis with no breaks draws nothing and
  # takes no room.
  @doc false
  @spec draw(Coord.t(), Coord.panel_params(), Theme.t()) :: %{Coord.side() => Guide.drawn()}
  def draw(coord, panel_params, theme) do
    coord
    |> sides(panel_params)
    |> Map.new(fn {side, {_aesthetic, look, breaks}} ->
      {side, axis(breaks, side, look, theme)}
    end)
  end

  # The axes drawn inside the panel that `panel_params` describes under `coord`, over its layers,
  # in `theme`'s look, placed in the panel's cell: a radial panel's angle axis, around its circle;
  # none for a panel whose axes are all on its sides.
  @doc false
  @spec draw_inside(Coord.t(), Coord.panel_params(), Theme.t()) :: [Scene.primitive()]
  def draw_inside(coord, panel_params, theme) do
    case Coord.axes(coord, panel_params) do
      %{theta: {_aesthetic, :theta, breaks}} -> Guide.AxisTheta.draw(breaks, theme)
      %{} -> []
    end
  end

  # The title of the axis on each side of a panel that `panel_params` describes under `coord`, by
  # side, given each aesthetic's title, `:none` for none, in `theme`'s look. A title of `:none`
  # draws nothing and takes no room, and so does one the theme removes.
  @doc false
  @spec titles(
          Coord.t(),
          Coord.panel_params(),
          %{(:x | :y) => String.t() | :none},
          Theme.t()
        ) :: %{Coord.side() => Guide.drawn()}
  def titles(coord, panel_params, guide_titles, theme) do
    coord
    |> sides(panel_params)
    |> Map.new(fn {side, {aesthetic, _look, _breaks}} ->
      title =
        guide_titles
        |> Map.fetch!(aesthetic)
        |> title(side, theme)

      {side, title}
    end)
  end

  # The axes the coordinate system puts on the panel's sides.
  defp sides(coord, panel_params) do
    coord
    |> Coord.axes(panel_params)
    |> Map.take([:bottom, :left])
  end

  # The axis drawn on `side` of the panel from `breaks`, each its place along that side, 0 to 1,
  # and its label, in `look` (an x axis's below the panel, a y axis's or a radius axis's to its
  # left) and `theme`'s: how far it reaches from the panel, in points, and its primitives, placed
  # in a cell that deep.
  defp axis([], _side, _look, _theme), do: {0.0, []}
  defp axis(breaks, side, look, theme), do: draw_axis(breaks, side, look, elements(theme, look))

  # An axis whose scale has no labels, or whose labels the theme removes, draws its ticks alone and
  # reaches only as far as they do, as ggplot2's leaves out the labels and their room.
  defp draw_axis(breaks, side, _look, {text_look, ticks})
       when text_look == :none or elem(hd(breaks), 1) == :none do
    places = Enum.map(breaks, fn {place, _label} -> place end)
    depth = reach(ticks)

    case side do
      :bottom -> {depth, bottom_ticks(places, ticks)}
      :left -> {depth, left_ticks(places, ticks)}
    end
  end

  # Labels below the panel count their margins above and below them, as ggplot2's do.
  defp draw_axis(breaks, :bottom, :x, {%{margin: margin} = text_look, ticks}) do
    {places, labels} = Enum.unzip(breaks)
    height = reach(ticks) + margin.top + Parts.line_height(text_look.size) + margin.bottom

    # A cell's y runs up from its bottom; the panel's edge is the cell's top.
    label_top = 1 - (reach(ticks) + margin.top) / height

    text = %Text{
      x: places,
      y: List.duplicate(label_top, length(places)),
      labels: labels,
      widths: Enum.map(labels, fn label -> Font.width(label, text_look.size) end),
      size: text_look.size,
      family: "",
      color: List.duplicate(text_look.color, length(places)),
      opacity: List.duplicate(1.0, length(places)),
      angle: 0,
      hjust: List.duplicate(0.5, length(places)),
      offset: List.duplicate({0.0, -Font.ascent(text_look.size)}, length(places)),
      check_overlap: false,
      ascent: Font.ascent(text_look.size)
    }

    tick_lines = bottom_ticks(places, ticks)
    {height, Enum.concat(tick_lines, [text])}
  end

  # Labels left of the panel count their margins either side of them, as ggplot2's do.
  defp draw_axis(breaks, :left, :y, {%{margin: margin} = text_look, ticks}) do
    {places, labels} = Enum.unzip(breaks)
    label_widths = Enum.map(labels, fn label -> Font.width(label, text_look.size) end)
    width = margin.left + Enum.max(label_widths) + margin.right + reach(ticks)

    # The panel's edge is the cell's right; the labels end at the margin.
    label_end = 1 - (reach(ticks) + margin.right) / width
    text = left_labels({places, labels, label_widths}, label_end, 1.0, text_look)

    {width, [text | left_ticks(places, ticks)]}
  end

  defp draw_axis(breaks, :left, :r, {%{margin: margin} = text_look, ticks}) do
    {places, labels} = Enum.unzip(breaks)
    label_widths = Enum.map(labels, fn label -> Font.width(label, text_look.size) end)
    label_width = Enum.max(label_widths)
    width = margin.left + label_width + margin.right + reach(ticks)

    # The labels are centred on the middle of the widest, between the two margins.
    label_middle = 1 - (reach(ticks) + margin.right + label_width / 2) / width
    text = left_labels({places, labels, label_widths}, label_middle, 0.5, text_look)

    {width, [text | left_ticks(places, ticks)]}
  end

  # The theme's elements an axis drawn in `look` is drawn with, ggplot2's for that axis on its side
  # (`axis.text.x.bottom`, `axis.ticks.x.bottom`, `axis.ticks.length.x.bottom`): its labels' look,
  # and its ticks' look with their length.
  defp elements(%Theme{} = theme, :x),
    do:
      {theme.axis_text_x_bottom,
       ticks(theme.axis_ticks_x_bottom, theme.axis_ticks_length_x_bottom)}

  defp elements(%Theme{} = theme, :y),
    do: {theme.axis_text_y_left, ticks(theme.axis_ticks_y_left, theme.axis_ticks_length_y_left)}

  defp elements(%Theme{} = theme, :r),
    do: {theme.axis_text_r, ticks(theme.axis_ticks_r, theme.axis_ticks_length_r)}

  # Ticks the theme removes are `:none`, whatever their length, as ggplot2's axis sets the length of
  # blank ticks to 0.
  defp ticks(:none, _length), do: :none
  defp ticks(look, length), do: Map.put(look, :length, length)

  # How far ticks reach out from the panel: their length, or none for ticks turned into the panel
  # by a negative length, which take no room, as ggplot2's measure the range from 0 to the length,
  # or for ticks the theme removes.
  defp reach(:none), do: 0.0
  defp reach(ticks), do: max(ticks.length, 0.0)

  # The labels of an axis to the panel's left, anchored at `x_place` across the axis's cell by
  # `hjust` of their widths, each centred on its break.
  defp left_labels({places, labels, label_widths}, x_place, hjust, text_look) do
    %Text{
      x: List.duplicate(x_place, length(places)),
      y: places,
      labels: labels,
      widths: label_widths,
      size: text_look.size,
      family: "",
      color: List.duplicate(text_look.color, length(places)),
      opacity: List.duplicate(1.0, length(places)),
      angle: 0,
      hjust: List.duplicate(hjust, length(places)),
      offset: List.duplicate({0.0, -Font.ascent(text_look.size) / 2}, length(places)),
      check_overlap: false,
      ascent: Font.ascent(text_look.size)
    }
  end

  # The ticks of an axis below the panel, each hung from the panel's edge, the top of the axis's
  # cell, and reaching its length down from it in points, or up into the panel for a negative
  # length, so they are drawn however deep the cell is, none deep included, as ggplot2 draws zero
  # and negative lengths; none for ticks the theme removes.
  defp bottom_ticks(_places, :none), do: []

  defp bottom_ticks(places, ticks) do
    [
      %Polylines{
        lines: Enum.map(places, fn place -> [{place, 1.0}, {place, 1.0}] end),
        offsets: List.duplicate([{0.0, -ticks.length}, {0.0, 0.0}], length(places)),
        stroke_width: ticks.line_width,
        dashes: :none,
        color: List.duplicate(ticks.color, length(places)),
        opacity: List.duplicate(1.0, length(places)),
        line_end: ticks.line_end,
        line_join: :round,
        mitre_limit: 10.0
      }
    ]
  end

  # The ticks of an axis to the panel's left, each hung from the panel's edge, the right of the
  # axis's cell, reaching its length left of it in points, or into the panel for a negative
  # length; none for ticks the theme removes.
  defp left_ticks(_places, :none), do: []

  defp left_ticks(places, ticks) do
    [
      %Polylines{
        lines: Enum.map(places, fn place -> [{1.0, place}, {1.0, place}] end),
        offsets: List.duplicate([{-ticks.length, 0.0}, {0.0, 0.0}], length(places)),
        stroke_width: ticks.line_width,
        dashes: :none,
        color: List.duplicate(ticks.color, length(places)),
        opacity: List.duplicate(1.0, length(places)),
        line_end: ticks.line_end,
        line_join: :round,
        mitre_limit: 10.0
      }
    ]
  end

  # The title of the axis on `side` of the panel, in `theme`'s look: how far its cell reaches from
  # the axis, in points, and its primitives, placed in a cell that deep and as long as the panel's
  # side.
  defp title(:none, _side, _theme), do: {0.0, []}

  # A title the theme removes draws as no title, as ggplot2's does.
  defp title(_text, :bottom, %Theme{axis_title_x_bottom: :none}), do: {0.0, []}
  defp title(_text, :left, %Theme{axis_title_y_left: :none}), do: {0.0, []}

  # A title hangs from its place, the top of its first line, toward the axis, each line centred
  # along the panel's side (`Giggly.Guide.Parts`). Below the panel it counts its margins above and
  # below it, and to its left those either side of it, as ggplot2's does.
  defp title(text, :bottom, %Theme{axis_title_x_bottom: %{margin: margin} = title_look}) do
    height = margin.top + Parts.title_height(text, title_look) + margin.bottom
    place = {0.5, 1 - margin.top / height}
    {height, [Parts.title_text(text, place, 0, {0.5, 1.0}, title_look)]}
  end

  defp title(text, :left, %Theme{axis_title_y_left: %{margin: margin} = title_look}) do
    width = margin.left + Parts.title_height(text, title_look) + margin.right
    place = {margin.left / width, 0.5}
    {width, [Parts.title_text(text, place, 90, {0.5, 1.0}, title_look)]}
  end
end
