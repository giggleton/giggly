defmodule Giggly.SVGTest do
  use ExUnit.Case, async: true

  alias Giggly.{Scene, SVG}
  alias Giggly.Scene.{Cell, Circles, Polygons, Polylines, Rect, Rectangles, Segments, Text}

  # Golden throughout: grid's own drawing of the same layout or marks, written by vdiffr 1.0.9's
  # svglite (R 4.6.1), sizes in grid's "bigpts", which are points. It moves only with how grid lays
  # out a table, anchors text or writes these elements.

  describe "draw/3, laying out the table" do
    test "shares split what the sizes in points leave by their weights" do
      drawn = draw(gray_cells([10, {:rest, 1}, {:rest, 3}, 20], [30, {:rest, 2}], false))

      # R writes the top edge as its rounding error, -0.0000000000000071.
      assert rects(drawn) === [
               {"0.00", "0.00", "10.00", "30.00"},
               {"10.00", "0.00", "172.50", "30.00"},
               {"182.50", "0.00", "517.50", "30.00"},
               {"700.00", "0.00", "20.00", "30.00"},
               {"0.00", "30.00", "10.00", "546.00"},
               {"10.00", "30.00", "172.50", "546.00"},
               {"182.50", "30.00", "517.50", "546.00"},
               {"700.00", "30.00", "20.00", "546.00"}
             ]
    end

    test "kept proportions give every share the scale of the way that runs out first, centred" do
      wide = draw(gray_cells([10, {:rest, 1}, {:rest, 3}, 20], [30, {:rest, 2}], true))

      assert rects(wide) === [
               {"0.00", "100.50", "10.00", "30.00"},
               {"10.00", "100.50", "172.50", "30.00"},
               {"182.50", "100.50", "517.50", "30.00"},
               {"700.00", "100.50", "20.00", "30.00"},
               {"0.00", "130.50", "10.00", "345.00"},
               {"10.00", "130.50", "172.50", "345.00"},
               {"182.50", "130.50", "517.50", "345.00"},
               {"700.00", "130.50", "20.00", "345.00"}
             ]

      # R writes the top edge as its rounding error, -0.0000000000000071.
      tall = draw(gray_cells([10, {:rest, 1}, 20], [30, {:rest, 2}], true))

      assert rects(tall) === [
               {"208.50", "0.00", "10.00", "30.00"},
               {"218.50", "0.00", "273.00", "30.00"},
               {"491.50", "0.00", "20.00", "30.00"},
               {"208.50", "30.00", "10.00", "546.00"},
               {"218.50", "30.00", "273.00", "546.00"},
               {"491.50", "30.00", "20.00", "546.00"}
             ]
    end
  end

  describe "draw/3, writing primitives" do
    test "text is anchored at the start, middle or end nearest its hjust, and moved the rest of its width" do
      text = fn x_place, hjust, angle ->
        %Text{
          x: [x_place],
          y: [100 / 576],
          labels: ["Hello"],
          widths: [20.05],
          size: 8.8,
          color: "#000000",
          angle: angle,
          hjust: hjust,
          offset: {0.0, 0.0}
        }
      end

      drawn =
        draw(
          whole([
            text.(100 / 720, 0.3, 0),
            text.(200 / 720, 0.8, 0),
            text.(100 / 720, 0.2, 0),
            text.(300 / 720, 0.3, 90)
          ])
        )

      assert texts(drawn) === [
               "<text x='104.01' y='476.00' text-anchor='middle'",
               "<text x='204.01' y='476.00' text-anchor='end'",
               "<text x='95.99' y='476.00'",
               "<text transform='translate(300.00,471.99) rotate(-90)' text-anchor='middle'"
             ]
    end

    # Not R's: the offset is the scene's own, along the text's baseline and toward its top.
    test "a text's anchor is moved along its baseline and toward its top by its offset" do
      text = fn angle ->
        %Text{
          x: [100 / 720],
          y: [100 / 576],
          labels: ["Hello"],
          widths: [20.05],
          size: 8.8,
          color: "#000000",
          angle: angle,
          hjust: 0.5,
          offset: {3.0, -4.0}
        }
      end

      assert texts(draw(whole([text.(0), text.(90)]))) === [
               "<text x='103.00' y='480.00' text-anchor='middle'",
               "<text transform='translate(104.00,473.00) rotate(-90)' text-anchor='middle'"
             ]
    end

    test "a polyline's points are moved by their offsets in points" do
      line = %Polylines{
        lines: [[{0.5, 0.25}, {0.5, 0.25}]],
        offsets: [[{0.0, 0.0}, {3.0, -4.0}]],
        stroke_width: 0.75,
        color: "#000000",
        opacity: [1.0],
        line_end: :butt,
        line_join: :round,
        mitre_limit: 10.0
      }

      assert draw(whole([line])) =~ "<polyline points='360.00,432.00 363.00,436.00 '"
    end

    test "a rectangle is hung from its top left corner, its look as ggplot2's GeomRect draws it" do
      rectangles = %Rectangles{
        xmin: [0.1],
        xmax: [0.3],
        ymin: [0.5],
        ymax: [0.8],
        fill: "#595959",
        fill_opacity: [1.0],
        color: :none,
        color_opacity: 0.0,
        # A 0.5 mm line, as grid draws it in points.
        stroke_width: 0.5 * 72.27 / 25.4 * 72 / 96
      }

      drawn = draw(whole([rectangles]))

      assert String.ends_with?(
               drawn,
               "<rect x='72.00' y='115.20' width='144.00' height='172.80' " <>
                 "style='stroke-width: 1.07; stroke: none; stroke-linecap: butt; " <>
                 "stroke-linejoin: miter; fill: #595959;' />\n</svg>\n"
             )
    end

    test "a circle's outline and fill carry its opacity, as svglite writes a colour's alpha" do
      circles = %Circles{
        x: [0.25, 0.75],
        y: [0.5, 0.5],
        radius: 1.95,
        stroke_width: 0.71,
        color: "#000000",
        opacity: [1 / 3, 1.0]
      }

      assert circles(draw(whole([circles]))) === [
               "style='stroke-width: 0.71; stroke: #000000; stroke-opacity: 0.33; " <>
                 "fill: #000000; fill-opacity: 0.33;'",
               "style='stroke-width: 0.71; stroke: #000000; fill: #000000;'"
             ]
    end

    test "a placed rectangle's fill carries its opacity, and its border none" do
      rectangles = %Rectangles{
        xmin: [0.1],
        xmax: [0.3],
        ymin: [0.5],
        ymax: [0.8],
        fill: "#595959",
        fill_opacity: [0.5],
        color: :none,
        color_opacity: 0.0,
        stroke_width: 1.07
      }

      assert draw(whole([rectangles])) =~
               "stroke-linejoin: miter; fill: #595959; fill-opacity: 0.50;' />"
    end

    # R keeps a colour's alpha as a byte, the opacity times 255 rounded half to even, and svglite
    # writes the byte over 255 with as many decimals as reach its first significant digit and one
    # more. 6.5 rounds to 6, 0.024, where 7 would be 0.027; 1.5 to 2, 0.0078, where 1 would be
    # 0.0039; 3.5 to 4, 0.016; 0.998 is byte 254, written 1.00; 0.999 is byte 255, opaque, and
    # written not at all; byte 243 is 0.95, where dividing by 254 would give 0.96. Golden: svglite's
    # styles for these alphas, from R 4.6.1, ggplot2 4.0.3 and vdiffr 1.0.9.
    test "an opacity is written as the byte R rounds it to, over 255, as svglite writes a number" do
      opacities = [6.5 / 255, 1.5 / 255, 3.5 / 255, 0.998, 0.999, 243 / 255]

      circles = %Circles{
        x: Enum.map(1..6, fn index -> index / 7 end),
        y: List.duplicate(0.5, 6),
        radius: 1.95,
        stroke_width: 0.71,
        color: "#000000",
        opacity: opacities
      }

      assert circles(draw(whole([circles]))) === [
               "style='stroke-width: 0.71; stroke: #000000; stroke-opacity: 0.024; " <>
                 "fill: #000000; fill-opacity: 0.024;'",
               "style='stroke-width: 0.71; stroke: #000000; stroke-opacity: 0.0078; " <>
                 "fill: #000000; fill-opacity: 0.0078;'",
               "style='stroke-width: 0.71; stroke: #000000; stroke-opacity: 0.016; " <>
                 "fill: #000000; fill-opacity: 0.016;'",
               "style='stroke-width: 0.71; stroke: #000000; stroke-opacity: 1.00; " <>
                 "fill: #000000; fill-opacity: 1.00;'",
               "style='stroke-width: 0.71; stroke: #000000; fill: #000000;'",
               "style='stroke-width: 0.71; stroke: #000000; stroke-opacity: 0.95; " <>
                 "fill: #000000; fill-opacity: 0.95;'"
             ]
    end

    # Golden: svglite's drawing of ggplot2 4.0.3's points and columns at `alpha = 0`, in vdiffr 1.0.9,
    # which writes no fill and leaves it to its stylesheet's `fill: none`; without that stylesheet
    # SVG fills a shape black, so the fill is written `none`.
    test "a wholly transparent colour is a stroke of none and a fill of none" do
      circles = %Circles{
        x: [0.5],
        y: [0.5],
        radius: 1.95,
        stroke_width: 0.71,
        color: "#000000",
        opacity: [0.0]
      }

      rectangles = %Rectangles{
        xmin: [0.1],
        xmax: [0.3],
        ymin: [0.5],
        ymax: [0.8],
        fill: "#595959",
        fill_opacity: [0.0],
        color: :none,
        color_opacity: 0.0,
        stroke_width: 1.07
      }

      drawn = draw(whole([circles, rectangles]))

      assert circles(drawn) === ["style='stroke-width: 0.71; stroke: none; fill: none;'"]
      assert drawn =~ "stroke-linecap: butt; stroke-linejoin: miter; fill: none;' />"
    end

    # Golden: svglite's drawing of ggplot2 4.0.3's `geom_col(fill = "#0000FF80", colour =
    # "#FF000080", alpha = 0.3)`, in vdiffr 1.0.9: the border its colour's own alpha, the fill the
    # layer's.
    test "a placed rectangle's border carries its own opacity, after its colour" do
      rectangles = %Rectangles{
        xmin: [0.1],
        xmax: [0.3],
        ymin: [0.5],
        ymax: [0.8],
        fill: "#0000FF",
        fill_opacity: [0.3],
        color: "#FF0000",
        color_opacity: 128 / 255,
        stroke_width: 1.07
      }

      assert draw(whole([rectangles])) =~
               "style='stroke-width: 1.07; stroke: #FF0000; stroke-opacity: 0.50; " <>
                 "stroke-linecap: butt; stroke-linejoin: miter; fill: #0000FF; " <>
                 "fill-opacity: 0.30;' />"
    end

    # Golden: svglite's drawing of ggplot2 4.0.3's `geom_col(fill = NA, colour = NA)`, in vdiffr
    # 1.0.9: a border of no colour is `none`, whatever opacity the scene gives it.
    test "a placed rectangle of no border colour is stroked none, whatever its opacity" do
      rectangles = %Rectangles{
        xmin: [0.1],
        xmax: [0.3],
        ymin: [0.5],
        ymax: [0.8],
        fill: "#595959",
        fill_opacity: [1.0],
        color: :none,
        color_opacity: 1.0,
        stroke_width: 1.07
      }

      assert draw(whole([rectangles])) =~
               "style='stroke-width: 1.07; stroke: none; stroke-linecap: butt; " <>
                 "stroke-linejoin: miter; fill: #595959;' />"
    end

    # Golden: svglite's drawing of ggplot2 4.0.3's `geom_col(fill = NA, colour = "red")`, in vdiffr
    # 1.0.9, which leaves the fill to its stylesheet.
    test "a placed rectangle of no fill is filled none, whatever its opacity" do
      rectangles = %Rectangles{
        xmin: [0.1],
        xmax: [0.3],
        ymin: [0.5],
        ymax: [0.8],
        fill: :none,
        fill_opacity: [1.0],
        color: "#FF0000",
        color_opacity: 1.0,
        stroke_width: 1.07
      }

      assert draw(whole([rectangles])) =~
               "style='stroke-width: 1.07; stroke: #FF0000; stroke-linecap: butt; " <>
                 "stroke-linejoin: miter; fill: none;' />"
    end

    # svglite declares these in its stylesheet; a stylesheet inlined in a page styles the whole page,
    # so the root declares them, and every element inherits them.
    test "the root declares svglite's lines: round ends, round corners and a mitre limit of 10" do
      assert draw(whole([])) =~
               ~r/^<svg [^>]* stroke-linecap='round' stroke-linejoin='round' stroke-miterlimit='10.00'>\n/
    end

    test "a polyline writes its ends, corners and mitre limit where they differ from the root's" do
      style = fn line_end, line_join, mitre_limit ->
        polyline = %Polylines{
          lines: [[{0.1, 0.1}, {0.2, 0.2}]],
          offsets: :none,
          stroke_width: 21.34,
          color: "#000000",
          opacity: [1.0],
          line_end: line_end,
          line_join: line_join,
          mitre_limit: mitre_limit
        }

        [style] =
          Regex.run(~r/<polyline [^>]*?style='([^']*)'/, draw(whole([polyline])),
            capture: :all_but_first
          )

        style
      end

      assert [
               style.(:butt, :round, 10.0),
               style.(:round, :round, 10.0),
               style.(:square, :bevel, 10.0),
               style.(:butt, :mitre, 10.0),
               style.(:butt, :mitre, 4.0),
               style.(:butt, :mitre, 10.5)
             ] === [
               "stroke-width: 21.34; stroke: #000000; stroke-linecap: butt; fill: none;",
               "stroke-width: 21.34; stroke: #000000; fill: none;",
               "stroke-width: 21.34; stroke: #000000; stroke-linecap: square; " <>
                 "stroke-linejoin: bevel; fill: none;",
               "stroke-width: 21.34; stroke: #000000; stroke-linecap: butt; " <>
                 "stroke-linejoin: miter; fill: none;",
               "stroke-width: 21.34; stroke: #000000; stroke-linecap: butt; " <>
                 "stroke-linejoin: miter; stroke-miterlimit: 4.00; fill: none;",
               "stroke-width: 21.34; stroke: #000000; stroke-linecap: butt; " <>
                 "stroke-linejoin: miter; stroke-miterlimit: 10.50; fill: none;"
             ]
    end

    test "each polyline's stroke carries its own opacity" do
      polylines = %Polylines{
        lines: [[{0.1, 0.1}, {0.2, 0.2}], [{0.3, 0.3}, {0.4, 0.4}]],
        offsets: :none,
        stroke_width: 1.07,
        color: "#000000",
        opacity: [0.1, 1.0],
        line_end: :butt,
        line_join: :round,
        mitre_limit: 10.0
      }

      assert Regex.scan(~r/<polyline [^>]*?style='([^']*)'/, draw(whole([polylines])),
               capture: :all_but_first
             ) === [
               [
                 "stroke-width: 1.07; stroke: #000000; stroke-opacity: 0.10; stroke-linecap: butt; fill: none;"
               ],
               ["stroke-width: 1.07; stroke: #000000; stroke-linecap: butt; fill: none;"]
             ]
    end

    test "a segment is a line from its start to its end, its stroke carrying its opacity" do
      segments = %Segments{
        starts: [{0.1, 0.5}],
        ends: [{0.3, 0.75}],
        stroke_width: 1.07,
        color: "#000000",
        opacity: [0.1],
        line_end: :butt,
        line_join: :round,
        mitre_limit: 10.0
      }

      drawn = draw(whole([segments]))

      assert String.ends_with?(
               drawn,
               "<line x1='72.00' y1='288.00' x2='216.00' y2='144.00' " <>
                 "style='stroke-width: 1.07; stroke: #000000; stroke-opacity: 0.10; " <>
                 "stroke-linecap: butt;' />\n</svg>\n"
             )
    end

    test "a polygon is filled round its outline, its border as svglite writes it" do
      polygon = %Polygons{
        outlines: [[{0.1, 0.1}, {0.2, 0.1}, {0.2, 0.3}]],
        fill: "#EBEBEB",
        color: :none,
        stroke_width: 0.75
      }

      drawn = draw(whole([polygon]))

      assert String.ends_with?(
               drawn,
               "<polygon points='72.00,518.40 144.00,518.40 144.00,403.20 ' " <>
                 "style='stroke-width: 0.75; stroke: none; fill: #EBEBEB;' />\n</svg>\n"
             )
    end
  end

  # A grey rectangle in every cell of a table with these widths and heights, a bare number a size
  # in points.
  defp gray_cells(widths, heights, keep_proportions) do
    cells =
      for row <- 1..length(heights), column <- 1..length(widths) do
        %Cell{
          rows: row..row,
          columns: column..column,
          clip: :off,
          hang: :none,
          primitives: [%Rect{fill: "#EBEBEB", color: :none, stroke_width: 0.75}]
        }
      end

    %Scene{
      widths: Enum.map(widths, &size/1),
      heights: Enum.map(heights, &size/1),
      keep_proportions: keep_proportions,
      cells: cells
    }
  end

  # One cell filling the drawing, holding `primitives`.
  defp whole(primitives) do
    %Scene{
      widths: [{:rest, 1}],
      heights: [{:rest, 1}],
      keep_proportions: false,
      cells: [%Cell{rows: 1..1, columns: 1..1, clip: :off, hang: :none, primitives: primitives}]
    }
  end

  defp size({:rest, weight}), do: {:rest, weight}
  defp size(points), do: {:points, points}

  # Drawn at vdiffr's size, 720 by 576 points.
  defp draw(scene) do
    scene
    |> SVG.draw(720, 576)
    |> IO.iodata_to_binary()
  end

  defp rects(svg) do
    ~r/<rect x='([^']*)' y='([^']*)' width='([^']*)' height='([^']*)'/
    |> Regex.scan(svg, capture: :all_but_first)
    |> Enum.map(fn [x, y, width, height] -> {x, y, width, height} end)
  end

  # Each circle's style, which says how it is drawn.
  defp circles(svg) do
    ~r/<circle [^>]*?(style='[^']*')/
    |> Regex.scan(svg, capture: :all_but_first)
    |> Enum.map(fn [style] -> style end)
  end

  # Each text element up to its style, which says where it is and how it is anchored.
  defp texts(svg) do
    ~r/<text[^>]*?(?= style=)/
    |> Regex.scan(svg)
    |> Enum.map(fn [element] -> element end)
  end

  # Golden: grid's drawing, through vdiffr 1.0.9's svglite (R 4.6.1), of a gtable 10 and 20 points
  # wide and 30 tall nested in the second column of one 100 points and a null wide, filling the
  # page: grid centres a table of fixed sizes in its cell both ways. It moves with how a nested
  # table is laid out.
  describe "draw/3, a scene nested in a cell" do
    test "a table of sizes in points is laid out in its cell and centred both ways" do
      nested = %Scene{
        widths: [{:points, 10}, {:points, 20}],
        heights: [{:points, 30}],
        keep_proportions: false,
        cells: [
          %Cell{
            rows: 1..1,
            columns: 1..2,
            clip: :off,
            hang: :none,
            primitives: [%Rect{fill: "#EBEBEB", color: :none, stroke_width: 0.75}]
          },
          %Cell{
            rows: 1..1,
            columns: 2..2,
            clip: :off,
            hang: :none,
            primitives: [%Rect{fill: "#FFFFFF", color: :none, stroke_width: 0.75}]
          }
        ]
      }

      scene = %Scene{
        widths: [{:points, 100}, {:rest, 1}],
        heights: [{:rest, 1}],
        keep_proportions: false,
        cells: [%Cell{rows: 1..1, columns: 2..2, clip: :off, hang: :none, primitives: [nested]}]
      }

      assert rects(draw(scene)) === [
               {"395.00", "273.00", "30.00", "30.00"},
               {"405.00", "273.00", "20.00", "30.00"}
             ]
    end

    test "a nested table's shares split what its sizes in points leave of the cell" do
      nested = %Scene{
        widths: [{:points, 10}, {:rest, 1}],
        heights: [{:rest, 1}],
        keep_proportions: false,
        cells: [
          %Cell{
            rows: 1..1,
            columns: 2..2,
            clip: :off,
            hang: :none,
            primitives: [%Rect{fill: "#FFFFFF", color: :none, stroke_width: 0.75}]
          }
        ]
      }

      assert rects(draw(whole([nested]))) === [{"10.00", "0.00", "710.00", "576.00"}]
    end
  end
end
