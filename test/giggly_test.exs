defmodule GigglyTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Plot}

  doctest Giggly

  @rows %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "qsec" => [16.46, 17.02]}
  @mixed_rows %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]}

  describe "layer_data/2" do
    test "a layer's mapping takes an aesthetic the plot also maps" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(%{y: :qsec})

      frame = Giggly.layer_data(plot)
      assert DataFrame.pull(frame, :y) == [16.46, 17.02]
    end

    test "layers are counted in the order they were added" do
      plot =
        @rows
        |> Plot.new(%{x: :wt})
        |> Plot.geom_point(%{y: :mpg})
        |> Plot.geom_point(%{y: :qsec})

      frame = Giggly.layer_data(plot, 1)
      assert DataFrame.pull(frame, :y) == [16.46, 17.02]
    end

    test "a layer the plot does not have is refused rather than read as nothing" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot, 1) end
      assert error.message =~ "no layer 1"
    end

    test "a column no scale can place yet is refused, naming the layer, the column and its type" do
      rows = %{"day" => [~D[2026-10-12], ~D[2026-10-13]], "mpg" => [21.0, 22.8]}

      plot =
        rows
        |> Plot.new(%{x: :day, y: :mpg})
        |> Plot.geom_point()

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
      assert error.message =~ "index 0"
      assert error.message =~ ":x"
      assert error.message =~ ~s("day")
      assert error.message =~ ":date"
    end

    test "a layer whose axis column disagrees in kind with an earlier layer's is refused" do
      plot =
        @mixed_rows
        |> Plot.new(%{y: :mpg})
        |> Plot.geom_point(%{x: :wt})
        |> Plot.geom_point(%{x: :cyl})

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
      # The later layer is blamed, first and with its own column; the earlier one is named after
      # it as what it disagrees with.
      assert String.starts_with?(error.message, ~s(the layer at index 1 maps :x to "cyl"))
      assert error.message =~ ~s("wt")
    end

    test "a layer that remaps an axis is checked by its own column, not the plot's" do
      plot =
        @mixed_rows
        |> Plot.new(%{x: :cyl, y: :mpg})
        |> Plot.geom_point(%{x: :wt})
        |> Plot.geom_point(%{x: :mpg})

      assert %{x: %Giggly.Scale.Continuous{}} = Giggly.panel_scales(plot)
    end

    test "an aesthetic that is not a position is not checked against the scales" do
      rows = %{
        "day" => [~D[2026-10-12], ~D[2026-10-13]],
        "wt" => [2.62, 2.875],
        "mpg" => [21.0, 22.8]
      }

      plot =
        rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(%{group: :day})

      frame = Giggly.layer_data(plot)
      assert [1, 2] = DataFrame.pull(frame, :group)
    end

    test "a negative index is refused rather than counted from the end" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot, -1) end
      assert error.message =~ "no layer -1"
    end
  end

  # Golden throughout: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same plot, printed to 17
  # significant digits. It moves with ggplot2's bar geometry or stacking.
  describe "layer_data/2, for geom_col" do
    test "each bar runs from 0 to its y, 0.9 wide and centred on its level" do
      frame =
        %{"trt" => ["a", "b", "c"], "outcome" => [2.3, 1.9, 3.2]}
        |> Plot.new(%{x: :trt, y: :outcome})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert edges(frame) === %{
               xmin: [0.55000000000000004, 1.55000000000000004, 2.54999999999999982],
               xmax: [1.45, 2.4500000000000002, 3.4500000000000002],
               ymin: [0.0, 0.0, 0.0],
               ymax: [2.3, 1.9, 3.2],
               y: [2.3, 1.9, 3.2]
             }
    end

    test "on a continuous axis a bar is 0.9 of the closest pair's gap, not counting from zero" do
      frame =
        %{"x" => [0.5, 10.0], "y" => [1.0, 2.0]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :xmin), DataFrame.pull(frame, :xmax)} ===
               {[-3.7750000000000004, 5.7249999999999996],
                [4.7750000000000004, 14.2750000000000004]}
    end

    test "bars at one x stack upward in group order, the highest group at the bottom" do
      frame =
        %{"x" => ["a", "a", "a", "b"], "y" => [1.0, 2.0, 4.0, 3.0], "g" => ["p", "q", "r", "p"]}
        |> Plot.new(%{x: :x, y: :y, group: :g})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax),
              DataFrame.pull(frame, :y)} ===
               {[6.0, 4.0, 0.0, 0.0], [7.0, 6.0, 4.0, 3.0], [7.0, 6.0, 4.0, 3.0]}
    end

    test "a bar below zero stacks downward from zero, apart from those above it" do
      frame =
        %{"x" => ["a", "a", "b", "b"], "y" => [1.0, 2.0, 3.0, -1.0], "g" => ["p", "q", "p", "q"]}
        |> Plot.new(%{x: :x, y: :y, group: :g})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax),
              DataFrame.pull(frame, :y)} ===
               {[2.0, 0.0, 0.0, -1.0], [3.0, 2.0, 3.0, 0.0], [3.0, 2.0, 3.0, 0.0]}
    end

    test "with every x different nothing stacks, so a bar below zero keeps its y" do
      frame =
        %{"x" => ["a", "b"], "y" => [2.0, -1.0]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax),
              DataFrame.pull(frame, :y)} === {[0.0, -1.0], [2.0, 0.0], [2.0, -1.0]}
    end

    test "an x shared only across panels still turns stacking on, each panel stacked alone" do
      frame =
        %{"x" => ["a", "a", "b"], "y" => [2.0, -1.0, 3.0], "f" => ["u", "v", "v"]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_col()
        |> Plot.facet_wrap(:f)
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax),
              DataFrame.pull(frame, :y)} === {[0.0, -1.0, 0.0], [2.0, 0.0, 3.0], [2.0, 0.0, 3.0]}
    end

    test "a stacked row missing its y loses its x and edges and stacks as nothing" do
      frame =
        %{"x" => ["a", "a", "b"], "y" => [2.0, nil, 3.0], "g" => ["p", "q", "p"]}
        |> Plot.new(%{x: :x, y: :y, group: :g})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert edges(frame) === %{
               xmin: [0.55000000000000004, nil, 1.55000000000000004],
               xmax: [1.45, nil, 2.4500000000000002],
               ymin: [0.0, nil, 0.0],
               ymax: [2.0, nil, 3.0],
               y: [2.0, 0.0, 3.0]
             }

      assert DataFrame.pull(frame, :x) === [1, nil, 2]
    end
  end

  # Golden throughout: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same plot, on the same
  # `mpg` where it is used, printed to 17 significant digits. It moves with `stat_count()` or the
  # bar geometry.
  describe "layer_data/2, for geom_bar" do
    test "each bar counts its level's rows, its height the count" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      counts = [5.0, 47.0, 41.0, 11.0, 33.0, 35.0, 62.0]

      assert {DataFrame.pull(frame, :count), DataFrame.pull(frame, :y),
              DataFrame.pull(frame, :prop)} === {counts, counts, List.duplicate(1.0, 7)}

      assert {DataFrame.pull(frame, :xmin), DataFrame.pull(frame, :xmax)} ===
               {[
                  0.55000000000000004,
                  1.55000000000000004,
                  2.54999999999999982,
                  3.54999999999999982,
                  4.54999999999999982,
                  5.54999999999999982,
                  6.54999999999999982
                ],
                [
                  1.45,
                  2.4500000000000002,
                  3.4500000000000002,
                  4.4500000000000002,
                  5.4500000000000002,
                  6.4500000000000002,
                  7.4500000000000002
                ]}
    end

    test "an alpha set on the layer is in each counted bar's row, set after counting" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar(alpha: 0.5)
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :alpha) === List.duplicate(0.5, 7)
    end

    test "groups are counted apart, in group order, each proportion its group's, and stacked" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, group: :drv})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :x) === [2, 3, 5, 6, 7, 2, 3, 4, 6, 1, 6, 7]

      assert DataFrame.pull(frame, :count) ===
               [12.0, 3.0, 33.0, 4.0, 51.0, 35.0, 38.0, 11.0, 22.0, 5.0, 9.0, 11.0]

      assert DataFrame.pull(frame, :prop) === [
               0.116504854368932043,
               0.029126213592233011,
               0.320388349514563131,
               0.038834951456310676,
               0.495145631067961167,
               0.330188679245283001,
               0.358490566037735825,
               0.103773584905660382,
               0.207547169811320764,
               0.200000000000000011,
               0.359999999999999987,
               0.440000000000000002
             ]

      assert {DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax)} ===
               {[35.0, 38.0, 0.0, 31.0, 11.0, 0.0, 0.0, 0.0, 9.0, 0.0, 0.0, 0.0],
                [47.0, 41.0, 33.0, 35.0, 62.0, 35.0, 38.0, 11.0, 31.0, 5.0, 9.0, 11.0]}
    end

    test "a weight sums its rows' weights instead of counting them" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar(%{weight: :displ})
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :y) === [
               30.800000000000001,
               109.299999999999983,
               119.799999999999983,
               37.300000000000004,
               145.800000000000040,
               93.100000000000023,
               276.299999999999898
             ]
    end

    test "on a continuous axis a bar is 0.9 of the closest gap, counting from zero" do
      x = List.duplicate(2.9, 5) ++ List.duplicate(3.1, 10) ++ List.duplicate(4.5, 4)

      frame =
        %{"x" => x}
        |> Plot.new(%{x: :x})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :count), DataFrame.pull(frame, :xmin),
              DataFrame.pull(frame, :xmax)} ===
               {[5.0, 10.0, 4.0], [2.8099999999999996, 3.0099999999999998, 4.4100000000000001],
                [2.9900000000000002, 3.1900000000000004, 4.5899999999999999]}
    end

    test "an integer column's bars are 0.9 wide, a float column's its closest gap's 0.9" do
      integers =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :cyl})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      floats =
        %{"x" => [4.0, 6.0, 8.0, 8.0]}
        |> Plot.new(%{x: :x})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert {DataFrame.pull(integers, :xmin), DataFrame.pull(floats, :xmin)} ===
               {[3.5499999999999998, 4.5499999999999998, 5.5499999999999998, 7.5499999999999998],
                [3.1000000000000001, 5.0999999999999996, 7.0999999999999996]}
    end

    test "a row missing its x is not counted, and a missing weight adds nothing" do
      missing_x =
        %{"x" => [1.0, nil, 1.0, 2.0]}
        |> Plot.new(%{x: :x})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      missing_weight =
        %{"x" => [1.0, 1.0, 2.0], "w" => [1.0, nil, 2.0]}
        |> Plot.new(%{x: :x, weight: :w})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert {DataFrame.pull(missing_x, :count), DataFrame.pull(missing_x, :prop)} ===
               {[2.0, 1.0], [0.66666666666666663, 0.33333333333333331]}

      assert DataFrame.pull(missing_weight, :count) === [1.0, 2.0]
    end

    test "a column constant within every group is carried, one that varies is dropped" do
      constant =
        %{"x" => ["a", "a", "b"], "w" => [2.0, 2.0, 2.0]}
        |> Plot.new(%{x: :x, weight: :w})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      varying =
        %{"x" => [1.0, 1.0, 2.0], "w" => [1.0, 3.0, 2.0]}
        |> Plot.new(%{x: :x, weight: :w})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert DataFrame.pull(constant, :weight) === [2.0, 2.0]
      assert :weight not in DataFrame.names(varying)
    end

    test "a group whose counts are all zero has no proportions" do
      frame =
        %{"x" => [1.0, 1.0, 2.0], "w" => [0.0, 0.0, 0.0]}
        |> Plot.new(%{x: :x, weight: :w})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :count), DataFrame.pull(frame, :prop)} ===
               {[0.0, 0.0], [:nan, :nan]}
    end
  end

  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1, `geom_bar(position = "dodge")` on the same
  # `mpg`, printed to 17 significant digits. It moves with `position_dodge()`.
  describe "layer_data/2, dodged" do
    test "the groups at one x share a bar's width, lowest group leftmost; a lone group keeps it" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, group: :drv})
        |> Plot.geom_bar(position: :dodge)
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :x) === [
               1.7749999999999999,
               2.7749999999999999,
               5.0,
               5.7000000000000002,
               6.7750000000000004,
               2.2250000000000001,
               3.2250000000000001,
               4.0,
               6.0,
               1.0,
               6.2999999999999998,
               7.2249999999999996
             ]

      assert DataFrame.pull(frame, :xmin) === [
               1.54999999999999982,
               2.54999999999999982,
               4.54999999999999982,
               5.54999999999999982,
               6.55000000000000071,
               2.0,
               3.0,
               3.54999999999999982,
               5.84999999999999964,
               0.55000000000000004,
               6.14999999999999947,
               7.0
             ]

      assert DataFrame.pull(frame, :xmax) === [
               2.0,
               3.0,
               5.4500000000000002,
               5.8500000000000005,
               7.0,
               2.4500000000000002,
               3.4500000000000002,
               4.4500000000000002,
               6.1500000000000004,
               1.45,
               6.4500000000000002,
               7.4499999999999993
             ]
    end
  end

  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same plot, on the same `mpg` where it
  # is used, printed to 17 significant digits. It moves with ggplot2's bar orientation.
  describe "layer_data/2, horizontal bars" do
    test "counting along y draws each bar from 0 rightward to its count" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new()
        |> Plot.geom_bar(%{y: :class})
        |> Giggly.layer_data()

      counts = [5.0, 47.0, 41.0, 11.0, 33.0, 35.0, 62.0]

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :xmin),
              DataFrame.pull(frame, :xmax)} === {counts, List.duplicate(0.0, 7), counts}

      assert {DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :flipped_aes)} ===
               {[
                  0.55000000000000004,
                  1.55000000000000004,
                  2.54999999999999982,
                  3.54999999999999982,
                  4.54999999999999982,
                  5.54999999999999982,
                  6.54999999999999982
                ], List.duplicate(true, 7)}
    end

    test "columns are horizontal when y alone is discrete, vertical when both are" do
      horizontal =
        %{"trt" => ["a", "b", "c"], "outcome" => [2.3, 1.9, 3.2]}
        |> Plot.new(%{x: :outcome, y: :trt})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      both_discrete =
        %{"x" => ["a", "b"], "y" => ["p", "q"]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(horizontal, :xmax), DataFrame.pull(horizontal, :ymax)} ===
               {[2.3, 1.9, 3.2], [1.45, 2.4500000000000002, 3.4500000000000002]}

      assert {DataFrame.pull(both_discrete, :ymin), DataFrame.pull(both_discrete, :ymax),
              DataFrame.pull(both_discrete, :flipped_aes)} ===
               {[0.0, 0.0], [1.0, 2.0], [false, false]}
    end

    test "horizontal bars stack rightward, below zero leftward, apart" do
      counted =
        %{"y" => ["a", "a", "a", "b"], "g" => ["p", "q", "q", "p"]}
        |> Plot.new(%{y: :y, group: :g})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      negative =
        %{"v" => [1.0, 2.0, -1.0], "k" => ["a", "a", "b"], "g" => ["p", "q", "p"]}
        |> Plot.new(%{x: :v, y: :k, group: :g})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(counted, :xmin), DataFrame.pull(counted, :xmax)} ===
               {[2.0, 0.0, 0.0], [3.0, 1.0, 2.0]}

      assert {DataFrame.pull(negative, :xmin), DataFrame.pull(negative, :xmax),
              DataFrame.pull(negative, :x)} ===
               {[2.0, 0.0, -1.0], [3.0, 2.0, 0.0], [3.0, 2.0, 0.0]}
    end

    test "horizontal bars dodge along y" do
      frame =
        %{"y" => ["a", "a", "a", "b"], "g" => ["p", "q", "q", "p"]}
        |> Plot.new(%{y: :y, group: :g})
        |> Plot.geom_bar(position: :dodge)
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :y), DataFrame.pull(frame, :ymin),
              DataFrame.pull(frame, :ymax)} ===
               {[0.77500000000000002, 2.0, 1.22500000000000009],
                [0.55000000000000004, 1.55000000000000004, 1.0],
                [1.0, 2.4500000000000002, 1.4500000000000002]}
    end
  end

  describe "the guides' titles" do
    test "an axis no layer maps is titled by the column a stat puts into it" do
      assembly =
        %{"class" => ["suv", "compact"]}
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar()
        |> Giggly.Assembly.run()

      assert assembly.guide_titles === %{x: "class", y: "count"}
    end

    test "counting along y titles x by the count" do
      assembly =
        %{"class" => ["suv", "compact"]}
        |> Plot.new()
        |> Plot.geom_bar(%{y: :class})
        |> Giggly.Assembly.run()

      assert assembly.guide_titles === %{x: "count", y: "class"}
    end

    test "a later layer's own mapping titles the axis over an earlier stat's column" do
      assembly =
        %{"x" => ["a", "b"], "y" => [5.0, 7.0]}
        |> Plot.new(%{x: :x})
        |> Plot.geom_bar()
        |> Plot.geom_col(%{y: :y})
        |> Giggly.Assembly.run()

      assert assembly.guide_titles === %{x: "x", y: "y"}
    end
  end

  describe "panel_scales/2" do
    test "the scales are trained again on the marks, so a discrete axis holds its bars' edges" do
      scales =
        %{"trt" => ["a", "b", "c"], "outcome" => [2.3, 1.9, 3.2]}
        |> Plot.new(%{x: :trt, y: :outcome})
        |> Plot.geom_col()
        |> Giggly.panel_scales()

      assert scales === %{
               x: %Giggly.Scale.Discrete{
                 levels: ["a", "b", "c"],
                 continuous_range: {0.55000000000000004, 3.4500000000000002}
               },
               y: %Giggly.Scale.Continuous{range: {0.0, 3.2}, transform: :identity}
             }
    end

    # Golden: ggplot2 4.0.3's x scale range in R 4.6.1 for the same plot.
    test "a scale is reset before it is trained again, so a mark that lost its x is not covered" do
      scales =
        %{"x" => [1.0, 1.0, 5.0], "y" => [1.0, 2.0, nil]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_col()
        |> Giggly.panel_scales()

      assert scales.x.range === {-0.80000000000000004, 2.7999999999999998}
    end

    test "an axis's scale is trained on every layer's column on that axis" do
      plot =
        @rows
        |> Plot.new(%{y: :mpg})
        |> Plot.geom_point(%{x: :wt})
        |> Plot.geom_point(%{x: :qsec})

      assert %{x: %Giggly.Scale.Continuous{range: {2.62, 17.02}}} = Giggly.panel_scales(plot)
    end

    test "a panel the plot does not have is refused rather than read as nothing" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      error = assert_raise ArgumentError, fn -> Giggly.panel_scales(plot, 2) end
      assert error.message =~ "no panel 2"
      assert error.message =~ "panel(s) 1"
    end

    test "a free discrete axis gives each panel the levels of its own rows, placed from 1" do
      plot =
        %{"cyl" => ["6", "4", "8", "6"], "mpg" => [21.0, 22.8, 18.7, 19.2], "am" => [1, 1, 0, 0]}
        |> Plot.new(%{x: :cyl, y: :mpg})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:am, scales: :free_x)

      assert {Giggly.panel_scales(plot, 1).x, Giggly.panel_scales(plot, 2).x} ==
               {%Giggly.Scale.Discrete{levels: ["6", "8"], continuous_range: {1, 2}},
                %Giggly.Scale.Discrete{levels: ["4", "6"], continuous_range: {1, 2}}}

      # Each row on its own panel's scale, in row order: "8" is the second level of panel 1's.
      frame = Giggly.layer_data(plot)
      assert DataFrame.pull(frame, :x) == [2, 1, 2, 1]
    end

    test "a fixed axis shares one scale across the panels, a free one beside it does not" do
      plot =
        %{"wt" => [1.0, 2.0, 3.0, 9.0], "mpg" => [10.0, 20.0, 30.0, 40.0], "am" => [0, 0, 1, 1]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:am, scales: :free_y)

      assert {Giggly.panel_scales(plot, 1), Giggly.panel_scales(plot, 2)} ==
               {%{
                  x: %Giggly.Scale.Continuous{range: {1.0, 9.0}, transform: :identity},
                  y: %Giggly.Scale.Continuous{range: {10.0, 20.0}, transform: :identity}
                },
                %{
                  x: %Giggly.Scale.Continuous{range: {1.0, 9.0}, transform: :identity},
                  y: %Giggly.Scale.Continuous{range: {30.0, 40.0}, transform: :identity}
                }}
    end

    test "an axis's scale is of the kind its columns need, on the y axis as on the x" do
      plot =
        @mixed_rows
        |> Plot.new(%{x: :wt, y: :cyl})
        |> Plot.geom_point()

      assert %{x: %Giggly.Scale.Continuous{}, y: %Giggly.Scale.Discrete{levels: ["4", "6"]}} =
               Giggly.panel_scales(plot)
    end

    test "an axis no layer maps gets an untrained continuous scale" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert %{x: %Giggly.Scale.Continuous{range: :none}} = Giggly.panel_scales(plot)
    end
  end

  describe "to_svg/2" do
    # Golden: test/golden/point.svg. The data spans x 0 to 10 and y 0 to 50 in columns wt and mpg,
    # as ggplot2's own snapshot `tests/testthat/_snaps/coord-cartesian/expand-range.svg` does, and
    # the drawing is checked against ggplot2's drawing of the same plot, made by
    # test/golden/point.R, element by element: the plot's and the panel's backgrounds, every grid
    # line, point, tick, label and title match it in position, size, colour and textLength, and
    # the panel's clip path and its group are svglite's for the same panel, id included. It is
    # drawn at vdiffr's size, 960 by 768 pixels (10 by 8 inches), so it can be set beside ggplot2's
    # own snapshots. The
    # row missing its mpg is not drawn but still widens the x axis, as in ggplot2. It moves only
    # with a change to what a plot draws: the drawing's size, the theme, the look of the points,
    # the expansion, the breaks, a plot title arriving, or the markup.
    test "each row with an x and a y is drawn as a point, with titled axes below and to the left" do
      plot =
        %{"wt" => [0.0, 4.0, 7.0, 10.0], "mpg" => [0.0, 50.0, 20.0, nil]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/point.svg")
    end

    # Golden: test/golden/col.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/col.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. geom_col()'s example from ggplot2's reference page:
    # three bars 0.9 wide on a discrete axis, from 0, which the y axis reaches once its scale is
    # trained again on the bars' edges; the discrete axis has major grid lines at its levels and no
    # minor ones. It moves with what moves test/golden/point.svg, and with the bars' geometry or
    # look.
    test "columns draw a bar from 0 to each y, 0.9 wide on a discrete axis" do
      plot =
        %{"trt" => ["a", "b", "c"], "outcome" => [2.3, 1.9, 3.2]}
        |> Plot.new(%{x: :trt, y: :outcome})
        |> Plot.geom_col()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/col.svg")
    end

    # Golden: test/golden/alpha.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/alpha.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. geom_col()'s example with alpha set on two layers:
    # the columns' fill half opaque and their border, which they do not draw, untouched; the points
    # a third opaque, outline and fill, written as R holds a colour's alpha, 85 of 255. It moves
    # with what moves test/golden/col.svg, and with how an opacity is drawn or written.
    test "an alpha set on a layer makes a column's fill and a point's outline and fill transparent" do
      plot =
        %{"trt" => ["a", "b", "c"], "outcome" => [2.3, 1.9, 3.2]}
        |> Plot.new(%{x: :trt, y: :outcome})
        |> Plot.geom_col(alpha: 0.5)
        |> Plot.geom_point(alpha: 1 / 3)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/alpha.svg")
    end

    # Golden: test/golden/bar.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/bar.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. geom_bar()'s first example from ggplot2's
    # reference page: the number of cars in each of mpg's classes, the y axis titled by the count
    # counting puts into it. It moves with what moves test/golden/col.svg, and with counting.
    test "counted bars rise to the number of rows at each level, the y axis titled count" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/bar.svg")
    end

    # Golden: test/golden/dodge.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/dodge.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. mpg's classes counted by drive train and dodged:
    # the groups at each class share one bar's width side by side, a class with one group keeping
    # all of it. It moves with what moves test/golden/bar.svg, and with dodging.
    test "dodged bars stand side by side within the width one bar takes" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, group: :drv})
        |> Plot.geom_bar(position: :dodge)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/dodge.svg")
    end

    # Golden: test/golden/horizontal_bar.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/horizontal_bar.R: every element matches it, the x axis drawn before the y
    # as in test/golden/point.svg, and every clip path. geom_bar()'s third example from ggplot2's
    # reference page: mpg's classes counted along y, the bars running rightward from 0 and the x
    # axis titled count. It moves with what moves test/golden/bar.svg, and with bar orientation.
    test "bars counted along y run rightward, the x axis titled count" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new()
        |> Plot.geom_bar(%{y: :class})

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/horizontal_bar.svg")
    end

    # Golden: test/golden/radial.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/radial.R: every element matches it, in order, and every clip path. The point
    # golden's data in radial coordinates: the panel is square and the table centred across the
    # drawing, the background a disc and the grid circles and spokes, munched as ggplot2 munches
    # them; the angle axis is drawn round the circle over the points, each label justified by its
    # angle, and the radius axis to the panel's left, its labels centred, up the panel's upper
    # half. It moves with what moves test/golden/point.svg, and with radial placing, munching, or
    # either radial axis's look.
    test "radial coordinates draw a square panel, its grid on a disc and its axes round and up it" do
      plot =
        %{"wt" => [0.0, 4.0, 7.0, 10.0], "mpg" => [0.0, 50.0, 20.0, nil]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.coord_radial()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/radial.svg")
    end

    # Golden: test/golden/facet_wrap.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/facet_wrap.R: every element, in order, and every clip path match it. Five
    # combinations of cyl and drv make five panels in two rows of three, the last row one short, so
    # the panel above the empty cell draws an x axis that hangs into it while its row takes no room
    # for it, and each panel has a strip for each column; the panels share the drawing equally,
    # the theme's spacing between them, and the titles are centred on them. It moves with what
    # moves test/golden/point.svg, and with the strips' look, the panel spacing, the layout of the
    # panels, or the order cells are drawn in.
    test "a wrapped facet draws a panel for each combination, with strips and axes at the margins" do
      plot =
        %{
          "wt" => [0.0, 4.0, 7.0, 10.0, 2.0, 5.0, 8.0, 3.0, 6.0],
          "mpg" => [0.0, 50.0, 20.0, 35.0, 10.0, 40.0, 25.0, 15.0, 30.0],
          "cyl" => [4, 4, 4, 6, 6, 6, 8, 8, 8],
          "drv" => ["f", "r", "r", "4", "4", "f", "f", "f", "f"]
        }
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.facet_wrap([:cyl, :drv])

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/facet_wrap.svg")
    end

    # Golden: test/golden/facet_wrap_radial.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/facet_wrap_radial.R: every element matches it, in order, and every strip's
    # clip path. test/golden/facet_wrap.svg's plot in radial coordinates: the five panels stay
    # square, the width running out first, so the table is centred down the drawing; each panel
    # draws its angle axis, the left column its radius axes, and no panel draws a bottom axis. It
    # moves with what moves test/golden/facet_wrap.svg and test/golden/radial.svg.
    test "faceted radial panels keep their shape together, the table centred in the drawing" do
      plot =
        %{
          "wt" => [0.0, 4.0, 7.0, 10.0, 2.0, 5.0, 8.0, 3.0, 6.0],
          "mpg" => [0.0, 50.0, 20.0, 35.0, 10.0, 40.0, 25.0, 15.0, 30.0],
          "cyl" => [4, 4, 4, 6, 6, 6, 8, 8, 8],
          "drv" => ["f", "r", "r", "4", "4", "f", "f", "f", "f"]
        }
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.facet_wrap([:cyl, :drv])
        |> Plot.coord_radial()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/facet_wrap_radial.svg")
    end

    # Golden: test/golden/facet_wrap_free.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/facet_wrap_free.R: every element, in order, and every clip path match it.
    # Each of five panels is on its own x and y scale, so each draws both axes; the first row's x
    # axes take room but for the one over the empty cell, and the left axes of panels b and e share
    # a column as wide as e's, b's sitting against its panel. It moves with what moves
    # test/golden/facet_wrap.svg, and with how free scales are trained or their axes placed.
    test "free scales give each panel its own scales, and each panel its own axes" do
      plot =
        %{
          "x" => [0.0, 10.0, 0.0, 1.0, 100.0, 200.0, 0.0, 4.0, 2.0, 3.0],
          "y" => [0.0, 50.0, 0.0, 5.0, 0.0, 500.0, 10.0, 20.0, 0.0, 1000.0],
          "g" => ["a", "a", "b", "b", "c", "c", "d", "d", "e", "e"]
        }
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:g, scales: :free)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/facet_wrap_free.svg")
    end

    test "a label's &, < and > are escaped, so a level cannot break the document" do
      svg =
        %{"make" => ["<a & b>"], "mpg" => [21.0]}
        |> Plot.new(%{x: :make, y: :mpg})
        |> Plot.geom_point()
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()

      assert svg =~ ">&lt;a &amp; b&gt;</text>"
    end

    test "an axis is titled by the first layer to map it, through that layer's own mapping" do
      svg =
        %{"wt" => [2.62], "hp" => [110], "mpg" => [21.0]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(%{x: :hp})
        |> Plot.geom_point()
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()

      assert svg =~ ">hp</text>"
    end

    # Drawn at the default size, 700 by 433 pixels, which the document gives in points.
    test "a plot with no layers maps no axis, so it draws its backgrounds but no axes or titles" do
      svg =
        %{"wt" => [2.62], "mpg" => [21.0]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()

      assert svg ==
               "<svg xmlns='http://www.w3.org/2000/svg' width='525.00pt' height='324.75pt' " <>
                 "viewBox='0 0 525.00 324.75'>\n" <>
                 "<defs>\n  <clipPath id='cpMC4wMHw1MjUuMDB8MC4wMHwzMjQuNzU='>\n" <>
                 "    <rect x='0.00' y='0.00' width='525.00' height='324.75' />\n" <>
                 "  </clipPath>\n</defs>\n" <>
                 "<g clip-path='url(#cpMC4wMHw1MjUuMDB8MC4wMHwzMjQuNzU=)'>\n" <>
                 "<rect x='0.00' y='0.00' width='525.00' height='324.75' " <>
                 "style='stroke-width: 1.07; stroke: #FFFFFF; fill: #FFFFFF;' />\n</g>\n" <>
                 "<defs>\n  <clipPath id='cpNS40OHw1MTkuNTJ8NS40OHwzMTkuMjc='>\n" <>
                 "    <rect x='5.48' y='5.48' width='514.04' height='313.79' />\n" <>
                 "  </clipPath>\n</defs>\n" <>
                 "<g clip-path='url(#cpNS40OHw1MTkuNTJ8NS40OHwzMTkuMjc=)'>\n" <>
                 "<rect x='5.48' y='5.48' width='514.04' height='313.79' " <>
                 "style='stroke-width: 1.07; stroke: none; fill: #EBEBEB;' />\n</g>\n</svg>\n"
    end

    test "an option it does not take is refused at the call, naming the option" do
      plot =
        %{"wt" => [2.62], "mpg" => [21.0]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      error =
        assert_raise NimbleOptions.ValidationError, fn -> Giggly.to_svg(plot, widht: 700) end

      assert error.key == [:widht]
    end
  end

  defp edges(frame) do
    Map.new([:xmin, :xmax, :ymin, :ymax, :y], fn name -> {name, DataFrame.pull(frame, name)} end)
  end
end
