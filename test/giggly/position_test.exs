defmodule Giggly.PositionTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Position}

  # Both axes continuous, as every test here but the discrete one's draws.
  @continuous %{x: :continuous, y: :continuous}

  describe "compute_layer/3 for nudging" do
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

      nudged = Position.compute_layer(%Position.Nudge{}, frame, @continuous)

      assert Enum.map([:xmin, :xmax, :ymin, :ymax], fn name -> DataFrame.pull(nudged, name) end) ===
               [[2.0, 3.0], [2.5, 4.0], [-0.5, 0.5], [0.5, 1.5]]
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

      dodged = Position.compute_layer(%Position.Dodge{width: 0.9}, frame, @continuous)

      assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(dodged, name) end) === [
               [0.775, 1.225, 1.775, 2.225],
               [0.55, 1.0, 1.5499999999999998, 2.0],
               [1.0, 1.4500000000000002, 2.0, 2.45]
             ]

      unmoved = Position.compute_layer(%Position.Dodge{width: :none}, frame, @continuous)

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

      dodged = Position.compute_layer(%Position.Dodge{width: 0.9}, frame, @continuous)

      assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(dodged, name) end) === [
               [0.775, 1.225],
               [0.7125, 1.1625],
               [0.8375, 1.2875000000000001]
             ]

      own = Position.compute_layer(%Position.Dodge{width: :none}, frame, @continuous)
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

      dodged = Position.compute_layer(%Position.Dodge{width: 0.9}, frame, @continuous)

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
            {%Position.Dodge{width: :none}, [0.6000000000000001, 1.0, 1.6000000000000001],
             [1.0, 1.4, 2.4]},
            {%Position.Dodge2{preserve: :total, padding: 0.1, reverse: false},
             [0.6200000000000001, 1.02, 1.6400000000000001], [0.98, 1.38, 2.36]}
          ] do
        dodged = Position.compute_layer(position, frame, @continuous)

        assert Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(dodged, name) end) ===
                 [[0.8, 1.2, 2.0], xmin, xmax]
      end
    end
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

    test "reversed, the lowest group is at the bottom of the pile" do
      assert stacked_columns(%Position.Stack{reverse: true}, bar_rows([1.0, 3.0, 2.0, 2.0])) ===
               [[1.0, 4.0, 2.0, 4.0], [0.0, 1.0, 0.0, 2.0], [1.0, 4.0, 2.0, 4.0]]
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
      %Position.Dodge2{preserve: :total, padding: 0.1, reverse: false},
      frame,
      @continuous
    )
  end
end
