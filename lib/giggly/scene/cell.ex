defmodule Giggly.Scene.Cell do
  @moduledoc false

  # One cell of a `Giggly.Scene` table: the rows and columns it spans, counting from 1, whether
  # what is drawn in it is cut off at its edges, and the primitives drawn in it, in drawing order.
  # A cell spans one row and one column, such as the panel's, or several, such as the plot's
  # background over the whole table (gtable's `t`, `b`, `l` and `r`). A clipped cell is `:on`, as
  # gtable's `clip` is, and every other `:off`, so that a mark on the panel's edge shows only the
  # part inside it.

  @enforce_keys [:rows, :columns, :clip, :primitives]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          rows: Range.t(pos_integer(), pos_integer()),
          columns: Range.t(pos_integer(), pos_integer()),
          clip: :on | :off,
          primitives: [Giggly.Scene.primitive()]
        }
end
