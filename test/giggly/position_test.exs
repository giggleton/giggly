defmodule Giggly.PositionTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Position}

  describe "compute_layer/2 for nudging" do
    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_rect()` of the same edges under
    # `position_nudge(x = 1, y = -0.5)`. No geom Giggly nudges has edges yet, so the table is built
    # here.
    test "every column in an axis's family moves by that axis's nudge" do
      frame =
        DataFrame.new(
          xmin: [1.0, 2.0],
          xmax: [1.5, 3.0],
          ymin: [0.0, 1.0],
          ymax: [1.0, 2.0],
          nudge_x: [1.0, 1.0],
          nudge_y: [-0.5, -0.5]
        )

      nudged = Position.compute_layer(%Position.Nudge{}, frame)

      assert Enum.map([:xmin, :xmax, :ymin, :ymax], fn name -> DataFrame.pull(nudged, name) end) ===
               [[2.0, 3.0], [2.5, 4.0], [-0.5, 0.5], [0.5, 1.5]]
    end
  end
end
