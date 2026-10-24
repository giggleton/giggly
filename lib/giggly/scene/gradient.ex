defmodule Giggly.Scene.Gradient do
  @moduledoc false

  # A rectangle filling its cell, filled with a linear gradient running up it, from the cell's
  # bottom edge to its top (`direction: :up`), or across it, from its left edge to its right
  # (`:across`), through each of `stops`, its offset from 0 at the start to 1 at the end and its
  # colour, `#RRGGBB`, opaque, with no border, its border's width `stroke_width` points all the
  # same: grid's `rectGrob()` filled with a `linearGradient()`, as ggplot2's colour bar draws its
  # bar in its gradient form, up a vertical bar and across a horizontal one, SVG drawing the colours
  # between the stops.

  @enforce_keys [:stops, :direction, :stroke_width]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          stops: [{float(), String.t()}],
          direction: :up | :across,
          stroke_width: float()
        }
end
