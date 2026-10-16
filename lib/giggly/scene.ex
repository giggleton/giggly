defmodule Giggly.Scene do
  @moduledoc false

  # What a plot draws, independent of any output format: a table whose cells hold drawing
  # primitives. A backend (`Giggly.SVG`) lays the table out at a size and writes each primitive.
  #
  # The table is a list of column widths, left to right, and row heights, top to bottom. Each is a
  # number of points (1/72 inch), for what has a size of its own, such as an axis or a margin,
  # measured when the scene is built; or a share of what the fixed sizes leave of the drawing,
  # `{:rest, weight}`, which a panel takes, as grid's `"null"` unit does: the columns that are a
  # share split the width left in proportion to their weights, and so do the rows. A scene that
  # keeps its proportions (gtable's `respect`) gives every share one scale, the largest that fits
  # both ways, so a panel keeps the shape its weights give it, and the table is centred in the
  # drawing, which it no longer fills. A cell spans one or more rows and columns, counting from 1,
  # as the plot's background spans the whole table, and holds primitives placed in the cell's own
  # units, 0 to 1 across its width and up its height, and offset from there in points where a
  # primitive says so; a primitive's sizes, such as a point's radius or a text's size, are in
  # points, whatever size the cell turns out to be. Cells are drawn in the order listed.
  #
  # A cell may hold a scene of its own among its primitives, a table laid out in the cell's box as
  # gtable nests one table in another, as ggplot2 nests a legend in the plot: its sizes in points
  # take their length, its shares split what they leave of the box, and a table that takes less
  # than the box, all its sizes in points, is centred in it both ways. It never keeps its
  # proportions.

  # A scene is values: it calls nothing, and exports the structs that rendering builds and a
  # backend reads.
  use Boundary, deps: [], exports: [Cell, Circles, Polygons, Polylines, Rect, Rectangles, Text]

  alias Giggly.Scene.Cell

  @enforce_keys [:widths, :heights, :keep_proportions, :cells]
  defstruct @enforce_keys

  @typedoc """
  A column's width or a row's height: a number of points, or a share, by its weight, of what the
  fixed sizes leave.
  """
  @type size :: {:points, number()} | {:rest, number()}

  @typedoc "Something drawn in a cell."
  @type primitive ::
          Giggly.Scene.Circles.t()
          | Giggly.Scene.Polygons.t()
          | Giggly.Scene.Polylines.t()
          | Giggly.Scene.Rect.t()
          | Giggly.Scene.Rectangles.t()
          | Giggly.Scene.Text.t()
          | t()

  @typedoc """
  The column widths left to right, the row heights top to bottom, whether the shares keep their
  proportions, and the cells.
  """
  @type t :: %__MODULE__{
          widths: [size()],
          heights: [size()],
          keep_proportions: boolean(),
          cells: [Cell.t()]
        }
end
