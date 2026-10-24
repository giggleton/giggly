defmodule Giggly.Scene.Cell do
  @moduledoc false

  # One cell of a `Giggly.Scene` table: the rows and columns it spans, counting from 1, whether
  # what is drawn in it is cut off at its edges, and the primitives drawn in it, in drawing order.
  # A cell spans one row and one column, such as the panel's, or several, such as the plot's
  # background over the whole table (gtable's `t`, `b`, `l` and `r`). A clipped cell is `:on`, as
  # gtable's `clip` is, and every other `:off`, so that a mark on the panel's edge shows only the
  # part inside it.
  #
  # A cell's box is its rows and columns, unless it hangs: `{:top, height}` makes the box `height`
  # points tall from the top of its rows, and `{:right, width}` `width` points wide ending at the
  # right of its columns, whatever they measure. An axis is drawn so below a panel with an empty
  # cell under it, which ggplot2 measures as taking no room, so the axis hangs into the empty space
  # below; every bottom axis hangs from its panel's edge, at its own height, and every left axis at
  # its own width, so one narrower than its column sits against its panel, as ggplot2's does.
  #
  # `{:at, {x, y}, {hjust, vjust}, {width, height}}` makes the box `width` by `height` points, its
  # own point `{hjust, vjust}` placed at the point `{x, y}` of its rows and columns, each a share of
  # their width or height from their left or bottom, as grid places a viewport (`viewport(x, y,
  # width, height, just)`); either may lie beyond them. A box of legends is placed so: beside the
  # panels at its justification's point of the room beside them, the same point of its own, and
  # inside them at a point of the panels; and each legend in the box at the box's justification.

  @enforce_keys [:rows, :columns, :clip, :hang, :primitives]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          rows: Range.t(pos_integer(), pos_integer()),
          columns: Range.t(pos_integer(), pos_integer()),
          clip: :on | :off,
          hang:
            :none
            | {:top, number()}
            | {:right, number()}
            | {:at, {number(), number()}, {number(), number()}, {number(), number()}},
          primitives: [Giggly.Scene.primitive()]
        }
end
