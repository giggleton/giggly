defmodule Giggly.Scene.Text do
  @moduledoc false

  # Labels, each at its `x` and `y` in the cell's units, all set at one `size` (in points) in one
  # font `family` and `face` and turned `angle` degrees anticlockwise: grid's `textGrob()`. A
  # `family` of `""` is the default sans-serif, as R's is; any other is the font's name. The face is
  # `:plain`, `:bold`, `:italic` or `:bold_italic`, grid's `fontface`; it changes how a label is
  # drawn, never its measured width.
  #
  # Each label has its own colour and opacity, `color` an `#RRGGBB` and `opacity` from 0 to 1, as
  # grid's graphical parameters are one per label, so labels in many colours need one text.
  #
  # Each label's anchor is its `offset` in points from its place, `{along, up}`: along the text's
  # baseline and toward its top, the top being up for level text and turned with it otherwise, so
  # a label is centred on a break or hung from the edge of its cell whatever size the cell turns
  # out to be. The anchor is on the label's baseline, at its `hjust` of its width from its start: 0
  # at its start, 0.5 at its middle, 1 at its end, or any fraction between, as grid's `hjust` places
  # it. `widths` holds each label's measured width, in points, which the label is drawn at whatever
  # font draws it, so the drawing agrees with the space measured for it.
  #
  # A text that checks overlap (`check_overlap`, grid's `check.overlap`) draws a label only where its
  # box crosses the box of no label drawn before it, in the order given: the box is its width along
  # the baseline from its anchor's start and `ascent` points up from the baseline, as grid measures
  # a string's height by the ascent of "M". Which labels overlap depends on where they land, so the
  # backend decides it once the boxes are placed, as grid does when it draws.

  @enforce_keys [
    :x,
    :y,
    :labels,
    :widths,
    :size,
    :family,
    :face,
    :color,
    :opacity,
    :angle,
    :hjust,
    :offset,
    :check_overlap,
    :ascent
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          x: [float()],
          y: [float()],
          labels: [String.t()],
          widths: [float()],
          size: float(),
          family: String.t(),
          face: :plain | :bold | :italic | :bold_italic,
          color: [String.t()],
          opacity: [float()],
          angle: number(),
          hjust: [float()],
          offset: [{float(), float()}],
          check_overlap: boolean(),
          ascent: float()
        }
end
