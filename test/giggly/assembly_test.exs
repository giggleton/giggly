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
               aesthetic: :alpha,
               title: "year",
               keys: [
                 %{label: "2000", value: 0.2},
                 %{label: "2002", value: 0.4},
                 %{label: "2004", value: 0.6},
                 %{label: "2006", value: 0.8},
                 %{label: "2008", value: 1.0}
               ],
               layers: [%{geom: %Geom.Point{}, fixed: %{}}]
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
                  %{label: "4", value: 0.1},
                  %{label: "f", value: 0.55},
                  %{label: "r", value: 1.0}
                ], [%{geom: %Geom.Bar{}, fixed: %{}}]}
    end

    test "only the layers that map the aesthetic draw its keys; one that sets it does not" do
      [legend] =
        %{"x" => [1, 2], "y" => [1, 2], "a" => [1.0, 2.0]}
        |> Plot.new(%{x: :x, y: :y, alpha: :a})
        |> Plot.geom_col()
        |> Plot.geom_point(alpha: 0.5)
        |> Assembly.run()
        |> Map.fetch!(:legends)

      assert legend.layers === [%{geom: %Geom.Bar{}, fixed: %{}}]
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
