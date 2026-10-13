defmodule Giggly.Scene.Rect do
  @moduledoc """
  A rectangle filling its cell, filled with `fill` and bordered in `color`, `:none` for no border,
  with a border `stroke_width` points wide: grid's `rectGrob()` at its default place and size, the
  whole of its viewport, which is how ggplot2 draws a background.
  """

  @enforce_keys [:fill, :color, :stroke_width]
  defstruct @enforce_keys

  @type t :: %__MODULE__{fill: String.t(), color: String.t() | :none, stroke_width: float()}
end
