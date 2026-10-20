defmodule Giggly.Geom.Rect do
  @moduledoc false

  # Rectangles, ggplot2's `GeomRect`: one per row, from its `xmin` to its `xmax` and its `ymin` to
  # its `ymax`. It takes no parameters yet. Use it through `Giggly.Geom`. Bars (`Giggly.Geom.Bar`)
  # are drawn as rectangles once their edges are worked out, as ggplot2's `GeomBar` is a `GeomRect`.
  #
  # Rectangles use `:xmin`, `:xmax`, `:ymin`, `:ymax`, `:group`, `:alpha`, `:color` and `:fill`, and
  # need all four corners, each mapped or set; an aesthetic joins the accepted list with the scale
  # that maps it, so a mapping never silently does nothing. ggplot2 4.0 also places a rectangle by
  # its centre and size (`x` and `width`, `y` and `height`), which waits.
  #
  # A rectangle is drawn where its corners are, which the build leaves as they are, so a row whose
  # `xmin` is past its `xmax` is drawn between them all the same, as grid draws one. A row missing a
  # corner is not drawn, and an infinite one reaches the panel's edge, where the coordinate system
  # puts it.
  #
  # Every rectangle looks as ggplot2's default rectangle does: filled with ink mixed 35% toward
  # paper, `#595959`, with no border, its border's width the theme's 0.5 mm all the same, as
  # ggplot2's snapshots write it, and solid, or filled and bordered in its row's colours, mapped or
  # set, `:none`, R's `NA`, or missing, leaving it unfilled or unbordered, its border as wide as its
  # row's `linewidth`, in millimetres, and in its row's line type, dashed as svglite writes it
  # (`Mark.dashes/2`), a blank one leaving it unbordered, as R's graphics engine draws a blank
  # border transparent. A row's `alpha`, where its table has one, makes the rectangle's fill that
  # opaque, replacing the fill's own alpha, and leaves its border in its colour's own, as ggplot2's
  # `GeomRect` applies `fill_alpha()` to the fill alone; a row without one keeps its fill's
  # (`Giggly.Geom.Mark`). The rectangles are drawn in row order, each run of rectangles whose
  # borders are as wide and dashed alike one primitive. Its legend key is its fill short of the key
  # by its border's width, as `draw_key_polygon()` draws it.

  defstruct []

  @type t :: %__MODULE__{}

  # The aesthetics a layer of rectangles can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:alpha, :color, :fill, :group, :xmax, :xmin, :ymax, :ymin]

  # The aesthetics a layer of rectangles cannot be drawn without, each mapped or set.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:xmax, :xmin, :ymax, :ymin]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame}
    alias Giggly.Geom.Mark
    alias Giggly.Scene.Rectangles

    # ggplot2's default rectangle: its fill, its border's width in millimetres, and its border's
    # line type, solid.
    @fill "#595959"
    @line_width 0.5
    @line_type {}

    # Points in a millimetre: a key's fill is its border's width short of the key each way, as
    # ggplot2's `draw_key_polygon()` takes `linewidth` millimetres off it, half each side.
    @points_per_millimetre 72 / 25.4

    # ggplot2's `GeomRect` draws its rectangles' corners mitred and their ends cut square, grid's
    # `linejoin = "mitre"` and `lineend = "butt"`, at grid's mitre limit.
    @line_end :butt
    @line_join :mitre
    @mitre_limit 10.0

    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds), do: frame

    # A rectangle for each row placed in the panel, in its fill and border.
    @impl Giggly.Geom
    def draw_panel(_geom, frame, coord, panel_params) do
      placed = Coord.transform(coord, frame, panel_params)
      fills = Mark.colors(placed, :fill, @fill)

      [:xmin, :xmax, :ymin, :ymax]
      |> Enum.map(fn name -> DataFrame.pull(placed, name) end)
      |> Enum.concat([
        fills,
        Mark.opacities(placed, fills),
        Mark.colors(placed, :color, :none),
        Mark.values(placed, :linewidth, @line_width),
        Mark.line_types(placed)
      ])
      |> Enum.zip_with(fn [xmin, xmax, ymin, ymax, fill, fill_opacity, color, width, line_type] ->
        %{
          extent: [xmin, xmax, ymin, ymax],
          fill: fill,
          fill_opacity: fill_opacity,
          border: border(color, line_type),
          line: {width, line_type}
        }
      end)
      |> Enum.filter(fn rectangle -> Enum.all?(rectangle.extent, &is_number/1) end)
      |> Enum.chunk_by(fn rectangle -> rectangle.line end)
      |> Enum.map(&rectangles/1)
    end

    # A run of rectangles whose borders are as wide and dashed alike.
    defp rectangles([%{line: {width, line_type}} | _rest] = drawn) do
      %Rectangles{
        xmin: Enum.map(drawn, fn %{extent: [xmin, _xmax, _ymin, _ymax]} -> xmin end),
        xmax: Enum.map(drawn, fn %{extent: [_xmin, xmax, _ymin, _ymax]} -> xmax end),
        ymin: Enum.map(drawn, fn %{extent: [_xmin, _xmax, ymin, _ymax]} -> ymin end),
        ymax: Enum.map(drawn, fn %{extent: [_xmin, _xmax, _ymin, ymax]} -> ymax end),
        offsets: :none,
        fill: Enum.map(drawn, fn rectangle -> Mark.hex(rectangle.fill) end),
        fill_opacity: Enum.map(drawn, fn rectangle -> rectangle.fill_opacity end),
        color: Enum.map(drawn, fn rectangle -> Mark.hex(rectangle.border) end),
        color_opacity: Enum.map(drawn, fn rectangle -> Mark.own_opacity(rectangle.border) end),
        stroke_width: Mark.stroke_width(width),
        dashes: Mark.dashes(line_type, width),
        line_end: @line_end,
        line_join: @line_join,
        mitre_limit: @mitre_limit
      }
    end

    # A border's colour in its line type: none where it is blank.
    defp border(_color, :none), do: :none
    defp border(color, _line_type), do: color

    # A legend's key: the rectangle's fill short of the key's edges by its border's width, as
    # ggplot2's `draw_key_polygon()` draws it, in the key's fill at its alpha and its border's
    # colour, width and line type.
    @impl Giggly.Geom
    def draw_key(_geom, key, {width, height}) do
      fill = Map.get(key, :fill, @fill)
      line_width = Map.get(key, :linewidth, @line_width)
      line_type = Map.get(key, :linetype, @line_type)
      border = border(Map.get(key, :color, :none), line_type)
      inset = line_width * @points_per_millimetre / 2

      [
        %Rectangles{
          xmin: [inset / width],
          xmax: [1 - inset / width],
          ymin: [inset / height],
          ymax: [1 - inset / height],
          offsets: :none,
          fill: [Mark.hex(fill)],
          fill_opacity: [Mark.opacity(fill, Map.get(key, :alpha))],
          color: [Mark.hex(border)],
          color_opacity: [Mark.own_opacity(border)],
          stroke_width: Mark.stroke_width(line_width),
          dashes: Mark.dashes(line_type, line_width),
          line_end: @line_end,
          line_join: @line_join,
          mitre_limit: @mitre_limit
        }
      ]
    end
  end
end
