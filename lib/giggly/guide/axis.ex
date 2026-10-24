defmodule Giggly.Guide.Axis do
  @moduledoc false

  # An axis, ggplot2's `guide_axis()`: a line along the panel's edge, a tick at each break,
  # reaching out from that edge, and the break's label beyond it; and the axis's title, beyond the
  # axis in a cell of its own, as ggplot2 lays its axis titles out.
  #
  # When a plot is rendered, `draw/3` takes the plot's coordinate system, a panel's params and the
  # plot's complete theme, and draws an axis on each side of the panel that the coordinate system
  # puts one, from that axis's breaks and line already placed along the side
  # (`Giggly.Coord.axes/2`), in the look the coordinate system names, so ticks and marks are placed
  # by one rule;
  # `draw_inside/3` draws the axes the coordinate system puts inside the panel, over its layers, a
  # radial panel's angle axis (`Giggly.Guide.AxisTheta`), as ggplot2's coordinate system draws its
  # foreground (`render_fg()`); and `titles/4` draws the title of the aesthetic the coordinate
  # system says each side shows, once for the plot, however many panels it has.
  #
  # It looks as the theme says (`Giggly.Theme`): its line runs along the panel's edge through the
  # places the coordinate system gives it and takes no room, as ggplot2 leaves an axis's line out
  # of its size; its ticks reach the theme's tick length out from the panel's edge, and its labels
  # sit the labels' margin beyond them. Lines and ticks are dashed as the theme says, and draw
  # nothing in the blank line type, the ticks keeping their room. Ticks the theme removes draw
  # nothing and count as no length, as ggplot2's axis counts them; a line it removes draws nothing;
  # labels it removes draw as a scale with no labels does, and so does a title. The labels are
  # placed as `Giggly.Guide.Parts` places every text, ggplot2's `titleGrob()`: each at its break
  # along the side, across it at its turned justification of their room beyond the ticks, moved by
  # the margins across the axis, and turned and justified as the theme says, so `theme_gray()`'s
  # hang below the panel from their ticks, end at their ticks to its left, and are centred between
  # their margins on a radial panel's radius axis, drawn in its own look, ggplot2's `axis.text.r`.
  # The labels' room is as deep as all of them turned, as one grob measures them. The axis reaches
  # as far from the panel as its tick, its margins and its labels need; one with no breaks draws
  # only its line and takes no room, as ggplot2's does.
  #
  # The order things are drawn in follows ggplot2's: the line first; below the panel the ticks and
  # then the labels, to its left the labels and then the ticks.
  #
  # A title is placed by the same rule in a cell of its own beyond its axis, counting its margins
  # across the axis, and along the panel's side at its turned justification of the side: below the
  # panel hanging from the top of its cell and centred, to its left turned 90 degrees with its top
  # to the left, as `theme_gray()` turns the y axis's title. Its cell is as deep as its margins and
  # its lines turned; an axis with no title takes no room.

  alias Giggly.{Coord, Guide, Scene, Theme}
  alias Giggly.Guide.Parts
  alias Giggly.Scene.Polylines

  # Ticks and the axis's line are drawn at their colour's opacity, their ends and dashes as the
  # theme says and their corners round, as `theme_gray()`'s `line` element draws every line.

  # The axis drawn on each side of the panel that `panel_params` describes under `coord`, by side,
  # in the look the coordinate system names and `theme`'s. An axis with no breaks draws only its
  # line and takes no room.
  @doc false
  @spec draw(Coord.t(), Coord.panel_params(), Theme.t()) :: %{Coord.side() => Guide.drawn()}
  def draw(coord, panel_params, theme) do
    coord
    |> sides(panel_params)
    |> Map.new(fn {side, {_aesthetic, look, breaks, line}} ->
      {side, axis({breaks, line}, side, look, theme)}
    end)
  end

  # The axes drawn inside the panel that `panel_params` describes under `coord`, over its layers,
  # in `theme`'s look, placed in the panel's cell: a radial panel's angle axis, around its circle;
  # none for a panel whose axes are all on its sides.
  @doc false
  @spec draw_inside(Coord.t(), Coord.panel_params(), Theme.t()) :: [Scene.primitive()]
  def draw_inside(coord, panel_params, theme) do
    case Coord.axes(coord, panel_params) do
      %{theta: {_aesthetic, :theta, breaks, line}} -> Guide.AxisTheta.draw(breaks, line, theme)
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
    |> Map.new(fn {side, {aesthetic, _look, _breaks, _line}} ->
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
  # and its label, and from `line`, the places along that side its line passes through, in `look`
  # (an x axis's below the panel, a y axis's or a radius axis's to its left) and `theme`'s: how far
  # it reaches from the panel, in points, and its primitives, placed in a cell that deep. Its line
  # is drawn first, along the panel's edge, and takes no room, as ggplot2 draws an axis's line
  # under its ticks and labels and leaves it out of the axis's size.
  defp axis({breaks, line}, side, look, theme) do
    {text_look, ticks, line_look} = elements(theme, look)
    {depth, primitives} = draw_axis(breaks, side, look, {text_look, ticks})
    {depth, axis_line(line, side, line_look) ++ primitives}
  end

  # An axis with no breaks draws only its line, as ggplot2's exits early.
  defp draw_axis([], _side, _look, _elements), do: {0.0, []}

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

  # Labels below the panel count their margins above and below them, as ggplot2's do: each at its
  # break, and up at its turned justification of their room below the ticks, which the cell's y,
  # running up from its bottom, places under the ticks hung from its top.
  defp draw_axis(breaks, :bottom, :x, {%{margin: margin} = text_look, ticks}) do
    {places, labels} = Enum.unzip(breaks)
    {_width, labels_height} = Parts.extent(labels, text_look)
    room = margin.top + labels_height + margin.bottom
    height = reach(ticks) + room
    {{_across, up}, offset} = Parts.anchor(text_look, :up)
    label_places = Enum.map(places, fn place -> {place, up * room / height} end)
    text = Parts.text(labels, label_places, offset, text_look)

    tick_lines = bottom_ticks(places, ticks)
    {height, Enum.concat(tick_lines, [text])}
  end

  # Labels left of the panel count their margins either side of them, as ggplot2's do: each at its
  # break, and across at its turned justification of their room left of the ticks.
  defp draw_axis(breaks, :left, _look, {%{margin: margin} = text_look, ticks}) do
    {places, labels} = Enum.unzip(breaks)
    {labels_width, _height} = Parts.extent(labels, text_look)
    room = margin.left + labels_width + margin.right
    width = room + reach(ticks)
    {{across, _up}, offset} = Parts.anchor(text_look, :across)
    label_places = Enum.map(places, fn place -> {across * room / width, place} end)
    text = Parts.text(labels, label_places, offset, text_look)

    {width, [text | left_ticks(places, ticks)]}
  end

  # The theme's elements an axis drawn in `look` is drawn with, ggplot2's for that axis on its side
  # (`axis.text.x.bottom`, `axis.ticks.x.bottom`, `axis.ticks.length.x.bottom`,
  # `axis.line.x.bottom`): its labels' look, its ticks' look with their length, and its line's look.
  defp elements(%Theme{} = theme, :x),
    do:
      {theme.axis_text_x_bottom,
       ticks(theme.axis_ticks_x_bottom, theme.axis_ticks_length_x_bottom),
       theme.axis_line_x_bottom}

  defp elements(%Theme{} = theme, :y),
    do:
      {theme.axis_text_y_left, ticks(theme.axis_ticks_y_left, theme.axis_ticks_length_y_left),
       theme.axis_line_y_left}

  defp elements(%Theme{} = theme, :r),
    do:
      {theme.axis_text_r, ticks(theme.axis_ticks_r, theme.axis_ticks_length_r), theme.axis_line_r}

  # Ticks the theme removes are `:none`, whatever their length, as ggplot2's axis sets the length of
  # blank ticks to 0.
  defp ticks(:none, _length), do: :none
  defp ticks(look, length), do: Map.put(look, :length, length)

  # How far ticks reach out from the panel: their length, or none for ticks turned into the panel
  # by a negative length, which take no room, as ggplot2's measure the range from 0 to the length,
  # or for ticks the theme removes.
  defp reach(:none), do: 0.0
  defp reach(ticks), do: max(ticks.length, 0.0)

  # An axis's line along the panel's edge, through `places` along it, in `look`: below the panel
  # the top of the axis's cell, to its left the cell's right; none for an axis whose coordinate
  # system gives it no line, or a line the theme removes or gives the blank line type, which R's
  # graphics engine does not draw.
  defp axis_line([], _side, _look), do: []
  defp axis_line(_places, _side, :none), do: []
  defp axis_line(_places, _side, %{dashes: :blank}), do: []

  defp axis_line(places, side, look) do
    points =
      case side do
        :bottom -> Enum.map(places, fn place -> {place, 1.0} end)
        :left -> Enum.map(places, fn place -> {1.0, place} end)
      end

    [
      %Polylines{
        lines: [points],
        offsets: :none,
        stroke_width: look.line_width,
        dashes: look.dashes,
        color: [look.color],
        opacity: [look.opacity],
        line_end: look.line_end,
        line_join: :round,
        mitre_limit: 10.0
      }
    ]
  end

  # The ticks of an axis below the panel, each hung from the panel's edge, the top of the axis's
  # cell, and reaching its length down from it in points, or up into the panel for a negative
  # length, so they are drawn however deep the cell is, none deep included, as ggplot2 draws zero
  # and negative lengths, dashed as the theme says; none for ticks the theme removes or gives the
  # blank line type, which keep their length.
  defp bottom_ticks(_places, :none), do: []
  defp bottom_ticks(_places, %{dashes: :blank}), do: []

  defp bottom_ticks(places, ticks) do
    [
      %Polylines{
        lines: Enum.map(places, fn place -> [{place, 1.0}, {place, 1.0}] end),
        offsets: List.duplicate([{0.0, -ticks.length}, {0.0, 0.0}], length(places)),
        stroke_width: ticks.line_width,
        dashes: ticks.dashes,
        color: List.duplicate(ticks.color, length(places)),
        opacity: List.duplicate(ticks.opacity, length(places)),
        line_end: ticks.line_end,
        line_join: :round,
        mitre_limit: 10.0
      }
    ]
  end

  # The ticks of an axis to the panel's left, each hung from the panel's edge, the right of the
  # axis's cell, reaching its length left of it in points, or into the panel for a negative
  # length; none for ticks the theme removes or gives the blank line type.
  defp left_ticks(_places, :none), do: []
  defp left_ticks(_places, %{dashes: :blank}), do: []

  defp left_ticks(places, ticks) do
    [
      %Polylines{
        lines: Enum.map(places, fn place -> [{1.0, place}, {1.0, place}] end),
        offsets: List.duplicate([{-ticks.length, 0.0}, {0.0, 0.0}], length(places)),
        stroke_width: ticks.line_width,
        dashes: ticks.dashes,
        color: List.duplicate(ticks.color, length(places)),
        opacity: List.duplicate(ticks.opacity, length(places)),
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

  # A title is anchored along the panel's side at its turned justification of the side, and across
  # it at its turned justification of its cell, moved by its margins across the axis: below the
  # panel those above and below it, and to its left those either side of it, as ggplot2's are.
  defp title(text, :bottom, %Theme{axis_title_x_bottom: %{margin: margin} = title_look}) do
    {_width, title_height} = Parts.extent([text], title_look)
    {place, offset} = Parts.anchor(title_look, :up)
    {margin.top + title_height + margin.bottom, [Parts.text([text], [place], offset, title_look)]}
  end

  defp title(text, :left, %Theme{axis_title_y_left: %{margin: margin} = title_look}) do
    {title_width, _height} = Parts.extent([text], title_look)
    {place, offset} = Parts.anchor(title_look, :across)
    {margin.left + title_width + margin.right, [Parts.text([text], [place], offset, title_look)]}
  end
end
