defmodule Giggly.PlotTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, DataFrame, Facet, Geom, Guide, Plot, Position, Scale, Stat}

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
                 accepted: [:alpha, :color, :fill, :group, :shape, :size, :x, :y],
                 annotation: false
               }
             ]
    end

    test "a column the data does not have is refused by the layer that maps it" do
      plot = Plot.new(@rows, %{x: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot, %{y: :mgp}) end
      assert error.message =~ "Plot.geom_point/3"
    end

    # ggplot2's points draw no label; its text does.
    test "an aesthetic points cannot use is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot, %{label: :cyl}) end
      assert error.message =~ "Plot.geom_point/3"
      assert error.message =~ ":label"
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

    test "a point's shape, size, stroke and fill are set for every point, a shape by name or number" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      by_number = Plot.geom_point(plot, shape: 21, size: 5, stroke: 2, fill: "white")
      by_name = Plot.geom_point(plot, shape: :circle_filled, size: 5, stroke: 2, fill: "white")

      assert [%Plot.Layer{fixed: fixed}] = by_number.reversed_layers
      assert fixed === %{shape: :circle_filled, size: 5.0, stroke: 2.0, fill: "#FFFFFF"}
      assert by_name.reversed_layers === by_number.reversed_layers
    end

    # ggplot2 4.0.3's `translate_shape_string()` table, its spaces written as underscores, and
    # "triangle square" left out for 14, which "square triangle" names.
    test "every shape's number is its place in the list of names, 0 to 25" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      shapes =
        for number <- 0..25 do
          [layer] = Plot.geom_point(plot, shape: number).reversed_layers
          layer.fixed.shape
        end

      assert shapes === [
               :square_open,
               :circle_open,
               :triangle_open,
               :plus,
               :cross,
               :diamond_open,
               :triangle_down_open,
               :square_cross,
               :asterisk,
               :diamond_plus,
               :circle_plus,
               :star,
               :square_plus,
               :circle_cross,
               :square_triangle,
               :square,
               :circle_small,
               :triangle,
               :diamond,
               :circle,
               :bullet,
               :circle_filled,
               :square_filled,
               :diamond_filled,
               :triangle_filled,
               :triangle_down_filled
             ]
    end

    test "a shape of :none is kept, to draw no point, and a stroke of :none, to draw no outline" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert %Plot{reversed_layers: [%Plot.Layer{fixed: %{shape: :none, stroke: :none}}]} =
               Plot.geom_point(plot, shape: :none, stroke: :none)
    end

    # ggplot2 4.0.3 aborts on a name it does not know ("Shape aesthetic contains invalid value"),
    # and R's graphics engine draws no shape past 25, nor a character, which Giggly takes no
    # shape for.
    test "a shape that is neither a name nor a number from 0 to 25 is refused, naming the names" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for shape <- [26, -1, 21.0, :triangle_up, "circle", "a"] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_point(plot, shape: shape)
          end

        assert error.message =~ "got: #{inspect(shape)}"
        assert error.message =~ ":square_open, :circle_open, :triangle_open,"
      end
    end

    test "a size or stroke below 0 is refused, and 0 taken" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert %Plot{reversed_layers: [%Plot.Layer{fixed: %{size: +0.0, stroke: +0.0}}]} =
               Plot.geom_point(plot, size: 0, stroke: 0)

      assert_raise NimbleOptions.ValidationError, ~r/invalid value for :size option/, fn ->
        Plot.geom_point(plot, size: -1)
      end

      assert_raise NimbleOptions.ValidationError,
                   ~r/invalid value for :stroke option.*-0.5/,
                   fn ->
                     Plot.geom_point(plot, stroke: -0.5)
                   end

      assert_raise NimbleOptions.ValidationError, ~r/invalid value for :stroke option.*nil/, fn ->
        Plot.geom_point(plot, stroke: nil)
      end
    end

    test "points map a fill" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(%{fill: :cyl})

      assert [%Plot.Layer{mapping: %{fill: "cyl"}}] = plot.reversed_layers
    end
  end

  describe "a bar's and a rectangle's border" do
    test "a border's width and line type are set for every bar or rectangle, as a line's are" do
      for {add, mapping} <- [
            {&Plot.geom_col/2, %{x: :cyl, y: :mpg}},
            {&Plot.geom_bar/2, %{x: :cyl}},
            {&Plot.geom_rect/2, %{xmin: :wt, xmax: :mpg, ymin: :wt, ymax: :mpg}}
          ] do
        plot = Plot.new(@rows, mapping)

        assert [%Plot.Layer{fixed: %{linewidth: 1.0, linetype: {1, 3}}}] =
                 add.(plot, linewidth: 1, linetype: 3).reversed_layers

        assert [%Plot.Layer{fixed: %{linewidth: +0.0, linetype: :none}}] =
                 add.(plot, linewidth: 0, linetype: :blank).reversed_layers

        for {option, value} <- [linewidth: -0.5, linetype: 7] do
          error =
            assert_raise NimbleOptions.ValidationError, fn -> add.(plot, [{option, value}]) end

          assert error.key == option
        end
      end
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
                 geom: %Geom.Bar{just: 0.5},
                 stat: %Stat.Identity{},
                 position: %Position.Stack{},
                 data: :none,
                 mapping: %{x: "cyl", y: "mpg"},
                 fixed: %{},
                 accepted: [:alpha, :color, :fill, :group, :linetype, :linewidth, :width, :x, :y],
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

    # ggplot2 4.0.3's `geom_col(orientation = "y")` over two numeric columns draws horizontal
    # bars, which the bar geom cannot yet be told to, so the option is not taken.
    test "orientation: is refused, the bars' direction being the geom's alone" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.geom_col(plot, orientation: :y)
        end

      assert error.message =~ "unknown options [:orientation]"
    end

    test "width: is set for every bar, as a float, and just: is the geom's, 0.5 unless given" do
      plot = Plot.new(@rows, %{x: :cyl, y: :mpg})

      assert [%Plot.Layer{geom: %Geom.Bar{just: 0.5}, fixed: %{width: 1.0}}] =
               Plot.geom_col(plot, width: 1).reversed_layers

      assert [%Plot.Layer{geom: %Geom.Bar{just: +0.0}, fixed: fixed}] =
               Plot.geom_col(plot, just: 0).reversed_layers

      assert fixed == %{}
    end

    test "a width that is not a number, and a just: outside 0 to 1, are refused" do
      plot = Plot.new(@rows, %{x: :cyl, y: :mpg})

      for {option, value} <- [width: "wide", just: 1.5, just: -0.1] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_col(plot, [{option, value}])
          end

        assert error.key == option
      end
    end

    test "a mapped width must hold numbers, its column refused at the call naming its type" do
      plot = Plot.new(@rows, %{x: :cyl, y: :mpg})

      assert [%Plot.Layer{mapping: %{width: "wt"}}] =
               Plot.geom_col(plot, %{width: :wt}).reversed_layers

      error = assert_raise ArgumentError, fn -> Plot.geom_col(plot, %{width: :cyl}) end
      assert error.message =~ "Plot.geom_col/3 maps :width to \"cyl\", a :string column"
    end
  end

  describe "geom_bar/3" do
    # ggplot2 4.0.3's `geom_bar(aes(width = w))` and `geom_histogram(aes(width = w))` draw bars of
    # their stat's width whatever `w` holds, and `geom_histogram(width = 0.5)` bins of their own
    # width, so neither takes what would change nothing.
    test "counted bars take width: but no mapped width, and histograms neither" do
      plot = Plot.new(@rows, %{x: :cyl})
      binned = Plot.new(@rows, %{x: :wt})

      assert [%Plot.Layer{fixed: %{width: 0.5}, geom: %Geom.Bar{just: 1.0}}] =
               Plot.geom_bar(plot, width: 0.5, just: 1).reversed_layers

      for call <- [
            fn -> Plot.geom_bar(plot, %{width: :wt}) end,
            fn -> Plot.geom_histogram(binned, %{width: :mpg}) end,
            fn -> Plot.stat_bin(binned, %{width: :mpg}) end
          ] do
        error = assert_raise ArgumentError, call
        assert error.message =~ "cannot use :width"
      end

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.geom_histogram(binned, width: 0.5)
        end

      assert error.message =~ "unknown options [:width]"
    end

    test "a bar layer records the bar geom, counting and stacking" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.geom_bar(%{x: :cyl, weight: :wt})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Bar{just: 0.5},
                 stat: %Stat.Count{},
                 position: %Position.Stack{},
                 data: :none,
                 mapping: %{x: "cyl", weight: "wt"},
                 fixed: %{},
                 accepted: [:group, :weight, :x, :y, :alpha, :color, :fill, :linetype, :linewidth],
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

  describe "geom_count/3 and stat_sum/3" do
    test "a count layer records the point geom, counting at each place and no position" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.geom_count(%{x: :wt, y: :mpg, weight: :wt})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Point{},
                 stat: %Stat.Sum{},
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{x: "wt", y: "mpg", weight: "wt"},
                 fixed: %{},
                 accepted: [:group, :size, :weight, :x, :y, :alpha, :color, :fill, :shape],
                 annotation: false
               }
             ]
    end

    test "stat_sum/3 adds the layer geom_count/3 adds" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert Plot.stat_sum(plot, %{colour: :cyl}, size: 2).reversed_layers ==
               Plot.geom_count(plot, %{colour: :cyl}, size: 2).reversed_layers

      assert Plot.stat_sum(plot, size: 2).reversed_layers ==
               Plot.geom_count(plot, size: 2).reversed_layers
    end

    test "options alone set every point's look, as a point layer's do" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_count(shape: 21, fill: "white", stroke: 1)

      assert [%Plot.Layer{fixed: %{shape: :circle_filled, fill: "#FFFFFF", stroke: 1.0}}] =
               plot.reversed_layers
    end

    test "an option points do not take is refused by the option's validation" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.geom_count(plot, position: :jitter)
        end

      assert error.message =~ "unknown options [:position]"
    end

    # ggplot2 4.0.3's `stat_sum()` requires x and y.
    test "a missing y is refused, naming the function that wrote the layer" do
      plot = Plot.new(@rows, %{x: :wt})

      for {add, function} <- [
            {&Plot.geom_count/1, "Plot.geom_count/3"},
            {&Plot.stat_sum/1, "Plot.stat_sum/3"}
          ] do
        error = assert_raise ArgumentError, fn -> add.(plot) end
        assert error.message =~ "#{function} needs :y"
      end
    end

    test "an aesthetic points cannot draw is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_count(plot, %{linewidth: :wt}) end
      assert error.message =~ "Plot.geom_count/3"
      assert error.message =~ ":linewidth"
    end

    test "a weight from a column that is not a number is refused, naming the column and its type" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_count(plot, %{weight: :cyl}) end
      assert error.message =~ "Plot.geom_count/3 maps :weight to \"cyl\", a :string column"
    end

    # ggplot2 4.0.3 documents `stat_sum()`'s computed variables as `n` and `prop`.
    test "an after_stat reads n and prop, and naming another is refused, listing those" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert [%Plot.Layer{mapping: %{size: {:after_stat, ["prop"]}}}] =
               Plot.geom_count(plot, %{size: {:after_stat, [:prop]}}).reversed_layers

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_count(plot, %{size: {:after_stat, [:count]}})
        end

      assert error.message =~ ~s(no variable "count")
      assert error.message =~ ~s("n", "prop")
    end

    test "an after_stat for the weight it consumes is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_count(plot, %{weight: {:after_stat, [:n]}})
        end

      assert error.message =~ "its stat consumes :weight as it computes"
    end
  end

  describe "geom_histogram/3 and stat_bin/3" do
    test "stat_bin/3 adds the layer geom_histogram/3 adds" do
      plot = Plot.new(@rows, %{x: :wt})

      assert Plot.stat_bin(plot, %{fill: :cyl}, binwidth: 1, position: :dodge).reversed_layers ==
               Plot.geom_histogram(plot, %{fill: :cyl}, binwidth: 1, position: :dodge).reversed_layers

      assert Plot.stat_bin(plot, bins: 5).reversed_layers ==
               Plot.geom_histogram(plot, bins: 5).reversed_layers

      assert Plot.stat_bin(plot).reversed_layers == Plot.geom_histogram(plot).reversed_layers
    end

    test "a binning layer records the bar geom, binning with its defaults and stacking" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.stat_bin(%{x: :wt, weight: :mpg})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Bar{just: 0.5},
                 stat: %Stat.Bin{
                   bins: 30,
                   binwidth: :none,
                   center: :none,
                   boundary: :none,
                   breaks: :none,
                   closed: :right,
                   pad: false,
                   drop: :none
                 },
                 position: %Position.Stack{},
                 data: :none,
                 mapping: %{x: "wt", weight: "mpg"},
                 fixed: %{},
                 accepted: [:group, :weight, :x, :y, :alpha, :color, :fill, :linetype, :linewidth],
                 annotation: false
               }
             ]
    end

    test "its options are recorded in binning's struct, numbers as floats" do
      plot =
        @rows
        |> Plot.new(%{x: :wt})
        |> Plot.stat_bin(
          bins: 5,
          binwidth: 2,
          center: 1,
          breaks: [0, 2.5, 5],
          closed: :left,
          pad: true,
          drop: :extremes,
          position: :dodge,
          fill: "white"
        )

      [layer] = plot.reversed_layers

      assert layer.stat === %Stat.Bin{
               bins: 5,
               binwidth: 2.0,
               center: 1.0,
               boundary: :none,
               breaks: [0.0, 2.5, 5.0],
               closed: :left,
               pad: true,
               drop: :extremes
             }

      assert {layer.position, layer.fixed} == {%Position.Dodge{}, %{fill: "#FFFFFF"}}
    end

    test "a boundary is recorded as a float" do
      plot =
        @rows
        |> Plot.new(%{x: :wt})
        |> Plot.stat_bin(boundary: 1)

      assert [%Plot.Layer{stat: %Stat.Bin{boundary: 1.0, center: :none}}] = plot.reversed_layers
    end

    test "a centre and a boundary together are refused, each placing every bin" do
      plot = Plot.new(@rows, %{x: :wt})

      for {add, function} <- [
            {&Plot.geom_histogram/2, "Plot.geom_histogram/3"},
            {&Plot.stat_bin/2, "Plot.stat_bin/3"}
          ] do
        error = assert_raise ArgumentError, fn -> add.(plot, center: 0, boundary: 0) end
        assert error.message =~ function
      end
    end

    test "a bin width not above 0 is refused" do
      plot = Plot.new(@rows, %{x: :wt})

      assert_raise NimbleOptions.ValidationError, fn -> Plot.stat_bin(plot, binwidth: 0) end
      assert_raise NimbleOptions.ValidationError, fn -> Plot.stat_bin(plot, binwidth: "1") end
    end

    test "breaks are refused unless two or more distinct numbers" do
      plot = Plot.new(@rows, %{x: :wt})

      for breaks <- [[1], [1, 1.0], [1, "2"], 3] do
        assert_raise NimbleOptions.ValidationError, fn -> Plot.stat_bin(plot, breaks: breaks) end
      end
    end

    test "x and y together, or neither, are refused, binning along one, naming the function" do
      both = Plot.new(@rows, %{x: :wt, y: :mpg})
      neither = Plot.new(@rows)

      error = assert_raise ArgumentError, fn -> Plot.stat_bin(both) end
      assert error.message =~ "Plot.stat_bin/3"
      assert_raise ArgumentError, fn -> Plot.stat_bin(neither) end
    end

    test "a mapping the grammar refuses is refused, naming the function" do
      plot = Plot.new(@rows)

      error = assert_raise ArgumentError, fn -> Plot.stat_bin(plot, %{x: {1, 2, 3}}) end
      assert error.message =~ "Plot.stat_bin/3"
    end

    test "an after_stat for the weight it consumes is refused" do
      plot = Plot.new(@rows, %{x: :wt})

      error =
        assert_raise ArgumentError, fn ->
          Plot.stat_bin(plot, %{weight: {:after_stat, [:count]}})
        end

      assert error.message =~ "its stat consumes :weight as it computes"
    end

    test "a weight that is not numbers is refused at the call" do
      plot = Plot.new(@rows, %{x: :wt, weight: :cyl})

      error = assert_raise ArgumentError, fn -> Plot.stat_bin(plot) end
      assert error.message =~ "Plot.stat_bin/3"
    end
  end

  describe "geom_freqpoly/3" do
    test "a frequency polygon records the path geom, binning padded at each end and no position" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.geom_freqpoly(%{x: :wt, colour: :cyl, weight: :mpg})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Path{line_end: :butt, line_join: :round, mitre_limit: 10.0},
                 stat: %Stat.Bin{
                   bins: 30,
                   binwidth: :none,
                   center: :none,
                   boundary: :none,
                   breaks: :none,
                   closed: :right,
                   pad: true,
                   drop: :none
                 },
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{x: "wt", color: "cyl", weight: "mpg"},
                 fixed: %{},
                 accepted: [:group, :weight, :x, :y, :alpha, :color, :linetype, :linewidth],
                 annotation: false
               }
             ]
    end

    test "with neither a mapping nor options, it bins the plot's mapping, padded" do
      plot =
        @rows
        |> Plot.new(%{x: :wt})
        |> Plot.geom_freqpoly()

      assert [%Plot.Layer{geom: %Geom.Path{}, stat: %Stat.Bin{pad: true}, mapping: mapping}] =
               plot.reversed_layers

      assert mapping == %{}
    end

    test "its binning options go to binning's struct, a line's to the path and its look" do
      plot =
        @rows
        |> Plot.new(%{x: :wt})
        |> Plot.geom_freqpoly(
          bins: 5,
          binwidth: 2,
          boundary: 1,
          breaks: [0, 2.5, 5],
          closed: :left,
          drop: :all,
          lineend: :round,
          linejoin: :mitre,
          linemitre: 2,
          colour: "red",
          linewidth: 2,
          linetype: :dashed,
          alpha: 0.5
        )

      [layer] = plot.reversed_layers

      assert layer.stat === %Stat.Bin{
               bins: 5,
               binwidth: 2.0,
               center: :none,
               boundary: 1.0,
               breaks: [0.0, 2.5, 5.0],
               closed: :left,
               pad: true,
               drop: :all
             }

      assert layer.geom === %Geom.Path{line_end: :round, line_join: :mitre, mitre_limit: 2.0}

      assert layer.fixed === %{
               color: "#FF0000",
               linewidth: 2.0,
               linetype: {4, 4},
               alpha: 0.5
             }
    end

    # ggplot2 4.0.3's `geom_freqpoly()` sets `pad = TRUE` after reading its arguments, so a
    # polygon is padded whatever `pad` says.
    test "pad:, position: and fill: are refused, a polygon being padded, unplaced and unfilled" do
      plot = Plot.new(@rows, %{x: :wt})

      for option <- [pad: false, position: :stack, fill: "red"] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Plot.geom_freqpoly(plot, [option]) end

        assert error.message =~ "unknown options [#{inspect(elem(option, 0))}]"
      end
    end

    test "a mapped fill is refused, which a line has none of" do
      plot = Plot.new(@rows, %{x: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_freqpoly(plot, %{fill: :cyl}) end
      assert error.message =~ "Plot.geom_freqpoly/3 cannot use :fill"
    end

    test "binning's refusals name the function" do
      plot = Plot.new(@rows, %{x: :wt})

      for add <- [
            fn -> Plot.geom_freqpoly(plot, center: 0, boundary: 0) end,
            fn -> Plot.geom_freqpoly(plot, %{x: :disp}) end,
            fn -> Plot.geom_freqpoly(plot, %{y: :mpg}) end,
            fn -> Plot.geom_freqpoly(plot, %{weight: :cyl}) end,
            fn -> Plot.geom_freqpoly(plot, %{weight: {:after_stat, [:count]}}) end
          ] do
        error = assert_raise ArgumentError, add
        assert error.message =~ "Plot.geom_freqpoly/3"
      end
    end
  end

  describe "orientation: of a counting or binning layer" do
    test "one naming the axis mapped is taken and recorded nowhere, saying what the mapping says" do
      along_x = Plot.new(@rows, %{x: :wt})
      along_y = Plot.new(@rows, %{y: :wt})

      for add <- [
            &Plot.geom_bar/2,
            &Plot.geom_histogram/2,
            &Plot.stat_bin/2,
            &Plot.geom_freqpoly/2
          ] do
        assert add.(along_x, orientation: :x) == add.(along_x, [])
        assert add.(along_y, orientation: :y) == add.(along_y, [])
      end
    end

    # ggplot2 4.0.3 warns "Computation failed in `stat_bin()`" for `geom_histogram(aes(x),
    # orientation = "y")`, and draws the plot without the layer.
    test "one naming the other axis is refused, saying how to run along it" do
      along_x = Plot.new(@rows, %{x: :wt})

      for {add, function, verb} <- [
            {&Plot.geom_histogram/2, "Plot.geom_histogram/3", "bin"},
            {&Plot.stat_bin/2, "Plot.stat_bin/3", "bin"},
            {&Plot.geom_freqpoly/2, "Plot.geom_freqpoly/3", "bin"},
            {&Plot.geom_bar/2, "Plot.geom_bar/3", "count"}
          ] do
        error = assert_raise ArgumentError, fn -> add.(along_x, orientation: :y) end
        assert error.message =~ "#{function} #{verb}s along x here, because :x is mapped"
        assert error.message =~ "To #{verb} along y, map :y instead of :x"
      end
    end

    test "the axis is the one mapped before the stat, the layer's own or the plot's" do
      plot = Plot.new(@rows, %{y: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_histogram(plot, orientation: :x) end
      assert error.message =~ "Plot.geom_histogram/3 bins along y here"

      after_stat = Plot.new(@rows, %{y: {:after_stat, [:density]}})

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_freqpoly(after_stat, %{x: :wt}, orientation: :y)
        end

      assert error.message =~ "Plot.geom_freqpoly/3 bins along x here"
    end

    # ggplot2 4.0.3 reads any orientation but "y" as "x".
    test "an axis other than :x and :y is refused" do
      plot = Plot.new(@rows, %{x: :wt})

      assert_raise NimbleOptions.ValidationError, fn ->
        Plot.geom_histogram(plot, orientation: :z)
      end
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
                 accepted: [:alpha, :color, :group, :linetype, :linewidth, :x, :y],
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

      error = assert_raise ArgumentError, fn -> Plot.geom_path(plot, %{shape: :cyl}) end
      assert error.message =~ "Plot.geom_path/3"
      assert error.message =~ ":shape"
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

    # R 4.6.1 reads `lty = 0` to `6` as "blank" to "twodash", and a string of hex digits as its own
    # lengths: vdiffr 1.0.9 dashes each 0.5 mm line `5.69,5.69`, `1.42,4.27`, `1.42,4.27,5.69,4.27`,
    # `9.96,4.27` and `2.85,2.85,8.54,2.85`, each length 1.42 times these (test/golden/line_types.R).
    test "a line type is set for every line, held as its dash pattern, by name, number or pattern" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for add <- [&Plot.geom_path/2, &Plot.geom_line/2] do
        by_number =
          for number <- 0..6 do
            [layer] = add.(plot, linetype: number).reversed_layers
            layer.fixed.linetype
          end

        by_name =
          for name <- [:blank, :solid, :dashed, :dotted, :dotdash, :longdash, :twodash] do
            [layer] = add.(plot, linetype: name).reversed_layers
            layer.fixed.linetype
          end

        assert by_number === [:none, {}, {4, 4}, {1, 3}, {1, 3, 4, 3}, {7, 3}, {2, 2, 6, 2}]
        assert by_name === by_number

        for pattern <- [{3, 3, 1, 15, 2, 2, 1, 1}, {1, 2, 3, 4, 5, 6}] do
          assert [%Plot.Layer{fixed: %{linetype: ^pattern}}] =
                   add.(plot, linetype: pattern).reversed_layers
        end
      end
    end

    # R refuses a pattern of an odd number of digits or more than 8 ("invalid line type: must be
    # length 2, 4, 6 or 8"), a 0 ("zeroes are not allowed"), and a number below 0; it takes 7 and
    # up round again from solid, which Giggly refuses rather than draw a line type not asked for.
    test "a line type that is not a name, a number from 0 to 6 or a pattern of 2 to 8 is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for line_type <- [
            7,
            -1,
            2.0,
            :dashdot,
            "dashed",
            "44",
            [4, 4],
            {},
            {4},
            {1, 2, 3},
            {1, 2, 3, 4, 5},
            {0, 4},
            {16, 1},
            {4.0, 4},
            {1, 1, 1, 1, 1, 1, 1, 1, 1, 1}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_path(plot, linetype: line_type)
          end

        assert error.key == :linetype
        assert error.message =~ "got: #{inspect(line_type)}"
        assert error.message =~ ":blank, :solid, :dashed, :dotted, :dotdash, :longdash, :twodash"
        assert error.message =~ "0 to 6"
        assert error.message =~ "2, 4, 6 or 8 lengths from 1 to 15"
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
                 accepted: [
                   :alpha,
                   :color,
                   :fill,
                   :group,
                   :linetype,
                   :linewidth,
                   :xmax,
                   :xmin,
                   :ymax,
                   :ymin
                 ],
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
    test "a bar annotation's width is checked as each bar's, and its just: as geom_col/3's" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for {option, value} <- [width: [0.5, "wide"], just: 2] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.annotate(plot, :col, [{:x, [1, 2]}, {:y, [3, 4]}, {option, value}])
          end

        assert error.key == option
      end
    end

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
               %Geom.Bar{just: 0.5},
               %Geom.Bar{just: 0.5},
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

    # ggplot2 4.0.3's `annotate("point", x = 1:3, y = 1, shape = c(21, 15, NA), size = c(2, 4,
    # 6), stroke = c(0.5, NA, 2))` draws each point in its own shape, size and stroke, none for the
    # missing shape and no outline for the missing stroke.
    test "a point's shape, size and stroke each take a list, a :none held as missing" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.annotate(:point,
          x: [1, 2, 3],
          y: 1,
          shape: [21, :square, :none],
          size: [2, 4, 6],
          stroke: [0.5, :none, 2]
        )

      assert [%Plot.Layer{fixed: fixed}] = plot.reversed_layers

      assert fixed === %{
               shape: [:circle_filled, :square, nil],
               size: [2.0, 4.0, 6.0],
               stroke: [0.5, nil, 2.0]
             }
    end

    # ggplot2 4.0.3's `annotate("rect", xmin = c(1, 3), xmax = c(2, 4), ymin = 0, ymax = 1,
    # linetype = c(2, 3), linewidth = c(1, 2))` borders the first rectangle dashed and 1 mm wide,
    # the second dotted and 2 mm wide.
    test "a bar's or a rectangle's line type and width each take a list, a blank held as missing" do
      plot = Plot.new(@rows)

      for {geom, positions} <- [
            {:rect, [xmin: [1, 3, 5, 7], xmax: [2, 4, 6, 8], ymin: 0, ymax: 1]},
            {:col, [x: [1, 2, 3, 4], y: 1]},
            {:bar, [x: [1, 2, 3, 4], y: 1]}
          ] do
        annotated =
          Plot.annotate(
            plot,
            geom,
            positions ++ [linetype: [2, :dotted, {3, 1}, :blank], linewidth: [1, 2, 3, 0]]
          )

        assert [%Plot.Layer{fixed: fixed}] = annotated.reversed_layers

        assert fixed === %{
                 linetype: [{4, 4}, {1, 3}, {3, 1}, nil],
                 linewidth: [1.0, 2.0, 3.0, +0.0]
               }
      end
    end

    # ggplot2 4.0.3: `annotate("rect", xmin = 1, xmax = 2, ymin = 0, ymax = 1, linetype =
    # c("dashed", "dotted"))` draws two rectangles, and given three of each corner "Unequal
    # parameter lengths: xmin (3), xmax (3), and linetype (2)", and so for linewidth.
    test "a list of line types or widths counts annotations as a position's list does" do
      plot = Plot.new(@rows)
      corners = [xmin: 1, xmax: 2, ymin: 0, ymax: 1]

      for {option, values} <- [linetype: [2, 3], linewidth: [1, 2]] do
        frame =
          plot
          |> Plot.annotate(:rect, [{option, values} | corners])
          |> Giggly.layer_data()

        assert DataFrame.pull(frame, :xmin) === [1.0, 1.0]

        error =
          assert_raise ArgumentError, fn ->
            Plot.annotate(plot, :rect, [
              {:xmin, [1, 3, 5]},
              {:xmax, [2, 4, 6]},
              {:ymin, 0},
              {:ymax, 1},
              {option, values}
            ])
          end

        assert error.message =~ "#{inspect(option)} 2 values"
      end
    end

    test "a dash pattern given to an annotation is one line type, and a list of one too" do
      plot = Plot.new(@rows)

      for line_type <- [{4, 2}, [{4, 2}]] do
        annotated =
          Plot.annotate(plot, :rect,
            xmin: [1, 3],
            xmax: [2, 4],
            ymin: 0,
            ymax: 1,
            linetype: line_type
          )

        assert [%Plot.Layer{fixed: %{linetype: {4, 2}}}] = annotated.reversed_layers
      end
    end

    # ggplot2 4.0.3 aborts drawing a path whose line type changes along it ("can't have varying
    # colour, linewidth, and/or alpha along the line when linetype isn't solid"), and a path
    # annotation is one line; its width may change along it, drawn a segment at a time.
    test "a path's or a line's annotation takes one line type, not a list, and a list of widths" do
      plot = Plot.new(@rows)

      for geom <- [:path, :line] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.annotate(plot, geom, x: [1, 2], y: 1, linetype: [2, 3])
          end

        assert error.key == :linetype

        assert [%Plot.Layer{fixed: %{linewidth: [1.0, 2.0]}}] =
                 Plot.annotate(plot, geom, x: [1, 2], y: 1, linewidth: [1, 2]).reversed_layers
      end

      assert [%Plot.Layer{fixed: %{linetype: {7, 3}, linewidth: 2.0}}] =
               Plot.annotate(plot, :path, x: [1, 2], y: 1, linetype: :longdash, linewidth: 2).reversed_layers
    end

    # ggplot2 4.0.3: "Unequal parameter lengths: x (2) and shape (3)", and so for size and stroke.
    test "a point's shape, size or stroke given another number of values is refused, naming it" do
      plot = Plot.new(@rows)

      for {aesthetic, values} <- [shape: [21, 22, 23], size: [1, 2, 3], stroke: [1, 2, 3]] do
        error =
          assert_raise ArgumentError, fn ->
            Plot.annotate(plot, :point, [{:x, [1, 2]}, {:y, 1}, {aesthetic, values}])
          end

        assert error.message =~ ":x 2 values and #{inspect(aesthetic)} 3 values"
      end
    end

    test "a list's values are of one type, as a column of the layer's table holds" do
      plot = Plot.new(@rows)

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

  describe "scale_x_discrete/2 and scale_y_discrete/2" do
    test "a discrete scale function records an untrained discrete scale with the options given" do
      labeller = fn values -> Enum.map(values, &to_string/1) end

      plot =
        @rows
        |> Plot.new(%{x: :cyl, y: :mpg})
        |> Plot.scale_x_discrete(
          name: "Cylinders",
          limits: ["8", nil, "4"],
          breaks: ["4"],
          labels: labeller,
          expand: [add: 2]
        )
        |> Plot.scale_y_discrete(labels: %{4 => "four", nil => "none"})

      unmarked =
        @rows
        |> Plot.new(%{x: :cyl, y: :mpg})
        |> Plot.scale_x_discrete(breaks: :none, labels: :none)

      assert {plot.scales, unmarked.scales} === {
               %{
                 x: %Scale.Discrete{
                   name: "Cylinders",
                   limits: ["8", nil, "4"],
                   breaks: ["4"],
                   labels: labeller,
                   expand: [mult: {0.0, 0.0}, add: {2.0, 2.0}]
                 },
                 y: %Scale.Discrete{labels: %{4 => "four", nil => "none"}}
               },
               %{x: %Scale.Discrete{breaks: :none, labels: :none}}
             }
    end

    test "an option not given keeps a discrete position scale's default" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.scale_y_discrete()

      assert plot.scales.y === %Scale.Discrete{
               levels: [],
               continuous_range: :none,
               palette: :identity,
               na_value: nil,
               guide: :axis,
               name: :default,
               limits: :default,
               breaks: :default,
               labels: :default,
               expand: [mult: {0, 0}, add: {0.6, 0.6}]
             }
    end

    test "an option a discrete scale cannot take is refused, naming it and what was wrong with it" do
      plot = Plot.new(@rows)

      for {key, value, shown} <- [
            {:name, 5, "got: 5"},
            {:limits, [], "got: []"},
            {:limits, {"a", "b"}, ~s(got: {"a", "b"})},
            {:limits, ["a", ~D[2020-01-01]], ~s(got: ~D[2020-01-01] in ["a", ~D[2020-01-01]])},
            {:limits, ["a", "b", "a"], ~s(got: "a" more than once in ["a", "b", "a"])},
            {:limits, [4, 4.0], "got: 4.0 more than once"},
            {:breaks, "a", ~s(got: "a")},
            {:breaks, [{1, 2}], "got: {1, 2} in"},
            {:breaks, [nil, nil], "got: nil more than once"},
            {:labels, ["a", 1], "got: 1 in it"},
            {:labels, %{"a" => 1}, ~s(got: 1 in %{"a" => 1})},
            {:labels, %{["a"] => "b"}, ~s(got: ["a"] in)},
            {:labels, "a",
             ~s(a map from a value to its label, a function of one argument or :none, got: "a")},
            {:expand, [mult: "a"], ~s([mult: "a"])}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.scale_x_discrete(plot, [{key, value}])
          end

        assert {error.key, error.message =~ shown} == {key, true}
      end

      minor =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.scale_x_discrete(plot, minor_breaks: ["a"])
        end

      assert minor.key == [:minor_breaks]
    end

    # ggplot2 4.0.3 pads a list of labels short of the breaks with NA and drops one past them, or
    # with breaks given fails ("`breaks` and `labels` must have the same length"); a list is
    # refused at the call wherever the count of breaks is known there.
    test "a list of labels is one for each break given, or else for each limit given" do
      plot = Plot.new(@rows)

      assert_raise ArgumentError,
                   ~r/scale_x_discrete.* 1 labels.* each of its 2 breaks, \["4", "6"\]/,
                   fn ->
                     Plot.scale_x_discrete(plot, labels: ["a"], breaks: ["4", "6"], limits: ["4"])
                   end

      assert_raise ArgumentError, ~r/scale_y_discrete.* 3 labels.* each of its 2 limits/, fn ->
        Plot.scale_y_discrete(plot, labels: ["a", "b", "c"], limits: ["4", "6"])
      end

      assert Plot.scale_x_discrete(plot, labels: ["a", "b"], limits: ["4", "6"]).scales.x.labels ===
               ["a", "b"]

      assert Plot.scale_x_discrete(plot, labels: ["a"], breaks: :none, limits: ["4", "6"]).scales.x.labels ===
               ["a"]

      assert Plot.scale_x_discrete(plot, labels: ["a", "b", "c"]).scales.x.labels ===
               ["a", "b", "c"]
    end
  end

  # The reason Calendar.strftime/3 gives for refusing to write a date in `format`.
  defp strftime_refusal(format) do
    Calendar.strftime(~D[1970-01-01], format)
  rescue
    exception -> Exception.message(exception)
  end

  describe "scale_x_date/2 and scale_y_date/2" do
    test "a date scale function records an untrained date scale with the options given" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.scale_x_date(
          name: "Day",
          limits: {~D[2026-10-19], nil},
          breaks: [~D[2026-10-01]],
          labels: ["first"],
          minor_breaks: :none,
          expand: [mult: 0]
        )
        |> Plot.scale_y_date()

      assert plot.scales === %{
               x: %Scale.Continuous{
                 transform: :date,
                 name: "Day",
                 limits: {~D[2026-10-19], nil},
                 breaks: [~D[2026-10-01]],
                 labels: ["first"],
                 minor_breaks: :none,
                 expand: [mult: {0.0, 0.0}, add: {0.0, 0.0}]
               },
               y: %Scale.Continuous{transform: :date}
             }
    end

    test "a step records a width of breaks and a format the labels it writes" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.scale_x_date(date_breaks: [week: 2], date_minor_breaks: [day: 1])
        |> Plot.scale_y_date(date_labels: "%b %d", breaks: :none)

      yearly =
        @rows
        |> Plot.new()
        |> Plot.scale_x_date(date_breaks: [year: 10], date_minor_breaks: [month: 3])

      assert {plot.scales, yearly.scales.x} === {
               %{
                 x: %Scale.Continuous{
                   transform: :date,
                   breaks: {:width, [week: 2]},
                   minor_breaks: {:width, [day: 1]}
                 },
                 y: %Scale.Continuous{
                   transform: :date,
                   labels: {:format, "%b %d"},
                   breaks: :none
                 }
               },
               %Scale.Continuous{
                 transform: :date,
                 breaks: {:width, [year: 10]},
                 minor_breaks: {:width, [month: 3]}
               }
             }
    end

    # ggplot2 4.0.3 takes the `date_` option of the two and ignores the other; each is refused
    # beside its twin, naming both.
    test "an option given beside its date_ twin is refused" do
      plot = Plot.new(@rows)

      for {options, named} <- [
            {[breaks: [~D[2026-10-01]], date_breaks: [week: 1]], ":breaks and :date_breaks"},
            {[labels: :none, date_labels: "%d"], ":labels and :date_labels"},
            {[minor_breaks: :none, date_minor_breaks: [day: 1]],
             ":minor_breaks and :date_minor_breaks"}
          ] do
        error = assert_raise ArgumentError, fn -> Plot.scale_x_date(plot, options) end
        assert error.message =~ "Plot.scale_x_date/2 is given both #{named}"
      end

      assert_raise ArgumentError, ~r/scale_y_date.* 1 labels.* has none/, fn ->
        Plot.scale_y_date(plot, labels: ["a"], date_breaks: [month: 1])
      end
    end

    # Calendar.strftime/3 raises on a directive it lacks, such as R's %W, and on a time's for a
    # date, such as %H; either is refused at the call, passing on its own reason, which the test
    # takes from Calendar.strftime/3 rather than pinning its wording.
    test "an option a date scale cannot take is refused, naming it and what was wrong with it" do
      plot = Plot.new(@rows)

      for {key, value, shown} <- [
            {:limits, {~D[2026-10-01], 3}, "got: {~D[2026-10-01], 3}"},
            {:limits, {1, 3}, "each a date or nil"},
            {:breaks, [~D[2026-10-01], 3], "got: 3 in it"},
            {:breaks, ~D[2026-10-01], "got: ~D[2026-10-01]"},
            {:minor_breaks, [1.5], "got: 1.5 in it"},
            {:date_breaks, [weeks: 1], "got: [weeks: 1]"},
            {:date_breaks, [week: 0], "got: [week: 0]"},
            {:date_breaks, [week: 1.5], "got: [week: 1.5]"},
            {:date_breaks, [week: 1, day: 2], "got: [week: 1, day: 2]"},
            {:date_breaks, [hour: 1], "got: [hour: 1]"},
            {:date_breaks, "1 week", ~s(got: "1 week")},
            {:date_minor_breaks, [quarter: 1], "got: [quarter: 1]"},
            {:date_labels, "%W", ~s(got: "%W", which it cannot: #{strftime_refusal("%W")})},
            {:date_labels, "%H", ~s(got: "%H", which it cannot: #{strftime_refusal("%H")})},
            {:date_labels, :short, "got: :short"},
            {:labels, %{"a" => "b"}, ~s(got: %{"a" => "b"})}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.scale_x_date(plot, [{key, value}])
          end

        assert {error.key, error.message =~ shown} == {key, true}
      end

      transformed =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.scale_x_date(plot, transform: :log10)
        end

      assert transformed.key == [:transform]
    end
  end

  describe "xlim/2, ylim/2 and lims/2 of a discrete axis's values, and xlim/3 of dates" do
    test "a list of values gives a discrete scale those limits" do
      plot = Plot.new(@rows)

      assert Plot.xlim(plot, ["8", "4"]).scales === %{x: %Scale.Discrete{limits: ["8", "4"]}}
      assert Plot.ylim(plot, [nil, 4]).scales === %{y: %Scale.Discrete{limits: [nil, 4]}}

      assert Plot.lims(plot, x: [true, false], y: {1, 2}).scales === %{
               x: %Scale.Discrete{limits: [true, false]},
               y: %Scale.Continuous{limits: {1.0, 2.0}}
             }
    end

    # ggplot2 4.0.3's `limits()` reverses an axis given numbers high to low and never one given
    # dates, which its date scale sorts.
    test "two dates give a date scale those limits, in either order, a nil end left to the data" do
      plot = Plot.new(@rows)

      assert Plot.xlim(plot, ~D[2026-10-19], ~D[2026-10-01]).scales.x ===
               %Scale.Continuous{transform: :date, limits: {~D[2026-10-19], ~D[2026-10-01]}}

      assert Plot.ylim(plot, nil, ~D[2026-10-01]).scales.y ===
               %Scale.Continuous{transform: :date, limits: {nil, ~D[2026-10-01]}}

      assert Plot.lims(plot, x: {~D[2026-10-01], nil}).scales.x ===
               %Scale.Continuous{transform: :date, limits: {~D[2026-10-01], nil}}

      assert Plot.xlim(plot, nil, nil).scales.x === %Scale.Continuous{}
    end

    # R's `xlim("I1", "IF")` takes any number of values as separate arguments; Elixir has no
    # such call, so a discrete axis's limits are one list, and two strings are refused naming it.
    test "two strings, a date beside a number, or no values are refused" do
      plot = Plot.new(@rows)

      for {limit, shown} <- [
            {fn -> Plot.xlim(plot, "I1", "IF") end,
             ~s(or a list of a discrete axis's values, got: {"I1", "IF"})},
            {fn -> Plot.ylim(plot, ~D[2026-10-01], 4) end, "each a date or nil"},
            {fn -> Plot.xlim(plot, []) end, "at least one value"},
            {fn -> Plot.lims(plot, y: ["a", "a"]) end, ~s(got: "a" more than once)}
          ] do
        error = assert_raise NimbleOptions.ValidationError, limit
        assert error.message =~ shown
      end
    end
  end

  # Golden: the defaults of ggplot2 4.0.3's colour, fill and alpha scale functions, read with
  # `args()` in R 4.6.1: pal_hue()'s hues from 15 to 375, chroma 100, luminance 65; pal_grey()'s
  # 0.2 to 0.8, its missing value red; the gradient from #132B43 to #56B1F7; gradient2's
  # muted("red"), #832424, white and muted("blue"), #3A3A98, about 0; alpha's 0.1 to 1; every
  # other missing colour grey50.
  describe "the colour, fill and alpha scale functions" do
    test "each records an untrained scale of its palette, its guide and its missing value" do
      plot = Plot.new(@rows)

      recorded = fn color_function, fill_function ->
        {color_function.(plot).scales.color, fill_function.(plot).scales.fill}
      end

      hue = {:hue, %{hue: {15.0, 375.0}, chroma: 100.0, luminance: 65.0, direction: 1}}
      hued = %Scale.Discrete{palette: hue, guide: :legend, na_value: "#7F7F7F"}
      gray = %Scale.Discrete{palette: {:gray, {0.2, 0.8}}, guide: :legend, na_value: "#FF0000"}

      gradient = %Scale.Continuous{
        palette: {:gradient, ["#132B43", "#56B1F7"]},
        guide: :colorbar,
        na_value: "#7F7F7F"
      }

      diverging = %{
        gradient
        | palette: {:gradient, ["#832424", "#FFFFFF", "#3A3A98"]},
          rescaler: {:mid, 0.0}
      }

      assert recorded.(&Plot.scale_color_hue/1, &Plot.scale_fill_hue/1) === {hued, hued}
      assert recorded.(&Plot.scale_color_gray/1, &Plot.scale_fill_gray/1) === {gray, gray}

      assert recorded.(&Plot.scale_color_gradient/1, &Plot.scale_fill_gradient/1) ===
               {gradient, gradient}

      assert recorded.(&Plot.scale_color_gradient2/1, &Plot.scale_fill_gradient2/1) ===
               {diverging, diverging}
    end

    test "a discrete or continuous scale given no palette records its aesthetic's default scale" do
      plot = Plot.new(@rows)

      assert {Plot.scale_color_discrete(plot).scales.color,
              Plot.scale_fill_discrete(plot).scales.fill,
              Plot.scale_color_continuous(plot).scales.color,
              Plot.scale_fill_continuous(plot).scales.fill,
              Plot.scale_alpha_discrete(plot).scales.alpha,
              Plot.scale_alpha_continuous(plot).scales.alpha,
              Plot.scale_size_discrete(plot).scales.size,
              Plot.scale_size_continuous(plot).scales.size,
              Plot.scale_shape_discrete(plot).scales.shape,
              Plot.scale_linetype_discrete(plot).scales.linetype,
              Plot.scale_linewidth_discrete(plot).scales.linewidth,
              Plot.scale_linewidth_continuous(plot).scales.linewidth} ===
               {Scale.new(:discrete, :color), Scale.new(:discrete, :fill),
                Scale.new(:continuous, :color), Scale.new(:continuous, :fill),
                Scale.new(:discrete, :alpha), Scale.new(:continuous, :alpha),
                Scale.new(:discrete, :size), Scale.new(:continuous, :size),
                Scale.new(:discrete, :shape), Scale.new(:discrete, :linetype),
                Scale.new(:discrete, :linewidth), Scale.new(:continuous, :linewidth)}
    end

    test "a manual or gradientn scale given no colours is refused, naming the option it needs" do
      plot = Plot.new(@rows)

      for {call, option} <- [
            {fn -> Plot.scale_color_manual(plot) end, ":values"},
            {fn -> Plot.scale_fill_manual(plot) end, ":values"},
            {fn -> Plot.scale_color_gradientn(plot) end, ":colors"},
            {fn -> Plot.scale_fill_gradientn(plot) end, ":colors"}
          ] do
        error = assert_raise NimbleOptions.ValidationError, call
        assert error.message =~ "required #{option} option not found"
      end
    end

    test "each records the colours and options it is given" do
      labeller = fn values -> Enum.map(values, &to_string/1) end

      plot =
        @rows
        |> Plot.new()
        |> Plot.scale_color_manual(
          values: %{"6" => "red", "4" => :none},
          name: "Cylinders",
          limits: ["4", "6"],
          breaks: ["6"],
          labels: labeller,
          na_value: "black"
        )
        |> Plot.scale_fill_gradientn(
          colors: ["white", "steelblue"],
          limits: {nil, 30},
          breaks: [10, 20],
          labels: ["ten", "twenty"],
          na_value: :none
        )
        |> Plot.scale_alpha_continuous(range: {0, 1}, na_value: 0.5)

      assert plot.scales === %{
               color: %Scale.Discrete{
                 palette: {:manual, %{"6" => "#FF0000", "4" => :none}},
                 guide: :legend,
                 na_value: "#000000",
                 name: "Cylinders",
                 limits: ["4", "6"],
                 breaks: ["6"],
                 labels: labeller
               },
               fill: %Scale.Continuous{
                 palette: {:gradient, ["#FFFFFF", "#4682B4"]},
                 guide: :colorbar,
                 na_value: :none,
                 limits: {nil, 30.0},
                 breaks: [10.0, 20.0],
                 labels: ["ten", "twenty"]
               },
               alpha: %Scale.Continuous{
                 palette: {:rescale, {0.0, 1.0}},
                 guide: :legend,
                 na_value: 0.5
               }
             }
    end

    test "a palette, hues, greys and a midpoint are recorded as given, as floats" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.scale_color_hue(hue: {0, 90}, chroma: 30, luminance: 40, direction: -1)
        |> Plot.scale_fill_gray(start: 0, end: 1)

      palettes = fn other -> {other.scales.color.palette, other.scales.fill.palette} end

      assert palettes.(plot) ===
               {{:hue, %{hue: {0.0, 90.0}, chroma: 30.0, luminance: 40.0, direction: -1}},
                {:gray, {0.0, 1.0}}}

      assert {Plot.scale_color_discrete(plot, palette: ["red", "#0000FF80"]).scales.color.palette,
              Plot.scale_color_continuous(plot, palette: ["red", "blue"]).scales.color.palette,
              Plot.scale_fill_gradient2(plot, midpoint: 4).scales.fill.rescaler} ===
               {{:manual, ["#FF0000", "#0000FF80"]}, {:gradient, ["#FF0000", "#0000FF"]},
                {:mid, 4.0}}
    end

    # ggplot2 4.0.3's `manual_scale()` names an unnamed vector of values by a vector of breaks,
    # the first value the first break's, after it has chosen the scale's limits, so they stay its
    # levels; a map's names, the user's, limit it.
    test "a manual scale's list beside a list of breaks is recorded with them, to be named by them" do
      plot = Plot.new(@rows)
      palette = fn options -> Plot.scale_color_manual(plot, options).scales.color.palette end

      assert {palette.(values: ["red", "blue", "green"], breaks: [8, 4]),
              palette.(values: %{8 => "red"}, breaks: [8, 4]),
              palette.(values: ["red", "blue"], breaks: :none)} ===
               {{:manual, ["#FF0000", "#0000FF", "#008000"], [8, 4]},
                {:manual, %{8 => "#FF0000"}}, {:manual, ["#FF0000", "#0000FF"]}}
    end

    test "an option a colour, fill or alpha scale cannot take is refused, naming what was wrong" do
      plot = Plot.new(@rows)

      for {function, options, shown} <- [
            {&Plot.scale_color_manual/2, [values: []], "at least one colour"},
            {&Plot.scale_color_manual/2, [values: ~D[2020-01-01]],
             "or a map from a value to its colour, got: ~D[2020-01-01]"},
            {&Plot.scale_color_manual/2, [values: %{}], "or a map from a value to its colour"},
            {&Plot.scale_color_manual/2, [values: ["grey50"]], ~s(got: "grey50")},
            {&Plot.scale_fill_manual/2, [values: %{4 => "red", 4.0 => "blue"}], "more than once"},
            {&Plot.scale_fill_manual/2, [values: %{4 => "grey50"}], ~s(got: "grey50")},
            {&Plot.scale_color_hue/2, [hue: 5], "expected {first, last}, two numbers, got: 5"},
            {&Plot.scale_color_hue/2, [hue: {"a", 90}], ~s(two numbers, got: {"a", 90})},
            {&Plot.scale_fill_hue/2, [hue: {0, "b"}], ~s(two numbers, got: {0, "b"})},
            {&Plot.scale_color_hue/2, [chroma: "a"], ~s(expected a number, got: "a")},
            {&Plot.scale_fill_hue/2, [direction: 0], "expected one of [1, -1], got: 0"},
            {&Plot.scale_color_hue/2, [expand: [add: 1]], "unknown options [:expand]"},
            {&Plot.scale_color_gray/2, [start: 2], "from 0, black, to 1, white, got: 2"},
            {&Plot.scale_fill_gray/2, [end: -0.1], "got: -0.1"},
            {&Plot.scale_color_discrete/2, [palette: []], "at least one colour, got: []"},
            {&Plot.scale_color_gradient/2, [low: "#FF000080"],
             ~s(no alpha of its own, since a gradient blends colours alone, got: "#FF000080")},
            {&Plot.scale_color_gradient/2, [high: "grey50"], ~s(got: "grey50")},
            {&Plot.scale_fill_gradient2/2, [mid: :none], "no alpha of its own"},
            {&Plot.scale_color_gradient2/2, [midpoint: "a"], ~s(expected a number, got: "a")},
            {&Plot.scale_fill_gradientn/2, [colors: "red"], ~s(got: "red")},
            {&Plot.scale_color_continuous/2, [palette: ["red", "#FF000080"]], "no alpha"},
            {&Plot.scale_color_continuous/2, [limits: [1, 2]], "got: [1, 2]"},
            {&Plot.scale_color_continuous/2, [na_value: "grey50"], ~s(got: "grey50")},
            {&Plot.scale_alpha_continuous/2, [range: {0, 2}], "each an opacity from 0 to 1"},
            {&Plot.scale_alpha_continuous/2, [range: 1], "got: 1"},
            {&Plot.scale_alpha_discrete/2, [na_value: 2], "got: 2"}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> function.(plot, options) end
        assert error.message =~ shown
      end
    end

    test "labels not one for each break or limit, or without breaks, are refused at the call" do
      plot = Plot.new(@rows)

      assert_raise ArgumentError,
                   ~r/scale_fill_hue\/2 is given 1 labels, which must be one for each of its 2 breaks/,
                   fn -> Plot.scale_fill_hue(plot, breaks: ["4", "6"], labels: ["four"]) end

      assert_raise ArgumentError,
                   ~r/scale_color_gradient\/2 is given 2 labels, which need breaks/,
                   fn -> Plot.scale_color_gradient(plot, labels: ["a", "b"]) end
    end

    test "lims/2 gives a colour, fill or alpha scale its limits, as its scale functions do" do
      plot = Plot.new(@rows)

      assert Plot.lims(plot, colour: [4, 6, 8], fill: {0, 10}, alpha: {nil, 1}).scales === %{
               color: Plot.scale_color_discrete(plot, limits: [4, 6, 8]).scales.color,
               fill: Plot.scale_fill_continuous(plot, limits: {0, 10}).scales.fill,
               alpha: Plot.scale_alpha_continuous(plot, limits: {nil, 1}).scales.alpha
             }

      assert Plot.lims(plot, alpha: ["a", "b"]).scales.alpha ===
               Plot.scale_alpha_discrete(plot, limits: ["a", "b"]).scales.alpha
    end

    # ggplot2 4.0.3's `limits()` reverses a scale only for limits strictly high to low, so
    # `lims(colour = c(5, 5))` keeps the identity.
    test "lims/2 takes a colour scale's limits of one value, which run neither way" do
      plot = Plot.new(@rows)

      assert Plot.lims(plot, color: {5, 5}).scales.color ===
               Plot.scale_color_continuous(plot, limits: {5, 5}).scales.color
    end

    test "a list of labels the wrong length is refused naming the function that was given it" do
      plot = Plot.new(@rows)
      discrete = [breaks: ["4", "6"], labels: ["four"]]
      continuous = [labels: ["a"]]

      for {function, name, options} <- [
            {&Plot.scale_color_manual/2, "scale_color_manual", [values: ["red"]] ++ discrete},
            {&Plot.scale_fill_manual/2, "scale_fill_manual", [values: ["red"]] ++ discrete},
            {&Plot.scale_color_hue/2, "scale_color_hue", discrete},
            {&Plot.scale_fill_hue/2, "scale_fill_hue", discrete},
            {&Plot.scale_color_gray/2, "scale_color_gray", discrete},
            {&Plot.scale_fill_gray/2, "scale_fill_gray", discrete},
            {&Plot.scale_color_discrete/2, "scale_color_discrete", discrete},
            {&Plot.scale_fill_discrete/2, "scale_fill_discrete", discrete},
            {&Plot.scale_alpha_discrete/2, "scale_alpha_discrete", discrete},
            {&Plot.scale_color_gradient/2, "scale_color_gradient", continuous},
            {&Plot.scale_fill_gradient/2, "scale_fill_gradient", continuous},
            {&Plot.scale_color_gradient2/2, "scale_color_gradient2", continuous},
            {&Plot.scale_fill_gradient2/2, "scale_fill_gradient2", continuous},
            {&Plot.scale_color_gradientn/2, "scale_color_gradientn",
             [colors: ["red"]] ++ continuous},
            {&Plot.scale_fill_gradientn/2, "scale_fill_gradientn",
             [colors: ["red"]] ++ continuous},
            {&Plot.scale_color_continuous/2, "scale_color_continuous", continuous},
            {&Plot.scale_fill_continuous/2, "scale_fill_continuous", continuous},
            {&Plot.scale_alpha_continuous/2, "scale_alpha_continuous", continuous},
            {&Plot.scale_size_continuous/2, "scale_size_continuous", continuous},
            {&Plot.scale_size_area/2, "scale_size_area", continuous},
            {&Plot.scale_radius/2, "scale_radius", continuous},
            {&Plot.scale_size_discrete/2, "scale_size_discrete", discrete}
          ] do
        error = assert_raise ArgumentError, fn -> function.(plot, options) end
        assert error.message =~ "Plot.#{name}/2 is given 1 labels"
      end
    end

    # ggplot2 4.0.3's `lims(colour = c(10, 1))` reverses the colours through a reverse
    # transformation, which Giggly's colour, fill and alpha scales do not have yet.
    test "lims/2 refuses a colour, fill or alpha scale's limits high to low, or dates" do
      plot = Plot.new(@rows)

      for {options, shown} <- [
            {[color: {10, 1}],
             "low first, since a colour, fill, alpha, size or line width scale cannot run " <>
               "from high to low, got: {10, 1}"},
            {[fill: {~D[2026-01-01], nil}], "two numbers, each nil"},
            {[alpha: "a"], ~s(got: "a")}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> Plot.lims(plot, options) end
        assert error.message =~ shown
      end
    end
  end

  # Golden: the defaults of ggplot2 4.0.3's size scale functions, read with `args()` and run in R
  # 4.6.1: `scale_size_continuous()`'s `pal_area()` from 1 to 6, `scale_size_area()`'s 6 through
  # `rescale_max()`, `scale_radius()`'s 1 to 6, and the discrete scale's `sqrt(seq(4, 36))`, each a
  # legend; `scale_size_continuous(na.value = 1)` and `scale_radius(na.value = 1)` fail, "unused
  # argument".
  describe "the size scale functions" do
    test "each records an untrained scale of its palette and a legend, its missing value none" do
      plot = Plot.new(@rows)

      assert {Plot.scale_size_continuous(plot).scales.size,
              Plot.scale_size_area(plot).scales.size, Plot.scale_radius(plot).scales.size,
              Plot.scale_size_discrete(plot).scales.size} ===
               {%Scale.Continuous{palette: {:area, {1.0, 6.0}}, guide: :legend},
                %Scale.Continuous{palette: {:abs_area, 6.0}, rescaler: :max, guide: :legend},
                %Scale.Continuous{palette: {:rescale, {1.0, 6.0}}, guide: :legend},
                %Scale.Discrete{palette: {:area_sequence, {2.0, 6.0}}, guide: :legend}}
    end

    test "each records the sizes and options it is given, as floats" do
      plot = Plot.new(@rows)

      assert {Plot.scale_size_continuous(plot,
                range: {0, 10},
                name: "Power",
                limits: {nil, 400},
                breaks: [100, 200],
                labels: ["a", "b"]
              ).scales.size, Plot.scale_size_area(plot, max_size: 10, na_value: 1).scales.size,
              Plot.scale_radius(plot, range: {2, 8}).scales.size.palette,
              Plot.scale_size_discrete(plot, range: {1, 3}, na_value: 0, limits: ["4", "6"]).scales.size} ===
               {%Scale.Continuous{
                  palette: {:area, {0.0, 10.0}},
                  guide: :legend,
                  name: "Power",
                  limits: {nil, 400.0},
                  breaks: [100.0, 200.0],
                  labels: ["a", "b"]
                },
                %Scale.Continuous{
                  palette: {:abs_area, 10.0},
                  rescaler: :max,
                  guide: :legend,
                  na_value: 1.0
                }, {:rescale, {2.0, 8.0}},
                %Scale.Discrete{
                  palette: {:area_sequence, {1.0, 3.0}},
                  guide: :legend,
                  na_value: 0.0,
                  limits: ["4", "6"]
                }}
    end

    test "an option a size scale cannot take is refused, naming what was wrong" do
      plot = Plot.new(@rows)

      for {function, options, shown} <- [
            {&Plot.scale_size_continuous/2, [range: {-1, 6}],
             "each a size in millimetres, 0 or more, got: {-1, 6}"},
            {&Plot.scale_radius/2, [range: 6], "got: 6"},
            {&Plot.scale_size_discrete/2, [range: {1, "a"}], ~s(got: {1, "a"})},
            {&Plot.scale_size_area/2, [max_size: -1], "0 or more, got: -1"},
            {&Plot.scale_size_area/2, [na_value: "a"], ~s(got: "a")},
            {&Plot.scale_size_discrete/2, [na_value: -1], "got: -1"},
            {&Plot.scale_size_continuous/2, [na_value: 1], "unknown options [:na_value]"},
            {&Plot.scale_radius/2, [na_value: 1], "unknown options [:na_value]"},
            {&Plot.scale_size_area/2, [range: {1, 6}], "unknown options [:range]"},
            {&Plot.scale_size_continuous/2, [transform: :log10], "unknown options [:transform]"}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> function.(plot, options) end
        assert error.message =~ shown
      end
    end

    # ggplot2 4.0.3's `lims(size = c(20, 0))` reverses the sizes through a reverse transformation,
    # which Giggly's size scales do not have.
    test "lims/2 gives a size scale its limits, low first, as its scale functions do" do
      plot = Plot.new(@rows)

      assert {Plot.lims(plot, size: {0, 400}).scales.size,
              Plot.lims(plot, size: ["8", "4"]).scales.size} ===
               {Plot.scale_size_continuous(plot, limits: {0, 400}).scales.size,
                Plot.scale_size_discrete(plot, limits: ["8", "4"]).scales.size}

      error = assert_raise NimbleOptions.ValidationError, fn -> Plot.lims(plot, size: {20, 0}) end
      assert error.message =~ "since a colour, fill, alpha, size or line width scale cannot run"
    end

    test "labs/2 titles the size legend" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.labs(size: "Power")

      assert plot.labels === %{size: "Power"}
    end
  end

  describe "the shape scale functions" do
    test "each records an untrained discrete scale of its palette and a legend, its missing value none" do
      plot = Plot.new(@rows)

      assert {Plot.scale_shape_discrete(plot).scales.shape,
              Plot.scale_shape_discrete(plot, solid: false).scales.shape,
              Plot.scale_shape_manual(plot, values: [1, :triangle, :none]).scales.shape} ===
               {%Scale.Discrete{palette: {:shape, :solid}, guide: :legend},
                %Scale.Discrete{palette: {:shape, :open}, guide: :legend},
                %Scale.Discrete{
                  palette: {:manual, [:circle_open, :triangle, :none]},
                  guide: :legend
                }}
    end

    test "each records the shapes and options it is given, a shape by name or number held as its name" do
      plot = Plot.new(@rows)

      assert {Plot.scale_shape_discrete(plot,
                name: "Cylinders",
                limits: ["8", "4"],
                breaks: ["4"],
                labels: ["four"],
                na_value: 4
              ).scales.shape,
              Plot.scale_shape_manual(plot, values: %{"4" => 21, 6 => :star}, na_value: :none).scales.shape,
              Plot.scale_shape_manual(plot, values: [0, 25, 2], breaks: ["8", "4"]).scales.shape.palette} ===
               {%Scale.Discrete{
                  palette: {:shape, :solid},
                  guide: :legend,
                  name: "Cylinders",
                  limits: ["8", "4"],
                  breaks: ["4"],
                  labels: ["four"],
                  na_value: :cross
                },
                %Scale.Discrete{
                  palette: {:manual, %{"4" => :circle_filled, 6 => :star}},
                  guide: :legend,
                  na_value: :none
                }, {:manual, [:square_open, :triangle_down_filled, :triangle_open], ["8", "4"]}}
    end

    test "an option a shape scale cannot take is refused, naming what was wrong" do
      plot = Plot.new(@rows)

      for {function, options, shown} <- [
            {&Plot.scale_shape_discrete/2, [solid: :yes], "expected boolean, got: :yes"},
            {&Plot.scale_shape_discrete/2, [na_value: 26], "or :none, got: 26"},
            {&Plot.scale_shape_discrete/2, [values: [1]], "unknown options [:values]"},
            {&Plot.scale_shape_discrete/2, [range: {1, 6}], "unknown options [:range]"},
            {&Plot.scale_shape_manual/2, [values: [1, 26]], "or :none, got: 26"},
            {&Plot.scale_shape_manual/2, [values: %{"4" => "circle"}],
             ~s(or :none, got: "circle")},
            {&Plot.scale_shape_manual/2, [values: %{[1] => 1}], "got: [1] in [[1]]"},
            {&Plot.scale_shape_manual/2, [values: []],
             "expected a list of at least one shape, or a map from a value to its shape, got: []"},
            {&Plot.scale_shape_manual/2, [values: :circle], "got: :circle"},
            {&Plot.scale_shape_manual/2, [values: [1], solid: false], "unknown options [:solid]"}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> function.(plot, options) end
        assert error.message =~ shown
      end

      error = assert_raise NimbleOptions.ValidationError, fn -> Plot.scale_shape_manual(plot) end
      assert error.message =~ "required :values option not found"
    end

    test "a list of labels not one for each break or limit given is refused" do
      plot = Plot.new(@rows)

      for {function, name} <- [
            {&Plot.scale_shape_discrete/2, "Plot.scale_shape_discrete/2"},
            {fn shaped, options ->
               Plot.scale_shape_manual(shaped, [{:values, [1, 2]} | options])
             end, "Plot.scale_shape_manual/2"}
          ] do
        error =
          assert_raise ArgumentError, fn -> function.(plot, breaks: ["4", "6"], labels: ["a"]) end

        assert error.message =~
                 "#{name} is given 1 labels, which must be one for each of its 2 breaks"
      end
    end

    # ggplot2 4.0.3's `lims(shape = c(1, 5))` aborts: "A continuous variable cannot be mapped to
    # the shape aesthetic."
    test "lims/2 gives a shape scale its limits, a list alone, as scale_shape_discrete/2 does" do
      plot = Plot.new(@rows)

      assert Plot.lims(plot, shape: ["8", "4"]).scales.shape ===
               Plot.scale_shape_discrete(plot, limits: ["8", "4"]).scales.shape

      error = assert_raise NimbleOptions.ValidationError, fn -> Plot.lims(plot, shape: {1, 5}) end

      assert error.message =~
               "expected a list of the values the scale shows, since a shape scale is discrete, " <>
                 "got: {1, 5}"
    end

    test "labs/2 titles the shape legend" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.labs(shape: "Cylinders")

      assert plot.labels === %{shape: "Cylinders"}
    end
  end

  describe "the line type and line width scale functions" do
    test "each records an untrained scale of its palette and a legend, its missing value none" do
      plot = Plot.new(@rows)

      assert {Plot.scale_linetype_discrete(plot).scales.linetype,
              Plot.scale_linetype_manual(plot, values: [2, :blank, {3, 1}]).scales.linetype,
              Plot.scale_linewidth_continuous(plot).scales.linewidth,
              Plot.scale_linewidth_discrete(plot).scales.linewidth} ===
               {%Scale.Discrete{palette: :linetype, guide: :legend},
                %Scale.Discrete{palette: {:manual, [{4, 4}, :none, {3, 1}]}, guide: :legend},
                %Scale.Continuous{palette: {:rescale, {1.0, 6.0}}, guide: :legend},
                %Scale.Discrete{palette: {:sequence, {2.0, 6.0}}, guide: :legend}}
    end

    test "each records the line types, widths and options it is given, a line type as its pattern" do
      plot = Plot.new(@rows)

      assert {Plot.scale_linetype_discrete(plot,
                name: "Cylinders",
                limits: ["8", "4"],
                breaks: ["4"],
                labels: ["four"],
                na_value: :dotted
              ).scales.linetype,
              Plot.scale_linetype_manual(plot, values: %{"4" => 5, 6 => :solid}, na_value: :blank).scales.linetype,
              Plot.scale_linetype_manual(plot, values: [:twodash, {2, 1}], breaks: ["8", "4"]).scales.linetype.palette,
              Plot.scale_linewidth_continuous(plot,
                range: {0, 4},
                name: "Duration",
                limits: {nil, 20},
                breaks: [5, 10],
                labels: ["a", "b"]
              ).scales.linewidth,
              Plot.scale_linewidth_discrete(plot, range: {1, 3}, na_value: 0, limits: ["4", "6"]).scales.linewidth} ===
               {%Scale.Discrete{
                  palette: :linetype,
                  guide: :legend,
                  name: "Cylinders",
                  limits: ["8", "4"],
                  breaks: ["4"],
                  labels: ["four"],
                  na_value: {1, 3}
                },
                %Scale.Discrete{
                  palette: {:manual, %{"4" => {7, 3}, 6 => {}}},
                  guide: :legend,
                  na_value: :none
                }, {:manual, [{2, 2, 6, 2}, {2, 1}], ["8", "4"]},
                %Scale.Continuous{
                  palette: {:rescale, {0.0, 4.0}},
                  guide: :legend,
                  name: "Duration",
                  limits: {nil, 20.0},
                  breaks: [5.0, 10.0],
                  labels: ["a", "b"]
                },
                %Scale.Discrete{
                  palette: {:sequence, {1.0, 3.0}},
                  guide: :legend,
                  na_value: 0.0,
                  limits: ["4", "6"]
                }}
    end

    # ggplot2 4.0.3's `scale_linewidth_continuous(na.value = 3)` fails, "unused argument", and
    # its line type and line width scales take no transformation here, as size's take none.
    test "an option a line type or line width scale cannot take is refused, naming what was wrong" do
      plot = Plot.new(@rows)

      for {function, options, shown} <- [
            {&Plot.scale_linetype_discrete/2, [na_value: 7], "or a dash pattern"},
            {&Plot.scale_linetype_discrete/2, [na_value: {1, 16}], "got: {1, 16}"},
            {&Plot.scale_linetype_discrete/2, [values: [1]], "unknown options [:values]"},
            {&Plot.scale_linetype_manual/2, [values: [1, "22"]], ~s(got: "22")},
            {&Plot.scale_linetype_manual/2, [values: %{"4" => {1, 2, 3}}], "got: {1, 2, 3}"},
            {&Plot.scale_linetype_manual/2, [values: []],
             "expected a list of at least one line type, or a map from a value to its line " <>
               "type, got: []"},
            {&Plot.scale_linewidth_continuous/2, [range: {-1, 6}],
             "each a width in millimetres, 0 or more, got: {-1, 6}"},
            {&Plot.scale_linewidth_discrete/2, [range: 6], "got: 6"},
            {&Plot.scale_linewidth_discrete/2, [na_value: -1], "got: -1"},
            {&Plot.scale_linewidth_continuous/2, [na_value: 1], "unknown options [:na_value]"},
            {&Plot.scale_linewidth_continuous/2, [transform: :log10],
             "unknown options [:transform]"}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> function.(plot, options) end
        assert error.message =~ shown
      end

      error =
        assert_raise NimbleOptions.ValidationError, fn -> Plot.scale_linetype_manual(plot) end

      assert error.message =~ "required :values option not found"
    end

    test "a list of labels not one for each break or limit given is refused" do
      plot = Plot.new(@rows)

      for {function, name} <- [
            {&Plot.scale_linetype_discrete/2, "Plot.scale_linetype_discrete/2"},
            {fn typed, options ->
               Plot.scale_linetype_manual(typed, [{:values, [1, 2]} | options])
             end, "Plot.scale_linetype_manual/2"},
            {&Plot.scale_linewidth_discrete/2, "Plot.scale_linewidth_discrete/2"}
          ] do
        error =
          assert_raise ArgumentError, fn -> function.(plot, breaks: ["4", "6"], labels: ["a"]) end

        assert error.message =~
                 "#{name} is given 1 labels, which must be one for each of its 2 breaks"
      end

      error =
        assert_raise ArgumentError, fn ->
          Plot.scale_linewidth_continuous(plot, labels: ["a"])
        end

      assert error.message =~ "Plot.scale_linewidth_continuous/2 is given 1 labels"
    end

    # ggplot2 4.0.3's `lims(linetype = c(1, 5))` aborts: "A continuous variable cannot be mapped
    # to the linetype aesthetic", and its `lims(linewidth = c(10, 0))` reverses the widths through
    # a reverse transformation, which Giggly's line width scales do not have.
    test "lims/2 gives a line type scale a list of limits, and a line width scale either, low first" do
      plot = Plot.new(@rows)

      assert {Plot.lims(plot, linetype: ["8", "4"]).scales.linetype,
              Plot.lims(plot, linewidth: {0, 10}).scales.linewidth,
              Plot.lims(plot, linewidth: ["8", "4"]).scales.linewidth} ===
               {Plot.scale_linetype_discrete(plot, limits: ["8", "4"]).scales.linetype,
                Plot.scale_linewidth_continuous(plot, limits: {0, 10}).scales.linewidth,
                Plot.scale_linewidth_discrete(plot, limits: ["8", "4"]).scales.linewidth}

      for {options, shown} <- [
            {[linetype: {1, 5}],
             "expected a list of the values the scale shows, since a line type scale is " <>
               "discrete, got: {1, 5}"},
            {[linewidth: {10, 0}],
             "since a colour, fill, alpha, size or line width scale cannot run"}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> Plot.lims(plot, options) end
        assert error.message =~ shown
      end
    end

    test "labs/2 titles the line type and line width legends" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.labs(linetype: "Series", linewidth: "Duration of\nunemployment")

      assert plot.labels === %{linetype: "Series", linewidth: "Duration of\nunemployment"}
    end
  end

  describe "a scale's guide:, guide_legend/1 and guides/2" do
    # Each colour, fill and alpha scale function, with the options it needs, and whether its scale
    # is a continuous colour or fill scale, the one kind a colour bar shows.
    @guided_scale_functions [
      {&Plot.scale_color_manual/2, [values: ["red"]], :discrete},
      {&Plot.scale_fill_manual/2, [values: ["red"]], :discrete},
      {&Plot.scale_color_hue/2, [], :discrete},
      {&Plot.scale_fill_hue/2, [], :discrete},
      {&Plot.scale_color_gray/2, [], :discrete},
      {&Plot.scale_fill_gray/2, [], :discrete},
      {&Plot.scale_color_discrete/2, [], :discrete},
      {&Plot.scale_fill_discrete/2, [], :discrete},
      {&Plot.scale_alpha_discrete/2, [], :alpha},
      {&Plot.scale_color_gradient/2, [], :continuous},
      {&Plot.scale_fill_gradient/2, [], :continuous},
      {&Plot.scale_color_gradient2/2, [], :continuous},
      {&Plot.scale_fill_gradient2/2, [], :continuous},
      {&Plot.scale_color_gradientn/2, [colors: ["red"]], :continuous},
      {&Plot.scale_fill_gradientn/2, [colors: ["red"]], :continuous},
      {&Plot.scale_color_continuous/2, [], :continuous},
      {&Plot.scale_fill_continuous/2, [], :continuous},
      {&Plot.scale_alpha_continuous/2, [], :alpha},
      {&Plot.scale_size_continuous/2, [], :size},
      {&Plot.scale_size_area/2, [], :size},
      {&Plot.scale_radius/2, [], :size},
      {&Plot.scale_size_discrete/2, [], :size},
      {&Plot.scale_shape_discrete/2, [], :shape},
      {&Plot.scale_shape_manual/2, [values: [1]], :shape},
      {&Plot.scale_linetype_discrete/2, [], :linetype},
      {&Plot.scale_linetype_manual/2, [values: [1]], :linetype},
      {&Plot.scale_linewidth_continuous/2, [], :linewidth},
      {&Plot.scale_linewidth_discrete/2, [], :linewidth}
    ]

    # Each aesthetic other than colour and fill as a colour bar's refusal names it.
    @guided_nouns %{
      alpha: "alpha",
      shape: "shape",
      size: "size",
      linetype: "line type",
      linewidth: "line width"
    }

    test "each scale function records the guide it is given" do
      plot = Plot.new(@rows)
      reversed = Plot.guide_legend(reverse: true)

      for {function, options, kind} <- @guided_scale_functions,
          guide <- [:none, :legend, reversed | if(kind == :continuous, do: [:colorbar], else: [])] do
        [scale] = Map.values(function.(plot, [{:guide, guide} | options]).scales)
        assert scale.guide === guide
      end
    end

    # ggplot2 4.0.3 warns "`guide_colourbar()` needs continuous scales." for a discrete colour
    # scale, and "`guide_colourbar()` cannot be used for alpha." for either alpha scale, and for
    # shape, size, linetype and linewidth, and draws no guide.
    test "a colour bar is refused for a discrete scale, and for any aesthetic but colour, saying why" do
      plot = Plot.new(@rows)

      for {function, options, kind} <- @guided_scale_functions, kind != :continuous do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            function.(plot, [{:guide, :colorbar} | options])
          end

        assert error.message =~
                 if(kind == :discrete,
                   do: "a colour bar shows a continuous scale, and this one is discrete",
                   else:
                     "a colour bar shows colour or fill, never #{Map.fetch!(@guided_nouns, kind)}; " <>
                       "give :legend"
                 )
      end
    end

    test "a guide that is not one is refused, naming what a guide can be" do
      plot = Plot.new(@rows)

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.scale_color_hue(plot, guide: :legnd)
        end

      assert error.message =~
               "expected :legend, :colorbar, :none or a legend Plot.guide_legend/1 makes, " <>
                 "got: :legnd"
    end

    test "guide_legend/1 makes a legend, its keys reversed when asked" do
      assert {Plot.guide_legend(), Plot.guide_legend(reverse: true)} ===
               {%Guide.Legend{reverse: false}, %Guide.Legend{reverse: true}}

      for options <- [[reverse: 1], [order: 1]] do
        assert_raise NimbleOptions.ValidationError, fn -> Plot.guide_legend(options) end
      end
    end

    test "guides/2 records each guide by canonical name, and a later call replaces only what it sets" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.guides(colour: :none, fill: :legend)
        |> Plot.guides(fill: :colorbar, alpha: Plot.guide_legend(reverse: true))

      assert {Plot.new(@rows).guides, plot.guides} ===
               {%{}, %{color: :none, fill: :colorbar, alpha: %Guide.Legend{reverse: true}}}
    end

    test "guides/2 refuses a colour bar but for colour or fill, and an aesthetic it chooses no guide for" do
      plot = Plot.new(@rows)

      for {aesthetic, noun} <- @guided_nouns do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.guides(plot, [{aesthetic, :colorbar}])
          end

        assert error.message =~ "a colour bar shows colour or fill, never #{noun}"
      end

      assert Plot.guides(plot, size: :none, shape: :legend, linetype: :none, linewidth: :legend).guides ===
               %{size: :none, shape: :legend, linetype: :none, linewidth: :legend}

      for key <- [:x, :stroke] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Plot.guides(plot, [{key, :none}]) end

        assert error.key == [key]
      end
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

      for key <- [:stroke, :titel] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Plot.labs(plot, [{key, "A"}]) end

        assert error.key == [key]
      end
    end
  end
end
