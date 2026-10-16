defmodule Giggly.PlotTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, Facet, Geom, Plot, Position, Stat}

  doctest Giggly.Plot

  @rows %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]}

  describe "new/2" do
    test "a plot records the null facet, cartesian coordinates and the gray theme by default" do
      plot = Plot.new(@rows)

      assert {plot.facet, plot.coord, plot.theme} ==
               {%Facet.Null{}, %Coord.Cartesian{clip: :on}, :gray}
    end

    test "a missing column's refusal names the call, the aesthetic, the column as written and the columns" do
      error = assert_raise ArgumentError, fn -> Plot.new(@rows, %{x: :wt, y: :mgp}) end

      assert error.message =~ "Plot.new/2"
      assert error.message =~ ":y"
      assert error.message =~ ":mgp"
      assert error.message =~ ~s("mpg")
    end

    test "a value that is not a column reference is refused rather than read as a column's name" do
      rows = %{"2.5" => [2.62, 2.875], "mpg" => [21.0, 22.8]}

      error = assert_raise ArgumentError, fn -> Plot.new(rows, %{x: 2.5, y: :mpg}) end
      assert error.message =~ ":x"
      assert error.message =~ "2.5"
    end
  end

  describe "geom_point/3" do
    test "a point layer records its geom, the identity stat and position, and its resolved mapping" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.geom_point(%{x: :wt, y: :mpg, group: :cyl})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Point{},
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 mapping: %{x: "wt", y: "mpg", group: "cyl"},
                 fixed: %{}
               }
             ]
    end

    test "a column the data does not have is refused by the layer that maps it" do
      plot = Plot.new(@rows, %{x: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot, %{y: :mgp}) end
      assert error.message =~ "Plot.geom_point/3"
    end

    test "an aesthetic points cannot use is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot, %{color: :cyl}) end
      assert error.message =~ "Plot.geom_point/3"
      assert error.message =~ ":color"
      assert error.message =~ ":group"
    end

    test "an aesthetic points cannot use is refused when the plot's mapping gives it" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, color: :cyl})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot) end
      assert error.message =~ ":color"
    end

    test "x or y mapped by neither the layer nor the plot is refused" do
      plot = Plot.new(@rows, %{x: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot) end
      assert error.message =~ ":y"
    end

    test "a mapped alpha is accepted, since a scale now maps it" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(%{alpha: :mpg})

      assert [%Plot.Layer{mapping: %{alpha: "mpg"}}] = plot.reversed_layers
    end

    test "an alpha the layer sets leaves the plot's mapping of it out of what the layer draws" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, alpha: :cyl})
      plot = Plot.geom_point(plot, alpha: 0.3)
      [layer] = plot.reversed_layers

      assert Plot.computed_mapping(plot, layer) === %{x: "wt", y: "mpg"}
    end

    test "an alpha set alone is recorded for every mark, a whole number as a float" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(alpha: 1)

      assert [%Plot.Layer{fixed: fixed, mapping: %{}}] = plot.reversed_layers
      assert fixed === %{alpha: 1.0}
    end

    test "a mapping and an alpha together record both" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.geom_point(%{x: :wt, y: :mpg}, alpha: 0.4)

      assert [%Plot.Layer{fixed: %{alpha: 0.4}, mapping: %{x: "wt", y: "mpg"}}] =
               plot.reversed_layers
    end

    test "an alpha of 0, invisible, is a value like any other from 0 to 1" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(alpha: 0)

      assert [%Plot.Layer{fixed: %{alpha: +0.0}}] = plot.reversed_layers
    end

    test "an alpha outside 0 to 1, or not a number, is refused by the option's validation" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for alpha <- [1.5, -0.1, "0.4"] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_point(plot, alpha: alpha)
          end

        assert error.key == :alpha
      end
    end

    test "an alpha given twice is refused rather than one silently winning" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error =
        assert_raise ArgumentError, fn -> Plot.geom_point(plot, alpha: 0.4, alpha: "x") end

      assert error.message =~ ":alpha"
    end

    test "a colour is recorded for every mark in its one spelling, written colour: or color:" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for {options, color} <- [
            {[colour: "SteelBlue"], "#4682B4"},
            {[color: "#4682b480"], "#4682B480"}
          ] do
        assert [%Plot.Layer{fixed: %{color: ^color}}] =
                 Plot.geom_point(plot, options).reversed_layers
      end
    end

    test "a colour the layer sets leaves the plot's mapping of colour out of what the layer draws" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, colour: :cyl})
      plot = Plot.geom_point(plot, colour: "red")
      [layer] = plot.reversed_layers

      assert Plot.computed_mapping(plot, layer) === %{x: "wt", y: "mpg"}
    end

    test "a colour CSS does not define is refused by the option's validation, naming the value" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.geom_point(plot, colour: "grey50")
        end

      assert error.key == :color
      assert error.message =~ ~s("grey50")
    end

    test "a colour given as both colour: and color: is refused rather than one silently winning" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error =
        assert_raise ArgumentError, fn -> Plot.geom_point(plot, colour: "red", color: "blue") end

      assert error.message =~ ":color"
    end

    test "points take no fill, which only the filled shapes not yet drawn use" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error =
        assert_raise NimbleOptions.ValidationError, fn -> Plot.geom_point(plot, fill: "red") end

      assert error.message =~ "fill"
    end
  end

  describe "geom_col/3" do
    test "a column layer records the bar geom, the identity stat and stacking" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.geom_col(%{x: :cyl, y: :mpg})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Bar{},
                 stat: %Stat.Identity{},
                 position: %Position.Stack{},
                 mapping: %{x: "cyl", y: "mpg"},
                 fixed: %{}
               }
             ]
    end

    test "a column the data does not have is refused, naming the call" do
      plot = Plot.new(@rows, %{x: :cyl})

      error = assert_raise ArgumentError, fn -> Plot.geom_col(plot, %{y: :mgp}) end
      assert error.message =~ "Plot.geom_col/3"
    end

    test "a mapping and options together record both" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.geom_col(%{x: :cyl, y: :mpg}, position: :dodge, alpha: 0.5)

      assert [
               %Plot.Layer{
                 position: %Position.Dodge{},
                 mapping: %{x: "cyl", y: "mpg"},
                 fixed: %{alpha: 0.5}
               }
             ] = plot.reversed_layers
    end

    test "an aesthetic bars cannot use is refused, naming the call" do
      plot = Plot.new(@rows, %{x: :cyl, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_col(plot, %{color: :wt}) end
      assert error.message =~ "Plot.geom_col/3"
      assert error.message =~ ":color"
    end

    test "y mapped by neither the layer nor the plot is refused, naming the call" do
      plot = Plot.new(@rows, %{x: :cyl})

      error = assert_raise ArgumentError, fn -> Plot.geom_col(plot) end
      assert error.message =~ "Plot.geom_col/3"
      assert error.message =~ ":y"
    end
  end

  describe "geom_bar/3" do
    test "a bar layer records the bar geom, counting and stacking" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.geom_bar(%{x: :cyl, weight: :wt})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Bar{},
                 stat: %Stat.Count{},
                 position: %Position.Stack{},
                 mapping: %{x: "cyl", weight: "wt"},
                 fixed: %{}
               }
             ]
    end

    test "options alone choose the position, and dodging records the dodge" do
      plot =
        @rows
        |> Plot.new(%{x: :cyl})
        |> Plot.geom_bar(position: :dodge)

      assert [%Plot.Layer{position: %Position.Dodge{}, mapping: %{}, fixed: %{}}] =
               plot.reversed_layers
    end

    test "counted bars accept a mapped alpha, which the bar geom draws though counting ignores it" do
      plot =
        @rows
        |> Plot.new(%{x: :cyl})
        |> Plot.geom_bar(%{alpha: :cyl})

      assert [%Plot.Layer{mapping: %{alpha: "cyl"}}] = plot.reversed_layers
    end

    test "an alpha is recorded for every bar, the position left stacking" do
      plot =
        @rows
        |> Plot.new(%{x: :cyl})
        |> Plot.geom_bar(alpha: 0.5)

      assert [%Plot.Layer{position: %Position.Stack{}, fixed: %{alpha: 0.5}}] =
               plot.reversed_layers
    end

    test "a fill and a border colour are recorded for every bar, counted or not" do
      plot = Plot.new(@rows, %{x: :cyl})

      for {add, options, fixed} <- [
            {&Plot.geom_bar/2, [fill: "white", colour: "red"],
             %{fill: "#FFFFFF", color: "#FF0000"}},
            {fn plot, options -> Plot.geom_col(plot, %{y: :mpg}, options) end, [fill: "#7f7f7f"],
             %{fill: "#7F7F7F"}}
          ] do
        assert [%Plot.Layer{fixed: ^fixed}] = add.(plot, options).reversed_layers
      end
    end

    test "a fill CSS does not define is refused by the option's validation" do
      plot = Plot.new(@rows, %{x: :cyl})

      error =
        assert_raise NimbleOptions.ValidationError, fn -> Plot.geom_bar(plot, fill: "grey50") end

      assert error.key == :fill
    end

    test "a position bars do not take is refused by the option's validation" do
      plot = Plot.new(@rows, %{x: :cyl})

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.geom_bar(plot, position: :jitter)
        end

      assert error.key == :position
    end

    test "an option given twice is refused rather than one silently winning" do
      plot = Plot.new(@rows, %{x: :cyl})

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_bar(plot, %{}, position: :dodge, position: :stack)
        end

      assert error.message =~ ":position"
    end

    test "a column the data does not have is refused, naming the call" do
      plot = Plot.new(@rows)

      error = assert_raise ArgumentError, fn -> Plot.geom_bar(plot, %{x: :cly}) end
      assert error.message =~ "Plot.geom_bar/3"
    end

    test "x and y together are refused, since it counts along one and the count is the other" do
      plot = Plot.new(@rows, %{x: :cyl, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_bar(plot) end
      assert error.message =~ "Plot.geom_bar/3"
      assert error.message =~ ":x, :y"
    end

    test "y alone is counted along, for horizontal bars" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.geom_bar(%{y: :cyl})

      assert [%Plot.Layer{mapping: %{y: "cyl"}}] = plot.reversed_layers
    end

    test "neither x nor y mapped is refused, naming both" do
      plot = Plot.new(@rows)

      error = assert_raise ArgumentError, fn -> Plot.geom_bar(plot) end
      assert error.message =~ "one of :x, :y"
    end

    test "a weight from a column that is not a number is refused, naming the column and its type" do
      plot = Plot.new(@rows, %{x: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_bar(plot, %{weight: :cyl}) end
      assert error.message =~ "Plot.geom_bar/3"
      assert error.message =~ ~s("cyl")
      assert error.message =~ ":string"
    end
  end

  describe "geom_path/3 and geom_line/3" do
    test "a path layer records its geom with ggplot2's ends, corners and mitre limit by default" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_path(%{group: :cyl})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Path{line_end: :butt, line_join: :round, mitre_limit: 10.0},
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 mapping: %{group: "cyl"},
                 fixed: %{}
               }
             ]
    end

    test "a line layer records its geom, oriented along x by default" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_line()

      assert [
               %Plot.Layer{
                 geom: %Geom.Line{
                   orientation: :x,
                   line_end: :butt,
                   line_join: :round,
                   mitre_limit: 10.0
                 },
                 stat: %Stat.Identity{},
                 position: %Position.Identity{}
               }
             ] = plot.reversed_layers
    end

    test "the options choose the geom's ends, corners, mitre limit and orientation" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_line(orientation: :y, lineend: :square, linejoin: :mitre, linemitre: 4)

      assert [
               %Plot.Layer{
                 geom: %Geom.Line{
                   orientation: :y,
                   line_end: :square,
                   line_join: :mitre,
                   mitre_limit: 4.0
                 }
               }
             ] = plot.reversed_layers
    end

    test "a line width and an alpha are set for every line, whole numbers as floats" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_path(linewidth: 2, alpha: 1)

      assert [%Plot.Layer{fixed: %{linewidth: 2.0, alpha: 1.0}}] = plot.reversed_layers
    end

    test "a colour is set for every line of a path or a line, and they take no fill" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for add <- [&Plot.geom_path/2, &Plot.geom_line/2] do
        assert [%Plot.Layer{fixed: %{color: "#FF0000"}}] =
                 add.(plot, colour: "red").reversed_layers

        assert_raise NimbleOptions.ValidationError, fn -> add.(plot, fill: "red") end
      end
    end

    test "a line width below 0, a mitre limit below 1 or an end or corner not taken is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for {option, value} <- [
            linewidth: -0.5,
            linewidth: "2",
            linemitre: 0.5,
            lineend: :flat,
            linejoin: :miter,
            orientation: :z
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_line(plot, [{option, value}])
          end

        assert error.key == option
      end
    end

    test "a path takes no orientation, which only lines are put in order of" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.geom_path(plot, orientation: :y)
        end

      assert error.message =~ "orientation"
    end

    test "paths and lines accept a group and a mapped alpha" do
      for add <- [&Plot.geom_path/2, &Plot.geom_line/2] do
        plot =
          @rows
          |> Plot.new(%{x: :wt, y: :mpg})
          |> add.(%{group: :cyl, alpha: :mpg})

        assert [%Plot.Layer{mapping: %{group: "cyl", alpha: "mpg"}}] = plot.reversed_layers
      end
    end

    test "an aesthetic lines cannot use is refused, naming the call" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_line(plot, %{weight: :cyl}) end
      assert error.message =~ "Plot.geom_line/3"
      assert error.message =~ ":weight"

      error = assert_raise ArgumentError, fn -> Plot.geom_path(plot, %{linewidth: :cyl}) end
      assert error.message =~ "Plot.geom_path/3"
      assert error.message =~ ":linewidth"
    end

    test "a column the data does not have is refused, naming the call" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_path(plot, %{group: :cly}) end
      assert error.message =~ "Plot.geom_path/3"

      error = assert_raise ArgumentError, fn -> Plot.geom_line(plot, %{group: :cly}) end
      assert error.message =~ "Plot.geom_line/3"
    end

    test "x or y mapped by neither the layer nor the plot is refused, naming the call" do
      plot = Plot.new(@rows, %{x: :wt})

      for {add, function} <- [
            {&Plot.geom_path/1, "Plot.geom_path/3"},
            {&Plot.geom_line/1, "Plot.geom_line/3"}
          ] do
        error = assert_raise ArgumentError, fn -> add.(plot) end
        assert error.message =~ function
        assert error.message =~ ":y"
      end
    end

    # grid draws a line 0 wide as the thinnest it can, and refuses a mitre limit below 1.
    test "a line width of 0 and a mitre limit of 1 are values like any other" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_path(linewidth: 0, linemitre: 1)

      assert [%Plot.Layer{fixed: %{linewidth: +0.0}, geom: %Geom.Path{mitre_limit: 1.0}}] =
               plot.reversed_layers
    end
  end

  describe "facet_wrap/3" do
    test "a plot records the wrapped facet with its columns by their names in the data" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.facet_wrap([:cyl, "wt"], ncol: 2)

      assert plot.facet == %Facet.Wrap{
               facets: ["cyl", "wt"],
               nrow: :none,
               ncol: 2,
               scales: :fixed
             }
    end

    test "one column needs no list, an option not given is recorded as :none, and scales as given" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.facet_wrap(:cyl, nrow: 3, scales: :free_y)

      assert plot.facet == %Facet.Wrap{facets: ["cyl"], nrow: 3, ncol: :none, scales: :free_y}
    end

    test "a column the data does not have is refused, naming it and the data's columns" do
      plot = Plot.new(@rows)

      error = assert_raise ArgumentError, fn -> Plot.facet_wrap(plot, :cly) end
      assert error.message =~ "Plot.facet_wrap/3"
      assert error.message =~ ":cly"
      assert error.message =~ ~s("cyl")
    end

    test "a value that is not a column reference is refused" do
      plot = Plot.new(@rows)

      error = assert_raise ArgumentError, fn -> Plot.facet_wrap(plot, ncol: 2) end
      assert error.message =~ "{:ncol, 2}"
    end

    test "no column at all is refused" do
      plot = Plot.new(@rows)

      assert_raise ArgumentError, ~r/none/, fn -> Plot.facet_wrap(plot, []) end
    end

    test "a column named twice is refused" do
      plot = Plot.new(@rows)

      error = assert_raise ArgumentError, fn -> Plot.facet_wrap(plot, [:cyl, "cyl"]) end
      assert error.message =~ "Plot.facet_wrap/3"
      assert error.message =~ ~s(:cyl, "cyl")
      assert error.message =~ ~s(column "cyl" more than once)
    end

    test "a count that is not a positive whole number is refused by the option's validation" do
      plot = Plot.new(@rows)

      assert_raise NimbleOptions.ValidationError, fn -> Plot.facet_wrap(plot, :cyl, nrow: 0) end
    end
  end
end
