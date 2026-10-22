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

  # Golden: ggplot2 4.0.3's `position_dodge2()` in R 4.6.1, its `setup_params()` and then
  # `compute_panel()` on each panel of the same table, printed to 17 significant digits: a bar
  # Giggly draws has one edge missing, or an infinite x, only from infinite data, so the tables
  # are built here. They move with `position_dodge2()`.
  describe "compute_layer/2 for dodging by clusters" do
    test "a bar missing an edge is in no cluster and loses its x, the others dodged and padded" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1, 1, 1],
          group: [1, 2, 1, 1, 1],
          x: [1.0, 1.0, 2.0, 3.0, 4.0],
          xmin: [0.75, 0.75, :nan, 2.75, 3.75],
          xmax: [1.25, 1.25, 2.25, :nan, 4.25]
        )

      dodged = dodged_by_clusters(frame)

      assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(dodged, name) end) === [
               [0.875, 1.125, :nan, :nan, 4.0],
               [0.76249999999999996, 1.01249999999999996, :nan, :nan, 3.77499999999999991],
               [0.98750000000000004, 1.23750000000000004, :nan, :nan, 4.22499999999999964]
             ]
    end

    # R fails on the first panel ("non-numeric argument to binary operator"), its clusters' sizes
    # summed over no rows; Giggly leaves its bars as R leaves any bar missing an edge (design-log
    # §4, the entry beginning "Dodging by clusters places each cluster"). The second panel is R's.
    test "a panel where no bar has edges keeps none, the next panel dodged as ever" do
      frame =
        DataFrame.new(
          panel: [1, 1, 2, 2],
          group: [1, 2, 1, 2],
          x: [1.0, 1.0, 1.0, 1.0],
          xmin: [nil, nil, 0.55, 0.55],
          xmax: [nil, nil, 1.45, 1.45]
        )

      dodged = dodged_by_clusters(frame)

      assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(dodged, name) end) === [
               [nil, nil, 0.77500000000000002, 1.22500000000000009],
               [nil, nil, 0.57250000000000001, 1.02250000000000019],
               [nil, nil, 0.97750000000000004, 1.42749999999999999]
             ]
    end

    test "minus infinity comes first, and a missing x last, NA and NaN in the order they came" do
      infinite =
        DataFrame.new(
          panel: [1, 1, 1],
          group: [1, 1, 1],
          x: [2.0, :neg_infinity, -1.0],
          xmin: [1.75, :neg_infinity, -1.25],
          xmax: [2.25, :neg_infinity, -0.75]
        )

      missing =
        DataFrame.new(
          panel: [1, 1, 1],
          group: [1, 2, 3],
          x: [nil, 1.0, :nan],
          xmin: [nil, 0.75, :nan],
          xmax: [nil, 1.25, :nan]
        )

      dodged = dodged_by_clusters(infinite)
      sorted = dodged_by_clusters(missing)

      assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(dodged, name) end) === [
               [:nan, -1.0, 2.0],
               [:nan, -1.25, 1.75],
               [:nan, -0.75, 2.25]
             ]

      assert {DataFrame.pull(sorted, :group), DataFrame.pull(sorted, :x)} ===
               {[2, 1, 3], [1.0, nil, :nan]}
    end

    test "a table without a flipped_aes column is dodged along x, its heights left alone" do
      frame =
        DataFrame.new(
          panel: [1, 1],
          group: [1, 2],
          x: [1.0, 1.0],
          xmin: [0.55, 0.55],
          xmax: [1.45, 1.45],
          y: [2.0, 3.0],
          ymin: [0.0, 0.0],
          ymax: [2.0, 3.0]
        )

      dodged = dodged_by_clusters(frame)

      assert Enum.map([:xmin, :xmax, :ymin, :ymax], fn name -> DataFrame.pull(dodged, name) end) ===
               [
                 [0.57250000000000001, 1.02250000000000019],
                 [0.97750000000000004, 1.42749999999999999],
                 [0.0, 0.0],
                 [2.0, 3.0]
               ]
    end
  end

  # `frame` dodged by clusters with R's defaults: `preserve = "total"`, `padding = 0.1`.
  defp dodged_by_clusters(frame) do
    Position.compute_layer(
      %Position.Dodge2{preserve: :total, padding: 0.1, reverse: false},
      frame
    )
  end
end
