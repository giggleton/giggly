defmodule Giggly.GeomTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, DataFrame, Font, Geom, Theme}
  alias Giggly.Scene.{Circles, Polygons, Polylines, Rectangles, Segments, Text}

  @path %Geom.Path{line_end: :butt, line_join: :round, mitre_limit: 10.0}
  @line %Geom.Line{orientation: :x, line_end: :butt, line_join: :round, mitre_limit: 10.0}

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

    Geom.draw_panel(geom, filled, coord, panel_params)
  end

  # A key's glyph and the room it needs, `key` laid over the geom's defaults, as rendering hands a
  # geom a key.
  defp draw_key(geom, key), do: Geom.draw_key(geom, Map.merge(key_defaults(geom), key))
  defp key_size(geom, key), do: Geom.key_size(geom, Map.merge(key_defaults(geom), key))

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

  describe "draw_panel/4 for points" do
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

  describe "draw_panel/4 for box plots" do
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

  describe "draw_panel/4 for ribbons and areas" do
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

  describe "draw_panel/4 for paths, in a line type" do
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
      geom = %Geom.Path{line_end: :round, line_join: :mitre, mitre_limit: 4.0}

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

  describe "draw_panel/4 for text" do
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

  describe "draw_key/2 for ribbons, areas and rectangles" do
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

  describe "draw_key/2" do
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
      geom = %Geom.Path{line_end: :square, line_join: :mitre, mitre_limit: 4.0}

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

    # Golden: ggplot2 4.0.3's legends through vdiffr 1.0.9 for a missing line type or width: a
    # path's key draws no line for either, and a bar's key of a missing width nothing at all, as
    # `draw_key_polygon()`'s rectangle of a missing width has no size; a missing line type leaves a
    # bar's border blank, as `gg_par()` reads `NA` as `"blank"`.
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
      ascent = Font.ascent(11.0)

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
               {[0.0], [1.0], [0.0], [{margin, -margin - Font.ascent(11.0)}]}
    end

    # Golden: ggplot2 4.0.3's keys for text set `hjust = 0, vjust = 1` and turned 100, 200 and 300
    # degrees, through vdiffr 1.0.9, which Giggly's drawings of the same plots match in every
    # element: `rotate_just()` puts the anchor at (1 - vjust, hjust) of the key, then at
    # (1 - hjust, 1 - vjust), then at (vjust, 1 - hjust).
    test "a turned text's key is placed at its justification turned with it" do
      ascent = Font.ascent(11.0)

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
  describe "key_size/2" do
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

    test "a box's key needs its size and line width added, a missing one counting 0" do
      assert rounded_size(key_size(@box, %{})) === {5.67, 5.67}
      assert rounded_size(key_size(@box, %{size: 4.0, linewidth: nil})) === {11.34, 11.34}
      assert key_size(@box, %{size: nil, linewidth: nil}) === {0.0, 0.0}
    end
  end

  defp rounded_size({width, height}), do: {Float.round(width, 2), Float.round(height, 2)}
end
