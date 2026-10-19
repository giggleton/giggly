defmodule Giggly.GeomTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, DataFrame, Font, Geom}
  alias Giggly.Scene.{Circles, Polylines, Rectangles, Segments, Text}

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

      assert [%Circles{opacity: [1.0, 1.0], color: ["#000000", "#000000"]}] =
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

      assert [%Circles{color: ["#FF0000", "#FF0000"], opacity: [0.2, @half_alpha]}] =
               Geom.draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    test "each point is drawn in its row's colour, as a mapped colour gives one per row" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          x: [1.0, 2.0, 3.0],
          y: [1.0, 2.0, 3.0],
          color: ["#F8766D", "#00BA3880", "#7F7F7F"]
        )

      assert [
               %Circles{
                 color: ["#F8766D", "#00BA38", "#7F7F7F"],
                 opacity: [1.0, @half_alpha, 1.0]
               }
             ] =
               Geom.draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    test "a colour of :none, or a missing one, draws no point, as ggplot2 drops one whose colour is NA" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0], color: [:none, nil])

      drawn = Geom.draw_panel(%Geom.Point{}, frame, coord, panel_params)

      assert Enum.flat_map(drawn, fn %Circles{x: x_places} -> x_places end) === []
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

      assert [%Rectangles{fill_opacity: [0.5, 1.0, 1.0], color: [:none, :none, :none]}] =
               Geom.draw_panel(%Geom.Bar{}, frame, coord, panel_params)

      without_alpha = DataFrame.new(xmin: [0.0], xmax: [1.0], ymin: [0.0], ymax: [2.0])

      assert [%Rectangles{fill_opacity: [1.0], fill: ["#595959"], color_opacity: [+0.0]}] =
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
               {["#0000FF", "#0000FF"], [0.3, @half_alpha], ["#FF0000", "#FF0000"],
                [@half_alpha, @half_alpha]}
    end

    test "each bar is filled and bordered in its row's colours, as mapped colours give them" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          xmin: [0.0, 2.0],
          xmax: [1.0, 3.0],
          ymin: [0.0, 0.0],
          ymax: [2.0, 4.0],
          fill: ["#F8766D", "#00BFC480"],
          color: ["#7F7F7F", "#00000080"]
        )

      assert [%Rectangles{} = rectangles] =
               Geom.draw_panel(%Geom.Bar{}, frame, coord, panel_params)

      assert {rectangles.fill, rectangles.fill_opacity, rectangles.color,
              rectangles.color_opacity} ===
               {["#F8766D", "#00BFC4"], [1.0, @half_alpha], ["#7F7F7F", "#000000"],
                [1.0, @half_alpha]}
    end

    test "a fill or border of :none, or a missing one, is none at all, whatever the alpha" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          xmin: [0.0, 1.0],
          xmax: [1.0, 2.0],
          ymin: [0.0, 0.0],
          ymax: [2.0, 2.0],
          alpha: [0.5, 0.5],
          fill: [:none, nil],
          color: ["#FF0000", nil]
        )

      assert [
               %Rectangles{
                 fill: [:none, :none],
                 fill_opacity: [+0.0, +0.0],
                 color: ["#FF0000", :none],
                 color_opacity: [1.0, +0.0]
               }
             ] =
               Geom.draw_panel(%Geom.Bar{}, frame, coord, panel_params)
    end
  end

  describe "draw_panel/4 for rectangles" do
    test "a rectangle is placed between its corners as given, reversed or infinite" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          xmin: [1.0, :neg_infinity, nil],
          xmax: [0.0, 2.0, 1.0],
          ymin: [4.0, 1.0, 0.0],
          ymax: [2.0, :infinity, 1.0]
        )

      assert [%Rectangles{} = rectangles] =
               Geom.draw_panel(%Geom.Rect{}, frame, coord, panel_params)

      assert {rectangles.xmin, rectangles.xmax, rectangles.ymin, rectangles.ymax} ===
               {[0.25, 0.0], [0.0, 0.5], [1.0, 0.25], [0.5, 1.0]}
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

      assert [%Polylines{opacity: [1.0], stroke_width: @default_width, color: ["#000000"]}] =
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

      assert [%Polylines{color: ["#FF0000"], opacity: [@half_alpha]}] =
               Geom.draw_panel(@path, own, coord, params)

      replaced = DataFrame.put(own, :alpha, [0.2, 0.4])

      assert [%Segments{color: ["#FF0000"], opacity: [0.2]}] =
               Geom.draw_panel(@path, replaced, coord, params)
    end

    test "each group's line is in its first row's colour, as a mapped colour gives one per group",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 4.0, 0.0, 4.0],
          y: [0.0, 4.0, 4.0, 0.0],
          group: [1, 1, 2, 2],
          color: ["#F8766D", "#F8766D", "#00BFC480", "#00BFC480"]
        )

      assert [%Polylines{color: ["#F8766D", "#00BFC4"], opacity: [1.0, @half_alpha]}] =
               Geom.draw_panel(@path, frame, coord, params)
    end

    test "where a group's colour varies, every group is drawn as segments, each in its start's colour",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 1.0, 2.0, 0.0, 4.0],
          y: [0.0, 1.0, 2.0, 4.0, 4.0],
          group: [1, 1, 1, 2, 2],
          color: ["#F8766D", "#00BA38", "#619CFF", "#7F7F7F", "#7F7F7F"]
        )

      assert [%Segments{} = segments] = Geom.draw_panel(@path, frame, coord, params)
      assert segments.starts === [{0.0, 0.0}, {0.25, 0.25}, {0.0, 1.0}]
      assert segments.color === ["#F8766D", "#00BA38", "#7F7F7F"]
      assert segments.opacity === [1.0, 1.0, 1.0]
    end

    test "a colour of :none, or a missing one, draws no line, as ggplot2 drops rows whose colour is NA",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0], group: [1, 1], color: [:none, :none])

      missing =
        DataFrame.new(
          x: [1.0, 2.0, 3.0],
          y: [1.0, 2.0, 3.0],
          group: [1, 1, 1],
          color: [nil, "#FF0000", "#FF0000"]
        )

      assert Geom.draw_panel(@path, frame, coord, params) === []

      assert [%Polylines{lines: [[{0.5, 0.5}, {0.75, 0.75}]], color: ["#FF0000"]}] =
               Geom.draw_panel(@path, missing, coord, params)
    end

    test "a line is drawn as a path through its rows", %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 3.0, 2.0], y: [1.0, 2.0, 3.0], group: [1, 1, 1])

      assert Geom.draw_panel(@line, frame, coord, params) ===
               Geom.draw_panel(@path, frame, coord, params)
    end
  end

  describe "draw_panel/4 for text" do
    setup do
      coord = %Coord.Cartesian{}
      params = Coord.panel_params(coord, {{0.0, 1.0}, [], []}, {{0.0, 1.0}, [], []})
      %{coord: coord, params: params}
    end

    # Each row's place, label and the text the geom draws it in, from a frame of one row per label.
    defp text(frame, %{coord: coord, params: params}, geom \\ %Geom.Text{check_overlap: false}) do
      [%Text{} = text] = Geom.draw_panel(geom, frame, coord, params)
      text
    end

    test "a row missing its x, its y or its label is not drawn", context do
      frame =
        DataFrame.new(
          x: [0.2, nil, 0.4, 0.6, 0.8],
          y: [0.2, 0.2, :nan, 0.6, 0.8],
          label: ["a", "b", "c", nil, "e"]
        )

      assert %Text{x: [0.2, 0.8], y: [0.2, 0.8], labels: ["a", "e"]} = text(frame, context)
    end

    test "a colour of :none, or a missing one, draws no label, as ggplot2 drops text whose colour is NA",
         context do
      frame = DataFrame.new(x: [0.2, 0.4], y: [0.2, 0.4], label: ["a", "b"], color: [:none, nil])

      assert %Text{labels: []} = text(frame, context)
    end

    test "a label is written as R's as.character() writes its value", context do
      frame = DataFrame.new(x: [0.5, 0.5], y: [0.5, 0.5], label: [1.0e5, 21.0])
      flags = DataFrame.new(x: [0.5], y: [0.5], label: [true])

      assert {text(frame, context).labels, text(flags, context).labels} ===
               {["1e+05", "21"], ["TRUE"]}
    end

    # Golden: ggplot2 4.0.3's `compute_just()` of the same places, each label's x (`a`) and y (`b`),
    # turned 0, 90, 136 and 270 degrees.
    test "a label justified inward or outward is justified by where it falls", context do
      frame =
        DataFrame.new(
          x: [0.2, 0.5, 0.8, 0.2, 0.8, 0.4995],
          y: [0.9, 0.9, 0.1, 0.1, 0.9, 0.9],
          label: ["a", "b", "c", "d", "e", "f"]
        )

      hjusts = fn just, angle ->
        rows = DataFrame.row_count(frame)

        frame
        |> DataFrame.put(:hjust, List.duplicate(just, rows))
        |> DataFrame.put(:angle, List.duplicate(angle, rows))
        |> text(context)
        |> Map.fetch!(:hjust)
      end

      assert Enum.map([0.0, 90.0, 136.0, 270.0], fn angle ->
               {hjusts.(:inward, angle), hjusts.(:outward, angle)}
             end) === [
               {[0.0, 0.5, 1.0, 0.0, 1.0, 0.5], [1.0, 0.5, 0.0, 1.0, 0.0, 0.5]},
               {[1.0, 1.0, 0.0, 0.0, 1.0, 1.0], [0.0, 0.0, 1.0, 1.0, 0.0, 0.0]},
               {[1.0, 0.5, 0.0, 1.0, 0.0, 0.5], [0.0, 0.5, 1.0, 0.0, 1.0, 0.5]},
               {[0.0, 0.0, 1.0, 1.0, 0.0, 0.0], [1.0, 1.0, 0.0, 0.0, 1.0, 1.0]}
             ]
    end

    test "a label's vjust lowers its baseline that part of its ascent, a word by where it falls",
         context do
      ascent = Font.ascent(11.0)

      frame =
        DataFrame.new(
          x: [0.5, 0.5, 0.5],
          y: [0.2, 0.9, 0.5],
          label: ["a", "b", "c"],
          vjust: [:inward, :inward, :inward]
        )

      assert text(frame, context).offset === [{0.0, -0.0}, {0.0, -ascent}, {0.0, -0.5 * ascent}]

      numbers = DataFrame.put(frame, :vjust, [0.25, 0.25, 0.25])
      assert text(numbers, context).offset === List.duplicate({0.0, -0.25 * ascent}, 3)
    end

    test "the words left, center, right, bottom, middle and top justify a label as numbers do",
         context do
      words = [:left, :center, :right, :bottom, :middle, :top]
      rows = length(words)

      hjusts =
        Enum.map(words, fn word ->
          frame = DataFrame.new(x: [0.2], y: [0.2], label: ["a"], hjust: [word])
          [hjust] = text(frame, context).hjust

          hjust
        end)

      assert {rows, hjusts} === {6, [0.0, 0.5, 1.0, 0.0, 0.5, 1.0]}
    end

    test "a label is 11 points, or the layer's size in millimetres times ggplot2's .pt",
         context do
      frame = DataFrame.new(x: [0.5], y: [0.5], label: ["Mazda"])
      sized = DataFrame.put(frame, :size, [5.0])

      points = 5.0 * (72.27 / 25.4)
      assert {text(frame, context).size, text(sized, context).size} === {11.0, points}

      assert %Text{widths: [width], ascent: ascent} = text(sized, context)
      assert {width, ascent} === {Font.width("Mazda", points), Font.ascent(points)}
    end

    test "each label is in its row's colour at its row's alpha, black and opaque by default",
         context do
      frame =
        DataFrame.new(
          x: [0.2, 0.4, 0.6],
          y: [0.2, 0.4, 0.6],
          label: ["a", "b", "c"],
          color: ["#F8766D", "#00BA3880", "#619CFF"],
          alpha: [0.5, nil, nil]
        )

      assert %Text{color: ["#F8766D", "#00BA38", "#619CFF"], opacity: [0.5, @half_alpha, 1.0]} =
               text(frame, context)

      plain = DataFrame.new(x: [0.2], y: [0.2], label: ["a"])
      assert %Text{color: ["#000000"], opacity: [1.0]} = text(plain, context)
    end

    test "the layer's angle and family and the geom's overlap check reach the text", context do
      frame =
        DataFrame.new(
          x: [0.2],
          y: [0.2],
          label: ["a"],
          angle: [30.5],
          family: ["Times New Roman"]
        )

      assert %Text{angle: 30.5, family: "Times New Roman", check_overlap: true} =
               text(frame, context, %Geom.Text{check_overlap: true})

      assert %Text{angle: +0.0, family: "", check_overlap: false} =
               text(DataFrame.new(x: [0.2], y: [0.2], label: ["a"]), context)
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
      assert [%Circles{color: ["#4682B4"], opacity: [0.2]}] =
               Geom.draw_key(%Geom.Point{}, %{alpha: 0.2, color: "#4682B480"}, {17.28, 17.28})

      assert [%Circles{color: ["#4682B4"], opacity: [@half_alpha]}] =
               Geom.draw_key(%Geom.Point{}, %{alpha: nil, color: "#4682B480"}, {17.28, 17.28})

      assert Geom.draw_key(%Geom.Point{}, %{alpha: 0.2, color: :none}, {17.28, 17.28}) === []
    end

    test "a bar's key is its fill short of the key's edges by its border's width" do
      assert [%Rectangles{} = key] = Geom.draw_key(%Geom.Bar{}, %{alpha: 0.55}, {17.28, 17.28})

      [xmin] = key.xmin
      [xmax] = key.xmax
      [ymin] = key.ymin

      assert {Float.round((xmax - xmin) * 17.28, 2), Float.round(ymin * 17.28, 2),
              key.fill_opacity, key.color} === {15.86, 0.71, [0.55], [:none]}
    end

    test "a bar's key is filled and bordered as its layer sets, the key's alpha its fill's alone" do
      key = %{alpha: 0.3, fill: "#0000FF80", color: "#FF000080"}

      assert [%Rectangles{} = drawn] = Geom.draw_key(%Geom.Bar{}, key, {17.28, 17.28})

      assert {drawn.fill, drawn.fill_opacity, drawn.color, drawn.color_opacity} ===
               {["#0000FF"], [0.3], ["#FF0000"], [@half_alpha]}
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

    test "a text's key is the letter a at the middle of the key, in its colour at its alpha" do
      ascent = Font.ascent(11.0)

      assert [%Text{} = key] =
               Geom.draw_key(
                 %Geom.Text{check_overlap: false},
                 %{color: "#F8766D", alpha: 0.5},
                 {17.28, 17.28}
               )

      assert {key.labels, key.x, key.y, key.hjust, key.offset, key.color, key.opacity, key.size} ===
               {["a"], [0.5], [0.5], [0.5], [{0.0, -0.5 * ascent}], ["#F8766D"], [0.5], 11.0}

      assert Geom.draw_key(%Geom.Text{check_overlap: false}, %{color: :none}, {17.28, 17.28}) ===
               []
    end

    # Golden: ggplot2 4.0.3's key for text set `hjust = 0, vjust = 1`, through vdiffr 1.0.9: the
    # letter's start 1.32 points, a tenth of a line of 11-point text 1.2 lines apart, inside the
    # key's left edge, and its top as far below the key's top.
    test "a text's key is placed at the layer's justification, a tenth of a line in from its edges" do
      margin = 0.1 * 11.0 * 1.2

      assert [%Text{} = key] =
               Geom.draw_key(
                 %Geom.Text{check_overlap: false},
                 %{hjust: 0.0, vjust: 1.0},
                 {17.28, 17.28}
               )

      assert {key.x, key.y, key.hjust, key.offset} ===
               {[margin / 17.28], [(17.28 - margin) / 17.28], [0.0], [{0.0, -Font.ascent(11.0)}]}
    end

    # Golden: ggplot2 4.0.3's keys for text set `hjust = 0, vjust = 1` and turned 100, 200 and 300
    # degrees, through vdiffr 1.0.9, which Giggly's drawings of the same plots match in every
    # element: `rotate_just()` puts the anchor at (1 - vjust, hjust) of the key, then at
    # (1 - hjust, 1 - vjust), then at (vjust, 1 - hjust).
    test "a turned text's key is placed at its justification turned with it" do
      places =
        Enum.map([100.0, 200.0, 300.0], fn angle ->
          [%Text{x: [x_place], y: [y_place]}] =
            Geom.draw_key(
              %Geom.Text{check_overlap: false},
              %{hjust: 0.0, vjust: 1.0, angle: angle},
              {100.0, 100.0}
            )

          {Float.round(x_place, 4), Float.round(y_place, 4)}
        end)

      margin = 0.1 * 11.0 * 1.2 / 100

      assert places === [
               {Float.round(margin, 4), Float.round(margin, 4)},
               {Float.round(1 - margin, 4), Float.round(margin, 4)},
               {Float.round(1 - margin, 4), Float.round(1 - margin, 4)}
             ]
    end

    test "a path's key is in the colour its layer sets, and a colour of :none draws none" do
      assert [%Segments{color: ["#FF0000"], opacity: [@half_alpha]}] =
               Geom.draw_key(@path, %{alpha: nil, color: "#FF000080"}, {17.28, 17.28})

      assert Geom.draw_key(@path, %{alpha: 0.4, color: :none}, {17.28, 17.28}) === []
    end
  end
end
