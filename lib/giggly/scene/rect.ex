defmodule Giggly.Scene.Rect do
  @moduledoc false

  # A rectangle filling its cell, filled with `fill`, `:none` for no fill, and bordered in `color`,
  # `:none` for no border, with a border `stroke_width` points wide and dashed as `dashes` says, as
  # `Giggly.Scene.Polylines` dashes a line: grid's `rectGrob()` at its default place and size, the
  # whole of its viewport, which is how ggplot2 draws a background and the panel's border.

  @enforce_keys [:fill, :color, :stroke_width, :dashes]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          fill: String.t() | :none,
          color: String.t() | :none,
          stroke_width: float(),
          dashes: Giggly.Scene.Polylines.dashes()
        }
end
