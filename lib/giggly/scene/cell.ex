defmodule Giggly.Scene.Cell do
  @moduledoc """
  One cell of a `Giggly.Scene` table: the rows and columns it spans, counting from 1, and the
  primitives drawn in it, in drawing order. A cell spans one row and one column, such as the
  panel's, or several, such as the plot's background over the whole table (gtable's `t`, `b`,
  `l` and `r`).
  """

  @enforce_keys [:rows, :columns, :primitives]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          rows: Range.t(pos_integer(), pos_integer()),
          columns: Range.t(pos_integer(), pos_integer()),
          primitives: [Giggly.Scene.primitive()]
        }
end
