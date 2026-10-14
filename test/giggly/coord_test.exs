defmodule Giggly.CoordTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, DataFrame}

  describe "transform/2" do
    test "x-family and y-family columns are placed 0 to 1 across the panel, infinities at its edges" do
      params = Coord.panel_params(:cartesian, {{0.0, 4.0}, [], []}, {{10.0, 20.0}, [], []})

      frame =
        DataFrame.new(
          x: [1.0, :infinity, nil, :nan],
          xend: [3.0, 2.0, 0.0, 4.0],
          y: [15.0, :neg_infinity, 20.0, 10.0],
          group: [1, 1, 2, 2]
        )

      placed = Coord.transform(frame, params)

      assert DataFrame.pull(placed, :x) === [0.25, 1.0, nil, :nan]
      assert DataFrame.pull(placed, :xend) === [0.75, 0.5, 0.0, 1.0]
      assert DataFrame.pull(placed, :y) === [0.5, 0.0, 1.0, 0.0]
      assert DataFrame.pull(placed, :group) === [1, 1, 2, 2]
    end

    test "on an axis whose extent has equal ends every position is at the middle, infinities too" do
      params = Coord.panel_params(:cartesian, {{1.0e16, 1.0e16}, [], []}, {{0.0, 1.0}, [], []})

      frame =
        DataFrame.new(x: [1.0e16, :infinity, :neg_infinity, nil], y: [0.0, 0.0, 0.0, 0.0])

      placed = Coord.transform(frame, params)

      assert DataFrame.pull(placed, :x) === [0.5, 0.5, 0.5, nil]
    end
  end

  describe "axes/1" do
    test "a cartesian panel's x axis is at the bottom and its y axis on the left, breaks placed" do
      params =
        Coord.panel_params(
          :cartesian,
          {{0.0, 4.0}, [{1.0, "1"}, {3.0, "3"}], [2.0]},
          {{10.0, 20.0}, [{15.0, "15"}], []}
        )

      assert Coord.axes(params) === %{
               bottom: {:x, [{0.25, "1"}, {0.75, "3"}]},
               left: {:y, [{0.5, "15"}]}
             }
    end
  end

  describe "grid/1" do
    test "a cartesian panel's major and minor lines cross it from edge to edge" do
      params =
        Coord.panel_params(
          :cartesian,
          {{0.0, 4.0}, [{1.0, "1"}, {3.0, "3"}], [2.0]},
          {{10.0, 20.0}, [{15.0, "15"}], [12.5, 17.5]}
        )

      assert Coord.grid(params) === %{
               major: %{
                 x: [[{0.25, 0.0}, {0.25, 1.0}], [{0.75, 0.0}, {0.75, 1.0}]],
                 y: [[{0.0, 0.5}, {1.0, 0.5}]]
               },
               minor: %{
                 x: [[{0.5, 0.0}, {0.5, 1.0}]],
                 y: [[{0.0, 0.25}, {1.0, 0.25}], [{0.0, 0.75}, {1.0, 0.75}]]
               }
             }
    end

    test "across an axis whose extent has equal ends a line shrinks to a point at the middle" do
      params =
        Coord.panel_params(
          :cartesian,
          {{1.0e16, 1.0e16}, [{1.0e16, "10000000000000000"}], []},
          {{0.0, 1.0}, [{0.5, "0.5"}], []}
        )

      assert Coord.grid(params).major === %{
               x: [[{0.5, 0.0}, {0.5, 1.0}]],
               y: [[{0.5, 0.5}, {0.5, 0.5}]]
             }
    end
  end

  describe "clip/1" do
    test "cartesian coordinates clip the panel, ggplot2's default" do
      params = Coord.panel_params(:cartesian, {{0.0, 1.0}, [], []}, {{0.0, 1.0}, [], []})

      assert Coord.clip(params) == :on
    end
  end
end
