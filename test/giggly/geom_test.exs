defmodule Giggly.GeomTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, DataFrame, Font, Geom, Theme}
  alias Giggly.Scene.{Arrow, Circles, Polygons, Polylines, Rectangles, Segments, Text}

  @path %Geom.Path{line_end: :butt, line_join: :round, mitre_limit: 10.0, arrow: :none}
  @line %Geom.Line{
    orientation: :x,
    line_end: :butt,
    line_join: :round,
    mitre_limit: 10.0,
    arrow: :none
  }
  @segment %Geom.Segment{line_end: :butt, line_join: :round, arrow: :none}
  @hline %Geom.Hline{line_end: :butt}
  @vline %Geom.Vline{line_end: :butt}
  @abline %Geom.Abline{line_end: :butt}
  @linerange %Geom.Linerange{orientation: :none, line_end: :butt}
  @pointrange %Geom.Pointrange{orientation: :none, line_end: :butt}
  @errorbar %Geom.Errorbar{orientation: :none, line_end: :butt}
  @crossbar %Geom.Crossbar{
    orientation: :none,
    middle: %{},
    box: %{},
    line_end: :butt,
    line_join: :mitre
  }
  @rug %Geom.Rug{sides: [:bottom, :left], length: {0.25, :npc}, outside: false, line_end: :butt}

  @ribbon %Geom.Ribbon{
    orientation: :none,
    outline_type: :both,
    line_end: :butt,
    line_join: :round,
    mitre_limit: 10.0
  }

  @area %Geom.Area{
    orientation: :x,
    outline_type: :upper,
    line_end: :butt,
    line_join: :round,
    mitre_limit: 10.0
  }

  @smooth %Geom.Smooth{se: true, line_end: :butt, line_join: :round, mitre_limit: 10.0}

  @continuous %{x: :continuous, y: :continuous}

  # A cartesian panel 2 wide and 4 tall.
  @cartesian %Coord.Cartesian{}
  @params Coord.panel_params(%Coord.Cartesian{}, {{0.0, 2.0}, [], []}, {{0.0, 4.0}, [], []})

  # A 0.5 mm line, ggplot2's default, in points: `0.5 * .pt` line-width units of 1/96 inch, as
  # ggplot2 and svglite work it out.
  @default_width 0.5 * (72.27 / 25.4) / 96 * 72
  @two_millimetres 2.0 * (72.27 / 25.4) / 96 * 72

  # A colour's own alpha of 80, half-opaque: R holds it as the byte 128, so its opacity is 128/255.
  @half_alpha 128 / 255

  # The layers' defaults under `theme_gray()` at its default sizes.
  @element Theme.complete(%{complete: :none, settings: %{}}).geom

  # Dashes in points to two decimals, as svglite writes them.
  defp rounded(:none), do: :none
  defp rounded(dashes), do: Enum.map(dashes, fn length -> Float.round(length, 2) end)

  # The primitives `geom` draws `frame`'s rows with, each default the frame lacks in every row, as
  # the assembly hands a geom its rows.
  defp draw_panel(geom, frame, coord, panel_params) do
    rows = DataFrame.row_count(frame)

    filled =
      geom
      |> Geom.default_aesthetics(@element)
      |> Enum.reject(fn {aesthetic, _value} -> aesthetic in DataFrame.names(frame) end)
      |> Enum.reduce(frame, fn {aesthetic, value}, filled ->
        DataFrame.put(filled, aesthetic, List.duplicate(value, rows))
      end)

    Geom.draw_panel(geom, filled, coord, panel_params, false)
  end

  # `geom` with an arrowhead at grid's defaults, 18 points long, closed and filled with its line's
  # colour, with `changes` made to it.
  defp arrowed(geom, changes) do
    arrow = %{angle: 30.0, length: 18.0, ends: :last, type: :closed, fill: :color}
    %{geom | arrow: Map.merge(arrow, Map.new(changes))}
  end

  # A key's glyph and the room it needs, `key` laid over the geom's defaults, as rendering hands a
  # geom a key.
  defp draw_key(geom, key), do: Geom.draw_key(geom, Map.merge(key_defaults(geom), key), false)
  defp key_size(geom, key), do: Geom.key_size(geom, Map.merge(key_defaults(geom), key), false)

  # A band's rows as a ribbon's setup leaves them, along x, outlined in red, in one panel and group.
  defp band(x_positions, lows, highs) do
    rows = length(x_positions)

    DataFrame.new(
      x: x_positions,
      ymin: lows,
      ymax: highs,
      panel: List.duplicate(1, rows),
      group: List.duplicate(1, rows),
      flipped_aes: List.duplicate(false, rows),
      color: List.duplicate("#FF0000", rows)
    )
  end

  defp key_defaults(geom) do
    geom
    |> Geom.default_aesthetics(@element)
    |> Map.new()
  end

  describe "draw_panel/5 for points" do
    test "a row missing its x or its y is not drawn" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0, nil, 2.0, 3.0], y: [1.0, 3.0, :nan, 2.0])

      assert [%Circles{x: [0.25, 0.75], y: [0.25, 0.5]}] =
               draw_panel(%Geom.Point{}, frame, coord, panel_params)
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

      assert [
               %Circles{
                 x: [0.25, 0.5, 0.75],
                 color_opacity: [0.25, 1.0, 1.0],
                 fill_opacity: [0.25, 1.0, 1.0]
               }
             ] = draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    test "a table without alpha draws every point opaque" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0])

      assert [%Circles{color_opacity: [1.0, 1.0], color: ["#000000", "#000000"]}] =
               draw_panel(%Geom.Point{}, frame, coord, panel_params)
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

      assert [%Circles{color: ["#FF0000", "#FF0000"], color_opacity: [0.2, @half_alpha]}] =
               draw_panel(%Geom.Point{}, frame, coord, panel_params)
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
                 color_opacity: [1.0, @half_alpha, 1.0]
               }
             ] =
               draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    test "a colour of :none, or a missing one, draws no point, as ggplot2 drops one whose colour is NA" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0], color: [:none, nil])

      drawn = draw_panel(%Geom.Point{}, frame, coord, panel_params)

      assert Enum.flat_map(drawn, fn %Circles{x: x_places} -> x_places end) === []
    end

    # Golden: vdiffr 1.0.9's drawing of ggplot2 4.0.3's `geom_point(shape = 21, size = 5, stroke =
    # 5)`, its font size `size * .pt + stroke * .stroke / 2`: a radius of 8.88 points and an
    # outline 7.09 points wide.
    test "a point's radius and outline are worked out from its size and stroke, as grid's are" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(x: [1.0], y: [1.0], shape: [:circle_filled], size: [5.0], stroke: [5.0])

      assert [%Circles{radius: [radius], stroke_width: stroke_width}] =
               draw_panel(%Geom.Point{}, frame, coord, panel_params)

      assert_in_delta radius, 8.88, 0.005
      assert_in_delta stroke_width, 7.09, 0.005
    end

    # R's graphics engine leaves an open shape unfilled, fills 15 to 18 in the point's colour with
    # no outline, outlines and fills 19 and 20 in it, and fills 21 to 25 with the point's fill.
    test "a shape's outline and fill are drawn in the point's colour or fill, as R draws each" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          x: [1.0, 2.0, 3.0, 4.0],
          y: [1.0, 1.0, 1.0, 1.0],
          shape: [:circle_open, :circle_small, :circle, :circle_filled],
          color: List.duplicate("#FF0000", 4),
          fill: List.duplicate("#0000FF80", 4),
          alpha: [nil, nil, nil, 0.2]
        )

      assert [
               %Circles{
                 color: ["#FF0000", :none, "#FF0000", "#FF0000"],
                 color_opacity: [1.0, _none, 1.0, 0.2],
                 fill: [:none, "#FF0000", "#FF0000", "#0000FF"],
                 fill_opacity: [_no_fill, 1.0, 1.0, 0.2]
               }
             ] = draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    # R's graphics engine draws each point whole before the next, so a point drawn later covers an
    # earlier one: shape 7 is a square and then its two diagonals.
    test "points are drawn in row order, each point's elements in the order R draws them" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0], shape: [:square_cross, :square_cross])

      assert [
               %Rectangles{xmin: [0.25]},
               %Segments{starts: [{0.25, 0.25}, {0.25, 0.25}]},
               %Rectangles{xmin: [0.5]},
               %Segments{starts: [{0.5, 0.5}, {0.5, 0.5}]}
             ] = draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    test "a run of elements of one kind and one outline width is one primitive" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          x: [1.0, 2.0, 3.0, 4.0],
          y: [1.0, 1.0, 1.0, 1.0],
          shape: [:circle, :circle_open, :circle, :square_open],
          stroke: [0.5, 0.5, 1.0, 1.0]
        )

      assert [
               %Circles{x: [0.25, 0.5]},
               %Circles{x: [0.75]},
               %Rectangles{xmin: [1.0]}
             ] = draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    # Golden: vdiffr 1.0.9's drawing of ggplot2 4.0.3's shapes 0 to 25 at size 0 and stroke 0:
    # no circle, and every square, polygon and line at no size.
    test "a circle of no radius is not drawn, as R's graphics engine draws none" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0], y: [1.0], shape: [:circle_plus], size: [0.0], stroke: [0.0])

      assert [%Segments{starts: [{0.25, 0.25}, {0.25, 0.25}]}] =
               draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    # Golden: vdiffr 1.0.9's drawing of ggplot2 4.0.3's shapes 7 and 21 at size 5 and stroke NA:
    # shape 7's square with no outline and no diagonals, and a circle of radius 5.33, as at
    # stroke 0, with no outline and its fill.
    test "a stroke of :none, or a missing one, draws no outline and no lines, and adds no size" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          x: [1.0, 2.0],
          y: [1.0, 1.0],
          shape: [:square_cross, :circle_filled],
          size: [5.0, 5.0],
          stroke: [:none, nil],
          fill: ["#FF0000", "#FF0000"]
        )

      assert [
               %Rectangles{color: [:none], stroke_width: +0.0},
               %Circles{radius: [radius], color: [:none], fill: ["#FF0000"]}
             ] = draw_panel(%Geom.Point{}, frame, coord, panel_params)

      assert_in_delta radius, 5.33, 0.005
    end

    # Golden: vdiffr 1.0.9 draws ggplot2 4.0.3's `geom_point(size = 0.1, stroke = 0)` as a circle
    # of radius 0.11.
    test "a circle however small is drawn" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0], y: [1.0], size: [0.1], stroke: [0.0])

      assert [%Circles{radius: [radius]}] =
               draw_panel(%Geom.Point{}, frame, coord, panel_params)

      assert_in_delta radius, 0.11, 0.005
    end

    test "a shape of :none, or a missing one, draws no point" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0, 2.0, 3.0], y: [1.0, 1.0, 1.0], shape: [:none, nil, :square])

      assert [%Polygons{outlines: [[{0.75, 0.25}, {0.75, 0.25}, {0.75, 0.25}, {0.75, 0.25}]]}] =
               draw_panel(%Geom.Point{}, frame, coord, panel_params)
    end

    # ggplot2 4.0.3's `GeomPoint` drops a row whose size is missing, as a size scale's missing
    # value leaves it, and so does its key.
    test "a missing size draws no point" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0, 3.0], y: [1.0, 1.0], size: [nil, 2.0])

      assert [%Circles{x: [0.75]}] = draw_panel(%Geom.Point{}, frame, coord, panel_params)
      assert draw_key(%Geom.Point{}, %{size: nil}) === []
    end
  end

  describe "draw_panel/5 for bars" do
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
               draw_panel(%Geom.Bar{just: 0.5}, frame, coord, panel_params)

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
               draw_panel(%Geom.Bar{just: 0.5}, frame, coord, panel_params)

      without_alpha = DataFrame.new(xmin: [0.0], xmax: [1.0], ymin: [0.0], ymax: [2.0])

      assert [%Rectangles{fill_opacity: [1.0], fill: ["#595959"], color_opacity: [+0.0]}] =
               draw_panel(%Geom.Bar{just: 0.5}, without_alpha, coord, panel_params)
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
               draw_panel(%Geom.Bar{just: 0.5}, frame, coord, panel_params)

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
               draw_panel(%Geom.Bar{just: 0.5}, frame, coord, panel_params)

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
               draw_panel(%Geom.Bar{just: 0.5}, frame, coord, panel_params)
    end
  end

  describe "draw_panel/5 for rectangles" do
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
               draw_panel(%Geom.Rect{}, frame, coord, panel_params)

      assert {rectangles.xmin, rectangles.xmax, rectangles.ymin, rectangles.ymax} ===
               {[0.25, 0.0], [0.0, 0.5], [1.0, 0.25], [0.5, 1.0]}
    end

    # Golden: ggplot2 4.0.3's `annotate("rect", ..., colour = "black", linetype = c("dashed",
    # "dashed", "dashed", "blank"), linewidth = c(0.5, 0.5, 2, 0.5))` through vdiffr 1.0.9: borders
    # 1.07 points wide dashed `5.69,5.69`, then 4.27 wide dashed `22.76,22.76`, then a blank one
    # `stroke: none` with no dashes.
    test "each border is as wide and dashed as its row, each run of one look a primitive" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          xmin: [0.0, 1.0, 2.0, 3.0],
          xmax: [1.0, 2.0, 3.0, 4.0],
          ymin: [0.0, 0.0, 0.0, 0.0],
          ymax: [1.0, 1.0, 1.0, 1.0],
          color: ["#000000", "#000000", "#000000", "#000000"],
          linewidth: [0.5, 0.5, 2.0, 0.5],
          linetype: [{4, 4}, {4, 4}, {4, 4}, nil]
        )

      assert [thin, thick, blank] = draw_panel(%Geom.Rect{}, frame, coord, panel_params)

      assert {thin.xmin, thick.xmin, blank.xmin} === {[0.0, 0.25], [0.5], [0.75]}

      assert Enum.map([thin, thick, blank], fn rectangles ->
               {Float.round(rectangles.stroke_width, 2), rounded(rectangles.dashes),
                rectangles.color}
             end) === [
               {1.07, [5.69, 5.69], ["#000000", "#000000"]},
               {4.27, [22.76, 22.76], ["#000000"]},
               {1.07, :none, [:none]}
             ]
    end

    # Golden: ggplot2 4.0.3's `geom_col(aes(linewidth = w), colour = "black")` through vdiffr
    # 1.0.9, `w` missing for one bar: R's graphics engine draws a border of no width transparent,
    # `stroke: none`, which svglite writes `nan` wide and Giggly 0.
    test "a missing border width draws no border, a run of its own 0 wide" do
      coord = %Coord.Cartesian{}
      panel_params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      frame =
        DataFrame.new(
          xmin: [0.0, 1.0, 2.0],
          xmax: [1.0, 2.0, 3.0],
          ymin: [0.0, 0.0, 0.0],
          ymax: [1.0, 1.0, 1.0],
          color: ["#000000", "#000000", "#000000"],
          linewidth: [0.5, nil, 0.5]
        )

      assert [first, missing, last] = draw_panel(%Geom.Rect{}, frame, coord, panel_params)

      assert {first.color, missing.color, missing.stroke_width, last.color} ===
               {["#000000"], [:none], 0.0, ["#000000"]}
    end
  end

  describe "draw_panel/5 for hexagons" do
    @hex %Geom.Hex{line_end: :butt, line_join: :mitre, mitre_limit: 10.0}

    # Hexagons as hexagonal binning leaves them: `centres` in one panel, each `{width, height}`
    # in `sizes`, a group each in `groups`, with `columns` besides.
    defp hexagons(centres, sizes, groups, columns \\ []) do
      {x_positions, y_positions} = Enum.unzip(centres)
      {widths, heights} = Enum.unzip(sizes)

      DataFrame.new(
        [
          x: x_positions,
          y: y_positions,
          width: widths,
          height: heights,
          panel: List.duplicate(1, length(centres)),
          group: groups
        ] ++ columns
      )
    end

    # A hexagon `height` high reaches its height over √3 above its centre at its sides and twice
    # that at its top: one 1 wide and √3 high, at 1, 2 on the panel 2 wide and 4 tall, has its
    # corners half a unit either side and a half and a whole unit up and down.
    test "a hexagon's six corners stand round its centre on a point, its sides upright" do
      frame = hexagons([{1.0, 2.0}], [{1.0, :math.sqrt(3)}], [1])

      assert [%Polygons{outlines: [outline]} = polygons] =
               draw_panel(@hex, frame, @cartesian, @params)

      expected = [
        {0.75, 0.625},
        {0.75, 0.375},
        {0.5, 0.25},
        {0.25, 0.375},
        {0.25, 0.625},
        {0.5, 0.75}
      ]

      Enum.zip_with(outline, expected, fn {x, y}, {wanted_x, wanted_y} ->
        assert_in_delta x, wanted_x, 1.0e-15
        assert_in_delta y, wanted_y, 1.0e-15
      end)

      assert {polygons.offsets, polygons.line_end, polygons.line_join, polygons.mitre_limit} ==
               {:none, :butt, :mitre, 10.0}
    end

    # ggplot2's `GeomHex$draw_group()` reads `width[1]` and `height[1]`, so every hexagon of a
    # group is its first row's size, and another group's its own first's.
    test "a group's hexagons are all its first row's size" do
      frame =
        hexagons(
          [{0.5, 1.0}, {1.5, 1.0}, {1.0, 3.0}],
          [{1.0, :math.sqrt(3)}, {0.2, 0.2}, {0.4, :math.sqrt(3)}],
          [1, 1, 2]
        )

      assert [%Polygons{outlines: outlines}] = draw_panel(@hex, frame, @cartesian, @params)

      widths =
        Enum.map(outlines, fn outline ->
          {x_places, _y_places} = Enum.unzip(outline)
          Float.round(Enum.max(x_places) - Enum.min(x_places), 12)
        end)

      assert widths == [0.5, 0.5, 0.2]
    end

    test "a hexagon's alpha reaches its fill alone, its border keeping its colour's own" do
      frame =
        hexagons([{0.5, 1.0}, {1.5, 1.0}], [{1.0, 1.0}, {1.0, 1.0}], [1, 1],
          fill: ["#FF0000", "#0000FF80"],
          alpha: [0.25, nil],
          color: ["#00FF0080", "#000000"]
        )

      assert [%Polygons{} = polygons] = draw_panel(@hex, frame, @cartesian, @params)

      assert {polygons.fill, polygons.fill_opacity, polygons.color, polygons.color_opacity} ==
               {["#FF0000", "#0000FF"], [0.25, @half_alpha], ["#00FF00", "#000000"],
                [@half_alpha, 1.0]}
    end

    # ggplot2's default hexagon is unbordered, filled with its ink mixed halfway to its paper.
    test "a hexagon given no look is filled grey and unbordered, its borders' width the theme's" do
      frame = hexagons([{1.0, 2.0}], [{1.0, 1.0}], [1])

      assert [%Polygons{} = polygons] = draw_panel(@hex, frame, @cartesian, @params)

      assert {polygons.fill, polygons.color, polygons.stroke_width, polygons.dashes} ==
               {["#808080"], [:none], @default_width, :none}
    end

    test "each run of hexagons bordered alike is one primitive, a blank border none" do
      frame =
        hexagons(
          [{0.25, 1.0}, {0.75, 1.0}, {1.25, 1.0}, {1.75, 1.0}],
          List.duplicate({0.5, 0.5}, 4),
          [1, 1, 1, 1],
          color: List.duplicate("#000000", 4),
          linewidth: [0.5, 0.5, 2.0, 0.5],
          linetype: [{4, 4}, {4, 4}, {4, 4}, nil]
        )

      assert [thin, thick, blank] = draw_panel(@hex, frame, @cartesian, @params)

      assert Enum.map([thin, thick, blank], fn polygons ->
               {length(polygons.outlines), Float.round(polygons.stroke_width, 2),
                rounded(polygons.dashes), polygons.color}
             end) === [
               {2, 1.07, [5.69, 5.69], ["#000000", "#000000"]},
               {1, 4.27, [22.76, 22.76], ["#000000"]},
               {1, 1.07, :none, [:none]}
             ]
    end

    # As a rectangle's: R's graphics engine draws a border of no width transparent, which
    # svglite writes `nan` wide and Giggly 0.
    test "a missing border width draws no border, a run of its own 0 wide" do
      frame =
        hexagons([{0.5, 1.0}, {1.5, 1.0}], [{1.0, 1.0}, {1.0, 1.0}], [1, 1],
          color: ["#000000", "#000000"],
          linewidth: [nil, 0.5]
        )

      assert [missing, drawn] = draw_panel(@hex, frame, @cartesian, @params)

      assert {missing.color, missing.stroke_width, drawn.color} ===
               {[:none], 0.0, ["#000000"]}
    end

    test "a hexagon missing its centre is not drawn" do
      frame =
        hexagons([{nil, 1.0}, {1.0, :nan}, {1.0, 2.0}], List.duplicate({1.0, 1.0}, 3), [1, 1, 1])

      assert [%Polygons{outlines: [_outline]}] = draw_panel(@hex, frame, @cartesian, @params)
    end

    # ggplot2's `GeomHex` never munches: under coordinates that curve, its corners are placed and
    # its sides drawn straight between them.
    test "in radial coordinates a hexagon is its six placed corners" do
      coord = %Coord.Radial{}
      params = Coord.panel_params(coord, {{0.0, 2.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = hexagons([{1.0, 2.0}], [{1.0, 1.0}], [1])

      assert [%Polygons{outlines: [[_first, _second, _third, _fourth, _fifth, _sixth]]}] =
               draw_panel(@hex, frame, coord, params)
    end

    test "a hexagon's key is a polygon's with the layer's ends and corners" do
      key = %{fill: "#FF0000", linewidth: 2.0}

      assert [%Rectangles{line_end: :butt, line_join: :mitre, fill: ["#FF0000"]}] =
               draw_key(@hex, key)

      assert key_size(@hex, key) == {4 * 72 / 25.4, 4 * 72 / 25.4}
      assert key_size(@hex, %{linewidth: nil}) == {0.0, 0.0}
    end
  end

  describe "draw_panel/5 for box plots" do
    @box %Geom.Boxplot{
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
    }

    # A set-up box, as `layer_data()` shows `geom_boxplot()`'s of 1, 2, 3, 4, 5 and 20 at x 1, with
    # `columns` in place of its own or beside them, and without those `dropped`.
    defp box_rows(columns, dropped \\ []) do
      [
        ymin: [1.0],
        lower: [2.25],
        middle: [3.5],
        upper: [4.75],
        ymax: [5.0],
        outliers: [[20.0]],
        notchupper: [5.1125807473322595],
        notchlower: [1.887419252667741],
        x: [1.0],
        flipped_aes: [false],
        panel: [1],
        group: [1],
        xmin: [0.625],
        xmax: [1.375]
      ]
      |> Keyword.merge(columns)
      |> Keyword.drop(dropped)
      |> DataFrame.new()
    end

    defp box_params do
      coord = %Coord.Cartesian{}
      {coord, Coord.panel_params(coord, {{0.0, 2.0}, [], []}, {{0.0, 20.0}, [], []})}
    end

    test "a box's fill and outliers take its alpha, and its lines never do" do
      {coord, params} = box_params()
      frame = box_rows(alpha: [0.5], fill: ["#FF0000"])

      assert [
               %Circles{color_opacity: [0.5], fill_opacity: [0.5]},
               %Segments{opacity: [1.0, 1.0]},
               %Polygons{color: ["#333333"], color_opacity: [1.0], fill_opacity: [0.5]},
               %Segments{opacity: [1.0]}
             ] = draw_panel(@box, frame, coord, params)
    end

    test "a part whose colour is :none, or a blank border, is not drawn, the box still filled" do
      {coord, params} = box_params()
      geom = %{@box | whisker: %{color: :none}, box: %{linetype: :none}}

      assert [%Circles{}, %Polygons{color: [:none], fill: ["#FFFFFF"]}, %Segments{}] =
               draw_panel(geom, box_rows([]), coord, params)
    end

    test "the median is twice the box's width unless its look gives one" do
      {coord, params} = box_params()
      frame = box_rows(linewidth: [1.0])
      [_outliers, _whiskers, _box, median] = draw_panel(@box, frame, coord, params)
      given = %{@box | median: %{linewidth: 0.5}}
      [_outliers, _whiskers, _box, given_median] = draw_panel(given, frame, coord, params)

      assert {median.stroke_width, given_median.stroke_width} ===
               {@two_millimetres, @default_width}
    end

    test "outliers are drawn as points in the outliers' look, else in the box's" do
      {coord, params} = box_params()
      frame = box_rows(fill: ["#FF0000"], shape: [:circle_filled], size: [3.0], alpha: [0.5])

      look = %{
        color: "#0000FF",
        fill: "#00FF00",
        shape: :triangle_filled,
        size: 2.0,
        stroke: 1.0,
        alpha: 0.25
      }

      [boxs | _rest] = draw_panel(@box, frame, coord, params)
      looked = draw_panel(%{@box | outlier: look}, frame, coord, params)

      points = fn values ->
        [x: [1.0], y: [20.0]]
        |> Enum.concat(Enum.map(values, fn {aesthetic, value} -> {aesthetic, [value]} end))
        |> DataFrame.new()
        |> then(fn points -> draw_panel(%Geom.Point{}, points, coord, params) end)
      end

      assert [boxs] ===
               points.(
                 color: "#333333",
                 fill: "#FF0000",
                 shape: :circle_filled,
                 size: 3.0,
                 stroke: 0.5,
                 alpha: 0.5
               )

      assert Enum.take(looked, length(looked) - 3) === points.(look)
    end

    # R's `(xmin - x) * staplewidth + x` and `(xmax - x) * staplewidth + x`, at a staplewidth
    # whose staples a swapped side would move.
    test "staples cross the whiskers' ends, a share of the box's width, the upper first" do
      {coord, params} = box_params()
      geom = %{@box | staplewidth: 0.25}

      assert [_outliers, %Segments{starts: starts, ends: ends} | _rest] =
               draw_panel(geom, box_rows([]), coord, params)

      assert {starts, ends} ===
               {[{0.453125, 0.25}, {0.453125, 0.05}], [{0.546875, 0.25}, {0.546875, 0.05}]}
    end

    test "the median takes its own colour and line type, else the box's" do
      {coord, params} = box_params()
      geom = %{@box | median: %{color: "#FF0000", linetype: {4, 4}}}
      [_outliers, _whiskers, _box, median] = draw_panel(geom, box_rows([]), coord, params)

      assert {median.color, rounded(median.dashes)} === {["#FF0000"], [11.38, 11.38]}
    end

    # As grid splits a polygon at a missing point: `geom_boxplot() + xlim(0.7, 3.5)`, then with
    # `notch = TRUE` and `xlim(0.5, 3.2)`, draw a box whose side the limit cuts as the pieces
    # left, and leave out the median, which has lost an end; a box cut both sides leaves none.
    test "a box whose side a limit cuts is drawn in the pieces left, its median left out" do
      {coord, params} = box_params()
      cut_left = box_rows(xmin: [nil])

      assert [%Circles{}, %Segments{}, %Polygons{outlines: [left]}] =
               draw_panel(@box, cut_left, coord, params)

      assert left === [{0.6875, 0.1125}, {0.6875, 0.2375}]

      cut_right = box_rows(xmax: [nil])

      assert [%Circles{}, %Segments{}, %Polygons{outlines: pieces}] =
               draw_panel(%{@box | notch: true}, cut_right, coord, params)

      assert pieces === [
               [{0.3125, 0.2375}, {0.3125, 0.25562903736661297}],
               [{0.3125, 0.09437096263338704}, {0.3125, 0.1125}]
             ]

      cut_both = box_rows(xmin: [nil], xmax: [nil])

      assert [%Circles{}, %Segments{}] = draw_panel(@box, cut_both, coord, params)
    end

    test "a box keeping no outliers draws none" do
      {coord, params} = box_params()
      frame = box_rows([], [:outliers])

      assert [%Segments{}, %Polygons{}, %Segments{}] =
               draw_panel(@box, frame, coord, params)
    end

    test "boxes are drawn in the order of their groups, each whole before the next" do
      {coord, params} = box_params()

      frame =
        DataFrame.new(
          ymin: [1.0, 1.0],
          lower: [2.0, 2.0],
          middle: [3.0, 3.0],
          upper: [4.0, 4.0],
          ymax: [5.0, 5.0],
          outliers: [[], []],
          notchupper: [4.0, 4.0],
          notchlower: [2.0, 2.0],
          x: [1.5, 0.5],
          flipped_aes: [false, false],
          panel: [1, 1],
          group: [2, 1],
          xmin: [1.25, 0.25],
          xmax: [1.75, 0.75]
        )

      assert [
               %Segments{starts: [{0.25, _first}, _second]},
               %Polygons{},
               %Segments{},
               %Segments{starts: [{0.75, _third}, _fourth]},
               %Polygons{},
               %Segments{}
             ] = draw_panel(@box, frame, coord, params)
    end
  end

  # Golden: ggplot2 4.0.3's keys through vdiffr 1.0.9 (R 4.6.1), a 17.28-point key: a point at its
  # middle, and a bar's fill 15.86 points square, its border's 0.5 mm short of the key.
  describe "setup_data/3, draw_panel/5 and draw_key/3 for violins" do
    @violin %Geom.Violin{line_end: :butt, line_join: :mitre}

    # A violin's rows as its densities and setup leave them, at x 1 in a room from 0.5 to 1.5, in
    # one panel, group 1 unless given, with `columns` in place of its own or beside them.
    defp violin_rows(columns) do
      rows = length(Keyword.fetch!(columns, :y))

      [
        x: List.duplicate(1.0, rows),
        xmin: List.duplicate(0.5, rows),
        xmax: List.duplicate(1.5, rows),
        panel: List.duplicate(1, rows),
        group: List.duplicate(1, rows),
        flipped_aes: List.duplicate(false, rows)
      ]
      |> Keyword.merge(columns)
      |> DataFrame.new()
    end

    # Golden: `geom_violin(position = "identity")` of groups at x 1 and 3 in one facet and 10 and
    # 10.5 in another, ggplot2 4.0.3's `layer_data()`: each 0.45 wide, 0.9 of the closest spacing
    # counting from zero, 0.5, the smaller of the panels'.
    test "a violin is 0.9 of the closest spacing in any panel wide, counting from zero" do
      frame =
        DataFrame.new(
          x: [1.0, 3.0, 10.0, 10.5],
          y: [1.0, 1.0, 1.0, 1.0],
          panel: [1, 1, 2, 2],
          group: [1, 2, 3, 4],
          flipped_aes: [false, false, false, false]
        )

      set_up = Geom.setup_data(@violin, frame, @continuous)

      assert DataFrame.pull(set_up, :width) == [0.45, 0.45, 0.45, 0.45]
      assert DataFrame.pull(set_up, :xmin) == [0.775, 2.775, 9.775, 10.275]
      assert DataFrame.pull(set_up, :xmax) == [1.225, 3.225, 10.225, 10.725]

      # Golden: the same of groups at x 1 and 3 in one panel: 0.9 wide, the spacing from 0 to 1.
      apart =
        DataFrame.new(
          x: [1.0, 3.0],
          y: [1.0, 1.0],
          panel: [1, 1],
          group: [1, 2],
          flipped_aes: [false, false]
        )

      set_apart = Geom.setup_data(@violin, apart, @continuous)
      assert DataFrame.pull(set_apart, :xmin) == [0.55, 2.55]
    end

    # Golden: `geom_violin()` of x a and b at y 1, 2, 4, 1, 3 and 4 mapping a width of 0.5 for a
    # and 0.7 for b, and a short group kept beside `width = 0.5`, whose width R leaves missing.
    test "a violin keeps the width its rows hold, a missing one leaving its sides missing" do
      frame =
        DataFrame.new(
          x: [1.0, 2.0, 3.0],
          y: [1.0, 1.0, 1.0],
          width: [0.5, 0.7, nil],
          panel: [1, 1, 1],
          group: [1, 2, 3],
          flipped_aes: [false, false, false]
        )

      set_up = Geom.setup_data(@violin, frame, @continuous)

      assert DataFrame.pull(set_up, :xmin) == [0.75, 1.65, nil]
      assert DataFrame.pull(set_up, :xmax) == [1.25, 2.35, nil]
    end

    test "a horizontal violin is set up along y, as its densities say" do
      frame =
        DataFrame.new(
          x: [1.0, 2.0],
          y: [1.0, 2.0],
          panel: [1, 1],
          group: [1, 2],
          flipped_aes: [true, true]
        )

      set_up = Geom.setup_data(@violin, frame, @continuous)

      assert DataFrame.pull(set_up, :ymin) == [0.55, 1.55]
      assert DataFrame.pull(set_up, :ymax) == [1.45, 2.45]
      refute :xmin in DataFrame.names(set_up)
    end

    test "an outline runs up its left side and down its right, ties in their order, and closes" do
      frame = violin_rows(y: [2.0, 1.0, 1.0], violinwidth: [1.0, 0.2, 0.4])

      [%Polygons{outlines: [outline]}] = draw_panel(@violin, frame, @cartesian, @params)

      left = [{0.45, 0.25}, {0.4, 0.25}, {0.25, 0.5}]
      right = [{0.75, 0.5}, {0.55, 0.25}, {0.6, 0.25}]
      expected = Enum.concat([left, right, [{0.45, 0.25}]])

      assert Enum.map(outline, fn {x, y} -> {Float.round(x, 12), Float.round(y, 12)} end) ==
               expected
    end

    test "violins are drawn in the order of their groups, a row missing x or y left out" do
      frame =
        violin_rows(
          y: [1.0, 2.0, nil, 1.0, 2.0, :nan],
          violinwidth: [1.0, 1.0, 1.0, 0.5, 0.5, 0.5],
          group: [2, 2, 2, 1, 1, 1],
          fill: ["#FF0000", "#FF0000", "#FF0000", "#0000FF", "#0000FF", "#0000FF"]
        )

      assert [
               %Polygons{fill: ["#0000FF"], outlines: [first]},
               %Polygons{fill: ["#FF0000"], outlines: [second]}
             ] = draw_panel(@violin, frame, @cartesian, @params)

      assert {Enum.count(first), Enum.count(second)} == {5, 5}
    end

    test "violins are drawn in the order of their groups however many a panel holds" do
      groups = Enum.to_list(40..1//-1)

      fills =
        Enum.map(groups, fn group ->
          "#0000" <> String.pad_leading(Integer.to_string(group), 2, "0")
        end)

      frame =
        violin_rows(
          y: List.duplicate(1.0, 40),
          violinwidth: List.duplicate(1.0, 40),
          group: groups,
          fill: fills
        )

      drawn =
        @violin
        |> draw_panel(frame, @cartesian, @params)
        |> Enum.map(fn %Polygons{fill: [fill]} -> fill end)

      assert drawn == Enum.reverse(fills)
    end

    test "a missing width splits the outline, a run of two points or more drawn" do
      split = violin_rows(y: [1.0, 2.0, 3.0], violinwidth: [1.0, nil, 1.0])
      [%Polygons{outlines: pieces}] = draw_panel(@violin, split, @cartesian, @params)
      lone = violin_rows(y: [1.0], violinwidth: [nil])

      assert Enum.map(pieces, &length/1) == [2, 2]
      assert draw_panel(@violin, lone, @cartesian, @params) == []
    end

    test "a violin's fill takes its alpha and its border never does" do
      frame = violin_rows(y: [1.0, 2.0], violinwidth: [1.0, 1.0], alpha: [0.5, 0.5])

      assert [%Polygons{color: ["#333333"], color_opacity: [1.0], fill_opacity: [0.5]}] =
               draw_panel(@violin, frame, @cartesian, @params)
    end

    test "a border of no colour, a blank one or one of no width is left off, the fill drawn" do
      for look <- [[color: [:none, :none]], [linetype: [:none, :none]], [linewidth: [nil, nil]]] do
        frame = violin_rows(Keyword.merge([y: [1.0, 2.0], violinwidth: [1.0, 1.0]], look))

        assert [%Polygons{color: [:none], fill: ["#FFFFFF"]}] =
                 draw_panel(@violin, frame, @cartesian, @params)
      end

      unwidened = violin_rows(y: [1.0, 2.0], violinwidth: [1.0, 1.0], linewidth: [nil, nil])
      [%Polygons{stroke_width: width}] = draw_panel(@violin, unwidened, @cartesian, @params)
      assert width === 0.0
    end

    # vdiffr: `geom_violin(lineend = "square", linejoin = "mitre", linemitre = 3)` draws the same
    # SVG as `geom_violin()`, every border butt, round and limited at 10.
    test "a violin's border is cut square and rounded whatever ends and corners its layer gives" do
      frame = violin_rows(y: [1.0, 2.0], violinwidth: [1.0, 1.0])

      [drawn] =
        draw_panel(%{@violin | line_end: :square, line_join: :bevel}, frame, @cartesian, @params)

      assert {drawn.line_end, drawn.line_join, drawn.mitre_limit} == {:butt, :round, 10.0}
    end

    # vdiffr: `geom_violin(aes(fill = factor(cyl)), lineend = "round", linejoin = "bevel")` keys
    # each fill bevelled, where the default keys them mitred.
    test "a violin's key is a rectangle's, its ends and corners the layer's" do
      [mitred] = draw_key(@violin, %{fill: "#FF0000"})
      [bevelled] = draw_key(%{@violin | line_join: :bevel, line_end: :round}, %{})

      assert {mitred.line_join, mitred.line_end, mitred.fill} == {:mitre, :butt, ["#FF0000"]}
      assert {bevelled.line_join, bevelled.line_end} == {:bevel, :round}
    end

    test "a violin is ggplot2's default under the theme, its weight 1" do
      assert Geom.default_aesthetics(@violin, @element) == [
               weight: 1.0,
               color: "#333333",
               fill: "#FFFFFF",
               linewidth: @element.borderwidth,
               linetype: @element.bordertype,
               alpha: nil
             ]

      assert {@element.borderwidth, @element.bordertype} == {0.5, {}}
    end
  end

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

    # A summary's line, whose stat writes its orientation.
    test "a line given no orientation is put in order of y where its rows run along y" do
      frame =
        DataFrame.new(
          x: [1.0, 2.0, 3.0],
          y: [3.0, 1.0, 2.0],
          panel: [1, 1, 1],
          group: [1, 1, 1],
          flipped_aes: [true, true, true]
        )

      along_y =
        Geom.setup_data(%{@line | orientation: :none}, frame, %{x: :continuous, y: :continuous})

      along_x = DataFrame.put(frame, :flipped_aes, [false, false, false])

      assert DataFrame.pull(along_y, :x) === [2.0, 3.0, 1.0]

      assert %{@line | orientation: :none}
             |> Geom.setup_data(along_x, %{x: :continuous, y: :continuous})
             |> DataFrame.pull(:x) === [1.0, 2.0, 3.0]
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_line()` over a discrete y,
    # `flipped_aes` FALSE in every row, so a position reads it before the discrete axis.
    test "a line writes its orientation in every row's flipped_aes, true along y" do
      frame =
        DataFrame.new(x: [2.0, 1.0], y: [1, 2], panel: [1, 1], group: [1, 1])

      levels = %{x: :continuous, y: :discrete}

      along_x = Geom.setup_data(@line, frame, levels)
      along_y = Geom.setup_data(%{@line | orientation: :y}, frame, levels)

      assert {DataFrame.pull(along_x, :flipped_aes), DataFrame.pull(along_y, :flipped_aes)} ==
               {[false, false], [true, true]}
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

  describe "setup_data/3 for smooths" do
    test "rows are put in order of panel, group and x, the stat's orientation in every row" do
      frame =
        DataFrame.new(
          x: [2.0, 3.0, 1.0, 2.0, 0.0],
          y: [1.0, 2.0, 3.0, 4.0, 5.0],
          flipped_aes: [false, nil, false, false, false],
          panel: [1, 1, 1, 1, 2],
          group: [1, 2, 1, 1, 1]
        )

      set_up = Geom.setup_data(@smooth, frame, @continuous)

      assert DataFrame.pull(set_up, :y) === [3.0, 1.0, 4.0, 2.0, 5.0]
      assert DataFrame.pull(set_up, :flipped_aes) == List.duplicate(false, 5)
    end

    test "a smooth the stat ran along y puts its rows in order of y" do
      frame =
        DataFrame.new(
          x: [1.0, 2.0, 3.0],
          y: [3.0, 1.0, 2.0],
          flipped_aes: [true, true, true],
          panel: [1, 1, 1],
          group: [1, 1, 1]
        )

      set_up = Geom.setup_data(@smooth, frame, @continuous)

      assert DataFrame.pull(set_up, :x) === [2.0, 3.0, 1.0]
      assert DataFrame.pull(set_up, :flipped_aes) == [true, true, true]
    end
  end

  # Each golden here is ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the plot named.
  describe "setup_data/3 for ribbons and areas" do
    # Golden: `ggplot(ribbon, aes(x = y, ymax = hi, xmin = lo)) + geom_ribbon()`.
    test "a ribbon given a ymax runs along x, in order, its y its ymin or else its ymax" do
      frame =
        DataFrame.new(
          x: [3, 1, 2],
          ymax: [3.0, 2.0, 4.0],
          panel: [1, 1, 1],
          group: [-1, -1, -1]
        )

      set_up = Geom.setup_data(@ribbon, frame, @continuous)

      assert {DataFrame.pull(set_up, :x), DataFrame.pull(set_up, :y)} ===
               {[1, 2, 3], [2.0, 4.0, 3.0]}

      assert DataFrame.pull(set_up, :flipped_aes) === [false, false, false]
    end

    # Golden: `ggplot(ribbon, aes(y = y, xmin = lo, xmax = hi)) + geom_ribbon()`.
    test "a ribbon given no ymin or ymax runs along y, its x its xmin" do
      frame =
        DataFrame.new(
          y: [3, 1, 2],
          xmin: [1.0, 0.5, 2.0],
          xmax: [3.0, 2.0, 4.0],
          panel: [1, 1, 1],
          group: [-1, -1, -1]
        )

      set_up = Geom.setup_data(@ribbon, frame, @continuous)

      assert {DataFrame.pull(set_up, :y), DataFrame.pull(set_up, :x)} ===
               {[1, 2, 3], [0.5, 2.0, 1.0]}

      assert DataFrame.pull(set_up, :flipped_aes) === [true, true, true]
      assert [:y, :xmin, :xmax, :panel, :group | _rest] = DataFrame.names(set_up)
    end

    test "a ribbon runs as its layer says, whatever its range" do
      frame =
        DataFrame.new(
          x: [1, 2],
          y: [2, 1],
          xmin: [1.0, 0.5],
          xmax: [2.0, 1.5],
          ymin: [3.0, 2.0],
          panel: [1, 1],
          group: [-1, -1]
        )

      along_y = Geom.setup_data(%{@ribbon | orientation: :y}, frame, @continuous)
      along_x = Geom.setup_data(%{@ribbon | orientation: :x}, frame, @continuous)

      assert {DataFrame.pull(along_y, :flipped_aes), DataFrame.pull(along_x, :flipped_aes)} ===
               {[true, true], [false, false]}

      assert {DataFrame.pull(along_y, :x), DataFrame.pull(along_x, :y)} ===
               {[0.5, 1.0], [3.0, 2.0]}
    end

    test "an area runs from 0 to its y, in order of panel, group and x" do
      frame =
        DataFrame.new(x: [2, 1, 1], y: [3.0, 4.0, 5.0], panel: [1, 1, 2], group: [1, 1, 1])

      set_up = Geom.setup_data(@area, frame, @continuous)

      assert Enum.map([:x, :ymin, :ymax], fn name -> DataFrame.pull(set_up, name) end) ===
               [[1, 2, 1], [0.0, 0.0, 0.0], [4.0, 3.0, 5.0]]
    end

    test "a ribbon given a ymin alone runs along x" do
      frame =
        DataFrame.new(
          x: [2, 1],
          ymin: [1.0, 0.5],
          xmax: [3.0, 2.0],
          panel: [1, 1],
          group: [-1, -1]
        )

      set_up = Geom.setup_data(@ribbon, frame, @continuous)

      assert {DataFrame.pull(set_up, :flipped_aes), DataFrame.pull(set_up, :y)} ===
               {[false, false], [0.5, 1.0]}
    end

    # ggplot2's `order(data$PANEL, data$group, data$x)`: a lower panel first, whatever its group.
    test "a band's rows are put in order of panel before group" do
      frame =
        DataFrame.new(x: [1, 1], y: [3.0, 4.0], panel: [2, 1], group: [1, 2])

      set_up = Geom.setup_data(@area, frame, @continuous)

      assert DataFrame.pull(set_up, :ymax) === [4.0, 3.0]
    end

    test "an area runs along y where its stat says so, over the layer's orientation" do
      frame =
        DataFrame.new(
          x: [3.0, 4.0],
          y: [2, 1],
          panel: [1, 1],
          group: [1, 1],
          flipped_aes: [true, true]
        )

      set_up = Geom.setup_data(@area, frame, @continuous)

      assert Enum.map([:y, :xmin, :xmax], fn name -> DataFrame.pull(set_up, name) end) ===
               [[1, 2], [0.0, 0.0], [4.0, 3.0]]
    end
  end

  describe "draw_panel/5 for ribbons and areas" do
    # Golden: ggplot2 4.0.3's `geom_ribbon(colour = "red")` through vdiffr 1.0.9: a polygon of no
    # border out along `ymax` and back along `ymin`, then the upper and the lower edge, each a line.
    test "a piece is a polygon out along its upper edge and back along its lower, then its lines" do
      assert [%Polygons{} = polygon, %Polylines{} = lines] =
               draw_panel(
                 @ribbon,
                 band([0.0, 1.0, 2.0], [0.0, 1.0, 0.0], [2.0, 3.0, 2.0]),
                 @cartesian,
                 @params
               )

      assert polygon.outlines === [
               [{0.0, 0.5}, {0.5, 0.75}, {1.0, 0.5}, {1.0, 0.0}, {0.5, 0.25}, {0.0, 0.0}]
             ]

      assert {polygon.stroke_width, polygon.color, polygon.fill} === {0.0, [:none], ["#333333"]}

      assert lines.lines === [
               [{0.0, 0.5}, {0.5, 0.75}, {1.0, 0.5}],
               [{1.0, 0.0}, {0.5, 0.25}, {0.0, 0.0}]
             ]

      assert {lines.color, lines.stroke_width} === {["#FF0000", "#FF0000"], @default_width}
    end

    # Golden: ggplot2 4.0.3's `geom_ribbon(colour = "red")` of `lo = c(1, NA, 1, 1.2, NA)` through
    # vdiffr 1.0.9: a polygon of two points for the first row alone, with no line, then the third
    # and fourth rows' polygon and lines.
    test "a row missing a position splits its group, a piece of one row drawing no lines" do
      frame =
        band([0.0, 0.5, 1.0, 1.5, 2.0], [1.0, nil, 1.0, 1.2, nil], [2.0, 2.5, 2.2, 2.4, 2.6])

      assert [%Polygons{outlines: [lone]}, %Polygons{outlines: [piece]}, %Polylines{lines: lines}] =
               draw_panel(@ribbon, frame, @cartesian, @params)

      assert {length(lone), length(piece), length(lines)} === {2, 4, 2}
    end

    test "the outline draws the upper edge alone, the lower alone, or the polygon's border" do
      frame = band([0.0, 2.0], [0.0, 0.0], [4.0, 4.0])

      assert [_polygon, %Polylines{lines: [[{+0.0, 1.0}, {1.0, 1.0}]]}] =
               draw_panel(%{@ribbon | outline_type: :upper}, frame, @cartesian, @params)

      assert [_polygon, %Polylines{lines: [[{1.0, +0.0}, {+0.0, +0.0}]]}] =
               draw_panel(%{@ribbon | outline_type: :lower}, frame, @cartesian, @params)

      assert [%Polygons{color: ["#FF0000"], stroke_width: @default_width}] =
               draw_panel(%{@ribbon | outline_type: :full}, frame, @cartesian, @params)
    end

    test "the fill is at the row's alpha and the lines at their colour's own" do
      frame =
        [0.0, 2.0]
        |> band([0.0, 0.0], [4.0, 4.0])
        |> DataFrame.put(:alpha, [0.5, 0.5])
        |> DataFrame.put(:color, ["#FF000080", "#FF000080"])

      assert [%Polygons{fill_opacity: [0.5]}, %Polylines{opacity: [@half_alpha, @half_alpha]}] =
               draw_panel(@ribbon, frame, @cartesian, @params)
    end

    # Golden: ggplot2 4.0.3's default `geom_area()` through vdiffr 1.0.9: its upper edge a line of
    # `stroke: none`.
    test "an outline of no colour is written with none, and a blank or missing one not drawn" do
      frame = band([0.0, 2.0], [0.0, 0.0], [4.0, 4.0])
      uncoloured = DataFrame.put(frame, :color, [nil, nil])

      assert [_polygon, %Polylines{color: [:none, :none], opacity: [+0.0, +0.0]}] =
               draw_panel(@ribbon, uncoloured, @cartesian, @params)

      assert [_polygon] =
               draw_panel(
                 @ribbon,
                 DataFrame.put(frame, :linetype, [:none, :none]),
                 @cartesian,
                 @params
               )

      assert [_polygon] =
               draw_panel(
                 @ribbon,
                 DataFrame.put(frame, :linewidth, [nil, nil]),
                 @cartesian,
                 @params
               )
    end

    test "a whole border of the blank line type or a missing width is not drawn" do
      frame = band([0.0, 2.0], [0.0, 0.0], [4.0, 4.0])
      full = %{@ribbon | outline_type: :full}

      assert [%Polygons{color: [:none], stroke_width: +0.0, dashes: :none}] =
               draw_panel(
                 full,
                 DataFrame.put(frame, :linetype, [:none, :none]),
                 @cartesian,
                 @params
               )

      assert [%Polygons{color: [:none], stroke_width: +0.0}] =
               draw_panel(full, DataFrame.put(frame, :linewidth, [nil, nil]), @cartesian, @params)
    end

    test "a position of NaN breaks a band as a missing one does" do
      frame = band([0.0, 1.0, 2.0], [0.0, :nan, 0.0], [2.0, 2.0, 2.0])

      assert [%Polygons{}, %Polygons{}] = draw_panel(@ribbon, frame, @cartesian, @params)
    end

    # ggplot2's `GeomRibbon` numbers each stretch of an area's complete rows, a row missing its
    # ymin in none: each stretch is an outline in the order of its rows, and a row in none is on
    # no line.
    test "an area's stretches are outlined in order, and its rows missing a ymin in no line" do
      rows = 70
      x_positions = Enum.map(1..rows, fn index -> index / 35 end)
      lows = Enum.map(1..rows, fn index -> if rem(index, 2) == 0, do: nil, else: 0.0 end)

      frame =
        x_positions
        |> band(lows, List.duplicate(2.0, rows))
        |> DataFrame.put(:y, List.duplicate(2.0, rows))

      assert [%Polygons{outlines: outlines}] = draw_panel(@area, frame, @cartesian, @params)

      firsts = Enum.map(outlines, fn [{x, _y} | _rest] -> x end)
      assert {length(outlines), firsts} == {35, Enum.sort(firsts)}

      gapped =
        [0.0, 0.5, 1.0, 1.5, 2.0]
        |> band([0.0, nil, nil, 0.0, 0.0], [2.0, 2.0, 2.0, 2.0, 2.0])
        |> DataFrame.put(:y, [2.0, 2.0, 2.0, 2.0, 2.0])

      assert [%Polygons{}, %Polylines{lines: [_upper, _lower]}] =
               draw_panel(%{@area | outline_type: :both}, gapped, @cartesian, @params)
    end

    test "a ribbon whose look varies along it is refused" do
      frame =
        [0.0, 2.0]
        |> band([0.0, 0.0], [4.0, 4.0])
        |> DataFrame.put(:fill, ["#FF0000", "#0000FF"])

      error =
        assert_raise ArgumentError, fn -> draw_panel(@ribbon, frame, @cartesian, @params) end

      assert error.message =~ "cannot vary its fill along it"
      assert error.message =~ "gradient"
    end

    test "an area's padding is left off its upper edge, kept on its lower" do
      frame =
        [0.0, 0.5, 1.5, 2.0]
        |> band([0.0, 0.0, 0.0, 0.0], [0.0, 4.0, 4.0, 0.0])
        |> DataFrame.put(:y, [0.0, 4.0, 4.0, 0.0])
        |> DataFrame.put(:align_padding, [true, false, false, true])

      assert [%Polygons{outlines: [outline]}, %Polylines{lines: [upper, lower]}] =
               draw_panel(%{@area | outline_type: :both}, frame, @cartesian, @params)

      assert {length(outline), upper, length(lower)} === {6, [{0.25, 1.0}, {0.75, 1.0}], 4}
    end

    test "an area drops a row missing its y, and a ribbon one missing its ymin" do
      frame =
        [0.0, 1.0, 2.0]
        |> band([0.0, nil, 0.0], [2.0, 4.0, 2.0])
        |> DataFrame.put(:y, [2.0, 4.0, 2.0])

      assert [%Polygons{outlines: [_first, _second]}] =
               draw_panel(%{@area | outline_type: :both}, frame, @cartesian, @params)

      assert [%Polygons{outlines: [_lone]}, %Polygons{outlines: [_last]}] =
               draw_panel(@ribbon, frame, @cartesian, @params)
    end
  end

  describe "draw_panel/5 for paths, in a line type" do
    setup do
      coord = %Coord.Cartesian{}

      %{
        coord: coord,
        params: Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      }
    end

    # Golden: ggplot2 4.0.3's `geom_line(linetype = ...)` through vdiffr 1.0.9: "dashed" 0.5 mm wide
    # `5.69,5.69`, 0.2 mm wide `4.00,4.00`, and "longdash" 2 mm wide `39.83,17.07`.
    test "a line is dashed, each length times its width in line-width units, or alone under one",
         %{coord: coord, params: params} do
      for {line_type, width, dashes} <- [
            {{4, 4}, 0.5, [5.69, 5.69]},
            {{4, 4}, 0.2, [4.0, 4.0]},
            {{7, 3}, 2.0, [39.83, 17.07]},
            {{}, 2.0, :none}
          ] do
        frame =
          DataFrame.new(
            x: [0.0, 4.0],
            y: [0.0, 4.0],
            group: [1, 1],
            linetype: [line_type, line_type],
            linewidth: [width, width]
          )

        assert [%Polylines{dashes: drawn}] = draw_panel(@path, frame, coord, params)
        assert rounded(drawn) === dashes
      end
    end

    # R's graphics engine draws no line whose line type is "blank".
    test "a blank line draws nothing", %{coord: coord, params: params} do
      frame = DataFrame.new(x: [0.0, 4.0], y: [0.0, 4.0], group: [1, 1], linetype: [:none, :none])

      assert draw_panel(@path, frame, coord, params) === []
    end

    # ggplot2 4.0.3's `geom_path(aes(colour = y), linetype = "dashed")`, and "blank" alike: "can't
    # have varying colour, linewidth, and/or alpha along the line when linetype isn't solid".
    test "a line not solid whose colour or alpha varies along it is refused, a blank one too",
         %{coord: coord, params: params} do
      for {line_type, look} <- [
            {{4, 4}, [color: ["#FF0000", "#0000FF", "#0000FF"]]},
            {:none, [color: ["#FF0000", "#0000FF", "#0000FF"]]},
            {{1, 3}, [alpha: [0.5, 1.0, 1.0]]}
          ] do
        frame =
          DataFrame.new(
            [
              x: [0.0, 2.0, 4.0],
              y: [0.0, 4.0, 0.0],
              group: [1, 1, 1],
              linetype: [line_type, line_type, line_type]
            ] ++ look
          )

        error =
          assert_raise ArgumentError, fn -> draw_panel(@path, frame, coord, params) end

        assert error.message =~ ":solid"
      end
    end

    # Golden: ggplot2 4.0.3's `layer_grob()` in R 4.6.1 for `geom_path()` of three groups, their
    # line types and widths set by `I()`: one polyline, each group in its own `lty` and `lwd`, in
    # group order. A group whose line type is missing, as a column holds a mapped blank one, is
    # dropped, as `handle_na()` drops rows missing a line type.
    test "lines alike in width and line type are one primitive, in group order, a missing type none",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 4.0, 0.0, 4.0, 0.0, 4.0, 0.0, 4.0],
          y: [1.0, 1.0, 2.0, 2.0, 3.0, 3.0, 4.0, 4.0],
          group: [1, 1, 2, 2, 3, 3, 4, 4],
          linetype: [{}, {}, {}, {}, nil, nil, {4, 4}, {4, 4}],
          linewidth: [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 2.0, 2.0]
        )

      assert [solid, dashed] = draw_panel(@path, frame, coord, params)

      assert {length(solid.lines), solid.dashes, solid.stroke_width, length(dashed.lines),
              rounded(dashed.dashes), dashed.stroke_width} ===
               {2, :none, @default_width, 1, [22.76, 22.76], @two_millimetres}
    end

    # ggplot2 4.0.3's `GeomPath` aborts in R 4.6.1 where any group is not solid and any group's look
    # varies, each group apart: a dashed line beside one whose width varies, or a line type changing
    # along one line, "can't have varying colour, linewidth, and/or alpha along the line when
    # linetype isn't solid".
    test "while any line is not solid, a look varying along any line is refused",
         %{coord: coord, params: params} do
      for look <- [
            [linetype: [{4, 4}, {4, 4}, {}, {}], linewidth: [0.5, 0.5, 1.0, 2.0]],
            [linetype: [{}, {}, {}, {4, 4}], linewidth: [0.5, 0.5, 0.5, 0.5]]
          ] do
        frame =
          DataFrame.new(
            [x: [0.0, 4.0, 0.0, 4.0], y: [1.0, 1.0, 2.0, 2.0], group: [1, 1, 2, 2]] ++ look
          )

        error =
          assert_raise ArgumentError, fn -> draw_panel(@path, frame, coord, params) end

        assert error.message =~ "cannot vary its colour, alpha, width or line type along it"
      end
    end

    # Golden: ggplot2 4.0.3's `geom_path(aes(colour = z), linewidth = 2)` through vdiffr 1.0.9:
    # segments 4.27 points wide.
    test "a solid line whose colour varies along it is drawn in solid segments at its width",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 2.0, 4.0],
          y: [0.0, 4.0, 0.0],
          group: [1, 1, 1],
          color: ["#FF0000", "#0000FF", "#0000FF"],
          linetype: [{}, {}, {}],
          linewidth: [2.0, 2.0, 2.0]
        )

      assert [%Segments{dashes: :none, color: ["#FF0000", "#0000FF"], stroke_width: width}] =
               draw_panel(@path, frame, coord, params)

      assert Float.round(width, 2) === 4.27
    end
  end

  describe "draw_panel/5 for paths" do
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

      assert [%Polylines{lines: lines}] = draw_panel(@path, frame, coord, params)
      assert lines === [[{0.25, 0.25}, {0.5, 0.5}], [{1.0, 0.75}, {1.0, 1.0}]]
    end

    # Golden: ggplot2 4.0.3's `layer_grob()` in R 4.6.1 for `geom_path()` through (0, 0) and (2, 4)
    # in red and a last row missing `y` in blue: one red polyline, as `handle_na()` drops the last
    # row before the look is tested for constancy.
    test "a row dropped at a group's end does not make its look vary",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 2.0, 4.0],
          y: [0.0, 4.0, nil],
          group: [1, 1, 1],
          color: ["#FF0000", "#FF0000", "#0000FF"]
        )

      assert [%Polylines{color: ["#FF0000"]}] = draw_panel(@path, frame, coord, params)
    end

    test "a piece of one point between missing positions draws nothing",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 2.0, 3.0, 4.0], y: [1.0, nil, 2.0, 3.0], group: [1, 1, 1, 1])

      assert [%Polylines{lines: [[{0.75, 0.5}, {1.0, 0.75}]]}] =
               draw_panel(@path, frame, coord, params)
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

      assert [%Polylines{} = polylines] = draw_panel(@path, frame, coord, params)
      assert polylines.lines === [[{1.0, 0.0}, {0.0, 0.0}], [{0.0, 1.0}, {1.0, 1.0}]]
      assert polylines.opacity === [0.25, 0.5]
    end

    test "a group of one row is not drawn, and a panel with no group of two draws nothing",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 2.0, 3.0], y: [1.0, 2.0, 3.0], group: [1, 1, 2])

      assert [%Polylines{lines: [[{0.25, 0.25}, {0.5, 0.5}]]}] =
               draw_panel(@path, frame, coord, params)

      single = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0], group: [1, 2])
      assert draw_panel(@path, single, coord, params) === []
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

      assert [%Segments{} = segments] = draw_panel(@path, frame, coord, params)
      assert segments.starts === [{0.0, 0.0}, {0.75, 0.75}, {0.0, 1.0}]
      assert segments.ends === [{0.25, 0.25}, {1.0, 1.0}, {1.0, 1.0}]
      assert segments.opacity === [0.1, 0.4, 1.0]
    end

    # Golden: ggplot2 4.0.3's `layer_grob()` in R 4.6.1 for `geom_path(aes(linewidth = w))`, and its
    # drawing through vdiffr 1.0.9: a segment from each row to the next, each as wide as the row it
    # starts from, a missing width's `lwd` `NA` and not drawn, as R's graphics engine draws no line
    # of no width, and rows missing a width or a line type at a group's ends dropped, as
    # `handle_na()` drops them.
    test "where a width varies along a line, each segment is its start's width, a missing one none",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 1.0, 2.0, 3.0, 4.0, 0.0, 4.0, 4.0],
          y: [0.0, 1.0, 2.0, 3.0, 4.0, 4.0, 4.0, 0.0],
          group: [1, 1, 1, 1, 1, 2, 2, 2],
          linewidth: [nil, 0.5, 0.5, nil, 2.0, 2.0, 2.0, 2.0],
          linetype: [{}, {}, {}, {}, {}, {}, {}, nil]
        )

      assert [thin, thick] = draw_panel(@path, frame, coord, params)

      assert {thin.starts, thin.ends, thin.stroke_width, thick.starts, thick.ends,
              thick.stroke_width} ===
               {[{0.25, 0.25}, {0.5, 0.5}], [{0.5, 0.5}, {0.75, 0.75}], @default_width,
                [{0.0, 1.0}], [{1.0, 1.0}], @two_millimetres}
    end

    test "every line is as wide as the layer sets, and ended, joined and mitred as the geom says",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0], group: [1, 1], linewidth: [2.0, 2.0])
      geom = %Geom.Path{line_end: :round, line_join: :mitre, mitre_limit: 4.0, arrow: :none}

      assert [%Polylines{} = polylines] = draw_panel(geom, frame, coord, params)

      assert {polylines.stroke_width, polylines.line_end, polylines.line_join,
              polylines.mitre_limit} === {@two_millimetres, :round, :mitre, 4.0}
    end

    test "a table without alpha or a line width draws opaque lines ggplot2's default width",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 2.0], y: [1.0, 2.0], group: [1, 1])

      assert [%Polylines{opacity: [1.0], stroke_width: @default_width, color: ["#000000"]}] =
               draw_panel(@path, frame, coord, params)
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
               draw_panel(@path, own, coord, params)

      replaced = DataFrame.put(own, :alpha, [0.2, 0.4])

      assert [%Segments{color: ["#FF0000"], opacity: [0.2]}] =
               draw_panel(@path, replaced, coord, params)
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
               draw_panel(@path, frame, coord, params)
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

      assert [%Segments{} = segments] = draw_panel(@path, frame, coord, params)
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

      assert draw_panel(@path, frame, coord, params) === []

      assert [%Polylines{lines: [[{0.5, 0.5}, {0.75, 0.75}]], color: ["#FF0000"]}] =
               draw_panel(@path, missing, coord, params)
    end

    test "a line is drawn as a path through its rows", %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 3.0, 2.0], y: [1.0, 2.0, 3.0], group: [1, 1, 1])

      assert draw_panel(@line, frame, coord, params) ===
               draw_panel(@path, frame, coord, params)
    end
  end

  describe "arrowheads" do
    setup do
      coord = %Coord.Cartesian{}

      %{
        coord: coord,
        params: Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      }
    end

    # Golden: ggplot2 4.0.3's `geom_path(aes(alpha = a, group = g), arrow = arrow(ends = e))` over
    # these rows through vdiffr 1.0.9, for each end (test/golden/path_arrow_varying.svg for
    # "both"): `repair_segment_arrow()` keeps a lone segment's head, the first's and the last's at
    # the line's own ends, and draws every other with no length, three points at its tip.
    test "a path drawn as segments has heads only at each line's own ends",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 1.0, 2.0, 3.0, 0.0, 4.0],
          y: [0.0, 1.0, 2.0, 3.0, 4.0, 4.0],
          group: [1, 1, 1, 1, 2, 2],
          alpha: [0.1, 0.2, 0.3, 0.4, 1.0, 1.0]
        )

      heads =
        for ends <- [:last, :first, :both] do
          assert [%Segments{arrows: arrows}] =
                   draw_panel(arrowed(@path, ends: ends), frame, coord, params)

          Enum.map(arrows, fn head -> {head.ends, head.length} end)
        end

      assert heads === [
               [{:last, 0.0}, {:last, 0.0}, {:last, 18.0}, {:last, 18.0}],
               [{:first, 18.0}, {:first, 0.0}, {:first, 0.0}, {:first, 18.0}],
               [{:first, 18.0}, {:both, 0.0}, {:last, 18.0}, {:both, 18.0}]
             ]

      assert [%Segments{arrows: arrows}] = draw_panel(arrowed(@path, []), frame, coord, params)

      assert Enum.map(arrows, fn head -> {head.fill, head.fill_opacity} end) ===
               [{"#000000", 0.1}, {"#000000", 0.2}, {"#000000", 0.3}, {"#000000", 1.0}]
    end

    # As grid draws a polyline broken by `NA`s (test/golden/path_arrow_missing.svg): its heads at
    # its own first and last points, so a lone first piece takes its head with it.
    test "a broken line has its first end's head on its first piece and its last's on its last",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 1.0, 2.0, 3.0, 4.0, 3.0, 2.0, 1.0],
          y: [0.0, 1.0, nil, 2.0, 3.0, nil, 4.0, 4.0],
          group: [1, 1, 1, 1, 1, 1, 1, 1]
        )

      heads =
        for ends <- [:both, :last, :first] do
          assert [%Polylines{lines: [_first, _middle, _last], arrows: arrows}] =
                   draw_panel(arrowed(@path, ends: ends), frame, coord, params)

          Enum.map(arrows, fn
            :none -> :none
            head -> head.ends
          end)
        end

      assert heads === [[:first, :none, :last], [:none, :none, :last], [:first, :none, :none]]

      lone_first =
        DataFrame.new(x: [0.0, 1.0, 2.0, 3.0], y: [0.0, nil, 1.0, 2.0], group: [1, 1, 1, 1])

      assert [%Polylines{arrows: :none}] =
               draw_panel(arrowed(@path, ends: :first), lone_first, coord, params)
    end

    # As ggplot2 4.0.3's `GeomSegment` and `GeomPath` fill a head: `alpha(arrow.fill %||% colour,
    # alpha)` (test/golden/segment_arrow.svg).
    test "a segment's head is filled with the arrow's fill, or its colour, at its alpha",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [1.0, 2.0],
          y: [1.0, 1.0],
          xend: [2.0, 3.0],
          yend: [2.0, 2.0],
          group: [-1, -1],
          color: ["#FF0000", "#0000FF80"],
          alpha: [0.5, nil]
        )

      fills =
        for fill <- [:color, "#00FF00"] do
          assert [%Segments{arrows: arrows}] =
                   draw_panel(arrowed(@segment, fill: fill), frame, coord, params)

          Enum.map(arrows, fn head -> {head.fill, Float.round(head.fill_opacity, 3)} end)
        end

      assert fills === [
               [{"#FF0000", 0.5}, {"#0000FF", 0.502}],
               [{"#00FF00", 0.5}, {"#00FF00", 1.0}]
             ]
    end

    # ggplot2 4.0.3's `GeomSegment` hands `GeomPath$draw_panel()` its `arrow` and not its
    # `arrow.fill` (test/golden/segment_arrow_radial.svg).
    test "a segment drawn as a path under radial coordinates leaves the arrow's fill behind" do
      coord = %Coord.Radial{}
      params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0], y: [2.0], xend: [3.0], yend: [3.0], group: [-1])

      assert [%Polylines{arrows: [%Arrow{fill: "#000000", ends: :last, length: 18.0}]}] =
               draw_panel(arrowed(@segment, fill: "#FFFFFF"), frame, coord, params)
    end

    # Golden: ggplot2 4.0.3's `geom_segment(aes(colour = g), arrow = arrow(type = "closed"),
    # arrow.fill = "white")` through vdiffr 1.0.9, at grid's 30 degrees and 0.25 inches: each key
    # carries the arrow, filled, at its alpha, and is 19.49 points wide and 18.00 tall, the head's
    # room, `draw_key_path()`'s glyph size, whatever the line's width.
    test "a path's key carries its arrowhead and needs the head's room" do
      geom = arrowed(@path, fill: "#FFFFFF")

      assert [%Segments{arrows: [%Arrow{fill: "#FFFFFF", fill_opacity: 0.5}]}] =
               draw_key(geom, %{color: "#FF0000", alpha: 0.5})

      assert rounded_size(key_size(geom, %{linewidth: 8.0})) === {19.49, 18.0}
      assert rounded_size(key_size(geom, %{linewidth: nil})) === {19.49, 18.0}
      assert [%Segments{arrows: :none}] = draw_key(@path, %{})
    end
  end

  describe "draw_panel/5 for segments" do
    setup do
      coord = %Coord.Cartesian{}

      %{
        coord: coord,
        params: Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      }
    end

    test "each row is a straight line from its start to its end, in row order",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 4.0],
          y: [0.0, 4.0],
          xend: [2.0, 1.0],
          yend: [4.0, 3.0],
          group: [-1, -1],
          color: ["#FF0000", "#0000FF"]
        )

      assert [%Segments{} = segments] = draw_panel(@segment, frame, coord, params)
      assert segments.starts === [{0.0, 0.0}, {1.0, 1.0}]
      assert segments.ends === [{0.5, 1.0}, {0.25, 0.75}]
      assert segments.color === ["#FF0000", "#0000FF"]
      assert segments.arrows === :none

      assert {segments.line_end, segments.line_join, segments.mitre_limit} ===
               {:butt, :round, 10.0}
    end

    test "a row missing a position, its width or its line type is not drawn, and an infinite end " <>
           "reaches the panel's edge",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [1.0, 1.0, 1.0, 1.0, 1.0, 2.0],
          y: [1.0, 1.0, :nan, 1.0, 1.0, 2.0],
          xend: [:infinity, nil, 2.0, 2.0, 2.0, 3.0],
          yend: [2.0, 2.0, 2.0, 2.0, 2.0, 3.0],
          group: [-1, -1, -1, -1, -1, -1],
          linewidth: [0.5, 0.5, 0.5, nil, 0.5, 0.5],
          linetype: [{}, {}, {}, {}, nil, {}]
        )

      assert [%Segments{starts: starts, ends: ends}] = draw_panel(@segment, frame, coord, params)
      assert starts === [{0.25, 0.25}, {0.5, 0.5}]
      assert ends === [{1.0, 0.5}, {0.75, 0.75}]
    end

    # Golden: ggplot2 4.0.3 and vdiffr 1.0.9 draw a segment whose colour is `NA` as a `<line>` with
    # `stroke: none`, and one in the line type `"blank"` not at all.
    test "a colour of :none is a line of no stroke, and a blank line type draws none",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 1.0],
          y: [0.0, 1.0],
          xend: [1.0, 2.0],
          yend: [1.0, 2.0],
          group: [-1, -1],
          color: ["#FF0000", nil]
        )

      blank = DataFrame.put(frame, :linetype, [:none, :none])

      assert [%Segments{color: colors, opacity: opacities}] =
               draw_panel(@segment, frame, coord, params)

      assert colors === ["#FF0000", :none]
      assert opacities === [1.0, 0.0]
      assert draw_panel(@segment, blank, coord, params) === []
    end

    test "each run of segments alike in width and line type is one primitive, in row order",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.0, 1.0, 2.0, 3.0],
          y: [0.0, 0.0, 0.0, 0.0],
          xend: [1.0, 2.0, 3.0, 4.0],
          yend: [4.0, 4.0, 4.0, 4.0],
          group: [-1, -1, -1, -1],
          linewidth: [0.5, 0.5, 2.0, 2.0],
          linetype: [{}, {}, {}, {4, 4}]
        )

      primitives = draw_panel(@segment, frame, coord, params)

      assert Enum.map(primitives, fn segments -> length(segments.starts) end) == [2, 1, 1]

      assert Enum.map(primitives, fn segments -> segments.stroke_width end) ===
               [@default_width, @two_millimetres, @two_millimetres]

      assert [:none, :none, [_dash, _gap]] =
               Enum.map(primitives, fn segments -> segments.dashes end)
    end

    test "a layer mapping only xend ends each segment at its own y, and only yend at its own x",
         %{coord: coord, params: params} do
      across = DataFrame.new(x: [1.0], y: [1.0], xend: [3.0], group: [-1])
      up = DataFrame.new(x: [1.0], y: [1.0], yend: [3.0], group: [-1])

      assert [%Segments{ends: [{0.75, 0.25}]}] = draw_panel(@segment, across, coord, params)
      assert [%Segments{ends: [{0.25, 0.75}]}] = draw_panel(@segment, up, coord, params)
    end

    test "under radial coordinates each row is a path of its two ends, following the circle, " <>
           "with the segments' line ends and round corners" do
      coord = %Coord.Radial{}
      params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      geom = %Geom.Segment{line_end: :square, line_join: :mitre, arrow: :none}

      frame =
        DataFrame.new(
          x: [1.0, 2.0],
          y: [2.0, 2.0],
          xend: [3.0, nil],
          yend: [2.0, 3.0],
          group: [-1, -1]
        )

      placed = Coord.transform(coord, DataFrame.new(x: [1.0, 3.0], y: [2.0, 2.0]), params)

      ends =
        placed
        |> DataFrame.pull(:x)
        |> Enum.zip_with(DataFrame.pull(placed, :y), fn x, y -> {x, y} end)

      assert [%Polylines{lines: [line]} = polylines] = draw_panel(geom, frame, coord, params)
      assert [List.first(line), List.last(line)] === ends
      assert [_start, _step, _more | _rest] = line

      assert {polylines.line_end, polylines.line_join, polylines.mitre_limit} ===
               {:square, :round, 10.0}
    end
  end

  describe "setup_data/3, draw_panel/5 and draw_key/3 for line ranges and point ranges" do
    setup do
      coord = %Coord.Cartesian{}

      %{
        coord: coord,
        params: Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      }
    end

    # ggplot2's `has_flipped_aes(range_is_orthogonal = TRUE)`: a range given in y runs along x,
    # one given only in x along y, and the layer's orientation over either.
    test "a range runs along y where it has no ymin or ymax, or as its orientation says" do
      vertical = DataFrame.new(x: [1.0], ymin: [0.0], ymax: [2.0])
      horizontal = DataFrame.new(y: [1.0], xmin: [0.0], xmax: [2.0])
      both = DataFrame.new(x: [1.0], y: [1.0], ymin: [0.0], xmax: [2.0])

      flipped = fn geom, frame ->
        geom
        |> Geom.setup_data(frame, @continuous)
        |> DataFrame.pull(:flipped_aes)
      end

      assert flipped.(@linerange, vertical) === [false]
      assert flipped.(@linerange, horizontal) === [true]
      assert flipped.(@pointrange, both) === [false]
      assert flipped.(%{@pointrange | orientation: :y}, both) === [true]
      assert flipped.(%{@linerange | orientation: :x}, horizontal) === [false]
    end

    test "each row is a segment from its ymin to its ymax at its x, or turned, from its xmin to " <>
           "its xmax at its y",
         %{coord: coord, params: params} do
      vertical =
        DataFrame.new(
          x: [1.0, 3.0],
          ymin: [0.0, 2.0],
          ymax: [2.0, 4.0],
          group: [1, 2],
          flipped_aes: [false, false]
        )

      horizontal =
        DataFrame.new(
          y: [1.0],
          xmin: [0.0],
          xmax: [4.0],
          group: [1],
          flipped_aes: [true]
        )

      assert [%Segments{} = up] = draw_panel(@linerange, vertical, coord, params)
      assert {up.starts, up.ends} === {[{0.25, 0.0}, {0.75, 0.5}], [{0.25, 0.5}, {0.75, 1.0}]}

      assert [%Segments{} = across] = draw_panel(@linerange, horizontal, coord, params)
      assert {across.starts, across.ends} === {[{0.0, 0.25}], [{1.0, 0.25}]}
    end

    # ggplot2's `GeomLinerange` hands its rows to `GeomSegment$draw_panel()` with its `lineend`
    # alone, so its corners are a segment's, round, and it draws no arrowheads.
    test "a line range is ended as the layer says, its corners round, a row missing an end not " <>
           "drawn",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [1.0, 2.0],
          ymin: [nil, 1.0],
          ymax: [2.0, 3.0],
          group: [1, 2],
          flipped_aes: [false, false]
        )

      assert [%Segments{} = lines] =
               draw_panel(%{@linerange | line_end: :round}, frame, coord, params)

      assert {lines.starts, lines.line_end, lines.line_join, lines.arrows} ===
               {[{0.5, 0.25}], :round, :round, :none}
    end

    # ggplot2's `GeomPointrange$draw_panel()`: a `gList()` of the line ranges' segments and then
    # `GeomPoint$draw_panel()` at `size * fatten`, 4.
    test "a point range draws every line and then every point, at four times its size",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [1.0, 3.0],
          y: [1.0, 3.0],
          ymin: [0.0, 2.0],
          ymax: [2.0, 4.0],
          group: [1, 2],
          flipped_aes: [false, false],
          size: [0.5, 1.0],
          stroke: [1.0, 1.0]
        )

      assert [%Segments{starts: [{0.25, +0.0}, {0.75, 0.5}]}, %Circles{} = points] =
               draw_panel(@pointrange, frame, coord, params)

      # A missing size draws no point, as `GeomPoint` drops the row.
      unsized = DataFrame.put(frame, :size, [nil, nil])
      assert [%Segments{}] = draw_panel(@pointrange, unsized, coord, params)

      as_point =
        draw_panel(%Geom.Point{}, DataFrame.put(frame, :size, [2.0, 4.0]), coord, params)

      assert [points] == as_point
    end

    test "a line range's key runs up the key, or across it for a horizontal layer, with the " <>
           "layer's ends" do
      assert [%Segments{starts: [{0.5, 0.1}], ends: [{0.5, 0.9}], line_end: :square}] =
               draw_key(%{@linerange | line_end: :square}, %{flipped_aes: false})

      assert [%Segments{starts: [{0.1, 0.5}], ends: [{0.9, 0.5}]}] =
               draw_key(@linerange, %{flipped_aes: true})
    end

    # ggplot2's `draw_key_pointrange()`: `draw_key_linerange()` and `draw_key_point()` at
    # `size * 4`.
    test "a point range's key is a line range's with a point over it at four times its size" do
      key = %{flipped_aes: true, size: 1.5, stroke: 1.0}

      assert [%Segments{starts: [{0.1, 0.5}]} | point] = draw_key(@pointrange, key)
      assert point == draw_key(%Geom.Point{}, %{key | size: 6.0})
    end
  end

  describe "setup_data/3, draw_panel/5 and draw_key/3 for error bars and crossbars" do
    setup do
      coord = %Coord.Cartesian{}

      %{
        coord: coord,
        params: Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      }
    end

    # ggplot2's `compute_data_size(zero = FALSE, discrete = TRUE)` across panels: the smallest
    # spacing in any panel, 1 on a discrete axis, times 0.9.
    test "a bar's sides are its x less and plus half its width, or 0.9 of the closest spacing in " <>
           "any panel, the width then dropped" do
      frame =
        DataFrame.new(
          x: [1.0, 3.0, 1.0, 1.5],
          ymin: [0.0, 0.0, 0.0, 0.0],
          ymax: [1.0, 1.0, 1.0, 1.0],
          panel: [1, 1, 2, 2]
        )

      set_up = Geom.setup_data(@errorbar, frame, @continuous)
      assert DataFrame.pull(set_up, :xmin) === [0.775, 2.775, 0.775, 1.275]
      assert DataFrame.pull(set_up, :xmax) === [1.225, 3.225, 1.225, 1.725]
      refute :width in DataFrame.names(set_up)

      discrete = Geom.setup_data(@crossbar, frame, %{x: :discrete, y: :continuous})
      assert DataFrame.pull(discrete, :xmin) === [0.55, 2.55, 0.55, 1.05]

      widened =
        Geom.setup_data(@errorbar, DataFrame.put(frame, :width, [2, 2, 1, 1]), @continuous)

      assert DataFrame.pull(widened, :xmax) === [2.0, 4.0, 1.5, 2.0]
    end

    test "a horizontal bar's sides are set along y, from the y axis's kind" do
      frame = DataFrame.new(y: [1.0, 2.0], xmin: [0.0, 0.0], xmax: [1.0, 1.0], panel: [1, 1])
      set_up = Geom.setup_data(@errorbar, frame, %{x: :continuous, y: :discrete})

      assert DataFrame.pull(set_up, :flipped_aes) === [true, true]
      assert DataFrame.pull(set_up, :ymin) === [0.55, 1.55]
      assert DataFrame.pull(set_up, :ymax) === [1.45, 2.45]
    end

    # ggplot2 4.0.3 fails at `x - width / 2` for a width an expression makes text.
    test "a width that is not a number is refused when set up" do
      frame =
        DataFrame.new(x: [1.0], ymin: [0.0], ymax: [1.0], panel: [1], width: ["wide"])

      for geom <- [@errorbar, @crossbar] do
        error = assert_raise ArgumentError, fn -> Geom.setup_data(geom, frame, @continuous) end
        assert error.message =~ "width is a :string column"
      end
    end

    # ggplot2's `GeomErrorbar$draw_panel()`: eight points a row, `xmin, xmax, NA, x, x, NA, xmin,
    # xmax` across and `ymax, ymax, NA, ymax, ymin, NA, ymin, ymin` up, a group a row.
    test "an error bar is its top whisker, its stem and its bottom whisker, a path a row",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [2.0],
          xmin: [1.0],
          xmax: [3.0],
          ymin: [1.0],
          ymax: [3.0],
          group: [1],
          flipped_aes: [false]
        )

      assert [%Polylines{lines: lines, line_end: :butt, line_join: :round}] =
               draw_panel(@errorbar, frame, coord, params)

      assert lines === [
               [{0.25, 0.75}, {0.75, 0.75}],
               [{0.5, 0.75}, {0.5, 0.25}],
               [{0.25, 0.25}, {0.75, 0.25}]
             ]
    end

    test "a horizontal error bar is turned, its whiskers up the panel",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          y: [2.0],
          ymin: [1.0],
          ymax: [3.0],
          xmin: [1.0],
          xmax: [3.0],
          group: [1],
          flipped_aes: [true]
        )

      assert [%Polylines{lines: [top | _rest]}] = draw_panel(@errorbar, frame, coord, params)
      assert top === [{0.75, 0.25}, {0.75, 0.75}]
    end

    # ggplot2's `GeomCrossbar$draw_panel()`: a `gList()` of `GeomPolygon` over every row, then
    # `GeomSegment` over every row's middle, at `linewidth * fatten`, 2.5.
    test "a crossbar layer draws every box, then every line across, 2.5 times the border's width",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [1.0, 3.0],
          y: [1.0, 3.0],
          xmin: [0.5, 2.5],
          xmax: [1.5, 3.5],
          ymin: [0.0, 2.0],
          ymax: [2.0, 4.0],
          group: [1, 2],
          flipped_aes: [false, false]
        )

      assert [%Polygons{} = first, %Polygons{}, %Segments{} = across, %Segments{}] =
               draw_panel(@crossbar, frame, coord, params)

      assert first.outlines === [
               [{0.125, 0.5}, {0.125, +0.0}, {0.375, +0.0}, {0.375, 0.5}, {0.125, 0.5}]
             ]

      assert {first.line_end, first.line_join} === {:butt, :mitre}
      assert {across.starts, across.ends} === {[{0.125, 0.25}], [{0.375, 0.25}]}
      assert first.stroke_width === @default_width
      assert across.stroke_width === 1.25 * (72.27 / 25.4) / 96 * 72
      assert {first.mitre_limit, across.mitre_limit} === {10.0, 10.0}
    end

    # R's engine draws no line of no width, and svglite writes a border of none 0 wide.
    test "a crossbar of a missing width draws its box unbordered and no line across",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [1.0],
          y: [1.0],
          xmin: [0.5],
          xmax: [1.5],
          ymin: [0.0],
          ymax: [2.0],
          group: [1],
          flipped_aes: [false],
          linewidth: [nil]
        )

      assert [%Polygons{stroke_width: +0.0}] = draw_panel(@crossbar, frame, coord, params)
    end

    test "a crossbar's middle and box looks replace its own" do
      geom = %{@crossbar | middle: %{color: "#FF0000", linewidth: 1.0}, box: %{color: "#0000FF"}}

      frame =
        DataFrame.new(
          x: [1.0],
          y: [1.0],
          xmin: [0.5],
          xmax: [1.5],
          ymin: [0.0],
          ymax: [2.0],
          group: [1],
          flipped_aes: [false]
        )

      params = Coord.panel_params(@cartesian, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      assert [%Polygons{color: ["#0000FF"]}, %Segments{color: ["#FF0000"]} = across] =
               draw_panel(geom, frame, @cartesian, params)

      assert across.stroke_width === @two_millimetres / 2
    end

    # ggplot2's `draw_key_crossbar()`: `rectGrob(height = 0.5, width = 0.75)` and a line from
    # 0.125 to 0.875, each turned for a horizontal layer, the line not widened.
    test "a crossbar's key is a box and a line across it, turned for a horizontal layer" do
      assert [%Rectangles{} = box, %Polylines{lines: [[{0.125, 0.5}, {0.875, 0.5}]]} = across] =
               draw_key(@crossbar, %{flipped_aes: false})

      assert {box.xmin, box.xmax, box.ymin, box.ymax} === {[0.125], [0.875], [0.25], [0.75]}
      assert across.stroke_width === box.stroke_width
      assert {box.mitre_limit, across.mitre_limit} === {10.0, 10.0}

      # A missing line type, R's `NA`, draws the box unbordered and no line across.
      assert [%Rectangles{color: [:none]}] =
               draw_key(@crossbar, %{flipped_aes: false, linetype: nil})

      assert [%Rectangles{xmin: [0.25], ymin: [0.125]}, %Polylines{lines: [[{0.5, 0.125}, _end]]}] =
               draw_key(@crossbar, %{flipped_aes: true})
    end

    test "an error bar's key is a path's, across the key either way" do
      assert draw_key(@errorbar, %{flipped_aes: false}) == draw_key(@path, %{})
      assert draw_key(@errorbar, %{flipped_aes: true}) == draw_key(@path, %{})
    end
  end

  describe "draw_panel/5 for a range layer's empty panel" do
    test "a panel of no rows draws nothing, and a layer of no rows is set up with no sides" do
      params = Coord.panel_params(@cartesian, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})

      row =
        DataFrame.new(
          x: [1.0],
          y: [1.0],
          xmin: [0.5],
          xmax: [1.5],
          ymin: [0.0],
          ymax: [2.0],
          group: [1],
          panel: [1],
          flipped_aes: [false]
        )

      empty = DataFrame.slice(row, [])

      for geom <- [@linerange, @errorbar, @crossbar] do
        assert draw_panel(geom, empty, @cartesian, params) == []
      end

      unset = DataFrame.select(empty, x: :x, ymin: :ymin, panel: :panel)
      set_up = Geom.setup_data(@errorbar, unset, @continuous)

      assert DataFrame.row_count(set_up) == 0
      assert {DataFrame.pull(set_up, :xmin), DataFrame.pull(set_up, :xmax)} == {[], []}
    end
  end

  describe "draw_panel/5 for reference lines" do
    setup do
      coord = %Coord.Cartesian{}

      %{
        coord: coord,
        params: Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{10.0, 20.0}, [], []})
      }
    end

    test "a horizontal line crosses the panel's x extent at its yintercept, each repeat drawn once",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          yintercept: [15.0, 12.5, 15.0],
          group: [-1, -1, -1],
          color: ["#FF0000", "#0000FF", "#FF0000"]
        )

      assert [%Segments{} = lines] = draw_panel(@hline, frame, coord, params)
      assert {lines.starts, lines.ends} === {[{0.0, 0.5}, {0.0, 0.25}], [{1.0, 0.5}, {1.0, 0.25}]}
      assert lines.color === ["#FF0000", "#0000FF"]
    end

    test "a vertical line runs up the panel's y extent at its xintercept, each repeat drawn once",
         %{coord: coord, params: params} do
      frame = DataFrame.new(xintercept: [1.0, 3.0, 1.0], group: [-1, -1, -1])

      assert [%Segments{} = lines] = draw_panel(@vline, frame, coord, params)

      assert {lines.starts, lines.ends} ===
               {[{0.25, 0.0}, {0.75, 0.0}], [{0.25, 1.0}, {0.75, 1.0}]}
    end

    # ggplot2's `GeomHline` and `GeomVline` hand their rows to `GeomSegment$draw_panel()` with their
    # `lineend` alone, so their corners are a segment's, round.
    test "a reference line is ended as the layer says, its corners round",
         %{coord: coord, params: params} do
      frame = DataFrame.new(yintercept: [15.0], group: [-1])

      assert [%Segments{line_end: :square, line_join: :round}] =
               draw_panel(%Geom.Hline{line_end: :square}, frame, coord, params)
    end

    test "a line missing its intercept is not drawn", %{coord: coord, params: params} do
      frame = DataFrame.new(xintercept: [nil, 2.0], group: [-1, -1])

      assert [%Segments{starts: [{0.5, +0.0}]}] = draw_panel(@vline, frame, coord, params)
    end

    test "under radial coordinates a horizontal line is a circle and a vertical one a spoke" do
      coord = %Coord.Radial{}
      params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{10.0, 20.0}, [], []})

      assert [%Polylines{lines: [circle]}] =
               draw_panel(@hline, DataFrame.new(yintercept: [15.0], group: [-1]), coord, params)

      assert [%Polylines{lines: [spoke]}] =
               draw_panel(@vline, DataFrame.new(xintercept: [1.0], group: [-1]), coord, params)

      # Every point of the circle as far from the centre; the spoke from the centre out at 3
      # o'clock, x's 1 a quarter turn round its extent.
      radii =
        circle
        |> Enum.map(fn {x, y} ->
          ((x - 0.5) ** 2 + (y - 0.5) ** 2)
          |> :math.sqrt()
          |> Float.round(9)
        end)
        |> Enum.uniq()

      heights = Enum.uniq_by(spoke, fn {_x, y} -> Float.round(y, 9) end)

      assert {Enum.count(circle) > 2, Enum.count(radii)} === {true, 1}
      assert {List.first(spoke), heights} === {{0.5, 0.5}, [{0.5, 0.5}]}
    end
  end

  # The panel runs 0 to 4 along x and 10 to 20 up y, so clipped, as a cartesian panel is by
  # default, the extents a diagonal line is cut to are those widened by their widths each side, -4
  # to 8 and 0 to 30, a cell's -1 to 2. Each end is worked out as `GeomAbline` works it out: x where
  # y meets each end of its extent, `(y - intercept) / slope`, the lesser no lower than x's start
  # and the greater no higher than its end, then `y = intercept + slope * x` at both. Golden: every
  # cartesian end is ggplot2 4.0.3's own, the `x0`, `y0`, `x1` and `y1` of `layer_grob()` for the
  # same lines under `coord_cartesian(xlim = c(0, 4), ylim = c(10, 20), expand = FALSE)`, clipped
  # or not; the infinite intercept and slope draw a `zeroGrob()`.
  describe "draw_panel/5 for diagonal lines" do
    setup do
      coord = %Coord.Cartesian{}

      %{
        coord: coord,
        params: Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{10.0, 20.0}, [], []})
      }
    end

    test "a line runs between the widened extents, cut to the x extent where y stays inside",
         %{coord: coord, params: params} do
      # y = 10 + x meets y's ends at x -10 and 20, cut to -4 and 8, where y is 6 and 18.
      frame = DataFrame.new(intercept: [10.0], slope: [1.0], group: [-1])

      assert [%Segments{starts: [{-1.0, -0.4}], ends: [{2.0, 0.8}]}] =
               draw_panel(@abline, frame, coord, params)
    end

    test "a steep line is cut to where its y meets the y extent's ends, whichever way it slopes",
         %{coord: coord, params: params} do
      # y = 10 + 10x meets y's 0 and 30 at x -1 and 2; y = 20 - 10x meets them at 2 and -1.
      frame = DataFrame.new(intercept: [10.0, 20.0], slope: [10.0, -10.0], group: [-1, -1])

      assert [%Segments{} = lines] = draw_panel(@abline, frame, coord, params)

      assert {lines.starts, lines.ends} ===
               {[{-0.25, -1.0}, {-0.25, 2.0}], [{0.5, 2.0}, {0.5, -1.0}]}
    end

    test "a flat line runs the whole x extent, from the division's infinities",
         %{coord: coord, params: params} do
      frame = DataFrame.new(intercept: [15.0], slope: [0.0], group: [-1])

      assert [%Segments{starts: [{-1.0, 0.5}], ends: [{2.0, 0.5}]}] =
               draw_panel(@abline, frame, coord, params)
    end

    test "each repeat is drawn once, its corners round and its ends as the layer says",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          intercept: [10.0, 10.0, 12.0],
          slope: [1.0, 1.0, 1.0],
          group: [-1, -1, -1]
        )

      assert [%Segments{starts: [_first, _second], line_end: :square, line_join: :round}] =
               draw_panel(%Geom.Abline{line_end: :square}, frame, coord, params)
    end

    # R's `NA` and infinities: a missing intercept leaves every end missing; an infinite slope
    # makes `0 * Inf`, NaN, at y; an infinite intercept `Inf - Inf`, NaN, at the end's y.
    test "a line missing its intercept or slope draws nothing, and nor does an infinite one",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          intercept: [nil, 0.0, :infinity, 10.0],
          slope: [1.0, :infinity, 1.0, 1.0],
          group: [-1, -1, -1, -1]
        )

      assert [%Segments{starts: [{-1.0, -0.4}]}] = draw_panel(@abline, frame, coord, params)
    end

    test "unclipped, a line runs between the extents themselves", %{params: params} do
      coord = %Coord.Cartesian{clip: :off}
      frame = DataFrame.new(intercept: [10.0], slope: [1.0], group: [-1])

      assert [%Segments{starts: [{+0.0, +0.0}], ends: [{1.0, 0.4}]}] =
               draw_panel(@abline, frame, coord, params)
    end

    # As R draws them: y = 100 + x is 100 at x's start, and meets y's end, 20, at x -80, so its
    # end is cut to that, below its start, and the line is drawn above and left of the panel; a
    # flat line on y's end meets it at `0 / 0`, NaN, which leaves the row out.
    test "unclipped, a line missing the panel is drawn beyond it, and one on its edge not at all",
         %{params: params} do
      coord = %Coord.Cartesian{clip: :off}
      frame = DataFrame.new(intercept: [100.0, 20.0], slope: [1.0, 0.0], group: [-1, -1])

      assert [%Segments{starts: [{+0.0, 9.0}], ends: [{-20.0, 1.0}]}] =
               draw_panel(@abline, frame, coord, params)
    end

    # `GeomAbline` widens the extents only where the coordinate system is linear and clipped, so a
    # radial panel clipped, which `coord_radial/1` cannot yet ask for, is not widened either.
    test "under radial coordinates a line follows the panel's curves between the extents, clipped or not" do
      params = Coord.panel_params(%Coord.Radial{}, {{0.0, 4.0}, [], []}, {{10.0, 20.0}, [], []})
      frame = DataFrame.new(intercept: [10.0], slope: [1.0], group: [-1])

      # Not widened: y = 10 + x from x's start, at 10, to its end, at 14.
      placed =
        Coord.transform(%Coord.Radial{}, DataFrame.new(x: [0.0, 4.0], y: [10.0, 14.0]), params)

      ends =
        placed
        |> DataFrame.pull(:x)
        |> Enum.zip_with(DataFrame.pull(placed, :y), fn x, y -> {x, y} end)

      for coord <- [%Coord.Radial{}, %Coord.Radial{clip: :on}] do
        assert [%Polylines{lines: [line]}] = draw_panel(@abline, frame, coord, params)
        assert [List.first(line), List.last(line)] === ends
        assert [_start, _step, _more | _rest] = line
      end
    end

    test "an intercept or slope an expression makes that is not a number is refused" do
      axes = %{x: :continuous, y: :continuous}

      for {intercepts, slopes, refused} <- [{["a"], [1.0], "intercept"}, {[1.0], ["a"], "slope"}] do
        frame = DataFrame.new(intercept: intercepts, slope: slopes)

        assert_raise ArgumentError,
                     "a line is drawn at y = intercept + slope * x, so its #{refused} must be a " <>
                       "number, but the layer's #{refused} is a :string column",
                     fn -> Geom.setup_data(@abline, frame, axes) end
      end

      numbers = DataFrame.new(intercept: [1], slope: [nil])
      assert Geom.setup_data(@abline, numbers, axes) === numbers
    end
  end

  describe "draw_panel/5 for rugs" do
    setup do
      coord = %Coord.Cartesian{}

      %{
        coord: coord,
        params: Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      }
    end

    test "each side is a line per row from its edge in, drawn in ggplot2's order whatever the " <>
           "order given",
         %{coord: coord, params: params} do
      geom = %{@rug | sides: [:right, :left, :top, :bottom]}
      frame = DataFrame.new(x: [1.0, 3.0], y: [1.0, 2.0], color: ["#FF0000", "#0000FF"])

      assert [bottom, top, left, right] = draw_panel(geom, frame, coord, params)

      assert {bottom.starts, bottom.ends} ===
               {[{0.25, 0.0}, {0.75, 0.0}], [{0.25, 0.25}, {0.75, 0.25}]}

      assert {top.starts, top.ends} === {[{0.25, 1.0}, {0.75, 1.0}], [{0.25, 0.75}, {0.75, 0.75}]}
      assert {left.starts, left.ends} === {[{0.0, 0.25}, {0.0, 0.5}], [{0.25, 0.25}, {0.25, 0.5}]}

      assert {right.starts, right.ends} ===
               {[{1.0, 0.25}, {1.0, 0.5}], [{0.75, 0.25}, {0.75, 0.5}]}

      assert bottom.color === ["#FF0000", "#0000FF"]

      assert {bottom.offsets, bottom.arrows, bottom.line_end, bottom.line_join} ===
               {:none, :none, :butt, :round}

      assert bottom.mitre_limit === 10.0
    end

    test "a length in points leaves each line's inner end at the edge, moved in by that many",
         %{coord: coord, params: params} do
      geom = %{@rug | sides: [:bottom, :top, :left, :right], length: {12.0, :points}}
      frame = DataFrame.new(x: [1.0], y: [2.0])

      assert [bottom, top, left, right] = draw_panel(geom, frame, coord, params)
      assert {bottom.starts, bottom.ends} === {[{0.25, 0.0}], [{0.25, 0.0}]}
      assert {right.starts, right.ends} === {[{1.0, 0.5}], [{1.0, 0.5}]}
      assert bottom.offsets === [{{0.0, 0.0}, {0.0, 12.0}}]
      assert top.offsets === [{{0.0, 0.0}, {0.0, -12.0}}]
      assert left.offsets === [{{0.0, 0.0}, {12.0, 0.0}}]
      assert right.offsets === [{{0.0, 0.0}, {-12.0, 0.0}}]
    end

    # ggplot2 4.0.3's `geom_rug(sides = "trbl", outside = TRUE)` runs its lines from 0npc to
    # -0.03npc and from 1npc to 1.03npc, and with `length = unit(12, "pt")` to -12 points and to
    # 1npc plus 12 points.
    test "drawn outside, each line runs as far out from its edge, a share or a number of points",
         %{coord: coord, params: params} do
      geom = %{@rug | sides: [:bottom, :top, :left, :right], outside: true}
      frame = DataFrame.new(x: [1.0], y: [2.0])

      assert [bottom, top, left, right] = draw_panel(geom, frame, coord, params)
      assert {bottom.starts, bottom.ends} === {[{0.25, 0.0}], [{0.25, -0.25}]}
      assert {top.starts, top.ends} === {[{0.25, 1.0}], [{0.25, 1.25}]}
      assert {left.starts, left.ends} === {[{0.0, 0.5}], [{-0.25, 0.5}]}
      assert {right.starts, right.ends} === {[{1.0, 0.5}], [{1.25, 0.5}]}

      assert [bottom, top, left, right] =
               draw_panel(%{geom | length: {12.0, :points}}, frame, coord, params)

      assert {bottom.starts, bottom.ends} === {[{0.25, 0.0}], [{0.25, 0.0}]}
      assert bottom.offsets === [{{0.0, 0.0}, {0.0, -12.0}}]
      assert top.offsets === [{{0.0, 0.0}, {0.0, 12.0}}]
      assert left.offsets === [{{0.0, 0.0}, {-12.0, 0.0}}]
      assert right.offsets === [{{0.0, 0.0}, {12.0, 0.0}}]
    end

    # As ggplot2 4.0.3's `GeomRug$handle_na()` keeps them: `vctrs::vec_set_union()` of the rows
    # with an `x` and those with a `y`, so the row repeating the first is drawn once, the one
    # missing its `x` comes last along the left, and along one axis every row is drawn.
    test "along both axes, the rows with an x and then those with a y, each repeated row once",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(x: [1.0, nil, 1.0, 2.0, 3.0], y: [1.0, 0.5, 1.0, 2.0, nil])

      assert [bottom, left] = draw_panel(@rug, frame, coord, params)
      assert Enum.map(bottom.starts, fn {x, _y} -> x end) === [0.25, 0.5, 0.75]
      assert Enum.map(left.starts, fn {_x, y} -> y end) === [0.25, 0.5, 0.125]

      assert [bottom_alone] = draw_panel(%{@rug | sides: [:bottom]}, frame, coord, params)
      assert Enum.map(bottom_alone.starts, fn {x, _y} -> x end) === [0.25, 0.25, 0.5, 0.75]
    end

    test "along every side, as along two, each repeated row is drawn once",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 1.0, 2.0], y: [1.0, 1.0, 2.0])
      geom = %{@rug | sides: [:bottom, :top, :left, :right]}

      sides = draw_panel(geom, frame, coord, params)

      assert Enum.map(sides, fn side -> length(side.starts) end) == [2, 2, 2, 2]
    end

    test "rows differing in any column are each drawn along both axes",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 1.0], y: [1.0, 1.0], color: ["#FF0000", "#0000FF"])

      assert [%Segments{color: ["#FF0000", "#0000FF"]}, %Segments{color: ["#FF0000", "#0000FF"]}] =
               draw_panel(@rug, frame, coord, params)
    end

    # As ggplot2 4.0.3 keeps every row for a side whose axis the layer does not map, so the row
    # repeating the first is drawn once along the bottom, and a rug of x alone draws nothing on
    # the left.
    test "an axis the layer does not map draws nothing along its sides, its rows all joining " <>
           "the other's",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 1.0, 2.0, nil])

      assert [%Segments{starts: starts}] = draw_panel(@rug, frame, coord, params)
      assert starts === [{0.25, 0.0}, {0.5, 0.0}]

      assert draw_panel(%{@rug | sides: [:left]}, frame, coord, params) === []
      assert draw_panel(%{@rug | sides: []}, frame, coord, params) === []
    end

    # Golden: ggplot2 4.0.3 and vdiffr 1.0.9 draw no line for a rug whose width or line type is
    # `NA`, and one whose colour is `NA` as a `<line>` with `stroke: none`.
    test "a row missing its place, width or line type, or blank, draws no line, and a colour of " <>
           ":none a line of no stroke",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [1.0, 2.0, 3.0, 4.0, :infinity, :nan],
          color: ["#FF0000", "#FF0000", "#FF0000", "#FF0000", nil, "#FF0000"],
          linewidth: [nil, 0.5, 0.5, 0.5, 0.5, 0.5],
          linetype: [{}, nil, {}, {}, {}, {}]
        )

      blank = DataFrame.put(frame, :linetype, List.duplicate(:none, 6))

      assert [%Segments{starts: starts, color: colors, opacity: opacities}] =
               draw_panel(@rug, frame, coord, params)

      assert starts === [{0.75, 0.0}, {1.0, 0.0}, {1.0, 0.0}]
      assert colors === ["#FF0000", "#FF0000", :none]
      assert opacities === [1.0, 1.0, 0.0]
      assert draw_panel(@rug, blank, coord, params) === []
    end

    test "each run of a side's lines alike in width and line type is one primitive",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [1.0, 2.0, 3.0], linewidth: [0.5, 0.5, 2.0])
      geom = %{@rug | sides: [:bottom, :top]}

      primitives = draw_panel(geom, frame, coord, params)

      assert Enum.map(primitives, fn segments -> length(segments.starts) end) == [2, 1, 2, 1]

      assert Enum.map(primitives, fn segments -> segments.stroke_width end) ===
               [@default_width, @two_millimetres, @default_width, @two_millimetres]
    end

    test "under radial coordinates the lines are straight from the square edges, at each row's " <>
           "place" do
      coord = %Coord.Radial{}
      params = Coord.panel_params(coord, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0, 3.0], y: [2.0, 3.0])
      placed = Coord.transform(coord, frame, params)

      assert [bottom, left] = draw_panel(@rug, frame, coord, params)

      assert Enum.map(bottom.starts, fn {x, _y} -> x end) === DataFrame.pull(placed, :x)
      assert Enum.map(left.ends, fn {x, _y} -> x end) === [0.25, 0.25]
    end

    test "its key is a path's with the rug's line ends" do
      geom = %{@rug | line_end: :round}
      path = %{@path | line_end: :round}

      assert draw_key(geom, %{}) === draw_key(path, %{})
      assert key_size(geom, %{}) === key_size(path, %{})
      assert Geom.default_aesthetics(geom, @element) === Geom.default_aesthetics(path, @element)
    end
  end

  describe "draw_panel/5 for text" do
    setup do
      coord = %Coord.Cartesian{}
      params = Coord.panel_params(coord, {{0.0, 1.0}, [], []}, {{0.0, 1.0}, [], []})
      %{coord: coord, params: params}
    end

    # Each row's place, label and the text the geom draws it in, from a frame of one row per label.
    defp text(frame, %{coord: coord, params: params}, geom \\ %Geom.Text{check_overlap: false}) do
      [%Text{} = text] = draw_panel(geom, frame, coord, params)
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
      ascent = Font.ascent(11.0, "", :plain, false)

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

      assert {width, ascent} ===
               {Font.width("Mazda", points, "", :plain, false),
                Font.ascent(points, "", :plain, false)}
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

    # The test below reads the glyphs a font gives, which the build without Pica, where
    # `Font.glyphs/5` gives none, would type as code that can never run, so it is compiled only
    # where Pica is.
    if Code.ensure_loaded?(Pica) do
      @tag :pica
      test "labels in a family registered with Pica carry its outlines, a run for each drawn",
           context do
        frame =
          DataFrame.new(
            x: [0.2, nil, 0.8],
            y: [0.2, 0.5, 0.8],
            label: ["AV", "b", "A"],
            family: ["Lato", "Lato", "Lato"]
          )

        assert %Text{glyphs: %Giggly.Scene.Glyphs{} = glyphs} = text(frame, context)
        assert glyphs === Font.glyphs(["AV", "A"], 11.0, "Lato", :plain, false)

        assert %Text{glyphs: :none} =
                 text(DataFrame.new(x: [0.2], y: [0.2], label: ["a"]), context)
      end
    end
  end

  describe "the justification text and labels share" do
    # Golden: ggplot2 4.0.3's `compute_just(just, 0.2, 0.9, angle)` at each angle, a label's x
    # (`a`) low and its y (`b`) high, so whichever axis it reads decides the side: past 45 and 135
    # degrees either way, at them, and short of them, a whole turn back and on, and 225, whose half
    # turn is -135.
    test "inward and outward follow compute_just() at the angles where it turns" do
      angles =
        [44.5, 45, 45.5, 134.5, 135, 135.5, -44.5, -45, -45.5, -134.5, -135, -135.5] ++
          [225, -90, 404.5, 405.5, 450]

      justified = fn just ->
        Enum.map(angles, fn angle -> Geom.Text.justification(just, 0.2, 0.9, angle) end)
      end

      assert {justified.(:inward), justified.(:outward)} ===
               {[
                  0.0,
                  0.0,
                  1.0,
                  1.0,
                  0.0,
                  1.0,
                  0.0,
                  0.0,
                  0.0,
                  0.0,
                  0.0,
                  1.0,
                  0.0,
                  0.0,
                  0.0,
                  1.0,
                  1.0
                ],
                [
                  1.0,
                  1.0,
                  0.0,
                  0.0,
                  1.0,
                  0.0,
                  1.0,
                  1.0,
                  1.0,
                  1.0,
                  1.0,
                  0.0,
                  1.0,
                  1.0,
                  1.0,
                  0.0,
                  0.0
                ]}
    end

    # Golden: ggplot2 4.0.3's `compute_just(just, 0.2, 0.1, angle)` either side of -45 and -135
    # degrees and at them, a label's x and y both low, so reading the other axis while reversing
    # the side tells turned backward from not, where a low x and a high y cancel out.
    test "inward and outward follow compute_just() where text turns backward" do
      angles = [-44.5, -45, -45.5, -134.5, -135, -135.5]

      justified = fn just ->
        Enum.map(angles, fn angle -> Geom.Text.justification(just, 0.2, 0.1, angle) end)
      end

      assert {justified.(:inward), justified.(:outward)} ===
               {[0.0, 0.0, 1.0, 1.0, 0.0, 1.0], [1.0, 1.0, 0.0, 0.0, 1.0, 0.0]}
    end

    # Golden: ggplot2 4.0.3's `compute_just("inward", a, a, 0)` at `a` of 0.5 less and plus 0.001,
    # `just_dir()`'s tolerance, and a little further.
    test "a label within the middle's tolerance is centred, and one past it is not" do
      places = [0.5 - 0.001, 0.5 + 0.001, 0.5 - 0.0010001, 0.5 + 0.0010001]

      assert Enum.map(places, fn place ->
               Geom.Text.justification(:inward, place, place, 0)
             end) === [0.5, 0.5, 0.0, 1.0]
    end

    # Golden: ggplot2 4.0.3's `rotate_just(angle, 0.2, 0.9)` at each angle, either side of each
    # quarter turn, a quarter turn back, and a whole turn and two on.
    test "a key's justification is turned at each quarter turn as rotate_just() turns it" do
      angles = [-90, 89.5, 90, 179.5, 180, 269.5, 270, 359.5, 360.5, 449.5, 450, 719]

      turned =
        Enum.map(angles, fn angle ->
          {hjust, vjust} = Geom.Text.turned_justification(angle, 0.2, 0.9)
          {Float.round(hjust, 15), Float.round(vjust, 15)}
        end)

      assert turned === [
               {0.9, 0.8},
               {0.2, 0.9},
               {0.1, 0.2},
               {0.1, 0.2},
               {0.8, 0.1},
               {0.8, 0.1},
               {0.9, 0.8},
               {0.9, 0.8},
               {0.2, 0.9},
               {0.2, 0.9},
               {0.1, 0.2},
               {0.9, 0.8}
             ]
    end

    test "a justification that is neither a float nor one of ggplot2's words is refused" do
      for just <- [:sideways, 1] do
        assert_raise FunctionClauseError, fn ->
          just
          |> untyped()
          |> Geom.Text.justification(0.2, 0.9, 0.0)
        end
      end
    end
  end

  describe "draw_panel/5 and draw_key/3 for labels" do
    # A label's parameters as `Plot.geom_label/3` records ggplot2's defaults.
    @quarter_line {0.25, :lines}
    @label %Geom.Label{
      label_padding: %{
        top: @quarter_line,
        right: @quarter_line,
        bottom: @quarter_line,
        left: @quarter_line
      },
      label_r: {0.15, :lines},
      border_color: :color,
      text_color: :color
    }

    setup do
      coord = %Coord.Cartesian{}
      params = Coord.panel_params(coord, {{0.0, 1.0}, [], []}, {{0.0, 1.0}, [], []})
      %{coord: coord, params: params}
    end

    test "a row missing its x, its y or its label is not drawn, and each other is a box and text",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.2, nil, 0.4, 0.6, 0.8],
          y: [0.2, 0.2, :nan, 0.6, 0.8],
          label: ["a", "b", "c", nil, "e"]
        )

      not_a_number = DataFrame.new(x: [0.2, 0.4], y: [0.2, 0.4], label: [:nan, 2.5])

      assert [
               %Polygons{outlines: [[{0.2, 0.2} | _first]]},
               %Text{labels: ["a"]},
               %Polygons{outlines: [[{0.8, 0.8} | _second]]},
               %Text{labels: ["e"]}
             ] = draw_panel(@label, frame, coord, params)

      assert [%Polygons{}, %Text{labels: ["2.5"]}] =
               draw_panel(@label, not_a_number, coord, params)
    end

    # grid's `gpar()` defaults, which `labelGrob()`'s box takes: round ends and corners, a mitre
    # limit of 10.
    test "a box's ends and corners are grid's, round, at its mitre limit",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [0.5], y: [0.5], label: ["a"])

      assert [%Polygons{line_end: :round, line_join: :round, mitre_limit: 10.0}, %Text{}] =
               draw_panel(@label, frame, coord, params)
    end

    test "a label of no colour keeps its box, unbordered, and its text in no colour",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [0.2, 0.4], y: [0.2, 0.4], label: ["a", "b"], color: [:none, nil])

      drawn = draw_panel(@label, frame, coord, params)

      assert [
               %Polygons{color: [:none], fill: ["#FFFFFF"]},
               %Text{color: [:none], opacity: [+0.0]},
               %Polygons{color: [:none], fill: ["#FFFFFF"]},
               %Text{color: [:none], opacity: [+0.0]}
             ] = drawn
    end

    # A line type a scale maps to blank is held as `nil`, as a column holds one type.
    test "each box is bordered as wide and dashed as its row says, none where blank, missing or 0",
         %{coord: coord, params: params} do
      frame =
        DataFrame.new(
          x: [0.2, 0.4, 0.6, 0.8],
          y: [0.2, 0.4, 0.6, 0.8],
          label: ["a", "b", "c", "d"],
          linewidth: [2.0, 2.0, nil, 0.0],
          linetype: [{4, 4}, nil, {}, {}]
        )

      boxes =
        @label
        |> draw_panel(frame, coord, params)
        |> Enum.filter(fn primitive -> is_struct(primitive, Polygons) end)
        |> Enum.map(fn box -> {box.color, box.stroke_width, rounded(box.dashes)} end)

      assert boxes === [
               {["#000000"], @two_millimetres, [22.76, 22.76]},
               {[:none], @two_millimetres, :none},
               {[:none], +0.0, :none},
               {[:none], +0.0, :none}
             ]
    end

    test "the layer's text and border colours replace the row's, which :color keeps",
         %{coord: coord, params: params} do
      frame = DataFrame.new(x: [0.2], y: [0.2], label: ["a"], color: ["#FF000080"])
      parted = %{@label | border_color: "#0000FF", text_color: :none}

      assert [
               %Polygons{color: ["#FF0000"], color_opacity: [@half_alpha]},
               %Text{color: ["#FF0000"]}
             ] =
               draw_panel(@label, frame, coord, params)

      assert [%Polygons{color: ["#0000FF"], color_opacity: [1.0]}, %Text{color: [:none]}] =
               draw_panel(parted, frame, coord, params)
    end

    # Golden: ggplot2 4.0.3 under vdiffr 1.0.9 draws `geom_label(aes(fill = g), linewidth = 2^-26)`'s
    # labels bordered and its keys `stroke: none`, as `draw_key_label()` takes a width `all.equal()`
    # calls 0, its tolerance `sqrt(.Machine$double.eps)`, as none, and at `linewidth = 1.4902e-8`
    # both bordered.
    test "a key's border is none at a width all.equal() takes as 0, where a label's is drawn" do
      tolerance = :math.pow(2, -26)
      frame = DataFrame.new(x: [0.5], y: [0.5], label: ["a"], linewidth: [tolerance])
      params = Coord.panel_params(@cartesian, {{0.0, 1.0}, [], []}, {{0.0, 1.0}, [], []})

      assert [%Polygons{color: [:none]}, %Text{}] = draw_key(@label, %{linewidth: tolerance})

      assert [%Polygons{color: ["#000000"]}, %Text{}] =
               draw_panel(@label, frame, @cartesian, params)

      assert [%Polygons{color: ["#000000"]}, %Text{}] = draw_key(@label, %{linewidth: 1.4902e-8})
    end

    test "a key of no width or no line type is unbordered, and one of no width drawn 0 wide" do
      assert [%Polygons{color: [:none], stroke_width: +0.0}, %Text{}] =
               draw_key(@label, %{linewidth: nil})

      assert [%Polygons{color: [:none], dashes: :none}, %Text{}] =
               draw_key(@label, %{linetype: nil})
    end

    # ggplot2 4.0.3's `draw_key_label()` justifies its key by `compute_just(hjust)`, a word as a
    # number and inward or outward read against the middle.
    test "a key's justification by a word is its number, inward or outward centred" do
      assert [%Polygons{}, %Text{hjust: [1.0], x: [1.0], y: [+0.0]}] =
               draw_key(@label, %{hjust: :right, vjust: :bottom})

      assert [%Polygons{}, %Text{hjust: [0.5], x: [0.5], y: [0.5]}] =
               draw_key(@label, %{hjust: :inward, vjust: :outward})
    end

    # The test below reads the glyphs a font gives, which the build without Pica, where
    # `Font.glyphs/5` gives none, would type as code that can never run, so it is compiled only
    # where Pica is.
    if Code.ensure_loaded?(Pica) do
      @tag :pica
      test "a label in a family registered with Pica is measured in it and carries its outlines",
           %{coord: coord, params: params} do
        frame = DataFrame.new(x: [0.5], y: [0.5], label: ["AV"], family: ["Lato"])

        assert [%Polygons{}, %Text{size: size, widths: [width], ascent: ascent, glyphs: glyphs}] =
                 draw_panel(@label, frame, coord, params)

        assert {width, ascent} ===
                 {Font.width("AV", size, "Lato", :plain, false),
                  Font.ascent(size, "Lato", :plain, false)}

        assert glyphs === Font.glyphs(["AV"], size, "Lato", :plain, false)

        assert [%Polygons{}, %Text{size: key_font_size, glyphs: key_glyphs}] =
                 draw_key(@label, %{family: "Lato"})

        assert key_glyphs === Font.glyphs(["a"], key_font_size, "Lato", :plain, false)

        # The key's room is its letter's width and the padding, so it is narrower by what Lato's
        # "a" is narrower than the table's.
        {lato_width, _lato_height} = key_size(@label, %{family: "Lato"})
        {table_width, _table_height} = key_size(@label, %{})

        assert_in_delta lato_width - table_width,
                        Font.width("a", key_font_size, "Lato", :plain, false) -
                          Font.width("a", key_font_size, "", :plain, false),
                        1.0e-9
      end
    end
  end

  describe "draw_key/3 for ribbons, areas and rectangles" do
    # Golden: ggplot2 4.0.3's `geom_area(aes(fill = type))` through vdiffr 1.0.9: each key's
    # rectangle `stroke-linecap: butt` with grid's round corners, as `draw_key_polygon()` takes the
    # layer's `linejoin`, where a rectangle's key is mitred.
    test "a ribbon's and an area's key is a rectangle's, its ends and corners the layer's" do
      key = %{fill: "#F8766D"}

      assert [%Rectangles{line_end: :butt, line_join: :round, mitre_limit: 10.0}] =
               draw_key(@ribbon, key)

      assert [%Rectangles{line_end: :square, line_join: :bevel}] =
               draw_key(%{@area | line_end: :square, line_join: :bevel}, key)

      assert [%Rectangles{line_end: :butt, line_join: :mitre}] = draw_key(%Geom.Rect{}, key)
      assert key_size(@area, key) == key_size(%Geom.Rect{}, key)
    end
  end

  describe "draw_panel/5 for smooths" do
    # Past 32 groups a map's keys come in no order, so the groups are drawn in their own.
    test "a panel's smooths are drawn in the order of their groups, past 32 of them" do
      groups = Enum.to_list(1..40)

      frame =
        DataFrame.new(
          x: Enum.flat_map(groups, fn _group -> [0.0, 2.0] end),
          y: Enum.flat_map(groups, fn group -> [group / 10, group / 10] end),
          panel: List.duplicate(1, 80),
          group: Enum.flat_map(groups, fn group -> [group, group] end),
          flipped_aes: List.duplicate(false, 80)
        )

      lines = draw_panel(%{@smooth | se: false}, frame, @cartesian, @params)

      heights = Enum.map(lines, fn %Polylines{lines: [[{_x, y} | _rest]]} -> y end)
      assert {length(heights), heights} == {40, Enum.sort(heights)}
    end
  end

  describe "draw_key/3 for smooths" do
    # Golden: ggplot2 4.0.3's `geom_smooth(aes(colour = drv), method = lm)` through vdiffr 1.0.9:
    # each key's band a rectangle over the whole key, `stroke-width: 0.75; stroke: none`, at the
    # band's alpha, then its line; and `aes(fill = drv)` with `colour = "#FF000080"`, whose keys'
    # lines vdiffr writes with no opacity, where the panel's are 0.50, as `draw_key_smooth()` sets
    # an alpha of 1.
    test "a smooth's key is its band over the whole key, then its line at an alpha of 1" do
      key = %{color: "#FF000080", fill: "#999999", alpha: 0.4}

      assert [
               %Rectangles{
                 xmin: [+0.0],
                 xmax: [1.0],
                 ymin: [+0.0],
                 ymax: [1.0],
                 offsets: :none,
                 fill: ["#999999"],
                 fill_opacity: [0.4],
                 color: [:none],
                 stroke_width: 0.75
               },
               %Segments{color: ["#FF0000"], opacity: [1.0], line_end: :butt}
             ] = draw_key(@smooth, key)

      assert [%Segments{line_end: :round}] =
               draw_key(%{@smooth | se: false, line_end: :round}, key)

      sized = Map.put(key, :linewidth, 1.5)
      assert Geom.key_size(@smooth, sized, false) == Geom.key_size(@path, sized, false)
    end
  end

  describe "draw_key/3" do
    test "a box's key takes the key's line width, line type and alpha, its lines never the alpha" do
      key = %{flipped_aes: false, linewidth: 1.0, linetype: {4, 4}, alpha: 0.5, fill: "#FF0000"}
      millimetre = 2 * @default_width

      assert [whiskers, box, median, staples] = draw_key(@box, key)

      assert {box.fill, box.fill_opacity, box.color_opacity, box.stroke_width} ===
               {["#FF0000"], [0.5], [1.0], millimetre}

      assert Enum.map([whiskers, median, staples], fn line ->
               {line.stroke_width, rounded(line.dashes), Enum.uniq(line.opacity)}
             end) === List.duplicate({millimetre, [11.38, 11.38], [1.0]}, 3)
    end

    test "a box's key leaves out a part whose colour is :none, and every line of no type or width" do
      geom = %{@box | whisker: %{color: :none}}

      assert [%Rectangles{color: ["#333333"]}, %Polylines{}, %Polylines{}] =
               draw_key(geom, %{flipped_aes: false})

      assert [%Rectangles{color: [:none]}] =
               draw_key(@box, %{flipped_aes: false, linetype: nil})

      assert [%Rectangles{color: [:none], stroke_width: +0.0}] =
               draw_key(@box, %{flipped_aes: false, linewidth: nil})
    end

    test "a point's key is the point at the middle of the key, at the key's alpha" do
      assert [%Circles{x: [0.5], y: [0.5], color_opacity: [0.2]}] =
               draw_key(%Geom.Point{}, %{alpha: 0.2})

      assert [%Circles{color_opacity: [1.0]}] =
               draw_key(%Geom.Point{}, %{alpha: nil})
    end

    test "a point's key is in the colour its layer sets, the key's alpha replacing the colour's own" do
      assert [%Circles{color: ["#4682B4"], color_opacity: [0.2]}] =
               draw_key(%Geom.Point{}, %{alpha: 0.2, color: "#4682B480"})

      assert [%Circles{color: ["#4682B4"], color_opacity: [@half_alpha]}] =
               draw_key(%Geom.Point{}, %{alpha: nil, color: "#4682B480"})

      assert draw_key(%Geom.Point{}, %{alpha: 0.2, color: :none}) === []
    end

    # Golden: vdiffr 1.0.9's drawing of ggplot2 4.0.3's `geom_point(shape = 21, size = 3)` filled
    # by a mapped fill, its stroke 2 and NA: each key filled with its break's colour, a circle of
    # radius 4.62 with a 2.83-point outline, and of radius 3.20 with none.
    test "a point's key is drawn in the key's shape, size, stroke and fill" do
      key = %{alpha: nil, fill: "#F8766D", shape: :circle_filled, size: 3.0, stroke: 2.0}

      assert [%Circles{radius: [radius], stroke_width: stroke_width, fill: ["#F8766D"]}] =
               draw_key(%Geom.Point{}, key)

      assert_in_delta radius, 4.62, 0.005
      assert_in_delta stroke_width, 2.83, 0.005

      assert [%Circles{radius: [no_stroke_radius], color: [:none]}] =
               draw_key(%Geom.Point{}, %{key | stroke: :none})

      assert_in_delta no_stroke_radius, 3.20, 0.005
      assert draw_key(%Geom.Point{}, %{shape: :none}) === []
    end

    test "a bar's key is its fill short of the key's edges by its border's width" do
      assert [%Rectangles{} = key] = draw_key(%Geom.Bar{just: 0.5}, %{alpha: 0.55})
      [{{left, bottom}, {right, top}}] = key.offsets

      assert {key.xmin, key.xmax, key.ymin, key.ymax} === {[0.0], [1.0], [0.0], [1.0]}

      assert {Float.round(left, 2), Float.round(bottom, 2), Float.round(right, 2),
              Float.round(top, 2), key.fill_opacity, key.color} ===
               {0.71, 0.71, -0.71, -0.71, [0.55], [:none]}
    end

    # Golden: ggplot2 4.0.3's `geom_col(colour = "black", linewidth = 1.5, linetype = "dotted")`
    # through vdiffr 1.0.9: each key 13.03 points square, bordered 3.20 points wide, dotted
    # `4.27,12.80`; a blank border not drawn.
    test "a bar's key is short of the key by its border's width, which it is drawn at and dashed" do
      key = %{color: "#000000", linewidth: 1.5, linetype: {1, 3}}

      assert [%Rectangles{} = drawn] = draw_key(%Geom.Bar{just: 0.5}, key)
      [{{left, _bottom}, {right, _top}}] = drawn.offsets

      assert {Float.round(17.28 + right - left, 2), Float.round(drawn.stroke_width, 2),
              rounded(drawn.dashes), drawn.color} === {13.03, 3.2, [4.27, 12.8], ["#000000"]}

      assert [%Rectangles{color: [:none], dashes: :none}] =
               draw_key(%Geom.Bar{just: 0.5}, %{key | linetype: :none})
    end

    test "a bar's key is filled and bordered as its layer sets, the key's alpha its fill's alone" do
      key = %{alpha: 0.3, fill: "#0000FF80", color: "#FF000080"}

      assert [%Rectangles{} = drawn] = draw_key(%Geom.Bar{just: 0.5}, key)

      assert {drawn.fill, drawn.fill_opacity, drawn.color, drawn.color_opacity} ===
               {["#0000FF"], [0.3], ["#FF0000"], [@half_alpha]}
    end

    # ggplot2's `draw_key_path()`: a segment from a tenth of the key's width to nine tenths, at
    # mid-height, ended as the layer's lines are, its corners grid's default.
    test "a path's key is a line across the middle of the key, as wide as the layer sets" do
      geom = %Geom.Path{line_end: :square, line_join: :mitre, mitre_limit: 4.0, arrow: :none}

      assert [%Segments{} = key] =
               draw_key(geom, %{alpha: 0.4, linewidth: 2.0})

      assert {key.starts, key.ends, key.opacity, key.stroke_width} ===
               {[{0.1, 0.5}], [{0.9, 0.5}], [0.4], @two_millimetres}

      assert {key.line_end, key.line_join, key.mitre_limit} === {:square, :round, 10.0}
    end

    # Golden: ggplot2 4.0.3's `geom_line(aes(colour = g), linetype = "longdash", linewidth = 1)`
    # through vdiffr 1.0.9: each key dashed `19.92,8.54`, as its line; R's graphics engine draws no
    # key of a blank line.
    test "a path's key is dashed as its line type, and a blank one draws none" do
      assert [%Segments{dashes: dashes}] =
               draw_key(@path, %{linewidth: 1.0, linetype: {7, 3}})

      assert rounded(dashes) === [19.92, 8.54]
      assert draw_key(@path, %{linetype: :none}) === []
    end

    # ggplot2's `GeomSegment` draws its key with `draw_key_path()`, ended as its segments are.
    test "a segment's key and its room are a path's, ended as the segments are" do
      segment = %Geom.Segment{line_end: :square, line_join: :mitre, arrow: :none}
      path = %Geom.Path{line_end: :square, line_join: :round, mitre_limit: 10.0, arrow: :none}
      key = %{alpha: 0.4, linewidth: 2.0}

      assert draw_key(segment, key) === draw_key(path, key)
      assert key_size(segment, key) === key_size(path, key)
    end

    # Golden: ggplot2 4.0.3's legends through vdiffr 1.0.9 for a missing line type or width: a
    # path's key draws no line for either, and a bar's key of a missing width nothing at all, as
    # `draw_key_polygon()`'s rectangle of a missing width has no size; a missing line type leaves a
    # bar's border blank, as `gg_par()` reads `NA` as `"blank"`.
    # ggplot2's `GeomHline` draws its key with `draw_key_path()`, ended as its lines are.
    test "a horizontal line's key and its room are a path's, ended as the lines are" do
      path = %Geom.Path{line_end: :square, line_join: :round, mitre_limit: 10.0, arrow: :none}
      key = %{alpha: 0.4, linewidth: 2.0}

      assert draw_key(%Geom.Hline{line_end: :square}, key) === draw_key(path, key)
      assert key_size(%Geom.Hline{line_end: :square}, key) === key_size(path, key)
    end

    # ggplot2's `draw_key_vline()`: `segmentsGrob(0.5, 0, 0.5, 1)`, the whole key's height.
    test "a vertical line's key runs up the middle of the key, needing a path's room" do
      vline = %Geom.Vline{line_end: :square}
      key = %{alpha: 0.4, linewidth: 2.0}

      assert [%Segments{} = glyph] = draw_key(vline, key)

      assert {glyph.starts, glyph.ends, glyph.opacity, glyph.stroke_width, glyph.line_end} ===
               {[{0.5, 0.0}], [{0.5, 1.0}], [0.4], @two_millimetres, :square}

      assert key_size(vline, key) === key_size(@path, key)
      assert draw_key(vline, %{linetype: :none}) === []
    end

    # ggplot2's `draw_key_abline()`: `segmentsGrob(0, 0, 1, 1)`, corner to corner.
    test "a diagonal line's key runs from the key's bottom left corner to its top right" do
      abline = %Geom.Abline{line_end: :square}
      key = %{alpha: 0.4, linewidth: 2.0}

      assert [%Segments{} = glyph] = draw_key(abline, key)

      assert {glyph.starts, glyph.ends, glyph.opacity, glyph.stroke_width, glyph.line_end} ===
               {[{0.0, 0.0}], [{1.0, 1.0}], [0.4], @two_millimetres, :square}

      assert key_size(abline, key) === key_size(@path, key)
      assert draw_key(abline, %{linetype: :none}) === []
    end

    test "a key of a missing width draws nothing, and of a missing line type no line or border" do
      assert {draw_key(@path, %{linewidth: nil}), draw_key(@path, %{linetype: nil}),
              draw_key(%Geom.Bar{just: 0.5}, %{color: "#000000", linewidth: nil})} ===
               {[], [], []}

      assert [%Rectangles{color: [:none], dashes: :none}] =
               draw_key(%Geom.Bar{just: 0.5}, %{color: "#000000", linetype: nil})
    end

    test "a line's key is a path's, ggplot2's default width where the layer sets none" do
      assert draw_key(@line, %{alpha: nil}) ===
               draw_key(@path, %{alpha: nil})

      assert [%Segments{opacity: [1.0], stroke_width: @default_width}] =
               draw_key(@path, %{alpha: nil})
    end

    test "a text's key is the letter a at the middle of the key, in its colour at its alpha" do
      ascent = Font.ascent(11.0, "", :plain, false)

      assert [%Text{} = key] =
               draw_key(
                 %Geom.Text{check_overlap: false},
                 %{color: "#F8766D", alpha: 0.5}
               )

      assert {key.labels, key.x, key.y, key.hjust, key.offset, key.color, key.opacity, key.size} ===
               {["a"], [0.5], [0.5], [0.5], [{0.0, -0.5 * ascent}], ["#F8766D"], [0.5], 11.0}

      assert draw_key(%Geom.Text{check_overlap: false}, %{color: :none}) ===
               []
    end

    # Golden: ggplot2 4.0.3's key for text set `hjust = 0, vjust = 1`, through vdiffr 1.0.9: the
    # letter's start 1.32 points, a tenth of a line of 11-point text 1.2 lines apart, inside the
    # key's left edge, and its top as far below the key's top, whatever the key's size.
    test "a text's key is placed at the layer's justification, a tenth of a line in from its edges" do
      margin = 0.1 * 11.0 * 1.2

      assert [%Text{} = key] =
               draw_key(
                 %Geom.Text{check_overlap: false},
                 %{hjust: 0.0, vjust: 1.0}
               )

      assert {key.x, key.y, key.hjust, key.offset} ===
               {[0.0], [1.0], [0.0], [{margin, -margin - Font.ascent(11.0, "", :plain, false)}]}
    end

    # Golden: ggplot2 4.0.3's keys for text set `hjust = 0, vjust = 1` and turned 100, 200 and 300
    # degrees, through vdiffr 1.0.9, which Giggly's drawings of the same plots match in every
    # element: `rotate_just()` puts the anchor at (1 - vjust, hjust) of the key, then at
    # (1 - hjust, 1 - vjust), then at (vjust, 1 - hjust).
    test "a turned text's key is placed at its justification turned with it" do
      ascent = Font.ascent(11.0, "", :plain, false)

      places =
        Enum.map([100.0, 200.0, 300.0], fn angle ->
          [%Text{x: [x_place], y: [y_place], offset: [{along, up}]}] =
            draw_key(
              %Geom.Text{check_overlap: false},
              %{hjust: 0.0, vjust: 1.0, angle: angle}
            )

          # The anchor in a key 100 points square: its place, moved by its offset less the
          # ascent `vjust` takes off, turned back from the text's frame.
          radians = angle * :math.pi() / 180
          margin_up = up + ascent
          across = along * :math.cos(radians) - margin_up * :math.sin(radians)
          upward = along * :math.sin(radians) + margin_up * :math.cos(radians)
          {Float.round(x_place * 100 + across, 4), Float.round(y_place * 100 + upward, 4)}
        end)

      margin = 0.1 * 11.0 * 1.2

      assert places === [
               {Float.round(margin, 4), Float.round(margin, 4)},
               {Float.round(100 - margin, 4), Float.round(margin, 4)},
               {Float.round(100 - margin, 4), Float.round(100 - margin, 4)}
             ]
    end

    # Golden: ggplot2 4.0.3's keys for text set `hjust = "inward", vjust = "outward"`, unturned and
    # turned 90 degrees, through vdiffr 1.0.9, each drawn where the key set `hjust = 0.5, vjust =
    # 0.5` is: `draw_key_text()` asks `compute_just()` against the key's middle, along the text or,
    # turned, across it, and a label at the middle is centred.
    test "a text's key justified inward or outward is centred, turned or not" do
      for angle <- [0.0, 90.0] do
        assert draw_key(
                 %Geom.Text{check_overlap: false},
                 %{hjust: :inward, vjust: :outward, angle: angle}
               ) ===
                 draw_key(
                   %Geom.Text{check_overlap: false},
                   %{hjust: 0.5, vjust: 0.5, angle: angle}
                 )
      end
    end

    # The test below reads the glyphs a font gives, which the build without Pica, where
    # `Font.glyphs/5` gives none, would type as code that can never run, so it is compiled only
    # where Pica is.
    if Code.ensure_loaded?(Pica) do
      @tag :pica
      test "a text's key in a family registered with Pica carries the outline of its letter" do
        [%Text{size: size, glyphs: glyphs}] =
          draw_key(%Geom.Text{check_overlap: false}, %{family: "Lato"})

        assert %Giggly.Scene.Glyphs{} = glyphs
        assert glyphs === Font.glyphs(["a"], size, "Lato", :plain, false)
      end
    end

    test "a path's key is in the colour its layer sets, and a colour of :none draws none" do
      assert [%Segments{color: ["#FF0000"], opacity: [@half_alpha]}] =
               draw_key(@path, %{alpha: nil, color: "#FF000080"})

      assert draw_key(@path, %{alpha: 0.4, color: :none}) === []
    end
  end

  # The room each geom's key glyph needs, in points, checked against vdiffr 1.0.9's drawings of
  # ggplot2 4.0.3's legends (the keys of test/golden/point_key_big.svg, bar_key_big.svg,
  # line_key_big.svg and text_key_big.svg) and against `draw_key_text()`'s own `width` and
  # `height` on vdiffr's device.
  describe "key_size/3" do
    test "a point's key needs its size, in millimetres, either way; a missing size none" do
      assert rounded_size(key_size(%Geom.Point{}, %{size: 8.0})) === {22.68, 22.68}
      assert rounded_size(key_size(%Geom.Point{}, %{})) === {4.25, 4.25}
      assert key_size(%Geom.Point{}, %{size: nil}) === {0.0, 0.0}
    end

    test "a path's or line's key needs its line's width; a bar's twice its border's" do
      assert rounded_size(key_size(@path, %{linewidth: 8.0})) === {22.68, 22.68}
      assert rounded_size(key_size(@line, %{})) === {1.42, 1.42}

      assert rounded_size(key_size(%Geom.Bar{just: 0.5}, %{linewidth: 4.0})) ===
               {22.68, 22.68}

      assert rounded_size(key_size(%Geom.Rect{}, %{})) === {2.83, 2.83}

      assert {key_size(@path, %{linewidth: nil}),
              key_size(%Geom.Bar{just: 0.5}, %{linewidth: nil})} ===
               {{0.0, 0.0}, {0.0, 0.0}}
    end

    # R's own figures, `attr(draw_key_text(...), "width")` and `"height"` in big points.
    test "a text's key needs its letter's box, turned with it, its descent and a margin each side" do
      text = %Geom.Text{check_overlap: false}

      assert Enum.map([0.0, 30.0, 90.0, 135.0], fn angle ->
               rounded_size(key_size(text, %{size: 12.0, angle: angle}))
             end) === [{21.87, 33.47}, {34.62, 38.86}, {33.47, 21.87}, {37.94, 37.94}]

      assert rounded_size(key_size(text, %{size: 3.88})) === {9.02, 12.77}
    end

    test "a line range's key needs a path's room; a point range's its size and line width added" do
      assert rounded_size(key_size(@linerange, %{linewidth: 8.0})) === {22.68, 22.68}

      assert rounded_size(key_size(@pointrange, %{size: 4.0, linewidth: 4.0})) ===
               {22.68, 22.68}

      assert rounded_size(key_size(@pointrange, %{})) === {2.83, 2.83}
      assert key_size(@pointrange, %{size: nil, linewidth: nil}) === {0.0, 0.0}
    end

    test "an error bar's and a crossbar's key need a path's room" do
      assert rounded_size(key_size(@errorbar, %{linewidth: 8.0})) === {22.68, 22.68}
      assert rounded_size(key_size(@crossbar, %{linewidth: 8.0})) === {22.68, 22.68}
    end

    test "a box's key needs its size and line width added, a missing one counting 0" do
      assert rounded_size(key_size(@box, %{})) === {5.67, 5.67}
      assert rounded_size(key_size(@box, %{size: 4.0, linewidth: nil})) === {11.34, 11.34}
      assert key_size(@box, %{size: nil, linewidth: nil}) === {0.0, 0.0}
    end
  end

  # Golden throughout: svglite's drawing of ggplot2 4.0.3's geoms with an alpha of -Inf, -0.5, 1.5
  # and Inf through an identity scale, R 4.6.1 (`inc4/step7/geoms.txt`, `geoms2.R`, `own.txt`): an
  # alpha below 0 draws nothing and one above 1 is opaque everywhere; an infinite one draws
  # nothing in most geoms, but is opaque, whatever the colour's own alpha, in a band's fill, a box
  # plot's box and outliers and the reference lines.
  describe "draw_panel/5 for an alpha off 0 to 1, or infinite" do
    @off_range [-0.5, 1.5, :infinity, :neg_infinity]

    test "a point's alpha is held between 0 and 1, and an infinite one draws nothing" do
      frame = DataFrame.new(x: [0.5, 1.0, 1.5, 2.0], y: [1.0, 1.0, 1.0, 1.0], alpha: @off_range)

      assert [
               %Circles{
                 color_opacity: [+0.0, 1.0, +0.0, +0.0],
                 fill_opacity: [+0.0, 1.0, +0.0, +0.0]
               }
             ] =
               draw_panel(%Geom.Point{}, frame, @cartesian, @params)
    end

    test "an alpha given as an integer is an opacity as a float" do
      frame = DataFrame.new(x: [0.5, 1.0], y: [1.0, 1.0], alpha: [1, 0])

      assert [%Circles{color_opacity: opacities}] =
               draw_panel(%Geom.Point{}, frame, @cartesian, @params)

      assert opacities === [1.0, +0.0]
    end

    test "a rectangle's fill draws nothing at an infinite alpha" do
      frame =
        DataFrame.new(
          xmin: [0.0, 0.5, 1.0, 1.5],
          xmax: [0.5, 1.0, 1.5, 2.0],
          ymin: [0.0, 0.0, 0.0, 0.0],
          ymax: [1.0, 1.0, 1.0, 1.0],
          alpha: @off_range
        )

      assert [%Rectangles{fill_opacity: [+0.0, 1.0, +0.0, +0.0]}] =
               draw_panel(%Geom.Rect{}, frame, @cartesian, @params)
    end

    test "a band's fill is opaque at an infinite alpha, held between 0 and 1 otherwise" do
      fills =
        Enum.map(@off_range, fn alpha ->
          rows = DataFrame.put(band([0.0, 1.0], [0.0, 0.0], [1.0, 1.0]), :alpha, [alpha, alpha])

          [%Polygons{fill_opacity: [opacity]} | _lines] =
            draw_panel(@ribbon, rows, @cartesian, @params)

          opacity
        end)

      assert fills === [+0.0, 1.0, 1.0, 1.0]
    end

    test "a reference line is opaque at an infinite alpha, colour's own alpha or not" do
      look = [
        group: [-1, -1, -1, -1],
        color: ["#FF000080", "#FF000080", "#FF000080", "#FF000080"],
        alpha: @off_range
      ]

      horizontal = DataFrame.new([yintercept: [1.0, 2.0, 3.0, 3.5]] ++ look)
      vertical = DataFrame.new([xintercept: [0.5, 1.0, 1.5, 1.75]] ++ look)

      diagonal =
        DataFrame.new([intercept: [0.0, 0.5, 1.0, 1.5], slope: [1.0, 1.0, 1.0, 1.0]] ++ look)

      opacities =
        Enum.map([{@hline, horizontal}, {@vline, vertical}, {@abline, diagonal}], fn {geom, frame} ->
          [%Segments{opacity: opacity}] = draw_panel(geom, frame, @cartesian, @params)
          opacity
        end)

      assert opacities === List.duplicate([+0.0, 1.0, 1.0, 1.0], 3)
    end

    test "a box plot's box and outliers are opaque at an infinite alpha" do
      {coord, params} = box_params()
      frame = box_rows(alpha: [:neg_infinity], fill: ["#FF000080"])

      assert [
               %Circles{color_opacity: [1.0], fill_opacity: [1.0]},
               %Segments{},
               %Polygons{fill_opacity: [1.0]},
               %Segments{}
             ] = draw_panel(@box, frame, coord, params)
    end
  end

  defp rounded_size({width, height}), do: {Float.round(width, 2), Float.round(height, 2)}

  # `value` with its type hidden from the compiler, so a test can hand a function a value its
  # guards refuse.
  @spec untyped(term()) :: term()
  defp untyped(value), do: value
end
