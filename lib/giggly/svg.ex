defmodule Giggly.SVG do
  @moduledoc """
  Writes a `Giggly.Scene` as SVG.

  The table is laid out at the size it is given, in points (1/72 inch): each column or row with a
  size in points takes it, and the one column and the one row that are `:rest` take what is left.
  A scene with more than one of either is refused (`MatchError`) until panels can share the rest.
  Each cell's
  primitives are then placed in the cell's box, cells in the order the scene lists them. The
  document's user unit is the point, as svglite writes it: the `viewBox` is the size in points and
  `width` and `height` carry `pt`, so a radius of 1.95 is 1.95 points at the size the plot is
  shown. Numbers are written with two decimals, and each primitive as svglite writes it, so
  output can be set beside the SVG ggplot2's own tests snapshot.

  Text is drawn in the fonts whose widths `Giggly.Font` measures with (Liberation Sans, Arial,
  Helvetica) or else the browser's sans-serif, and each label is stretched or squeezed to its
  measured width (svglite's `textLength`), so it fills the space measured for it whatever font
  draws it.
  """

  # The SVG backend reads the scene and nothing else.
  use Boundary, deps: [Giggly.Scene], exports: []

  alias Giggly.Scene
  alias Giggly.Scene.{Cell, Points, Polylines, Text}

  @font_family ~S("Liberation Sans", Arial, Helvetica, sans-serif)

  @doc """
  The SVG document that draws `scene` at `width` by `height` points, as grid's `grid.draw()` puts a
  finished table on a device.
  """
  @spec draw(Scene.t(), number(), number()) :: iodata()
  def draw(%Scene{widths: widths, heights: heights, cells: cells}, width, height) do
    columns = lay_out(widths, width)
    rows = lay_out(heights, height)

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
      Enum.map(cells, fn cell -> cell(cell, columns, rows) end),
      "</svg>\n"
    ]
  end

  # Each column's or row's start and length along the drawing: sizes in points take their length,
  # and the one `:rest` takes what they leave.
  defp lay_out(sizes, total) do
    {fixed_sizes, [:rest]} = Enum.split_with(sizes, fn size -> size != :rest end)
    rest = total - Enum.sum(for {:points, length} <- fixed_sizes, do: length)

    {spans, _end} =
      Enum.map_reduce(sizes, 0, fn size, start ->
        length = span_length(size, rest)
        {{start, length}, start + length}
      end)

    spans
  end

  defp span_length({:points, length}, _rest), do: length
  defp span_length(:rest, rest), do: rest

  defp cell(%Cell{row: row, column: column, primitives: primitives}, columns, rows) do
    box = {Enum.at(columns, column - 1), Enum.at(rows, row - 1)}
    Enum.map(primitives, fn primitive -> primitive(primitive, box) end)
  end

  # A cell's y runs up from its bottom edge; SVG's runs down from the top.
  defp place({x, y}, {{left, width}, {top, height}}),
    do: {left + x * width, top + (1 - y) * height}

  defp primitive(%Points{} = points, box) do
    style = [
      "style='stroke-width: ",
      number(points.stroke_width),
      "; stroke: ",
      points.color,
      "; fill: ",
      points.color,
      ";'"
    ]

    points.x
    |> Enum.zip(points.y)
    |> Enum.map(fn position ->
      {x_position, y_position} = place(position, box)

      [
        "<circle cx='",
        number(x_position),
        "' cy='",
        number(y_position),
        "' r='",
        number(points.radius),
        "' ",
        style,
        " />\n"
      ]
    end)
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

  # The baseline sits `baseline_offset` points above the label's point, and SVG's y runs down.
  defp primitive(%Text{} = text, box) do
    anchor = text_anchor(text.anchor)

    style = [
      "style='font-size: ",
      number(text.size),
      "px; fill: ",
      text.color,
      "; font-family: ",
      @font_family,
      ";'"
    ]

    [text.x, text.y, text.labels, text.widths]
    |> Enum.zip()
    |> Enum.map(fn {x_place, y_place, label, label_width} ->
      {x_position, y_position} = place({x_place, y_place}, box)

      [
        "<text x='",
        number(x_position),
        "' y='",
        number(y_position - text.baseline_offset),
        "'",
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

  defp text_anchor(:middle), do: " text-anchor='middle'"
  defp text_anchor(:end), do: " text-anchor='end'"

  # The characters svglite escapes in text.
  defp escape(label) do
    label
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp number(value), do: :erlang.float_to_binary(value / 1, decimals: 2)
end
