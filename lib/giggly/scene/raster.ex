defmodule Giggly.Scene.Raster do
  @moduledoc false

  # An image of equal cells, grid's `rasterGrob()`: `fill` and `fill_opacity` hold its cells' colours
  # row by row, the top row first and each left to right, a colour `#RRGGBB` or `:none`, a cell
  # left clear, at its opacity from 0 to 1; the image spans its cell's units from `xmin` to `xmax`
  # across and `ymin` to `ymax` up, its cells stretched to fill it. `interpolate` says whether a
  # viewer blends neighbouring cells, as ggplot2's `geom_raster(interpolate = TRUE)` asks, or
  # draws each as a block of its colour.

  @enforce_keys [:xmin, :xmax, :ymin, :ymax, :fill, :fill_opacity, :interpolate]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          xmin: float(),
          xmax: float(),
          ymin: float(),
          ymax: float(),
          fill: [[String.t() | :none]],
          fill_opacity: [[float()]],
          interpolate: boolean()
        }
end
