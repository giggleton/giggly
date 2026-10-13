defmodule Giggly.Scene.Text do
  @moduledoc """
  Labels, each at its `x` and `y` in the cell's units, all set at one `size` (in points) and
  `color` and turned `angle` degrees anticlockwise, 0 or 90: grid's `textGrob()`.

  Each label is anchored at its point by its `:middle` or its `:end`, and its baseline sits
  `baseline_offset` points from the point toward the text's top (away from it, when negative),
  the top being up for level text and to the left for text turned 90 degrees. That is how a label
  is centred on a break or hung from the edge of its cell whatever size the cell turns out to be. `widths` holds
  each label's measured width, in points, which the label is drawn at whatever font draws it, so
  the drawing agrees with the space measured for it.
  """

  @enforce_keys [:x, :y, :labels, :widths, :size, :color, :angle, :anchor, :baseline_offset]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          x: [float()],
          y: [float()],
          labels: [String.t()],
          widths: [float()],
          size: float(),
          color: String.t(),
          angle: 0 | 90,
          anchor: :middle | :end,
          baseline_offset: float()
        }
end
