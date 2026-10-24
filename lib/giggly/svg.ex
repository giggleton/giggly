defmodule Giggly.SVG do
  @moduledoc false

  # Writes a `Giggly.Scene` as SVG.
  #
  # The table is laid out at the size it is given, in points (1/72 inch), as grid lays out a layout:
  # each column or row with a size in points takes it, and the columns that are shares split what is
  # left by their weights, as do the rows. A scene that keeps its proportions gives every share one
  # scale, the one that fits whichever way runs out first, as grid does a layout with `respect`, and
  # the table, which then fills the drawing only one way, is centred in it. Each cell's box runs
  # from the start of its first column and row to the end of its last, or hangs a height of its own
  # from its rows' top or a width of its own from its columns' right, and its primitives are placed
  # in that box, and moved by any offset they carry in points, cells in the order the scene lists
  # them; a clipped cell's are drawn in a group cut off at the box, as svglite writes one. A scene
  # nested in a cell, such as a legend, is laid out in the cell's box the same way, centred in it
  # when all its sizes are in points. The document's user unit is the point, as svglite writes it:
  # the `viewBox` is the size in points and `width` and `height` carry `pt`, so a radius of 1.95 is
  # 1.95 points at the size the plot is shown. A position is written with two decimals, a size, an
  # opacity or an offset as svglite writes a number, more decimals the nearer it is to 0, and each
  # primitive as svglite writes it, so output can be set
  # beside the SVG ggplot2's own tests snapshot; a polyline also says it is not filled, and so does a
  # shape of no fill or a wholly transparent one, which svglite leaves to its stylesheet and SVG
  # would otherwise fill black. svglite's stylesheet also
  # gives every line round ends, round corners and a mitre limit of 10, and writes a line's own
  # only where it differs; a stylesheet inlined in a page styles the whole page, so the root
  # declares those three as attributes, which every element inherits and any CSS outranks, and a
  # line writes its own ends, corners and limit as svglite does.
  #
  # svglite anchors text only at its start, middle or end, so R's graphics engine hands it the
  # nearest of those to a label's `hjust` and moves the label along its baseline by the rest of
  # its width; so does this backend. A text that checks overlap draws each label only where its box
  # crosses no box drawn before it, which grid decides once it knows where the labels land, as only
  # a backend does here. An empty label is not written, as svglite writes none, though it keeps the
  # room measured for it.
  #
  # Text is drawn in the fonts whose widths `Giggly.Font` measures with (Liberation Sans, Arial,
  # Helvetica) or else the browser's sans-serif, and each label is stretched or squeezed to its
  # measured width (svglite's `textLength`), so it fills the space measured for it whatever font
  # draws it.

  # The SVG backend reads the scene and nothing else.
  use Boundary, deps: [Giggly.Scene], exports: []

  alias Giggly.Scene

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

  @font_family ~S("Liberation Sans", Arial, Helvetica, sans-serif)

  # A double's machine epsilon, below which svglite's `dbl_format()` writes a number as 0.
  @epsilon 2.220446049250313e-16

  # The SVG document that draws `scene` at `width` by `height` points, as grid's `grid.draw()` puts
  # a finished table on a device.
  @doc false
  @spec draw(Scene.t(), number(), number()) :: iodata()
  def draw(%Scene{widths: widths, heights: heights, cells: cells} = scene, width, height) do
    {column_spans, row_spans} =
      lay_out({widths, width}, {heights, height}, scene.keep_proportions)

    [
      "<svg xmlns='http://www.w3.org/2000/svg' width='",
      number(width),
      "pt' height='",
      number(height),
      "pt' viewBox='0 0 ",
      number(width),
      " ",
      number(height),
      "' stroke-linecap='round' stroke-linejoin='round' stroke-miterlimit='10.00'>\n",
      Enum.map(cells, fn cell -> cell(cell, column_spans, row_spans) end),
      "</svg>\n"
    ]
  end

  # Each column's and each row's start and length along the drawing, as grid lays out a layout:
  # sizes in points take their length, and the shares split what they leave by weight, its weight
  # times what is left over all the weights. A table keeping its proportions gives each share its
  # weight over the weights of the way that runs out first, times what that way leaves, as grid
  # allocates a respected layout's null units, and is centred both ways.
  defp lay_out({widths, width}, {heights, height}, false) do
    {spans(widths, split(widths, width), 0), spans(heights, split(heights, height), 0)}
  end

  defp lay_out({widths, width}, {heights, height}, true) do
    {width_left, height_left} = {left(widths, width), left(heights, height)}
    {width_weight, height_weight} = {weight(widths), weight(heights)}

    share =
      if height_left / width_left > height_weight / width_weight,
        do: fn weight -> weight / width_weight * width_left end,
        else: fn weight -> weight / height_weight * height_left end

    {centred(widths, share, width), centred(heights, share, height)}
  end

  # The shares' split of what the sizes in points leave of `total`.
  defp split(sizes, total) do
    left = left(sizes, total)
    total_weight = weight(sizes)
    fn weight -> left * weight / total_weight end
  end

  defp left(sizes, total), do: total - Enum.sum(for {:points, length} <- sizes, do: length)
  defp weight(sizes), do: Enum.sum(for {:rest, weight} <- sizes, do: weight)

  # The sizes laid end to end, centred in `total`.
  defp centred(sizes, share, total) do
    length =
      sizes
      |> Enum.map(fn size -> length(size, share) end)
      |> Enum.sum()

    spans(sizes, share, (total - length) / 2)
  end

  # The sizes laid out in `total` from `start`, the shares splitting what the sizes in points leave,
  # and centred in `total` when they take less of it, as they do when none is a share.
  defp centred_spans(sizes, total, start) do
    share = split(sizes, total)

    length =
      sizes
      |> Enum.map(fn size -> length(size, share) end)
      |> Enum.sum()

    spans(sizes, share, start + (total - length) / 2)
  end

  # Each size's start and length, the first starting at `start`.
  defp spans(sizes, share, start) do
    {spans, _end} =
      Enum.map_reduce(sizes, start, fn size, from ->
        length = length(size, share)
        {{from, length}, from + length}
      end)

    spans
  end

  defp length({:points, length}, _share), do: length
  defp length({:rest, weight}, share), do: share.(weight)

  defp cell(%Cell{rows: rows, columns: columns} = cell, column_spans, row_spans) do
    box = hang({span(column_spans, columns), span(row_spans, rows)}, cell.hang)
    drawn = Enum.map(cell.primitives, fn primitive -> primitive(primitive, box) end)
    clip(drawn, cell.clip, box)
  end

  # A clipped cell's primitives are drawn in a group cut off at the cell's box, as svglite writes a
  # clipping viewport: the box's clip path, named by its edges so that two drawings on one page
  # share a name only when they share the box, then the group.
  defp clip(drawn, :off, _box), do: drawn

  defp clip(drawn, :on, {{left, width}, {top, height}}) do
    edges =
      Enum.join([number(left), number(left + width), number(top), number(top + height)], "|")

    id = ["cp", Base.encode64(edges)]

    [
      "<defs>\n  <clipPath id='",
      id,
      "'>\n    <rect x='",
      number(left),
      "' y='",
      number(top),
      "' width='",
      number(width),
      "' height='",
      number(height),
      "' />\n  </clipPath>\n</defs>\n<g clip-path='url(#",
      id,
      ")'>\n",
      drawn,
      "</g>\n"
    ]
  end

  # A hanging cell's box: from its rows' top as tall as it says, or as wide as it says ending at its
  # columns' right or starting at their left.
  defp hang(box, :none), do: box
  defp hang({columns, {top, _height}}, {:top, height}), do: {columns, {top, height}}

  defp hang({{left, width}, rows}, {:right, own_width}),
    do: {{left + width - own_width, own_width}, rows}

  defp hang({{left, _width}, rows}, {:left, own_width}), do: {{left, own_width}, rows}

  # A cell's start and length in one direction: from its first column's or row's start to its
  # last one's end.
  defp span(spans, first..last//1) do
    {start, _first_length} = Enum.at(spans, first - 1)
    {last_start, last_length} = Enum.at(spans, last - 1)
    {start, last_start + last_length - start}
  end

  # A cell's y runs up from its bottom edge; SVG's runs down from the top.
  defp place({x, y}, {{left, width}, {top, height}}),
    do: {left + x * width, top + (1 - y) * height}

  # A position moved `across` and `up` in points.
  defp moved({x_position, y_position}, {across, up}), do: {x_position + across, y_position - up}

  # A scene nested in a cell, laid out in the cell's box as grid lays out a layout in a viewport:
  # its sizes in points take their length and its shares split what is left, and a table of points
  # alone, smaller than the box, is centred in it both ways, as gtable centres a legend in the plot.
  # Its cells are drawn as the whole scene's are.
  defp primitive(%Scene{keep_proportions: false} = scene, {{left, width}, {top, height}}) do
    column_spans = centred_spans(scene.widths, width, left)
    row_spans = centred_spans(scene.heights, height, top)
    Enum.map(scene.cells, fn cell -> cell(cell, column_spans, row_spans) end)
  end

  # Each circle at its own radius, its outline its colour at its opacity and its fill likewise, as
  # svglite writes a colour's alpha.
  defp primitive(%Circles{} = circles, box) do
    columns = [
      circles.x,
      circles.y,
      circles.radius,
      circles.color,
      circles.color_opacity,
      circles.fill,
      circles.fill_opacity
    ]

    Enum.zip_with(columns, fn [x_place, y_place, radius, color, color_opacity, fill, fill_opacity] ->
      {x_position, y_position} = place({x_place, y_place}, box)

      [
        "<circle cx='",
        number(x_position),
        "' cy='",
        number(y_position),
        "' r='",
        significant(radius),
        "' style='stroke-width: ",
        significant(circles.stroke_width),
        ";",
        stroke_style(color, color_opacity),
        fill_style(fill, fill_opacity),
        "' />\n"
      ]
    end)
  end

  # A rectangle fills its cell, its dashes after its stroke, as svglite writes a rectangle.
  defp primitive(%Rect{} = rect, {{left, width}, {top, height}}) do
    [
      "<rect x='",
      number(left),
      "' y='",
      number(top),
      "' width='",
      number(width),
      "' height='",
      number(height),
      "' style='stroke-width: ",
      significant(rect.stroke_width),
      "; stroke: ",
      paint(rect.color),
      ";",
      dash_style(rect.dashes),
      " fill: ",
      paint(rect.fill),
      ";' />\n"
    ]
  end

  # A gradient's rectangle fills its cell, filled with a linear gradient up it, as svglite writes
  # one: the gradient in a `<defs>` of its own, running at the rectangle's middle from its bottom
  # edge to its top in the drawing's points (`userSpaceOnUse`), each stop at its offset, written as
  # svglite writes a number below 1, in its colour, opaque; then the rectangle, filled with it and
  # stroked none. Its id is its content's, `lg` and the MD5 of what it holds, so two drawings on one
  # page share an id only when they share the gradient and cannot fill each other's bars.
  defp primitive(%Gradient{} = gradient, {{left, width}, {top, height}}) do
    middle = left + width / 2

    definition = [
      "gradientUnits='userSpaceOnUse' spreadMethod='pad' x1='",
      number(middle),
      "' y1='",
      number(top + height),
      "' x2='",
      number(middle),
      "' y2='",
      number(top),
      "'>\n",
      Enum.map(gradient.stops, fn {offset, color} ->
        [
          "  <stop offset='",
          significant(offset),
          "' stop-color='",
          color,
          "' stop-opacity='1.00'/>\n"
        ]
      end)
    ]

    digest =
      definition
      |> :erlang.md5()
      |> Base.encode16(case: :lower)

    id = ["lg", digest]

    [
      "<defs>\n<linearGradient id='",
      id,
      "' ",
      definition,
      "</linearGradient>\n</defs>\n<rect x='",
      number(left),
      "' y='",
      number(top),
      "' width='",
      number(width),
      "' height='",
      number(height),
      "' style='stroke-width: ",
      significant(gradient.stroke_width),
      "; stroke: none; fill: url(#",
      id,
      ");' />\n"
    ]
  end

  # Each rectangle as grid places one hung from its top left corner, as ggplot2's `GeomRect` hangs
  # it, its border its colour at its opacity, its dashes, ends and corners as a line's, and its fill
  # its colour at its opacity.
  defp primitive(%Rectangles{} = rectangles, box) do
    dashes = dash_style(rectangles.dashes)
    style = line_style(rectangles.line_end, rectangles.line_join, rectangles.mitre_limit)

    columns = [
      placed_rectangles(rectangles, box),
      rectangles.fill,
      rectangles.fill_opacity,
      rectangles.color,
      rectangles.color_opacity
    ]

    Enum.zip_with(columns, fn [
                                {x_position, y_position, across, down},
                                fill,
                                fill_opacity,
                                color,
                                color_opacity
                              ] ->
      [
        "<rect x='",
        number(x_position),
        "' y='",
        number(y_position),
        "' width='",
        number(across),
        "' height='",
        number(down),
        "' style='stroke-width: ",
        significant(rectangles.stroke_width),
        ";",
        stroke_style(color, color_opacity),
        dashes,
        style,
        fill_style(fill, fill_opacity),
        "' />\n"
      ]
    end)
  end

  # Each line as svglite writes a polyline, its stroke its colour at its opacity, then its dashes.
  defp primitive(%Polylines{} = polylines, box) do
    lines = placed_lines(polylines.lines, polylines.offsets, box)
    dashes = dash_style(polylines.dashes)
    style = line_style(polylines.line_end, polylines.line_join, polylines.mitre_limit)

    Enum.zip_with([lines, polylines.color, polylines.opacity], fn [line, color, opacity] ->
      [
        "<polyline points='",
        points(line),
        "' style='stroke-width: ",
        significant(polylines.stroke_width),
        ";",
        stroke_style(color, opacity),
        dashes,
        style,
        " fill: none;' />\n"
      ]
    end)
  end

  # Each segment as svglite writes a line, from its start to its end, each moved by its offset,
  # its stroke its colour at its opacity, then its dashes.
  defp primitive(%Segments{} = segments, box) do
    dashes = dash_style(segments.dashes)
    style = line_style(segments.line_end, segments.line_join, segments.mitre_limit)
    columns = [placed_segments(segments, box), segments.color, segments.opacity]

    Enum.zip_with(columns, fn [{{x_start, y_start}, {x_finish, y_finish}}, color, opacity] ->
      [
        "<line x1='",
        number(x_start),
        "' y1='",
        number(y_start),
        "' x2='",
        number(x_finish),
        "' y2='",
        number(y_finish),
        "' style='stroke-width: ",
        significant(segments.stroke_width),
        ";",
        stroke_style(color, opacity),
        dashes,
        style,
        "' />\n"
      ]
    end)
  end

  # Each polygon round its outline, each point moved by its offset, its border its colour at its
  # opacity, then its dashes and line style, and its fill likewise, as svglite writes a polygon.
  defp primitive(%Polygons{} = polygons, box) do
    dashes = dash_style(polygons.dashes)
    style = line_style(polygons.line_end, polygons.line_join, polygons.mitre_limit)

    columns = [
      placed_lines(polygons.outlines, polygons.offsets, box),
      polygons.color,
      polygons.color_opacity,
      polygons.fill,
      polygons.fill_opacity
    ]

    Enum.zip_with(columns, fn [outline, color, color_opacity, fill, fill_opacity] ->
      [
        "<polygon points='",
        points(outline),
        "' style='stroke-width: ",
        significant(polygons.stroke_width),
        ";",
        stroke_style(color, color_opacity),
        dashes,
        style,
        fill_style(fill, fill_opacity),
        "' />\n"
      ]
    end)
  end

  defp primitive(%Text{} = text, box) do
    columns = [
      text.x,
      text.y,
      text.labels,
      text.widths,
      text.color,
      text.opacity,
      text.hjust,
      text.offset
    ]

    columns
    |> Enum.zip_with(fn [x_place, y_place, label, label_width, color, opacity, hjust, offset] ->
      %{
        place: place({x_place, y_place}, box),
        label: label,
        width: label_width,
        color: color,
        opacity: opacity,
        hjust: hjust,
        offset: offset
      }
    end)
    |> drawn_labels(text)
    |> Enum.reject(fn label -> label.label == "" end)
    |> Enum.map(fn label -> text_label(label, text) end)
  end

  # A label as svglite writes one: anchored at the start, middle or end nearest its `hjust`, and
  # moved back along its baseline by the part of its width between there and its `hjust`.
  defp text_label(label, text) do
    anchor = 0.5 * Float.floor(2 * label.hjust + 0.5)
    {along, up} = label.offset

    baseline =
      along_text(label.place, {along - (label.hjust - anchor) * label.width, up}, text.angle)

    [
      "<text",
      text_position(baseline, text.angle),
      text_anchor(anchor),
      " style='font-size: ",
      number(text.size),
      "px;",
      text_fill(label.color, label.opacity),
      " font-family: ",
      font_family(text.family),
      ";' textLength='",
      number(label.width),
      "px' lengthAdjust='spacingAndGlyphs'>",
      escape(label.label),
      "</text>\n"
    ]
  end

  # The labels a text draws: all of them, or, when it checks overlap, each whose box crosses the
  # box of no label drawn before it, in order, as grid's `textGrob(check.overlap = TRUE)` draws.
  defp drawn_labels(labels, %Text{check_overlap: false}), do: labels

  defp drawn_labels(labels, %Text{check_overlap: true} = text) do
    {drawn, _boxes} =
      Enum.reduce(labels, {[], []}, fn label, so_far ->
        drawn_unless_crossing(label, so_far, text)
      end)

    Enum.reverse(drawn)
  end

  # The labels drawn so far, latest first, and their boxes, with `label` and its box added unless its
  # box crosses one of theirs.
  defp drawn_unless_crossing(label, {drawn, boxes}, text) do
    box = label_box(label, text)

    if Enum.any?(boxes, fn other -> boxes_cross?(box, other) end),
      do: {drawn, boxes},
      else: {[label | drawn], [box | boxes]}
  end

  # A label's box, its corners in order round it, as grid's `textRect()` makes it: as long as the
  # label's width along its baseline from where its `hjust` puts its start, and as tall as the text's
  # ascent up from its baseline, turned with the text.
  defp label_box(label, text) do
    {along, up} = label.offset
    start = along - label.hjust * label.width
    finish = start + label.width
    top = up + text.ascent

    Enum.map([{start, up}, {finish, up}, {finish, top}, {start, top}], fn corner ->
      along_text(label.place, corner, text.angle)
    end)
  end

  # Whether two boxes cross, as grid's `intersect()` decides: whether an edge of one crosses an edge
  # of the other. A box wholly inside another crosses nothing, as grid's does not.
  defp boxes_cross?(box, other) do
    other_edges = edges(other)

    box
    |> edges()
    |> Enum.any?(fn edge ->
      Enum.any?(other_edges, fn other_edge -> lines_cross?(edge, other_edge) end)
    end)
  end

  defp edges([first | _rest] = corners) do
    corners
    |> Enum.concat([first])
    |> Enum.chunk_every(2, 1, :discard)
  end

  # Whether two edges cross, as grid's `linesIntersect()` decides, by Paul Bourke's method: two that
  # lie along one line cross where their extents overlap, two that are parallel never, and any
  # others where each passes strictly between the other's ends.
  defp lines_cross?([{x1, y1}, {x2, y2}], [{x3, y3}, {x4, y4}]) do
    denominator = (y4 - y3) * (x2 - x1) - (x4 - x3) * (y2 - y1)
    along_first = (x4 - x3) * (y1 - y3) - (y4 - y3) * (x1 - x3)
    along_second = (x2 - x1) * (y1 - y3) - (y2 - y1) * (x1 - x3)

    cond do
      denominator == 0 and along_first == 0 and x1 == x2 ->
        extents_meet?({y1, y2}, {y3, y4})

      denominator == 0 and along_first == 0 ->
        extents_meet?({x1, x2}, {x3, x4})

      denominator == 0 ->
        false

      true ->
        strictly_inside?(along_first / denominator) and
          strictly_inside?(along_second / denominator)
    end
  end

  defp strictly_inside?(fraction), do: fraction > 0 and fraction < 1

  # Whether the extents of two edges along one line meet, as grid compares them: unless one starts
  # below the other and ends before the other begins.
  defp extents_meet?({start, finish}, {other_start, other_finish}) do
    not ((start < other_start and max(start, finish) < min(other_start, other_finish)) or
           (other_start < start and max(other_start, other_finish) < min(start, finish)))
  end

  # A position moved `along` a text's baseline and `up` toward its top, in points, the baseline
  # turned `angle` degrees anticlockwise from rightward, as R's graphics engine turns it.
  defp along_text(position, {along, up}, angle) do
    radians = angle * :math.pi() / 180
    cosine = :math.cos(radians)
    sine = :math.sin(radians)
    moved(position, {along * cosine - up * sine, along * sine + up * cosine})
  end

  # svglite places level text by its `x` and `y`, and turned text by a transform, its angle negated
  # since SVG turns clockwise and written as vdiffr writes it, a whole number of degrees (`%0.0f`).
  defp text_position({x_position, y_position}, angle) when angle == 0,
    do: [" x='", number(x_position), "' y='", number(y_position), "'"]

  defp text_position({x_position, y_position}, angle) do
    [
      " transform='translate(",
      number(x_position),
      ",",
      number(y_position),
      ") rotate(",
      whole_degrees(-angle),
      ")'"
    ]
  end

  # A number of degrees as C's `%0.0f` writes it: rounded to the nearest whole number, a tie to the
  # even one, and a negative number that rounds to 0 written `-0`.
  defp whole_degrees(degrees) do
    floor = Float.floor(degrees / 1)
    rest = degrees - floor
    rounded = round_whole(floor, rest)
    sign = if rounded == 0 and degrees < 0, do: "-", else: ""

    whole =
      rounded
      |> trunc()
      |> Integer.to_string()

    [sign, whole]
  end

  defp round_whole(floor, rest) when rest > 0.5, do: floor + 1
  defp round_whole(floor, rest) when rest < 0.5, do: floor

  defp round_whole(floor, _half) do
    if rem(trunc(floor), 2) == 0, do: floor, else: floor + 1
  end

  # A label's colour as vdiffr writes it: left out for opaque black, SVG's default.
  defp text_fill("#000000", opacity) when opacity == 1, do: ""
  defp text_fill(color, opacity), do: fill_style(color, opacity)

  # The default family, `""`, is drawn in the fonts whose widths `Giggly.Font` measures with; any
  # other is named, quoted, and drawn at those widths all the same.
  defp font_family(""), do: @font_family
  defp font_family(family), do: [?", escape_attribute(family), ?"]

  # svglite writes no anchor for text anchored at its start, SVG's default.
  defp text_anchor(anchor) when anchor == 0.0, do: ""
  defp text_anchor(anchor) when anchor == 0.5, do: " text-anchor='middle'"
  defp text_anchor(anchor) when anchor == 1.0, do: " text-anchor='end'"

  # Placed lines, or a polygon's outlines, each point moved by its offset, if they carry any.
  defp placed_lines(lines, :none, box),
    do: Enum.map(lines, fn line -> Enum.map(line, fn position -> place(position, box) end) end)

  defp placed_lines(lines, offsets, box) do
    Enum.zip_with(lines, offsets, fn line, line_offsets ->
      Enum.zip_with(line, line_offsets, fn position, offset -> placed(position, offset, box) end)
    end)
  end

  # A position placed in its box and moved by its offset in points.
  defp placed(position, offset, box) do
    position
    |> place(box)
    |> moved(offset)
  end

  # Each segment's start and end in the drawing, each moved by its offset, if the segments carry
  # any.
  defp placed_segments(%Segments{offsets: :none} = segments, box) do
    Enum.zip_with(segments.starts, segments.ends, fn start, finish ->
      {place(start, box), place(finish, box)}
    end)
  end

  defp placed_segments(%Segments{} = segments, box) do
    Enum.zip_with(
      [segments.starts, segments.ends, segments.offsets],
      fn [start, finish, {start_offset, finish_offset}] ->
        {placed(start, start_offset, box), placed(finish, finish_offset, box)}
      end
    )
  end

  # Each rectangle's top left corner in the drawing, its width and its height: its width and
  # height the cell's share of its extent, or the distance between its corners once each is moved
  # by its offset. A rectangle whose `xmin` is past its `xmax`, or `ymin` past its `ymax`, is
  # written from its left and top all the same, as svglite writes one, its width and height never
  # negative.
  defp placed_rectangles(
         %Rectangles{offsets: :none} = rectangles,
         {{_left, width}, {_top, height}} = box
       ) do
    columns = [rectangles.xmin, rectangles.xmax, rectangles.ymin, rectangles.ymax]

    Enum.zip_with(columns, fn [xmin, xmax, ymin, ymax] ->
      {x_position, y_position} = place({min(xmin, xmax), max(ymin, ymax)}, box)
      {x_position, y_position, abs(xmax - xmin) * width, abs(ymax - ymin) * height}
    end)
  end

  defp placed_rectangles(%Rectangles{} = rectangles, box) do
    columns = [
      rectangles.xmin,
      rectangles.xmax,
      rectangles.ymin,
      rectangles.ymax,
      rectangles.offsets
    ]

    Enum.zip_with(columns, fn [xmin, xmax, ymin, ymax, {low_offset, high_offset}] ->
      {low_x, low_y} = placed({xmin, ymin}, low_offset, box)
      {high_x, high_y} = placed({xmax, ymax}, high_offset, box)
      {min(low_x, high_x), min(low_y, high_y), abs(high_x - low_x), abs(high_y - low_y)}
    end)
  end

  defp points(positions) do
    Enum.map(positions, fn {x_position, y_position} ->
      [number(x_position), ",", number(y_position), " "]
    end)
  end

  # A line's dashes as svglite writes them, after its stroke: each length in points, joined by
  # commas, or nothing for a solid line, SVG's default.
  defp dash_style(:none), do: ""

  defp dash_style(dashes),
    do: [" stroke-dasharray: ", Enum.map_intersperse(dashes, ",", &number/1), ";"]

  # A line's ends and corners as svglite writes them, leaving out what its stylesheet declares,
  # round ends, round corners and a mitre limit of 10, which the document's root declares here: a
  # line's ends when not round, its corners when not round, and its mitre limit only for mitred
  # corners, when it is not 10.
  defp line_style(line_end, line_join, mitre_limit),
    do: [line_end_style(line_end), line_join_style(line_join, mitre_limit)]

  defp line_end_style(:round), do: ""
  defp line_end_style(:butt), do: " stroke-linecap: butt;"
  defp line_end_style(:square), do: " stroke-linecap: square;"

  defp line_join_style(:round, _mitre_limit), do: ""
  defp line_join_style(:bevel, _mitre_limit), do: " stroke-linejoin: bevel;"

  defp line_join_style(:mitre, mitre_limit) when abs(mitre_limit - 10) > 1.0e-3,
    do: [" stroke-linejoin: miter; stroke-miterlimit: ", number(mitre_limit), ";"]

  defp line_join_style(:mitre, _mitre_limit), do: " stroke-linejoin: miter;"

  # A border or a fill of `:none` is SVG's `none`: svglite writes a border whose colour is R's `NA`
  # so, and leaves out such a fill, which its stylesheet then makes `none`.
  defp paint(:none), do: "none"
  defp paint(color), do: color

  # svglite writes a text's fill only when it is not black, SVG's default.
  # The characters svglite escapes in text.
  defp escape(label) do
    label
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  # A font's name inside a single-quoted style attribute and its own double quotes: escaped as
  # text is, and its quotes too.
  defp escape_attribute(name) do
    name
    |> escape()
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  # A stroke or a fill in a colour at an opacity, as svglite writes an R colour, which holds its
  # alpha as a byte, the opacity times 255 rounded half to even: the colour, then the byte over 255
  # as its opacity, left out for an opaque colour, 255. A stroke or fill of no colour, `:none`, or
  # wholly transparent, 0, is written `none`: svglite writes such a stroke `none` and skips such a
  # fill, which its stylesheet then makes `none`, and SVG without that stylesheet would fill black.
  defp stroke_style(:none, _opacity), do: " stroke: none;"

  defp stroke_style(color, opacity) do
    case alpha_byte(opacity) do
      0 -> " stroke: none;"
      byte -> [" stroke: ", color, ";", opacity_style("stroke", byte)]
    end
  end

  defp fill_style(:none, _opacity), do: " fill: none;"

  defp fill_style(fill, opacity) do
    case alpha_byte(opacity) do
      0 -> " fill: none;"
      byte -> [" fill: ", fill, ";", opacity_style("fill", byte)]
    end
  end

  defp opacity_style(_property, 255), do: ""

  defp opacity_style(property, byte),
    do: [" ", property, "-opacity: ", significant(byte / 255), ";"]

  defp alpha_byte(opacity) do
    scaled = opacity * 255
    whole = trunc(scaled)
    half_to_even(whole, scaled - whole)
  end

  defp half_to_even(whole, fraction) when fraction < 0.5, do: whole
  defp half_to_even(whole, fraction) when fraction > 0.5, do: whole + 1
  defp half_to_even(whole, _half) when rem(whole, 2) == 0, do: whole
  defp half_to_even(whole, _half), do: whole + 1

  # A position or an extent, with two decimals, as svglite writes one from 0.1 up and a clip path's
  # edges into its name. svglite writes a smaller one as `significant/1` does, but a position that
  # near 0 is layout's rounding error, which grid's arithmetic and this backend's leave apart, as
  # 5.7e-14 for grid's 0 at the top of a radial panel's background.
  defp number(value), do: :erlang.float_to_binary(value / 1, decimals: 2)

  # A size, a stroke's width or a circle's radius, an opacity or a gradient stop's offset, as
  # svglite's `write_double()` writes every number: from 1 up, and 0, with two decimals; nearer 0
  # than 1 with as many decimals as reach its first significant digit and one more, so 0.0235 is
  # 0.024, 0.0078 keeps its 78 and 0.04 is 0.040, and from 0.1 up two; and one nearer 0 than a
  # double's epsilon as 0, as svglite's `dbl_format()` takes it. Each is worked out in R's own
  # order, so no rounding error sets it apart from R's.
  defp significant(value) when abs(value) < @epsilon, do: number(0.0)

  defp significant(value) when abs(value) < 1 do
    magnitude = abs(value)
    decimals = ceil(-:math.log10(magnitude)) + 1
    :erlang.float_to_binary(value, decimals: decimals)
  end

  defp significant(value), do: number(value)
end
