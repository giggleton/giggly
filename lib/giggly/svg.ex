defmodule Giggly.SVG do
  @moduledoc false

  # Writes a `Giggly.Scene` as SVG.
  #
  # The table is laid out at the size it is given, in points (1/72 inch): each column or row with a
  # size in points takes it, and the columns that are `:rest` share what is left equally, as do the
  # rows. Each cell's box runs from the start of its first column and row to the end of its last,
  # or hangs a height of its own from the top of its first row, and its primitives are placed in
  # that box, cells in the order the scene lists them; a clipped cell's
  # are drawn in a group cut off at the box, as svglite writes one. The
  # document's user unit is the point, as svglite writes it: the `viewBox` is the size in points and
  # `width` and `height` carry `pt`, so a radius of 1.95 is 1.95 points at the size the plot is
  # shown. Numbers are written with two decimals, and each primitive as svglite writes it, so
  # output can be set beside the SVG ggplot2's own tests snapshot.
  #
  # Text is drawn in the fonts whose widths `Giggly.Font` measures with (Liberation Sans, Arial,
  # Helvetica) or else the browser's sans-serif, and each label is stretched or squeezed to its
  # measured width (svglite's `textLength`), so it fills the space measured for it whatever font
  # draws it.

  # The SVG backend reads the scene and nothing else.
  use Boundary, deps: [Giggly.Scene], exports: []

  alias Giggly.Scene
  alias Giggly.Scene.{Cell, Circles, Polylines, Rect, Text}

  @font_family ~S("Liberation Sans", Arial, Helvetica, sans-serif)

  # The SVG document that draws `scene` at `width` by `height` points, as grid's `grid.draw()` puts
  # a finished table on a device.
  @doc false
  @spec draw(Scene.t(), number(), number()) :: iodata()
  def draw(%Scene{widths: widths, heights: heights, cells: cells}, width, height) do
    column_spans = lay_out(widths, width)
    row_spans = lay_out(heights, height)

    [
      "<svg xmlns='http://www.w3.org/2000/svg' width='",
      number(width),
      "pt' height='",
      number(height),
      "pt' viewBox='0 0 ",
      number(width),
      " ",
      number(height),
      "'>\n",
      Enum.map(cells, fn cell -> cell(cell, column_spans, row_spans) end),
      "</svg>\n"
    ]
  end

  # Each column's or row's start and length along the drawing: sizes in points take their length,
  # and each `:rest` an equal share of what they leave.
  defp lay_out(sizes, total) do
    {fixed_sizes, rests} = Enum.split_with(sizes, fn size -> size != :rest end)
    rest = (total - Enum.sum(for {:points, length} <- fixed_sizes, do: length)) / length(rests)

    {spans, _end} =
      Enum.map_reduce(sizes, 0, fn size, start ->
        length = span_length(size, rest)
        {{start, length}, start + length}
      end)

    spans
  end

  defp span_length({:points, length}, _rest), do: length
  defp span_length(:rest, rest), do: rest

  defp cell(%Cell{rows: rows, columns: columns} = cell, column_spans, row_spans) do
    box = {span(column_spans, columns), hang(span(row_spans, rows), cell.hang)}
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

  # A hanging cell's rows: from their top, as tall as it says.
  defp hang(rows, :none), do: rows
  defp hang({top, _height}, {:top, height}), do: {top, height}

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

  defp primitive(%Circles{} = circles, box) do
    style = [
      "style='stroke-width: ",
      number(circles.stroke_width),
      "; stroke: ",
      circles.color,
      "; fill: ",
      circles.color,
      ";'"
    ]

    Enum.zip_with(circles.x, circles.y, fn x_place, y_place ->
      {x_position, y_position} = place({x_place, y_place}, box)

      [
        "<circle cx='",
        number(x_position),
        "' cy='",
        number(y_position),
        "' r='",
        number(circles.radius),
        "' ",
        style,
        " />\n"
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

  defp primitive(%Polylines{} = polylines, box) do
    style = [
      "style='stroke-width: ",
      number(polylines.stroke_width),
      "; stroke: ",
      polylines.color,
      "; stroke-linecap: butt;'"
    ]

    Enum.map(polylines.lines, fn line ->
      points =
        Enum.map(line, fn position ->
          {x_position, y_position} = place(position, box)
          [number(x_position), ",", number(y_position), " "]
        end)

      ["<polyline points='", points, "' ", style, " />\n"]
    end)
  end

  defp primitive(%Text{} = text, box) do
    anchor = text_anchor(text.anchor)

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

    Enum.zip_with(columns, fn [x_place, y_place, label, label_width] ->
      baseline =
        {x_place, y_place}
        |> place(box)
        |> baseline(text.baseline_offset, text.angle)

      [
        "<text",
        text_position(baseline, text.angle),
        anchor,
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

  # The baseline sits `baseline_offset` points toward the text's top: up, which is SVG's lower y,
  # for level text, and left for text turned 90 degrees.
  defp baseline({x_position, y_position}, offset, 0), do: {x_position, y_position - offset}
  defp baseline({x_position, y_position}, offset, 90), do: {x_position - offset, y_position}

  # svglite places level text by its `x` and `y`, and turned text by a transform, its angle negated
  # since SVG turns clockwise.
  defp text_position({x_position, y_position}, 0),
    do: [" x='", number(x_position), "' y='", number(y_position), "'"]

  defp text_position({x_position, y_position}, 90),
    do: [" transform='translate(", number(x_position), ",", number(y_position), ") rotate(-90)'"]

  defp text_anchor(:middle), do: " text-anchor='middle'"
  defp text_anchor(:end), do: " text-anchor='end'"

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

  defp number(value), do: :erlang.float_to_binary(value / 1, decimals: 2)
end
