defmodule Giggly.Scene.Polylines do
  @moduledoc false

  # Lines, each through its points in order, given as `{x, y}` in the cell's units, all of one
  # `stroke_width` (in points), each in its `color`, `#RRGGBB`, as opaque as its `opacity`, from 0
  # to 1, and never filled: grid's `polylineGrob()`, which ggplot2 draws an axis's ticks and a
  # panel's grid lines with, one line per tick or grid line, and a layer's lines with, one per
  # group, each in its group's colour. `line_end` is
  # how a line's ends are drawn (`:butt`, cut square at the end; `:round`; `:square`, cut square
  # half the line's width beyond it), `line_join` how it turns a corner (`:round`, `:mitre` or
  # `:bevel`), and `mitre_limit` how far a mitred corner may reach, in widths of the line, before
  # it is bevelled: grid's `lineend`, `linejoin` and `linemitre`. `offsets` moves each point a
  # number of points across and up from its place, one `{across, up}` for each point, line by line,
  # as grid adds a unit in points to one in the viewport's own (`unit(x, "npc") + unit(d, "pt")`): a
  # tick reaching out from a circle whose size in points is known only when the scene is laid out.
  # `:none` moves no point.

  @enforce_keys [
    :lines,
    :offsets,
    :stroke_width,
    :color,
    :opacity,
    :line_end,
    :line_join,
    :mitre_limit
  ]
  defstruct @enforce_keys

  @typedoc "How a line's ends are drawn, grid's `lineend`."
  @type line_end :: :butt | :round | :square

  @typedoc "How a line turns a corner, grid's `linejoin`."
  @type line_join :: :round | :mitre | :bevel

  @type t :: %__MODULE__{
          lines: [[{float(), float()}]],
          offsets: :none | [[{float(), float()}]],
          stroke_width: float(),
          color: [String.t()],
          opacity: [float()],
          line_end: line_end(),
          line_join: line_join(),
          mitre_limit: float()
        }
end
