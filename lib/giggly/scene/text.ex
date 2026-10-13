defmodule Giggly.Scene.Text do
  @moduledoc """
  Labels, each at its `x` and `y` in the cell's units, all set at one `size` (in points) and
  `color`: grid's `textGrob()`.

  Each label is anchored at its point by its `:middle` or its `:end`, and its baseline sits
  `baseline_offset` points above the point (below, when negative), which is how a label is
  centred on a break or hung below one whatever size its cell turns out to be. `widths` holds
  each label's measured width, in points, which the label is drawn at whatever font draws it, so
  the drawing agrees with the space measured for it.
  """

  @enforce_keys [:x, :y, :labels, :widths, :size, :color, :anchor, :baseline_offset]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          x: [float()],
          y: [float()],
          labels: [String.t()],
          widths: [float()],
          size: float(),
          color: String.t(),
          anchor: :middle | :end,
          baseline_offset: float()
        }
end
