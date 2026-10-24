defmodule Giggly.AssemblyTest do
  use ExUnit.Case, async: true

  alias Giggly.{Assembly, Geom, Guide, Plot}

  # Golden throughout: ggplot2 4.0.3's `get_guide_data()` for the same plot in R 4.6.1, printed to
  # 17 significant digits, and the defaults its legends' keys are filled with, as each layer's
  # key data shows them (`decor`) under `theme_gray()` at its default sizes. It moves with
  # ggplot2's default alpha scales, how a legend's keys are chosen, or a geom's defaults.
  describe "run/1, legends" do
    @point_defaults %{
      shape: :circle,
      color: "#000000",
      fill: nil,
      size: 1.5,
      alpha: nil,
      stroke: 0.5
    }

    @bar_defaults %{color: nil, fill: "#595959", linewidth: 0.5, linetype: {}, alpha: nil}

    @keep_rows %{
      "x" => ["p", "q", "p", "q"],
      "y" => [1, 3, 2, 4],
      "g" => ["a", "b", "a", "b"],
      "h" => ["a", "b", "c", "c"],
      "m" => [nil, "b", "a", "b"],
      "n" => [1, 2, 3, 4],
      "k" => [10, 20, 30, 40],
      "one" => [1, 1, 1, 1]
    }

    test "a mapped alpha's legend is titled by its column, a key for each break at its alpha" do
      [legend] =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, alpha: :year})
        |> Plot.geom_point()
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert legend === %{
               guide: %Guide.Legend{},
               aesthetics: [:alpha],
               title: "year",
               keys: [
                 %{label: "2000", value: 2000.0, values: %{alpha: 0.2}},
                 %{label: "2002", value: 2002.0, values: %{alpha: 0.4}},
                 %{label: "2004", value: 2004.0, values: %{alpha: 0.6}},
                 %{label: "2006", value: 2006.0, values: %{alpha: 0.8}},
                 %{label: "2008", value: 2008.0, values: %{alpha: 1.0}}
               ],
               layers: [
                 %{
                   geom: %Geom.Point{},
                   defaults: @point_defaults,
                   aesthetics: [:alpha],
                   fixed: %{},
                   flipped: false,
                   draws: [true, true, true, true, true]
                 }
               ]
             }
    end

    # Golden: `get_guide_data(plot, "colour")` for `geom_point(aes(colour = "smooth"))` is one key,
    # `smooth`, #F8766D, and for `aes(colour = 7)` one key, `7`, #336A98, at 0.5 of the bar.
    test "a constant's legend has one key" do
      legend = fn mapping ->
        [legend] =
          Giggly.Datasets.mpg()
          |> Plot.new(%{x: :displ, y: :hwy})
          |> Plot.geom_point(mapping)
          |> Assembly.run()
          |> Map.fetch!(:legends)

        {legend.guide, legend.keys}
      end

      assert {legend.(%{colour: {:constant, "smooth"}}), legend.(%{colour: 7})} ===
               {{%Guide.Legend{},
                 [%{label: "smooth", value: "smooth", values: %{color: "#F8766D"}}]},
                {%Guide.Colorbar{bins: 15},
                 [%{label: "7", value: 7.0, values: %{color: "#336A98"}, place: 0.5}]}}
    end

    test "a discrete alpha's legend has a key for each level, spread from 0.1 to 1" do
      [legend] =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, alpha: :drv})
        |> Plot.geom_bar()
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert {legend.keys, legend.layers} ===
               {[
                  %{label: "4", value: "4", values: %{alpha: 0.1}},
                  %{label: "f", value: "f", values: %{alpha: 0.55}},
                  %{label: "r", value: "r", values: %{alpha: 1.0}}
                ],
                [
                  %{
                    geom: %Geom.Bar{just: 0.5},
                    defaults: @bar_defaults,
                    aesthetics: [:alpha],
                    fixed: %{},
                    flipped: false,
                    draws: [true, true, true]
                  }
                ]}
    end

    # Golden: ggplot2 4.0.3's colour bar params for mpg's `colour = cty` in the gradient form, R
    # 4.6.1: each key's colour and its place up the bar, and the bar's 15 colours at their values.
    test "a continuous colour's guide is a colour bar, its keys placed up the bar and its colours sampled" do
      [legend] =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, colour: :cty})
        |> Plot.geom_point()
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert {legend.guide, legend.title, legend.layers} ===
               {%Guide.Colorbar{bins: 15}, "cty", []}

      assert Enum.map(legend.keys, fn key -> {key.label, key.values.color, key.place} end) === [
               {"10", "#153049", 0.038461538461538464},
               {"15", "#214769", 0.23076923076923078},
               {"20", "#2E608A", 0.42307692307692307},
               {"25", "#3B7AAD", 0.6153846153846154},
               {"30", "#4895D1", 0.8076923076923077},
               {"35", "#56B1F7", 1.0}
             ]

      assert Enum.map(legend.decor, fn {_place, color} -> color end) === [
               "#132B43",
               "#17334E",
               "#1C3C5A",
               "#204566",
               "#254E72",
               "#29577E",
               "#2E618B",
               "#336A98",
               "#3874A5",
               "#3D7EB2",
               "#4288C0",
               "#4792CD",
               "#4C9CDB",
               "#51A6E9",
               "#56B1F7"
             ]

      assert {hd(legend.decor), List.last(legend.decor)} === {{0.0, "#132B43"}, {1.0, "#56B1F7"}}
    end

    # ggplot2 hashes a guide's kind with its title and labels, so a colour bar and a legend of one
    # column, with one title and the same labels, stay two guides.
    test "a colour bar and a legend with the same title and labels stay apart" do
      legends =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, colour: :cty, alpha: :cty})
        |> Plot.geom_point()
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert Enum.map(legends, fn legend -> {legend.aesthetics, legend.guide} end) ===
               [{[:alpha], %Guide.Legend{}}, {[:color], %Guide.Colorbar{bins: 15}}]
    end

    test "a discrete colour's legend has a key for each level in the hue palette, NA last in grey50" do
      [legend] =
        %{"x" => [1, 2, 3], "y" => [1, 2, 3], "g" => ["b", "a", nil]}
        |> Plot.new(%{x: :x, y: :y, colour: :g})
        |> Plot.geom_point()
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert {legend.aesthetics, legend.title, legend.keys} ===
               {[:color], "g",
                [
                  %{label: "a", value: "a", values: %{color: "#F8766D"}},
                  %{label: "b", value: "b", values: %{color: "#00BFC4"}},
                  %{label: "NA", value: nil, values: %{color: "#7F7F7F"}}
                ]}
    end

    test "legends with the same title and labels merge, each key holding every aesthetic's value" do
      [legend] =
        %{"x" => [1, 2, 3], "y" => [1, 2, 3], "g" => ["b", "a", nil]}
        |> Plot.new(%{x: :x, y: :y, colour: :g, fill: :g})
        |> Plot.geom_col()
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert legend === %{
               guide: %Guide.Legend{},
               aesthetics: [:color, :fill],
               title: "g",
               keys: [
                 %{label: "a", value: "a", values: %{color: "#F8766D", fill: "#F8766D"}},
                 %{label: "b", value: "b", values: %{color: "#00BFC4", fill: "#00BFC4"}},
                 %{label: "NA", value: nil, values: %{color: "#7F7F7F", fill: "#7F7F7F"}}
               ],
               layers: [
                 %{
                   geom: %Geom.Bar{just: 0.5},
                   defaults: @bar_defaults,
                   aesthetics: [:color, :fill],
                   fixed: %{},
                   flipped: false,
                   draws: [true, true, true]
                 }
               ]
             }
    end

    test "a legend merges only into the one that reads alike, the others left as they are" do
      legends =
        %{"x" => [1, 2, 3], "y" => [1, 2, 3], "g" => ["b", "a", nil]}
        |> Plot.new(%{x: :x, y: :y, colour: :g, fill: :g, alpha: :y})
        |> Plot.geom_col()
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert Enum.map(legends, fn legend ->
               {legend.aesthetics, legend.title, Enum.map(legend.keys, fn key -> key.label end)}
             end) === [
               {[:alpha], "y", ["1.0", "1.5", "2.0", "2.5", "3.0"]},
               {[:color, :fill], "g", ["a", "b", "NA"]}
             ]
    end

    # Golden: ggplot2 4.0.3's `keep_key_data()`, each layer's `.draw` in `ggplot_build()`'s guide
    # params, R 4.6.1. A layer draws in a discrete key only where its own column holds the break.
    test "a layer draws in a discrete key only where its own column holds the key's break" do
      [legend] =
        @keep_rows
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{colour: :g})
        |> Plot.geom_line(%{colour: :h})
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert {Enum.map(legend.keys, fn key -> key.label end),
              Enum.map(legend.layers, fn layer -> layer.draws end)} ===
               {["a", "b", "c"], [[true, true, false], [true, true, true]]}
    end

    # Golden: the same `.draw` for `geom_point(aes(colour = factor(n))) + geom_line(aes(colour =
    # factor(one), group = 1))`: a factor's numbers are levels, so the line draws in key 1 alone.
    test "a factor's numbers are keys like any level, drawn only where a layer holds them" do
      [legend] =
        @keep_rows
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{colour: {:factor, [:n]}})
        |> Plot.geom_line(%{colour: {:factor, [:one]}, group: 1})
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert {Enum.map(legend.keys, fn key -> key.label end),
              Enum.map(legend.layers, fn layer -> layer.draws end)} ===
               {["1", "2", "3", "4"], [[true, true, true, true], [true, false, false, false]]}
    end

    test "a layer draws in the NA key only where its own column holds a missing value" do
      [legend] =
        @keep_rows
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{colour: :m})
        |> Plot.geom_line(%{colour: :g})
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert {Enum.map(legend.keys, fn key -> key.label end),
              Enum.map(legend.layers, fn layer -> layer.draws end)} ===
               {["a", "b", "NA"], [[true, true, true], [true, true, false]]}
    end

    test "every layer draws in every key of a continuous scale, whatever its column holds" do
      [legend] =
        @keep_rows
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{alpha: :n})
        |> Plot.geom_point(%{alpha: :k})
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert {Enum.map(legend.keys, fn key -> key.label end),
              Enum.map(legend.layers, fn layer -> layer.draws end)} ===
               {["10", "20", "30", "40"], [[true, true, true, true], [true, true, true, true]]}
    end

    # The counted bars' colour varies within their one group, so counting drops it, and they draw
    # in every key, as ggplot2's `keep_key_data()` keeps a layer with no column to look in.
    test "a layer whose stat dropped the legend's column draws in every key" do
      [legend] =
        @keep_rows
        |> Plot.new(%{x: :x})
        |> Plot.geom_bar(%{colour: :h, group: :one})
        |> Plot.geom_point(%{y: :y, colour: :g})
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert {Enum.map(legend.keys, fn key -> key.label end),
              Enum.map(legend.layers, fn layer -> layer.draws end)} ===
               {["a", "b"], [[true, true], [true, true]]}
    end

    # ggplot2 draws a layer in a merged legend with only the aesthetics it maps: the columns' key
    # without a colour, the points' without a fill.
    test "a merged legend is drawn by each layer mapping one of its aesthetics, with those it maps" do
      [legend] =
        %{"x" => [1, 2, 3], "y" => [1, 2, 3], "g" => ["b", "a", nil]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_col(%{fill: :g})
        |> Plot.geom_point(%{colour: :g})
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert {legend.aesthetics, legend.layers} ===
               {[:color, :fill],
                [
                  %{
                    geom: %Geom.Bar{just: 0.5},
                    defaults: @bar_defaults,
                    aesthetics: [:fill],
                    fixed: %{},
                    flipped: false,
                    draws: [true, true, true]
                  },
                  %{
                    geom: %Geom.Point{},
                    defaults: @point_defaults,
                    aesthetics: [:color],
                    fixed: %{},
                    flipped: false,
                    draws: [true, true, true]
                  }
                ]}
    end

    # ggplot2 4.0.3: `geom_path()` under a plot's `fill` it cannot use has groups 1, 2, 3 and no
    # guide box, since no layer's geom knows `fill`.
    test "an aesthetic a layer takes from the plot and cannot use groups its rows and draws no legend" do
      assembly =
        %{"x" => [1, 2, 3], "y" => [1, 3, 2], "g" => ["a", "b", "c"]}
        |> Plot.new(%{x: :x, y: :y, fill: :g})
        |> Plot.geom_path()
        |> Assembly.run()

      [frame] = assembly.layer_data
      assert {Giggly.DataFrame.pull(frame, :group), assembly.legends} === {[1, 2, 3], []}
    end

    # ggplot2 4.0.3: the points under `aes(wt, mpg, label = rownames(mtcars))` carry each label and
    # are one group, -1, as `add_group()` leaves `label` out.
    test "a plot's label rides along in a point layer under a text layer, grouping nothing" do
      [points, text] =
        %{"wt" => [2.62, 2.32], "mpg" => [21.0, 22.8], "model" => ["Mazda RX4", "Datsun 710"]}
        |> Plot.new(%{x: :wt, y: :mpg, label: :model})
        |> Plot.geom_point()
        |> Plot.geom_text()
        |> Assembly.run()
        |> Map.fetch!(:layer_data)

      assert {Giggly.DataFrame.pull(points, :label), Giggly.DataFrame.pull(points, :group),
              Giggly.DataFrame.pull(text, :group)} ===
               {["Mazda RX4", "Datsun 710"], [-1, -1], [-1, -1]}
    end

    # ggplot2 4.0.3's layer_data() keeps an aesthetic the layer cannot use, and its geom never reads
    # it. A position stays in the rows drawn, as a geom reads only the positions it uses or works
    # out, and a value the layer sets replaces the plot's mapping of it. The geom's defaults follow
    # the table's own columns, and in the rows drawn one takes the place of an aesthetic carried
    # unused: the points' carried stroke is in their table, their default stroke in the rows drawn.
    test "an aesthetic a layer carries unused is in its table but not in the rows its geom draws" do
      data = %{"x" => [1, 2], "y" => [1, 3], "w" => [1, 2]}

      assembly =
        data
        |> Plot.new(%{x: :x, y: :y, linewidth: :w, stroke: :w, xmin: :w})
        |> Plot.geom_point()
        |> Plot.geom_path(linewidth: 2)
        |> Assembly.run()

      names = fn frames -> Enum.map(frames, &Giggly.DataFrame.names/1) end

      assert names.(assembly.layer_data) === [
               [
                 :x,
                 :y,
                 :linewidth,
                 :stroke,
                 :xmin,
                 :panel,
                 :group,
                 :shape,
                 :color,
                 :fill,
                 :size,
                 :alpha
               ],
               [:x, :y, :stroke, :xmin, :panel, :group, :color, :linewidth, :linetype, :alpha]
             ]

      assert names.(assembly.drawn_data) === [
               [:x, :y, :xmin, :panel, :group, :shape, :color, :fill, :size, :alpha, :stroke],
               [:x, :y, :xmin, :panel, :group, :color, :linewidth, :linetype, :alpha]
             ]

      [carried, drawn] =
        Enum.map([assembly.layer_data, assembly.drawn_data], fn [points, _path] ->
          Giggly.DataFrame.pull(points, :stroke)
        end)

      assert {carried, drawn} === {[1, 2], [0.5, 0.5]}
    end

    # ggplot2 4.0.3's key data (`decor`) for `ggplot(d, aes(x, y, colour = l)) + geom_point(stroke
    # = 2) + theme_gray(base_size = 16)`, and for `geom_col()` with `theme_void()`: each key filled
    # with its layer's defaults under the theme, what the layer sets laid over them.
    test "each layer's keys take its geom's defaults under the plot's theme" do
      rows = %{"x" => [1, 3, 5], "y" => [1, 3, 2], "l" => ["a", "b", "c"]}

      layer = fn plot ->
        [legend] = Assembly.run(plot).legends
        [layer] = legend.layers
        {layer.defaults, layer.fixed}
      end

      points =
        rows
        |> Plot.new(%{x: :x, y: :y, colour: :l})
        |> Plot.geom_point(stroke: 2)
        |> Plot.theme_gray(base_size: 16)

      bars =
        rows
        |> Plot.new(%{x: :x, y: :y, colour: :l})
        |> Plot.geom_col()
        |> Plot.theme_void()

      assert {layer.(points), layer.(bars)} ===
               {{%{
                   shape: :circle,
                   color: "#000000",
                   fill: nil,
                   size: 2.1818181818181817,
                   alpha: nil,
                   stroke: 0.72727272727272729
                 }, %{stroke: 2.0}},
                {%{color: nil, fill: "#000000A6", linewidth: 0.5, linetype: {}, alpha: nil}, %{}}}
    end

    # ggplot2 4.0.3: bars coloured and filled by one column have one guide; `labs(fill = "F")` gives
    # them two, `labs(fill = "F", colour = "F")` one again, and `labs(colour = NULL)` two, one with
    # no title.
    test "a label titles a legend, so legends it titles apart are drawn apart and alike as one" do
      legends = fn labels ->
        %{"x" => ["a", "b"], "y" => [1, 2], "g" => ["p", "q"]}
        |> Plot.new(%{x: :x, y: :y, colour: :g, fill: :g})
        |> Plot.geom_col()
        |> Plot.labs(labels)
        |> Assembly.run()
        |> Map.fetch!(:legends)
        |> Enum.map(fn legend -> {legend.aesthetics, legend.title} end)
      end

      assert {legends.(fill: "F"), legends.(fill: "F", colour: "F"), legends.(colour: :none)} ===
               {[{[:color], "g"}, {[:fill], "F"}], [{[:color, :fill], "F"}],
                [{[:color], :none}, {[:fill], "g"}]}
    end

    # Steve's choice, where ggplot2 4.0.3 nudges each label by its row's `nudge_x`: no layer maps a
    # nudge yet, so one the plot maps rides into a text layer and is replaced by the default, 0.
    test "a nudge the plot maps rides into a text layer and moves nothing" do
      [frame] =
        %{"x" => [1.0, 2.0], "y" => [1.0, 2.0], "name" => ["a", "b"], "shift" => [0.5, -0.5]}
        |> Plot.new(%{x: :x, y: :y, label: :name, nudge_x: :shift})
        |> Plot.geom_text()
        |> Assembly.run()
        |> Map.fetch!(:layer_data)

      assert {Giggly.DataFrame.pull(frame, :x), Giggly.DataFrame.pull(frame, :nudge_x)} ===
               {[1.0, 2.0], [+0.0, +0.0]}
    end

    # ggplot2's text knows no `fill`, so it draws no key in a fill legend; its point knows one.
    test "a layer draws in a legend only for the aesthetics it can use" do
      [legend] =
        %{"x" => [1, 2], "y" => [1, 2], "g" => ["a", "b"]}
        |> Plot.new(%{x: :x, y: :y, fill: :g})
        |> Plot.geom_col()
        |> Plot.geom_text(%{label: :g})
        |> Plot.geom_point()
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert Enum.map(legend.layers, fn layer -> {layer.geom, layer.aesthetics} end) ===
               [{%Geom.Bar{just: 0.5}, [:fill]}, {%Geom.Point{}, [:fill]}]
    end

    test "legends with different titles stay apart, in the order of their aesthetics' names" do
      legends =
        %{"x" => [1, 2, 3], "y" => [1, 2, 3], "g" => ["b", "a", nil], "h" => ["b", "a", nil]}
        |> Plot.new(%{x: :x, y: :y, fill: :h, colour: :g, alpha: :y})
        |> Plot.geom_col()
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert Enum.map(legends, fn legend -> {legend.aesthetics, legend.title} end) ===
               [{[:alpha], "y"}, {[:color], "g"}, {[:fill], "h"}]
    end

    # The colour scale trains on both layers' columns, the alpha scale on the second's alone; both
    # are titled by the first column mapped to them, "g", as ggplot2 titles them.
    test "legends with the same title and different labels stay apart" do
      legends =
        %{"x" => [1, 2, 3], "y" => [1, 2, 3], "g" => ["a", "b", "a"], "h" => ["a", "b", "c"]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{colour: :g})
        |> Plot.geom_point(%{colour: :h, alpha: :g})
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert Enum.map(legends, fn legend ->
               {legend.aesthetics, legend.title, Enum.map(legend.keys, fn key -> key.label end)}
             end) === [{[:alpha], "g", ["a", "b"]}, {[:color], "g", ["a", "b", "c"]}]
    end

    test "only the layers that map the aesthetic draw its keys; one that sets it does not" do
      [legend] =
        %{"x" => [1, 2], "y" => [1, 2], "a" => [1.0, 2.0]}
        |> Plot.new(%{x: :x, y: :y, alpha: :a})
        |> Plot.geom_col()
        |> Plot.geom_point(alpha: 0.5)
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert legend.layers === [
               %{
                 geom: %Geom.Bar{just: 0.5},
                 defaults: @bar_defaults,
                 aesthetics: [:alpha],
                 fixed: %{},
                 flipped: false,
                 draws: [true, true, true, true, true]
               }
             ]
    end

    # ggplot2's key data holds what a layer sets beside the key's value, so a line's key is as wide
    # as the lines the layer sets.
    test "a layer drawing a legend's keys carries what it sets to them" do
      [legend] =
        %{"x" => [1, 2], "y" => [1, 2], "a" => [1.0, 2.0]}
        |> Plot.new(%{x: :x, y: :y, alpha: :a})
        |> Plot.geom_line(linewidth: 2)
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert [%{fixed: %{linewidth: 2.0}}] = legend.layers
    end

    # Golden: `get_guide_data(plot, "size")` for `geom_count()` over mpg's cty and hwy is two keys,
    # 5 and 10, at sizes 3.773500981126146 and 5.1602514716892189, titled `n`; with `size = 3` set
    # it is `NULL`. It moves with the default size scale and `stat_sum()`'s default size.
    test "a size a stat maps by default is scaled and draws its legend, unless the layer sets it" do
      plot = Plot.new(Giggly.Datasets.mpg(), %{x: :cty, y: :hwy})
      counted = Plot.geom_count(plot)
      set = Plot.geom_count(plot, size: 3)

      legends = fn layered ->
        layered
        |> Assembly.run()
        |> Map.fetch!(:legends)
      end

      assert legends.(counted) === [
               %{
                 guide: %Guide.Legend{},
                 aesthetics: [:size],
                 title: "n",
                 keys: [
                   %{label: "5", value: 5.0, values: %{size: 3.773500981126146}},
                   %{label: "10", value: 10.0, values: %{size: 5.1602514716892189}}
                 ],
                 layers: [
                   %{
                     geom: %Geom.Point{},
                     defaults: @point_defaults,
                     aesthetics: [:size],
                     fixed: %{},
                     flipped: false,
                     draws: [true, true]
                   }
                 ]
               }
             ]

      assert legends.(set) === []
    end

    test "an aesthetic whose every column a stat dropped has no legend" do
      assembly =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, alpha: :year})
        |> Plot.geom_bar()
        |> Assembly.run()

      assert assembly.legends === []
    end
  end

  # Golden throughout: ggplot2 4.0.3's `get_guide_data()` for the same plot in R 4.6.1, `NULL`
  # where it draws no guide, and its legend count from `ggplot_build()`.
  describe "run/1, guides" do
    @guide_rows %{"x" => [1, 2, 3, 4], "y" => [1, 2, 3, 4], "g" => ["a", "b", "c", nil]}

    # The legends `plot` gives, each as its kind of guide, its aesthetics, and its keys' labels and
    # values.
    defp guide_keys(plot) do
      plot
      |> Assembly.run()
      |> Map.fetch!(:legends)
      |> Enum.map(fn legend ->
        {legend.guide.__struct__, legend.aesthetics,
         Enum.map(legend.keys, fn key -> {key.label, key.values} end)}
      end)
    end

    defp guided(mapping) do
      @guide_rows
      |> Plot.new(mapping)
      |> Plot.geom_point()
    end

    test "a guide guides/2 sets wins over its scale's, whichever is given first" do
      discrete = guided(%{x: :x, y: :y, colour: :g})

      guides_last =
        discrete
        |> Plot.scale_color_discrete(guide: :none)
        |> Plot.guides(color: :legend)

      guides_first =
        discrete
        |> Plot.guides(color: :none)
        |> Plot.scale_color_discrete(guide: :legend)

      reversed_first =
        discrete
        |> Plot.guides(color: Plot.guide_legend(reverse: true))
        |> Plot.scale_color_discrete(guide: :none)

      assert [{Guide.Legend, [:color], [{"a", _a}, {"b", _b}, {"c", _c}, {"NA", _missing}]}] =
               guide_keys(guides_last)

      assert guide_keys(guides_first) === []

      assert [{Guide.Legend, [:color], [{"NA", _missing}, {"c", _c}, {"b", _b}, {"a", _a}]}] =
               guide_keys(reversed_first)
    end

    test "a guide of :none draws none, given by the scale or by guides/2" do
      continuous = guided(%{x: :x, y: :y, colour: :x})
      by_scale = Plot.scale_color_continuous(continuous, guide: :none)
      by_guides = Plot.guides(continuous, color: :none)
      other_aesthetic = Plot.guides(continuous, fill: :none)

      assert {guide_keys(by_scale), guide_keys(by_guides), length(guide_keys(other_aesthetic))} ===
               {[], [], 1}
    end

    test "a reversed legend's keys run from the last break, the missing value's key first" do
      discrete = guided(%{x: :x, y: :y, colour: :g})
      plot = Plot.guides(discrete, color: Plot.guide_legend(reverse: true))

      assert guide_keys(plot) === [
               {Guide.Legend, [:color],
                [
                  {"NA", %{color: "#7F7F7F"}},
                  {"c", %{color: "#619CFF"}},
                  {"b", %{color: "#00BA38"}},
                  {"a", %{color: "#F8766D"}}
                ]}
             ]
    end

    test "a continuous colour scale read by a legend has a key for each break, reversed or not" do
      continuous = guided(%{x: :x, y: :y, colour: :x})
      by_scale = Plot.scale_color_gradient(continuous, guide: :legend)
      by_guides = Plot.guides(continuous, color: :legend)
      reversed = Plot.guides(continuous, color: Plot.guide_legend(reverse: true))

      keys = [
        {"1", %{color: "#132B43"}},
        {"2", %{color: "#28547A"}},
        {"3", %{color: "#3E81B7"}},
        {"4", %{color: "#56B1F7"}}
      ]

      assert {guide_keys(by_scale), guide_keys(by_guides), guide_keys(reversed)} ===
               {[{Guide.Legend, [:color], keys}], [{Guide.Legend, [:color], keys}],
                [{Guide.Legend, [:color], Enum.reverse(keys)}]}
    end

    test "a colour bar guides/2 gives a discrete scale is refused when the plot is run" do
      discrete = guided(%{x: :x, y: :y, colour: :g})
      plot = Plot.guides(discrete, color: :colorbar)

      error = assert_raise ArgumentError, fn -> Assembly.run(plot) end

      assert error.message ==
               "Plot.guides/2 gives color a colour bar, which shows a continuous scale, and " <>
                 "color's scale is discrete; give it :legend"
    end

    test "legends reversed alike merge, and one reversed beside one not stays apart" do
      plot =
        @guide_rows
        |> Plot.new(%{x: :x, y: :y, colour: :g, fill: :g})
        |> Plot.geom_col()

      reversed = Plot.guide_legend(reverse: true)
      both = Plot.guides(plot, color: reversed, fill: reversed)
      one = Plot.guides(plot, color: reversed)

      assert {guide_keys(both), length(guide_keys(one))} ===
               {[
                  {Guide.Legend, [:color, :fill],
                   [
                     {"NA", %{color: "#7F7F7F", fill: "#7F7F7F"}},
                     {"c", %{color: "#619CFF", fill: "#619CFF"}},
                     {"b", %{color: "#00BA38", fill: "#00BA38"}},
                     {"a", %{color: "#F8766D", fill: "#F8766D"}}
                   ]}
                ], 2}
    end

    test "a guide for an aesthetic no layer maps draws nothing" do
      unmapped = guided(%{x: :x, y: :y})
      assert guide_keys(Plot.guides(unmapped, color: :legend)) === []
    end
  end
end
