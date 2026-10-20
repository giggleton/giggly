defmodule Giggly.SVGTest do
  use ExUnit.Case, async: true

  alias Giggly.{Font, Scene, SVG}

  alias Giggly.Scene.{
    Cell,
    Circles,
    Gradient,
    Polygons,
    Polylines,
    Rect,
    Rectangles,
    Segments,
    Text
  }

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
          family: "",
          color: ["#000000"],
          opacity: [1.0],
          angle: angle,
          hjust: [hjust],
          offset: [{0.0, 0.0}],
          check_overlap: false,
          ascent: 6.3
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
          family: "",
          color: ["#000000"],
          opacity: [1.0],
          angle: angle,
          hjust: [0.5],
          offset: [{3.0, -4.0}],
          check_overlap: false,
          ascent: 6.3
        }
      end

      assert texts(draw(whole([text.(0), text.(90)]))) === [
               "<text x='103.00' y='480.00' text-anchor='middle'",
               "<text transform='translate(104.00,473.00) rotate(-90)' text-anchor='middle'"
             ]
    end

    # Golden: grid's drawing, through vdiffr 1.0.9's svglite (R 4.6.1), of the same labels at the
    # same places in big points, 11 points, `vjust = 0`, `check.overlap = TRUE`, one call level and
    # one turned 45 degrees. Level, it keeps A, D, H and the two justified to either side of 297.5,
    # and leaves out B, whose edges cross A's, C, whose top and bottom lie along A's and overlap
    # them, and G, whose sides lie along A's and overlap them; H's sides lie along A's line but
    # above it. Turned, it leaves out the label along the first's baseline and keeps the one to its
    # side, which would cross the first were the boxes not turned; turned 30 degrees, of two pairs
    # whose boxes meet only aslant, it keeps the pair that does not cross and leaves out the second of
    # the pair that does. It moves with grid's test.
    test "a text checking overlap leaves out each label whose box crosses one drawn before it" do
      level =
        overlap_text(
          [
            {"MMMM", 100, 100, 0.5},
            {"MMMM", 110, 103, 0.5},
            {"M", 100, 100, 0.5},
            {"MMMM", 160, 100, 0.5},
            {"MMMM", 100, 103, 0.5},
            {"MMMM", 100, 120, 0.5},
            {"MMMM", 300, 100, 0.0},
            {"MMMM", 295, 100, 1.0}
          ],
          0
        )

      turned =
        overlap_text(
          [{"MMMM", 500, 300, 0.5}, {"MMMM", 520, 320, 0.5}, {"MMMM", 530, 300, 0.5}],
          45
        )

      apart = overlap_text([{"MMMM", 200, 300, 0.5}, {"MMMM", 170, 318, 0.5}], 30)
      crossing = overlap_text([{"MMMM", 350, 300, 0.5}, {"MMMM", 369, 309, 0.5}], 30)

      assert texts(draw(whole([level, turned, apart, crossing]))) === [
               "<text x='100.00' y='476.00' text-anchor='middle'",
               "<text x='160.00' y='476.00' text-anchor='middle'",
               "<text x='100.00' y='456.00' text-anchor='middle'",
               "<text x='300.00' y='476.00'",
               "<text x='295.00' y='476.00' text-anchor='end'",
               "<text transform='translate(500.00,276.00) rotate(-45)' text-anchor='middle'",
               "<text transform='translate(530.00,276.00) rotate(-45)' text-anchor='middle'",
               "<text transform='translate(200.00,276.00) rotate(-30)' text-anchor='middle'",
               "<text transform='translate(170.00,258.00) rotate(-30)' text-anchor='middle'",
               "<text transform='translate(350.00,276.00) rotate(-30)' text-anchor='middle'"
             ]

      assert length(texts(draw(whole([%{level | check_overlap: false}])))) === 8
    end

    # Golden: vdiffr 1.0.9 (R 4.6.1) writes a turned label's angle as C's `%0.0f`: ggplot2's text
    # turned 30.5, 29.5, 91.5, 0.3 and -45 degrees, and grid's turned 29.3 and -0.3.
    test "a turned label's angle is written in whole degrees, a tie to the even one" do
      rotations =
        Enum.map([30.5, 29.5, 91.5, 0.3, -45.0, 29.3, -0.3], fn angle ->
          [element] =
            [one_label(%{angle: angle})]
            |> whole()
            |> draw()
            |> texts()

          [rotation] = Regex.run(~r/rotate\(([^)]*)\)/, element, capture: :all_but_first)
          rotation
        end)

      assert rotations === ["-30", "-30", "-92", "-0", "45", "-29", "0"]
    end

    # Not vdiffr's, which writes every family as `sans`: Giggly names the family a layer sets.
    test "a label's font is the default list, or the family named, quoted and escaped" do
      families =
        Enum.map(["", "Times New Roman", ~s(Bob's "Font" & Co)], fn family ->
          [_whole, style] =
            Regex.run(
              ~r/font-family: (.*);' textLength/,
              draw(whole([one_label(%{family: family})]))
            )

          style
        end)

      assert families === [
               ~s("Liberation Sans", Arial, Helvetica, sans-serif),
               ~s("Times New Roman"),
               ~s("Bob&apos;s &quot;Font&quot; &amp; Co")
             ]
    end

    # vdiffr writes a label's fill unless it is black and opaque, and its opacity as svglite writes
    # an R colour's alpha.
    test "a label's colour is left out only for opaque black, and written with its opacity" do
      fills =
        Enum.map(
          [{"#000000", 1.0}, {"#000000", 0.5}, {"#00BA38", 1.0}, {"#00BA38", 0.0}],
          fn {color, opacity} ->
            [_whole, style] =
              Regex.run(
                ~r/style='font-size: 11.00px;(.*) font-family/,
                draw(whole([one_label(%{color: [color], opacity: [opacity]})]))
              )

            style
          end
        )

      assert fills === [
               "",
               " fill: #000000; fill-opacity: 0.50;",
               " fill: #00BA38;",
               " fill: none;"
             ]
    end

    test "a polyline's points are moved by their offsets in points" do
      line = %Polylines{
        lines: [[{0.5, 0.25}, {0.5, 0.25}]],
        offsets: [[{0.0, 0.0}, {3.0, -4.0}]],
        stroke_width: 0.75,
        dashes: :none,
        color: ["#000000"],
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
        offsets: :none,
        fill: ["#595959"],
        fill_opacity: [1.0],
        color: [:none],
        color_opacity: [0.0],
        # A 0.5 mm line, as grid draws it in points.
        stroke_width: 0.5 * 72.27 / 25.4 * 72 / 96,
        dashes: :none,
        line_end: :butt,
        line_join: :mitre,
        mitre_limit: 10.0
      }

      drawn = draw(whole([rectangles]))

      assert String.ends_with?(
               drawn,
               "<rect x='72.00' y='115.20' width='144.00' height='172.80' " <>
                 "style='stroke-width: 1.07; stroke: none; stroke-linecap: butt; " <>
                 "stroke-linejoin: miter; fill: #595959;' />\n</svg>\n"
             )
    end

    # Golden: ggplot2 4.0.3's drawing, through vdiffr 1.0.9, of `geom_rect()` with each row's
    # corners swapped is the drawing of the rows as given, element for element.
    test "a rectangle whose corners are reversed is written as the one they bound" do
      rectangles = fn {xmin, xmax, ymin, ymax} ->
        %Rectangles{
          xmin: [xmin],
          xmax: [xmax],
          ymin: [ymin],
          ymax: [ymax],
          offsets: :none,
          fill: ["#595959"],
          fill_opacity: [1.0],
          color: [:none],
          color_opacity: [0.0],
          stroke_width: 0.5 * 72.27 / 25.4 * 72 / 96,
          dashes: :none,
          line_end: :butt,
          line_join: :mitre,
          mitre_limit: 10.0
        }
      end

      reversed = draw(whole([rectangles.({0.3, 0.1, 0.8, 0.5})]))

      assert reversed == draw(whole([rectangles.({0.1, 0.3, 0.5, 0.8})]))
      assert reversed =~ "<rect x='72.00' y='115.20' width='144.00' height='172.80' "
    end

    test "a circle's outline and fill carry its opacity, as svglite writes a colour's alpha" do
      circles = %Circles{
        x: [0.25, 0.75],
        y: [0.5, 0.5],
        radius: [1.95, 1.95],
        stroke_width: 0.71,
        color: List.duplicate("#000000", 2),
        color_opacity: [1 / 3, 1.0],
        fill: List.duplicate("#000000", 2),
        fill_opacity: [1 / 3, 1.0]
      }

      assert circles(draw(whole([circles]))) === [
               "style='stroke-width: 0.71; stroke: #000000; stroke-opacity: 0.33; " <>
                 "fill: #000000; fill-opacity: 0.33;'",
               "style='stroke-width: 0.71; stroke: #000000; fill: #000000;'"
             ]
    end

    # A mapped colour gives one per mark, as grid's `gp` holds one per element and svglite writes
    # each element's own.
    test "each circle, rectangle, polyline and segment is written in its own colour" do
      circles = %Circles{
        x: [0.25, 0.75],
        y: [0.5, 0.5],
        radius: [1.95, 1.95],
        stroke_width: 0.71,
        color: ["#F8766D", "#00BFC4"],
        color_opacity: [1.0, 1.0],
        fill: ["#F8766D", "#00BFC4"],
        fill_opacity: [1.0, 1.0]
      }

      rectangles = %Rectangles{
        xmin: [0.1, 0.5],
        xmax: [0.3, 0.7],
        ymin: [0.5, 0.5],
        ymax: [0.8, 0.8],
        offsets: :none,
        fill: ["#F8766D", "#00BFC4"],
        fill_opacity: [1.0, 1.0],
        color: [:none, "#7F7F7F"],
        color_opacity: [1.0, 1.0],
        stroke_width: 1.07,
        dashes: :none,
        line_end: :butt,
        line_join: :mitre,
        mitre_limit: 10.0
      }

      polylines = %Polylines{
        lines: [[{0.1, 0.1}, {0.2, 0.2}], [{0.3, 0.3}, {0.4, 0.4}]],
        offsets: :none,
        stroke_width: 1.07,
        dashes: :none,
        color: ["#F8766D", "#00BFC4"],
        opacity: [1.0, 1.0],
        line_end: :butt,
        line_join: :round,
        mitre_limit: 10.0
      }

      segments = %Segments{
        starts: [{0.1, 0.5}, {0.3, 0.5}],
        ends: [{0.3, 0.75}, {0.5, 0.75}],
        offsets: :none,
        stroke_width: 1.07,
        dashes: :none,
        color: ["#00BFC4", "#F8766D"],
        opacity: [1.0, 1.0],
        line_end: :butt,
        line_join: :round,
        mitre_limit: 10.0
      }

      drawn = draw(whole([circles, rectangles, polylines, segments]))

      assert circles(drawn) === [
               "style='stroke-width: 0.71; stroke: #F8766D; fill: #F8766D;'",
               "style='stroke-width: 0.71; stroke: #00BFC4; fill: #00BFC4;'"
             ]

      assert drawn =~ "stroke: none; stroke-linecap: butt; stroke-linejoin: miter; fill: #F8766D;"

      assert drawn =~
               "stroke: #7F7F7F; stroke-linecap: butt; stroke-linejoin: miter; fill: #00BFC4;"

      assert Regex.scan(~r/<(polyline|line) [^>]*?stroke: (#[0-9A-F]{6});/, drawn,
               capture: :all_but_first
             ) === [
               ["polyline", "#F8766D"],
               ["polyline", "#00BFC4"],
               ["line", "#00BFC4"],
               ["line", "#F8766D"]
             ]
    end

    # Golden: svglite 2.2.2's drawing of ggplot2 4.0.3's colour bar in its gradient form (R 4.6.1):
    # the gradient in a `<defs>` of its own, from the rectangle's bottom edge to its top at its
    # middle, each stop's offset written as svglite writes a number below 1, then the rectangle
    # filled with it. Its id is Giggly's, from its content, where svglite's counts up from `pat-0`.
    test "a gradient fills its cell with a linear gradient up it, as svglite writes one" do
      gradient = %Gradient{
        stops: [{0.0, "#132B43"}, {1 / 14, "#17334E"}, {2 / 14, "#1C3C5A"}, {1.0, "#56B1F7"}],
        stroke_width: 0.75
      }

      cell = %Cell{rows: 1..1, columns: 1..1, clip: :off, hang: :none, primitives: [gradient]}

      scene = %Giggly.Scene{
        widths: [{:points, 100.0}, {:points, 17.28}, {:rest, 1}],
        heights: [{:points, 200.0}, {:points, 86.4}, {:rest, 1}],
        keep_proportions: false,
        cells: [%{cell | rows: 2..2, columns: 2..2}]
      }

      drawn = draw(scene)
      [_all, id] = Regex.run(~r/<linearGradient id='(lg[0-9a-f]{32})'/, drawn)

      assert drawn =~
               "<defs>\n<linearGradient id='#{id}' gradientUnits='userSpaceOnUse' " <>
                 "spreadMethod='pad' x1='108.64' y1='286.40' x2='108.64' y2='200.00'>\n" <>
                 "  <stop offset='0.00' stop-color='#132B43' stop-opacity='1.00'/>\n" <>
                 "  <stop offset='0.071' stop-color='#17334E' stop-opacity='1.00'/>\n" <>
                 "  <stop offset='0.14' stop-color='#1C3C5A' stop-opacity='1.00'/>\n" <>
                 "  <stop offset='1.00' stop-color='#56B1F7' stop-opacity='1.00'/>\n" <>
                 "</linearGradient>\n</defs>\n" <>
                 "<rect x='100.00' y='200.00' width='17.28' height='86.40' " <>
                 "style='stroke-width: 0.75; stroke: none; fill: url(##{id});' />\n"
    end

    test "a gradient's id is its content's, the same for the same gradient and another for another" do
      id = fn stops ->
        gradient = %Gradient{stops: stops, stroke_width: 0.75}
        [_all, id] = Regex.run(~r/<linearGradient id='([^']*)'/, draw(whole([gradient])))
        id
      end

      same = [{0.0, "#132B43"}, {1.0, "#56B1F7"}]

      assert id.(same) === id.(same)
      refute id.(same) === id.([{0.0, "#132B43"}, {1.0, "#FFFFFF"}])
    end

    test "a placed rectangle's fill carries its opacity, and its border none" do
      rectangles = %Rectangles{
        xmin: [0.1],
        xmax: [0.3],
        ymin: [0.5],
        ymax: [0.8],
        offsets: :none,
        fill: ["#595959"],
        fill_opacity: [0.5],
        color: [:none],
        color_opacity: [0.0],
        stroke_width: 1.07,
        dashes: :none,
        line_end: :butt,
        line_join: :mitre,
        mitre_limit: 10.0
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
        radius: List.duplicate(1.95, 6),
        stroke_width: 0.71,
        color: List.duplicate("#000000", 6),
        color_opacity: opacities,
        fill: List.duplicate("#000000", 6),
        fill_opacity: opacities
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
        radius: [1.95],
        stroke_width: 0.71,
        color: ["#000000"],
        color_opacity: [0.0],
        fill: ["#000000"],
        fill_opacity: [0.0]
      }

      rectangles = %Rectangles{
        xmin: [0.1],
        xmax: [0.3],
        ymin: [0.5],
        ymax: [0.8],
        offsets: :none,
        fill: ["#595959"],
        fill_opacity: [0.0],
        color: [:none],
        color_opacity: [0.0],
        stroke_width: 1.07,
        dashes: :none,
        line_end: :butt,
        line_join: :mitre,
        mitre_limit: 10.0
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
        offsets: :none,
        fill: ["#0000FF"],
        fill_opacity: [0.3],
        color: ["#FF0000"],
        color_opacity: [128 / 255],
        stroke_width: 1.07,
        dashes: :none,
        line_end: :butt,
        line_join: :mitre,
        mitre_limit: 10.0
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
        offsets: :none,
        fill: ["#595959"],
        fill_opacity: [1.0],
        color: [:none],
        color_opacity: [1.0],
        stroke_width: 1.07,
        dashes: :none,
        line_end: :butt,
        line_join: :mitre,
        mitre_limit: 10.0
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
        offsets: :none,
        fill: [:none],
        fill_opacity: [1.0],
        color: ["#FF0000"],
        color_opacity: [1.0],
        stroke_width: 1.07,
        dashes: :none,
        line_end: :butt,
        line_join: :mitre,
        mitre_limit: 10.0
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
          dashes: :none,
          color: ["#000000"],
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
        dashes: :none,
        color: List.duplicate("#000000", 2),
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

    # As vdiffr 1.0.9's `write_style_linetype()` writes a line's style, test/golden/line_types.svg
    # and test/golden/bar_line_types.svg among its drawings: `stroke-dasharray` after the stroke
    # and its opacity, before the ends and corners, each length to two decimals, written for a
    # border of no colour too, and none for a solid line.
    test "a line's dashes follow its stroke, each length in points, and a solid line has none" do
      line = [line_end: :butt, line_join: :round, mitre_limit: 10.0]

      polylines =
        struct!(
          Polylines,
          [
            lines: [[{0.1, 0.1}, {0.2, 0.2}]],
            offsets: :none,
            stroke_width: 1.07,
            dashes: [5.6906, 17.0718],
            color: ["#FF0000"],
            opacity: [0.5]
          ] ++ line
        )

      segments =
        struct!(
          Segments,
          [
            starts: [{0.1, 0.5}],
            ends: [{0.3, 0.75}],
            offsets: :none,
            stroke_width: 1.07,
            dashes: [1.4226, 4.2679, 5.6906, 4.2679],
            color: ["#000000"],
            opacity: [1.0]
          ] ++ line
        )

      rectangles = %Rectangles{
        xmin: [0.1, 0.5],
        xmax: [0.2, 0.6],
        ymin: [0.1, 0.1],
        ymax: [0.2, 0.2],
        offsets: :none,
        fill: ["#595959", "#595959"],
        fill_opacity: [1.0, 1.0],
        color: [:none, "#000000"],
        color_opacity: [0.0, 1.0],
        stroke_width: 1.07,
        dashes: [4.0, 4.0],
        line_end: :butt,
        line_join: :mitre,
        mitre_limit: 10.0
      }

      assert Regex.scan(
               ~r/<(?:polyline|line|rect x)[^>]*?style='([^']*)'/,
               draw(whole([polylines, segments, rectangles, %{polylines | dashes: :none}])),
               capture: :all_but_first
             ) === [
               [
                 "stroke-width: 1.07; stroke: #FF0000; stroke-opacity: 0.50; " <>
                   "stroke-dasharray: 5.69,17.07; stroke-linecap: butt; fill: none;"
               ],
               [
                 "stroke-width: 1.07; stroke: #000000; " <>
                   "stroke-dasharray: 1.42,4.27,5.69,4.27; stroke-linecap: butt;"
               ],
               [
                 "stroke-width: 1.07; stroke: none; stroke-dasharray: 4.00,4.00; " <>
                   "stroke-linecap: butt; stroke-linejoin: miter; fill: #595959;"
               ],
               [
                 "stroke-width: 1.07; stroke: #000000; stroke-dasharray: 4.00,4.00; " <>
                   "stroke-linecap: butt; stroke-linejoin: miter; fill: #595959;"
               ],
               [
                 "stroke-width: 1.07; stroke: #FF0000; stroke-opacity: 0.50; " <>
                   "stroke-linecap: butt; fill: none;"
               ]
             ]
    end

    test "a segment is a line from its start to its end, its stroke carrying its opacity" do
      segments = %Segments{
        starts: [{0.1, 0.5}],
        ends: [{0.3, 0.75}],
        offsets: :none,
        stroke_width: 1.07,
        dashes: :none,
        color: ["#000000"],
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
        offsets: :none,
        stroke_width: 0.75,
        color: [:none],
        color_opacity: [1.0],
        fill: ["#EBEBEB"],
        fill_opacity: [1.0]
      }

      drawn = draw(whole([polygon]))

      assert String.ends_with?(
               drawn,
               "<polygon points='72.00,518.40 144.00,518.40 144.00,403.20 ' " <>
                 "style='stroke-width: 0.75; stroke: none; fill: #EBEBEB;' />\n</svg>\n"
             )
    end

    # Golden: the styles vdiffr 1.0.9 writes for ggplot2 4.0.3's shapes 1 and 16 at alpha 0.5, each
    # circle placed here: an outline alone, `stroke-opacity: 0.50` and no fill, which svglite leaves
    # to its stylesheet; a fill alone, `stroke: none; fill: #0000FF; fill-opacity: 0.50`.
    test "each circle is written at its own radius, its outline and fill each in its own colour" do
      circles = %Circles{
        x: [0.25, 0.75],
        y: [0.5, 0.5],
        radius: [6.04, 1.95],
        stroke_width: 1.42,
        color: ["#0000FF", :none],
        color_opacity: [0.5, 0.0],
        fill: [:none, "#0000FF"],
        fill_opacity: [0.0, 0.5]
      }

      drawn = draw(whole([circles]))

      assert Regex.scan(~r/<circle [^>]*/, drawn) === [
               [
                 "<circle cx='180.00' cy='288.00' r='6.04' style='stroke-width: 1.42; " <>
                   "stroke: #0000FF; stroke-opacity: 0.50; fill: none;' /"
               ],
               [
                 "<circle cx='540.00' cy='288.00' r='1.95' style='stroke-width: 1.42; " <>
                   "stroke: none; fill: #0000FF; fill-opacity: 0.50;' /"
               ]
             ]
    end

    # vdiffr 1.0.9 writes ggplot2 4.0.3's shape 0, a square round its place, with grid's round
    # corners and ends, which svglite does not write; the corners here are placed by hand.
    test "a rectangle's corners are moved by their offsets, its ends and corners as a line's" do
      rectangles = %Rectangles{
        xmin: [0.5],
        xmax: [0.5],
        ymin: [0.5],
        ymax: [0.5],
        offsets: [{{-6.0, -4.0}, {6.0, 4.0}}],
        fill: [:none],
        fill_opacity: [0.0],
        color: ["#0000FF"],
        color_opacity: [0.5],
        stroke_width: 1.42,
        dashes: :none,
        line_end: :round,
        line_join: :round,
        mitre_limit: 10.0
      }

      drawn = draw(whole([rectangles]))

      assert String.ends_with?(
               drawn,
               "<rect x='354.00' y='284.00' width='12.00' height='8.00' style='stroke-width: " <>
                 "1.42; stroke: #0000FF; stroke-opacity: 0.50; fill: none;' />\n</svg>\n"
             )
    end

    # Golden: the styles vdiffr 1.0.9 writes for ggplot2 4.0.3's shapes 2 and 15 at alpha 0.5, each
    # polygon placed here: an outline alone, and a fill alone.
    test "a polygon's points are moved by their offsets, each polygon in its own colours" do
      polygons = %Polygons{
        outlines: [List.duplicate({0.5, 0.5}, 3), List.duplicate({0.25, 0.5}, 3)],
        offsets: [
          [{0.0, 9.0}, {8.0, -5.0}, {-8.0, -5.0}],
          [{-6.0, -6.0}, {6.0, -6.0}, {0.0, 6.0}]
        ],
        stroke_width: 1.42,
        color: ["#0000FF", :none],
        color_opacity: [0.5, 0.0],
        fill: [:none, "#0000FF"],
        fill_opacity: [0.0, 0.5]
      }

      drawn = draw(whole([polygons]))

      assert Regex.scan(~r/<polygon [^>]*/, drawn) === [
               [
                 "<polygon points='360.00,279.00 368.00,293.00 352.00,293.00 ' style='" <>
                   "stroke-width: 1.42; stroke: #0000FF; stroke-opacity: 0.50; fill: none;' /"
               ],
               [
                 "<polygon points='174.00,294.00 186.00,294.00 180.00,282.00 ' style='" <>
                   "stroke-width: 1.42; stroke: none; fill: #0000FF; fill-opacity: 0.50;' /"
               ]
             ]
    end

    test "a segment's ends are moved by their offsets" do
      segments = %Segments{
        starts: [{0.5, 0.5}],
        ends: [{0.5, 0.5}],
        offsets: [{{-8.5, -3.0}, {8.5, 3.0}}],
        stroke_width: 1.42,
        dashes: :none,
        color: ["#0000FF"],
        opacity: [1.0],
        line_end: :round,
        line_join: :round,
        mitre_limit: 10.0
      }

      drawn = draw(whole([segments]))

      assert String.ends_with?(
               drawn,
               "<line x1='351.50' y1='291.00' x2='368.50' y2='285.00' " <>
                 "style='stroke-width: 1.42; stroke: #0000FF;' />\n</svg>\n"
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

  # Labels checking overlap, each `{label, x, y, hjust}` at its place in points in the whole drawing,
  # 11 points tall and black, its baseline on its place, turned `angle` degrees.
  defp overlap_text(labels, angle) do
    count = length(labels)

    %Text{
      x: Enum.map(labels, fn {_label, x_points, _y_points, _hjust} -> x_points / 720 end),
      y: Enum.map(labels, fn {_label, _x_points, y_points, _hjust} -> y_points / 576 end),
      labels: Enum.map(labels, fn {label, _x_points, _y_points, _hjust} -> label end),
      widths:
        Enum.map(labels, fn {label, _x_points, _y_points, _hjust} -> Font.width(label, 11.0) end),
      size: 11.0,
      family: "",
      color: List.duplicate("#000000", count),
      opacity: List.duplicate(1.0, count),
      angle: angle,
      hjust: Enum.map(labels, fn {_label, _x_points, _y_points, hjust} -> hjust end),
      offset: List.duplicate({0.0, 0.0}, count),
      check_overlap: true,
      ascent: Font.ascent(11.0)
    }
  end

  # One label in the middle of the drawing, 11 points and black, with `changes` made to it.
  defp one_label(changes) do
    struct!(
      %Text{
        x: [0.5],
        y: [0.5],
        labels: ["Hello"],
        widths: [25.68],
        size: 11.0,
        family: "",
        color: ["#000000"],
        opacity: [1.0],
        angle: 0,
        hjust: [0.5],
        offset: [{0.0, 0.0}],
        check_overlap: false,
        ascent: 7.88
      },
      changes
    )
  end

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
