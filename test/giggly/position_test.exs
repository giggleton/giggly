defmodule Giggly.PositionTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Position}

  # Both axes continuous, as every test here but the discrete one's draws.
  @continuous %{x: :continuous, y: :continuous}

  describe "compute_layer/3 for nudging" do
    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_rect()` of the same edges under
    # `position_nudge(x = 1, y = -0.5)`.
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

      nudged = Position.compute_layer(%Position.Nudge{}, frame, @continuous)

      assert Enum.map([:xmin, :xmax, :ymin, :ymax], fn name -> DataFrame.pull(nudged, name) end) ===
               [[2.0, 3.0], [2.5, 4.0], [-0.5, 0.5], [0.5, 1.5]]
    end

    # ggplot2 4.0.3's `layer_data()` positions are doubles, whatever the types mapped; R misses a
    # position beside a missing nudge where another nudge along the axis is not 0, and fails where
    # all are, where this departs.
    test "an integer position nudged by an integer comes out a double, missing where it or its " <>
           "nudge is" do
      frame =
        DataFrame.new(
          x: [1, 2, nil],
          y: [1, 2, 3],
          nudge_x: [0.5, nil, 0.5],
          nudge_y: [0, nil, 0]
        )

      nudged = Position.compute_layer(%Position.Nudge{}, frame, @continuous)

      assert {DataFrame.pull(nudged, :x), DataFrame.pull(nudged, :y)} ===
               {[1.5, nil, nil], [1.0, nil, 3.0]}
    end
  end

  describe "compute_layer/3 for dodging" do
    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for position_dodge's page's line ranges
    # over x "a", "a", "b", "b" in groups 1 and 2, printed to 17 significant digits:
    # `position_dodge(width = 0.9)` gives the x, xmin and xmax below; `"dodge"`, no width, leaves
    # x as it is with xmin and xmax at it.
    test "a mark with no sides is given them, its x less and plus half the width given, else its x" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1, 1],
          group: [1, 2, 1, 2],
          x: [1, 1, 2, 2],
          ymin: [1, 2, 3, 4],
          ymax: [3, 4, 5, 6]
        )

      dodged =
        Position.compute_layer(
          %Position.Dodge{width: 0.9, preserve: :total, orientation: :x, reverse: false},
          frame,
          @continuous
        )

      assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(dodged, name) end) === [
               [0.775, 1.225, 1.775, 2.225],
               [0.55, 1.0, 1.5499999999999998, 2.0],
               [1.0, 1.4500000000000002, 2.0, 2.45]
             ]

      unmoved =
        Position.compute_layer(
          %Position.Dodge{width: :none, preserve: :total, orientation: :x, reverse: false},
          frame,
          @continuous
        )

      assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(unmoved, name) end) === [
               [1.0, 1.0, 2.0, 2.0],
               [1.0, 1.0, 2.0, 2.0],
               [1.0, 1.0, 2.0, 2.0]
             ]
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the reference page's error bars, 0.25
    # wide, under `position_dodge(width = 0.9)`, printed to 17 significant digits, at trt 1; under
    # `"dodge"`, within their own width, x 0.9375 and 1.0625.
    test "marks with sides share the width given, else the panel's first mark's, keeping their own" do
      frame =
        DataFrame.new(
          panel: [1, 1],
          group: [1, 2],
          x: [1, 1],
          xmin: [0.875, 0.875],
          xmax: [1.125, 1.125],
          ymax: [1.1, 5.3]
        )

      dodged =
        Position.compute_layer(
          %Position.Dodge{width: 0.9, preserve: :total, orientation: :x, reverse: false},
          frame,
          @continuous
        )

      assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(dodged, name) end) === [
               [0.775, 1.225],
               [0.7125, 1.1625],
               [0.8375, 1.2875000000000001]
             ]

      own =
        Position.compute_layer(
          %Position.Dodge{width: :none, preserve: :total, orientation: :x, reverse: false},
          frame,
          @continuous
        )

      assert DataFrame.pull(own, :x) === [0.9375, 1.0625]
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_point(position =
    # position_dodge(width = 0.9))` of the same rows, printed to 17 significant digits; its
    # columns end `xmin`, `xmax`, `ymax`, after R's `order`, which Giggly does not write.
    test "a mark with no ymax is given its y as one, which it keeps" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1, 1],
          group: [1, 2, 1, 2],
          x: [1.0, 1.0, 2.0, 2.0],
          y: [2.0, 3.0, 4.0, -1.0]
        )

      dodged =
        Position.compute_layer(
          %Position.Dodge{width: 0.9, preserve: :total, orientation: :x, reverse: false},
          frame,
          @continuous
        )

      assert DataFrame.names(dodged) == [:panel, :group, :x, :y, :xmin, :xmax, :ymax]

      assert Enum.map([:x, :xmin, :xmax, :ymax], fn name -> DataFrame.pull(dodged, name) end) ===
               [
                 [0.775, 1.225, 1.775, 2.225],
                 [0.55, 1.0, 1.5499999999999998, 2.0],
                 [1.0, 1.4500000000000002, 2.0, 2.4500000000000002],
                 [2.0, 3.0, 4.0, -1.0]
               ]
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_rect(position = "dodge")` and
    # `"dodge2"` of the same corners, printed to 17 significant digits: each rectangle's x, which
    # it keeps, is the middle of its sides.
    test "a mark with sides and no x, a rectangle, is given their middle as its x" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1],
          group: [1, 2, 1],
          xmin: [0.6, 0.6, 1.6],
          xmax: [1.4, 1.4, 2.4],
          ymin: [0.0, 0.0, 0.0],
          ymax: [2.0, 3.0, 1.0]
        )

      for {position, xmin, xmax} <- [
            {%Position.Dodge{width: :none, preserve: :total, orientation: :x, reverse: false},
             [0.6000000000000001, 1.0, 1.6000000000000001], [1.0, 1.4, 2.4]},
            {%Position.Dodge2{width: :none, preserve: :total, padding: 0.1, reverse: false},
             [0.6200000000000001, 1.02, 1.6400000000000001], [0.98, 1.38, 2.36]}
          ] do
        dodged = Position.compute_layer(position, frame, @continuous)

        assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(dodged, name) end) ===
                 [[0.8, 1.2, 2.0], xmin, xmax]
      end
    end
  end

  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1, printed to 17 significant digits, for
  # `geom_col()` of bars 0.9 wide, groups 1 and 2 at x 1 and 1 alone at 2 in one panel, 2 alone at
  # 3 in the next, `facet_wrap(~f)`, under `position_dodge()` with each option.
  describe "compute_layer/3 for dodging with its options" do
    setup do
      x_positions = [1.0, 1.0, 2.0, 3.0]

      frame =
        DataFrame.new(
          panel: [1, 1, 1, 2],
          group: [1, 2, 1, 2],
          x: x_positions,
          xmin: Enum.map(x_positions, fn x -> x - 0.45 end),
          xmax: Enum.map(x_positions, fn x -> x + 0.45 end),
          ymax: [1.0, 2.0, 3.0, 4.0]
        )

      %{frame: frame}
    end

    test "with :single, each mark takes the share it would among the most groups at any x, in " <>
           "any panel, lone marks the first",
         %{frame: frame} do
      assert placed(dodge(preserve: :single), frame) === [
               [
                 0.77500000000000002,
                 1.22500000000000009,
                 1.77499999999999991,
                 2.77499999999999991
               ],
               [0.55000000000000004, 1.0, 1.54999999999999982, 2.54999999999999982],
               [1.0, 1.4500000000000002, 2.0, 3.0]
             ]
    end

    test "reversed, the highest group at an x comes first, a lone mark where it was",
         %{frame: frame} do
      assert placed(dodge(reverse: true), frame) === [
               [1.22500000000000009, 0.77500000000000002, 2.0, 3.0],
               [1.0, 0.55000000000000004, 1.55000000000000004, 2.54999999999999982],
               [1.4500000000000002, 1.0, 2.4500000000000002, 3.4500000000000002]
             ]
    end

    test "with :single, reversed, a lone mark takes the last share", %{frame: frame} do
      assert placed(dodge(preserve: :single, reverse: true), frame) === [
               [
                 1.22500000000000009,
                 0.77500000000000002,
                 2.22500000000000009,
                 3.22500000000000009
               ],
               [1.0, 0.55000000000000004, 2.0, 3.0],
               [1.4500000000000002, 1.0, 2.4500000000000002, 3.4500000000000002]
             ]
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_point(position =
    # position_dodge(width = 0.9, orientation = "y"))` of points over two continuous axes, two
    # sharing a y, printed to 17 significant digits.
    test "an orientation along y dodges marks that do not say which way they run along y" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1],
          group: [1, 2, 1],
          x: [1.0, 3.0, 2.0],
          y: [2.0, 2.0, 4.0]
        )

      along_y = dodge(width: 0.9, orientation: :y)
      dodged = Position.compute_layer(along_y, frame, @continuous)

      assert Enum.map([:x, :y, :ymin, :ymax], fn name -> DataFrame.pull(dodged, name) end) === [
               [1.0, 3.0, 2.0],
               [1.7749999999999999, 2.2250000000000001, 4.0],
               [1.5499999999999998, 2.0, 3.5499999999999998],
               [2.0, 2.4500000000000002, 4.4500000000000002]
             ]

      told = DataFrame.put(frame, :flipped_aes, [false, false, false])
      along_x = Position.compute_layer(along_y, told, @continuous)

      assert DataFrame.pull(along_x, :y) === [2.0, 2.0, 4.0]
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_point(position =
    # position_dodge(width = 0.9))` of points over a continuous x and a discrete y, R grouping
    # them by colour and y, printed to 17 significant digits. A `flipped_aes` column, as a line's
    # geom writes, is read first, as `has_flipped_aes()` reads it.
    test "marks whose one discrete axis is y are dodged along y, whatever the orientation" do
      frame =
        DataFrame.new(panel: [1, 1, 1], group: [1, 2, 3], x: [2.0, 3.0, 1.0], y: [1, 1, 2])

      levels = %{x: :continuous, y: :discrete}

      for orientation <- [:x, :y] do
        position = dodge(width: 0.9, orientation: orientation)
        dodged = Position.compute_layer(position, frame, levels)

        assert Enum.map([:x, :y, :ymin, :ymax], fn name -> DataFrame.pull(dodged, name) end) === [
                 [2.0, 3.0, 1.0],
                 [0.77500000000000002, 1.22500000000000009, 2.0],
                 [0.55000000000000004, 1.0, 1.55000000000000004],
                 [1.0, 1.4500000000000002, 2.4500000000000002]
               ]
      end

      at_levels = DataFrame.new(panel: [1, 1], group: [1, 2], x: [1, 1], y: [2.0, 2.0])
      along_y = dodge(width: 0.9, orientation: :y)
      along_x = Position.compute_layer(along_y, at_levels, %{x: :discrete, y: :continuous})

      assert DataFrame.pull(along_x, :x) === [0.775, 1.225]

      told = DataFrame.put(frame, :flipped_aes, [false, false, false])
      within = dodge(width: 0.9)
      written = Position.compute_layer(within, told, levels)

      assert DataFrame.pull(written, :y) === [1, 1, 2]
    end
  end

  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1, printed to 17 significant digits, for
  # dodging the rows the mutation pass over step 5 found nothing pinning.
  describe "compute_layer/3 for dodging, the shares at an x" do
    # `geom_point(position = position_dodge(width = 0.9, preserve = ...))` of two points of group 1
    # and one of group 2 at x 1, one of group 1 at 2.
    test "a group with two marks at an x counts once among its groups, either way" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1, 1],
          group: [1, 1, 2, 1],
          x: [1.0, 1.0, 1.0, 2.0],
          y: [1.0, 2.0, 3.0, 4.0]
        )

      for {preserve, last} <- [{:total, 2.0}, {:single, 1.77499999999999991}] do
        position = dodge(width: 0.9, preserve: preserve)
        dodged = Position.compute_layer(position, frame, @continuous)

        assert DataFrame.pull(dodged, :x) ===
                 [0.77500000000000002, 0.77500000000000002, 1.22500000000000009, last]
      end
    end

    # `geom_col(position = position_dodge(reverse = TRUE))` of three groups at x 1 and two at 2.
    test "reversed, each x's marks are ranked from its own highest group" do
      x_positions = [1.0, 1.0, 1.0, 2.0, 2.0]

      frame =
        DataFrame.new(
          panel: [1, 1, 1, 1, 1],
          group: [1, 2, 3, 1, 2],
          x: x_positions,
          xmin: Enum.map(x_positions, fn x -> x - 0.45 end),
          xmax: Enum.map(x_positions, fn x -> x + 0.45 end),
          ymax: [1.0, 2.0, 3.0, 4.0, 5.0]
        )

      assert placed(dodge(reverse: true), frame) === [
               [
                 1.30000000000000004,
                 1.0,
                 0.69999999999999996,
                 2.22500000000000009,
                 1.77499999999999991
               ],
               [
                 1.15000000000000013,
                 0.84999999999999998,
                 0.54999999999999993,
                 2.0,
                 1.54999999999999982
               ],
               [
                 1.44999999999999996,
                 1.14999999999999991,
                 0.84999999999999998,
                 2.45000000000000018,
                 2.0
               ]
             ]
    end

    # `geom_col(aes(width = w), just = 0, position = "dodge")` of bars 0.4 and 0.8 wide from x 1:
    # the panel's first width spaces them, the widest sizes each share.
    test "the widest mark at an xmin sizes every share" do
      frame =
        DataFrame.new(
          panel: [1, 1],
          group: [1, 2],
          x: [1.0, 1.0],
          xmin: [1.0, 1.0],
          xmax: [1.0 + 0.4, 1.0 + 0.8],
          ymax: [1.0, 2.0]
        )

      assert placed(dodge([]), frame) === [
               [0.90000000000000002, 1.10000000000000009],
               [0.69999999999999996, 0.90000000000000013],
               [1.1000000000000001, 1.3]
             ]
    end

    # R's `pos_dodge()` gives rows missing their x a missing `xmin`, dodged together to NA.
    test "marks missing their x share a missing xmin and stay missing, the rest dodged" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1, 1],
          group: [1, 2, 1, 2],
          x: [nil, nil, 1.0, 1.0],
          y: [1.0, 2.0, 3.0, 4.0]
        )

      within = dodge(width: 0.9)
      dodged = Position.compute_layer(within, frame, @continuous)

      assert {DataFrame.pull(dodged, :x), DataFrame.pull(dodged, :xmin)} ===
               {[nil, nil, 0.775, 1.225], [nil, nil, 0.55, 1.0]}
    end
  end

  # The position columns `position` leaves `frame`'s marks at: their x, xmin and xmax.
  defp placed(position, frame) do
    dodged = Position.compute_layer(position, frame, @continuous)
    Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(dodged, name) end)
  end

  # Dodging with `options`, each not given its default.
  defp dodge(options) do
    defaults = [width: :none, preserve: :total, orientation: :x, reverse: false]
    struct!(Position.Dodge, Keyword.merge(defaults, options))
  end

  # Golden: ggplot2 4.0.3's `position_dodge2()` in R 4.6.1, its `setup_params()` and then
  # `compute_panel()` on each panel of the same table, printed to 17 significant digits: a bar
  # Giggly draws has one edge missing, or an infinite x, only from infinite data, so the tables
  # are built here. They move with `position_dodge2()`.
  describe "compute_layer/3 for dodging by clusters" do
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

    # R's `layer_data()` for `geom_rect(position = position_dodge2(preserve = "single"))` of the
    # same rectangles divides by the panel's one cluster: x 0.6 and 1.4, xmin 0.24 and 1.04, xmax
    # 0.96 and 1.76, where this departs.
    test "with :single, rectangles are counted at the middle of their sides, as every mark" do
      frame =
        DataFrame.new(
          panel: [1, 1],
          group: [1, 2],
          xmin: [0.6, 0.6],
          xmax: [1.4, 1.4],
          ymin: [0.0, 0.0],
          ymax: [2.0, 3.0]
        )

      single = %Position.Dodge2{width: :none, preserve: :single, padding: 0.1, reverse: false}
      dodged = Position.compute_layer(single, frame, @continuous)

      assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(dodged, name) end) === [
               [0.8, 1.2],
               [0.6200000000000001, 1.02],
               [0.98, 1.38]
             ]
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

  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_point(position =
  # position_dodge2(width = 0.5))`, printed to 17 significant digits.
  describe "compute_layer/3 for dodging by clusters within a width" do
    test "each mark with no edges is given them, half the width each side, and dodged as a bar" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1, 1],
          group: [1, 2, 2, 1],
          x: [1.0, 1.0, 1.0, 2.0],
          y: [1.0, 2.0, 3.0, 4.0]
        )

      position = %Position.Dodge2{width: 0.5, preserve: :total, padding: 0.1, reverse: false}
      dodged = Position.compute_layer(position, frame, @continuous)

      assert Enum.map([:x, :xmin, :xmax, :y], fn name -> DataFrame.pull(dodged, name) end) === [
               [0.83333333333333326, 1.0, 1.16666666666666652, 2.0],
               [
                 0.75833333333333330,
                 0.92500000000000004,
                 1.09166666666666656,
                 1.77499999999999991
               ],
               [
                 0.90833333333333321,
                 1.07499999999999996,
                 1.24166666666666647,
                 2.22500000000000009
               ],
               [1.0, 2.0, 3.0, 4.0]
             ]
    end
  end

  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_area(stat = "identity")` of the
  # same rows, each band set up from 0 to its y as the area geom sets it up and in its order.
  describe "compute_layer/3 for stacking marks with only a y" do
    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_point(position = "stack")` of
    # the same rows: R stacks them by their y, writing `ymax`, then `xmin` and `xmax`, then `ymin`.
    test "each mark piles by its y, its ymin and ymax its stretch of the pile" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1, 1],
          group: [1, 2, 1, 2],
          x: [1.0, 1.0, 2.0, 2.0],
          y: [2.0, 3.0, 4.0, -1.0]
        )

      stacked = Position.compute_layer(%Position.Stack{}, frame, @continuous)

      assert DataFrame.names(stacked) == [:panel, :group, :x, :y, :ymax, :xmin, :xmax, :ymin]

      assert Enum.map([:y, :ymin, :ymax, :xmin, :xmax], fn name ->
               DataFrame.pull(stacked, name)
             end) ===
               [
                 [5.0, 3.0, 4.0, 0.0],
                 [3.0, 0.0, 0.0, -1.0],
                 [5.0, 3.0, 4.0, 0.0],
                 [1.0, 1.0, 2.0, 2.0],
                 [1.0, 1.0, 2.0, 2.0]
               ]
    end
  end

  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_point(position = "stack")` over a
  # continuous x and a discrete y.
  describe "compute_layer/3 for stacking marks whose one discrete axis is y" do
    test "the marks at a level pile along x" do
      frame =
        DataFrame.new(panel: [1, 1, 1], group: [1, 2, 3], x: [2.0, 3.0, 1.0], y: [1, 1, 2])

      stacked =
        Position.compute_layer(%Position.Stack{}, frame, %{x: :continuous, y: :discrete})

      assert Enum.map([:x, :xmin, :xmax, :y], fn name -> DataFrame.pull(stacked, name) end) === [
               [5.0, 3.0, 1.0],
               [3.0, 0.0, 0.0],
               [5.0, 3.0, 1.0],
               [1, 1, 2]
             ]
    end
  end

  describe "compute_layer/3 for stacking areas" do
    test "each row's xmin and xmax is its x, and the bands at an x pile up, the first group on top" do
      stacked =
        Position.compute_layer(%Position.Stack{}, area_rows([1.0, 3.0, 2.0, 4.0]), @continuous)

      assert Enum.map([:y, :ymin, :ymax, :xmin, :xmax], fn name ->
               DataFrame.pull(stacked, name)
             end) ===
               [
                 [3.0, 7.0, 2.0, 4.0],
                 [2.0, 4.0, 0.0, 0.0],
                 [3.0, 7.0, 2.0, 4.0],
                 [1.0, 2.0, 1.0, 2.0],
                 [1.0, 2.0, 1.0, 2.0]
               ]
    end

    test "a band below zero piles down from zero, keeping its ymax below its ymin" do
      stacked =
        Position.compute_layer(%Position.Stack{}, area_rows([1.0, -3.0, -2.0, 4.0]), @continuous)

      assert Enum.map([:y, :ymin, :ymax], fn name -> DataFrame.pull(stacked, name) end) ===
               [[1.0, 0.0, 0.0, 4.0], [0.0, 0.0, 0.0, 0.0], [1.0, -3.0, -2.0, 4.0]]
    end
  end

  # Golden: ggplot2 4.0.3 in R 4.6.1, `position_stack()` and `position_fill()` run through their
  # own `setup_params()`, `setup_data()` and `compute_panel()` on the same rows, so a NaN stays
  # NaN, where `layer_data()`'s scales make it missing. They move with a pile's order, where its
  # vjust sets a y, or filling's division and its threshold.
  describe "compute_layer/3 for stacking with its options, and for filling" do
    test "vjust moves each bar's y up its stretch, its edges where they were" do
      for {vjust, y} <- [{0.5, [3.5, 1.5, 3.0, 1.0]}, {2.0, [5.0, 6.0, 6.0, 4.0]}] do
        stacked = stacked_columns(%Position.Stack{vjust: vjust}, bar_rows([1.0, 3.0, 2.0, 2.0]))
        assert stacked == [y, [3.0, 0.0, 2.0, 0.0], [4.0, 3.0, 4.0, 2.0]]
      end
    end

    test "reversed, the lowest group is at the bottom of the pile, in whatever order the rows " <>
           "arrive" do
      assert stacked_columns(%Position.Stack{reverse: true}, bar_rows([1.0, 3.0, 2.0, 2.0])) ===
               [[1.0, 4.0, 2.0, 4.0], [0.0, 1.0, 0.0, 2.0], [1.0, 4.0, 2.0, 4.0]]

      highest_first = bar_rows([1.0, 1.0, 2.0, 2.0], [2, 1, 2, 1], [1.0, 3.0, 2.0, 2.0])

      assert stacked_columns(%Position.Stack{reverse: true}, highest_first) ===
               [[4.0, 3.0, 4.0, 2.0], [3.0, 0.0, 2.0, 0.0], [4.0, 3.0, 4.0, 2.0]]
    end

    test "filled, each pile reaches 1, and its options move it as stacking's do" do
      rows = bar_rows([1.0, 3.0, 2.0, 2.0])

      assert stacked_columns(%Position.Stack{fill: true}, rows) ===
               [[1.0, 0.75, 1.0, 0.5], [0.75, 0.0, 0.5, 0.0], [1.0, 0.75, 1.0, 0.5]]

      assert stacked_columns(%Position.Stack{fill: true, vjust: 0.5, reverse: true}, rows) ===
               [[0.125, 0.625, 0.25, 0.75], [0.0, 0.25, 0.0, 0.5], [0.25, 1.0, 0.5, 1.0]]
    end

    test "a point's y moves up the stretch stacking gives it" do
      frame = DataFrame.new(panel: [1, 1], group: [1, 2], x: [1.0, 1.0], y: [2.0, 3.0])
      stacked = Position.compute_layer(%Position.Stack{vjust: 0.5}, frame, @continuous)

      assert Enum.map([:y, :ymin, :ymax], fn name -> DataFrame.pull(stacked, name) end) ===
               [[4.0, 1.5], [3.0, 0.0], [5.0, 3.0]]
    end

    test "with every x apart, only filling and a vjust other than 1 stack the bars" do
      rows =
        DataFrame.new(
          panel: [1, 1, 1],
          group: [1, 2, 1],
          x: [1.0, 2.0, 3.0],
          xmin: [0.55, 1.55, 2.55],
          xmax: [1.45, 2.45, 3.45],
          y: [2.0, -3.0, 4.0],
          ymin: [0.0, 0.0, 0.0],
          ymax: [2.0, -3.0, 4.0]
        )

      for {position, columns} <- [
            {%Position.Stack{reverse: true},
             [[2.0, -3.0, 4.0], [0.0, 0.0, 0.0], [2.0, -3.0, 4.0]]},
            {%Position.Stack{vjust: 0.5}, [[1.0, -1.5, 2.0], [0.0, 0.0, 0.0], [2.0, -3.0, 4.0]]},
            {%Position.Stack{fill: true}, [[1.0, 0.0, 1.0], [0.0, 0.0, 0.0], [1.0, -1.0, 1.0]]}
          ] do
        assert {position, stacked_columns(position, rows)} === {position, columns}
      end
    end

    test "filled, a pile below zero reaches -1 and one totalling no more than R's " <>
           "sqrt(.Machine$double.eps) is left as it is" do
      signs =
        bar_rows([1.0, 1.0, 1.0], [1, 2, 3], [1.0, -2.0, -2.0])

      assert stacked_columns(%Position.Stack{fill: true}, signs) ===
               [[1.0, -0.5, 0.0], [0.0, -0.5, 0.0], [1.0, -1.0, -0.5]]

      zero = bar_rows([1.0, 1.0], [1, 2], [0.0, 0.0])

      assert stacked_columns(%Position.Stack{fill: true}, zero) ===
               [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]

      for {height, filled} <- [
            {1.0e-9, [[2.0e-9, 1.0e-9], [1.0e-9, 0.0], [2.0e-9, 1.0e-9]]},
            {1.0e-7, [[1.0, 0.5], [0.5, 0.0], [1.0, 0.5]]}
          ] do
        tiny = bar_rows([1.0, 1.0], [1, 2], [height, height])
        assert {height, stacked_columns(%Position.Stack{fill: true}, tiny)} === {height, filled}
      end
    end

    test "filled, a pile reaching infinity leaves its bars below at 0, the infinite one NaN" do
      infinite = bar_rows([1.0, 1.0], [1, 2], [:infinity, 2.0])

      assert stacked_columns(%Position.Stack{fill: true}, infinite) ===
               [[:nan, 0.0], [:nan, 0.0], [:nan, 0.0]]
    end

    # A departure: R fails ("missing value where TRUE/FALSE needed") filling a pile whose total
    # is NaN; Giggly divides by it, so its marks are missing and not drawn.
    test "filled, a pile holding both infinities, its total NaN, has every height NaN" do
      both =
        DataFrame.new(
          panel: [1, 1],
          group: [1, 2],
          x: [1.0, 1.0],
          y: [:infinity, :neg_infinity],
          ymin: [0.0, 0.0],
          ymax: [1.0, 1.0]
        )

      assert stacked_columns(%Position.Stack{}, both) ===
               [[:nan, :nan], [:nan, :neg_infinity], [:nan, 0.0]]

      assert stacked_columns(%Position.Stack{fill: true}, both) ===
               [[:nan, :nan], [:nan, :nan], [:nan, :nan]]
    end
  end

  # R's jitter is drawn from R's own random numbers, which Giggly does not reproduce, so these pin
  # the distances to Erlang's `exsss` numbers from the seed (`draws/2`), and R's own rules, each
  # checked in ggplot2 4.0.3 with R 4.6.1: a distance is `-amount + 2 * amount * u`, as R's
  # `runif()` scales a draw; each panel draws from the seed afresh, so panels with as many rows
  # move them alike; an amount not given is 0.4 of each panel's closest spacing.
  describe "compute_layer/3 for jittering" do
    test "each row draws across then up from its panel's numbers, each panel's from the seed" do
      frame =
        DataFrame.new(
          panel: [1, 2, 1, 2],
          x: [1.0, 3.0, 2.0, 4.0],
          y: [5.0, 6.0, 7.0, 8.0]
        )

      jittered =
        Position.compute_layer(
          %Position.Jitter{width: 0.4, height: 0.2, seed: 5},
          frame,
          @continuous
        )

      [first_across, first_up, second_across, second_up] = draws(5, 4)

      assert {DataFrame.pull(jittered, :x), DataFrame.pull(jittered, :y)} ===
               {[
                  1.0 + distance(first_across, 0.4),
                  3.0 + distance(first_across, 0.4),
                  2.0 + distance(second_across, 0.4),
                  4.0 + distance(second_across, 0.4)
                ],
                [
                  5.0 + distance(first_up, 0.2),
                  6.0 + distance(first_up, 0.2),
                  7.0 + distance(second_up, 0.2),
                  8.0 + distance(second_up, 0.2)
                ]}

      assert DataFrame.names(jittered) === [:panel, :x, :y]
    end

    # R: x 1 and 3 in one panel move up to 0.8, x 1 and 1.5 in another up to 0.2; a discrete
    # axis's levels 1 and 3, integers here as R's are `mapped_discrete`, up to 0.4.
    test "an amount not given is 0.4 of the closest spacing of each panel's positions" do
      apart =
        DataFrame.new(
          panel: [1, 1, 2, 2],
          x: [1.0, 3.0, 1.0, 1.5],
          y: [0.0, 0.0, 0.0, 0.0]
        )

      levels = DataFrame.new(panel: [1, 1], x: [1, 3], y: [0.0, 0.0])
      position = %Position.Jitter{width: :none, height: 0.0, seed: 1}
      [first, _first_up, second, _second_up] = draws(1, 4)

      jittered_apart = Position.compute_layer(position, apart, @continuous)
      jittered_levels = Position.compute_layer(position, levels, %{x: :discrete, y: :continuous})

      assert DataFrame.pull(jittered_apart, :x) === [
               1.0 + distance(first, 0.8),
               3.0 + distance(second, 0.8),
               1.0 + distance(first, 0.2),
               1.5 + distance(second, 0.2)
             ]

      assert DataFrame.pull(jittered_levels, :x) ===
               [1.0 + distance(first, 0.4), 3.0 + distance(second, 0.4)]
    end

    test "every position on an axis moves by its row's distance, a missing or infinite one stays" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1],
          x: [1.0, nil, :infinity],
          xmin: [0.5, 0.5, 0.5],
          y: [2.0, 2.0, 2.0],
          ymax: [3.0, :neg_infinity, nil],
          size: [1.5, 1.5, 1.5]
        )

      jittered =
        Position.compute_layer(
          %Position.Jitter{width: 0.3, height: 0.1, seed: 2},
          frame,
          @continuous
        )

      [across, up, second_across, second_up, third_across, third_up] = draws(2, 6)

      assert Enum.map([:x, :xmin, :y, :ymax, :size], fn name -> DataFrame.pull(jittered, name) end) ===
               [
                 [1.0 + distance(across, 0.3), nil, :infinity],
                 [
                   0.5 + distance(across, 0.3),
                   0.5 + distance(second_across, 0.3),
                   0.5 + distance(third_across, 0.3)
                 ],
                 [
                   2.0 + distance(up, 0.1),
                   2.0 + distance(second_up, 0.1),
                   2.0 + distance(third_up, 0.1)
                 ],
                 [3.0 + distance(up, 0.1), :neg_infinity, nil],
                 [1.5, 1.5, 1.5]
               ]
    end

    test "an amount of 0 moves nothing, and leaves the other axis's distances as they were" do
      frame = DataFrame.new(panel: [1, 1], x: [1, 2], y: [3, 4])

      still =
        Position.compute_layer(
          %Position.Jitter{width: 0.0, height: 0.5, seed: 9},
          frame,
          @continuous
        )

      moved =
        Position.compute_layer(
          %Position.Jitter{width: 0.3, height: 0.5, seed: 9},
          frame,
          @continuous
        )

      assert DataFrame.pull(still, :x) === [1.0, 2.0]
      assert DataFrame.pull(still, :y) === DataFrame.pull(moved, :y)
      assert DataFrame.pull(moved, :x) !== [1.0, 2.0]
    end

    # R's `resolution(c(1, 1, -Inf))` counts the gap to minus infinity, so its jitter is infinite
    # and sends the finite points to an infinity; Giggly's spacing leaves an infinity out.
    test "positions whose only gap is to an infinity are 1 apart, moving up to 0.4" do
      frame = DataFrame.new(panel: [1, 1, 1], x: [1.0, 2.0, 3.0], y: [1.0, 1.0, :neg_infinity])

      jittered =
        Position.compute_layer(
          %Position.Jitter{width: 0.0, height: :none, seed: 4},
          frame,
          @continuous
        )

      [_first_across, first_up, _second_across, second_up | _rest] = draws(4, 6)

      assert DataFrame.pull(jittered, :y) ===
               [1.0 + distance(first_up, 0.4), 1.0 + distance(second_up, 0.4), :neg_infinity]
    end
  end

  describe "compute_layer/3 for jittering, given what Plot never gives" do
    # A layer's `position: {:jitter, options}` keeps every amount as a float, so an integer is a
    # programmer error, refused rather than drawn from.
    test "an amount that is not a float is refused" do
      frame = DataFrame.new(panel: [1], x: [1.0], y: [1.0])

      assert_raise FunctionClauseError, fn ->
        Position.compute_layer(
          %Position.Jitter{width: untyped(1), height: :none, seed: 0},
          frame,
          @continuous
        )
      end
    end
  end

  # R's jitter is not reproduced (see jittering's tests), so these pin the dodge to ggplot2 4.0.3's
  # `layer_data()` in R 4.6.1 with `jitter.width = 0`, and the jitter to `exsss`'s numbers from the
  # seed at R's amounts: `width / (ndodge + 2)`, ndodge the most groups at one x in any panel, the
  # width not given 0.4 of the layer's closest spacing over every panel (`jd_edges.R`, the
  # positions sweep's `jd_*` cells).
  describe "compute_layer/3 for jittering beside dodging" do
    # R: `geom_point(aes(xd, y, colour = g), position = position_jitterdodge(jitter.width = 0))`,
    # its rows unsorted, three groups at p, two at q and r; the same as `position_dodge(width =
    # 0.75)`, and as R draws it with `reverse = TRUE`.
    test "dodges the groups at each position within 0.75, lowest first, and gives a point a top" do
      frame =
        DataFrame.new(
          panel: List.duplicate(1, 7),
          group: [5, 3, 1, 4, 2, 7, 6],
          x: [2, 1, 1, 2, 1, 3, 3],
          y: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]
        )

      dodged = Position.compute_layer(still(), frame, %{x: :discrete, y: :continuous})

      assert Enum.map([:x, :xmin, :xmax, :ymax], fn name -> DataFrame.pull(dodged, name) end) ===
               [
                 [2.1875, 1.25, 0.75, 1.8125, 1.0, 3.1875, 2.8125],
                 [2.0, 1.125, 0.625, 1.625, 0.875, 3.0, 2.625],
                 [2.375, 1.375, 0.875, 2.0, 1.125, 3.375, 3.0],
                 [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]
               ]
    end

    # R: `geom_col(position = position_jitterdodge(jitter.width = 0))`, bars 0.9 wide.
    test "a bar keeps its own width over the number of groups, centred in its share" do
      dodged =
        Position.compute_layer(still(), bar_rows([1.0, 1.0], [1, 2], [3.0, 4.0]), @continuous)

      assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(dodged, name) end) ===
               [[0.8125, 1.1875], [0.5875, 0.9625], [1.0375, 1.4125]]
    end

    # R: the most groups at one x set the amount in every panel, 0.4 / 5 on a discrete axis; a
    # panel of two groups beside one of three jitters at most 0.0797 (`jd_panels.R`).
    test "the sideways amount is 0.4 over the most groups at one x in any panel plus 2" do
      frame =
        DataFrame.new(
          panel: [1, 1, 2, 2, 2],
          group: [1, 2, 1, 2, 3],
          x: [1, 1, 1, 1, 1],
          y: [1.0, 2.0, 3.0, 4.0, 5.0]
        )

      jittered =
        Position.compute_layer(
          %Position.Jitterdodge{
            jitter_width: :none,
            jitter_height: 0.0,
            dodge_width: 0.75,
            seed: 3
          },
          frame,
          %{x: :discrete, y: :continuous}
        )

      [first, _, second, _] = draws(3, 4)
      [_, _, _, _, third, _] = draws(3, 6)
      # 0.4 of a discrete axis's spacing, 1, over three groups plus 2.
      amount = 0.4 / 5

      assert DataFrame.pull(jittered, :x) === [
               0.8125 + distance(first, amount),
               1.1875 + distance(second, amount),
               0.75 + distance(first, amount),
               1.0 + distance(second, amount),
               1.25 + distance(third, amount)
             ]
    end

    # R: points at p and r of a discrete axis whose scale holds p, q and r move at most 0.0996,
    # inside 0.4 / 4, where their positions, 1 and 3, are 2 apart (`jd_mutants.R`).
    test "a discrete axis's positions are 1 apart, whatever levels the layer holds" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1, 1],
          group: [1, 2, 1, 2],
          x: [1, 1, 3, 3],
          y: [0.0, 0.0, 0.0, 0.0]
        )

      jittered =
        Position.compute_layer(
          %Position.Jitterdodge{
            jitter_width: :none,
            jitter_height: 0.0,
            dodge_width: 0.75,
            seed: 5
          },
          frame,
          %{x: :discrete, y: :continuous}
        )

      [first, _, second, _, third, _, fourth, _] = draws(5, 8)

      # 0.4 of a discrete axis's spacing, 1, over two groups at each x plus 2.
      amount = 0.4 / 4

      assert DataFrame.pull(jittered, :x) === [
               0.8125 + distance(first, amount),
               1.1875 + distance(second, amount),
               2.8125 + distance(third, amount),
               3.1875 + distance(fourth, amount)
             ]
    end

    # R: continuous x at 0.25 and 2.25 move at most 0.199, inside 0.4 * 2 / 4, where counting the
    # gap from zero would make the spacing 0.25 (`jd_mutants.R`).
    test "a continuous axis's spacing is the closest gap between its positions, not from zero" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1, 1],
          group: [1, 2, 1, 2],
          x: [0.25, 0.25, 2.25, 2.25],
          y: [0.0, 0.0, 0.0, 0.0]
        )

      jittered =
        Position.compute_layer(
          %Position.Jitterdodge{
            jitter_width: :none,
            jitter_height: 0.0,
            dodge_width: 0.75,
            seed: 5
          },
          frame,
          @continuous
        )

      [first, _, second, _, third, _, fourth, _] = draws(5, 8)
      amount = 0.4 * 2.0 / 4

      assert DataFrame.pull(jittered, :x) === [
               0.0625 + distance(first, amount),
               0.4375 + distance(second, amount),
               2.0625 + distance(third, amount),
               2.4375 + distance(fourth, amount)
             ]
    end

    # R: `geom_col(aes(width = w))` of bars at 1 and 1.25, 0.5 and 1 wide, both from xmin 0.75:
    # two groups share the widest bar's width; one group keeps each bar as it is.
    test "the marks at one xmin take the widest one's width over n, one group none" do
      bars = fn group ->
        DataFrame.new(
          panel: [1, 1],
          group: group,
          x: [1.0, 1.25],
          xmin: [0.75, 0.75],
          xmax: [1.25, 1.75],
          y: [2.0, 3.0]
        )
      end

      apart = Position.compute_layer(still(), bars.([1, 2]), @continuous)
      together = Position.compute_layer(still(), bars.([1, 1]), @continuous)

      assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(apart, name) end) ===
               [[0.8125, 1.4375], [0.5625, 1.1875], [1.0625, 1.6875]]

      assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(together, name) end) ===
               [[1.0, 1.25], [0.75, 0.75], [1.25, 1.75]]
    end

    # R: positions 0.5 apart in one panel and alone in the others move at most 0.4 * 0.5 / 4 in
    # every panel, where jittering alone works out each panel's.
    test "the amount not given is worked out over the whole layer, before dodging" do
      frame =
        DataFrame.new(
          panel: [1, 1, 2, 2, 3, 3],
          group: [1, 2, 1, 2, 1, 2],
          x: [2.0, 2.0, 1.5, 1.5, 1.0, 1.0],
          y: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        )

      jittered =
        Position.compute_layer(
          %Position.Jitterdodge{
            jitter_width: :none,
            jitter_height: 0.0,
            dodge_width: 0.75,
            seed: 8
          },
          frame,
          @continuous
        )

      [first, _, second, _] = draws(8, 4)
      amount = 0.4 * 0.5 / 4

      assert DataFrame.pull(jittered, :x) === [
               1.8125 + distance(first, amount),
               2.1875 + distance(second, amount),
               1.3125 + distance(first, amount),
               1.6875 + distance(second, amount),
               0.8125 + distance(first, amount),
               1.1875 + distance(second, amount)
             ]
    end

    # R: `jitter.width = 0.5` beside two groups moves at most 0.125, `jitter.height = 0.3` at most
    # 0.3, its edges with its x.
    test "a width given is divided among the groups too, and a height given is not" do
      frame = DataFrame.new(panel: [1, 1], group: [1, 2], x: [1.0, 1.0], y: [2.0, 3.0])

      jittered =
        Position.compute_layer(
          %Position.Jitterdodge{
            jitter_width: 0.5,
            jitter_height: 0.3,
            dodge_width: 0.75,
            seed: 4
          },
          frame,
          @continuous
        )

      [first_across, first_up, second_across, second_up] = draws(4, 4)
      across = 0.5 / 4

      assert Enum.map([:x, :xmin, :y, :ymax], fn name -> DataFrame.pull(jittered, name) end) ===
               [
                 [
                   0.8125 + distance(first_across, across),
                   1.1875 + distance(second_across, across)
                 ],
                 [0.625 + distance(first_across, across), 1.0 + distance(second_across, across)],
                 [2.0 + distance(first_up, 0.3), 3.0 + distance(second_up, 0.3)],
                 [2.0 + distance(first_up, 0.3), 3.0 + distance(second_up, 0.3)]
               ]
    end

    # R: points over a continuous x and a discrete y are dodged and jittered sideways along y, the
    # levels 1 apart however many the layer holds, as along x.
    test "marks whose one discrete axis is y are dodged and jittered sideways along y" do
      frame =
        DataFrame.new(panel: [1, 1, 1], group: [1, 2, 1], x: [2.0, 3.0, 4.0], y: [1, 1, 3])

      jittered =
        Position.compute_layer(
          %Position.Jitterdodge{
            jitter_width: :none,
            jitter_height: 0.3,
            dodge_width: 0.75,
            seed: 6
          },
          frame,
          %{x: :continuous, y: :discrete}
        )

      [first_across, first_up, second_across, second_up, third_across, third_up] = draws(6, 6)
      # 0.4 of a discrete axis's spacing, 1, over two groups plus 2.
      sideways = 0.4 / 4

      assert Enum.map([:x, :y, :ymin], fn name -> DataFrame.pull(jittered, name) end) === [
               [
                 2.0 + distance(first_across, 0.3),
                 3.0 + distance(second_across, 0.3),
                 4.0 + distance(third_across, 0.3)
               ],
               [
                 0.8125 + distance(first_up, sideways),
                 1.1875 + distance(second_up, sideways),
                 3 + distance(third_up, sideways)
               ],
               [
                 0.625 + distance(first_up, sideways),
                 1.0 + distance(second_up, sideways),
                 2.625 + distance(third_up, sideways)
               ]
             ]
    end

    # R: x 1, 1, NA, 2, 2 of groups a, b, a, a, b dodge to 0.8125, 1.1875, NA, 1.8125, 2.1875;
    # and x 1, 1, NA, NA, 2 of groups a, b, a, b, a to 0.8125, 1.1875, NA, NA, 2, the missing
    # pair two groups at no position (`jd_mutants.R`).
    test "a row missing its x or y stays missing, and the rest dodge as R's" do
      frame =
        DataFrame.new(
          panel: [1, 1, 1, 1, 1],
          group: [1, 2, 1, 1, 2],
          x: [1.0, 1.0, nil, 2.0, 2.0],
          y: [1.0, 2.0, 3.0, nil, 5.0]
        )

      pair =
        DataFrame.new(
          panel: [1, 1, 1, 1, 1],
          group: [1, 2, 1, 2, 1],
          x: [1.0, 1.0, nil, nil, 2.0],
          y: [1.0, 2.0, 3.0, 4.0, 5.0]
        )

      dodged = Position.compute_layer(still(), frame, @continuous)
      dodged_pair = Position.compute_layer(still(), pair, @continuous)

      assert {DataFrame.pull(dodged, :x), DataFrame.pull(dodged, :y)} ===
               {[0.8125, 1.1875, nil, 1.8125, 2.1875], [1.0, 2.0, 3.0, nil, 5.0]}

      assert Enum.map([:x, :xmin], fn name -> DataFrame.pull(dodged_pair, name) end) ===
               [[0.8125, 1.1875, nil, nil, 2.0], [0.625, 1.0, nil, nil, 1.625]]
    end
  end

  # Jittering beside dodging within 0.75 with no jitter, so the marks are only dodged.
  defp still,
    do: %Position.Jitterdodge{jitter_width: 0.0, jitter_height: 0.0, dodge_width: 0.75, seed: 1}

  # `value` with its type hidden from the compiler, so a test can hand a function a value its
  # guards refuse.
  @spec untyped(term()) :: term()
  defp untyped(value), do: value

  # The first `count` numbers Erlang's `exsss` algorithm draws from `seed`, each from 0 to 1.
  defp draws(seed, count) do
    {numbers, _stream} =
      Enum.map_reduce(1..count, :rand.seed_s(:exsss, seed), fn _draw, stream ->
        :rand.uniform_s(stream)
      end)

    numbers
  end

  # A jitter's distance for the draw `draw` and the amount `amount`, as R's `runif()` scales it.
  defp distance(draw, amount), do: -amount + 2 * amount * draw

  # Two groups of areas at x 1 and 2, in the order the area geom sets them up in, each band from 0
  # to its y.
  # Bars at 1 and 2 of the groups 1 and 2, as a column layer hands them over, each `heights` high.
  defp bar_rows(heights), do: bar_rows([1.0, 1.0, 2.0, 2.0], [1, 2, 1, 2], heights)

  # Bars at `x` of `group`, each `y` high and 0.9 wide.
  defp bar_rows(x, group, y) do
    DataFrame.new(
      panel: Enum.map(x, fn _x -> 1 end),
      group: group,
      x: x,
      xmin: Enum.map(x, fn position -> position - 0.45 end),
      xmax: Enum.map(x, fn position -> position + 0.45 end),
      y: y,
      ymin: Enum.map(y, fn _y -> 0.0 end),
      ymax: y
    )
  end

  # `rows` moved by `position`, its y, ymin and ymax.
  defp stacked_columns(position, rows) do
    stacked = Position.compute_layer(position, rows, @continuous)
    Enum.map([:y, :ymin, :ymax], fn name -> DataFrame.pull(stacked, name) end)
  end

  defp area_rows(heights) do
    DataFrame.new(
      x: [1.0, 2.0, 1.0, 2.0],
      y: heights,
      panel: [1, 1, 1, 1],
      group: [1, 1, 2, 2],
      flipped_aes: [false, false, false, false],
      ymin: [0.0, 0.0, 0.0, 0.0],
      ymax: heights
    )
  end

  # `frame` dodged by clusters with R's defaults: `preserve = "total"`, `padding = 0.1`.
  defp dodged_by_clusters(frame) do
    Position.compute_layer(
      %Position.Dodge2{width: :none, preserve: :total, padding: 0.1, reverse: false},
      frame,
      @continuous
    )
  end
end
