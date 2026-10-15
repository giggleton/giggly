defmodule Giggly.CoordTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, DataFrame}

  @cartesian %Coord.Cartesian{}
  @radial %Coord.Radial{}

  describe "transform/3" do
    test "x-family and y-family columns are placed 0 to 1 across the panel, infinities at its edges" do
      params = Coord.panel_params(@cartesian, {{0.0, 4.0}, [], []}, {{10.0, 20.0}, [], []})

      frame =
        DataFrame.new(
          x: [1.0, :infinity, nil, :nan],
          xend: [3.0, 2.0, 0.0, 4.0],
          y: [15.0, :neg_infinity, 20.0, 10.0],
          group: [1, 1, 2, 2]
        )

      placed = Coord.transform(@cartesian, frame, params)

      assert DataFrame.pull(placed, :x) === [0.25, 1.0, nil, :nan]
      assert DataFrame.pull(placed, :xend) === [0.75, 0.5, 0.0, 1.0]
      assert DataFrame.pull(placed, :y) === [0.5, 0.0, 1.0, 0.0]
      assert DataFrame.pull(placed, :group) === [1, 1, 2, 2]
    end

    test "on an axis whose extent has equal ends every position is at the middle, infinities too" do
      params = Coord.panel_params(@cartesian, {{1.0e16, 1.0e16}, [], []}, {{0.0, 1.0}, [], []})

      frame =
        DataFrame.new(x: [1.0e16, :infinity, :neg_infinity, nil], y: [0.0, 0.0, 0.0, 0.0])

      placed = Coord.transform(@cartesian, frame, params)

      assert DataFrame.pull(placed, :x) === [0.5, 0.5, 0.5, nil]
    end

    # Golden: ggplot2 4.0.3's `CoordRadial$transform()` on the same params (scales 1.4.0, R 4.6.1),
    # printed to 17 significant digits; a change to ggplot2's radial placing moves it.
    test "radial coordinates put x round the circle from 12 o'clock and y out from its centre" do
      params = Coord.panel_params(@radial, {{0.0, 4.0}, [], []}, {{10.0, 20.0}, [], []})

      frame =
        DataFrame.new(
          x: [1.0, :infinity, :neg_infinity, 3.0, nil, 2.0],
          y: [15.0, 20.0, :infinity, :neg_infinity, 12.0, :nan],
          group: [1, 1, 1, 2, 2, 2]
        )

      placed = Coord.transform(@radial, frame, params)

      assert DataFrame.pull(placed, :x) === [0.7, 0.5, 0.5, 0.5, nil, :nan]
      assert DataFrame.pull(placed, :y) === [0.5, 0.9, 0.9, 0.5, nil, :nan]
      assert DataFrame.pull(placed, :group) === [1, 1, 1, 2, 2, 2]
    end

    # Golden: ggplot2 4.0.3's `CoordRadial$transform()` on the same params (R 4.6.1).
    test "radially, an extent of equal ends puts every position half a turn round or halfway out" do
      equal_angles =
        Coord.panel_params(@radial, {{1.0e16, 1.0e16}, [], []}, {{0.0, 1.0}, [], []})

      frame = DataFrame.new(x: [1.0e16, :infinity, :neg_infinity], y: [0.5, 1.0, 0.0])
      placed = Coord.transform(@radial, frame, equal_angles)

      assert DataFrame.pull(placed, :x) === [0.5, 0.5, 0.5]
      assert DataFrame.pull(placed, :y) === [0.29999999999999999, 0.099999999999999978, 0.5]

      equal_radii = Coord.panel_params(@radial, {{0.0, 4.0}, [], []}, {{5.0, 5.0}, [], []})
      frame = DataFrame.new(x: [1.0, 2.0], y: [5.0, :neg_infinity])
      placed = Coord.transform(@radial, frame, equal_radii)

      assert DataFrame.pull(placed, :x) === [0.7, 0.5]
      assert DataFrame.pull(placed, :y) === [0.5, 0.29999999999999999]
    end

    test "radial coordinates refuse a range, which cannot be placed without its pair" do
      params = Coord.panel_params(@radial, {{0.0, 4.0}, [], []}, {{10.0, 20.0}, [], []})
      frame = DataFrame.new(x: [1.0], xend: [2.0], y: [15.0])

      assert_raise MatchError, fn -> Coord.transform(@radial, frame, params) end
    end
  end

  describe "axes/2" do
    test "a cartesian panel's x axis is at the bottom and its y axis on the left, breaks placed" do
      params =
        Coord.panel_params(
          @cartesian,
          {{0.0, 4.0}, [{1.0, "1"}, {3.0, "3"}], [2.0]},
          {{10.0, 20.0}, [{15.0, "15"}], []}
        )

      assert Coord.axes(@cartesian, params) === %{
               bottom: {:x, :x, [{0.25, "1"}, {0.75, "3"}]},
               left: {:y, :y, [{0.5, "15"}]}
             }
    end

    # Golden: ggplot2 4.0.3's axis keys for these extents, the radius axis's breaks placed at
    # minus infinity and the angle axis's at plus infinity, as its guides place them (R 4.6.1).
    test "a radial panel's radius axis is on its left, up the radius at 12 o'clock, and its angle axis round the circle" do
      params =
        Coord.panel_params(
          @radial,
          {{-0.5, 10.5}, [{0.0, "0.0"}, {5.0, "5.0"}, {10.0, "10.0"}], [2.5]},
          {{-2.5, 52.5}, [{0.0, "0"}, {50.0, "50"}], [25.0]}
        )

      assert Coord.axes(@radial, params) === %{
               bottom: {:x, :x, []},
               left: {:y, :r, [{0.51818181818181819, "0"}, {0.88181818181818183, "50"}]},
               theta:
                 {:x, :theta,
                  [
                    {{0.61269302273657189, 0.88379718944579899}, 0.28559933214452665, "0.0"},
                    {{0.5, 0.099999999999999978}, 3.14159265358979312, "5.0"},
                    {{0.38730697726342811, 0.88379718944579899}, 5.99758597503505975, "10.0"}
                  ]}
             }
    end
  end

  describe "grid/2" do
    test "a cartesian panel's major and minor lines cross it from edge to edge" do
      params =
        Coord.panel_params(
          @cartesian,
          {{0.0, 4.0}, [{1.0, "1"}, {3.0, "3"}], [2.0]},
          {{10.0, 20.0}, [{15.0, "15"}], [12.5, 17.5]}
        )

      assert Coord.grid(@cartesian, params) === %{
               major: %{
                 x: [[{0.25, 0.0}, {0.25, 1.0}], [{0.75, 0.0}, {0.75, 1.0}]],
                 y: [[{0.0, 0.5}, {1.0, 0.5}]]
               },
               minor: %{
                 x: [[{0.5, 0.0}, {0.5, 1.0}]],
                 y: [[{0.0, 0.25}, {1.0, 0.25}], [{0.0, 0.75}, {1.0, 0.75}]]
               },
               background: :panel
             }
    end

    test "across an axis whose extent has equal ends a line shrinks to a point at the middle" do
      params =
        Coord.panel_params(
          @cartesian,
          {{1.0e16, 1.0e16}, [{1.0e16, "10000000000000000"}], []},
          {{0.0, 1.0}, [{0.5, "0.5"}], []}
        )

      assert Coord.grid(@cartesian, params).major === %{
               x: [[{0.5, 0.0}, {0.5, 1.0}]],
               y: [[{0.5, 0.5}, {0.5, 0.5}]]
             }
    end
  end

  describe "grid/2, radially" do
    # Golden: ggplot2 4.0.3's `coord_munch()` on the same params, as `guide_grid()` munches a grid
    # that is not rectangular (R 4.6.1); a change to its segment length, boost or distance moves the
    # counts. The circle is at a small radius so it is cut into few steps, listed whole.
    setup do
      params =
        Coord.panel_params(
          @radial,
          {{0.0, 4.0}, [], [1.0]},
          {{0.0, 100.0}, [{1.0, "1"}], []}
        )

      %{grid: Coord.grid(@radial, params)}
    end

    test "a circle runs round at a radius's break, cut finer the longer it is", %{grid: grid} do
      assert grid.major.y === [
               [
                 {0.5, 0.504},
                 {0.5038042260651806, 0.50123606797749976},
                 {0.50235114100916989, 0.49676393202250019},
                 {0.49764885899083011, 0.49676393202250019},
                 {0.4961957739348194, 0.50123606797749976},
                 {0.5, 0.504}
               ]
             ]

      assert grid.minor.y === []
    end

    test "a spoke runs from the centre to the edge at an angle's break", %{grid: grid} do
      assert grid.major.x === []
      assert [spoke] = grid.minor.x
      assert length(spoke) === 30

      assert [Enum.at(spoke, 0), Enum.at(spoke, 1), List.last(spoke)] === [
               {0.5, 0.5},
               {0.51379310344827589, 0.5},
               {0.90000000000000002, 0.5}
             ]
    end

    test "the background is the disc, down the spoke at 12 o'clock and round the edge", %{
      grid: grid
    } do
      assert length(grid.background) === 244

      assert Enum.map([0, 1, 29, 30, 31, 59, 60, 61, 243], fn index ->
               Enum.at(grid.background, index)
             end) === [
               {0.5, 0.90000000000000002},
               {0.5, 0.88620689655172413},
               {0.5, 0.5},
               {0.5, 0.5},
               {0.5, 0.51379310344827589},
               {0.5, 0.90000000000000002},
               {0.51358265392029956, 0.89976932287568212},
               {0.52714964180286428, 0.89907755756240681},
               {0.48641734607970055, 0.89976932287568212}
             ]
    end
  end

  describe "clip/1" do
    test "cartesian coordinates clip each panel by default, as ggplot2's do" do
      assert Coord.clip(%Coord.Cartesian{}) == :on
    end

    test "radial coordinates clip no panel by default, as ggplot2's do" do
      assert Coord.clip(%Coord.Radial{}) == :off
    end
  end

  describe "aspect/2" do
    test "a cartesian panel takes whatever shape the drawing leaves it" do
      params = Coord.panel_params(@cartesian, {{0.0, 4.0}, [], []}, {{10.0, 20.0}, [], []})
      assert Coord.aspect(@cartesian, params) === :none
    end

    test "a radial panel is square" do
      params = Coord.panel_params(@radial, {{0.0, 4.0}, [], []}, {{10.0, 20.0}, [], []})
      assert Coord.aspect(@radial, params) === 1.0
    end
  end
end
