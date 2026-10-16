defmodule Giggly.Scene.Circles do
  @moduledoc false

  # Filled circles, one at each `x` and `y` in the cell's units, all of one `radius`, outline
  # `stroke_width` (both in points) and `color`, each as opaque as its `opacity`, from 0 to 1,
  # outline and fill alike: grid's `circleGrob()`, its colour carrying each point's alpha as
  # ggplot2's `alpha()` gives it. It is what R's graphics engine draws for shape 19, the solid
  # circle that is ggplot2's default point.

  @enforce_keys [:x, :y, :radius, :stroke_width, :color, :opacity]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          x: [float()],
          y: [float()],
          radius: float(),
          stroke_width: float(),
          color: String.t(),
          opacity: [float()]
        }
end
