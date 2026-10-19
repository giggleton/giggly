defmodule Giggly.PlotTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, DataFrame, Facet, Geom, Plot, Position, Scale, Stat}

  doctest Giggly.Plot

  @rows %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]}

  describe "new/2" do
    test "a plot records the null facet, cartesian coordinates and the gray theme by default" do
      plot = Plot.new(@rows)

      assert {plot.facet, plot.coord, plot.theme} ==
               {%Facet.Null{}, %Coord.Cartesian{clip: :on}, :gray}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 draws `ggplot(df, aes(wt, height)) + geom_point(data = df2)`
    # where only df2 has `height`, taking x and y from df2.
    test "the mapping may name a column only a layer's own table holds" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :height})
        |> Plot.geom_point(data: %{"wt" => [1.0, 2.0], "height" => [10.0, 11.0]})

      assert [%Plot.Layer{mapping: %{}}] = plot.reversed_layers
    end

    test "a number is a constant rather than read as a column's name" do
      rows = %{"2.5" => [2.62, 2.875], "mpg" => [21.0, 22.8]}

      assert Plot.new(rows, %{x: 2.5, y: :mpg}).mapping === %{x: {:constant, 2.5}, y: "mpg"}
    end

    test "a value the mapping grammar refuses is refused here, naming the call and the value" do
      error = assert_raise ArgumentError, fn -> Plot.new(@rows, %{x: :wt, colour: nil}) end
      assert error.message =~ "Plot.new/2"
      assert error.message =~ ":color to nil"
    end
  end

  describe "mappings of expressions and constants" do
    test "a layer holds each value resolved, an expression's columns by name as strings" do
      divide = &Kernel.//2
      plot = Plot.new(@rows, %{x: :wt})

      assert [%Plot.Layer{mapping: mapping}] =
               Plot.geom_point(plot, %{y: {divide, [:mpg, :wt]}, colour: {:constant, "a"}}).reversed_layers

      assert mapping === %{y: {divide, ["mpg", "wt"]}, color: {:constant, "a"}}
    end

    test "a column an expression reads is checked against the layer's table, naming the column" do
      plot = Plot.new(@rows, %{x: :wt})

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_point(plot, %{y: {&Kernel.//2, [:mpg, :weight]}})
        end

      assert error.message =~ "Plot.geom_point/3"
      assert error.message =~ ":y"
      assert error.message =~ ~s("weight")
      assert error.message =~ "the plot's data"
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 fails to build `ggplot(df, aes(wt, mpg / cyl)) +
    # geom_point(data = df2)` where df2 lacks `cyl`: "object 'cyl' not found". The expression here
    # is a capture the compiler does not inline, so the message shows it as it was written.
    test "a column an expression from the plot's mapping reads is checked against each layer's" do
      plot = Plot.new(@rows, %{x: :wt, y: {&Float.round/2, [:mpg, :cyl]}})
      own = %{"wt" => [3.0], "mpg" => [20.0]}

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot, data: own) end

      assert error.message =~ "takes :y from"
      assert error.message =~ ~s(to {&Float.round/2, ["mpg", "cyl"]})
      assert error.message =~ ~s(no column "cyl")
      assert error.message =~ "own data"
    end

    test "a value the grammar refuses in a layer's own mapping is refused by the layer function" do
      plot = Plot.new(@rows, %{x: :wt})

      error =
        assert_raise ArgumentError, fn -> Plot.geom_point(plot, %{y: :mpg, colour: nil}) end

      assert String.starts_with?(error.message, "Plot.geom_point/3 maps :color to nil, but ")
    end

    # ggplot2 4.0.3 in R 4.6.1 counts a weight of whole numbers (`1L, 2L, 4L`) and one of missing
    # values only (`NA_real_`) without complaint: 4 and 3, and 0 and 0.
    test "a weight column of whole numbers, or of missing values only, is accepted at the call" do
      rows = %{"class" => ["suv", "suv", "compact"], "w" => [1, 2, 4], "none" => [nil, nil, nil]}
      plot = Plot.new(rows, %{x: :class})

      assert [%Plot.Layer{}] = Plot.geom_bar(plot, %{weight: :w}).reversed_layers
      assert [%Plot.Layer{}] = Plot.geom_bar(plot, %{weight: :none}).reversed_layers
    end

    test "a constant reads no column, so a layer's own table needs none for it" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, colour: {:constant, "smooth"}})

      assert [%Plot.Layer{}] =
               Plot.geom_point(plot, data: %{"wt" => [3.0], "mpg" => [20.0]}).reversed_layers
    end

    test "a constant weight that is not a number is refused at the call, naming its type" do
      plot = Plot.new(@rows, %{x: :cyl})

      error =
        assert_raise ArgumentError, fn -> Plot.geom_bar(plot, %{weight: {:constant, "a"}}) end

      assert error.message =~ ~s({:constant, "a"})
      assert error.message =~ ":string"
    end

    # ggplot2 4.0.3 in R 4.6.1 fails `stat_count()` for `weight = factor(wt)`: `rowsum()`'s "'x'
    # must be numeric".
    test "a factor's weight is refused at the call, its type a category" do
      plot = Plot.new(@rows, %{x: :cyl})

      error =
        assert_raise ArgumentError, fn -> Plot.geom_bar(plot, %{weight: {:factor, [:wt]}}) end

      assert error.message =~ ":category"
    end

    test "an expression's weight is not checked at the call, its type known only when run" do
      plot = Plot.new(@rows, %{x: :cyl})

      assert [%Plot.Layer{}] =
               Plot.geom_bar(plot, %{weight: {&Kernel.to_string/1, [:wt]}}).reversed_layers
    end
  end

  describe "mappings of after_stat" do
    # ggplot2 4.0.3 in R 4.6.1 counts `geom_bar(aes(class, after_stat(prop)))`: the stat sees only
    # x, so it counts along x and takes y for no second position.
    test "an after_stat names no column of the table, and is neither counted along nor exclusive" do
      plot = Plot.new(@rows, %{x: :cyl})

      assert [%Plot.Layer{mapping: %{y: {:after_stat, ["prop"]}}}] =
               Plot.geom_bar(plot, %{y: {:after_stat, [:prop]}}).reversed_layers
    end

    # ggplot2 4.0.3 in R 4.6.1 documents `stat_count()`'s computed variables as `count` and `prop`;
    # its table also holds `width`, which a mapping here cannot read.
    test "an after_stat naming a variable its stat does not compute is refused, listing those it does" do
      plot = Plot.new(@rows, %{x: :cyl})

      error =
        assert_raise ArgumentError, fn -> Plot.geom_bar(plot, %{y: {:after_stat, [:width]}}) end

      assert error.message =~ ~s(maps :y to {:after_stat, ["width"]})
      assert error.message =~ ~s(no variable "width")
      assert error.message =~ ~s("count", "prop")
    end

    test "an after_stat the layer takes from the plot's mapping is checked against its stat" do
      plot = Plot.new(@rows, %{x: :cyl, y: {:after_stat, [:density]}})

      error = assert_raise ArgumentError, fn -> Plot.geom_bar(plot) end

      assert error.message =~ ~s(takes :y from the plot's mapping, which maps it to {:after_stat)
      assert error.message =~ ~s(no variable "density")
    end

    # ggplot2 4.0.3 in R 4.6.1 lets `geom_point(aes(colour = after_stat(y)))` read the layer's own
    # aesthetics; the identity stat documents no computed variables, so here it has none.
    test "a layer whose stat computes nothing refuses every after_stat" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_point(plot, %{colour: {:after_stat, [:count]}})
        end

      assert error.message =~ "its stat computes no variables, so an after_stat has none to read"
    end

    # ggplot2 4.0.3 in R 4.6.1 puts `weight = after_stat(count)` into the counted table, where it
    # does nothing: `stat_count()`'s `dropped_aes` is "weight".
    test "an after_stat for an aesthetic its stat consumes is refused" do
      plot = Plot.new(@rows, %{x: :cyl})

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_bar(plot, %{weight: {:after_stat, [:count]}})
        end

      assert error.message =~ ~s(maps :weight to {:after_stat, ["count"]})
      assert error.message =~ "its stat consumes :weight as it computes"
    end

    # ggplot2 4.0.3 in R 4.6.1 refuses `geom_bar(aes(x = after_stat(count)))`: "`stat_count()`
    # requires an x or y aesthetic."
    test "an aesthetic mapped only after the stat does not meet what the stat requires" do
      plot = Plot.new(@rows)

      error =
        assert_raise ArgumentError, fn -> Plot.geom_bar(plot, %{x: {:after_stat, [:count]}}) end

      assert error.message =~ "needs one of :x, :y"
      assert error.message =~ "maps :x only after its stat"
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
                 data: :none,
                 mapping: %{x: "wt", y: "mpg", group: "cyl"},
                 fixed: %{},
                 accepted: [:alpha, :color, :group, :x, :y],
                 annotation: false
               }
             ]
    end

    test "a column the data does not have is refused by the layer that maps it" do
      plot = Plot.new(@rows, %{x: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot, %{y: :mgp}) end
      assert error.message =~ "Plot.geom_point/3"
    end

    # A point's fill colours only the filled shapes, which Giggly does not draw yet.
    test "an aesthetic points cannot use is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot, %{fill: :cyl}) end
      assert error.message =~ "Plot.geom_point/3"
      assert error.message =~ ":fill"
      assert error.message =~ ":group"
    end

    # ggplot2 carries an aesthetic a layer takes from the plot and cannot use, as a plot's `label`
    # rides along in a point layer under a text layer.
    test "an aesthetic points cannot use is taken unused from the plot's mapping" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg, fill: :cyl})
        |> Plot.geom_point()

      assert [%Plot.Layer{mapping: %{}}] = plot.reversed_layers
    end

    test "points map their colour, written colour or color" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert %Plot{reversed_layers: [%Plot.Layer{mapping: %{color: "cyl"}}]} =
               Plot.geom_point(plot, %{colour: :cyl})
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
                 data: :none,
                 mapping: %{x: "cyl", y: "mpg"},
                 fixed: %{},
                 accepted: [:alpha, :color, :fill, :group, :x, :y],
                 annotation: false
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

      error = assert_raise ArgumentError, fn -> Plot.geom_col(plot, %{size: :wt}) end
      assert error.message =~ "Plot.geom_col/3"
      assert error.message =~ ":size"
    end

    test "bars map their border's colour and their fill" do
      plot = Plot.new(@rows, %{x: :cyl, y: :mpg})

      assert %Plot{reversed_layers: [%Plot.Layer{mapping: %{color: "wt", fill: "cyl"}}]} =
               Plot.geom_col(plot, %{colour: :wt, fill: :cyl})
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
                 data: :none,
                 mapping: %{x: "cyl", weight: "wt"},
                 fixed: %{},
                 accepted: [:group, :weight, :x, :y, :alpha, :color, :fill],
                 annotation: false
               }
             ]
    end

    test "counted bars map their fill and their border's colour" do
      plot = Plot.new(@rows, %{x: :cyl})

      assert %Plot{reversed_layers: [%Plot.Layer{mapping: %{color: "cyl", fill: "cyl"}}]} =
               Plot.geom_bar(plot, %{fill: :cyl, colour: :cyl})
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
    test "paths and lines map their colour, and refuse a fill, which a line has none of" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert %Plot{reversed_layers: [%Plot.Layer{mapping: %{color: "cyl"}}]} =
               Plot.geom_path(plot, %{colour: :cyl})

      assert %Plot{reversed_layers: [%Plot.Layer{mapping: %{color: "cyl"}}]} =
               Plot.geom_line(plot, %{colour: :cyl})

      error = assert_raise ArgumentError, fn -> Plot.geom_line(plot, %{fill: :cyl}) end
      assert error.message =~ ":fill"
    end

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
                 data: :none,
                 mapping: %{group: "cyl"},
                 fixed: %{},
                 accepted: [:alpha, :color, :group, :x, :y],
                 annotation: false
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

  describe "geom_text/3" do
    @cars %{"wt" => [2.62, 2.32], "mpg" => [21.0, 22.8], "model" => ["Mazda RX4", "Datsun 710"]}

    test "a text layer records its geom, not checking overlap, the identity stat and nudging" do
      plot =
        @cars
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_text(%{label: :model})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Text{check_overlap: false},
                 stat: %Stat.Identity{},
                 position: %Position.Nudge{},
                 data: :none,
                 mapping: %{label: "model"},
                 fixed: %{},
                 accepted: [:alpha, :color, :group, :label, :x, :y],
                 annotation: false
               }
             ]
    end

    test "the options set the labels' look for every row, and check overlap" do
      plot =
        @cars
        |> Plot.new(%{x: :wt, y: :mpg, label: :model})
        |> Plot.geom_text(
          check_overlap: true,
          size: 5,
          angle: 45,
          hjust: :inward,
          vjust: 1,
          family: "Times New Roman",
          colour: "red",
          alpha: 0.5,
          nudge_x: 0.1,
          nudge_y: -1
        )

      assert [
               %Plot.Layer{
                 geom: %Geom.Text{check_overlap: true},
                 fixed: %{
                   size: 5.0,
                   angle: 45.0,
                   hjust: :inward,
                   vjust: 1.0,
                   family: "Times New Roman",
                   color: "#FF0000",
                   alpha: 0.5,
                   nudge_x: 0.1,
                   nudge_y: -1.0
                 }
               }
             ] = plot.reversed_layers
    end

    test "a column the data does not have is refused by the text layer that maps it" do
      plot = Plot.new(@cars, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_text(plot, %{label: :modle}) end
      assert error.message =~ "Plot.geom_text/3"
      assert error.message =~ ":modle"
    end

    test "a size of 0 is a size like any other; only one below 0 is refused" do
      plot =
        @cars
        |> Plot.new(%{x: :wt, y: :mpg, label: :model})
        |> Plot.geom_text(size: 0)

      assert [%Plot.Layer{fixed: %{size: +0.0}}] = plot.reversed_layers
    end

    test "a label mapped by neither the layer nor the plot is refused, naming the call" do
      plot = Plot.new(@cars, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_text(plot) end
      assert error.message =~ "Plot.geom_text/3"
      assert error.message =~ ":label"
    end

    test "an aesthetic text cannot use, mapped by the layer, is refused" do
      plot = Plot.new(@cars, %{x: :wt, y: :mpg, label: :model})

      error = assert_raise ArgumentError, fn -> Plot.geom_text(plot, %{fill: :model}) end
      assert error.message =~ "Plot.geom_text/3"
      assert error.message =~ ":fill"
    end

    test "a size below 0, or an angle, justification or nudge of the wrong kind, is refused" do
      plot = Plot.new(@cars, %{x: :wt, y: :mpg, label: :model})

      for {key, value} <- [
            size: -1,
            size: "5",
            angle: "45",
            hjust: :sideways,
            vjust: "top",
            family: :serif,
            nudge_x: "0.1",
            nudge_y: :down
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_text(plot, [{key, value}])
          end

        assert error.key == key
      end
    end

    test "every word ggplot2 justifies by is taken, as is any number" do
      plot = Plot.new(@cars, %{x: :wt, y: :mpg, label: :model})

      words = [:left, :center, :right, :bottom, :middle, :top, :inward, :outward]

      justified =
        Enum.map(words ++ [-0.5, 2], fn just ->
          [%Plot.Layer{fixed: %{hjust: hjust}}] =
            Plot.geom_text(plot, hjust: just).reversed_layers

          hjust
        end)

      assert justified === words ++ [-0.5, 2.0]
    end
  end

  describe "a layer's own table" do
    @own %{"wt" => [4.0, 3.0], "mpg" => [16.0, 15.0], "name" => ["p", "q"]}

    test "each layer function draws the table its data: option gives in place of the plot's" do
      plot = Plot.new(@rows, %{x: :wt})

      for add_layer <- [
            fn plot -> Plot.geom_point(plot, %{y: :mpg}, data: @own) end,
            fn plot -> Plot.geom_bar(plot, data: @own) end,
            fn plot -> Plot.geom_col(plot, %{y: :mpg}, data: @own) end,
            fn plot -> Plot.geom_path(plot, %{y: :mpg}, data: @own) end,
            fn plot -> Plot.geom_line(plot, %{y: :mpg}, data: @own) end,
            fn plot -> Plot.geom_text(plot, %{y: :mpg, label: :name}, data: @own) end,
            fn plot ->
              Plot.geom_rect(plot, %{xmin: :mpg, xmax: :mpg}, data: @own, ymin: 0, ymax: 1)
            end
          ] do
        %Plot{reversed_layers: [layer]} = drawn = add_layer.(plot)
        table = Plot.layer_table(drawn, layer)
        assert DataFrame.pull(table, "wt") == [4.0, 3.0]
      end
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 fails to build `ggplot(df, aes(wt, mpg, colour = cyl)) +
    # geom_point(data = df2)` where df2 lacks `cyl`: "object 'cyl' not found".
    test "a column the plot's mapping names is refused at the call when the layer's own table lacks it" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, colour: :cyl})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot, data: @own) end
      assert error.message =~ "Plot.geom_point/3"
      assert error.message =~ ":color"
      assert error.message =~ "plot's mapping"
      assert error.message =~ ~s("cyl")
      assert error.message =~ "own data"
      assert error.message =~ ~s("name")
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 fails the same way when the plot maps `label`, which points
    # cannot use, to a column the layer's own table lacks: it evaluates every inherited aesthetic.
    test "an aesthetic the layer takes from the plot and cannot use still needs its column" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, label: :cyl})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot, data: @own) end
      assert error.message =~ ":label"
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 builds `geom_point(data = df2, colour = "red")` under a plot
    # mapping colour to a column df2 lacks, every point red.
    test "an aesthetic the layer sets needs no column in its own table" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, colour: :cyl})

      assert [%Plot.Layer{}] = Plot.geom_point(plot, data: @own, colour: "red").reversed_layers
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 builds `geom_point(aes(colour = mpg), data = df2)` under a
    # plot mapping colour to a column df2 lacks.
    test "an aesthetic the layer maps itself needs only its own column" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, colour: :cyl})

      assert [%Plot.Layer{mapping: %{color: "mpg"}}] =
               Plot.geom_point(plot, %{colour: :mpg}, data: @own).reversed_layers
    end

    test "a column the layer's own mapping names is refused when its own table lacks it" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error =
        assert_raise ArgumentError, fn -> Plot.geom_point(plot, %{colour: :cyl}, data: @own) end

      assert error.message =~ ":color"
      assert error.message =~ ":cyl"
      assert error.message =~ "own data"
    end

    test "a misspelt column in the plot's mapping is refused by the first layer to take it" do
      plot = Plot.new(@rows, %{x: :wt, y: :mgp})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot) end
      assert error.message =~ "Plot.geom_point/3"
      assert error.message =~ ":y"
      assert error.message =~ "plot's mapping"
      assert error.message =~ ~s("mgp")
      assert error.message =~ "the plot's data"
      assert error.message =~ ~s("mpg")
    end

    test "a weight's column is read from the layer's own table" do
      plot = Plot.new(%{"cyl" => ["6", "4"], "weight" => [1.0, 2.0]}, %{x: :cyl, weight: :weight})
      own = %{"cyl" => ["6", "4"], "weight" => ["heavy", "light"]}

      error = assert_raise ArgumentError, fn -> Plot.geom_bar(plot, data: own) end
      assert error.message =~ ":string"
    end

    test "a data: option that is not a table is refused at the call" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert_raise ArgumentError, ~r/expected a table/, fn ->
        Plot.geom_point(plot, data: [1, 2])
      end
    end
  end

  describe "geom_rect/3" do
    test "a rectangle layer records its geom, the identity stat and position, and its corners" do
      plot =
        @rows
        |> Plot.new(%{xmin: :wt})
        |> Plot.geom_rect(%{xmax: :mpg}, ymin: 0, ymax: :infinity)

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Rect{},
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{xmax: "mpg"},
                 fixed: %{ymin: 0.0, ymax: :infinity},
                 accepted: [:alpha, :color, :fill, :group, :xmax, :xmin, :ymax, :ymin],
                 annotation: false
               }
             ]
    end

    test "a column its own mapping names that the data lacks is refused, naming the call" do
      plot = Plot.new(@rows, %{xmin: :wt})

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_rect(plot, %{xmax: :weight}, ymin: 0, ymax: 1)
        end

      assert error.message =~ "Plot.geom_rect/3 maps :xmax"
    end

    test "a corner neither mapped nor set is refused, naming the call and the corner" do
      plot = Plot.new(@rows, %{xmin: :wt, xmax: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_rect(plot, ymin: 0) end
      assert error.message =~ "Plot.geom_rect/3 needs :ymax"
      assert error.message =~ "no option sets it"
    end

    test "a corner is set to a number or an infinity, and nothing else" do
      plot = Plot.new(@rows, %{xmin: :wt, xmax: :mpg})

      assert_raise NimbleOptions.ValidationError, ~r/expected a position on the axis/, fn ->
        Plot.geom_rect(plot, ymin: "0", ymax: 1)
      end
    end

    # ggplot2 4.0 places a rectangle by its x and width too, which waits.
    test "a rectangle's own mapping of x is refused, naming the call" do
      plot = Plot.new(@rows)

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_rect(plot, %{x: :wt}, xmin: 0, xmax: 1, ymin: 0, ymax: 1)
        end

      assert error.message =~ "Plot.geom_rect/3 cannot use :x"
    end
  end

  describe "annotate/3" do
    test "an annotation records its geom, the identity stat and position, and a table of its values" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
        |> Plot.annotate(:text, x: [2, 3], y: 25, label: "a", size: 5, check_overlap: true)

      [layer] = plot.reversed_layers

      assert %Plot.Layer{
               geom: %Geom.Text{check_overlap: true},
               stat: %Stat.Identity{},
               position: %Position.Identity{},
               mapping: %{x: "x", y: "y"},
               fixed: %{label: "a", size: 5.0},
               accepted: [:alpha, :color, :group, :label, :x, :y],
               annotation: true
             } = layer

      table = Plot.layer_table(plot, layer)

      assert {DataFrame.pull(table, "x"), DataFrame.pull(table, "y")} ===
               {[2.0, 3.0], [25.0, 25.0]}

      assert Plot.computed_mapping(plot, layer) == %{x: "x", y: "y"}
    end

    test "each geom records the kind the function of its name records, with its parameters" do
      plot = Plot.new(@rows)

      kinds =
        for {geom, options} <- [
              point: [x: 1, y: 1],
              col: [x: 1, y: 1],
              bar: [x: 1, y: 1],
              path: [x: [1, 2], y: [1, 2], lineend: :round],
              line: [x: [1, 2], y: [1, 2], orientation: :y],
              rect: [xmin: 1, xmax: 2, ymin: 1, ymax: 2]
            ] do
          %Plot{reversed_layers: [layer]} = Plot.annotate(plot, geom, options)
          Plot.layer_geom(layer)
        end

      assert kinds == [
               %Geom.Point{},
               %Geom.Bar{},
               %Geom.Bar{},
               %Geom.Path{line_end: :round, line_join: :round, mitre_limit: 10.0},
               %Geom.Line{orientation: :y, line_end: :butt, line_join: :round, mitre_limit: 10.0},
               %Geom.Rect{}
             ]
    end

    test "a geom it does not draw with is refused, naming the geoms it does" do
      plot = Plot.new(@rows)

      error = assert_raise ArgumentError, fn -> Plot.annotate(plot, :segment, x: 1, y: 1) end
      assert error.message =~ ":point, :col, :bar, :path, :line, :text or :rect, got: :segment"
    end

    # ggplot2 4.0.3 warns "Ignoring unknown aesthetics: xmin", and the x axis still reaches it;
    # "Ignoring unknown parameters: `label`" for a rectangle; and ignores `nudge_x`, as an
    # annotation is not nudged.
    test "an option its geom does not take is refused, naming it" do
      plot = Plot.new(@rows)

      for {geom, options, refused} <- [
            {:text, [x: 1, y: 1, label: "a", xmin: 0], ":xmin"},
            {:rect, [xmin: 1, xmax: 2, ymin: 1, ymax: 2, label: "a"], ":label"},
            {:text, [x: 1, y: 1, label: "a", nudge_x: 1], ":nudge_x"},
            {:col, [x: 1, y: 1, position: :dodge], ":position"},
            {:point, [x: 1, y: 1, data: @rows], ":data"}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.annotate(plot, geom, options)
          end

        assert error.message =~ "unknown options [#{refused}]"
      end
    end

    # ggplot2 4.0.3: "Unequal parameter lengths: x (2) and y (3)", and "x (2) and label (3)".
    test "options given different numbers of values are refused, naming each" do
      plot = Plot.new(@rows)

      positions =
        assert_raise ArgumentError, fn ->
          Plot.annotate(plot, :text, x: [1, 2], y: [1, 2, 3], label: "a")
        end

      assert positions.message =~ "Plot.annotate/3 gives :x 2 values and :y 3 values"

      labels =
        assert_raise ArgumentError, fn ->
          Plot.annotate(plot, :text, x: [1, 2], y: 1, label: ["a", "b", "c"])
        end

      assert labels.message =~ ":x 2 values and :label 3 values"
    end

    # ggplot2 4.0.3: "`geom_text()` requires the following missing aesthetics: label". An
    # annotation takes no position from the plot's mapping, so that mapping gives it none.
    test "an aesthetic its geom needs and is not given is refused, the plot's mapping giving none" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      label = assert_raise ArgumentError, fn -> Plot.annotate(plot, :text, x: 1, y: 1) end
      assert label.message =~ "Plot.annotate/3 needs :label, but :text is given no value for it"

      position = assert_raise ArgumentError, fn -> Plot.annotate(plot, :text, label: "a") end
      assert position.message =~ "Plot.annotate/3 needs :x, :y"
    end

    test "an aesthetic its geom sets once for the layer takes one value, not a list" do
      plot = Plot.new(@rows)

      assert_raise NimbleOptions.ValidationError, ~r/invalid value for :size option/, fn ->
        Plot.annotate(plot, :text, x: [1, 2], y: 1, label: "a", size: [3, 5])
      end
    end

    test "a list's values are of one type, as a column of the layer's table holds" do
      plot = Plot.new(@rows)

      assert_raise ArgumentError, ~r/the column :fill .*\(:none and "#FF0000"\)/, fn ->
        Plot.annotate(plot, :rect, xmin: 1, xmax: 2, ymin: 1, ymax: 2, fill: [:none, "red"])
      end

      assert_raise ArgumentError, ~r/the column :label .*\("a" and 1\)/, fn ->
        Plot.annotate(plot, :text, x: [1, 2], y: 1, label: ["a", 1])
      end

      assert_raise ArgumentError, ~r/the column "x" .*\(1.0 and "a"\)/, fn ->
        Plot.annotate(plot, :text, x: [1, "a"], y: 1, label: "a")
      end
    end

    test "each value of a list is checked as one value is" do
      plot = Plot.new(@rows)

      assert_raise NimbleOptions.ValidationError, ~r/expected a number from 0 to 1, got: 2/, fn ->
        Plot.annotate(plot, :point, x: [1, 2], y: 1, alpha: [0.5, 2])
      end
    end

    test "a position is a value a scale places, and a label one text writes" do
      plot = Plot.new(@rows)

      assert_raise NimbleOptions.ValidationError, ~r/expected a position.*got: 2\.\.5/, fn ->
        Plot.annotate(plot, :text, x: 2..5, y: 1, label: "a")
      end

      assert_raise NimbleOptions.ValidationError, ~r/expected a label.*got: %\{\}/, fn ->
        Plot.annotate(plot, :text, x: 1, y: 1, label: %{})
      end
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

    # Golden: ggplot2 4.0.3 in R 4.6.1 facets `ggplot(df) + geom_point(data = df2)` by a column only
    # df2 has; whether some table has every column is checked when the plot is run.
    test "a column the plot's data lacks is taken, since a layer's own table may hold it" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.facet_wrap(:gear)

      assert plot.facet == %Facet.Wrap{facets: ["gear"], nrow: :none, ncol: :none, scales: :fixed}
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

  describe "scale_x_continuous/2, scale_y_continuous/2, xlim/3, ylim/3 and lims/2" do
    test "a plot has no scales until a scale function gives it one" do
      assert Plot.new(@rows).scales === %{}
    end

    test "a scale function records an untrained continuous scale with the options given" do
      labeller = fn breaks -> Enum.map(breaks, &Float.to_string/1) end

      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.scale_x_continuous(
          name: "Weight",
          limits: {2, nil},
          breaks: [2, 3.5],
          minor_breaks: :none,
          labels: labeller
        )
        |> Plot.scale_y_continuous(labels: :none, expand: [mult: {0.5, 1}, add: 2])

      assert plot.scales === %{
               x: %Scale.Continuous{
                 name: "Weight",
                 limits: {2.0, nil},
                 breaks: [2.0, 3.5],
                 minor_breaks: :none,
                 labels: labeller
               },
               y: %Scale.Continuous{labels: :none, expand: [mult: {0.5, 1.0}, add: {2.0, 2.0}]}
             }
    end

    test "an option not given keeps the scale's default" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.scale_x_continuous()
        |> Plot.scale_y_continuous()

      default = %Scale.Continuous{
        name: :default,
        limits: {nil, nil},
        breaks: :default,
        minor_breaks: :default,
        labels: :default,
        expand: [mult: {0.05, 0.05}, add: {0, 0}]
      }

      assert plot.scales === %{x: default, y: default}
    end

    # ggplot2 replaces a scale added for an aesthetic that has one ("Scale for x is already
    # present"): in R 4.6.1, breaks set before xlim() are lost, and limits set before a scale.
    test "a later scale for an aesthetic replaces the earlier, xlim/3 and lims/2 included" do
      plot = Plot.new(@rows)

      breaks_then_limits =
        plot
        |> Plot.scale_x_continuous(breaks: [2, 4])
        |> Plot.xlim(1, 6)

      limits_then_breaks =
        plot
        |> Plot.lims(x: {1, 6}, y: {0, 30})
        |> Plot.scale_x_continuous(breaks: [2, 4])

      assert {breaks_then_limits.scales, limits_then_breaks.scales} ===
               {%{x: %Scale.Continuous{limits: {1.0, 6.0}}},
                %{
                  x: %Scale.Continuous{breaks: [2.0, 4.0]},
                  y: %Scale.Continuous{limits: {0.0, 30.0}}
                }}
    end

    # ggplot2 4.0.3 takes `xlim(3, 3)`, an axis of zero width, which is widened as a single value;
    # its `limits()` reverses an axis given high to low, and a scale function sorts its limits once
    # transformed, so they are kept as given.
    test "limits may be equal, and given high to low reverse the axis xlim/3 or lims/2 sets" do
      plot = Plot.new(@rows)

      assert Plot.xlim(plot, 3, 3).scales.x === %Scale.Continuous{limits: {3.0, 3.0}}

      assert Plot.xlim(plot, 3.5, 3).scales.x ===
               %Scale.Continuous{limits: {3.5, 3.0}, transform: :reverse}

      assert Plot.ylim(plot, 6, nil).scales.y === %Scale.Continuous{limits: {6.0, nil}}

      assert Plot.lims(plot, y: {6, 1}).scales.y ===
               %Scale.Continuous{limits: {6.0, 1.0}, transform: :reverse}

      assert Plot.scale_x_continuous(plot, limits: {5, 2}).scales.x ===
               %Scale.Continuous{limits: {5.0, 2.0}}
    end

    test "a transformed scale's function records its transformation and its options as given" do
      plot = Plot.new(@rows)

      for {function, aesthetic, transform} <- [
            {&Plot.scale_x_log10/2, :x, :log10},
            {&Plot.scale_y_log10/2, :y, :log10},
            {&Plot.scale_x_sqrt/2, :x, :sqrt},
            {&Plot.scale_y_sqrt/2, :y, :sqrt},
            {&Plot.scale_x_reverse/2, :x, :reverse},
            {&Plot.scale_y_reverse/2, :y, :reverse}
          ] do
        assert function.(plot, name: "Mileage", limits: {30, 10}).scales ===
                 %{
                   aesthetic => %Scale.Continuous{
                     transform: transform,
                     name: "Mileage",
                     limits: {30.0, 10.0}
                   }
                 }
      end

      for transform <- [:identity, :log10, :sqrt, :reverse, :reciprocal] do
        assert Plot.scale_x_continuous(plot, transform: transform).scales.x ===
                 %Scale.Continuous{transform: transform}
      end
    end

    test "a transformed scale's function takes no transformation, and names itself" do
      plot = Plot.new(@rows)

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.scale_y_log10(plot, transform: :sqrt)
        end

      assert error.key == [:transform]

      for {function, name} <- [
            {&Plot.scale_x_log10/2, "Plot.scale_x_log10/2"},
            {&Plot.scale_y_log10/2, "Plot.scale_y_log10/2"},
            {&Plot.scale_x_sqrt/2, "Plot.scale_x_sqrt/2"},
            {&Plot.scale_y_sqrt/2, "Plot.scale_y_sqrt/2"},
            {&Plot.scale_x_reverse/2, "Plot.scale_x_reverse/2"},
            {&Plot.scale_y_reverse/2, "Plot.scale_y_reverse/2"}
          ] do
        labels = assert_raise ArgumentError, fn -> function.(plot, labels: ["a"]) end
        assert labels.message =~ name
      end
    end

    test "ylim/3 sets the y scale's limits, nil leaving an end to the data" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.ylim(nil, 25)

      assert plot.scales === %{y: %Scale.Continuous{limits: {nil, 25.0}}}
    end

    test "an option a scale cannot take is refused, naming it and what was wrong with it" do
      plot = Plot.new(@rows)
      two_arguments = fn _break, _index -> "label" end

      # Each option, its value, and the part of it the refusal shows.
      for {key, value, shown} <- [
            {:name, 5, "5"},
            {:limits, {"a", 3}, ~s({"a", 3})},
            {:limits, [2, 5], "[2, 5]"},
            {:breaks, [1, "a"], ~s(got: "a" in it)},
            {:breaks, 3, "got: 3"},
            {:minor_breaks, [:a], "got: :a in it"},
            {:labels, ["a", 1], "got: 1 in it"},
            {:labels, two_arguments, inspect(two_arguments)},
            {:labels, "label", ~s(got: "label")},
            {:expand, [mult: 1, mult: 2], "[mult: 1, mult: 2]"},
            {:expand, [scale: 1], "[scale: 1]"},
            {:expand, [mult: "a"], ~s([mult: "a"])},
            {:expand, [mult: {0, "a"}], ~s([mult: {0, "a"}])},
            {:expand, [0, 0.05], "[0, 0.05]"},
            {:expand, 0.05, "got: 0.05"},
            {:transform, :log2, ":log2"},
            {:transform, "log10", ~s("log10")}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.scale_x_continuous(plot, [{key, value}])
          end

        assert {error.key, error.message =~ shown} == {key, true}
      end

      misspelt =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.scale_x_continuous(plot, limit: {2, 5})
        end

      assert misspelt.key == [:limit]
    end

    test "limits xlim/3, ylim/3 and lims/2 cannot take are refused" do
      plot = Plot.new(@rows)

      for limit <- [
            fn -> Plot.ylim(plot, "a", 1) end,
            fn -> Plot.lims(plot, z: {1, 6}) end
          ] do
        assert_raise NimbleOptions.ValidationError, limit
      end
    end

    test "a list of labels needs a list of breaks as long" do
      plot = Plot.new(@rows)

      assert_raise ArgumentError, ~r/scale_x_continuous.* 2 labels.* has none/, fn ->
        Plot.scale_x_continuous(plot, labels: ["a", "b"])
      end

      assert_raise ArgumentError,
                   ~r/scale_y_continuous.* 2 labels.*got: \[1\.0, 2\.0, 3\.0\]/,
                   fn ->
                     Plot.scale_y_continuous(plot, labels: ["a", "b"], breaks: [1, 2, 3])
                   end

      assert_raise ArgumentError, ~r/got: :none/, fn ->
        Plot.scale_x_continuous(plot, labels: ["a"], breaks: :none)
      end

      assert Plot.scale_x_continuous(plot, labels: ["a", "b"], breaks: [1, 2]).scales.x.labels ===
               ["a", "b"]
    end
  end

  describe "labs/2" do
    test "a plot has no labels until labs/2 sets them" do
      assert Plot.new(@rows).labels === %{}
    end

    test "labels are recorded by canonical name, and a later call replaces only what it sets" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.labs(x: "first", title: "Title", colour: "Cylinders")
        |> Plot.labs(x: "second", title: :none, tag: "A\nB")

      assert plot.labels === %{
               x: "second",
               title: :none,
               color: "Cylinders",
               tag: "A\nB"
             }
    end

    test "a label that is neither text nor :none is refused" do
      plot = Plot.new(@rows)

      for {key, value} <- [x: 5, title: :centre] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Plot.labs(plot, [{key, value}]) end

        assert error.key == key
      end
    end

    test "a label for nothing a guide or the plot shows is refused, a misspelling among them" do
      plot = Plot.new(@rows)

      for key <- [:shape, :titel] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Plot.labs(plot, [{key, "A"}]) end

        assert error.key == [key]
      end
    end
  end
end
