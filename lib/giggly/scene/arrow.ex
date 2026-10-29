defmodule Giggly.Scene.Arrow do
  @moduledoc false

  # An arrowhead on a line, grid's `arrow()`, as a line of `Giggly.Scene.Segments` or
  # `Giggly.Scene.Polylines` carries one: two arms `length` points long, at `angle` degrees either
  # side of the line's last piece, from its tip at the line's end, at its first point (`:first`),
  # its last (`:last`) or both (`:both`), the first's drawn first. Its shape is worked out in
  # points by the backend, which alone knows a cell's size, so a head keeps its shape whatever the
  # panel's. A head is drawn in its line's stroke, width, dashes, ends and corners, as grid draws
  # one in its line's `gp`: `:open`, the arms alone, or `:closed`, a triangle filled with `fill`,
  # `#RRGGBB` or `:none`, as opaque as `fill_opacity`, from 0 to 1. A head of no length is drawn
  # all the same, three points at its tip, as grid draws one.

  @enforce_keys [:angle, :length, :ends, :type, :fill, :fill_opacity]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          angle: float(),
          length: float(),
          ends: :first | :last | :both,
          type: :open | :closed,
          fill: String.t() | :none,
          fill_opacity: float()
        }
end
