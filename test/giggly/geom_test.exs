defmodule Giggly.GeomTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, DataFrame, Geom}
  alias Giggly.Scene.{Circles, Polylines, Rectangles, Segments}

  @path %Geom.Path{line_end: :butt, line_join: :round, mitre_limit: 10.0}
  @line %Geom.Line{orientation: :x, line_end: :butt, line_join: :round, mitre_limit: 10.0}

  # A 0.5 mm line, ggplot2's default, in points: `0.5 * .pt` line-width units of 1/96 inch, as
  # ggplot2 and svglite work it out.
  @default_width 0.5 * (72.27 / 25.4) / 96 * 72
  @two_millimetres 2.0 * (72.27 / 25.4) / 96 * 72

  # A colour's own alpha of 80, half-opaque: R holds it as the byte 128, so its opacity is 128/255.
  @half_alpha 128 / 255

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

      assert [%Circles{opacity: [1.0, 1.0], color: "#000000"}] =
               Geom.draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    # Golden: svglite's drawing of ggplot2 4.0.3's points coloured "#FF000080" with an alpha mapped
    # to 0.2 and NA, through vdiffr 1.0.9: 0.20, and the colour's own 0.50.
    test "a point is drawn in the colour its layer sets, its row's alpha replacing the colour's own" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          x: [1.0, 2.0],
          y: [1.0, 2.0],
          alpha: [0.2, nil],
          color: ["#FF000080", "#FF000080"]
        )

      assert [%Circles{color: "#FF0000", opacity: [0.2, @half_alpha]}] =
               Geom.draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    test "a colour of :none draws no point, as ggplot2 drops a point whose colour is NA" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0], color: [:none, :none])

      assert Geom.draw_panel(%Geom.Point{}, frame, coord, panel_params) === []
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

      assert [%Rectangles{fill_opacity: [1.0], fill: "#595959", color_opacity: +0.0}] =
               Geom.draw_panel(%Geom.Bar{}, without_alpha, coord, panel_params)
    end

    # Golden: svglite's drawing of ggplot2 4.0.3's `geom_col(fill = "#0000FF80", colour =
    # "#FF000080")` with an alpha of 0.3 and of none, through vdiffr 1.0.9: the fill 0.30 and the
    # fill's own 0.50, the border its own 0.50 whatever the alpha.
    test "a bar is filled and bordered as its layer sets, the alpha its fill's alone" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          xmin: [0.0, 2.0],
          xmax: [1.0, 3.0],
          ymin: [0.0, 0.0],
          ymax: [2.0, 4.0],
          alpha: [0.3, nil],
          fill: ["#0000FF80", "#0000FF80"],
          color: ["#FF000080", "#FF000080"]
        )

      assert [%Rectangles{} = rectangles] =
               Geom.draw_panel(%Geom.Bar{}, frame, coord, panel_params)

      assert {rectangles.fill, rectangles.fill_opacity, rectangles.color,
              rectangles.color_opacity} ===
               {"#0000FF", [0.3, @half_alpha], "#FF0000", @half_alpha}
    end

    test "a fill of :none is no fill at all, whatever the alpha" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          xmin: [0.0],
          xmax: [1.0],
          ymin: [0.0],
          ymax: [2.0],
          alpha: [0.5],
          fill: [:none],
          color: ["#FF0000"]
        )

      assert [
               %Rectangles{
                 fill: :none,
                 fill_opacity: [+0.0],
                 color: "#FF0000",
                 color_opacity: 1.0
               }
             ] =
               Geom.draw_panel(%Geom.Bar{}, frame, coord, panel_params)
    end
  end

  # Golden: ggplot2 4.0.3's keys through vdiffr 1.0.9 (R 4.6.1), a 17.28-point key: a point at its
  # middle, and a bar's fill 15.86 points square, its border's 0.5 mm short of the key.
  describe "setup_data/3 for lines" do
    test "rows are put in order of panel, group and x, rows that tie keeping their order" do
      frame =
        DataFrame.new(
          x: [2.0, 3.0, 1.0, 2.0, 0.0],
          y: [1.0, 2.0, 3.0, 4.0, 5.0],
          panel: [1, 1, 1, 1, 2],
          group: [1, 2, 1, 1, 1]
        )

      set_up = Geom.setup_data(@line, frame, %{x: :continuous, y: :continuous})

      assert DataFrame.pull(set_up, :y) === [3.0, 1.0, 4.0, 2.0, 5.0]
    end

    test "a line oriented along y puts its rows in order of y" do
      frame =
        DataFrame.new(x: [1.0, 2.0, 3.0], y: [3.0, 1.0, 2.0], panel: [1, 1, 1], group: [1, 1, 1])

      set_up =
        Geom.setup_data(%{@line | orientation: :y}, frame, %{x: :continuous, y: :continuous})

      assert DataFrame.pull(set_up, :x) === [2.0, 3.0, 1.0]
    end

    # R's `order()` puts minus infinity first, plus infinity after the numbers and `NA` last.
    test "an infinite position sorts at its end, and a missing one after every other" do
      frame =
        DataFrame.new(
          x: [nil, 2.0, :infinity, :neg_infinity, 1.0, :nan],
          y: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
          panel: [1, 1, 1, 1, 1, 1],
          group: [1, 1, 1, 1, 1, 1]
        )

      set_up = Geom.setup_data(@line, frame, %{x: :continuous, y: :continuous})

      assert DataFrame.pull(set_up, :y) === [4.0, 5.0, 2.0, 3.0, 1.0, 6.0]
    end

    test "a path keeps the data's order" do
      frame =
        DataFrame.new(x: [3.0, 1.0, 2.0], y: [1.0, 2.0, 3.0], panel: [1, 1, 1], group: [1, 1, 1])

      assert Geom.setup_data(@path, frame, %{x: :continuous, y: :continuous}) === frame
    end
  end

  describe "draw_panel/4 for paths" do
    setup do
      coord = %Coord.Cartesian{}

      %{
        coord: coord,
        params: Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      }
    end

    test "a group's rows missing a position are dropped at its ends and break it in the middle",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 1.0, 2.0, 3.0, 4.0, 4.0, 3.0],
          y: [nil, 1.0, 2.0, :nan, 3.0, 4.0, nil],
          group: [1, 1, 1, 1, 1, 1, 1]
        )

      assert [%Polylines{lines: lines}] = Geom.draw_panel(@path, frame, coord, params)
      assert lines === [[{0.25, 0.25}, {0.5, 0.5}], [{1.0, 0.75}, {1.0, 1.0}]]
    end

    test "a piece of one point between missing positions draws nothing",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 2.0, 3.0, 4.0], y: [1.0, nil, 2.0, 3.0], group: [1, 1, 1, 1])

      assert [%Polylines{lines: [[{0.75, 0.5}, {1.0, 0.75}]]}] =
               Geom.draw_panel(@path, frame, coord, params)
    end

    test "each group is a line in group order, in the alpha of its first row",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 4.0, 4.0, 0.0],
          y: [4.0, 0.0, 4.0, 0.0],
          group: [2, 1, 2, 1],
          alpha: [0.5, 0.25, 0.5, 0.25]
        )

      assert [%Polylines{} = polylines] = Geom.draw_panel(@path, frame, coord, params)
      assert polylines.lines === [[{1.0, 0.0}, {0.0, 0.0}], [{0.0, 1.0}, {1.0, 1.0}]]
      assert polylines.opacity === [0.25, 0.5]
    end

    test "a group of one row is not drawn, and a panel with no group of two draws nothing",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 2.0, 3.0], y: [1.0, 2.0, 3.0], group: [1, 1, 2])

      assert [%Polylines{lines: [[{0.25, 0.25}, {0.5, 0.5}]]}] =
               Geom.draw_panel(@path, frame, coord, params)

      single = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0], group: [1, 2])
      assert Geom.draw_panel(@path, single, coord, params) === []
    end

    test "where a group's alpha varies, every group is drawn as segments, each in its start's alpha",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 1.0, 2.0, 3.0, 4.0, 0.0, 4.0],
          y: [0.0, 1.0, nil, 3.0, 4.0, 4.0, 4.0],
          group: [1, 1, 1, 1, 1, 2, 2],
          alpha: [0.1, 0.2, 0.3, 0.4, 0.5, 1.0, 1.0]
        )

      assert [%Segments{} = segments] = Geom.draw_panel(@path, frame, coord, params)
      assert segments.starts === [{0.0, 0.0}, {0.75, 0.75}, {0.0, 1.0}]
      assert segments.ends === [{0.25, 0.25}, {1.0, 1.0}, {1.0, 1.0}]
      assert segments.opacity === [0.1, 0.4, 1.0]
    end

    test "every line is as wide as the layer sets, and ended, joined and mitred as the geom says",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0], group: [1, 1], linewidth: [2.0, 2.0])
      geom = %Geom.Path{line_end: :round, line_join: :mitre, mitre_limit: 4.0}

      assert [%Polylines{} = polylines] = Geom.draw_panel(geom, frame, coord, params)

      assert {polylines.stroke_width, polylines.line_end, polylines.line_join,
              polylines.mitre_limit} === {@two_millimetres, :round, :mitre, 4.0}
    end

    test "a table without alpha or a line width draws opaque lines ggplot2's default width",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0], group: [1, 1])

      assert [%Polylines{opacity: [1.0], stroke_width: @default_width, color: "#000000"}] =
               Geom.draw_panel(@path, frame, coord, params)
    end

    test "a line is drawn in the colour its layer sets, its row's alpha replacing the colour's own",
         %{coord: coord, params: params} do
      own =
        DataFrame.new(
          x: [1.0, 2.0],
          y: [1.0, 2.0],
          group: [1, 1],
          color: ["#FF000080", "#FF000080"]
        )

      assert [%Polylines{color: "#FF0000", opacity: [@half_alpha]}] =
               Geom.draw_panel(@path, own, coord, params)

      replaced = DataFrame.put(own, :alpha, [0.2, 0.4])

      assert [%Segments{color: "#FF0000", opacity: [0.2]}] =
               Geom.draw_panel(@path, replaced, coord, params)
    end

    test "a colour of :none draws no line, as ggplot2 drops the rows whose colour is NA",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0], group: [1, 1], color: [:none, :none])

      assert Geom.draw_panel(@path, frame, coord, params) === []
    end

    test "a line is drawn as a path through its rows", %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 3.0, 2.0], y: [1.0, 2.0, 3.0], group: [1, 1, 1])

      assert Geom.draw_panel(@line, frame, coord, params) ===
               Geom.draw_panel(@path, frame, coord, params)
    end
  end

  describe "draw_key/3" do
    test "a point's key is the point at the middle of the key, at the key's alpha" do
      assert [%Circles{x: [0.5], y: [0.5], opacity: [0.2]}] =
               Geom.draw_key(%Geom.Point{}, %{alpha: 0.2}, {17.28, 17.28})

      assert [%Circles{opacity: [1.0]}] =
               Geom.draw_key(%Geom.Point{}, %{alpha: nil}, {17.28, 17.28})
    end

    test "a point's key is in the colour its layer sets, the key's alpha replacing the colour's own" do
      assert [%Circles{color: "#4682B4", opacity: [0.2]}] =
               Geom.draw_key(%Geom.Point{}, %{alpha: 0.2, color: "#4682B480"}, {17.28, 17.28})

      assert [%Circles{color: "#4682B4", opacity: [@half_alpha]}] =
               Geom.draw_key(%Geom.Point{}, %{alpha: nil, color: "#4682B480"}, {17.28, 17.28})

      assert Geom.draw_key(%Geom.Point{}, %{alpha: 0.2, color: :none}, {17.28, 17.28}) === []
    end

    test "a bar's key is its fill short of the key's edges by its border's width" do
      assert [%Rectangles{} = key] = Geom.draw_key(%Geom.Bar{}, %{alpha: 0.55}, {17.28, 17.28})

      [xmin] = key.xmin
      [xmax] = key.xmax
      [ymin] = key.ymin

      assert {Float.round((xmax - xmin) * 17.28, 2), Float.round(ymin * 17.28, 2),
              key.fill_opacity, key.color} === {15.86, 0.71, [0.55], :none}
    end

    test "a bar's key is filled and bordered as its layer sets, the key's alpha its fill's alone" do
      key = %{alpha: 0.3, fill: "#0000FF80", color: "#FF000080"}

      assert [%Rectangles{} = drawn] = Geom.draw_key(%Geom.Bar{}, key, {17.28, 17.28})

      assert {drawn.fill, drawn.fill_opacity, drawn.color, drawn.color_opacity} ===
               {"#0000FF", [0.3], "#FF0000", @half_alpha}
    end

    # ggplot2's `draw_key_path()`: a segment from a tenth of the key's width to nine tenths, at
    # mid-height, ended as the layer's lines are, its corners grid's default.
    test "a path's key is a line across the middle of the key, as wide as the layer sets" do
      geom = %Geom.Path{line_end: :square, line_join: :mitre, mitre_limit: 4.0}

      assert [%Segments{} = key] =
               Geom.draw_key(geom, %{alpha: 0.4, linewidth: 2.0}, {17.28, 17.28})

      assert {key.starts, key.ends, key.opacity, key.stroke_width} ===
               {[{0.1, 0.5}], [{0.9, 0.5}], [0.4], @two_millimetres}

      assert {key.line_end, key.line_join, key.mitre_limit} === {:square, :round, 10.0}
    end

    test "a line's key is a path's, ggplot2's default width where the layer sets none" do
      assert Geom.draw_key(@line, %{alpha: nil}, {17.28, 17.28}) ===
               Geom.draw_key(@path, %{alpha: nil}, {17.28, 17.28})

      assert [%Segments{opacity: [1.0], stroke_width: @default_width}] =
               Geom.draw_key(@path, %{alpha: nil}, {17.28, 17.28})
    end

    test "a path's key is in the colour its layer sets, and a colour of :none draws none" do
      assert [%Segments{color: "#FF0000", opacity: [@half_alpha]}] =
               Geom.draw_key(@path, %{alpha: nil, color: "#FF000080"}, {17.28, 17.28})

      assert Geom.draw_key(@path, %{alpha: 0.4, color: :none}, {17.28, 17.28}) === []
    end
  end
end
