defmodule Giggly.Guide.AxisTheta do
  @moduledoc false

  # The axis around a radial panel's circle, ggplot2's `guide_axis_theta()`: drawn inside the
  # panel, over its layers, a tick at each break reaching out from the circle's edge along the
  # break's angle, and the break's label beyond it. Use it through `Giggly.Guide`.
  #
  # It looks as an x axis does (`Giggly.Theme`), as ggplot2's `axis.text.theta` and
  # `axis.ticks.theta` inherit the x axis's look: each tick reaches the theme's tick length out from
  # the circle, and each label's anchor sits the tick length and the labels' margin out, the label
  # justified by its angle so it stands clear of the circle: centred above a break at 12 o'clock,
  # starting to the right of one at 3, hanging below one at 6 and ending to the left of one at 9,
  # its `hjust` `0.5 - sin(angle) / 2` and its `vjust` `0.5 - cos(angle) / 2`, the share of its
  # height below its anchor, as ggplot2 justifies it. Neither is measured nor given room, as
  # ggplot2's are not: the panel has room round its circle. Each label is a text of its own, since
  # each is justified its own way; the labels are drawn and then the ticks, as ggplot2 draws them.

  alias Giggly.{Font, Theme}
  alias Giggly.Scene.{Polylines, Text}

  # The axis drawn from `breaks`, each its place on the circle's edge, its angle clockwise from
  # 12 o'clock and its label, in `theme`'s look: its primitives, placed in the panel's cell.
  @doc false
  @spec draw([Giggly.Coord.theta_break()], Theme.t()) :: [Giggly.Scene.primitive()]
  def draw(breaks, %Theme{
        axis_ticks: ticks_look,
        axis_ticks_length: tick_length,
        axis_text: text_look
      }) do
    label_offset = tick_length + text_look.margin

    labels =
      Enum.map(breaks, fn {{x_place, y_place}, angle, label} ->
        vjust = 0.5 - :math.cos(angle) / 2

        %Text{
          x: [x_place],
          y: [y_place],
          labels: [label],
          widths: [Font.width(label, text_look.size)],
          size: text_look.size,
          color: text_look.color,
          angle: 0,
          hjust: 0.5 - :math.sin(angle) / 2,
          offset:
            {label_offset * :math.sin(angle),
             label_offset * :math.cos(angle) - vjust * Font.ascent(text_look.size)}
        }
      end)

    ticks = %Polylines{
      lines: Enum.map(breaks, fn {place, _angle, _label} -> [place, place] end),
      offsets:
        Enum.map(breaks, fn {_place, angle, _label} ->
          [{0.0, 0.0}, {tick_length * :math.sin(angle), tick_length * :math.cos(angle)}]
        end),
      stroke_width: ticks_look.line_width,
      color: ticks_look.color
    }

    Enum.concat(labels, [ticks])
  end
end
