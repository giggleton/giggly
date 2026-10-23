defmodule Giggly.Guide.AxisTheta do
  @moduledoc false

  # The axis around a radial panel's circle, ggplot2's `guide_axis_theta()`: drawn inside the
  # panel, over its layers, a tick at each break reaching out from the circle's edge along the
  # break's angle, and the break's label beyond it. `Giggly.Guide.Axis.draw_inside/3` draws it.
  #
  # It looks as the theme's angle axis does (`Giggly.Theme`'s `axis_text_theta` and the rest), which
  # inherits the x axis's look: each tick reaches its tick length out from the circle, and each
  # label's anchor sits the tick length and the widest side of the labels' margin out, the label
  # justified by its angle so it stands clear of the circle: centred above a break at 12 o'clock,
  # starting to the right of one at 3, hanging below one at 6 and ending to the left of one at 9,
  # its `hjust` `0.5 - sin(angle) / 2` and its `vjust` `0.5 - cos(angle) / 2`, the share of its
  # height below its anchor, as ggplot2 justifies it. Neither is measured nor given room, as
  # ggplot2's are not: the panel has room round its circle. Each label is a text of its own, since
  # each is justified its own way; the labels are drawn and then the ticks, as ggplot2 draws them.
  # Labels or ticks the theme removes draw nothing; the labels keep their place beyond removed
  # ticks, as ggplot2's angle axis keeps the ticks' length in their offset.

  alias Giggly.{Font, Theme}
  alias Giggly.Scene.{Polylines, Text}

  # Ticks are opaque, their ends as the theme's ticks say and their corners round, as
  # `theme_gray()`'s `line` element draws every line.

  # The axis drawn from `breaks`, each its place on the circle's edge, its angle clockwise from
  # 12 o'clock and its label, in `theme`'s look: its primitives, placed in the panel's cell.
  @doc false
  @spec draw([Giggly.Coord.theta_break()], Theme.t()) :: [Giggly.Scene.primitive()]
  def draw(breaks, %Theme{
        axis_ticks_theta: ticks_look,
        axis_ticks_length_theta: tick_length,
        axis_text_theta: text_look
      }) do
    labels(breaks, tick_length, text_look) ++ ticks(breaks, tick_length, ticks_look)
  end

  # Each break's label, justified by its angle beyond its tick; none where the theme removes them.
  defp labels(_breaks, _tick_length, :none), do: []

  defp labels(breaks, tick_length, text_look) do
    # A label sits its margin's widest side beyond its tick, or beyond the circle for a tick turned
    # into the panel by a negative length, as ggplot2's does.
    widest_margin =
      text_look.margin
      |> Map.values()
      |> Enum.max()

    label_offset = max(tick_length, 0.0) + widest_margin

    # A scale with no labels has a tick at each break and nothing beside it.
    breaks
    |> Enum.reject(fn {_place, _angle, label} -> label == :none end)
    |> Enum.map(fn {{x_place, y_place}, angle, label} ->
      vjust = 0.5 - :math.cos(angle) / 2

      %Text{
        x: [x_place],
        y: [y_place],
        labels: [label],
        widths: [Font.width(label, text_look.size)],
        size: text_look.size,
        family: "",
        color: [text_look.color],
        opacity: [1.0],
        angle: 0,
        hjust: [0.5 - :math.sin(angle) / 2],
        offset: [
          {label_offset * :math.sin(angle),
           label_offset * :math.cos(angle) - vjust * Font.ascent(text_look.size)}
        ],
        check_overlap: false,
        ascent: Font.ascent(text_look.size)
      }
    end)
  end

  # A tick at each break, reaching out from the circle along its angle; none where the theme
  # removes them.
  defp ticks(_breaks, _tick_length, :none), do: []

  defp ticks(breaks, tick_length, ticks_look) do
    [
      %Polylines{
        lines: Enum.map(breaks, fn {place, _angle, _label} -> [place, place] end),
        offsets:
          Enum.map(breaks, fn {_place, angle, _label} ->
            [{0.0, 0.0}, {tick_length * :math.sin(angle), tick_length * :math.cos(angle)}]
          end),
        stroke_width: ticks_look.line_width,
        dashes: :none,
        color: List.duplicate(ticks_look.color, length(breaks)),
        opacity: List.duplicate(1.0, length(breaks)),
        line_end: ticks_look.line_end,
        line_join: :round,
        mitre_limit: 10.0
      }
    ]
  end
end
