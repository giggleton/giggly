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
  # 1.95 points at the size the plot is shown. Numbers are written with two decimals, an opacity as
  # svglite writes a number below 1, and each primitive as svglite writes it, so output can be set
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
  # its width; so does this backend.
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

  # Each circle's outline and fill are its colour at its opacity, as svglite writes a colour's
  # alpha.
  defp primitive(%Circles{} = circles, box) do
    columns = [circles.x, circles.y, circles.color, circles.opacity]

    Enum.zip_with(columns, fn [x_place, y_place, color, opacity] ->
      {x_position, y_position} = place({x_place, y_place}, box)

      [
        "<circle cx='",
        number(x_position),
        "' cy='",
        number(y_position),
        "' r='",
        number(circles.radius),
        "' style='stroke-width: ",
        number(circles.stroke_width),
        ";",
        stroke_style(color, opacity),
        fill_style(color, opacity),
        "' />\n"
      ]
    end)
  end

  # A rectangle fills its cell.
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
      number(rect.stroke_width),
      "; stroke: ",
      stroke(rect.color),
      "; fill: ",
      rect.fill,
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
        ["  <stop offset='", offset(offset), "' stop-color='", color, "' stop-opacity='1.00'/>\n"]
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
      number(gradient.stroke_width),
      "; stroke: none; fill: url(#",
      id,
      ");' />\n"
    ]
  end

  # Each rectangle as grid places one hung from its top left corner, as ggplot2's `GeomRect` hangs
  # it, its width and height the cell's share of its extent, its border its colour at its opacity
  # and its fill likewise.
  defp primitive(%Rectangles{} = rectangles, {{_left, width}, {_top, height}} = box) do
    columns = [
      rectangles.xmin,
      rectangles.xmax,
      rectangles.ymin,
      rectangles.ymax,
      rectangles.fill,
      rectangles.fill_opacity,
      rectangles.color,
      rectangles.color_opacity
    ]

    Enum.zip_with(columns, fn [xmin, xmax, ymin, ymax, fill, fill_opacity, color, color_opacity] ->
      {x_position, y_position} = place({xmin, ymax}, box)

      [
        "<rect x='",
        number(x_position),
        "' y='",
        number(y_position),
        "' width='",
        number((xmax - xmin) * width),
        "' height='",
        number((ymax - ymin) * height),
        "' style='stroke-width: ",
        number(rectangles.stroke_width),
        ";",
        stroke_style(color, color_opacity),
        " stroke-linecap: butt; stroke-linejoin: miter;",
        fill_style(fill, fill_opacity),
        "' />\n"
      ]
    end)
  end

  # Each line as svglite writes a polyline, its stroke its colour at its opacity.
  defp primitive(%Polylines{} = polylines, box) do
    lines = placed_lines(polylines, box)

    Enum.zip_with([lines, polylines.color, polylines.opacity], fn [line, color, opacity] ->
      [
        "<polyline points='",
        points(line),
        "' style='stroke-width: ",
        number(polylines.stroke_width),
        ";",
        stroke_style(color, opacity),
        line_style(polylines.line_end, polylines.line_join, polylines.mitre_limit),
        " fill: none;' />\n"
      ]
    end)
  end

  # Each segment as svglite writes a line, from its start to its end, its stroke its colour at its
  # opacity.
  defp primitive(%Segments{} = segments, box) do
    style = line_style(segments.line_end, segments.line_join, segments.mitre_limit)
    columns = [segments.starts, segments.ends, segments.color, segments.opacity]

    Enum.zip_with(columns, fn [start, finish, color, opacity] ->
      {x_start, y_start} = place(start, box)
      {x_finish, y_finish} = place(finish, box)

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
        number(segments.stroke_width),
        ";",
        stroke_style(color, opacity),
        style,
        "' />\n"
      ]
    end)
  end

  defp primitive(%Polygons{} = polygons, box) do
    style = [
      "style='stroke-width: ",
      number(polygons.stroke_width),
      "; stroke: ",
      stroke(polygons.color),
      "; fill: ",
      polygons.fill,
      ";'"
    ]

    Enum.map(polygons.outlines, fn outline ->
      placed = Enum.map(outline, fn position -> place(position, box) end)
      ["<polygon points='", points(placed), "' ", style, " />\n"]
    end)
  end

  defp primitive(%Text{} = text, box) do
    anchor = 0.5 * Float.floor(2 * text.hjust + 0.5)

    style = [
      "style='font-size: ",
      number(text.size),
      "px;",
      fill(text.color),
      " font-family: ",
      @font_family,
      ";'"
    ]

    columns = [text.x, text.y, text.labels, text.widths]
    {along, up} = text.offset

    Enum.zip_with(columns, fn [x_place, y_place, label, label_width] ->
      # The anchor, moved back along the baseline by the part of the label's width between where
      # svglite anchors it and its `hjust`.
      baseline =
        {x_place, y_place}
        |> place(box)
        |> along_text({along - (text.hjust - anchor) * label_width, up}, text.angle)

      [
        "<text",
        text_position(baseline, text.angle),
        text_anchor(anchor),
        " ",
        style,
        " textLength='",
        number(label_width),
        "px' lengthAdjust='spacingAndGlyphs'>",
        escape(label),
        "</text>\n"
      ]
    end)
  end

  # A position moved `along` a text's baseline and `up` toward its top, in points: rightward and
  # up the page for level text, up and leftward for text turned 90 degrees.
  defp along_text(position, {along, up}, 0), do: moved(position, {along, up})
  defp along_text(position, {along, up}, 90), do: moved(position, {-up, along})

  # svglite places level text by its `x` and `y`, and turned text by a transform, its angle negated
  # since SVG turns clockwise.
  defp text_position({x_position, y_position}, 0),
    do: [" x='", number(x_position), "' y='", number(y_position), "'"]

  defp text_position({x_position, y_position}, 90),
    do: [" transform='translate(", number(x_position), ",", number(y_position), ") rotate(-90)'"]

  # svglite writes no anchor for text anchored at its start, SVG's default.
  defp text_anchor(anchor) when anchor == 0.0, do: ""
  defp text_anchor(anchor) when anchor == 0.5, do: " text-anchor='middle'"
  defp text_anchor(anchor) when anchor == 1.0, do: " text-anchor='end'"

  # Placed lines, each point moved by its offset, if the lines carry any.
  defp placed_lines(%Polylines{lines: lines, offsets: :none}, box),
    do: Enum.map(lines, fn line -> Enum.map(line, fn position -> place(position, box) end) end)

  defp placed_lines(%Polylines{lines: lines, offsets: offsets}, box) do
    Enum.zip_with(lines, offsets, fn line, line_offsets ->
      Enum.zip_with(line, line_offsets, fn position, offset ->
        position
        |> place(box)
        |> moved(offset)
      end)
    end)
  end

  defp points(positions) do
    Enum.map(positions, fn {x_position, y_position} ->
      [number(x_position), ",", number(y_position), " "]
    end)
  end

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

  # A border of `:none` is SVG's `none`, as svglite writes a border whose colour is R's `NA`.
  defp stroke(:none), do: "none"
  defp stroke(color), do: color

  # svglite writes a text's fill only when it is not black, SVG's default.
  defp fill("#000000"), do: ""
  defp fill(color), do: [" fill: ", color, ";"]

  # The characters svglite escapes in text.
  defp escape(label) do
    label
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
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

  defp number(value), do: :erlang.float_to_binary(value / 1, decimals: 2)

  # A gradient stop's offset, as svglite writes one: as a number below 1 between the ends, and with
  # two decimals at them.
  defp offset(value) when value > 0 and value < 1, do: significant(value)
  defp offset(value), do: number(value)

  # A number between 0 and 1 as svglite's `write_double()` writes one: with as many decimals as
  # reach its first significant digit and one more, so 0.0235 is 0.024 and 0.0078 keeps its 78; from
  # 0.1 up, two. Only an opacity and a gradient stop's offset are written so, and only between 0
  # and 1; every other number keeps two decimals (`number/1`).
  defp significant(value) when value > 0 and value < 1 do
    decimals = ceil(-:math.log10(value)) + 1
    :erlang.float_to_binary(value, decimals: decimals)
  end
end
