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

    test "a free discrete axis gives each panel the levels of its own rows, placed from 1" do
      plot =
        %{"cyl" => ["6", "4", "8", "6"], "mpg" => [21.0, 22.8, 18.7, 19.2], "am" => [1, 1, 0, 0]}
        |> Plot.new(%{x: :cyl, y: :mpg})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:am, scales: :free_x)

      assert {Giggly.panel_scales(plot, 1).x, Giggly.panel_scales(plot, 2).x} ==
               {%Giggly.Scale.Discrete{levels: ["6", "8"]},
                %Giggly.Scale.Discrete{levels: ["4", "6"]}}

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
end
