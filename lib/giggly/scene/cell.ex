defmodule Giggly.Scene.Cell do
  @moduledoc """
  One cell of a `Giggly.Scene` table: the row and column it sits at, counting from 1, and the
  primitives drawn in it, in drawing order.
  """

  @enforce_keys [:row, :column, :primitives]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          row: pos_integer(),
          column: pos_integer(),
          primitives: [Giggly.Scene.primitive()]
        }
end
