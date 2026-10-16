defmodule Giggly.GeomTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, DataFrame, Geom}
  alias Giggly.Scene.{Circles, Rectangles}

  describe "draw_panel/4 for points" do
    test "a row missing its x or its y is not drawn" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0, nil, 2.0, 3.0], y: [1.0, 3.0, :nan, 2.0])

      assert [%Circles{x: [0.25, 0.75], y: [0.25, 0.5]}] =
               Geom.draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    test "each point is as opaque as its row's alpha, and opaque where it has none" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          x: [1.0, nil, 2.0, 3.0],
          y: [1.0, 1.0, 2.0, 3.0],
          alpha: [0.25, 0.5, nil, 1]
        )

      assert [%Circles{x: [0.25, 0.5, 0.75], opacity: [0.25, 1.0, 1.0]}] =
               Geom.draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    test "a table without alpha draws every point opaque" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0])

      assert [%Circles{opacity: [1.0, 1.0]}] =
               Geom.draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end
  end

  describe "draw_panel/4 for bars" do
    test "a bar missing an edge is not drawn" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          xmin: [0.0, nil, 2.0],
          xmax: [1.0, 2.0, 3.0],
          ymin: [0.0, 0.0, 0.0],
          ymax: [2.0, 1.0, 4.0]
        )

      assert [%Rectangles{} = rectangles] =
               Geom.draw_panel(%Geom.Bar{}, frame, coord, panel_params)

      assert {rectangles.xmin, rectangles.xmax, rectangles.ymin, rectangles.ymax} ===
               {[0.0, 0.5], [0.25, 0.75], [0.0, 0.0], [0.5, 1.0]}
    end

    test "each bar's fill is as opaque as its row's alpha, its border not, opaque without one" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          xmin: [0.0, nil, 2.0, 3.0],
          xmax: [1.0, 2.0, 3.0, 4.0],
          ymin: [0.0, 0.0, 0.0, 0.0],
          ymax: [2.0, 1.0, 4.0, 1.0],
          alpha: [0.5, 0.25, :nan, nil]
        )

      assert [%Rectangles{fill_opacity: [0.5, 1.0, 1.0], color: :none}] =
               Geom.draw_panel(%Geom.Bar{}, frame, coord, panel_params)

      without_alpha = DataFrame.new(xmin: [0.0], xmax: [1.0], ymin: [0.0], ymax: [2.0])

      assert [%Rectangles{fill_opacity: [1.0]}] =
               Geom.draw_panel(%Geom.Bar{}, without_alpha, coord, panel_params)
    end
  end

  # Golden: ggplot2 4.0.3's keys through vdiffr 1.0.9 (R 4.6.1), a 17.28-point key: a point at its
  # middle, and a bar's fill 15.86 points square, its border's 0.5 mm short of the key.
  describe "draw_key/3" do
    test "a point's key is the point at the middle of the key, at the key's alpha" do
      assert [%Circles{x: [0.5], y: [0.5], opacity: [0.2]}] =
               Geom.draw_key(%Geom.Point{}, %{alpha: 0.2}, {17.28, 17.28})

      assert [%Circles{opacity: [1.0]}] =
               Geom.draw_key(%Geom.Point{}, %{alpha: nil}, {17.28, 17.28})
    end

    test "a bar's key is its fill short of the key's edges by its border's width" do
      assert [%Rectangles{} = key] = Geom.draw_key(%Geom.Bar{}, %{alpha: 0.55}, {17.28, 17.28})

      [xmin] = key.xmin
      [xmax] = key.xmax
      [ymin] = key.ymin

      assert {Float.round((xmax - xmin) * 17.28, 2), Float.round(ymin * 17.28, 2),
              key.fill_opacity, key.color} === {15.86, 0.71, [0.55], :none}
    end
  end
end
