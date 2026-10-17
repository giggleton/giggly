defmodule Giggly.AssemblyTest do
  use ExUnit.Case, async: true

  alias Giggly.{Assembly, Geom, Guide, Plot}

  # Golden throughout: ggplot2 4.0.3's `get_guide_data()` for the same plot in R 4.6.1, printed to
  # 17 significant digits. It moves with ggplot2's default alpha scales or how a legend's keys are
  # chosen.
  describe "run/1, legends" do
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
                   aesthetics: [:alpha],
                   fixed: %{},
                   draws: [true, true, true, true, true]
                 }
               ]
             }
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
                    geom: %Geom.Bar{},
                    aesthetics: [:alpha],
                    fixed: %{},
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
                   geom: %Geom.Bar{},
                   aesthetics: [:color, :fill],
                   fixed: %{},
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
                    geom: %Geom.Bar{},
                    aesthetics: [:fill],
                    fixed: %{},
                    draws: [true, true, true]
                  },
                  %{
                    geom: %Geom.Point{},
                    aesthetics: [:color],
                    fixed: %{},
                    draws: [true, true, true]
                  }
                ]}
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
                 geom: %Geom.Bar{},
                 aesthetics: [:alpha],
                 fixed: %{},
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

    test "an aesthetic whose every column a stat dropped has no legend" do
      assembly =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, alpha: :year})
        |> Plot.geom_bar()
        |> Assembly.run()

      assert assembly.legends === []
    end
  end
end
