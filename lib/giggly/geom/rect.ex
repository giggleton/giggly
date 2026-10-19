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
  # ggplot2's snapshots write it, or filled and bordered in its row's colours, mapped or set,
  # `:none`, R's `NA`, or missing, leaving it unfilled or unbordered. A row's `alpha`, where its table has one,
  # makes the rectangle's fill that opaque, replacing the fill's own alpha, and leaves its border in
  # its colour's own, as ggplot2's `GeomRect` applies `fill_alpha()` to the fill alone; a row
  # without one keeps its fill's (`Giggly.Geom.Mark`). Its legend key is its fill short of the key
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

    # ggplot2's default rectangle: its fill, and its border's width, 0.5 mm, in points as grid
    # draws a line.
    @fill "#595959"
    @stroke_width 0.5 * 72.27 / 25.4 * 72 / 96

    # A key's fill is its border's width, 0.5 mm, short of the key each way, as ggplot2's
    # `draw_key_polygon()` takes `linewidth` millimetres off it: half each side, in points.
    @key_inset 0.5 * 72 / 25.4 / 2

    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds), do: frame

    # A rectangle for each row placed in the panel, in its fill and border.
    @impl Giggly.Geom
    def draw_panel(_geom, frame, coord, panel_params) do
      placed = Coord.transform(coord, frame, panel_params)
      fills = Mark.colors(placed, :fill, @fill)

      drawn =
        [:xmin, :xmax, :ymin, :ymax]
        |> Enum.map(fn name -> DataFrame.pull(placed, name) end)
        |> Enum.concat([
          fills,
          Mark.opacities(placed, fills),
          Mark.colors(placed, :color, :none)
        ])
        |> Enum.zip_with(fn [xmin, xmax, ymin, ymax, fill, fill_opacity, border] ->
          %{
            extent: [xmin, xmax, ymin, ymax],
            fill: fill,
            fill_opacity: fill_opacity,
            border: border
          }
        end)
        |> Enum.filter(fn rectangle -> Enum.all?(rectangle.extent, &is_number/1) end)

      [
        %Rectangles{
          xmin: Enum.map(drawn, fn %{extent: [xmin, _xmax, _ymin, _ymax]} -> xmin end),
          xmax: Enum.map(drawn, fn %{extent: [_xmin, xmax, _ymin, _ymax]} -> xmax end),
          ymin: Enum.map(drawn, fn %{extent: [_xmin, _xmax, ymin, _ymax]} -> ymin end),
          ymax: Enum.map(drawn, fn %{extent: [_xmin, _xmax, _ymin, ymax]} -> ymax end),
          fill: Enum.map(drawn, fn rectangle -> Mark.hex(rectangle.fill) end),
          fill_opacity: Enum.map(drawn, fn rectangle -> rectangle.fill_opacity end),
          color: Enum.map(drawn, fn rectangle -> Mark.hex(rectangle.border) end),
          color_opacity: Enum.map(drawn, fn rectangle -> Mark.own_opacity(rectangle.border) end),
          stroke_width: @stroke_width
        }
      ]
    end

    # A legend's key: the rectangle's fill short of the key's edges by its border's width, as
    # ggplot2's `draw_key_polygon()` draws it, in the key's fill at its alpha and its border's
    # colour.
    @impl Giggly.Geom
    def draw_key(_geom, key, {width, height}) do
      fill = Map.get(key, :fill, @fill)
      border = Map.get(key, :color, :none)

      [
        %Rectangles{
          xmin: [@key_inset / width],
          xmax: [1 - @key_inset / width],
          ymin: [@key_inset / height],
          ymax: [1 - @key_inset / height],
          fill: [Mark.hex(fill)],
          fill_opacity: [Mark.opacity(fill, Map.get(key, :alpha))],
          color: [Mark.hex(border)],
          color_opacity: [Mark.own_opacity(border)],
          stroke_width: @stroke_width
        }
      ]
    end
  end
end
