defmodule Giggly.Scene.Text do
  @moduledoc false

  # Labels, each at its `x` and `y` in the cell's units, all set at one `size` (in points) and
  # `color` and turned `angle` degrees anticlockwise, 0 or 90: grid's `textGrob()`.
  #
  # Each label's anchor is `offset` points from its place, `{along, up}`: along the text's
  # baseline and toward its top, the top being up for level text and to the left for text turned
  # 90 degrees, so a label is centred on a break or hung from the edge of its cell whatever size
  # the cell turns out to be. The anchor is on the label's baseline, at `hjust` of its width from
  # its start: 0 at its start, 0.5 at its middle, 1 at its end, or any fraction between, as grid's
  # `hjust` places it. `widths` holds each label's measured width, in points, which the label is
  # drawn at whatever font draws it, so the drawing agrees with the space measured for it.

  @enforce_keys [:x, :y, :labels, :widths, :size, :color, :angle, :hjust, :offset]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          x: [float()],
          y: [float()],
          labels: [String.t()],
          widths: [float()],
          size: float(),
          color: String.t(),
          angle: 0 | 90,
          hjust: float(),
          offset: {float(), float()}
        }
end
