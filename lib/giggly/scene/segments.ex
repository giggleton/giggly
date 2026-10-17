defmodule Giggly.Scene.Segments do
  @moduledoc false

  # Straight lines, each from its start to its end, given as `{x, y}` in the cell's units, all of
  # one `stroke_width` (in points), each in its `color`, `#RRGGBB`, as opaque as its `opacity`, from
  # 0 to 1, their ends, corners and mitre limit drawn as `Giggly.Scene.Polylines` draws a line's:
  # grid's `segmentsGrob()`, which ggplot2's `GeomPath` draws a layer's lines with when their look
  # varies along them, one segment from each point to the next, in the colour of the point it
  # starts from, and `draw_key_path()` a line's legend key with.

  @enforce_keys [
    :starts,
    :ends,
    :stroke_width,
    :color,
    :opacity,
    :line_end,
    :line_join,
    :mitre_limit
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          starts: [{float(), float()}],
          ends: [{float(), float()}],
          stroke_width: float(),
          color: [String.t()],
          opacity: [float()],
          line_end: Giggly.Scene.Polylines.line_end(),
          line_join: Giggly.Scene.Polylines.line_join(),
          mitre_limit: float()
        }
end
