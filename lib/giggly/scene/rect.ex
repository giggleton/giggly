defmodule Giggly.Scene.Rect do
  @moduledoc false

  # A rectangle filling its cell, filled with `fill`, `:none` for no fill, at `fill_opacity`, and
  # bordered in `color`, `:none` for no border, at `color_opacity`, each an `#RRGGBB` and an opacity
  # from 0 to 1, with a border `stroke_width` points wide and dashed as `dashes` says, as
  # `Giggly.Scene.Polylines` dashes a line: grid's `rectGrob()` at its default place and size, the
  # whole of its viewport, which is how ggplot2 draws a background and the panel's border.

  @enforce_keys [:fill, :fill_opacity, :color, :color_opacity, :stroke_width, :dashes]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          fill: String.t() | :none,
          fill_opacity: float(),
          color: String.t() | :none,
          color_opacity: float(),
          stroke_width: float(),
          dashes: Giggly.Scene.Polylines.dashes()
        }
end
