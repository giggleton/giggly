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
      assert error.message =~ ~s("cyl")
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

  describe "panel_scales/2" do
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

    test "an axis no layer maps gets an untrained continuous scale" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert %{x: %Giggly.Scale.Continuous{range: :none}} = Giggly.panel_scales(plot)
    end
  end

  describe "to_svg/1" do
    # Golden: test/golden/point.svg. The data spans x 0 to 10 and y 0 to 50, the axes of ggplot2's
    # own snapshot `tests/testthat/_snaps/coord-cartesian/expand-range.svg`, and every tick and
    # label was checked against that snapshot measured from the panel's edges: y ticks from 2.74
    # points left of the panel to its edge, y labels ending 4.93 points left of it with baselines
    # 3.03 points below their ticks, x ticks 2.74 points below it and x baselines 10.99, the same
    # break labels and the same `textLength`s. The panel is the drawing less ggplot2's 5.48-point
    # plot margin and the two axes (14.72 points wide, 12.81 tall); the points' radius and outline
    # are ggplot2's default point. The row missing its mpg is not drawn but still widens the x axis,
    # as in ggplot2. It moves only with a change to what a plot draws: the drawing's size, the
    # point's or the axes' look, the expansion, a background or titles arriving, or the markup.
    test "each row with an x and a y is drawn as a point, with an axis below and to the left" do
      plot =
        %{"wt" => [0.0, 4.0, 7.0, 10.0], "mpg" => [0.0, 50.0, 20.0, nil]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      svg =
        plot
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/point.svg")
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
  end
end
