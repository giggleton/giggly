defmodule Giggly.Scene do
  @moduledoc false

  # What a plot draws, independent of any output format: a table whose cells hold drawing
  # primitives. A backend (`Giggly.SVG`) lays the table out at a size and writes each primitive.
  #
  # The table is a list of column widths, left to right, and row heights, top to bottom. Each is a
  # number of points (1/72 inch), for what has a size of its own, such as an axis or a margin,
  # measured when the scene is built; or `:rest`, what the fixed sizes leave of the drawing, which
  # the panel takes, as grid's `"null"` unit does. Today exactly one column and one row are
  # `:rest`; panels sharing the rest arrive with `facet_wrap`. A cell spans one or more rows and
  # columns, counting from 1, as the plot's background spans the whole table, and holds primitives
  # placed in the cell's own units, 0 to 1 across its width and up its height; a primitive's sizes,
  # such as a point's radius or a text's size, are in points, whatever size the cell turns out to
  # be. Cells are drawn in the order listed.

  # A scene is values: it calls nothing, and exports the structs that rendering builds and a
  # backend reads.
  use Boundary, deps: [], exports: [Cell, Points, Polylines, Rect, Text]

  alias Giggly.Scene.Cell

  @enforce_keys [:widths, :heights, :cells]
  defstruct @enforce_keys

  @typedoc """
  A column's width or a row's height: a number of points, or what the fixed sizes leave.
  """
  @type size :: {:points, number()} | :rest

  @typedoc "Something drawn in a cell."
  @type primitive ::
          Giggly.Scene.Points.t()
          | Giggly.Scene.Polylines.t()
          | Giggly.Scene.Rect.t()
          | Giggly.Scene.Text.t()

  @typedoc "The column widths left to right, the row heights top to bottom, and the cells."
  @type t :: %__MODULE__{widths: [size()], heights: [size()], cells: [Cell.t()]}
end
