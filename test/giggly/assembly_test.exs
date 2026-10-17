defmodule Giggly.AssemblyTest do
  use ExUnit.Case, async: true

  alias Giggly.{Assembly, Geom, Plot}

  # Golden throughout: ggplot2 4.0.3's `get_guide_data()` for the same plot in R 4.6.1, printed to
  # 17 significant digits. It moves with ggplot2's default alpha scales or how a legend's keys are
  # chosen.
  describe "run/1, legends" do
    test "a mapped alpha's legend is titled by its column, a key for each break at its alpha" do
      [legend] =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, alpha: :year})
        |> Plot.geom_point()
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert legend === %{
               aesthetics: [:alpha],
               title: "year",
               keys: [
                 %{label: "2000", values: %{alpha: 0.2}},
                 %{label: "2002", values: %{alpha: 0.4}},
                 %{label: "2004", values: %{alpha: 0.6}},
                 %{label: "2006", values: %{alpha: 0.8}},
                 %{label: "2008", values: %{alpha: 1.0}}
               ],
               layers: [%{geom: %Geom.Point{}, aesthetics: [:alpha], fixed: %{}}]
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
                  %{label: "4", values: %{alpha: 0.1}},
                  %{label: "f", values: %{alpha: 0.55}},
                  %{label: "r", values: %{alpha: 1.0}}
                ], [%{geom: %Geom.Bar{}, aesthetics: [:alpha], fixed: %{}}]}
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
                  %{label: "a", values: %{color: "#F8766D"}},
                  %{label: "b", values: %{color: "#00BFC4"}},
                  %{label: "NA", values: %{color: "#7F7F7F"}}
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
               aesthetics: [:color, :fill],
               title: "g",
               keys: [
                 %{label: "a", values: %{color: "#F8766D", fill: "#F8766D"}},
                 %{label: "b", values: %{color: "#00BFC4", fill: "#00BFC4"}},
                 %{label: "NA", values: %{color: "#7F7F7F", fill: "#7F7F7F"}}
               ],
               layers: [%{geom: %Geom.Bar{}, aesthetics: [:color, :fill], fixed: %{}}]
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
                  %{geom: %Geom.Bar{}, aesthetics: [:fill], fixed: %{}},
                  %{geom: %Geom.Point{}, aesthetics: [:color], fixed: %{}}
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

      assert legend.layers === [%{geom: %Geom.Bar{}, aesthetics: [:alpha], fixed: %{}}]
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
