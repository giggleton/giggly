defmodule Giggly.PlotTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, DataFrame, Facet, Geom, Guide, Plot, Position, Scale, Stat, Theme}

  doctest Giggly.Plot

  @rows %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]}

  describe "new/2" do
    test "a plot records the null facet, cartesian coordinates and the gray theme by default" do
      plot = Plot.new(@rows)

      assert {plot.facet, plot.coord, plot.theme} ==
               {%Facet.Null{}, %Coord.Cartesian{clip: :on}, %{complete: :none, settings: %{}}}
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

    # Golden: ggplot2 4.0.3 in R 4.6.1 fails to build `ggplot(mpg, aes(log10(class), hwy)) +
    # geom_point()`: "non-numeric argument to mathematical function".
    test "a function by name given a column that is not numbers is refused by the layer" do
      plot = Plot.new(@rows, %{x: :wt})

      own =
        assert_raise ArgumentError, fn -> Plot.geom_point(plot, %{y: {:log10, [:cyl]}}) end

      inherited =
        assert_raise ArgumentError, fn ->
          @rows
          |> Plot.new(%{x: :wt, y: {:log10, [:cyl]}})
          |> Plot.geom_point()
        end

      assert String.starts_with?(
               own.message,
               ~s(Plot.geom_point/3 maps :y to {:log10, ["cyl"]}, but )
             )

      assert String.starts_with?(
               inherited.message,
               ~s(Plot.geom_point/3 takes :y from the plot's mapping, which maps it to ) <>
                 ~s({:log10, ["cyl"]}, but )
             )

      assert {own.message =~ ":string column", inherited.message =~ ":string column"} ===
               {true, true}
    end

    test "a plot's function by name is checked against each layer's table, not at new/2" do
      plot = Plot.new(@rows, %{x: :wt, y: {:log10, [:cyl]}})
      own = %{"wt" => [3.0], "cyl" => [6]}

      assert [%Plot.Layer{}] = Plot.geom_point(plot, data: own).reversed_layers
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
                 annotation: false,
                 inherit: true
               }
             ]
    end

    test "a column the data does not have is refused by the layer that maps it" do
      plot = Plot.new(@rows, %{x: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot, %{y: :mgp}) end
      assert error.message =~ "Plot.geom_point/3"
    end

    test "points are jittered by name, with the defaults, or as told" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})
      told = Plot.position_jitter(width: 0.1, seed: 3)

      assert [%Plot.Layer{position: %Position.Jitter{width: :none, height: :none, seed: 0}}] =
               Plot.geom_point(plot, position: :jitter).reversed_layers

      assert [%Plot.Layer{position: ^told}] =
               Plot.geom_point(plot, position: told).reversed_layers
    end

    test "a position points do not take is refused by the option's validation, naming those they do" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for position <- [:stack, Plot.position_dodge2()] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_point(plot, position: position)
          end

        assert error.key == :position

        assert error.message =~
                 "expected :identity, :jitter or a position Plot.position_jitter/1 makes, got: "
      end
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
                 annotation: false,
                 inherit: true
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
                 position: %Position.Dodge{width: :none},
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
        assert error.message =~ inspect(value)
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
                 stat: %Stat.Count{width: :none},
                 position: %Position.Stack{},
                 data: :none,
                 mapping: %{x: "cyl", weight: "wt"},
                 fixed: %{},
                 accepted: [:group, :weight, :x, :y, :alpha, :color, :fill, :linetype, :linewidth],
                 annotation: false,
                 inherit: true
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

      assert [%Plot.Layer{position: %Position.Dodge{width: :none}, mapping: %{}, fixed: %{}}] =
               plot.reversed_layers
    end

    test "every bar function dodges by clusters by name, with the defaults, or as told" do
      plot = Plot.new(@rows, %{x: :wt})
      told = Plot.position_dodge2(preserve: :single, padding: 0, reverse: true)

      for add <- [&Plot.geom_bar/2, &Plot.geom_histogram/2, &Plot.stat_bin/2] do
        assert [%Plot.Layer{position: by_name}] = add.(plot, position: :dodge2).reversed_layers
        assert by_name == %Position.Dodge2{preserve: :total, padding: 0.1, reverse: false}
      end

      assert [%Plot.Layer{position: ^told}] =
               Plot.geom_col(plot, %{y: :mpg}, position: told).reversed_layers

      assert told == %Position.Dodge2{preserve: :single, padding: 0.0, reverse: true}
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

    test "a position bars do not take is refused by the option's validation, naming those they do" do
      plot = Plot.new(@rows, %{x: :cyl})

      for add <- [&Plot.geom_bar/2, &Plot.geom_col/2, &Plot.geom_histogram/2, &Plot.stat_bin/2],
          position <- [:jitter, Plot.position_jitter()] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> add.(plot, position: position) end

        assert error.key == :position

        assert error.message =~
                 ":stack, :dodge, :dodge2 or a position Plot.position_dodge/1 or " <>
                   "Plot.position_dodge2/1 makes"
      end
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

  describe "geom_jitter/3" do
    test "a jitter layer records the point geom, the identity stat and jittering" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.geom_jitter(%{x: :wt, y: :mpg}, colour: "red")

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Point{},
                 stat: %Stat.Identity{},
                 position: %Position.Jitter{width: :none, height: :none, seed: 0},
                 data: :none,
                 mapping: %{x: "wt", y: "mpg"},
                 fixed: %{color: "#FF0000"},
                 accepted: [:alpha, :color, :fill, :group, :shape, :size, :x, :y],
                 annotation: false,
                 inherit: true
               }
             ]
    end

    # ggplot2's `geom_jitter(width = 0.25)` is `position_jitter(width = 0.25)`, its height and seed
    # their defaults; neither is a size its points take, so neither is set on them, as R's
    # `layer_data()` of `geom_jitter(width = 0.2, height = 0.1)` holds no width or height.
    test "a width and a height say how far the points move, each kept as a float" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert [%Plot.Layer{position: %Position.Jitter{width: 1.0, height: :none, seed: 0}} = wide] =
               Plot.geom_jitter(plot, width: 1).reversed_layers

      assert [%Plot.Layer{position: %Position.Jitter{width: :none, height: +0.0}} = flat] =
               Plot.geom_jitter(plot, height: 0).reversed_layers

      assert {wide.fixed, flat.fixed} == {%{}, %{}}
    end

    test "a position says how the points move" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})
      told = Plot.position_jitter(height: 0.1, seed: -4)

      assert [%Plot.Layer{position: ^told}] =
               Plot.geom_jitter(plot, position: told).reversed_layers
    end

    # ggplot2's `geom_jitter()` aborts: "Both `position` and `width`/`height` were supplied."
    test "a position beside a width or a height is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for amounts <- [[width: 0.1], [height: 0.1], [width: 0.1, height: 0.1]] do
        error =
          assert_raise ArgumentError, fn ->
            Plot.geom_jitter(plot, [position: Plot.position_jitter()] ++ amounts)
          end

        assert error.message =~ "Plot.geom_jitter/3"
        assert error.message =~ "position: or width: and height:"
      end
    end

    # ggplot2's `geom_jitter()` takes no seed, which only its position takes.
    test "a negative distance, a position by name and a seed are refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for {options, key, message} <- [
            {[width: -0.1], :width, "expected a distance, a number 0 or more, got: -0.1"},
            {[height: "1"], :height, ~s(expected a distance, a number 0 or more, got: "1")},
            {[position: :jitter], :position,
             "expected a position Plot.position_jitter/1 makes, got: :jitter"},
            {[seed: 1], [:seed], "unknown options [:seed]"}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Plot.geom_jitter(plot, options) end

        assert error.key == key
        assert error.message =~ message
      end
    end

    test "a column the data does not have is refused by the layer that maps it" do
      plot = Plot.new(@rows, %{x: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_jitter(plot, %{y: :mgp}) end
      assert error.message =~ "Plot.geom_jitter/3"
    end

    test "an aesthetic points cannot use is refused by the layer that maps it" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_jitter(plot, %{label: :cyl}) end
      assert error.message =~ "Plot.geom_jitter/3"
      assert error.message =~ ":label"
    end
  end

  describe "geom_count/3 and stat_sum/3" do
    test "a count layer takes no position" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for add <- [&Plot.geom_count/2, &Plot.stat_sum/2] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> add.(plot, position: :jitter) end

        assert error.message =~ "unknown options [:position]"
      end
    end

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
                 annotation: false,
                 inherit: true
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
                 annotation: false,
                 inherit: true
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

      assert {layer.position, layer.fixed} == {%Position.Dodge{width: :none}, %{fill: "#FFFFFF"}}
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
                 geom: %Geom.Path{
                   line_end: :butt,
                   line_join: :round,
                   mitre_limit: 10.0,
                   arrow: :none
                 },
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
                 annotation: false,
                 inherit: true
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

      assert layer.geom === %Geom.Path{
               line_end: :round,
               line_join: :mitre,
               mitre_limit: 2.0,
               arrow: :none
             }

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

  describe "geom_boxplot/3" do
    test "a box plot layer records the box geom, the box plot's summary and dodging by clusters" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.geom_boxplot(%{x: :cyl, y: :mpg})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Boxplot{
                   outliers: true,
                   outlier: %{stroke: 0.5},
                   whisker: %{},
                   staple: %{},
                   median: %{},
                   box: %{},
                   notch: false,
                   notchwidth: 0.5,
                   staplewidth: 0.0,
                   varwidth: false
                 },
                 stat: %Stat.Boxplot{coef: 1.5, width: :none, orientation: :none},
                 position: %Position.Dodge2{preserve: :total, padding: 0.1, reverse: false},
                 data: :none,
                 mapping: %{x: "cyl", y: "mpg"},
                 fixed: %{},
                 accepted: [
                   :group,
                   :width,
                   :x,
                   :y,
                   :alpha,
                   :color,
                   :fill,
                   :linetype,
                   :linewidth,
                   :shape,
                   :size
                 ],
                 annotation: false,
                 inherit: true
               }
             ]
    end

    test "each part's look holds what is given, either spelling of a colour taken once" do
      plot =
        @rows
        |> Plot.new(%{x: :cyl, y: :mpg})
        |> Plot.geom_boxplot(
          outlier_colour: "red",
          outlier_shape: 21,
          outlier_stroke: :none,
          whisker_color: "blue",
          staple_linewidth: 2,
          median_linetype: :dotted,
          box_colour: :none,
          staplewidth: 1,
          notch: true,
          notchwidth: 0.25,
          varwidth: true,
          outliers: false
        )

      assert [%Plot.Layer{geom: geom}] = plot.reversed_layers

      assert geom == %Geom.Boxplot{
               outliers: false,
               outlier: %{color: "#FF0000", shape: :circle_filled, stroke: :none},
               whisker: %{color: "#0000FF"},
               staple: %{linewidth: 2.0},
               median: %{linetype: {1, 3}},
               box: %{color: :none},
               notch: true,
               notchwidth: 0.25,
               staplewidth: 1.0,
               varwidth: true
             }

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_boxplot(plot, whisker_colour: "red", whisker_color: "blue")
        end

      assert error.message =~ ":whisker_color is given twice"
    end

    test "the summary's options are its struct's, and what a box sets is fixed, width included" do
      plot =
        @rows
        |> Plot.new(%{x: :cyl, y: :mpg})
        |> Plot.geom_boxplot(
          coef: 3,
          width: 0.3,
          orientation: :x,
          fill: "white",
          size: 3,
          alpha: 0.4,
          linewidth: 2
        )

      assert [%Plot.Layer{stat: stat, fixed: fixed}] = plot.reversed_layers
      assert stat == %Stat.Boxplot{coef: 3.0, width: 0.3, orientation: :x}
      assert fixed === %{fill: "#FFFFFF", size: 3.0, width: 0.3, alpha: 0.4, linewidth: 2.0}
    end

    test "varwidth: dodges each box at its own width, whatever position is given" do
      plot = Plot.new(@rows, %{x: :cyl, y: :mpg})
      single = %Position.Dodge2{preserve: :single, padding: 0.1, reverse: false}

      for position <- [:dodge2, :dodge] do
        assert [%Plot.Layer{position: ^single}] =
                 Plot.geom_boxplot(plot, position: position, varwidth: true).reversed_layers
      end

      told = Plot.position_dodge2(padding: 0.3, reverse: true)

      assert [%Plot.Layer{position: kept}] =
               Plot.geom_boxplot(plot, position: told, varwidth: true).reversed_layers

      assert kept == %Position.Dodge2{preserve: :single, padding: 0.3, reverse: true}

      assert [%Plot.Layer{position: %Position.Dodge{width: :none}}] =
               Plot.geom_boxplot(plot, position: :dodge).reversed_layers
    end

    test "boxes are not stacked" do
      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          @rows
          |> Plot.new(%{x: :cyl, y: :mpg})
          |> Plot.geom_boxplot(position: :stack)
        end

      assert error.message =~
               "expected :dodge2, :dodge or a position Plot.position_dodge2/1 makes, got: :stack"
    end

    test "a weight the plot maps is refused, and one the layer maps cannot be used" do
      plot = Plot.new(@rows, %{x: :cyl, y: :mpg, weight: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_boxplot(plot) end

      assert error.message ==
               "Plot.geom_boxplot/3 takes :weight from the plot's mapping, which maps it to " <>
                 "\"wt\", but a box plot is not weighted: each box summarises its rows as they " <>
                 "are. Map :weight on the layers that count with it rather than on the plot."

      error =
        assert_raise ArgumentError, fn ->
          @rows
          |> Plot.new(%{x: :cyl, y: :mpg})
          |> Plot.geom_boxplot(%{weight: :wt})
        end

      assert error.message =~ "cannot use :weight"
    end

    test "with one of x and y mapped, orientation: must name the other; with both, it chooses" do
      alone = Plot.new(@rows, %{y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_boxplot(alone, orientation: :y) end

      assert error.message ==
               "Plot.geom_boxplot/3 summarises y here, because :y alone is mapped, so its " <>
                 "boxes stand along x and orientation: :y cannot apply. To stand the boxes " <>
                 "along y, map :x instead of :y; orientation: :y can then stay or be left out."

      error =
        assert_raise ArgumentError, fn ->
          @rows
          |> Plot.new(%{x: :mpg, colour: :cyl})
          |> Plot.geom_boxplot(orientation: :x)
        end

      assert error.message ==
               "Plot.geom_boxplot/3 summarises x here, because :x alone is mapped, so its " <>
                 "boxes stand along y and orientation: :x cannot apply. To stand the boxes " <>
                 "along x, map :y instead of :x; orientation: :x can then stay or be left out."

      for {plot, orientation} <- [
            {alone, :x},
            {Plot.new(@rows, %{x: :mpg}), :y},
            {Plot.new(@rows, %{x: :wt, y: :mpg}), :y}
          ] do
        assert [%Plot.Layer{stat: %Stat.Boxplot{orientation: ^orientation}}] =
                 Plot.geom_boxplot(plot, orientation: orientation).reversed_layers
      end
    end

    test "a box plot needs x or y, and a mapped width must hold numbers" do
      error =
        assert_raise ArgumentError, fn ->
          @rows
          |> Plot.new()
          |> Plot.geom_boxplot()
        end

      assert error.message =~ "Plot.geom_boxplot/3 needs"

      error =
        assert_raise ArgumentError, fn ->
          @rows
          |> Plot.new(%{x: :cyl, y: :mpg})
          |> Plot.geom_boxplot(%{width: :cyl})
        end

      assert error.message ==
               "Plot.geom_boxplot/3 maps :width to \"cyl\", a :string column, but a box is " <>
                 "drawn as wide as its width, so it must be a number"

      assert [%Plot.Layer{}] =
               @rows
               |> Plot.new(%{x: :cyl, y: :mpg, width: :cyl})
               |> Plot.geom_boxplot(width: 0.5)
               |> Map.fetch!(:reversed_layers)
    end

    # ggplot2 4.0.3's `stat_boxplot()` documents its whiskers, hinges, notches and width, each of
    # the first in either orientation, and drops x, y and weight.
    test "an after_stat reads the summary's documented variables, and none it consumes" do
      plot = Plot.new(@rows, %{x: :cyl, y: :mpg})

      for variable <- [
            :ymin,
            :xmin,
            :lower,
            :xlower,
            :middle,
            :xmiddle,
            :upper,
            :xupper,
            :ymax,
            :xmax,
            :notchlower,
            :notchupper,
            :width
          ] do
        assert [%Plot.Layer{}] =
                 Plot.geom_boxplot(plot, %{fill: {:after_stat, [variable]}}).reversed_layers
      end

      for variable <- [:outliers, :relvarwidth] do
        error =
          assert_raise ArgumentError, fn ->
            Plot.geom_boxplot(plot, %{fill: {:after_stat, [variable]}})
          end

        assert error.message =~ "Plot.geom_boxplot/3 maps :fill"
      end

      for aesthetic <- [:x, :y, :weight] do
        error =
          assert_raise ArgumentError, fn ->
            Plot.geom_boxplot(plot, %{aesthetic => {:after_stat, [:middle]}})
          end

        assert error.message =~ "its stat consumes #{inspect(aesthetic)}"
      end
    end

    test "a column the mapping misspells is refused, naming the function" do
      error =
        assert_raise ArgumentError, fn ->
          @rows
          |> Plot.new(%{x: :cyl})
          |> Plot.geom_boxplot(%{y: :mgp})
        end

      assert error.message =~ "Plot.geom_boxplot/3 maps :y to :mgp"
    end

    test "every box's look and its outliers' are checked and held as resolved" do
      plot =
        @rows
        |> Plot.new(%{x: :cyl, y: :mpg})
        |> Plot.geom_boxplot(
          colour: "red",
          linetype: :dashed,
          shape: 21,
          outlier_fill: "blue",
          outlier_size: 2,
          outlier_alpha: 0.5,
          median_colour: "green"
        )

      assert [%Plot.Layer{geom: geom, fixed: fixed}] = plot.reversed_layers
      assert fixed === %{color: "#FF0000", linetype: {4, 4}, shape: :circle_filled}

      assert {geom.outlier, geom.median} ===
               {%{fill: "#0000FF", size: 2.0, alpha: 0.5, stroke: 0.5}, %{color: "#008000"}}

      for refused <- [
            [alpha: 2],
            [linewidth: -1],
            [size: -1],
            [outlier_size: -1],
            [outlier_alpha: 2]
          ] do
        assert_raise NimbleOptions.ValidationError, fn -> Plot.geom_boxplot(plot, refused) end
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
                 geom: %Geom.Path{
                   line_end: :butt,
                   line_join: :round,
                   mitre_limit: 10.0,
                   arrow: :none
                 },
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{group: "cyl"},
                 fixed: %{},
                 accepted: [:alpha, :color, :group, :linetype, :linewidth, :x, :y],
                 annotation: false,
                 inherit: true
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

    test "a line's corners are rounded, mitred or bevelled" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for join <- [:round, :mitre, :bevel] do
        assert [%Plot.Layer{geom: %Geom.Path{line_join: ^join, arrow: :none}}] =
                 Plot.geom_path(plot, linejoin: join).reversed_layers
      end
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

  describe "geom_segment/3" do
    test "a segment layer records its geom with ggplot2's ends and corners by default" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_segment(%{xend: :wt, colour: :cyl})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Segment{line_end: :butt, line_join: :round, arrow: :none},
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{xend: "wt", color: "cyl"},
                 fixed: %{},
                 accepted: [:alpha, :color, :group, :linetype, :linewidth, :x, :xend, :y, :yend],
                 annotation: false,
                 inherit: true
               }
             ]
    end

    test "the options choose the geom's ends and corners and set every segment's look" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg, yend: :mpg})
        |> Plot.geom_segment(
          lineend: :square,
          linejoin: :mitre,
          colour: "red",
          linewidth: 2,
          linetype: :dashed,
          alpha: 1
        )

      assert [
               %Plot.Layer{
                 geom: %Geom.Segment{line_end: :square, line_join: :mitre, arrow: :none},
                 fixed: %{color: "#FF0000", linewidth: 2.0, linetype: {4, 4}, alpha: 1.0}
               }
             ] = plot.reversed_layers
    end

    test "a mapping a segment cannot use, or a column the data lacks, is refused naming " <>
           "geom_segment/3" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for mapping <- [%{xend: :wt, fill: :cyl}, %{xend: :nope}] do
        error = assert_raise ArgumentError, fn -> Plot.geom_segment(plot, mapping) end
        assert String.starts_with?(error.message, "Plot.geom_segment/3 ")
      end
    end

    # grid's `arrow()` defaults: 30 degrees, 0.25 inches, the last end, open; ggplot2's
    # `arrow.fill` the line's colour.
    test "arrow: true records an arrowhead at grid's defaults, its length in points, on every " <>
           "line layer and annotation" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, xend: :wt})
      binned = Plot.new(@rows, %{x: :wt})
      defaults = %{angle: 30.0, length: 18.0, ends: :last, type: :open, fill: :color}

      layers = [
        Plot.geom_segment(plot, arrow: true),
        Plot.geom_path(plot, arrow: true),
        Plot.geom_line(plot, arrow: true),
        Plot.geom_freqpoly(binned, arrow: true),
        Plot.annotate(plot, :segment, x: 1, y: 1, xend: 2, yend: 2, arrow: true),
        Plot.annotate(plot, :path, x: [1, 2], y: [1, 2], arrow: true),
        Plot.annotate(plot, :line, x: [1, 2], y: [1, 2], arrow: true)
      ]

      for layered <- layers do
        assert [%Plot.Layer{geom: %{arrow: ^defaults}, fixed: fixed}] = layered.reversed_layers
        refute Map.has_key?(fixed, :arrow)
      end

      assert [%Plot.Layer{geom: %Geom.Segment{arrow: :none}}] =
               Plot.geom_segment(plot).reversed_layers
    end

    # A length is worked out in points as grid works one out, through inches: TeX's points over
    # 72.27, centimetres over 2.54, millimetres over 10 and then 2.54.
    test "an arrowhead's options are recorded as given, its length in points and its fill " <>
           "resolved" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, xend: :wt})

      lengths =
        for {length, fill, kept} <- [
              {{5, :cm}, "white", "#FFFFFF"},
              {{72.27, :pt}, :none, :none},
              {{-2, :mm}, :color, :color}
            ] do
          options = [angle: 15, length: length, ends: :both, type: :closed, fill: fill]

          assert [%Plot.Layer{geom: %Geom.Segment{arrow: arrow}}] =
                   Plot.geom_segment(plot, arrow: options).reversed_layers

          assert Map.delete(arrow, :length) ===
                   %{angle: 15.0, ends: :both, type: :closed, fill: kept}

          arrow.length
        end

      assert lengths === [5 / 2.54 * 72, 72.27 / 72.27 * 72, -2 / 10 / 2.54 * 72]
    end

    test "an arrowhead that is not true or a keyword list of its options is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, xend: :wt})

      for arrow <- [
            false,
            :closed,
            [:closed],
            [length: 0.25],
            [length: {1, :npc}],
            [length: {"1", :cm}],
            [angle: "30"],
            [ends: :middle],
            [type: :filled],
            [fill: "nope"],
            [width: 2]
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_segment(plot, arrow: arrow)
          end

        assert error.key == :arrow
      end

      not_options =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.geom_segment(plot, arrow: :closed)
        end

      no_unit =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.geom_segment(plot, arrow: [length: {1, :npc}])
        end

      assert not_options.message =~ ":closed"
      assert no_unit.message =~ "{1, :npc}"
      assert no_unit.message =~ "[:pt, :cm, :mm, :in]"

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_path(plot, arrow: [angle: 10, angle: 20])
        end

      assert error.message =~ "given twice"
    end

    # ggplot2 4.0.3's `GeomSegment` requires `c("x", "y", "xend|yend")` and its `draw_panel()`
    # takes no `linemitre`.
    test "a segment needs one of xend and yend, and takes no mitre limit or fill" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_segment(plot) end
      assert error.message =~ "Plot.geom_segment/3 needs one of :xend, :yend"

      for {option, value} <- [linemitre: 4, fill: "red", lineend: :flat] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_segment(plot, [{option, value}])
          end

        assert error.key in [option, [option]]
      end
    end
  end

  describe "geom_rug/3" do
    # ggplot2 4.0.3's `geom_rug()`: `sides = "bl"`, `length = unit(0.03, "npc")`, `outside =
    # FALSE`, `lineend = "butt"`, and the identity stat and position.
    test "a rug layer records its geom with ggplot2's sides, length and line ends by default" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_rug(%{colour: :cyl})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Rug{
                   sides: [:bottom, :left],
                   length: {0.03, :npc},
                   outside: false,
                   line_end: :butt
                 },
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{color: "cyl"},
                 fixed: %{},
                 accepted: [:alpha, :color, :group, :linetype, :linewidth, :x, :y],
                 annotation: false,
                 inherit: true
               }
             ]
    end

    test "the options choose the sides, the length, the way out and the line ends, and set looks" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_rug(
          sides: [:top, :right],
          length: {1, :npc},
          outside: true,
          lineend: :round,
          colour: "red",
          linewidth: 2,
          linetype: :dashed,
          alpha: 1
        )

      assert [
               %Plot.Layer{
                 geom: %Geom.Rug{
                   sides: [:top, :right],
                   length: {1.0, :npc},
                   outside: true,
                   line_end: :round
                 },
                 fixed: %{color: "#FF0000", linewidth: 2.0, linetype: {4, 4}, alpha: 1.0}
               }
             ] = plot.reversed_layers
    end

    # Any amount, as grid draws a negative one's lines out from the edge; the theme's tests pin
    # how a unit is worked out in points.
    test "a length in a unit is recorded in points, worked out as the theme works one out" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for length <- [{12, :pt}, {0.5, :cm}, {-2, :mm}, {1, :in}] do
        assert [%Plot.Layer{geom: %Geom.Rug{length: {points, :points}}}] =
                 Plot.geom_rug(plot, length: length).reversed_layers

        assert points === Theme.points(length)
      end
    end

    test "sides that are not a list of the panel's four, each given once, are refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for sides <- [[:bottom, :bottom], [:north], :bottom, "bl"] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Plot.geom_rug(plot, sides: sides) end

        assert error.message =~
                 "[:top, :right, :bottom, :left], each given once, got: " <>
                   inspect(sides)
      end

      assert [%Plot.Layer{geom: %Geom.Rug{sides: []}}] =
               Plot.geom_rug(plot, sides: []).reversed_layers
    end

    # ggplot2 4.0.3 refuses `geom_rug(length = 0.01)`: "`length` must be a <unit> object".
    test "a length that is not an amount in a share of the panel or a unit is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for length <- [0.03, {0.03, :lines}, {"1", :npc}, {"1", :cm}, [0.03, :npc]] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_rug(plot, length: length)
          end

        assert error.message =~
                 "an amount with a unit of [:npc, :pt, :cm, :mm, :in], got: " <>
                   inspect(length)
      end
    end

    # ggplot2 4.0.3's `GeomRug` needs neither, and draws nothing with neither.
    test "a rug needs one of x and y" do
      unmapped = Plot.new(@rows)
      error = assert_raise ArgumentError, fn -> Plot.geom_rug(unmapped) end
      assert error.message =~ "Plot.geom_rug/3 needs one of :x, :y, but neither its mapping"

      for mapping <- [%{x: :wt}, %{y: :mpg}] do
        plot = Plot.new(@rows, mapping)
        assert [%Plot.Layer{}] = Plot.geom_rug(plot).reversed_layers
      end
    end

    # ggplot2 4.0.3: `geom_rug(position = "jitter")` of `aes(x)` alone fails as the plot is built,
    # "`position_jitter()` requires the following missing aesthetics: y".
    test "a jittered rug needs both x and y, saying it is jittered" do
      across = Plot.new(@rows, %{x: :wt})
      both = Plot.new(@rows, %{x: :wt, y: :mpg})

      for position <- [:jitter, Plot.position_jitter(seed: 3)] do
        error = assert_raise ArgumentError, fn -> Plot.geom_rug(across, position: position) end
        assert error.message =~ "Plot.geom_rug/3 needs :y, but neither its mapping"
        assert error.message =~ "its rugs are jittered"
      end

      assert [%Plot.Layer{position: %Position.Jitter{width: :none, height: :none, seed: 0}}] =
               Plot.geom_rug(both, position: :jitter).reversed_layers

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.geom_rug(both, position: :dodge)
        end

      assert error.key == :position
    end

    test "a mapping that is not a map, or options that are not a keyword list, are refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for {mapping, options} <- [{untyped(:wt), []}, {%{}, untyped(:bottom)}] do
        error =
          assert_raise FunctionClauseError, fn -> Plot.geom_rug(plot, mapping, options) end

        assert {error.module, error.function, error.arity} == {Plot, :geom_rug, 3}
      end
    end

    test "a mapping a rug cannot use, or an option it does not take, is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for mapping <- [%{xend: :wt}, %{fill: :cyl}, %{y: :nope}] do
        error = assert_raise ArgumentError, fn -> Plot.geom_rug(plot, mapping) end
        assert String.starts_with?(error.message, "Plot.geom_rug/3 ")
      end

      for {option, value} <- [linejoin: :mitre, fill: "red", outside: 1, arrow: true] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_rug(plot, [{option, value}])
          end

        assert error.key in [option, [option]]
      end
    end
  end

  describe "geom_linerange/3 and geom_pointrange/3" do
    @ranges %{
      "trt" => [1, 2],
      "resp" => [1.0, 3.0],
      "lower" => [0.8, 2.4],
      "upper" => [1.1, 3.3]
    }

    test "a range layer records its geom with no orientation and butt ends by default" do
      plot = Plot.new(@ranges, %{x: :trt, y: :resp})

      assert [
               %Plot.Layer{
                 geom: %Geom.Linerange{orientation: :none, line_end: :butt},
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{ymin: "lower", ymax: "upper"},
                 fixed: %{},
                 accepted: [
                   :alpha,
                   :color,
                   :group,
                   :linetype,
                   :linewidth,
                   :x,
                   :xmax,
                   :xmin,
                   :y,
                   :ymax,
                   :ymin
                 ],
                 annotation: false,
                 inherit: true
               }
             ] = Plot.geom_linerange(plot, %{ymin: :lower, ymax: :upper}).reversed_layers

      assert [%Plot.Layer{geom: %Geom.Pointrange{orientation: :none, line_end: :butt}}] =
               Plot.geom_pointrange(plot, %{ymin: :lower, ymax: :upper}).reversed_layers
    end

    test "the options choose the orientation and ends, and set every line's and point's look" do
      plot =
        Plot.new(@ranges, %{x: :trt, y: :resp, ymin: :lower, ymax: :upper, xmin: :lower})

      assert [
               %Plot.Layer{
                 geom: %Geom.Pointrange{orientation: :x, line_end: :round},
                 fixed: %{
                   color: "#FF0000",
                   linewidth: 2.0,
                   linetype: {4, 4},
                   fill: "#FFFFFF",
                   shape: :circle_filled,
                   size: 3.0,
                   stroke: 1.5
                 }
               }
             ] =
               Plot.geom_pointrange(plot,
                 orientation: :x,
                 lineend: :round,
                 colour: "red",
                 linewidth: 2,
                 linetype: :dashed,
                 fill: "white",
                 shape: 21,
                 size: 3,
                 stroke: 1.5
               ).reversed_layers

      assert_raise NimbleOptions.ValidationError, fn ->
        Plot.geom_linerange(plot, fill: "white")
      end
    end

    # ggplot2 4.0.3's `GeomLinerange$setup_params()` aborts building a vertical layer without x,
    # ymin and ymax: "Either, x, ymin, and ymax or y, xmin, and xmax must be supplied."
    test "a range layer is refused where it lacks a position its orientation runs along" do
      plot = Plot.new(@ranges, %{x: :trt, y: :resp})

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_linerange(plot, %{ymin: :lower, ymax: :upper}, orientation: :y)
        end

      assert String.starts_with?(
               error.message,
               "Plot.geom_linerange/3 runs along y, so it needs :y, :xmin and :xmax, but " <>
                 "neither its mapping nor the plot's gives :xmin and :xmax."
             )

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_pointrange(plot, %{ymin: :lower, xmax: :upper})
        end

      assert error.message =~
               "runs along x, so it needs :x, :ymin and :ymax, but neither its " <>
                 "mapping nor the plot's gives :ymax."

      across = Plot.new(@ranges, %{y: :trt, xmin: :lower, xmax: :upper})
      assert %Plot{} = Plot.geom_linerange(across)
    end

    test "a point range needs its point's x and y" do
      plot = Plot.new(@ranges, %{x: :trt})

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_pointrange(plot, %{ymin: :lower, ymax: :upper})
        end

      assert error.message =~ "Plot.geom_pointrange/3 needs :y"
    end

    # ggplot2 4.0.3: `annotate("pointrange", x = 3.5, y = 20, ymin = 12, ymax = 28, colour = "red",
    # size = 2.5, linewidth = 1.5)`, its looks one per annotation.
    test "a line range or point range annotation takes its positions and a look for each" do
      [layer] =
        @rows
        |> Plot.new()
        |> Plot.annotate(:pointrange,
          x: [3.5, 4.0],
          y: 20,
          ymin: 12,
          ymax: 28,
          colour: ["red", "blue"],
          size: 2.5,
          linewidth: [1.5, 1]
        )
        |> Map.fetch!(:reversed_layers)

      assert %Plot.Layer{
               geom: %Geom.Pointrange{orientation: :none, line_end: :butt},
               mapping: %{x: "x", y: "y", ymin: "ymin", ymax: "ymax"},
               fixed: %{color: ["#FF0000", "#0000FF"], size: 2.5, linewidth: [1.5, 1.0]},
               annotation: true
             } = layer

      plot = Plot.new(@rows)

      error =
        assert_raise ArgumentError, fn ->
          Plot.annotate(plot, :linerange, x: 1, ymin: 0, ymax: 2, orientation: :y)
        end

      assert error.message =~ "Plot.annotate/3 runs along y"
    end
  end

  describe "geom_errorbar/3 and geom_crossbar/3" do
    @bars %{
      "trt" => [1, 2],
      "resp" => [1.0, 3.0],
      "lower" => [0.8, 2.4],
      "upper" => [1.1, 3.3],
      "label" => ["a", "b"]
    }

    test "an error bar or crossbar layer records its geom, its crossbar's corners mitred" do
      plot = Plot.new(@bars, %{x: :trt, y: :resp, ymin: :lower, ymax: :upper})

      assert [
               %Plot.Layer{
                 geom: %Geom.Errorbar{orientation: :none, line_end: :butt},
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 fixed: %{width: 0.2},
                 accepted: accepted
               }
             ] = Plot.geom_errorbar(plot, width: 0.2).reversed_layers

      assert :width in accepted

      assert [
               %Plot.Layer{
                 geom: %Geom.Crossbar{
                   orientation: :none,
                   middle: %{},
                   box: %{},
                   line_end: :butt,
                   line_join: :mitre
                 }
               }
             ] = Plot.geom_crossbar(plot).reversed_layers

      assert [%Plot.Layer{accepted: crossbar_accepted}] =
               Plot.geom_crossbar(plot).reversed_layers

      assert crossbar_accepted == [
               :alpha,
               :color,
               :fill,
               :group,
               :linetype,
               :linewidth,
               :width,
               :x,
               :xmax,
               :xmin,
               :y,
               :ymax,
               :ymin
             ]

      assert [%Plot.Layer{geom: %Geom.Crossbar{line_join: :bevel}, fixed: %{linetype: {4, 4}}}] =
               Plot.geom_crossbar(plot, linejoin: :bevel, linetype: :dashed).reversed_layers

      assert_raise NimbleOptions.ValidationError, ~r/linetype/, fn ->
        Plot.geom_crossbar(plot, linetype: :wiggly)
      end
    end

    # ggplot2 4.0.3's `geom_crossbar(middle.colour = , middle.linetype = , box.linewidth = )`, R's
    # dotted names underscored, each part holding only the looks given.
    test "a crossbar's middle_ and box_ options give each part a look of its own" do
      plot = Plot.new(@bars, %{x: :trt, y: :resp, ymin: :lower, ymax: :upper})

      assert [
               %Plot.Layer{
                 geom: %Geom.Crossbar{
                   middle: %{color: "#FF0000", linetype: {4, 4}},
                   box: %{linewidth: 0.3},
                   line_end: :round,
                   line_join: :round
                 },
                 fixed: %{fill: "#FFFFFF"}
               }
             ] =
               Plot.geom_crossbar(plot,
                 middle_colour: "red",
                 middle_linetype: :dashed,
                 box_linewidth: 0.3,
                 lineend: :round,
                 linejoin: :round,
                 fill: "white"
               ).reversed_layers

      assert_raise NimbleOptions.ValidationError, fn ->
        Plot.geom_errorbar(plot, middle_colour: "red")
      end
    end

    test "a layer lacking its range's positions, or mapping a width that is not a number, is " <>
           "refused" do
      plot = Plot.new(@bars, %{x: :trt, y: :resp})

      error =
        assert_raise ArgumentError, fn -> Plot.geom_errorbar(plot, %{ymin: :lower}) end

      assert error.message =~ "Plot.geom_errorbar/3 needs one of :ymax, :xmax"

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_crossbar(plot, %{ymin: :lower, ymax: :upper}, orientation: :y)
        end

      assert error.message =~ "Plot.geom_crossbar/3 runs along y"

      # A crossbar's line across stands at its y, ggplot2's `required_aes` `c("x", "y", ...)`.
      error =
        assert_raise ArgumentError, fn ->
          @bars
          |> Plot.new(%{x: :trt})
          |> Plot.geom_crossbar(%{ymin: :lower, ymax: :upper})
        end

      assert error.message =~ "Plot.geom_crossbar/3 needs :y"

      for {layer, function} <- [
            {&Plot.geom_errorbar/3, "Plot.geom_errorbar/3"},
            {&Plot.geom_crossbar/3, "Plot.geom_crossbar/3"}
          ] do
        error =
          assert_raise ArgumentError, fn ->
            layer.(plot, %{ymin: :lower, ymax: :upper, width: :label}, [])
          end

        assert String.starts_with?(
                 error.message,
                 "#{function} maps :width to \"label\", a :string column"
               )
      end
    end

    # ggplot2 4.0.3: `annotate("errorbar", x = 3, ymin = 1, ymax = 2, width = 0.5)` and
    # `annotate("crossbar", x = 3, y = 3, ymin = 2.5, ymax = 3.5)`.
    test "an error bar or crossbar annotation takes its positions, a width and the crossbar's " <>
           "part looks" do
      plot = Plot.new(@rows)

      assert [%Plot.Layer{geom: %Geom.Errorbar{}, fixed: %{width: [0.5, 0.2]}, annotation: true}] =
               Plot.annotate(plot, :errorbar, x: [3, 4], ymin: 1, ymax: 2, width: [0.5, 0.2]).reversed_layers

      assert [
               %Plot.Layer{
                 geom: %Geom.Crossbar{middle: %{color: "#0000FF"}},
                 mapping: %{x: "x", y: "y", ymin: "ymin", ymax: "ymax"}
               }
             ] =
               Plot.annotate(plot, :crossbar,
                 x: 3,
                 y: 3,
                 ymin: 2.5,
                 ymax: 3.5,
                 middle_colour: "blue"
               ).reversed_layers

      error =
        assert_raise ArgumentError, fn ->
          Plot.annotate(plot, :errorbar, y: 1, xmin: 0, xmax: 2, orientation: :x)
        end

      assert error.message =~ "Plot.annotate/3 runs along x"
    end
  end

  describe "position_dodge/1 and a range layer's position:" do
    test "position_dodge/1 records the width given, as a float, or :none" do
      assert Plot.position_dodge(width: 1) == %Position.Dodge{width: 1.0}
      assert Plot.position_dodge() == %Position.Dodge{width: :none}

      assert_raise NimbleOptions.ValidationError, fn -> Plot.position_dodge(width: "wide") end
      assert_raise NimbleOptions.ValidationError, fn -> Plot.position_dodge(preserve: :single) end
    end

    test "a range layer is drawn where it is unless position: dodges it, by name or by a struct" do
      plot =
        Plot.new(@ranges, %{x: :trt, y: :resp, ymin: :lower, ymax: :upper, xmin: :lower})

      layers = [
        &Plot.geom_linerange/3,
        &Plot.geom_pointrange/3,
        &Plot.geom_errorbar/3,
        &Plot.geom_crossbar/3
      ]

      for layer <- layers do
        assert [%Plot.Layer{position: %Position.Identity{}}] =
                 layer.(plot, %{}, []).reversed_layers

        assert [%Plot.Layer{position: %Position.Dodge{width: :none}}] =
                 layer.(plot, %{}, position: :dodge).reversed_layers

        assert [%Plot.Layer{position: %Position.Dodge2{preserve: :total}}] =
                 layer.(plot, %{}, position: :dodge2).reversed_layers

        dodge = Plot.position_dodge(width: 0.9)

        assert [%Plot.Layer{position: ^dodge}] =
                 layer.(plot, %{}, position: dodge).reversed_layers

        assert_raise NimbleOptions.ValidationError, fn -> layer.(plot, %{}, position: :stack) end

        assert_raise NimbleOptions.ValidationError, ~r/expected :identity, :dodge, :dodge2/, fn ->
          layer.(plot, %{}, position: Plot.position_jitter())
        end
      end
    end

    test "a bar layer takes position_dodge/1's struct; a box plot does not" do
      plot = Plot.new(@rows, %{x: :cyl, y: :mpg})
      dodge = Plot.position_dodge(width: 0.5)

      assert [%Plot.Layer{position: ^dodge}] =
               Plot.geom_col(plot, position: dodge).reversed_layers

      assert_raise NimbleOptions.ValidationError, fn ->
        Plot.geom_boxplot(plot, position: dodge)
      end
    end
  end

  describe "stat_summary/3" do
    @summarised %{"cyl" => [4, 4, 6], "mpg" => [22.0, 26.0, 18.0], "vs" => ["a", "b", "a"]}

    test "a summary records mean_se, point ranges with no orientation, and the identity position" do
      plot = Plot.new(@summarised, %{x: :cyl, y: :mpg})

      assert [
               %Plot.Layer{
                 geom: %Geom.Pointrange{orientation: :none, line_end: :butt},
                 stat: %Stat.Summary{
                   fun_data: {:mean_se, mult: 1.0},
                   fun: :none,
                   fun_min: :none,
                   fun_max: :none,
                   orientation: :none
                 },
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{},
                 fixed: %{},
                 accepted: [
                   :alpha,
                   :color,
                   :fill,
                   :group,
                   :linetype,
                   :linewidth,
                   :shape,
                   :size,
                   :stroke,
                   :x,
                   :y
                 ],
                 annotation: false,
                 inherit: true
               }
             ] = Plot.stat_summary(plot).reversed_layers
    end

    test "the summary's options are its stat's, its orientation the stat's alone" do
      plot = Plot.new(@summarised, %{x: :cyl, y: :mpg})
      last = fn values -> List.last(values) end

      assert [
               %Plot.Layer{
                 geom: %Geom.Errorbar{orientation: :none},
                 stat: %Stat.Summary{
                   fun_data: :none,
                   fun: :median,
                   fun_min: :min,
                   fun_max: ^last,
                   orientation: :y
                 },
                 fixed: %{width: 0.5}
               }
             ] =
               Plot.stat_summary(plot,
                 geom: :errorbar,
                 fun: :median,
                 fun_min: :min,
                 fun_max: last,
                 orientation: :y,
                 width: 0.5
               ).reversed_layers

      assert [%Plot.Layer{stat: %Stat.Summary{fun_data: {:mean_se, mult: 2.0}}}] =
               Plot.stat_summary(plot, fun_data: {:mean_se, mult: 2}).reversed_layers

      assert [%Plot.Layer{stat: %Stat.Summary{fun_data: {:mean_se, mult: 1.0}}}] =
               Plot.stat_summary(plot, fun_data: :mean_se).reversed_layers

      assert [%Plot.Layer{stat: %Stat.Summary{orientation: :x}}] =
               Plot.stat_summary(plot, orientation: :x).reversed_layers
    end

    test "each geom takes its function's options, and the bars' position is the identity" do
      plot = Plot.new(@summarised, %{x: :cyl, y: :mpg})

      kinds =
        for geom <- [:point, :line, :bar, :crossbar, :linerange, :ribbon] do
          [layer] = Plot.stat_summary(plot, geom: geom).reversed_layers
          {layer.geom, layer.position}
        end

      assert [
               {%Geom.Point{}, %Position.Identity{}},
               {%Geom.Line{orientation: :none, line_end: :butt, arrow: :none}, _line},
               {%Geom.Bar{just: 0.5}, %Position.Identity{}},
               {%Geom.Crossbar{orientation: :none, line_join: :mitre}, %Position.Identity{}},
               {%Geom.Linerange{orientation: :none}, %Position.Identity{}},
               {%Geom.Ribbon{orientation: :none, outline_type: :both}, _ribbon}
             ] = kinds

      assert [%Plot.Layer{geom: %Geom.Bar{just: +0.0}, position: %Position.Stack{}}] =
               Plot.stat_summary(plot, geom: :bar, position: :stack, just: 0).reversed_layers

      assert [%Plot.Layer{position: %Position.Jitter{}}] =
               Plot.stat_summary(plot, geom: :point, position: :jitter).reversed_layers

      assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:width\]/, fn ->
        Plot.stat_summary(plot, geom: :point, width: 0.5)
      end

      assert_raise NimbleOptions.ValidationError, ~r/expected :identity, :stack/, fn ->
        Plot.stat_summary(plot, geom: :bar, position: :jitter)
      end
    end

    test "a geom it does not draw with is refused, naming those it does" do
      plot = Plot.new(@summarised, %{x: :cyl, y: :mpg})

      assert_raise ArgumentError,
                   "Plot.stat_summary/3 draws with :pointrange, :point, :line, :bar, " <>
                     ":crossbar, :errorbar, :linerange or :ribbon, got: :col",
                   fn -> Plot.stat_summary(plot, geom: :col) end
    end

    test "fun_data: beside fun:, fun_min: or fun_max: is refused, naming them" do
      plot = Plot.new(@summarised, %{x: :cyl, y: :mpg})

      assert_raise ArgumentError,
                   "Plot.stat_summary/3 is given fun_data:, the whole summary, and fun: and " <>
                     "fun_max:, part of one; give fun_data: alone, or fun:, fun_min: and fun_max:",
                   fn ->
                     Plot.stat_summary(plot, fun_data: :mean_se, fun: :mean, fun_max: :max)
                   end
    end

    test "a summary's values are checked at the call" do
      plot = Plot.new(@summarised, %{x: :cyl, y: :mpg})

      assert_raise NimbleOptions.ValidationError,
                   ~r/expected :mean, :median, :min, :max or a function of one argument, got: :sd/,
                   fn -> Plot.stat_summary(plot, fun: :sd) end

      assert_raise NimbleOptions.ValidationError, ~r/a function of one argument, got: /, fn ->
        Plot.stat_summary(plot, fun_min: fn left, right -> left + right end)
      end

      for fun_data <- [:mean_sd, "mean_cl_boot", {:mean_sdl, 1}, {:mean_cl_boot}] do
        assert_raise NimbleOptions.ValidationError,
                     ~r/expected :mean_se, :mean_cl_normal, :mean_sdl, :median_hilow or :mean_cl_boot, alone or in a tuple with a keyword list of its arguments, got: /,
                     fn -> Plot.stat_summary(plot, fun_data: fun_data) end
      end
    end

    test "a whole summary records every argument it takes, given or its default, in one order" do
      plot = Plot.new(@summarised, %{x: :cyl, y: :mpg})

      recorded =
        for fun_data <- [
              :mean_cl_normal,
              {:mean_cl_normal, conf_int: 0},
              {:mean_cl_normal, conf_int: 0.5},
              {:mean_cl_normal, mult: 1},
              :mean_sdl,
              {:mean_sdl, mult: 1},
              :median_hilow,
              {:median_hilow, conf_int: 1},
              {:median_hilow, conf_int: 0},
              :mean_cl_boot,
              {:mean_cl_boot, seed: -3, resamples: 1, conf_int: 0.5},
              {:mean_cl_boot, []}
            ] do
          [layer] = Plot.stat_summary(plot, fun_data: fun_data).reversed_layers
          layer.stat.fun_data
        end

      assert recorded === [
               {:mean_cl_normal, conf_int: 0.95},
               {:mean_cl_normal, conf_int: 0.0},
               {:mean_cl_normal, conf_int: 0.5},
               {:mean_cl_normal, mult: 1.0},
               {:mean_sdl, mult: 2.0},
               {:mean_sdl, mult: 1.0},
               {:median_hilow, conf_int: 0.95},
               {:median_hilow, conf_int: 1.0},
               {:median_hilow, conf_int: 0.0},
               {:mean_cl_boot, conf_int: 0.95, resamples: 1000, seed: 0},
               {:mean_cl_boot, conf_int: 0.5, resamples: 1, seed: -3},
               {:mean_cl_boot, conf_int: 0.95, resamples: 1000, seed: 0}
             ]
    end

    test "a whole summary's arguments are its own, each once, and each value is checked" do
      plot = Plot.new(@summarised, %{x: :cyl, y: :mpg})

      refused = [
        {{:mean_se, mult: "2"}, "expected :mean_se's mult: to be a number, got: \"2\""},
        {{:mean_sdl, [2]},
         "expected {:mean_sdl, arguments}'s arguments to be a keyword list of mult: each at " <>
           "most once, got: [2]"},
        {{:median_hilow, mult: 1},
         "expected {:median_hilow, arguments}'s arguments to be a keyword list of conf_int: " <>
           "each at most once, got: [mult: 1]"},
        {{:mean_cl_boot, seed: 1, seed: 2},
         "expected {:mean_cl_boot, arguments}'s arguments to be a keyword list of conf_int:, " <>
           "resamples:, seed: each at most once, got: [seed: 1, seed: 2]"},
        {{:mean_cl_normal, resamples: 10},
         "expected {:mean_cl_normal, arguments}'s arguments to be a keyword list of " <>
           "conf_int:, mult: each at most once, got: [resamples: 10]"},
        {{:mean_cl_normal, conf_int: 0.9, mult: 2},
         "expected {:mean_cl_normal, arguments} to give conf_int: or mult:, not both, got: " <>
           "[conf_int: 0.9, mult: 2]"},
        {{:mean_cl_normal, conf_int: 1},
         "expected :mean_cl_normal's conf_int: to be a number from 0, below 1, got: 1"},
        {{:mean_cl_normal, conf_int: -0.1},
         "expected :mean_cl_normal's conf_int: to be a number from 0, below 1, got: -0.1"},
        {{:median_hilow, conf_int: 1.5},
         "expected :median_hilow's conf_int: to be a number from 0 to 1, got: 1.5"},
        {{:mean_cl_boot, conf_int: -0.5},
         "expected :mean_cl_boot's conf_int: to be a number from 0 to 1, got: -0.5"},
        {{:mean_cl_boot, resamples: 0},
         "expected :mean_cl_boot's resamples: to be a whole number, 1 or more, got: 0"},
        {{:mean_cl_boot, resamples: 10.0},
         "expected :mean_cl_boot's resamples: to be a whole number, 1 or more, got: 10.0"},
        {{:mean_cl_boot, seed: 1.5}, "expected :mean_cl_boot's seed: to be an integer, got: 1.5"}
      ]

      for {fun_data, message} <- refused do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.stat_summary(plot, fun_data: fun_data)
          end

        assert Exception.message(error) =~ message
      end
    end

    # ggplot2 4.0.3 aborts building `stat_summary(aes(ymin = 10))`: "`geom_pointrange()` requires
    # the following missing aesthetics: ymin or xmin and xmax".
    test "a summary needs x and y, and refuses a range mapped, which it writes" do
      plot = Plot.new(@summarised, %{x: :cyl})

      assert_raise ArgumentError, ~r/Plot.stat_summary\/3 needs :y/, fn ->
        Plot.stat_summary(plot)
      end

      assert_raise ArgumentError, ~r/cannot use :ymin, which its mapping maps/, fn ->
        Plot.stat_summary(plot, %{y: :mpg, ymin: :mpg})
      end
    end

    test "a mapped width is a number where the geom draws one, and rides along where it does not" do
      plot = Plot.new(@summarised, %{x: :cyl, y: :mpg, width: :vs})

      assert_raise ArgumentError,
                   "Plot.stat_summary/3 maps :width to \"vs\", a :string column, but its geom " <>
                     "draws each mark as wide as its width, so it must be a number",
                   fn -> Plot.stat_summary(plot, geom: :errorbar) end

      assert [%Plot.Layer{}] = Plot.stat_summary(plot, geom: :point).reversed_layers
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
                 annotation: false,
                 inherit: true
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

  describe "geom_label/3" do
    @cars %{"wt" => [2.62, 2.32], "mpg" => [21.0, 22.8], "model" => ["Mazda RX4", "Datsun 710"]}

    # ggplot2 4.0.3's `geom_label()`: `label.padding = unit(0.25, "lines")`, `label.r =
    # unit(0.15, "lines")`, `border.colour` and `text.colour` `NULL`, the label's colour.
    test "a label layer records R's padding and corners, the identity stat and nudging" do
      plot =
        @cars
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_label(%{label: :model})

      quarter = {0.25, :lines}

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Label{
                   label_padding: %{top: quarter, right: quarter, bottom: quarter, left: quarter},
                   label_r: {0.15, :lines},
                   border_color: :color,
                   text_color: :color
                 },
                 stat: %Stat.Identity{},
                 position: %Position.Nudge{},
                 data: :none,
                 mapping: %{label: "model"},
                 fixed: %{},
                 accepted: [:alpha, :color, :fill, :group, :label, :linetype, :linewidth, :x, :y],
                 annotation: false,
                 inherit: true
               }
             ]
    end

    test "the options set every label's look, and its box's padding, corners and colours" do
      plot =
        @cars
        |> Plot.new(%{x: :wt, y: :mpg, label: :model})
        |> Plot.geom_label(
          size: 5,
          angle: 45,
          hjust: :inward,
          vjust: 1,
          family: "Times New Roman",
          colour: "red",
          fill: "lightyellow",
          alpha: 0.5,
          linewidth: 1,
          linetype: :dashed,
          nudge_x: 0.1,
          nudge_y: -1,
          label_padding: [top: 2, left: {1, :lines}, right: {0.5, :cm}],
          label_r: {1, :in},
          border_colour: :none,
          text_color: "blue"
        )

      assert [
               %Plot.Layer{
                 geom: %Geom.Label{
                   label_padding: %{
                     top: {top, :points},
                     right: {right, :points},
                     bottom: {+0.0, :points},
                     left: {1.0, :lines}
                   },
                   label_r: {radius, :points},
                   border_color: :none,
                   text_color: "#0000FF"
                 },
                 fixed: %{
                   size: 5.0,
                   angle: 45.0,
                   hjust: :inward,
                   vjust: 1.0,
                   family: "Times New Roman",
                   color: "#FF0000",
                   fill: "#FFFFE0",
                   alpha: 0.5,
                   linewidth: 1.0,
                   linetype: {4, 4},
                   nudge_x: 0.1,
                   nudge_y: -1.0
                 }
               }
             ] = plot.reversed_layers

      assert {top, right, radius} ===
               {Theme.points({2, :pt}), Theme.points({0.5, :cm}), Theme.points({1, :in})}
    end

    test "one length pads every side alike" do
      plot =
        @cars
        |> Plot.new(%{x: :wt, y: :mpg, label: :model})
        |> Plot.geom_label(label_padding: {3, :mm})

      side = {Theme.points({3, :mm}), :points}

      assert [
               %Plot.Layer{
                 geom: %Geom.Label{
                   label_padding: %{top: ^side, right: ^side, bottom: ^side, left: ^side}
                 }
               }
             ] = plot.reversed_layers
    end

    test "a column the data does not have is refused by the label layer that maps it" do
      plot = Plot.new(@cars, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_label(plot, %{label: :modle}) end
      assert error.message =~ "Plot.geom_label/3"
      assert error.message =~ ":modle"
    end

    test "a mapping that is not a map, or options that are not a keyword list, are refused" do
      plot = Plot.new(@cars, %{x: :wt, y: :mpg, label: :model})

      for {mapping, options} <- [{untyped(:wt), []}, {%{}, untyped(:bottom)}] do
        error =
          assert_raise FunctionClauseError, fn -> Plot.geom_label(plot, mapping, options) end

        assert {error.module, error.function, error.arity} == {Plot, :geom_label, 3}
      end
    end

    test "a label mapped by neither the layer nor the plot is refused, naming the call" do
      plot = Plot.new(@cars, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_label(plot) end
      assert error.message =~ "Plot.geom_label/3"
      assert error.message =~ ":label"
    end

    test "an aesthetic a label cannot use, mapped by the layer, is refused" do
      plot = Plot.new(@cars, %{x: :wt, y: :mpg, label: :model})

      error = assert_raise ArgumentError, fn -> Plot.geom_label(plot, %{shape: :model}) end
      assert error.message =~ "Plot.geom_label/3"
      assert error.message =~ ":shape"
    end

    test "padding, corners or part colours of the wrong kind are refused" do
      plot = Plot.new(@cars, %{x: :wt, y: :mpg, label: :model})

      for {key, value} <- [
            label_padding: {1, :npc},
            label_padding: [top: 1, top: 2],
            label_padding: [middle: 1],
            label_padding: "1",
            label_r: {0.5, :lines, :extra},
            label_r: [top: 1],
            border_color: "nonsense",
            text_color: 3
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_label(plot, [{key, value}])
          end

        assert error.key == key
      end
    end

    test "overlap is not checked, as ggplot2's geom_label() takes no check_overlap" do
      plot = Plot.new(@cars, %{x: :wt, y: :mpg, label: :model})

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.geom_label(plot, check_overlap: true)
        end

      assert error.key == [:check_overlap]
    end

    test "a part's colour written twice, once with each spelling, is refused" do
      plot = Plot.new(@cars, %{x: :wt, y: :mpg, label: :model})

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_label(plot, border_colour: "red", border_color: "blue")
        end

      assert error.message =~ ":border_color"
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
            fn plot -> Plot.geom_label(plot, %{y: :mpg, label: :name}, data: @own) end,
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

  describe "geom_ribbon/3 and geom_area/3" do
    @bands %{"x" => [1, 2], "low" => [1.0, 2.0], "high" => [3.0, 4.0], "g" => ["a", "b"]}

    test "a ribbon layer records its geom with ggplot2's outline, ends and corners by default" do
      plot =
        @bands
        |> Plot.new(%{x: :x, ymin: :low, ymax: :high})
        |> Plot.geom_ribbon()

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Ribbon{
                   orientation: :none,
                   outline_type: :both,
                   line_end: :butt,
                   line_join: :round,
                   mitre_limit: 10.0
                 },
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{},
                 fixed: %{},
                 accepted: [
                   :alpha,
                   :color,
                   :fill,
                   :group,
                   :linetype,
                   :linewidth,
                   :x,
                   :xmax,
                   :xmin,
                   :y,
                   :ymax,
                   :ymin
                 ],
                 annotation: false,
                 inherit: true
               }
             ]
    end

    test "an area layer records its geom, aligning and stacking, along x and outlined on top" do
      plot =
        @bands
        |> Plot.new(%{x: :x, y: :high})
        |> Plot.geom_area()

      assert [
               %Plot.Layer{
                 geom: %Geom.Area{
                   orientation: :x,
                   outline_type: :upper,
                   line_end: :butt,
                   line_join: :round,
                   mitre_limit: 10.0
                 },
                 stat: %Stat.Align{orientation: :x},
                 position: %Position.Stack{},
                 accepted: [:group, :x, :y, :alpha, :color, :fill, :linetype, :linewidth]
               }
             ] = plot.reversed_layers
    end

    test "the options choose the band's orientation, outline, position, ends and corners" do
      ribbon =
        @bands
        |> Plot.new(%{y: :x, xmin: :low, xmax: :high})
        |> Plot.geom_ribbon(orientation: :y, outline_type: :full, linejoin: :mitre, linemitre: 2)

      area =
        @bands
        |> Plot.new(%{x: :high, y: :x})
        |> Plot.geom_area(orientation: :y, position: :identity, outline_type: :lower)

      assert [
               %Plot.Layer{
                 geom: %Geom.Ribbon{
                   orientation: :y,
                   outline_type: :full,
                   line_join: :mitre,
                   mitre_limit: 2.0
                 }
               }
             ] = ribbon.reversed_layers

      assert [
               %Plot.Layer{
                 geom: %Geom.Area{orientation: :y, outline_type: :lower},
                 stat: %Stat.Align{orientation: :y},
                 position: %Position.Identity{}
               }
             ] = area.reversed_layers
    end

    test "a band's look is set for every band, its colour resolved and its alpha a float" do
      plot =
        @bands
        |> Plot.new(%{x: :x, ymin: :low, ymax: :high})
        |> Plot.geom_ribbon(colour: "red", fill: "steelblue", alpha: 1, linewidth: 2, linetype: 2)

      assert [
               %Plot.Layer{
                 fixed: %{
                   color: "#FF0000",
                   fill: "#4682B4",
                   alpha: 1.0,
                   linewidth: 2.0,
                   linetype: {4, 4}
                 }
               }
             ] = plot.reversed_layers
    end

    test "a ribbon needs one of x and y, of ymin and xmin, and of ymax and xmax" do
      plot = Plot.new(@bands, %{x: :x})

      error = assert_raise ArgumentError, fn -> Plot.geom_ribbon(plot, %{ymin: :low}) end
      assert error.message =~ "Plot.geom_ribbon/3 needs one of :ymax, :xmax"

      assert %Plot{} = Plot.geom_ribbon(plot, %{ymin: :low, xmax: :high})
    end

    # ggplot2 4.0.3 aborts drawing `geom_ribbon(aes(x, ymin = low, ymax = high), orientation =
    # "y")`: "Either xmin or xmax must be given as an aesthetic."
    test "a ribbon given an orientation needs its range across it, mapped or not" do
      plot = Plot.new(@bands, %{x: :x, ymin: :low, ymax: :high})

      error = assert_raise ArgumentError, fn -> Plot.geom_ribbon(plot, orientation: :y) end

      assert error.message =~
               "Plot.geom_ribbon/3 runs along y with orientation: :y, so it needs :xmin or :xmax"

      assert %Plot{} = Plot.geom_ribbon(plot, orientation: :x)

      assert %Plot{} =
               @bands
               |> Plot.new(%{y: :x, ymin: :low})
               |> Plot.geom_ribbon(%{xmax: :high}, orientation: :y)

      along_x = Plot.new(@bands, %{x: :x})
      assert %Plot{} = Plot.geom_ribbon(along_x, %{ymin: :low, xmax: :high}, orientation: :x)
      assert %Plot{} = Plot.geom_ribbon(along_x, %{ymax: :high, xmin: :low}, orientation: :x)

      error =
        assert_raise ArgumentError, fn ->
          @bands
          |> Plot.new(%{y: :x, xmin: :low, xmax: :high})
          |> Plot.geom_ribbon(orientation: :x)
        end

      assert error.message =~ "runs along x with orientation: :x, so it needs :ymin or :ymax"
    end

    test "a column a band layer names that its table lacks is reported by the layer's function" do
      plot = Plot.new(@bands, %{x: :x})

      error =
        assert_raise ArgumentError, fn -> Plot.geom_ribbon(plot, %{ymin: :lo, ymax: :high}) end

      assert error.message =~ "Plot.geom_ribbon/3"

      error = assert_raise ArgumentError, fn -> Plot.geom_area(plot, %{y: :hight}) end
      assert error.message =~ "Plot.geom_area/3"
    end

    test "an area needs x and y, and refuses a range or an after_stat" do
      plot = Plot.new(@bands, %{x: :x})

      error = assert_raise ArgumentError, fn -> Plot.geom_area(plot) end
      assert error.message =~ "Plot.geom_area/3 needs :y"

      error = assert_raise ArgumentError, fn -> Plot.geom_area(plot, %{y: :high, ymin: :low}) end
      assert error.message =~ ":ymin"

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_area(plot, %{y: :high, fill: {:after_stat, [:count]}})
        end

      assert error.message =~ "its stat computes no variables"
    end

    test "an outline type, an orientation or a position not offered is refused" do
      plot = Plot.new(@bands, %{x: :x, ymin: :low, ymax: :high, y: :high})

      assert_raise NimbleOptions.ValidationError, ~r/outline_type/, fn ->
        Plot.geom_ribbon(plot, outline_type: :middle)
      end

      assert_raise NimbleOptions.ValidationError, ~r/orientation/, fn ->
        Plot.geom_ribbon(plot, orientation: :z)
      end

      assert_raise NimbleOptions.ValidationError, ~r/position/, fn ->
        Plot.geom_area(plot, position: :dodge)
      end
    end
  end

  describe "geom_density/3 and stat_density/3" do
    @values %{
      "x" => [1.0, 2.0, 4.0, 4.0],
      "y" => [1, 2, 3, 4],
      "w" => [1, 2, 1, 2],
      "s" => ~w(a b c d)
    }

    test "a density layer records its geom, stat and position with ggplot2's defaults" do
      plot =
        @values
        |> Plot.new(%{x: :x})
        |> Plot.geom_density()

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Density{
                   orientation: :x,
                   outline_type: :upper,
                   line_end: :butt,
                   line_join: :round,
                   mitre_limit: 10.0
                 },
                 stat: %Stat.Density{
                   bandwidth: :nrd0,
                   adjust: 1.0,
                   kernel: :gaussian,
                   n: 512,
                   trim: false,
                   bounds: {:neg_infinity, :infinity}
                 },
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{},
                 fixed: %{},
                 accepted: [
                   :group,
                   :weight,
                   :x,
                   :y,
                   :alpha,
                   :color,
                   :fill,
                   :linetype,
                   :linewidth
                 ],
                 annotation: false,
                 inherit: true
               }
             ]
    end

    # ggplot2's `stat_density()` draws areas, stacked and outlined on both edges, with no `linejoin`
    # of its own, so its keys' corners are mitred while its outlines' are round.
    test "stat_density/3 records an area stacked and outlined on both edges, its corners unset" do
      plot = Plot.new(@values, %{x: :x})

      assert [
               %Plot.Layer{
                 geom: %Geom.Area{outline_type: :both, line_join: :none},
                 stat: %Stat.Density{bandwidth: :nrd0},
                 position: %Position.Stack{},
                 accepted: [:group, :weight, :x, :y, :alpha, :color, :fill, :linetype, :linewidth]
               }
             ] = Plot.stat_density(plot).reversed_layers

      assert [%Plot.Layer{geom: %Geom.Area{line_join: :bevel}, position: %Position.Identity{}}] =
               Plot.stat_density(plot, linejoin: :bevel, position: :identity).reversed_layers

      for line_join <- [:round, :mitre] do
        [layer] = Plot.stat_density(plot, linejoin: line_join).reversed_layers
        assert layer.geom.line_join == line_join
      end
    end

    test "the estimate's options are the stat's, each number kept as a float" do
      options = [
        bw: 2,
        adjust: 3,
        kernel: :epanechnikov,
        n: 10,
        trim: true,
        bounds: {1, :infinity}
      ]

      plot = Plot.new(@values, %{x: :x})

      for function <- [&Plot.geom_density/2, &Plot.stat_density/2] do
        [layer] = function.(plot, options).reversed_layers

        assert layer.stat === %Stat.Density{
                 bandwidth: 2.0,
                 adjust: 3.0,
                 kernel: :epanechnikov,
                 n: 10,
                 trim: true,
                 bounds: {1.0, :infinity}
               }
      end

      for kernel <- [
            :gaussian,
            :epanechnikov,
            :rectangular,
            :triangular,
            :biweight,
            :cosine,
            :optcosine
          ] do
        [layer] = Plot.geom_density(plot, kernel: kernel).reversed_layers
        assert layer.stat.kernel == kernel
      end

      [scott] = Plot.geom_density(plot, bw: :nrd, bounds: {:neg_infinity, 3}).reversed_layers
      assert {scott.stat.bandwidth, scott.stat.bounds} == {:nrd, {:neg_infinity, 3.0}}
    end

    test "a density's look is set for every curve, and its position chosen" do
      [layer] =
        @values
        |> Plot.new(%{x: :x})
        |> Plot.geom_density(
          colour: "red",
          fill: "steelblue",
          alpha: 1,
          linewidth: 2,
          linetype: 2,
          position: :stack,
          outline_type: :full
        )
        |> Map.fetch!(:reversed_layers)

      assert %Plot.Layer{
               geom: %Geom.Density{outline_type: :full},
               position: %Position.Stack{},
               fixed: %{
                 color: "#FF0000",
                 fill: "#4682B4",
                 alpha: 1.0,
                 linewidth: 2.0,
                 linetype: {4, 4}
               }
             } = layer
    end

    test "a bandwidth, a multiple, bounds, a kernel or a count not offered is refused" do
      plot = Plot.new(@values, %{x: :x})

      for bandwidth <- [0, -1, :infinity, :silverman, :ucv, "nrd0"] do
        error =
          assert_raise NimbleOptions.ValidationError, ~r/a bandwidth/, fn ->
            Plot.geom_density(plot, bw: bandwidth)
          end

        assert error.message =~ "got: #{inspect(bandwidth)}"
      end

      for adjust <- [0, -0.5, "1"] do
        error =
          assert_raise NimbleOptions.ValidationError, ~r/a multiple of the bandwidth/, fn ->
            Plot.stat_density(plot, adjust: adjust)
          end

        assert error.message =~ "got: #{inspect(adjust)}"
      end

      for bounds <- [{3, 1}, {:infinity, 5}, {1, :neg_infinity}, [1, 2], {1, nil}, {1}] do
        error =
          assert_raise NimbleOptions.ValidationError, ~r/bounds \{low, high\}/, fn ->
            Plot.geom_density(plot, bounds: bounds)
          end

        assert error.message =~ "got: #{inspect(bounds)}"
      end

      assert_raise NimbleOptions.ValidationError, ~r/kernel/, fn ->
        Plot.geom_density(plot, kernel: :gauss)
      end

      assert_raise NimbleOptions.ValidationError, ~r/:n option/, fn ->
        Plot.geom_density(plot, n: 0)
      end

      assert_raise NimbleOptions.ValidationError, ~r/position/, fn ->
        Plot.geom_density(plot, position: :dodge)
      end
    end

    test "bounds may meet" do
      plot = Plot.new(@values, %{x: :x})

      [layer] = Plot.geom_density(plot, bounds: {2, 2}).reversed_layers
      assert layer.stat.bounds == {2.0, 2.0}
    end

    test "a density runs along the one of x and y mapped, and a contrary orientation is refused" do
      assert [%Plot.Layer{geom: %Geom.Density{orientation: :y}}] =
               @values
               |> Plot.new(%{y: :x})
               |> Plot.geom_density(orientation: :y)
               |> Map.fetch!(:reversed_layers)

      error =
        assert_raise ArgumentError, fn ->
          @values
          |> Plot.new(%{x: :x})
          |> Plot.geom_density(orientation: :y)
        end

      assert error.message ==
               "Plot.geom_density/3 estimates along x here, because :x is mapped, so " <>
                 "orientation: :y cannot apply. To estimate along y, map :y instead of :x; " <>
                 "orientation: :y can then stay or be left out."
    end

    test "x and y together, or neither, are refused" do
      both =
        assert_raise ArgumentError, fn ->
          @values
          |> Plot.new(%{x: :x, y: :y})
          |> Plot.stat_density()
        end

      assert both.message ==
               "Plot.stat_density/3 maps :x, :y, but takes only one of them, since it runs " <>
                 "along one and computes the other"

      neither =
        assert_raise ArgumentError, fn ->
          @values
          |> Plot.new()
          |> Plot.geom_density()
        end

      assert neither.message =~ "one of :x, :y"
    end

    test "a weight that is not numbers, an unusable aesthetic or an unknown after_stat is refused" do
      plot = Plot.new(@values, %{x: :x})

      weight =
        assert_raise ArgumentError, fn -> Plot.geom_density(plot, %{weight: :s}) end

      assert weight.message =~ "a density spreads each row's weight"

      assert_raise ArgumentError, ~r/:size/, fn -> Plot.geom_density(plot, %{size: :y}) end

      for variable <- [:density, :count, :scaled, :ndensity, :wdensity, :n] do
        assert [_layer] =
                 Plot.geom_density(plot, %{y: {:after_stat, [variable]}}).reversed_layers
      end

      assert_raise ArgumentError, ~r/prop/, fn ->
        Plot.geom_density(plot, %{y: {:after_stat, [:prop]}})
      end

      assert_raise ArgumentError, ~r/:weight/, fn ->
        Plot.geom_density(plot, %{weight: {:after_stat, [:density]}})
      end
    end
  end

  describe "geom_hex/3 and stat_bin_hex/3" do
    @hex_values %{
      "x" => [1.0, 2.0, 4.0, 4.0],
      "y" => [1, 2, 3, 4],
      "w" => [1, 2, 1, 2],
      "s" => ~w(a b c d)
    }

    test "a hexagon layer records its geom, stat and position with ggplot2's defaults" do
      plot = Plot.new(@hex_values, %{x: :x, y: :y})

      expected = [
        %Plot.Layer{
          geom: %Geom.Hex{line_end: :butt, line_join: :mitre, mitre_limit: 10.0},
          stat: %Stat.BinHex{bins: {30, 30}, binwidth: :none},
          position: %Position.Identity{},
          data: :none,
          mapping: %{},
          fixed: %{},
          accepted: [:group, :weight, :x, :y, :alpha, :color, :fill, :linetype, :linewidth],
          annotation: false,
          inherit: true
        }
      ]

      assert Plot.geom_hex(plot).reversed_layers == expected
      assert Plot.stat_bin_hex(plot).reversed_layers == expected
    end

    test "bins and bin widths are one for both axes or a pair, each width kept as a float" do
      plot = Plot.new(@hex_values, %{x: :x, y: :y})

      [bins] = Plot.geom_hex(plot, bins: 10).reversed_layers
      assert bins.stat.bins == {10, 10}

      [pair] = Plot.stat_bin_hex(plot, bins: {10, 20}).reversed_layers
      assert pair.stat.bins == {10, 20}

      [one] = Plot.geom_hex(plot, bins: 1).reversed_layers
      assert one.stat.bins == {1, 1}

      [ones] = Plot.geom_hex(plot, bins: {1, 1}).reversed_layers
      assert ones.stat.bins == {1, 1}

      [width] = Plot.geom_hex(plot, binwidth: 2).reversed_layers
      assert width.stat.binwidth === {2.0, 2.0}

      [widths] = Plot.geom_hex(plot, binwidth: {0.1, 500}).reversed_layers
      assert widths.stat.binwidth === {0.1, 500.0}

      [whole] = Plot.geom_hex(plot, binwidth: {2, 500}).reversed_layers
      assert whole.stat.binwidth === {2.0, 500.0}
    end

    test "bins or bin widths not offered are refused" do
      plot = Plot.new(@hex_values, %{x: :x, y: :y})

      for bins <- [0, -1, 2.5, {0, 10}, {2.5, 10}, {10, 0}, {10}, {10, 20, 30}, [10, 20], "10"] do
        error =
          assert_raise NimbleOptions.ValidationError, ~r/a number of bins/, fn ->
            Plot.geom_hex(plot, bins: bins)
          end

        assert error.message =~ "got: #{inspect(bins)}"
      end

      for width <- [0, -0.5, {0, 1}, {"1", 1}, {1, 0}, {1, -1}, {1, 2, 3}, [1, 2], "1"] do
        error =
          assert_raise NimbleOptions.ValidationError, ~r/a bin width/, fn ->
            Plot.stat_bin_hex(plot, binwidth: width)
          end

        assert error.message =~ "got: #{inspect(width)}"
      end
    end

    test "a hexagon's look is set for every hexagon, and its borders' ends and corners chosen" do
      [layer] =
        @hex_values
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_hex(
          colour: "red",
          fill: "steelblue",
          alpha: 1,
          linewidth: 2,
          linetype: 2,
          lineend: :round,
          linejoin: :bevel,
          linemitre: 2
        )
        |> Map.fetch!(:reversed_layers)

      assert %Plot.Layer{
               geom: %Geom.Hex{line_end: :round, line_join: :bevel, mitre_limit: 2.0},
               fixed: %{
                 color: "#FF0000",
                 fill: "#4682B4",
                 alpha: 1.0,
                 linewidth: 2.0,
                 linetype: {4, 4}
               }
             } = layer

      plot = Plot.new(@hex_values, %{x: :x, y: :y})

      for join <- [:round, :mitre] do
        [joined] = Plot.geom_hex(plot, linejoin: join).reversed_layers
        assert joined.geom.line_join == join
      end
    end

    test "a layer missing x or y, a position, or an option not offered is refused" do
      for {function, name} <- [
            {&Plot.geom_hex/1, "geom_hex"},
            {&Plot.stat_bin_hex/1, "stat_bin_hex"}
          ],
          {mapping, missing} <- [{%{x: :x}, ":y"}, {%{y: :y}, ":x"}] do
        error =
          assert_raise ArgumentError, fn ->
            @hex_values
            |> Plot.new(mapping)
            |> function.()
          end

        assert error.message ==
                 "Plot.#{name}/3 needs #{missing}, but neither its mapping nor the plot's maps it"
      end

      assert_raise NimbleOptions.ValidationError, ~r/position/, fn ->
        @hex_values
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_hex(position: :identity)
      end
    end

    test "a weight that is not numbers, an unusable aesthetic or an unknown after_stat is refused" do
      plot = Plot.new(@hex_values, %{x: :x, y: :y})

      weight = assert_raise ArgumentError, fn -> Plot.geom_hex(plot, %{weight: :s}) end
      assert weight.message =~ "a weight is summed"

      assert [_layer] = Plot.geom_hex(plot, %{weight: :w}).reversed_layers

      assert_raise ArgumentError, ~r/:size/, fn -> Plot.geom_hex(plot, %{size: :y}) end

      for variable <- [:count, :density, :ncount, :ndensity] do
        assert [_layer] =
                 Plot.geom_hex(plot, %{fill: {:after_stat, [variable]}}).reversed_layers
      end

      for variable <- [:width, :height, :prop] do
        assert_raise ArgumentError, ~r/#{variable}/, fn ->
          Plot.geom_hex(plot, %{fill: {:after_stat, [variable]}})
        end
      end

      assert_raise ArgumentError, ~r/weight/, fn ->
        Plot.stat_bin_hex(plot, %{weight: {:after_stat, [:count]}})
      end
    end

    test "a mapping that is not a map, or options that are not a keyword list, are refused" do
      plot = Plot.new(@hex_values, %{x: :x, y: :y})

      for function <- [:geom_hex, :stat_bin_hex],
          {mapping, options} <- [{untyped(:x), []}, {%{}, untyped(:bins)}] do
        error =
          assert_raise FunctionClauseError, fn ->
            apply(Plot, function, [plot, mapping, options])
          end

        assert {error.module, error.function, error.arity} == {Plot, function, 3}
      end
    end
  end

  describe "geom_smooth/3 and stat_smooth/3" do
    @points %{
      "x" => [1, 2, 3, 4],
      "y" => [1.0, 3.0, 2.0, 4.0],
      "w" => [1, 2, 1, 2],
      "s" => ~w(a b c d)
    }

    test "a smooth layer records its geom and stat with ggplot2's defaults, and no method given" do
      plot =
        @points
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_smooth()

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Smooth{
                   se: true,
                   line_end: :butt,
                   line_join: :round,
                   mitre_limit: 10.0
                 },
                 stat: %Stat.Smooth{
                   method: :none,
                   se: true,
                   level: 0.95,
                   n: 80,
                   span: 0.75,
                   fullrange: false,
                   orientation: :x
                 },
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{},
                 fixed: %{},
                 accepted: [:group, :weight, :x, :y, :alpha, :color, :fill, :linetype, :linewidth],
                 annotation: false,
                 inherit: true
               }
             ]
    end

    test "stat_smooth/3 records what geom_smooth/3 does, its options in the geom and the stat" do
      options = [
        method: :loess,
        se: false,
        level: 0.9,
        n: 5,
        span: 1,
        fullrange: true,
        orientation: :y,
        lineend: :round,
        linejoin: :mitre,
        linemitre: 2
      ]

      plot = Plot.new(@points, %{x: :x, y: :y})
      [geom_layer] = Plot.geom_smooth(plot, options).reversed_layers
      [stat_layer] = Plot.stat_smooth(plot, options).reversed_layers

      assert geom_layer == stat_layer

      [bare] = Plot.stat_smooth(plot).reversed_layers
      assert bare.stat.method == :none

      [mapped] = Plot.stat_smooth(plot, %{weight: :w}).reversed_layers
      assert mapped.mapping == %{weight: "w"}

      assert %Plot.Layer{
               geom: %Geom.Smooth{
                 se: false,
                 line_end: :round,
                 line_join: :mitre,
                 mitre_limit: 2.0
               },
               stat: %Stat.Smooth{
                 method: :loess,
                 se: false,
                 level: 0.9,
                 n: 5,
                 span: 1.0,
                 fullrange: true,
                 orientation: :y
               }
             } = geom_layer

      assert geom_layer.stat.span === 1.0
    end

    test "a smooth's look is set for every curve, its colour resolved and its alpha a float" do
      plot =
        @points
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_smooth(
          method: :lm,
          colour: "red",
          fill: "steelblue",
          alpha: 1,
          linewidth: 2,
          linetype: 2
        )

      assert [
               %Plot.Layer{
                 fixed: %{
                   color: "#FF0000",
                   fill: "#4682B4",
                   alpha: 1.0,
                   linewidth: 2.0,
                   linetype: {4, 4}
                 }
               }
             ] = plot.reversed_layers
    end

    test "a level is a number above 0 and below 1, kept as a float" do
      plot = Plot.new(@points, %{x: :x, y: :y})

      assert [%Plot.Layer{stat: %Stat.Smooth{level: 0.5}}] =
               Plot.geom_smooth(plot, level: 0.5).reversed_layers

      for level <- [0, 0.0, 1, 1.0, 1.5, -0.1, "0.95"] do
        error =
          assert_raise NimbleOptions.ValidationError, ~r/above 0 and below 1/, fn ->
            Plot.geom_smooth(plot, level: level)
          end

        assert error.message =~ "got: #{inspect(level)}"
      end
    end

    test "a method, a count, an orientation or a flag not offered is refused" do
      plot = Plot.new(@points, %{x: :x, y: :y})

      error =
        assert_raise NimbleOptions.ValidationError, ~r/method/, fn ->
          Plot.geom_smooth(plot, method: :glm)
        end

      assert error.message =~ "[:lm, :loess, :gam]"

      for span <- [0, -0.5, "0.75"] do
        error =
          assert_raise NimbleOptions.ValidationError, ~r/a span, a number above 0/, fn ->
            Plot.geom_smooth(plot, span: span)
          end

        assert error.message =~ "got: #{inspect(span)}"
      end

      assert_raise NimbleOptions.ValidationError, ~r/:n option/, fn ->
        Plot.stat_smooth(plot, n: 0)
      end

      assert_raise NimbleOptions.ValidationError, ~r/orientation/, fn ->
        Plot.geom_smooth(plot, orientation: :z)
      end

      assert_raise NimbleOptions.ValidationError, ~r/fullrange/, fn ->
        Plot.geom_smooth(plot, fullrange: :yes)
      end
    end

    test "a smooth needs x and y, takes a weight, and refuses a band's ends" do
      plot = Plot.new(@points, %{x: :x})

      error = assert_raise ArgumentError, fn -> Plot.geom_smooth(plot, method: :lm) end
      assert error.message =~ "Plot.geom_smooth/3 needs :y"

      error = assert_raise ArgumentError, fn -> Plot.stat_smooth(plot, method: :lm) end
      assert error.message =~ "Plot.stat_smooth/3 needs :y"

      assert %Plot{} = Plot.geom_smooth(plot, %{y: :y, weight: :w}, method: :lm)

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_smooth(plot, %{y: :y, ymin: :y}, method: :lm)
        end

      assert error.message =~ ":ymin"
    end

    test "a weight column that is not numbers is refused at the call" do
      plot = Plot.new(@points, %{x: :x, y: :y})

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_smooth(plot, %{weight: :s}, method: :lm)
        end

      assert error.message =~ "Plot.geom_smooth/3 maps :weight to \"s\", a :string column"
      assert error.message =~ "a smooth weighs each row by its weight"
    end

    test "an after_stat reads the fit's values but no other stat's, and never the weight" do
      plot = Plot.new(@points, %{x: :x, y: :y})

      assert %Plot{} =
               Plot.geom_smooth(plot, %{alpha: {:after_stat, [:se]}}, method: :lm)

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_smooth(plot, %{alpha: {:after_stat, [:count]}}, method: :lm)
        end

      assert error.message =~ "count"

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_smooth(plot, %{weight: {:after_stat, [:se]}}, method: :lm)
        end

      assert error.message =~ ":weight"
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
                 annotation: false,
                 inherit: true
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

  describe "geom_tile/3" do
    test "a tile layer records its geom, the identity stat and position, and its set sizes" do
      plot =
        @rows
        |> Plot.new(%{x: :wt})
        |> Plot.geom_tile(%{y: :mpg}, width: 1, height: 2, colour: "red")

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Tile{},
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{y: "mpg"},
                 fixed: %{width: 1.0, height: 2.0, color: "#FF0000"},
                 accepted: [
                   :alpha,
                   :color,
                   :fill,
                   :group,
                   :height,
                   :linetype,
                   :linewidth,
                   :width,
                   :x,
                   :y
                 ],
                 annotation: false,
                 inherit: true
               }
             ]

      assert hd(plot.reversed_layers).fixed === %{width: 1.0, height: 2.0, color: "#FF0000"}
    end

    test "y mapped by neither the layer nor the plot is refused, naming the call" do
      plot = Plot.new(@rows, %{x: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_tile(plot) end

      assert error.message =~ "Plot.geom_tile/3 needs :y"
    end

    test "an aesthetic tiles cannot use is refused, naming the call" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_tile(plot, %{xmin: :wt}) end
      assert error.message =~ "Plot.geom_tile/3 cannot use :xmin"
    end

    # A width or height set at the call replaces a mapped one, so only a mapped one is checked.
    test "a mapped width or height that is not numbers is refused, a set one taking its place" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for size <- [:width, :height] do
        error = assert_raise ArgumentError, fn -> Plot.geom_tile(plot, %{size => :cyl}) end

        assert error.message ==
                 "Plot.geom_tile/3 maps #{inspect(size)} to \"cyl\", a :string column, but a " <>
                   "tile is drawn as #{if size == :width, do: "wide as its width", else: "tall as its height"}, " <>
                   "so it must be a number"

        assert [%Plot.Layer{}] =
                 Plot.geom_tile(plot, %{size => :cyl}, [{size, 1}]).reversed_layers
      end
    end

    test "a width or a height is set to a number, and nothing else" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert_raise NimbleOptions.ValidationError, ~r/expected a width, a number/, fn ->
        Plot.geom_tile(plot, width: "1")
      end

      assert_raise NimbleOptions.ValidationError,
                   ~r/expected a height, a number, got: :none$/,
                   fn ->
                     Plot.geom_tile(plot, height: :none)
                   end
    end

    test "a tile's look is checked and resolved at the call" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert [%Plot.Layer{fixed: fixed}] =
               Plot.geom_tile(plot, fill: "red", linewidth: 1, linetype: :dashed).reversed_layers

      assert fixed === %{fill: "#FF0000", linewidth: 1.0, linetype: {4, 4}}

      for {option, value} <- [fill: "reddish", linewidth: -1, linetype: :wavy] do
        assert_raise NimbleOptions.ValidationError, ~r/invalid value for :#{option} option/, fn ->
          Plot.geom_tile(plot, [{option, value}])
        end
      end
    end
  end

  describe "geom_raster/3" do
    test "a raster layer records its geom with its justification and interpolation" do
      plot =
        @rows
        |> Plot.new(%{x: :wt})
        |> Plot.geom_raster(%{y: :mpg}, hjust: 0, vjust: 1, interpolate: true, alpha: 0.5)

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: %Geom.Raster{hjust: 0.0, vjust: 1.0, interpolate: true},
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 data: :none,
                 mapping: %{y: "mpg"},
                 fixed: %{alpha: 0.5},
                 accepted: [:alpha, :fill, :group, :x, :y],
                 annotation: false,
                 inherit: true
               }
             ]

      assert [%Plot.Layer{geom: %Geom.Raster{hjust: hjust, vjust: vjust}}] =
               plot.reversed_layers

      assert {hjust, vjust} === {0.0, 1.0}
    end

    test "a raster is centred and blocky unless told otherwise" do
      assert [%Plot.Layer{geom: geom}] =
               @rows
               |> Plot.new(%{x: :wt, y: :mpg})
               |> Plot.geom_raster()
               |> Map.fetch!(:reversed_layers)

      assert geom === %Geom.Raster{hjust: 0.5, vjust: 0.5, interpolate: false}
    end

    test "y mapped by neither the layer nor the plot is refused, naming the call" do
      plot = Plot.new(@rows, %{x: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_raster(plot) end
      assert error.message =~ "Plot.geom_raster/3 needs :y"
    end

    test "a raster's fill is checked and resolved at the call" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert [%Plot.Layer{fixed: %{fill: "#FF0000"}}] =
               Plot.geom_raster(plot, fill: "red").reversed_layers

      assert_raise NimbleOptions.ValidationError, ~r/invalid value for :fill option/, fn ->
        Plot.geom_raster(plot, fill: "reddish")
      end
    end

    # ggplot2's raster ignores `colour`, so a raster takes none.
    test "a colour, mapped or set, is refused, and so is a justification past 0 to 1" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_raster(plot, %{colour: :cyl}) end
      assert error.message =~ "Plot.geom_raster/3 cannot use :color"

      assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:color\]/, fn ->
        Plot.geom_raster(plot, colour: "red")
      end

      assert_raise NimbleOptions.ValidationError, ~r/expected a number from 0 to 1/, fn ->
        Plot.geom_raster(plot, hjust: 1.5)
      end

      assert_raise NimbleOptions.ValidationError, ~r/invalid value for :interpolate/, fn ->
        Plot.geom_raster(plot, interpolate: :yes)
      end
    end
  end

  describe "geom_hline/3 and geom_vline/3" do
    # ggplot2 4.0.3's `geom_hline(yintercept = c(15, 25), colour = c("red", "blue"))` builds a
    # table of its own, maps `aes(yintercept = yintercept)`, sets each line's colour and takes
    # nothing from the plot's mapping; `lineend = "butt"`, the identity stat and position.
    test "lines given as values are an annotation of their own table, each look one per line" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
        |> Plot.geom_hline(yintercept: [15, 25], colour: ["red", "blue"], linewidth: 2)

      assert [
               %Plot.Layer{
                 geom: %Geom.Hline{line_end: :butt},
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 data: table,
                 mapping: %{yintercept: "yintercept"},
                 fixed: %{color: ["#FF0000", "#0000FF"], linewidth: 2.0},
                 accepted: [:alpha, :color, :group, :linetype, :linewidth, :yintercept],
                 annotation: true,
                 inherit: false
               }
             ] = plot.reversed_layers

      assert DataFrame.pull(table, "yintercept") === [15.0, 25.0]
    end

    # ggplot2 4.0.3's `geom_vline(aes(xintercept = wt), mean_wt)`: an ordinary layer of the table
    # it is given, `inherit.aes = FALSE`, so it takes no x from the plot's mapping.
    test "mapped lines are a layer of their table that takes nothing from the plot's mapping" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
        |> Plot.geom_vline(%{xintercept: :w}, data: %{"w" => [3.0]}, lineend: :round)

      assert [
               %Plot.Layer{
                 geom: %Geom.Vline{line_end: :round},
                 data: %_{},
                 mapping: %{xintercept: "w"},
                 fixed: %{},
                 accepted: [:alpha, :color, :group, :linetype, :linewidth, :xintercept],
                 annotation: false,
                 inherit: false
               } = layer
             ] = plot.reversed_layers

      assert Plot.computed_mapping(plot, layer) == %{xintercept: "w"}
    end

    test "a line's intercept is any position an axis takes, and its looks each one value or a list" do
      plot = Plot.new(@rows)
      instant = ~U[2020-01-01 05:30:00Z]

      for {value, kept} <- [
            {:infinity, :infinity},
            {"b", "b"},
            {~D[2020-01-05], ~D[2020-01-05]},
            {instant, instant},
            {~N[2020-01-01 05:30:00], ~N[2020-01-01 05:30:00]},
            {~T[05:30:00], ~T[05:30:00]}
          ] do
        assert [%Plot.Layer{data: table}] =
                 Plot.geom_vline(plot, xintercept: value).reversed_layers

        assert DataFrame.pull(table, "xintercept") === [kept]
      end

      assert [%Plot.Layer{fixed: %{linetype: [{4, 4}, nil], alpha: [0.5, 1.0]}}] =
               Plot.geom_hline(plot,
                 yintercept: [1, 2],
                 linetype: [:dashed, :blank],
                 alpha: [0.5, 1]
               ).reversed_layers
    end

    # ggplot2 4.0.3 warns "Ignoring `mapping` because `yintercept` was provided." and "Ignoring
    # `data`", and draws the lines the argument gives.
    test "lines given as values take no mapping and no table, which would draw nothing" do
      plot = Plot.new(@rows)

      mapping =
        assert_raise ArgumentError, fn ->
          Plot.geom_hline(plot, %{colour: :cyl}, yintercept: 20)
        end

      assert String.starts_with?(
               mapping.message,
               "Plot.geom_hline/3 draws the lines yintercept: gives, so it takes no mapping"
             )

      assert mapping.message =~ "got: %{colour: :cyl}"

      data =
        assert_raise ArgumentError, fn -> Plot.geom_vline(plot, xintercept: 2, data: @rows) end

      assert data.message ===
               "Plot.geom_vline/3 draws the lines xintercept: gives, so it takes no data:"
    end

    test "mapped lines take one value for each look, a list giving one per line only beside values" do
      plot = Plot.new(@rows)

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_hline(plot, %{yintercept: :mpg}, colour: ["red", "blue"])
        end

      assert String.starts_with?(error.message, "Plot.geom_hline/3 sets :color to")
      assert error.message =~ ~s(["#FF0000", "#0000FF"])
      assert error.message =~ "only beside yintercept:"
    end

    # ggplot2 4.0.3: "Aesthetics must be either length 1 or the same as the data (3)", and
    # "`geom_hline()` requires the following missing aesthetics: yintercept".
    test "lists of different lengths are refused, and so is a layer given no intercept" do
      plot = Plot.new(@rows, %{y: :mpg})

      lengths =
        assert_raise ArgumentError, fn ->
          Plot.geom_hline(plot, yintercept: [1, 2, 3], colour: ["red", "blue"])
        end

      assert String.starts_with?(
               lengths.message,
               "Plot.geom_hline/3 gives :yintercept 3 values and :color 2 values; an option " <>
                 "takes one value, or one per line, and these disagree on how many lines there are"
             )

      for {function, add, intercept} <- [
            {"geom_hline", &Plot.geom_hline/1, :yintercept},
            {"geom_vline", &Plot.geom_vline/1, :xintercept}
          ] do
        missing = assert_raise ArgumentError, fn -> add.(plot) end

        assert missing.message ===
                 "Plot.#{function}/3 needs #{inspect(intercept)}, but neither its mapping maps " <>
                   "it nor #{intercept}: gives it"
      end
    end

    test "a mapping that is not a map, or options that are not a keyword list, are refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for {add, name} <- [{&Plot.geom_hline/3, :geom_hline}, {&Plot.geom_vline/3, :geom_vline}],
          {mapping, options} <- [{untyped(:wt), []}, {%{}, untyped(:bottom)}] do
        error = assert_raise FunctionClauseError, fn -> add.(plot, mapping, options) end

        assert {error.module, error.function, error.arity} == {Plot, name, 3}
      end
    end

    test "a mapped line's columns are found in its own table, the plot's mapping never checked" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, colour: :cyl})

      assert [%Plot.Layer{}] =
               Plot.geom_hline(plot, %{yintercept: :level}, data: %{"level" => [1.0]}).reversed_layers

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_hline(plot, %{yintercept: :level}, data: %{"other" => [1.0]})
        end

      assert error.message =~ "the layer's own data has no column \"level\""
    end

    test "a line takes the options a reference line has, and no other" do
      plot = Plot.new(@rows)

      for option <- [arrow: true, position: :identity, size: 2, linejoin: :round, slope: 1] do
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.geom_hline(plot, [{:yintercept, 1} | [option]])
        end
      end

      assert_raise NimbleOptions.ValidationError, ~r/a date, a date-time or a time/, fn ->
        Plot.geom_vline(plot, xintercept: %{})
      end
    end
  end

  describe "geom_abline/3" do
    # ggplot2 4.0.3's `geom_abline(intercept = 37, slope = c(-5, -4))` builds a table of its own,
    # each intercept recycled to the slopes' count, and maps `aes(intercept = intercept, slope =
    # slope)`, taking nothing from the plot's mapping.
    test "lines given as values are an annotation of their own table, each look one per line" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
        |> Plot.geom_abline(intercept: 37, slope: [-5, -4], colour: ["red", "blue"])

      assert [
               %Plot.Layer{
                 geom: %Geom.Abline{line_end: :butt},
                 stat: %Stat.Identity{},
                 position: %Position.Identity{},
                 data: table,
                 mapping: %{intercept: "intercept", slope: "slope"},
                 fixed: %{color: ["#FF0000", "#0000FF"]},
                 accepted: [:alpha, :color, :group, :intercept, :linetype, :linewidth, :slope],
                 annotation: true,
                 inherit: false
               }
             ] = plot.reversed_layers

      assert {DataFrame.pull(table, "intercept"), DataFrame.pull(table, "slope")} ===
               {[37.0, 37.0], [-5.0, -4.0]}
    end

    # ggplot2 4.0.3: given nothing, `slope = 1, intercept = 0`; given either, the other's default.
    test "given neither value nor a mapping, the line is y = x, and either value takes the other's default" do
      plot = Plot.new(@rows)

      for {options, intercepts, slopes} <- [
            {[], [0.0], [1.0]},
            {[slope: 2], [0.0], [2.0]},
            {[intercept: 30, lineend: :round], [30.0], [1.0]}
          ] do
        assert [%Plot.Layer{data: table, annotation: true}] =
                 Plot.geom_abline(plot, options).reversed_layers

        assert {DataFrame.pull(table, "intercept"), DataFrame.pull(table, "slope")} ===
                 {intercepts, slopes}
      end
    end

    test "mapped lines are a layer of their table that takes nothing from the plot's mapping" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
        |> Plot.geom_abline(%{intercept: :a, slope: :b},
          data: %{"a" => [30.0], "b" => [-2]},
          lineend: :square
        )

      assert [
               %Plot.Layer{
                 geom: %Geom.Abline{line_end: :square},
                 data: %_{},
                 mapping: %{intercept: "a", slope: "b"},
                 annotation: false,
                 inherit: false
               } = layer
             ] = plot.reversed_layers

      assert Plot.computed_mapping(plot, layer) == %{intercept: "a", slope: "b"}
    end

    # ggplot2 4.0.3 warns "Ignoring `mapping` because `slope` and/or `intercept` were provided.",
    # and "Ignoring `data`" beside them or given alone, drawing y = x.
    test "lines given as values take no mapping and no table, and nor does the line y = x" do
      plot = Plot.new(@rows)

      mapping =
        assert_raise ArgumentError, fn ->
          Plot.geom_abline(plot, %{intercept: :wt}, slope: 2)
        end

      assert mapping.message ===
               "Plot.geom_abline/3 draws the lines slope: gives, so it takes no mapping, got: " <>
                 "%{intercept: :wt}"

      for {given, named} <- [{[intercept: 2], "intercept:"}, {[slope: 2], "slope:"}] do
        data =
          assert_raise ArgumentError, fn -> Plot.geom_abline(plot, [{:data, @rows} | given]) end

        assert data.message ===
                 "Plot.geom_abline/3 draws the lines #{named} gives, so it takes no data:"
      end

      alone = assert_raise ArgumentError, fn -> Plot.geom_abline(plot, data: @rows) end

      assert alone.message ===
               "Plot.geom_abline/3 given no mapping, intercept: or slope: draws the line y = x, " <>
                 "so it takes no data:; map :intercept and :slope to draw lines from the table"
    end

    # ggplot2 4.0.3: "`geom_abline()` requires the following missing aesthetics: slope", and
    # "Can't recycle `intercept` (size 2) to size 3".
    test "a mapped line needs both its intercept and its slope, and lists must agree in length" do
      plot = Plot.new(@rows)

      missing =
        assert_raise ArgumentError, fn ->
          Plot.geom_abline(plot, %{intercept: :a}, data: %{"a" => [1.0]})
        end

      assert missing.message ===
               "Plot.geom_abline/3 needs :slope, but neither its mapping maps it nor intercept: " <>
                 "or slope: gives it"

      looks =
        assert_raise ArgumentError, fn ->
          Plot.geom_abline(plot, %{intercept: :wt, slope: :mpg}, linewidth: [1, 2])
        end

      assert looks.message =~ "only beside intercept: or slope:"

      lengths =
        assert_raise ArgumentError, fn ->
          Plot.geom_abline(plot, intercept: [1, 2], slope: [1, 2, 3])
        end

      assert String.starts_with?(lengths.message, "Plot.geom_abline/3 gives :intercept 2 values")
    end

    # ggplot2 4.0.3 fails drawing: "non-numeric argument to binary operator", for a string
    # intercept, a mapped string slope or a date intercept alike.
    test "an intercept or slope must be a number, given or mapped" do
      plot = Plot.new(@rows)

      for value <- ["a", ~D[2020-01-03], :infinity, nil] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.geom_abline(plot, intercept: value)
          end

        assert error.message =~ "expected a number, or a list of them, got: #{inspect(value)}"
      end

      assert_raise NimbleOptions.ValidationError, ~r/expected a number/, fn ->
        Plot.geom_abline(plot, slope: [1, "steep"])
      end

      error =
        assert_raise ArgumentError, fn ->
          Plot.geom_abline(plot, %{intercept: :mpg, slope: :cyl})
        end

      assert error.message ===
               "Plot.geom_abline/3 maps :slope to \"cyl\", a :string column, but a line is " <>
                 "drawn at y = intercept + slope * x, so it must be a number"

      intercept =
        assert_raise ArgumentError, fn ->
          Plot.geom_abline(plot, %{intercept: :cyl, slope: :mpg})
        end

      assert intercept.message ===
               "Plot.geom_abline/3 maps :intercept to \"cyl\", a :string column, but a line " <>
                 "is drawn at y = intercept + slope * x, so it must be a number"
    end

    test "a line takes the options a reference line has, and no other" do
      plot = Plot.new(@rows)

      for option <- [arrow: true, position: :identity, size: 2, linejoin: :round, yintercept: 1] do
        assert_raise NimbleOptions.ValidationError, fn -> Plot.geom_abline(plot, [option]) end
      end
    end

    test "a mapping that is not a map, or options that are not a keyword list, are refused" do
      plot = Plot.new(@rows)

      for {mapping, options} <- [{untyped(:wt), []}, {%{}, untyped(:bottom)}] do
        error =
          assert_raise FunctionClauseError, fn -> Plot.geom_abline(plot, mapping, options) end

        assert {error.module, error.function, error.arity} == {Plot, :geom_abline, 3}
      end
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
               annotation: true,
               inherit: false
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
               %Geom.Path{line_end: :round, line_join: :round, mitre_limit: 10.0, arrow: :none},
               %Geom.Line{
                 orientation: :y,
                 line_end: :butt,
                 line_join: :round,
                 mitre_limit: 10.0,
                 arrow: :none
               },
               %Geom.Rect{}
             ]
    end

    test "a geom it does not draw with is refused, naming the geoms it does" do
      plot = Plot.new(@rows)

      error = assert_raise ArgumentError, fn -> Plot.annotate(plot, :curve, x: 1, y: 1) end

      assert error.message =~
               ":point, :col, :bar, :path, :line, :segment, :rug, :linerange, :pointrange, " <>
                 ":errorbar, :crossbar, :text, :label or :rect, got: :curve"
    end

    # ggplot2 4.0.3 warns "`geom` must not be \"hline\". Please use `geom_hline()` directly
    # instead."
    test "a reference line is refused, naming the function that draws it" do
      plot = Plot.new(@rows)

      for geom <- [:abline, :hline, :vline] do
        error = assert_raise ArgumentError, fn -> Plot.annotate(plot, geom, x: 1) end

        assert error.message ===
                 "Plot.annotate/3 does not draw #{inspect(geom)}: a reference line annotates on " <>
                   "its own, so use Plot.geom_#{geom}/3, whose options give its lines as values"
      end
    end

    # ggplot2 4.0.3 warns "Ignoring unknown aesthetics: xmin", and the x axis still reaches it;
    # "Ignoring unknown parameters: `label`" for a rectangle; and ignores `nudge_x`, as an
    # annotation is not nudged, and a label's `check_overlap`, which its geom lacks.
    test "an option its geom does not take is refused, naming it" do
      plot = Plot.new(@rows)

      for {geom, options, refused} <- [
            {:text, [x: 1, y: 1, label: "a", xmin: 0], ":xmin"},
            {:rect, [xmin: 1, xmax: 2, ymin: 1, ymax: 2, label: "a"], ":label"},
            {:text, [x: 1, y: 1, label: "a", nudge_x: 1], ":nudge_x"},
            {:label, [x: 1, y: 1, label: "a", nudge_y: 1], ":nudge_y"},
            {:label, [x: 1, y: 1, label: "a", check_overlap: true], ":check_overlap"},
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

      assert label.message =~
               "Plot.annotate/3 needs :label, but the :text annotation is given no value for it"

      position = assert_raise ArgumentError, fn -> Plot.annotate(plot, :text, label: "a") end
      assert position.message =~ "Plot.annotate/3 needs :x, :y"
    end

    # ggplot2 4.0.3 takes a list of each of these, one per annotation: `annotate("label", x = 1:2,
    # y = 1, label = "a", border.colour = c("red", "blue"))` borders the first red and the second
    # blue. Giggly sets them once for the layer, as `geom_text/3` and `geom_label/3` do.
    test "an aesthetic or a colour its geom sets once for the layer takes one value, not a list" do
      plot = Plot.new(@rows)

      for {geom, option} <- [
            text: :size,
            label: :size,
            label: :angle,
            label: :border_color,
            label: :text_color
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.annotate(plot, geom, [{:x, [1, 2]}, {:y, 1}, {:label, "a"}, {option, [3, 5]}])
          end

        assert error.key == option
      end
    end

    test "a label annotation records its geom with its box, and its look per annotation" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg, fill: :cyl})
        |> Plot.annotate(:label,
          x: [2, 3],
          y: 25,
          label: ["a", "b"],
          fill: ["pink", :none],
          colour: [:none, "red"],
          linewidth: [0, 1],
          linetype: [:dashed, :blank],
          size: 5,
          label_r: 0,
          border_colour: "blue"
        )

      [layer] = plot.reversed_layers

      assert %Plot.Layer{
               geom: %Geom.Label{
                 label_padding: %{
                   top: {0.25, :lines},
                   right: {0.25, :lines},
                   bottom: {0.25, :lines},
                   left: {0.25, :lines}
                 },
                 label_r: {+0.0, :points},
                 border_color: "#0000FF",
                 text_color: :color
               },
               stat: %Stat.Identity{},
               position: %Position.Identity{},
               mapping: %{x: "x", y: "y"},
               accepted: [:alpha, :color, :fill, :group, :label, :linetype, :linewidth, :x, :y],
               annotation: true
             } = layer

      assert layer.fixed === %{
               label: ["a", "b"],
               fill: ["#FFC0CB", nil],
               color: [nil, "#FF0000"],
               linewidth: [+0.0, 1.0],
               linetype: [{4, 4}, nil],
               size: 5.0
             }
    end

    # ggplot2 4.0.3's `annotate()` counts annotations over every option with `lengths()`, so a
    # `margin()` padding counts four: `annotate("label", x = 1, y = 2, label = "a", label.padding =
    # margin(1, 2, 3, 4))` has four rows, one label drawn four times, and beside two labels
    # "Unequal parameter lengths: x (2), label (2), and label.padding (4)". Giggly counts a
    # padding as one value, whatever its sides.
    test "a label's padding is one value for every label, however many sides it gives" do
      plot = Plot.new(@rows)
      padding = [top: 1, right: 2, bottom: 3, left: 4]

      for {places, labels} <- [{1, "a"}, {[1, 2], ["a", "b"]}] do
        frame =
          plot
          |> Plot.annotate(:label, x: places, y: 2, label: labels, label_padding: padding)
          |> Giggly.layer_data()

        assert DataFrame.pull(frame, :label) == List.wrap(labels)
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

    # ggplot2 4.0.3: `annotate("segment", x = 1:2, y = 0, xend = 3, yend = 1, linetype =
    # c("dashed", "dotted"))` draws two segments, each in its own line type, where a path's line
    # type cannot change along it.
    test "a segment annotation takes a line type per annotation, and no mitre limit" do
      plot = Plot.new(@rows)

      [layer] =
        plot
        |> Plot.annotate(:segment, x: [1, 2], y: 0, xend: 3, yend: 1, linetype: [:dashed, 3])
        |> Map.fetch!(:reversed_layers)

      assert %Plot.Layer{
               geom: %Geom.Segment{line_end: :butt, line_join: :round, arrow: :none},
               mapping: %{x: "x", y: "y", xend: "xend", yend: "yend"},
               fixed: %{linetype: [{4, 4}, {1, 3}]}
             } = layer

      assert_raise NimbleOptions.ValidationError, fn ->
        Plot.annotate(plot, :segment, x: 1, y: 0, xend: 3, linemitre: 4)
      end
    end

    # ggplot2 4.0.3: `annotate("rug", y = c(1.5, 3.5), sides = "r", outside = TRUE, linewidth =
    # c(1, 2))` draws a line out from the right for each, each as wide as its own.
    test "a rug annotation takes its positions, sides, length and way out, and a width for each" do
      [layer] =
        @rows
        |> Plot.new()
        |> Plot.annotate(:rug,
          y: [1.5, 3.5],
          sides: [:right],
          length: {2, :in},
          outside: true,
          linewidth: [1, 2]
        )
        |> Map.fetch!(:reversed_layers)

      assert %Plot.Layer{
               geom: %Geom.Rug{
                 sides: [:right],
                 length: {144.0, :points},
                 outside: true,
                 line_end: :butt
               },
               mapping: %{y: "y"},
               fixed: %{linewidth: [1.0, 2.0]},
               annotation: true,
               inherit: false
             } = layer

      plot = Plot.new(@rows)
      error = assert_raise ArgumentError, fn -> Plot.annotate(plot, :rug, sides: [:top]) end

      assert error.message =~
               "Plot.annotate/3 needs one of :x, :y, but the :rug annotation is given no value"
    end

    # ggplot2 4.0.3: `layer_data(ggplot() + annotate("col", x = 1, y = 3, width = c(0.5, 0.8)))`
    # has two rows, xmin 0.75 and 0.6, xmax 1.25 and 1.4.
    test "a list of bar widths counts annotations as a position's list does" do
      frame =
        @rows
        |> Plot.new()
        |> Plot.annotate(:col, x: 1, y: 3, width: [0.5, 0.8])
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :xmin) === [0.75, 0.6]
      assert DataFrame.pull(frame, :xmax) === [1.25, 1.4]
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

  describe "position_dodge2/1" do
    test "a padding outside 0 to 1, a preserve it does not know and a width are refused" do
      for {options, key, message} <- [
            {[padding: 1.5], :padding, "expected a fraction from 0 to 1, got: 1.5"},
            {[padding: -0.1], :padding, "expected a fraction from 0 to 1, got: -0.1"},
            {[padding: "0.1"], :padding, ~s(expected a fraction from 0 to 1, got: "0.1")},
            {[preserve: :both], :preserve, "expected one of [:total, :single], got: :both"},
            {[width: 0.5], [:width], "unknown options [:width]"}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Plot.position_dodge2(options) end

        assert error.key == key
        assert error.message =~ message
      end
    end

    test "a padding is kept as a float, 0 and 1 included" do
      assert Enum.map([0, 1], fn padding -> Plot.position_dodge2(padding: padding).padding end) ===
               [0.0, 1.0]
    end
  end

  describe "position_jitter/1" do
    test "a distance not given is left to the data, and the seed is 0 unless given" do
      assert Plot.position_jitter() === %Position.Jitter{width: :none, height: :none, seed: 0}

      assert Plot.position_jitter(width: 0, height: 2, seed: 12) ===
               %Position.Jitter{width: 0.0, height: 2.0, seed: 12}
    end

    # ggplot2 takes a negative distance and moves nothing by it, a seed of 1.5 as 1, and one
    # written as text with a warning.
    test "a negative distance and a seed that is not an integer are refused" do
      for {options, key, message} <- [
            {[width: -1], :width, "expected a distance, a number 0 or more, got: -1"},
            {[height: -0.5], :height, "expected a distance, a number 0 or more, got: -0.5"},
            {[seed: 1.5], :seed, "invalid value for :seed option: expected integer, got: 1.5"},
            {[seed: nil], :seed, "expected integer, got: nil"}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Plot.position_jitter(options) end

        assert error.key == key
        assert error.message =~ message
      end
    end
  end

  # The labeller a facet records when given none, as `labeller: :value`: each value alone, labelling
  # both sides, a strip for each column.
  @value_labeller %{
    rows: {:value, %{}},
    cols: {:value, %{}},
    columns: %{},
    default: {:value, %{}},
    multi_line: true
  }

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
               scales: :fixed,
               labeller: @value_labeller
             }
    end

    test "one column needs no list, an option not given is recorded as :none, and scales as given" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.facet_wrap(:cyl, nrow: 3, scales: :free_y)

      assert plot.facet == %Facet.Wrap{
               facets: ["cyl"],
               nrow: 3,
               ncol: :none,
               scales: :free_y,
               labeller: @value_labeller
             }
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 facets `ggplot(df) + geom_point(data = df2)` by a column only
    # df2 has; whether some table has every column is checked when the plot is run.
    test "a column the plot's data lacks is taken, since a layer's own table may hold it" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.facet_wrap(:gear)

      assert plot.facet.facets == ["gear"]
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

    test "a labeller given alone is recorded as the labeller of both sides, with its options" do
      plot = Plot.new(@rows)
      capitalize = fn label -> String.capitalize(label) end
      lookup = %{"4" => "four"}

      recorded =
        Enum.map(
          [
            :both,
            {:both, sep: "=", multi_line: false},
            {:context, []},
            :wrap,
            {:wrap, width: 10, multi_line: false},
            capitalize,
            lookup
          ],
          fn labeller -> Plot.facet_wrap(plot, :cyl, labeller: labeller).facet.labeller end
        )

      assert recorded == [
               %{@value_labeller | rows: {:both, %{sep: ": "}}, cols: {:both, %{sep: ": "}}},
               %{
                 @value_labeller
                 | rows: {:both, %{sep: "="}},
                   cols: {:both, %{sep: "="}},
                   multi_line: false
               },
               %{@value_labeller | rows: {:context, %{}}, cols: {:context, %{}}},
               %{@value_labeller | rows: {:wrap, %{width: 25}}, cols: {:wrap, %{width: 25}}},
               %{
                 @value_labeller
                 | rows: {:wrap, %{width: 10}},
                   cols: {:wrap, %{width: 10}},
                   multi_line: false
               },
               %{@value_labeller | rows: capitalize, cols: capitalize},
               %{@value_labeller | rows: lookup, cols: lookup}
             ]
    end

    test "a keyword list of labellers is recorded with each column's by its name, a side not " <>
           "given as :none" do
      plot = Plot.new(@rows)
      lookup = %{"4" => "four"}

      by_column =
        Plot.facet_wrap(plot, [:cyl, :wt],
          labeller: [columns: %{:cyl => :both, "wt" => lookup}, default: :context]
        )

      by_side =
        Plot.facet_wrap(plot, :cyl, labeller: [cols: {:both, sep: "="}, multi_line: false])

      assert by_column.facet.labeller == %{
               rows: :none,
               cols: :none,
               columns: %{"cyl" => {:both, %{sep: ": "}}, "wt" => lookup},
               default: {:context, %{}},
               multi_line: true
             }

      assert by_side.facet.labeller == %{
               rows: :none,
               cols: {:both, %{sep: "="}},
               columns: %{},
               default: {:value, %{}},
               multi_line: false
             }
    end

    test "a labeller it cannot use is refused by the option's validation, saying why" do
      plot = Plot.new(@rows)

      for {labeller, message} <- [
            {:label_both, "a keyword list of labellers, got: :label_both"},
            {{:both, [1]}, "a keyword list of labellers, got: {:both, [1]}"},
            {{:bogus, sep: "="}, ~s(a keyword list of labellers, got: {:bogus, [sep: "="]})},
            {["cyl"], ~s(a keyword list of labellers, got: ["cyl"])},
            {{:context, sep: "="}, "unknown options [:sep]"},
            {{:wrap, width: 0}, "invalid value for :width option: expected positive integer"},
            {{:wrap, width: 2.5}, "got: 2.5"},
            {[cols: {:wrap, multi_line: false}], "unknown options [:multi_line]"},
            {%{4 => "four"}, ~s(the labels to show, got: %{4 => "four"})},
            {%{"4" => "four", 6 => "six"}, "expected a map of labels to the labels to show"},
            {[rows: :both, cols: :value], "labelled by rows: or cols:, not both"},
            {[default: {:both, multi_line: false}], "unknown options [:multi_line]"},
            {[columns: [{:cyl, :both}, {"cyl", :value}]], ~s(got "cyl" twice)},
            {[columns: [cyl: :label_both]],
             ~s(the labeller of "cyl": expected :value, :both, :context or :wrap,)},
            {[columns: [:cyl]], "expected a column and its labeller, got: :cyl"},
            {[columns: :cyl], "expected a keyword list or a map of a labeller for each column"}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.facet_wrap(plot, :cyl, labeller: labeller)
          end

        assert error.key == :labeller
        assert error.message =~ message
      end
    end

    test "a labeller labelling every strip, and the faceting column apart, is refused" do
      plot = Plot.new(@rows)

      for side <- [:rows, :cols] do
        error =
          assert_raise ArgumentError, fn ->
            Plot.facet_wrap(plot, [:wt, :cyl], labeller: [{side, :both}, columns: [cyl: :value]])
          end

        assert String.starts_with?(
                 error.message,
                 "Plot.facet_wrap/3's labeller labels every strip with #{side}:"
               )

        assert error.message =~ ~s(columns: cannot also label "cyl")
      end

      labelled_apart = Plot.facet_wrap(plot, :cyl, labeller: [columns: [cyl: :value]])
      assert labelled_apart.facet.labeller.columns == %{"cyl" => {:value, %{}}}
    end
  end

  describe "coord_cartesian/2" do
    test "cartesian coordinates clip each panel unless told not to, replacing radial ones" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.coord_radial()

      assert Plot.coord_cartesian(plot).coord == %Coord.Cartesian{clip: :on}
      assert Plot.coord_cartesian(plot, clip: :off).coord == %Coord.Cartesian{clip: :off}
    end

    # ggplot2 4.0.3 builds `coord_cartesian(clip = "bogus")`, and grid fails as it draws it:
    # "invalid 'clip' value". grid's `"inherit"` draws byte for byte as `"off"` does, so Giggly
    # takes no second name for `:off`.
    test "a clip that is not :on or :off, or an option it does not take, is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      for {option, value} <- [clip: :inherit, clip: true, clip: "off", xlim: {1, 2}] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.coord_cartesian(plot, [{option, value}])
          end

        assert error.key in [option, [option]]
      end
    end

    test "options that are not a keyword list are refused by its own clause" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error =
        assert_raise FunctionClauseError, fn ->
          Plot.coord_cartesian(plot, untyped(%{clip: :off}))
        end

      assert {error.module, error.function, error.arity} == {Plot, :coord_cartesian, 2}
    end
  end

  describe "facet_grid/2" do
    test "a plot records the grid facet with each side's columns by their names in the data" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.facet_grid(rows: [:cyl, "wt"], cols: :mpg, scales: :free_x)

      assert plot.facet == %Facet.Grid{
               rows: ["cyl", "wt"],
               cols: ["mpg"],
               scales: :free_x,
               labeller: @value_labeller
             }
    end

    test "each of the scales' settings is recorded as given" do
      plot = Plot.new(@rows)

      assert Enum.map([:fixed, :free_x, :free_y, :free], fn scales ->
               Plot.facet_grid(plot, rows: :cyl, scales: scales).facet.scales
             end) == [:fixed, :free_x, :free_y, :free]
    end

    test "a side left out splits on no columns, and the scales are fixed unless given" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.facet_grid(cols: :cyl)

      assert plot.facet == %Facet.Grid{
               rows: [],
               cols: ["cyl"],
               scales: :fixed,
               labeller: @value_labeller
             }
    end

    test "no column on either side is refused" do
      plot = Plot.new(@rows)

      for options <- [[], [rows: [], cols: []]] do
        error = assert_raise ArgumentError, fn -> Plot.facet_grid(plot, options) end
        assert error.message =~ "Plot.facet_grid/2 needs a column to facet by"
      end
    end

    test "a column named twice, on one side or on both, is refused" do
      plot = Plot.new(@rows)

      error = assert_raise ArgumentError, fn -> Plot.facet_grid(plot, rows: :cyl, cols: "cyl") end
      assert error.message =~ "Plot.facet_grid/2"
      assert error.message =~ ~s(:cyl, "cyl")
      assert error.message =~ ~s(column "cyl" more than once)

      assert_raise ArgumentError, ~r/more than once/, fn ->
        Plot.facet_grid(plot, rows: [:cyl, :wt, :cyl])
      end
    end

    test "a labeller is recorded as facet_wrap/3 records one, a side each" do
      plot = Plot.new(@rows)

      recorded =
        Enum.map([:both, [rows: :both, cols: :value]], fn labeller ->
          Plot.facet_grid(plot, rows: :cyl, cols: :wt, labeller: labeller).facet.labeller
        end)

      assert recorded == [
               %{@value_labeller | rows: {:both, %{sep: ": "}}, cols: {:both, %{sep: ": "}}},
               %{@value_labeller | rows: {:both, %{sep: ": "}}, cols: {:value, %{}}}
             ]
    end

    test "a labeller labelling a side, and a column of that side apart, is refused" do
      plot = Plot.new(@rows)

      error =
        assert_raise ArgumentError, fn ->
          Plot.facet_grid(plot,
            rows: :cyl,
            cols: :wt,
            labeller: [rows: :both, columns: [cyl: :value]]
          )
        end

      assert String.starts_with?(
               error.message,
               "Plot.facet_grid/2's labeller labels every strip of the rows with rows:"
             )

      assert error.message =~ ~s(columns: cannot also label "cyl")

      assert_raise ArgumentError, ~r/every strip of the columns with cols:/, fn ->
        Plot.facet_grid(plot,
          rows: :cyl,
          cols: :wt,
          labeller: [cols: :both, columns: [wt: :value]]
        )
      end

      # A column of the other side is its own to label.
      labelled =
        Plot.facet_grid(plot,
          rows: :cyl,
          cols: :wt,
          labeller: [rows: :both, columns: [wt: :value]]
        )

      assert labelled.facet.labeller.columns == %{"wt" => {:value, %{}}}
    end

    test "a value that is not a column reference, or a scales that is not one, is refused" do
      plot = Plot.new(@rows)

      assert_raise NimbleOptions.ValidationError, fn -> Plot.facet_grid(plot, rows: 4) end
      assert_raise NimbleOptions.ValidationError, fn -> Plot.facet_grid(plot, cols: [:cyl, 4]) end

      assert_raise NimbleOptions.ValidationError, fn ->
        Plot.facet_grid(plot, rows: :cyl, scales: :free_z)
      end
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
        |> Plot.scale_y_continuous(labels: :none, expand: [mult: {1, 2}, add: 2])

      assert plot.scales === %{
               x: %Scale.Continuous{
                 name: "Weight",
                 limits: {2.0, nil},
                 breaks: [2.0, 3.5],
                 minor_breaks: :none,
                 labels: labeller
               },
               y: %Scale.Continuous{labels: :none, expand: [mult: {1.0, 2.0}, add: {2.0, 2.0}]}
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

    test "a list of labels takes nil for a missing one, and nothing but strings beside it" do
      plot = Plot.new(@rows)

      assert Plot.scale_x_continuous(plot, labels: ["a", nil], breaks: [1, 2]).scales.x.labels ===
               ["a", nil]

      assert Plot.scale_x_discrete(plot, labels: %{"4" => nil}).scales.x.labels === %{"4" => nil}

      assert_raise NimbleOptions.ValidationError,
                   ~r/expected a list of strings or nil, got: 1 in it/,
                   fn -> Plot.scale_x_continuous(plot, labels: ["a", 1], breaks: [1, 2]) end

      assert_raise NimbleOptions.ValidationError,
                   ~r/expected each label a string or nil, got: :four/,
                   fn -> Plot.scale_x_discrete(plot, labels: %{"4" => :four}) end
    end
  end

  describe "a breaks function and n_breaks: on the scale functions" do
    test "breaks: and minor_breaks: take a function of one argument or two, as R counts them" do
      plot = Plot.new(@rows)
      one = fn _limits -> [] end
      two = fn _limits, _second -> [] end

      recorded = [
        Plot.scale_x_continuous(plot, breaks: one, minor_breaks: two).scales.x,
        Plot.scale_x_log10(plot, breaks: two, minor_breaks: one).scales.x,
        Plot.scale_x_date(plot, breaks: one, minor_breaks: two).scales.x,
        Plot.scale_x_datetime(plot, breaks: two, minor_breaks: one).scales.x,
        Plot.scale_x_time(plot, breaks: one, minor_breaks: two).scales.x,
        Plot.scale_x_discrete(plot, breaks: one, minor_breaks: two).scales.x,
        Plot.scale_color_continuous(plot, breaks: two).scales.color,
        Plot.scale_color_binned(plot, breaks: one).scales.color,
        Plot.scale_color_discrete(plot, breaks: one).scales.color
      ]

      assert Enum.map(recorded, fn scale -> {scale.breaks, Map.get(scale, :minor_breaks)} end) ===
               [
                 {one, two},
                 {two, one},
                 {one, two},
                 {two, one},
                 {one, two},
                 {one, two},
                 {two, :default},
                 {one, nil},
                 {one, :default}
               ]

      three = fn _limits, _second, _third -> [] end

      for call <- [
            fn -> Plot.scale_x_continuous(plot, breaks: three) end,
            fn -> Plot.scale_x_date(plot, minor_breaks: three) end,
            fn -> Plot.scale_x_datetime(plot, breaks: three) end,
            fn -> Plot.scale_x_time(plot, breaks: three) end,
            fn -> Plot.scale_x_discrete(plot, minor_breaks: three) end,
            fn -> Plot.scale_color_binned(plot, breaks: three) end
          ] do
        error = assert_raise NimbleOptions.ValidationError, call
        assert error.message =~ "a function of one or two arguments"
      end
    end

    test "a discrete axis records its minor breaks as floats, its values' places" do
      plot = Plot.new(@rows)

      assert {Plot.scale_x_discrete(plot, minor_breaks: [1, 2.5]).scales.x.minor_breaks,
              Plot.scale_y_discrete(plot, minor_breaks: :none).scales.y.minor_breaks,
              Plot.scale_x_discrete(plot).scales.x.minor_breaks} === {[1.0, 2.5], :none, :default}
    end

    test "a list of labels may stand beside a breaks function, its count checked when run" do
      plot = Plot.new(@rows)
      breaker = fn _limits -> [1, 2] end

      assert {Plot.scale_x_continuous(plot, breaks: breaker, labels: ["a", "b"]).scales.x.labels,
              Plot.scale_color_binned(plot, breaks: breaker, labels: ["a"]).scales.color.labels} ===
               {["a", "b"], ["a"]}
    end

    test "n_breaks: is recorded on the continuous scale functions, and not on dates or times" do
      plot = Plot.new(@rows)

      assert {Plot.scale_x_continuous(plot, n_breaks: 10).scales.x.n_breaks,
              Plot.scale_y_sqrt(plot, n_breaks: 3).scales.y.n_breaks,
              Plot.scale_size_continuous(plot, n_breaks: 4).scales.size.n_breaks,
              Plot.scale_x_continuous(plot).scales.x.n_breaks} === {10, 3, 4, :default}

      for call <- [
            fn -> Plot.scale_x_date(plot, n_breaks: 10) end,
            fn -> Plot.scale_x_datetime(plot, n_breaks: 10) end,
            fn -> Plot.scale_x_time(plot, n_breaks: 10) end
          ] do
        error = assert_raise NimbleOptions.ValidationError, call
        assert error.key == [:n_breaks]
      end
    end

    # R warns and ignores `n.breaks` beside a function with no `n` argument, and ignores it
    # silently beside a list or NULL.
    test "n_breaks: beside breaks that want no number is refused at the call" do
      plot = Plot.new(@rows)

      for {call, shown} <- [
            {fn -> Plot.scale_x_continuous(plot, n_breaks: 3, breaks: [1, 2]) end, "[1, 2]"},
            {fn -> Plot.scale_x_log10(plot, n_breaks: 3, breaks: :none) end, ":none"},
            {fn -> Plot.scale_color_continuous(plot, n_breaks: 3, breaks: fn _ -> [] end) end,
             "#Function"},
            {fn -> Plot.scale_fill_binned(plot, n_breaks: 3, breaks: [1]) end, "[1]"}
          ] do
        error = assert_raise ArgumentError, call
        assert String.starts_with?(error.message, "Plot.scale_")
        assert error.message =~ "is given n_breaks: beside breaks: #{shown}"
        assert error.message =~ "which wants no number of breaks"
      end

      two = fn _limits, _wanted -> [] end

      assert {Plot.scale_x_continuous(plot, n_breaks: 1, breaks: two).scales.x.n_breaks,
              Plot.scale_x_log10(plot, n_breaks: 1).scales.x.n_breaks,
              Plot.scale_fill_binned(plot, breaks: [1]).scales.fill.breaks} === {1, 1, [1.0]}
    end

    test "one break wanted of the breaks the scale chooses is refused but on a log axis" do
      plot = Plot.new(@rows)

      for call <- [
            fn -> Plot.scale_x_continuous(plot, n_breaks: 1) end,
            fn -> Plot.scale_y_reverse(plot, n_breaks: 1) end,
            fn -> Plot.scale_alpha_continuous(plot, n_breaks: 1) end
          ] do
        error = assert_raise ArgumentError, call
        assert String.starts_with?(error.message, "Plot.scale_")

        assert error.message =~
                 "/2 is given n_breaks: 1, and the breaks it chooses need 2 or more"
      end

      assert Plot.scale_x_continuous(plot, transform: :log10, n_breaks: 1).scales.x.n_breaks === 1
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
            {:expand, [mult: "a"], ~s([mult: "a"])},
            {:breaks, fn _limits, _wanted -> [] end, "a function of one argument, or :none"},
            {:minor_breaks, ["a"], ~s(got: "a" in it)}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.scale_x_discrete(plot, [{key, value}])
          end

        assert {error.key, error.message =~ shown} == {key, true}
      end
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

  describe "scale_x_datetime/2 and scale_y_datetime/2" do
    test "a date-time scale function records an untrained date-time scale, its zone unsettled" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.scale_x_datetime(
          name: "At",
          limits: {~U[2024-03-10 06:00:00Z], nil},
          breaks: [~U[2024-03-10 12:00:00Z]],
          labels: ["noon"],
          minor_breaks: :none,
          expand: [mult: 0]
        )
        |> Plot.scale_y_datetime(limits: {nil, ~N[2024-03-10 18:00:00]})

      assert plot.scales === %{
               x: %Scale.Continuous{
                 transform: {:datetime, :default, Calendar.UTCOnlyTimeZoneDatabase},
                 name: "At",
                 limits: {~U[2024-03-10 06:00:00Z], nil},
                 breaks: [~U[2024-03-10 12:00:00Z]],
                 labels: ["noon"],
                 minor_breaks: :none,
                 expand: [mult: {0.0, 0.0}, add: {0.0, 0.0}]
               },
               y: %Scale.Continuous{
                 transform: {:datetime, :default, Calendar.UTCOnlyTimeZoneDatabase},
                 limits: {nil, ~N[2024-03-10 18:00:00]}
               }
             }
    end

    test "a date-time scale function given no options records the default date-time scale" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.scale_x_datetime()
        |> Plot.scale_y_datetime()

      transform = {:datetime, :default, Calendar.UTCOnlyTimeZoneDatabase}

      assert plot.scales === %{
               x: %Scale.Continuous{transform: transform},
               y: %Scale.Continuous{transform: transform}
             }
    end

    # scale_x_datetime(timezone = "America/New_York"): R puts the zone on the scale, and the time
    # zone database that reads it is passed beside it, never read from config; with no zone, the
    # first column settles it, and with no database, the standard library's, knowing UTC alone.
    test "a time zone and its database are recorded on the scale's transformation" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.scale_x_datetime(
          timezone: "America/New_York",
          time_zone_database: Tz.TimeZoneDatabase
        )
        |> Plot.scale_y_datetime(time_zone_database: Tz.TimeZoneDatabase)

      utc =
        @rows
        |> Plot.new()
        |> Plot.scale_x_datetime(timezone: "Etc/UTC")

      assert {plot.scales.x.transform, plot.scales.y.transform, utc.scales.x.transform} ===
               {{:datetime, "America/New_York", Tz.TimeZoneDatabase},
                {:datetime, :default, Tz.TimeZoneDatabase},
                {:datetime, "Etc/UTC", Calendar.UTCOnlyTimeZoneDatabase}}
    end

    test "a time zone its database does not know is refused at the call, naming both" do
      plot = Plot.new(@rows)

      kolkata =
        assert_raise ArgumentError, fn ->
          Plot.scale_x_datetime(plot, timezone: "Asia/Kolkata")
        end

      mars =
        assert_raise ArgumentError, fn ->
          Plot.scale_y_datetime(plot,
            timezone: "Mars/Olympus_Mons",
            time_zone_database: Tz.TimeZoneDatabase
          )
        end

      for {error, shown} <- [
            {kolkata,
             [
               ~s(Plot.scale_x_datetime/2 was given timezone: "Asia/Kolkata"),
               "Calendar.UTCOnlyTimeZoneDatabase does not know",
               "time_zone_database:",
               "Tz.TimeZoneDatabase"
             ]},
            {mars,
             [
               ~s(Plot.scale_y_datetime/2 was given timezone: "Mars/Olympus_Mons"),
               "Tz.TimeZoneDatabase does not know"
             ]}
          ],
          datum <- shown do
        assert error.message =~ datum
      end
    end

    test "a date-time scale's transformation is the one a scale of date-times gets by default" do
      assert Plot.Options.datetime_transform() === Scale.new(:datetime).transform
      assert Plot.Options.datetime_transform() === Scale.new(:naive_datetime).transform
    end

    test "a step under a day, or longer, records a width, and a format the labels it writes" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.scale_x_datetime(date_breaks: [hour: 6], date_minor_breaks: [minute: 30])
        |> Plot.scale_y_datetime(date_labels: "%H:%M %Z", breaks: :none)

      stepped = fn step ->
        @rows
        |> Plot.new()
        |> Plot.scale_x_datetime(date_breaks: step)
        |> Map.fetch!(:scales)
        |> Map.fetch!(:x)
      end

      seconds = stepped.(second: 15)
      weeks = stepped.(week: 1)
      longer = Enum.map([[day: 2], [month: 1], [year: 1]], fn step -> stepped.(step).breaks end)

      transform = {:datetime, :default, Calendar.UTCOnlyTimeZoneDatabase}

      assert longer === [{:width, [day: 2]}, {:width, [month: 1]}, {:width, [year: 1]}]

      assert {plot.scales, seconds.breaks, weeks.breaks} === {
               %{
                 x: %Scale.Continuous{
                   transform: transform,
                   breaks: {:width, [hour: 6]},
                   minor_breaks: {:width, [minute: 30]}
                 },
                 y: %Scale.Continuous{
                   transform: transform,
                   labels: {:format, "%H:%M %Z"},
                   breaks: :none
                 }
               },
               {:width, [second: 15]},
               {:width, [week: 1]}
             }
    end

    test "an option given beside its date_ twin is refused" do
      plot = Plot.new(@rows)

      for {options, named} <- [
            {[breaks: [~U[2024-03-10 00:00:00Z]], date_breaks: [hour: 1]],
             ":breaks and :date_breaks"},
            {[labels: :none, date_labels: "%H"], ":labels and :date_labels"},
            {[minor_breaks: :none, date_minor_breaks: [minute: 15]],
             ":minor_breaks and :date_minor_breaks"}
          ] do
        error = assert_raise ArgumentError, fn -> Plot.scale_x_datetime(plot, options) end
        assert error.message =~ "Plot.scale_x_datetime/2 is given both #{named}"
      end

      unbroken =
        assert_raise ArgumentError, fn ->
          Plot.scale_y_datetime(plot, labels: ["a"], date_breaks: [hour: 1])
        end

      assert unbroken.message =~ ~r/^Plot\.scale_y_datetime\/2 .* 1 labels.* has none/
    end

    # A date-time's directives (%H, %z, %Z, %f) are written, a format Calendar.strftime/3 lacks,
    # such as R's %W, is refused at the call with its own reason; a naive date-time names no
    # instant, so it is refused beside one that does.
    test "an option a date-time scale cannot take is refused, naming it and what was wrong" do
      plot = Plot.new(@rows)
      zoned = ~U[2024-03-10 06:00:00Z]
      naive = ~N[2024-03-10 06:00:00]

      for {key, value, shown} <- [
            {:limits, {zoned, 3}, "got: {~U[2024-03-10 06:00:00Z], 3}"},
            {:limits, {~D[2024-03-10], nil}, "each a DateTime, a NaiveDateTime or nil"},
            {:limits, {zoned, naive},
             "got both in the limits {~U[2024-03-10 06:00:00Z], ~N[2024-03-10 06:00:00]}"},
            {:breaks, [zoned, naive], "got both in the list"},
            {:breaks, [zoned, ~D[2024-03-10]], "got: ~D[2024-03-10] in it"},
            {:breaks, zoned, "got: ~U[2024-03-10 06:00:00Z]"},
            {:minor_breaks, [1.5], "got: 1.5 in it"},
            {:date_breaks, [hours: 1], "got: [hours: 1]"},
            {:date_breaks, [hour: 0], "got: [hour: 0]"},
            {:date_breaks, [second: 0.5], "got: [second: 0.5]"},
            {:date_breaks, [hour: 1, minute: 30], "got: [hour: 1, minute: 30]"},
            {:date_breaks, [microsecond: 500], "got: [microsecond: 500]"},
            {:date_minor_breaks, "30 mins", ~s(got: "30 mins")},
            {:date_labels, "%W", ~s(got: "%W", which it cannot: #{strftime_refusal("%W")})},
            {:date_labels, 4, "expected a format, a string, got: 4"},
            {:timezone, :utc, "expected string, got: :utc"},
            {:time_zone_database, "Tz.TimeZoneDatabase", ~s(expected atom, got: "Tz.)}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.scale_x_datetime(plot, [{key, value}])
          end

        assert {error.key, error.message =~ shown} == {key, true}
      end

      for format <- ["%H:%M:%S", "%z", "%Z", "%f"] do
        assert Plot.scale_x_datetime(plot, date_labels: format).scales.x.labels ===
                 {:format, format}
      end
    end
  end

  describe "scale_x_time/2 and scale_y_time/2" do
    test "a time scale function records an untrained time scale with the options given" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.scale_x_time(
          name: "At",
          limits: {~T[06:00:00], nil},
          breaks: [~T[12:00:00]],
          labels: ["noon"],
          minor_breaks: :none,
          expand: [mult: 0]
        )
        |> Plot.scale_y_time()

      assert plot.scales === %{
               x: %Scale.Continuous{
                 transform: :time,
                 name: "At",
                 limits: {~T[06:00:00], nil},
                 breaks: [~T[12:00:00]],
                 labels: ["noon"],
                 minor_breaks: :none,
                 expand: [mult: {0.0, 0.0}, add: {0.0, 0.0}]
               },
               y: Scale.new(:time)
             }
    end

    test "a step of seconds, minutes or hours records a width, and a format the labels it writes" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.scale_x_time(date_breaks: [hour: 6], date_minor_breaks: [minute: 30])
        |> Plot.scale_y_time(date_labels: "%I:%M %p", date_breaks: [second: 15])

      assert plot.scales === %{
               x: %Scale.Continuous{
                 transform: :time,
                 breaks: {:width, [hour: 6]},
                 minor_breaks: {:width, [minute: 30]}
               },
               y: %Scale.Continuous{
                 transform: :time,
                 breaks: {:width, [second: 15]},
                 labels: {:format, "%I:%M %p"}
               }
             }
    end

    test "an option given beside its date_ twin is refused" do
      plot = Plot.new(@rows)

      error =
        assert_raise ArgumentError, fn ->
          Plot.scale_x_time(plot, labels: :none, date_labels: "%H")
        end

      unbroken =
        assert_raise ArgumentError, fn ->
          Plot.scale_y_time(plot, labels: ["a"], date_breaks: [hour: 1])
        end

      assert error.message =~ "Plot.scale_x_time/2 is given both :labels and :date_labels"
      assert unbroken.message =~ ~r/^Plot\.scale_y_time\/2 .* 1 labels.* has none/
    end

    # ggplot2 takes "1 day" and longer on a time axis, which can mark only 00:00:00 and 24:00:00
    # there, as [hour: 24] does; a time of day has no date, so a format writing one is refused at
    # the call, where R writes 1970-01-01.
    test "an option a time scale cannot take is refused, naming it and what was wrong" do
      plot = Plot.new(@rows)

      for {key, value, shown} <- [
            {:limits, {~T[06:00:00], 3}, "got: {~T[06:00:00], 3}"},
            {:limits, {~N[2024-03-10 06:00:00], nil}, "each a time of day or nil"},
            {:breaks, [~T[06:00:00], ~U[2024-03-10 06:00:00Z]], "got: ~U[2024-03-10 06:00:00Z]"},
            {:breaks, ~T[06:00:00], "or :none, got: ~T[06:00:00]"},
            {:minor_breaks, [1.5], "got: 1.5 in it"},
            {:date_breaks, [day: 1], "got: [day: 1]"},
            {:date_breaks, [week: 1], "one of :second, :minute and :hour"},
            {:date_breaks, [hour: 0], "got: [hour: 0]"},
            {:date_breaks, [minute: 1.5], "got: [minute: 1.5]"},
            {:date_breaks, [hour: 1, minute: 30], "got: [hour: 1, minute: 30]"},
            {:date_minor_breaks, "30 mins", ~s(got: "30 mins")},
            {:date_labels, "%Y-%m-%d", ~s(got: "%Y-%m-%d", which it cannot: key :year not found)},
            {:date_labels, 4, "expected a format, a string, got: 4"}
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.scale_x_time(plot, [{key, value}])
          end

        assert {error.key, error.message =~ shown} == {key, true}
      end

      for format <- ["%H:%M:%S", "%I %p", "%f"] do
        assert Plot.scale_x_time(plot, date_labels: format).scales.x.labels === {:format, format}
      end
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

    # ggplot2 4.0.3's `limits.POSIXct()` makes a date-time scale and sorts its ends.
    test "two date-times give a date-time scale those limits, in either order, an end nil" do
      plot = Plot.new(@rows)
      transform = {:datetime, :default, Calendar.UTCOnlyTimeZoneDatabase}

      assert Plot.xlim(plot, ~U[2024-03-10 12:00:00Z], ~U[2024-03-10 06:00:00Z]).scales.x ===
               %Scale.Continuous{
                 transform: transform,
                 limits: {~U[2024-03-10 12:00:00Z], ~U[2024-03-10 06:00:00Z]}
               }

      assert Plot.ylim(plot, nil, ~N[2024-03-10 06:00:00]).scales.y ===
               %Scale.Continuous{transform: transform, limits: {nil, ~N[2024-03-10 06:00:00]}}

      assert Plot.lims(plot, x: {~N[2024-03-10 06:00:00], nil}).scales.x ===
               %Scale.Continuous{transform: transform, limits: {~N[2024-03-10 06:00:00], nil}}

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.xlim(plot, ~U[2024-03-10 06:00:00Z], ~N[2024-03-10 12:00:00])
        end

      assert error.message =~ "got both in the limits"
    end

    # R's `xlim("I1", "IF")` takes any number of values as separate arguments; Elixir has no
    # such call, so a discrete axis's limits are one list, and two strings are refused naming it.
    # ggplot2 4.0.3's `xlim()` fails on two `hms` values ("no applicable method for 'limits'").
    test "two strings, a date beside a number, two times or no values are refused" do
      plot = Plot.new(@rows)

      for {limit, shown} <- [
            {fn -> Plot.xlim(plot, "I1", "IF") end,
             ~s(or a list of a discrete axis's values, got: {"I1", "IF"})},
            {fn -> Plot.ylim(plot, ~D[2026-10-01], 4) end, "each a date or nil"},
            {fn -> Plot.xlim(plot, ~T[06:00:00], ~T[18:00:00]) end,
             "scale_x_time(plot, limits: {low, high}), got: {~T[06:00:00], ~T[18:00:00]}"},
            {fn -> Plot.lims(plot, y: {nil, ~T[18:00:00]}) end, "expected no times of day"},
            {fn -> Plot.xlim(plot, ~T[06:00:00], nil) end, "expected no times of day"},
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
            {&Plot.scale_alpha_discrete/2, [na_value: 2], "got: 2"},
            {&Plot.scale_color_viridis_d/2, [option: :D], "expected one of [:magma, :inferno, "},
            {&Plot.scale_fill_viridis_c/2, [option: "plasma"], ~s(got: "plasma")},
            {&Plot.scale_color_viridis_c/2, [begin: 1.5],
             "a place in the palette, from 0, its start, to 1, its end, got: 1.5"},
            {&Plot.scale_fill_viridis_d/2, [end: -1], "got: -1"},
            {&Plot.scale_color_viridis_d/2, [begin: "a"], ~s(got: "a")},
            {&Plot.scale_color_viridis_d/2, [direction: 0], "expected one of [1, -1], got: 0"},
            {&Plot.scale_fill_viridis_d/2, [alpha: 2], "from 0 to 1, got: 2"},
            {&Plot.scale_color_viridis_c/2, [alpha: 0.5], "unknown options [:alpha]"}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> function.(plot, options) end
        assert error.message =~ shown
      end
    end

    # Golden: the defaults of ggplot2 4.0.3's `scale_colour_viridis_d()` and
    # `scale_colour_viridis_c()`, read with `args()` in R 4.6.1, `pal_viridis()`'s: alpha 1, begin
    # 0, end 1, direction 1, option "D", viridis; the discrete scale's missing colour
    # `discrete_scale()`'s `NA`, the continuous one's grey50; and the continuous gradient through
    # `viridisLite::viridis(6)`, #440154, #414487, #2A788E, #22A884, #7AD151 and #FDE725.
    test "a viridis scale records its palette, R's defaults, and an ordered factor's default" do
      plot = Plot.new(@rows)
      viridis = %{option: :viridis, begin: 0.0, end: 1.0, direction: 1, alpha: 1.0}

      discrete = %Scale.Discrete{palette: {:viridis, viridis}, guide: :legend, na_value: :none}

      continuous = %Scale.Continuous{
        palette: {:gradient, ["#440154", "#414487", "#2A788E", "#22A884", "#7AD151", "#FDE725"]},
        guide: :colorbar,
        na_value: "#7F7F7F"
      }

      assert {Plot.scale_color_viridis_d(plot).scales.color,
              Plot.scale_fill_viridis_d(plot).scales.fill,
              Plot.scale_color_viridis_c(plot).scales.color,
              Plot.scale_fill_viridis_c(plot).scales.fill} ===
               {discrete, discrete, continuous, continuous}

      assert {discrete, discrete} === {Scale.new(:ordinal, :color), Scale.new(:ordinal, :fill)}
    end

    # Golden: `viridisLite::viridis(6, begin = 0.2, end = 0.9, direction = -1, option = "magma")`
    # in R 4.6.1, the gradient `scale_colour_viridis_c()` runs through with those options.
    test "a viridis scale records the options it is given, as floats" do
      plot = Plot.new(@rows)

      discrete =
        Plot.scale_fill_viridis_d(plot,
          option: :cividis,
          begin: 0,
          end: 1,
          direction: -1,
          alpha: 0
        )

      continuous =
        Plot.scale_color_viridis_c(plot,
          option: :magma,
          begin: 0.2,
          end: 0.9,
          direction: -1,
          na_value: "red"
        )

      assert {discrete.scales.fill.palette, continuous.scales.color} ===
               {{:viridis, %{option: :cividis, begin: 0.0, end: 1.0, direction: -1, alpha: 0.0}},
                %Scale.Continuous{
                  palette:
                    {:gradient,
                     ["#FECE91", "#FC8C63", "#E44F64", "#AD347C", "#742181", "#3B0F70"]},
                  guide: :colorbar,
                  na_value: "#FF0000"
                }}
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
            {&Plot.scale_color_viridis_d/2, "scale_color_viridis_d", discrete},
            {&Plot.scale_fill_viridis_d/2, "scale_fill_viridis_d", discrete},
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
            {&Plot.scale_color_viridis_c/2, "scale_color_viridis_c", continuous},
            {&Plot.scale_fill_viridis_c/2, "scale_fill_viridis_c", continuous},
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
  # Golden: the defaults of ggplot2 4.0.3's `scale_colour_brewer()` and `scale_colour_distiller()`,
  # read with `args()` in R 4.6.1: type "seq" and palette 1, Blues; the brewer's direction 1 and
  # missing colour `discrete_scale()`'s `NA`; the distiller's direction -1, missing colour grey50
  # and colour bar, its gradient through `pal_brewer()(7)`. `pal_brewer()` numbers each type's
  # palettes as `Scales.Palette.brewer_palettes/1` lists them, and its colours are the package's,
  # which its tests pin to R's.
  describe "the brewer and distiller scale functions" do
    test "each records an untrained scale of its palette, its guide and its missing value" do
      plot = Plot.new(@rows)
      blues = {:brewer, %{palette: "Blues", direction: 1}}
      discrete = %Scale.Discrete{palette: blues, guide: :legend, na_value: :none}
      reversed = Scales.Palette.discrete({:brewer, %{palette: "Blues", direction: -1}}, 7)

      continuous = %Scale.Continuous{
        palette: {:gradient, reversed},
        guide: :colorbar,
        na_value: "#7F7F7F"
      }

      assert {Plot.scale_color_brewer(plot).scales.color,
              Plot.scale_fill_brewer(plot).scales.fill,
              Plot.scale_color_distiller(plot).scales.color,
              Plot.scale_fill_distiller(plot).scales.fill} ===
               {discrete, discrete, continuous, continuous}
    end

    # As ggplot2 4.0.3's `pal_brewer()` reads a number among `type`'s palettes and a name alone in
    # R 4.6.1: `type = "div", palette = "Set1"` gives Set1; `scale_colour_distiller()` warns of a
    # qualitative palette and takes it.
    test "a palette is named, or numbered among its type's, which a name leaves unread" do
      plot = Plot.new(@rows)
      brewer = fn options -> Plot.scale_fill_brewer(plot, options).scales.fill.palette end

      assert {brewer.(type: :qual, palette: 2), brewer.(type: :div, palette: 9),
              brewer.(palette: 18),
              brewer.(type: :div, palette: "Set1", direction: -1, na_value: "red")} ===
               {{:brewer, %{palette: "Dark2", direction: 1}},
                {:brewer, %{palette: "Spectral", direction: 1}},
                {:brewer, %{palette: "YlOrRd", direction: 1}},
                {:brewer, %{palette: "Set1", direction: -1}}}

      distilled =
        Plot.scale_color_distiller(plot,
          type: :qual,
          palette: 8,
          direction: 1,
          values: [0, 0.5, 1],
          na_value: :none
        ).scales.color

      set3 = Scales.Palette.discrete({:brewer, %{palette: "Set3", direction: 1}}, 7)

      assert {distilled.palette, distilled.na_value} ===
               {{:gradient, set3, [0.0, 0.5, 1.0]}, :none}
    end

    test "a number past the last of its type's palettes is refused at the call, naming the function" do
      plot = Plot.new(@rows)

      for {call, shown} <- [
            {fn -> Plot.scale_color_brewer(plot, type: :qual, palette: 9) end,
             "Plot.scale_color_brewer/2 is given palette: 9, but ColorBrewer's :qual palettes " <>
               "number 8: Accent, Dark2, Paired, Pastel1, Pastel2, Set1, Set2, Set3"},
            {fn -> Plot.scale_fill_brewer(plot, palette: 19) end,
             "Plot.scale_fill_brewer/2 is given palette: 19, but ColorBrewer's :seq palettes " <>
               "number 18"},
            {fn -> Plot.scale_color_distiller(plot, type: :div, palette: 10) end,
             "Plot.scale_color_distiller/2 is given palette: 10, but ColorBrewer's :div"},
            {fn -> Plot.scale_fill_distiller(plot, palette: 19) end,
             "Plot.scale_fill_distiller/2 is given palette: 19"}
          ] do
        error = assert_raise ArgumentError, call
        assert error.message =~ shown
      end
    end

    # R's `palette = "set1"` warns and gives Greens, `palette = 1.5` is palette 1, `values =
    # c(0, NA, 1)` drops the `NA`, and too few values fail once the plot is built.
    test "an option a brewer or distiller scale cannot take is refused, naming what was wrong" do
      plot = Plot.new(@rows)

      for {function, options, shown} <- [
            {&Plot.scale_color_brewer/2, [palette: "set1"],
             ~s(a ColorBrewer palette's name, one of ["Blues", "BuGn")},
            {&Plot.scale_color_brewer/2, [palette: "set1"], ~s(counting from 1, got: "set1")},
            {&Plot.scale_fill_brewer/2, [palette: 0], "got: 0"},
            {&Plot.scale_color_distiller/2, [palette: 1.5], "got: 1.5"},
            {&Plot.scale_fill_distiller/2, [palette: :Set1], "got: :Set1"},
            {&Plot.scale_color_brewer/2, [type: :sequential],
             "expected one of [:seq, :div, :qual], got: :sequential"},
            {&Plot.scale_fill_brewer/2, [direction: 0], "expected one of [1, -1], got: 0"},
            {&Plot.scale_color_distiller/2, [direction: 0], "expected one of [1, -1], got: 0"},
            {&Plot.scale_color_brewer/2, [values: [0, 1]], "unknown options [:values]"},
            {&Plot.scale_fill_distiller/2, [values: [0, nil, 1]],
             "expected a list of numbers, got: [0, nil, 1]"},
            {&Plot.scale_color_distiller/2, [values: []], "a list of numbers, got: []"},
            {&Plot.scale_color_distiller/2, [values: 0.5], "a list of numbers, got: 0.5"},
            {&Plot.scale_color_gradientn/2, [colors: ["red"], values: ["a", "b"]],
             ~s(got: ["a", "b"])},
            {&Plot.scale_fill_gradientn/2, [colors: ["red"], values: [0.5]],
             "at least two different places, since the colours are blended between them, " <>
               "got: [0.5]"},
            {&Plot.scale_color_gradientn/2, [colors: ["red"], values: [0.5, 0.5]],
             "got: [0.5, 0.5]"}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> function.(plot, options) end
        assert error.message =~ shown
      end
    end

    # As ggplot2 4.0.3's `scale_colour_discrete(palette = "set1")` and
    # `scale_colour_continuous(palette = "Blues")` take scales' palette by name, in any case, in R
    # 4.6.1, and `palette = "red"` fails there ("Unknown palette: red"), a list of one is colours
    # here.
    test "palette: names a palette scales knows, in any case, or lists colours" do
      plot = Plot.new(@rows)
      color = fn function, options -> function.(plot, options).scales.color.palette end
      fill = fn function, options -> function.(plot, options).scales.fill.palette end

      named = &Scales.Palette.named/1

      assert {color.(&Plot.scale_color_discrete/2, palette: "set1"),
              fill.(&Plot.scale_fill_discrete/2, palette: "Viridis"),
              color.(&Plot.scale_color_discrete/2, palette: ["red"]),
              color.(&Plot.scale_color_continuous/2, palette: "Blues"),
              fill.(&Plot.scale_fill_continuous/2, palette: "GREY"),
              fill.(&Plot.scale_fill_gradientn/2, colors: ["red", "blue"], values: [1, 0])} ===
               {named.("Set1"), named.("viridis"), {:manual, ["#FF0000"]}, named.("Blues"),
                named.("grey"), {:gradient, ["#FF0000", "#0000FF"], [1.0, 0.0]}}

      for {function, options, shown} <- [
            {&Plot.scale_color_discrete/2, [palette: "red"], ~s(scales names no palette "red")},
            {&Plot.scale_fill_continuous/2, [palette: "Okabe-Ito"],
             ~s(no palette "Okabe-Ito"; its names, in any case, are "Blues")},
            {&Plot.scale_color_discrete/2, [palette: :Set1],
             "a palette's name or a list of at least one colour, got: :Set1"},
            {&Plot.scale_fill_continuous/2, [palette: []],
             "a palette's name or a list of at least one colour, got: []"}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> function.(plot, options) end
        assert error.message =~ shown
      end
    end
  end

  # Golden: the defaults of ggplot2 4.0.3's binned colour scale functions, read in R 4.6.1:
  # `scale_colour_binned()`'s gradient from "#132B43" to "#56B1F7" at each bin's middle, or
  # `pal_binned(as_discrete_pal(palette))` for a palette given; `_steps()` the same gradient,
  # `_steps2()` the diverging one through `rescale_mid()` at 0, `_stepsn()` `pal_gradient_n()`
  # through its colours, `_viridis_b()` `pal_binned(pal_viridis())` and `_fermenter()`
  # `pal_binned(pal_brewer("seq", 1, -1))`, Blues reversed; each colour steps, grey50 for a
  # missing value, and `binned_scale()`'s `n.breaks` (five nice breaks), `nice.breaks = TRUE`,
  # `right = TRUE` and `show.limits = FALSE`.
  describe "the binned colour scale functions" do
    test "each records an untrained binned scale of its palette, colour steps and grey50" do
      plot = Plot.new(@rows)
      gradient = %Scale.Binned{}

      steps2 = %Scale.Binned{
        palette: {:gradient, ["#832424", "#FFFFFF", "#3A3A98"]},
        rescaler: {:mid, 0.0}
      }

      viridis =
        {:binned, {:viridis, %{option: :viridis, begin: 0.0, end: 1.0, direction: 1, alpha: 1.0}}}

      assert {Plot.scale_color_binned(plot).scales.color,
              Plot.scale_fill_binned(plot).scales.fill, Plot.scale_color_steps(plot).scales.color,
              Plot.scale_fill_steps(plot).scales.fill, Plot.scale_color_steps2(plot).scales.color,
              Plot.scale_fill_steps2(plot).scales.fill} ===
               {gradient, gradient, gradient, gradient, steps2, steps2}

      fermenter = %Scale.Binned{palette: {:binned, {:brewer, %{palette: "Blues", direction: -1}}}}

      assert {Plot.scale_color_stepsn(plot, colors: ["red", "blue"]).scales.color,
              Plot.scale_fill_viridis_b(plot).scales.fill,
              Plot.scale_color_fermenter(plot).scales.color,
              Plot.scale_fill_fermenter(plot).scales.fill} ===
               {%Scale.Binned{palette: {:gradient, ["#FF0000", "#0000FF"]}},
                %Scale.Binned{palette: viridis}, fermenter, fermenter}
    end

    test "each records its palette's options and the binned scale's" do
      plot = Plot.new(@rows)

      binned_options = [
        name: "Power",
        limits: {400, 0},
        breaks: [100, 200],
        labels: ["a", "b"],
        nice_breaks: false,
        right: false,
        na_value: "red",
        guide: :legend
      ]

      recorded =
        Plot.scale_fill_steps2(plot, [low: "black", mid: "grey", midpoint: 150] ++ binned_options).scales.fill

      assert recorded ===
               %Scale.Binned{
                 palette: {:gradient, ["#000000", "#808080", "#3A3A98"]},
                 rescaler: {:mid, 150.0},
                 name: "Power",
                 limits: {400.0, 0.0},
                 breaks: [100.0, 200.0],
                 labels: ["a", "b"],
                 n_breaks: 5,
                 nice_breaks: false,
                 right: false,
                 na_value: "#FF0000",
                 guide: :legend
               }

      palette = fn function, options ->
        [scale] = Map.values(function.(plot, options).scales)
        scale
      end

      assert {palette.(&Plot.scale_color_binned/2, palette: "blues").palette,
              palette.(&Plot.scale_fill_binned/2, palette: ["red", "blue"]).palette,
              palette.(&Plot.scale_color_steps/2, low: "white", high: "black").palette,
              palette.(&Plot.scale_fill_stepsn/2, colors: ["red", "blue"], values: [1, 0]).palette,
              palette.(&Plot.scale_color_viridis_b/2,
                option: :magma,
                begin: 0.2,
                end: 0.8,
                direction: -1,
                alpha: 0.5
              ).palette,
              palette.(&Plot.scale_fill_fermenter/2, type: :qual, palette: 2, direction: 1).palette,
              palette.(&Plot.scale_color_binned/2, show_limits: true).show_limits} ===
               {{:binned, Scales.Palette.named("Blues")},
                {:binned, {:manual, ["#FF0000", "#0000FF"]}}, {:gradient, ["#FFFFFF", "#000000"]},
                {:gradient, ["#FF0000", "#0000FF"], [1.0, 0.0]},
                {:binned,
                 {:viridis, %{option: :magma, begin: 0.2, end: 0.8, direction: -1, alpha: 0.5}}},
                {:binned, {:brewer, %{palette: "Dark2", direction: 1}}}, true}
    end

    # R 4.6.1: `scale_colour_binned(n.breaks = 1)` fails once built ("'from' must be of length
    # 1"), as `labeling::extended()` finds no sequence for one break, but takes it beside
    # `nice.breaks = FALSE` or given breaks, which leave it unread; `show.limits = TRUE` beside a
    # character vector of labels warns and is ignored.
    test "one nice break wanted, or shown limits beside a list of labels, are refused at the call" do
      plot = Plot.new(@rows)

      for {call, shown} <- [
            {fn -> Plot.scale_color_binned(plot, n_breaks: 1) end,
             "Plot.scale_color_binned/2 is given n_breaks: 1, and nice breaks need 2 or more " <>
               "wanted; give nice_breaks: false for one break at the middle of the limits"},
            {fn ->
               Plot.scale_fill_fermenter(plot,
                 show_limits: true,
                 breaks: [100, 200],
                 labels: ["a", "b"]
               )
             end,
             "Plot.scale_fill_fermenter/2 is given show_limits: true beside a list of labels, " <>
               "which labels the breaks alone; add the limits to breaks: and labels:, or give " <>
               "labels: a function"},
            {fn -> Plot.scale_color_steps(plot, labels: ["a", "b"]) end,
             "Plot.scale_color_steps/2 is given 2 labels, which need breaks: a list of 2 breaks " <>
               "to label, and it has none"}
          ] do
        error = assert_raise ArgumentError, call
        assert error.message == shown
      end

      assert {Plot.scale_color_binned(plot, n_breaks: 1, nice_breaks: false).scales.color.n_breaks,
              Plot.scale_color_binned(plot, n_breaks: 1, breaks: fn _limits, _wanted -> [1] end).scales.color.n_breaks} ===
               {1, 1}
    end

    # R's `scale_colour_viridis_b()` lists `values` and `space` but never reads them.
    test "an option a binned scale cannot take is refused, naming what was wrong" do
      plot = Plot.new(@rows)

      for {function, options, shown} <- [
            {&Plot.scale_color_binned/2, [n_breaks: 0], "positive integer, got: 0"},
            {&Plot.scale_fill_steps/2, [n_breaks: 2.5], "positive integer, got: 2.5"},
            {&Plot.scale_color_stepsn/2, [colors: ["red"], nice_breaks: 1], "got: 1"},
            {&Plot.scale_fill_steps2/2, [show_limits: :yes], "got: :yes"},
            {&Plot.scale_color_steps/2, [right: nil], "got: nil"},
            {&Plot.scale_color_viridis_b/2, [values: [0, 1]], "unknown options [:values]"},
            {&Plot.scale_fill_binned/2, [palette: "red"], ~s(scales names no palette "red")},
            {&Plot.scale_color_fermenter/2, [palette: "set1"], ~s(got: "set1")},
            {&Plot.scale_color_binned/2, [expand: [mult: 0]], "unknown options [:expand]"},
            {&Plot.scale_color_steps2/2, [transform: :log10], "unknown options [:transform]"}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> function.(plot, options) end
        assert error.message =~ shown
      end

      error = assert_raise ArgumentError, fn -> Plot.scale_fill_fermenter(plot, palette: 19) end
      assert error.message =~ "Plot.scale_fill_fermenter/2 is given palette: 19"

      for call <- [
            fn -> Plot.scale_color_stepsn(plot) end,
            fn -> Plot.scale_fill_stepsn(plot) end
          ] do
        error = assert_raise NimbleOptions.ValidationError, call
        assert error.message =~ "required :colors option not found"
      end
    end

    test "a mistake found at the call names the function given it" do
      plot = Plot.new(@rows)

      for {function, options} <- [
            {&Plot.scale_color_binned/2, []},
            {&Plot.scale_fill_binned/2, []},
            {&Plot.scale_color_steps/2, []},
            {&Plot.scale_fill_steps/2, []},
            {&Plot.scale_color_steps2/2, []},
            {&Plot.scale_fill_steps2/2, []},
            {&Plot.scale_color_stepsn/2, [colors: ["red"]]},
            {&Plot.scale_fill_stepsn/2, [colors: ["red"]]},
            {&Plot.scale_color_viridis_b/2, []},
            {&Plot.scale_fill_viridis_b/2, []},
            {&Plot.scale_color_fermenter/2, []},
            {&Plot.scale_fill_fermenter/2, []}
          ] do
        error = assert_raise ArgumentError, fn -> function.(plot, [labels: ["a"]] ++ options) end
        {:name, name} = Function.info(function, :name)
        assert error.message =~ ~r/^Plot\.#{name}\/2 is given 1 labels/
      end
    end
  end

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
    # is a continuous colour or fill scale, the one kind a colour bar shows, or a binned one, which
    # colour steps show.
    @guided_scale_functions [
      {&Plot.scale_color_manual/2, [values: ["red"]], :discrete},
      {&Plot.scale_fill_manual/2, [values: ["red"]], :discrete},
      {&Plot.scale_color_hue/2, [], :discrete},
      {&Plot.scale_fill_hue/2, [], :discrete},
      {&Plot.scale_color_gray/2, [], :discrete},
      {&Plot.scale_fill_gray/2, [], :discrete},
      {&Plot.scale_color_discrete/2, [], :discrete},
      {&Plot.scale_fill_discrete/2, [], :discrete},
      {&Plot.scale_color_viridis_d/2, [], :discrete},
      {&Plot.scale_fill_viridis_d/2, [], :discrete},
      {&Plot.scale_alpha_discrete/2, [], :alpha},
      {&Plot.scale_color_gradient/2, [], :continuous},
      {&Plot.scale_fill_gradient/2, [], :continuous},
      {&Plot.scale_color_gradient2/2, [], :continuous},
      {&Plot.scale_fill_gradient2/2, [], :continuous},
      {&Plot.scale_color_gradientn/2, [colors: ["red"]], :continuous},
      {&Plot.scale_fill_gradientn/2, [colors: ["red"]], :continuous},
      {&Plot.scale_color_continuous/2, [], :continuous},
      {&Plot.scale_fill_continuous/2, [], :continuous},
      {&Plot.scale_color_viridis_c/2, [], :continuous},
      {&Plot.scale_fill_viridis_c/2, [], :continuous},
      {&Plot.scale_color_binned/2, [], :binned},
      {&Plot.scale_fill_binned/2, [], :binned},
      {&Plot.scale_color_steps/2, [], :binned},
      {&Plot.scale_fill_steps/2, [], :binned},
      {&Plot.scale_color_steps2/2, [], :binned},
      {&Plot.scale_fill_steps2/2, [], :binned},
      {&Plot.scale_color_stepsn/2, [colors: ["red"]], :binned},
      {&Plot.scale_fill_stepsn/2, [colors: ["red"]], :binned},
      {&Plot.scale_color_viridis_b/2, [], :binned},
      {&Plot.scale_fill_viridis_b/2, [], :binned},
      {&Plot.scale_color_fermenter/2, [], :binned},
      {&Plot.scale_fill_fermenter/2, [], :binned},
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
          guide <- [
            :none,
            :legend,
            reversed
            | Map.get(%{continuous: [:colorbar, :colorsteps], binned: [:colorsteps]}, kind, [])
          ] do
        [scale] = Map.values(function.(plot, [{:guide, guide} | options]).scales)
        assert scale.guide === guide
      end
    end

    # ggplot2 4.0.3 warns "`guide_colourbar()` needs continuous scales." for a discrete colour
    # scale, and "`guide_colourbar()` cannot be used for alpha." for either alpha scale, and for
    # shape, size, linetype and linewidth, and draws no guide; `guide_coloursteps()` draws a
    # discrete scale's guide broken, and takes colour and fill alone (`available_aes`).
    test "a colour bar or steps are refused for a discrete scale, and for any aesthetic but colour" do
      plot = Plot.new(@rows)

      for {function, options, kind} <- @guided_scale_functions,
          kind not in [:continuous, :binned],
          {guide, shows} <- [colorbar: "a colour bar shows", colorsteps: "colour steps show"] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            function.(plot, [{:guide, guide} | options])
          end

        assert error.message =~
                 if(kind == :discrete,
                   do: "continuous scale, and this one is discrete; give :legend",
                   else:
                     "#{shows} colour or fill, never #{Map.fetch!(@guided_nouns, kind)}; " <>
                       "give :legend"
                 )

        assert error.message =~ shows
      end
    end

    # ggplot2 4.0.3 draws `guide_colourbar()` for a binned scale, a bar of its bins' colours
    # blended where they meet.
    test "a colour bar is refused for a binned scale, naming colour steps" do
      plot = Plot.new(@rows)

      for {function, options, :binned} <- @guided_scale_functions do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            function.(plot, [{:guide, :colorbar} | options])
          end

        assert error.message =~
                 "a colour bar shows a continuous scale, and this one is binned; give :colorsteps"
      end
    end

    test "a guide that is not one is refused, naming what a guide can be" do
      plot = Plot.new(@rows)

      for function <- [&Plot.scale_color_hue/2, &Plot.scale_color_gradient/2] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> function.(plot, guide: :legnd) end

        assert error.message =~
                 "expected :legend, :colorbar, :colorsteps, :none or a legend " <>
                   "Plot.guide_legend/1 makes, got: :legnd"
      end
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

    test "guides/2 refuses a colour bar or steps but for colour or fill, and an aesthetic with no guide" do
      plot = Plot.new(@rows)

      for {aesthetic, noun} <- @guided_nouns,
          {guide, shows} <- [colorbar: "a colour bar shows", colorsteps: "colour steps show"] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.guides(plot, [{aesthetic, guide}])
          end

        assert error.message =~ "#{shows} colour or fill, never #{noun}"
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

  describe "theme_gray/2 and the other complete themes" do
    test "each records its name and base sizes, each width base_size / 22 unless given" do
      plot = Plot.new(@rows)

      assert {Plot.theme_bw(plot).theme, Plot.theme_void(plot, base_size: 16).theme.complete,
              Plot.theme_classic(plot, base_line_size: 1, base_rect_size: 0).theme.complete} ===
               {%{
                  complete: %{
                    name: :bw,
                    base_size: 11.0,
                    base_line_size: 0.5,
                    base_rect_size: 0.5,
                    base_family: "",
                    header_family: :none
                  },
                  settings: %{}
                },
                %{
                  name: :void,
                  base_size: 16.0,
                  base_line_size: 0.7272727272727273,
                  base_rect_size: 0.7272727272727273,
                  base_family: "",
                  header_family: :none
                },
                %{
                  name: :classic,
                  base_size: 11.0,
                  base_line_size: 1.0,
                  base_rect_size: 0.0,
                  base_family: "",
                  header_family: :none
                }}
    end

    # ggplot2's `header_family = NULL`, the titles taking the base family, is recorded as `:none`.
    test "each records its base family, \"\" unless given, and its header family, :none unless given" do
      plot = Plot.new(@rows)

      families =
        Enum.map(
          [
            Plot.theme_gray(plot, base_family: "serif", header_family: "Lobster"),
            Plot.theme_void(plot, header_family: ""),
            Plot.theme_minimal(plot, base_family: "mono")
          ],
          fn themed ->
            {themed.theme.complete.base_family, themed.theme.complete.header_family}
          end
        )

      assert families === [{"serif", "Lobster"}, {"", ""}, {"mono", :none}]
    end

    test "every function records its own theme and the base size given, 0 too" do
      plot = Plot.new(@rows)

      themed = [
        Plot.theme_gray(plot, base_size: 9),
        Plot.theme_bw(plot, base_size: 9),
        Plot.theme_linedraw(plot, base_size: 9),
        Plot.theme_light(plot, base_size: 9),
        Plot.theme_dark(plot, base_size: 9),
        Plot.theme_minimal(plot, base_size: 9),
        Plot.theme_classic(plot, base_size: 9),
        Plot.theme_void(plot, base_size: 0)
      ]

      assert Enum.map(themed, fn chosen ->
               {chosen.theme.complete.name, chosen.theme.complete.base_size}
             end) ===
               [
                 gray: 9.0,
                 bw: 9.0,
                 linedraw: 9.0,
                 light: 9.0,
                 dark: 9.0,
                 minimal: 9.0,
                 classic: 9.0,
                 void: 0.0
               ]
    end

    # ggplot2 replaces a plot's theme with a complete theme added to it, the settings laid over
    # the one before with it.
    test "a complete theme drops the settings given before it, and replaces an earlier one" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.theme(axis_text: [color: "red"])
        |> Plot.theme_minimal(base_size: 9)
        |> Plot.theme(axis_ticks: :none)
        |> Plot.theme_bw()

      unset =
        @rows
        |> Plot.new()
        |> Plot.theme_bw()

      assert plot.theme === unset.theme
    end

    # The rule is Theme.merge/2's, pinned in its tests; here, that theme/2 hands it the plot's
    # theme, the complete theme chosen with it.
    test "after a complete theme, an element set after its removal is recorded as replacing" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.theme_bw()
        |> Plot.theme(axis_text: :none)
        |> Plot.theme(axis_text: [colour: "red"])

      assert plot.theme.settings === %{axis_text: {:replace, %{color: "#FF0000"}}}
    end

    test "a base size, width or family it cannot use is refused at its key, naming the value" do
      plot = Plot.new(@rows)

      for {options, key, value} <- [
            {[base_size: -1], :base_size, -1},
            {[base_size: "11"], :base_size, "11"},
            {[base_line_size: -0.5], :base_line_size, -0.5},
            {[base_rect_size: :none], :base_rect_size, :none},
            {[base_family: :serif], :base_family, :serif},
            {[header_family: :none], :header_family, :none}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> Plot.theme_bw(plot, options) end
        assert {error.key, error.message =~ inspect(value)} == {key, true}
      end
    end

    test "an option it does not take, or one given twice, is refused, naming it" do
      plot = Plot.new(@rows)

      unknown =
        assert_raise NimbleOptions.ValidationError, fn ->
          Plot.theme_void(plot, ink: "navy")
        end

      twice =
        assert_raise ArgumentError, fn ->
          Plot.theme_gray(plot, base_family: "serif", base_family: "mono")
        end

      assert {unknown.message =~ "ink", twice.message =~ ":base_family"} == {true, true}
    end
  end

  describe "theme/2" do
    test "settings are recorded by element, a later call's properties merged into an earlier's" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.theme(axis_text: [colour: "red", size: 9], spacing: 3)
        |> Plot.theme(
          axis_text: [size: {:rel, 2}],
          plot_margin: [top: {1, :cm}],
          spacing: {1, :lines}
        )

      assert plot.theme === %{
               complete: :none,
               settings: %{
                 axis_text: %{color: "#FF0000", size: {:rel, 2}},
                 spacing: {1, :lines},
                 plot_margin: %{top: {1, :cm}, right: {0, :pt}, bottom: {0, :pt}, left: {0, :pt}}
               }
             }
    end

    test "a margin of one length is that length on every side, a number ggplot2's points" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.theme(legend_margin: 4, axis_text: [margin: {2, :mm}], margins: 3)

      assert plot.theme.settings === %{
               legend_margin: %{top: {4, :pt}, right: {4, :pt}, bottom: {4, :pt}, left: {4, :pt}},
               axis_text: %{
                 margin: %{top: {2, :mm}, right: {2, :mm}, bottom: {2, :mm}, left: {2, :mm}}
               },
               margins: %{top: {3, :pt}, right: {3, :pt}, bottom: {3, :pt}, left: {3, :pt}}
             }
    end

    test "every line end, face, legend position, direction and location is taken by name" do
      plot = Plot.new(@rows)

      for {element, values} <- [
            legend_position: [:right, :left, :top, :bottom, :inside, :none],
            legend_direction: [:horizontal, :vertical],
            legend_location: [:panel, :plot]
          ],
          value <- values do
        assert Plot.theme(plot, [{element, value}]).theme.settings === %{element => value}
      end

      for line_end <- [:butt, :round, :square] do
        assert Plot.theme(plot, axis_line: [lineend: line_end]).theme.settings ===
                 %{axis_line: %{lineend: line_end}}
      end

      for face <- [:plain, :bold, :italic, :bold_italic] do
        assert Plot.theme(plot, legend_title: [face: face]).theme.settings ===
                 %{legend_title: %{face: face}}
      end
    end

    test "a justification is taken by any name, or by names or shares across and up" do
      plot = Plot.new(@rows)

      justifications =
        [:center, :left, :right, :top, :bottom] ++
          for across <- [:left, :center, :right, 0.25], up <- [:bottom, :center, :top, 2] do
            {across, up}
          end

      for justification <- justifications do
        assert Plot.theme(plot, legend_justification_top: justification).theme.settings ===
                 %{legend_justification_top: justification}
      end

      for box_just <- [:center, :bottom, {:left, :bottom}, {:center, :center}, {:right, :top}] do
        assert Plot.theme(plot, legend_box_just: box_just).theme.settings ===
                 %{legend_box_just: box_just}
      end
    end

    test "a size or a line width of 0, a share of a margin and a border of :none are taken" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.theme(
          axis_text: [size: 0],
          panel_grid: [linewidth: {:rel, 0}],
          legend_margin: {:rel, 2},
          panel_background: [color: :none]
        )

      assert plot.theme.settings === %{
               axis_text: %{size: 0},
               panel_grid: %{linewidth: {:rel, 0}},
               legend_margin: {:rel, 2},
               panel_background: %{color: :none}
             }
    end

    # A line type is held as its dash pattern, as a layer's `linetype:` holds it, the blank one as
    # `:none`; the border's fill is taken, as ggplot2 takes it, though the border is never filled.
    test "a line type, a line's end, a fill of :none and panel_ontop are recorded as given" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.theme(
          panel_grid: [linetype: :dashed, lineend: :round],
          axis_ticks: [linetype: 3],
          axis_line: [linetype: {2, 2}],
          panel_background: [fill: :none, linetype: :blank],
          panel_border: [fill: "blue"],
          panel_ontop: true
        )

      assert plot.theme.settings === %{
               panel_grid: %{linetype: {4, 4}, lineend: :round},
               axis_ticks: %{linetype: {1, 3}},
               axis_line: %{linetype: {2, 2}},
               panel_background: %{fill: :none, linetype: :none},
               panel_border: %{fill: "#0000FF"},
               panel_ontop: true
             }
    end

    # A text's angle, justification and line height are numbers kept as floats, as R keeps a
    # number; its face is a name, R's "bold.italic" spelled `:bold_italic`.
    test "a text's face, angle, justification and line height are recorded, numbers as floats" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.theme(
          axis_text_x: [face: :bold, angle: 45, hjust: 1, vjust: -2],
          plot_title: [face: :bold_italic, lineheight: 0, hjust: 0.5]
        )

      assert plot.theme.settings === %{
               axis_text_x: %{face: :bold, angle: 45.0, hjust: 1.0, vjust: -2.0},
               plot_title: %{face: :bold_italic, lineheight: 0.0, hjust: 0.5}
             }
    end

    test "a text's family is recorded as named, the default's \"\" too" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.theme(title: [family: "Lobster Two"], axis_text: [family: ""])

      assert plot.theme.settings === %{
               title: %{family: "Lobster Two"},
               axis_text: %{family: ""}
             }
    end

    test "a colour may have an alpha of its own, transparent too" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.theme(axis_text: [color: "#ff000080"], panel_background: [fill: "transparent"])

      assert plot.theme.settings === %{
               axis_text: %{color: "#FF000080"},
               panel_background: %{fill: "#FFFFFF00"}
             }
    end

    test "a line, a rectangle or a text set to :none is recorded as removed" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.theme(axis_text: :none, panel_grid: :none, rect: :none, legend_position: :none)

      assert plot.theme.settings === %{
               axis_text: :none,
               panel_grid: :none,
               rect: :none,
               legend_position: :none
             }
    end

    test "an element the theme does not know, or a property its kind does not have, is refused" do
      plot = Plot.new(@rows)

      for {settings, key} <- [
            {[axis_text_z: []], [:axis_text_z]},
            {[axis_text: [linewidth: 2]], [:linewidth]},
            {[panel_grid: [size: 2]], [:size]},
            {[panel_background: [lineend: :round]], [:lineend]},
            {[axis_text: [fill: "red"]], [:fill]}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> Plot.theme(plot, settings) end
        assert error.key == key
      end
    end

    test "a value an element cannot use is refused at its key, naming the value" do
      plot = Plot.new(@rows)

      for {settings, key, value} <- [
            {[panel_grid: [colour: :none]], {:color, [:panel_grid]}, :none},
            {[axis_text: [size: -1]], {:size, [:axis_text]}, -1},
            {[panel_grid: [linewidth: {:rel, -1}]], {:linewidth, [:panel_grid]}, {:rel, -1}},
            {[spacing: {1, :px}], {:spacing, []}, {1, :px}},
            {[plot_margin: [top: 1, top: 2]], {:plot_margin, []}, [top: 1, top: 2]},
            {[plot_margin: [middle: 1]], {:plot_margin, []}, [middle: 1]},
            {[axis_text: [margin: {:rel, 2}]], {:margin, [:axis_text]}, {:rel, 2}},
            {[axis_text: [color: "grey50"]], {:color, [:axis_text]}, "grey50"},
            {[spacing: {:rel, "a"}], {:spacing, []}, {:rel, "a"}},
            {[plot_margin: [top: "x"]], {:plot_margin, []}, [top: "x"]},
            {[spacing: :none], {:spacing, []}, :none},
            {[spacing: {:rel, 2}], {:spacing, []}, {:rel, 2}},
            {[panel_spacing: {:rel, "a"}], {:panel_spacing, []}, {:rel, "a"}},
            {[margins: {:rel, 2}], {:margins, []}, {:rel, 2}},
            {[plot_margin: {:rel, :half}], {:plot_margin, []}, {:rel, :half}},
            {[plot_margin: :none], {:plot_margin, []}, :none},
            {[legend_position: :middle], {:legend_position, []}, :middle},
            {[legend_position: {0.5, 0.5}], {:legend_position, []}, {0.5, 0.5}},
            {[legend_position_inside: 0.5], {:legend_position_inside, []}, 0.5},
            {[legend_position_inside: {"a", 1}], {:legend_position_inside, []}, {"a", 1}},
            {[legend_justification: :inside], {:legend_justification, []}, :inside},
            {[legend_justification: {:top, :left}], {:legend_justification, []}, {:top, :left}},
            {[legend_justification: {:top, :bottom}], {:legend_justification, []},
             {:top, :bottom}},
            {[legend_box_just: {0.2, :top}], {:legend_box_just, []}, {0.2, :top}},
            {[legend_justification_top: {1, :right}], {:legend_justification_top, []},
             {1, :right}},
            {[legend_box_just: {0.2, 0.3}], {:legend_box_just, []}, {0.2, 0.3}},
            {[legend_direction: :diagonal], {:legend_direction, []}, :diagonal},
            {[legend_box: :diagonal], {:legend_box, []}, :diagonal},
            {[legend_location: :figure], {:legend_location, []}, :figure},
            {[legend_box_background: [fill: 3]], {:fill, [:legend_box_background]}, 3},
            {[panel_grid: [linetype: :wavy]], {:linetype, [:panel_grid]}, :wavy},
            {[panel_border: [linetype: {4, 16}]], {:linetype, [:panel_border]}, {4, 16}},
            {[axis_line: [lineend: :flat]], {:lineend, [:axis_line]}, :flat},
            {[panel_ontop: :yes], {:panel_ontop, []}, :yes},
            {[axis_text: [face: :oblique]], {:face, [:axis_text]}, :oblique},
            {[axis_text: [family: :serif]], {:family, [:axis_text]}, :serif},
            {[axis_text: [face: 2]], {:face, [:axis_text]}, 2},
            {[axis_text: [face: "bold"]], {:face, [:axis_text]}, "bold"},
            {[axis_text: [angle: "45"]], {:angle, [:axis_text]}, "45"},
            {[axis_text: [hjust: :left]], {:hjust, [:axis_text]}, :left},
            {[axis_text: [vjust: :top]], {:vjust, [:axis_text]}, :top},
            {[plot_title: [lineheight: -1]], {:lineheight, [:plot_title]}, -1},
            {[plot_title: [lineheight: {:rel, 2}]], {:lineheight, [:plot_title]}, {:rel, 2}}
          ] do
        error = assert_raise NimbleOptions.ValidationError, fn -> Plot.theme(plot, settings) end
        assert {{error.key, error.keys_path}, error.message =~ inspect(value)} == {key, true}
      end
    end

    test "an element or a property given twice is refused, naming it" do
      plot = Plot.new(@rows)

      for {settings, name} <- [
            {[spacing: 1, spacing: 2], ":spacing"},
            {[axis_text: [color: "red", colour: "blue"]], ":color"}
          ] do
        error = assert_raise ArgumentError, fn -> Plot.theme(plot, settings) end
        assert error.message =~ name
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

  describe "a scale's oob:" do
    # Every scale function ggplot2 4.0.3 gives an `oob` (`inc4/step7/formals.R`): the position,
    # date, date-time and time scales, the continuous and binned colour and fill scales, alpha's
    # and size by area's, each with what else it needs.
    @oob_scale_functions [
      {&Plot.scale_x_continuous/2, []},
      {&Plot.scale_y_continuous/2, []},
      {&Plot.scale_x_log10/2, []},
      {&Plot.scale_y_sqrt/2, []},
      {&Plot.scale_x_reverse/2, []},
      {&Plot.scale_x_date/2, []},
      {&Plot.scale_y_datetime/2, []},
      {&Plot.scale_x_time/2, []},
      {&Plot.scale_color_continuous/2, []},
      {&Plot.scale_fill_gradient/2, []},
      {&Plot.scale_color_gradient2/2, []},
      {&Plot.scale_fill_gradientn/2, [colors: ["red", "blue"]]},
      {&Plot.scale_color_viridis_c/2, []},
      {&Plot.scale_fill_distiller/2, []},
      {&Plot.scale_alpha_continuous/2, []},
      {&Plot.scale_size_area/2, []},
      {&Plot.scale_color_binned/2, []},
      {&Plot.scale_fill_steps/2, []},
      {&Plot.scale_color_steps2/2, []},
      {&Plot.scale_fill_stepsn/2, [colors: ["red", "blue"]]},
      {&Plot.scale_color_viridis_b/2, []},
      {&Plot.scale_fill_fermenter/2, []}
    ]

    defp recorded_oob(function, options) do
      @rows
      |> Plot.new()
      |> function.(options)
      |> Map.fetch!(:scales)
      |> Map.values()
      |> then(fn [scale] -> scale.oob end)
    end

    test "each scale function ggplot2 gives an oob records one, a name or a function of two arguments" do
      capped = fn values, _limits -> values end

      for {function, needed} <- @oob_scale_functions do
        assert {recorded_oob(function, [{:oob, :squish_any} | needed]),
                recorded_oob(function, [{:oob, capped} | needed])} === {:squish_any, capped}
      end
    end

    test "a continuous scale censors and a binned one squishes when given none, as ggplot2's" do
      assert {recorded_oob(&Plot.scale_y_continuous/2, []),
              recorded_oob(&Plot.scale_color_binned/2, [])} === {:censor, :squish}
    end

    # ggplot2 4.0.3's `scale_size_continuous()`, `scale_radius()`, `scale_linewidth_continuous()`
    # and a discrete scale fail on an `oob` ("unused argument").
    test "the size, radius and line width scales and a discrete scale take no oob:" do
      plot = Plot.new(@rows)

      for function <- [
            &Plot.scale_size_continuous/2,
            &Plot.scale_radius/2,
            &Plot.scale_linewidth_continuous/2,
            &Plot.scale_x_discrete/2
          ] do
        assert_raise NimbleOptions.ValidationError, ~r/unknown options \[:oob\]/, fn ->
          function.(plot, oob: :squish)
        end
      end
    end

    # ggplot2 4.0.3 recycles `oob_discard()`'s fewer values over the rows: limits of 10 to 30 on y
    # of 5, 20, 40 and 25 draw the points at 20, 25, 20 and 25 (`inc4/step7/fn.txt`).
    test ":discard is refused, naming :censor" do
      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          @rows
          |> Plot.new()
          |> Plot.scale_y_continuous(oob: :discard)
        end

      assert String.starts_with?(error.message, "invalid value for :oob option: oob: :discard ")
      assert error.message =~ "use :censor"
    end

    test "another name, or a function of another arity, is refused" do
      plot = Plot.new(@rows)

      for oob <- [:clamp, fn values -> values end] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Plot.scale_color_binned(plot, oob: oob)
          end

        assert String.starts_with?(
                 error.message,
                 "invalid value for :oob option: expected one of "
               )

        assert error.message =~
                 ":censor, :censor_any, :squish, :squish_any, :squish_infinite, :keep"

        assert error.message =~ "got: #{inspect(oob)}"
      end
    end
  end

  # `value` with its type hidden from the compiler, so a test can hand a function a value its
  # guards refuse.
  @spec untyped(term()) :: term()
  defp untyped(value), do: value
end
