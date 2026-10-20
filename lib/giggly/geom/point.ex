defmodule Giggly.Geom.Point do
  @moduledoc false

  # Points, ggplot2's `geom_point()`: one per row, at its `x` and `y`, drawn in its shape. It takes
  # no parameters. Draw it through `Giggly.Geom`.
  #
  # Points use `:x`, `:y`, `:group`, `:alpha`, `:color` and `:fill`, and need `:x` and `:y`; an
  # aesthetic joins the accepted list with the scale that maps it, so a mapping never silently does
  # nothing. A layer may also set each point's `:shape`, `:size` and `:stroke`, which no scale maps
  # yet.
  #
  # A row whose `x` or `y` is missing (`nil`, or the float `:nan`) is not drawn, as ggplot2 drops
  # it; ggplot2 also warns, which a pure pipeline cannot. An infinite position is drawn at the
  # panel's edge, where the coordinate system puts it.
  #
  # A point is drawn in its row's shape, one of the 26 R's graphics engine draws
  # (`Giggly.Geom.Shape`), worked out as ggplot2's `GeomPoint` hands it to grid: its font size is
  # `size * .pt + stroke * .stroke / 2` points, and its outline `stroke * .stroke / 2` line-width
  # units wide, from the row's size and stroke in millimetres; a stroke of `:none`, R's `NA`, or a
  # missing one, adds nothing to the size and draws no outline and no lines. Unless a layer sets
  # them, a point looks as ggplot2's default point does: the solid circle, `:circle` (R's 19), of
  # size 1.5 with a 0.5 border, which grid draws with a radius of 1.95 points and a 0.71-point
  # outline, the figures in ggplot2's own SVG test snapshots; black, or its row's colour, mapped or
  # set; and no fill, or its row's fill, mapped or set. Its colour outlines the shape and fills the
  # shapes R fills in a point's colour, and its fill fills shapes 21 to 25. A row's `alpha`, where
  # its table has one, makes both that opaque, replacing their own, as ggplot2's `alpha()` and
  # `fill_alpha()` do; a row without one keeps each colour's, which is opaque unless the colour
  # carries an alpha, as ggplot2's default alpha, `NA`, leaves a colour (`Giggly.Geom.Mark`). A row
  # whose colour is `:none`, R's `NA`, or missing, as a scale's `na_value: :none` leaves it, draws
  # no point, as ggplot2's `GeomPoint` drops a row whose colour is missing, and so does a row whose
  # shape is `:none` or missing.
  #
  # Points are drawn in row order, each point's elements in the order R draws them, so points that
  # overlap stack as R's do: each run of elements of one kind and one outline width is one
  # primitive.

  alias Giggly.Geom.Shape

  defstruct []

  @type t :: %__MODULE__{}

  # The aesthetics a layer of points can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:alpha, :color, :fill, :group, :x, :y]

  # The aesthetics a layer of points cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  # The shapes a point is drawn in, by name, in the order of R's numbers for them, 0 to 25, which
  # `Giggly.Plot` turns a number into.
  @doc false
  @spec shapes() :: [atom()]
  def shapes, do: Shape.names()

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame}
    alias Giggly.Geom.{Mark, Shape}
    alias Giggly.Scene.{Circles, Polygons, Rectangles, Segments}

    # ggplot2's default point: its shape, its size and border width in millimetres, its ink, and
    # no fill.
    @shape :circle
    @size 1.5
    @stroke 0.5
    @color "#000000"
    @fill :none

    # ggplot2's `.pt` (font points per millimetre) and `.stroke` (line-width units, 1/96 inch, per
    # millimetre), and a line-width unit in points, as svglite writes a line's width.
    @font_points_per_millimetre 72.27 / 25.4
    @line_width_units_per_millimetre 96 / 25.4
    @points_per_line_width_unit 72 / 96

    # grid's default line ends, corners and mitre limit, which a point's lines are drawn with.
    @line_end :round
    @line_join :round
    @mitre_limit 10.0

    # A point is drawn at its x and y alone.
    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds), do: frame

    # Each row placed in the panel, in its shape, size, stroke, colour and fill, but a row whose
    # colour or shape is `:none`.
    @impl Giggly.Geom
    def draw_panel(_geom, frame, coord, panel_params) do
      placed = Coord.transform(coord, frame, panel_params)
      colors = Mark.colors(placed, :color, @color)
      fills = Mark.colors(placed, :fill, @fill)

      [
        DataFrame.pull(placed, :x),
        DataFrame.pull(placed, :y),
        Mark.values(placed, :shape, @shape),
        Mark.values(placed, :size, @size),
        Mark.values(placed, :stroke, @stroke),
        colors,
        Mark.opacities(placed, colors),
        fills,
        Mark.opacities(placed, fills)
      ]
      |> Enum.zip_with(fn [
                            x_position,
                            y_position,
                            shape,
                            size,
                            stroke,
                            color,
                            color_opacity,
                            fill,
                            fill_opacity
                          ] ->
        %{
          place: {x_position, y_position},
          shape: shape,
          size: size,
          stroke: stroke,
          color: {color, color_opacity},
          fill: {fill, fill_opacity}
        }
      end)
      |> Enum.filter(&drawn?/1)
      |> primitives()
    end

    # A legend's key: the point at the middle of the key, as ggplot2's `draw_key_point()` draws
    # it, in the key's shape, size, stroke, colour and fill at its alpha; a colour or shape of
    # `:none` draws nothing.
    @impl Giggly.Geom
    def draw_key(_geom, key, _size) do
      color = Map.get(key, :color, @color)
      fill = Map.get(key, :fill, @fill)
      alpha = Map.get(key, :alpha)

      point = %{
        place: {0.5, 0.5},
        shape: Map.get(key, :shape, @shape),
        size: Map.get(key, :size, @size),
        stroke: Map.get(key, :stroke, @stroke),
        color: {color, Mark.opacity(color, alpha)},
        fill: {fill, Mark.opacity(fill, alpha)}
      }

      [point]
      |> Enum.filter(&drawn?/1)
      |> primitives()
    end

    defp drawn?(%{place: {x_position, y_position}, shape: shape, color: {color, _opacity}}) do
      is_number(x_position) and is_number(y_position) and color != :none and
        shape not in [nil, :none]
    end

    # The points' elements in order, each run of one kind and one outline width a primitive.
    defp primitives(points) do
      points
      |> Enum.flat_map(&marks/1)
      |> Enum.chunk_by(fn mark -> {mark.kind, mark.stroke_width} end)
      |> Enum.map(&primitive/1)
    end

    # The elements a point is drawn with, each at the point's place, its outline and fill painted.
    # A stroke of `:none`, or a missing one, adds nothing to the point's size, outlines nothing and
    # draws none of its segments, as R's graphics engine draws a border of no width transparent
    # and a line of no width not at all.
    defp marks(%{stroke: stroke} = point) when stroke in [nil, :none] do
      point.shape
      |> Shape.elements(point.size * @font_points_per_millimetre)
      |> Enum.reject(fn element -> match?({:segment, _start, _finish}, element) end)
      |> Enum.map(fn element -> %{mark(element, point, 0.0) | outline: {:none, 0.0}} end)
    end

    defp marks(point) do
      outline = point.stroke * @line_width_units_per_millimetre / 2
      font_size = point.size * @font_points_per_millimetre + outline
      stroke_width = outline * @points_per_line_width_unit

      point.shape
      |> Shape.elements(font_size)
      |> Enum.map(fn element -> mark(element, point, stroke_width) end)
    end

    defp mark({:segment, start, finish}, point, stroke_width) do
      %{
        kind: :segment,
        stroke_width: stroke_width,
        place: point.place,
        geometry: {start, finish},
        outline: point.color,
        fill: {:none, 0.0}
      }
    end

    defp mark({kind, geometry, {outline, fill}}, point, stroke_width) do
      %{
        kind: kind,
        stroke_width: stroke_width,
        place: point.place,
        geometry: geometry,
        outline: paint(outline, point),
        fill: paint(fill, point)
      }
    end

    defp paint(:color, point), do: point.color
    defp paint(:fill, point), do: point.fill
    defp paint(:none, _point), do: {:none, 0.0}

    defp primitive([%{kind: :circle, stroke_width: stroke_width} | _rest] = marks) do
      %Circles{
        x: Enum.map(marks, fn %{place: {x_position, _y_position}} -> x_position end),
        y: Enum.map(marks, fn %{place: {_x_position, y_position}} -> y_position end),
        radius: geometries(marks),
        stroke_width: stroke_width,
        color: colors(marks, :outline),
        color_opacity: opacities(marks, :outline),
        fill: colors(marks, :fill),
        fill_opacity: opacities(marks, :fill)
      }
    end

    # A square is a rectangle at the point's place, its corners half its side away each way.
    defp primitive([%{kind: :square, stroke_width: stroke_width} | _rest] = marks) do
      x_places = Enum.map(marks, fn %{place: {x_position, _y_position}} -> x_position end)
      y_places = Enum.map(marks, fn %{place: {_x_position, y_position}} -> y_position end)

      %Rectangles{
        xmin: x_places,
        xmax: x_places,
        ymin: y_places,
        ymax: y_places,
        offsets: Enum.map(marks, fn %{geometry: half} -> {{-half, -half}, {half, half}} end),
        fill: colors(marks, :fill),
        fill_opacity: opacities(marks, :fill),
        color: colors(marks, :outline),
        color_opacity: opacities(marks, :outline),
        stroke_width: stroke_width,
        line_end: @line_end,
        line_join: @line_join,
        mitre_limit: @mitre_limit
      }
    end

    # A polygon's corners are each at the point's place, moved by their offsets.
    defp primitive([%{kind: :polygon, stroke_width: stroke_width} | _rest] = marks) do
      %Polygons{
        outlines:
          Enum.map(marks, fn %{place: place, geometry: corners} ->
            List.duplicate(place, length(corners))
          end),
        offsets: geometries(marks),
        stroke_width: stroke_width,
        color: colors(marks, :outline),
        color_opacity: opacities(marks, :outline),
        fill: colors(marks, :fill),
        fill_opacity: opacities(marks, :fill)
      }
    end

    # A segment's ends are both at the point's place, moved by their offsets.
    defp primitive([%{kind: :segment, stroke_width: stroke_width} | _rest] = marks) do
      places = Enum.map(marks, fn %{place: place} -> place end)

      %Segments{
        starts: places,
        ends: places,
        offsets: geometries(marks),
        stroke_width: stroke_width,
        color: colors(marks, :outline),
        opacity: opacities(marks, :outline),
        line_end: @line_end,
        line_join: @line_join,
        mitre_limit: @mitre_limit
      }
    end

    defp geometries(marks), do: Enum.map(marks, fn %{geometry: geometry} -> geometry end)

    defp colors(marks, side) do
      Enum.map(marks, fn mark ->
        {color, _opacity} = Map.fetch!(mark, side)
        Mark.hex(color)
      end)
    end

    defp opacities(marks, side) do
      Enum.map(marks, fn mark ->
        {_color, opacity} = Map.fetch!(mark, side)
        opacity
      end)
    end
  end
end
