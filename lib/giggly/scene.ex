defmodule Giggly.Scene do
  @moduledoc """
  What a plot draws, independent of any output format: a table of row and column tracks whose
  cells hold drawing primitives. A backend (`Giggly.SVG`) lays the table out at a size and writes
  each primitive.

  A track's size is a weight, ggplot2's `"null"` unit, which takes the space left over in
  proportion to its weight. A cell sits at a row and a column, counting from 1, and holds
  primitives placed in the cell's own units, 0 to 1 across its width and up its height; a
  primitive's sizes, such as a point's radius, are in points (1/72 inch), whatever size the cell
  turns out to be. Today a plot's scene is one row and one column track holding one cell, its
  panel; several tracks, and tracks sized in absolute units or by measuring what they hold, arrive
  with the first cell beside the panel (an axis).
  """

  # A scene is values: it calls nothing, and exports the structs that rendering builds and a
  # backend reads.
  use Boundary, deps: [], exports: [Cell, Points]

  alias Giggly.Scene.Cell

  @enforce_keys [:widths, :heights, :cells]
  defstruct @enforce_keys

  @typedoc "A track's size: a weight, sharing the space the table is given with the other tracks."
  @type track :: {:null, number()}

  @typedoc "Something drawn in a cell."
  @type primitive :: Giggly.Scene.Points.t()

  @typedoc "The column tracks left to right, the row tracks top to bottom, and the cells."
  @type t :: %__MODULE__{widths: [track()], heights: [track()], cells: [Cell.t()]}
end
