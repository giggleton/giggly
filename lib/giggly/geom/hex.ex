defmodule Giggly.Geom.Hex do
  @moduledoc false

  # Hexagons, ggplot2's `GeomHex`, which `geom_hex()` draws with: one per row, centred on its `x`
  # and `y`. Its parameters are how a hexagon's border is drawn at its ends (`line_end`), its
  # corners (`line_join`) and how far a pointed corner reaches (`mitre_limit`), ggplot2's
  # `lineend`, `linejoin` and `linemitre`. Use it through `Giggly.Geom`.
  #
  # Hexagons use `:x`, `:y`, `:group`, `:alpha`, `:color`, `:fill`, `:linetype` and `:linewidth`;
  # what they cannot be drawn without, `:x` and `:y`, the stat before them needs, so a layer is
  # checked against the stat's requirements. Each is as wide and high as its group's first row's
  # `width` and `height`, which hexagonal binning (`Giggly.Stat.BinHex`) gives every row, so a
  # hexagon is drawn only after it.
  #
  # A hexagon is drawn as ggplot2's `GeomHex` draws one: its six corners, as hexbin's
  # `hexcoords()` sets them round its centre, half its width across and its height over √3 and
  # over 2 up, twice that at its top and bottom, so it stands on a point and its sides are upright;
  # each corner placed through the coordinate system (`Giggly.Coord.transform/3`), never munched,
  # so under coordinates that curve its sides stay straight between its placed corners. Each panel's
  # hexagons are drawn group by group, in row order, filled with its row's fill at its alpha and
  # bordered in its row's colour at the colour's own alpha, as ggplot2's `GeomHex` applies
  # `fill_alpha()` to the fill alone, as wide as its row's `linewidth`, in millimetres, and in its
  # row's line type, dashed as svglite writes it (`Mark.dashes/2`), a blank one leaving it
  # unbordered, each run of hexagons whose borders are as wide and dashed alike one primitive. A
  # row missing its place is not drawn.
  #
  # A hexagon the layer neither maps nor sets a look for looks as ggplot2's default hexagon does
  # under the plot's theme: filled with the theme's ink mixed halfway toward its paper, `#808080`
  # on white paper, unbordered, its border's width and line type the theme's borders'. Its legend
  # key is ggplot2's `draw_key_polygon()`, with the layer's ends and corners.

  @enforce_keys [:line_end, :line_join, :mitre_limit]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          line_end: Giggly.Scene.Polylines.line_end(),
          line_join: Giggly.Scene.Polylines.line_join(),
          mitre_limit: float()
        }

  # The aesthetics a layer of hexagons can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics,
    do: [:alpha, :color, :fill, :group, :linetype, :linewidth, :x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Geom.{Mark, Rect}
    alias Giggly.Scene.Polygons
    alias Scales.ColorOperations

    # How far a hexagon's default fill is mixed from the theme's ink toward its paper, ggplot2's
    # `col_mix(ink, paper)`, whose amount is half by default.
    @fill_toward_paper 0.5

    # Points in a millimetre, grid's `"mm"` in the scene's points: a key's fill is its border's
    # width short of the key each way, as ggplot2's `draw_key_polygon()` takes `linewidth`
    # millimetres off it, half each side, and needs that width twice.
    @points_per_millimetre 72 / 25.4

    @root_three 1.7320508075688772

    # ggplot2's `GeomHex$default_aes`: no border, a fill of the theme's ink mixed toward its paper,
    # and the theme's borders' width and line type.
    @impl Giggly.Geom
    def default_aesthetics(_geom, element) do
      [
        color: nil,
        fill: ColorOperations.mix(element.ink, element.paper, @fill_toward_paper),
        linewidth: element.borderwidth,
        linetype: element.bordertype,
        alpha: nil
      ]
    end

    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds), do: frame

    # The panel's hexagons, group by group, each round its centre, placed in the panel, in its
    # fill and border.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params, _installed_fonts) do
      fills = Mark.colors(frame, :fill)

      [:group, :x, :y, :width, :height]
      |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
      |> Enum.concat([
        fills,
        Mark.opacities(frame, fills),
        Mark.colors(frame, :color),
        DataFrame.pull(frame, :linewidth),
        Mark.line_types(frame)
      ])
      |> Enum.zip_with(fn [
                            group,
                            x,
                            y,
                            width,
                            height,
                            fill,
                            fill_opacity,
                            color,
                            line_width,
                            line_type
                          ] ->
        %{
          group: group,
          centre: {x, y},
          size: {width, height},
          fill: fill,
          fill_opacity: fill_opacity,
          border: Rect.border(color, line_width, line_type),
          line: {line_width || 0.0, line_type}
        }
      end)
      |> Enum.filter(fn %{centre: {x, y}} -> is_number(x) and is_number(y) end)
      |> Enum.chunk_by(fn hexagon -> hexagon.group end)
      |> Enum.flat_map(&sized/1)
      |> placed(coord, panel_params)
      |> Enum.chunk_by(fn hexagon -> hexagon.line end)
      |> Enum.map(fn drawn -> polygons(drawn, geom) end)
    end

    # A group's hexagons, each its six corners round its centre at the size its group's first row
    # gives, as `GeomHex$draw_group()` reads `width[1]` and `height[1]`.
    defp sized([%{size: {width, height}} | _rest] = group) do
      across = Arithmetic.divide(width, 2)

      up =
        height
        |> Arithmetic.divide(@root_three)
        |> Arithmetic.divide(2)

      twice_up = Arithmetic.multiply(2, up)

      offsets = [
        {across, up},
        {across, Arithmetic.multiply(-1, up)},
        {0.0, Arithmetic.multiply(-1, twice_up)},
        {Arithmetic.multiply(-1, across), Arithmetic.multiply(-1, up)},
        {Arithmetic.multiply(-1, across), up},
        {0.0, twice_up}
      ]

      Enum.map(group, fn %{centre: centre} = hexagon ->
        Map.put(hexagon, :offsets, {centre, offsets})
      end)
    end

    # The hexagons with their corners placed in the panel, all at once, as `GeomHex` transforms
    # them together.
    defp placed(hexagons, coord, panel_params) do
      {xs, ys} =
        hexagons
        |> Enum.flat_map(fn %{offsets: {{x, y}, offsets}} ->
          Enum.map(offsets, fn {across, up} ->
            {Arithmetic.add(x, across), Arithmetic.add(y, up)}
          end)
        end)
        |> Enum.unzip()

      corners = Coord.transform(coord, DataFrame.new(x: xs, y: ys), panel_params)

      outlines =
        corners
        |> DataFrame.pull(:x)
        |> Enum.zip(DataFrame.pull(corners, :y))
        |> Enum.chunk_every(6)

      Enum.zip_with(hexagons, outlines, fn hexagon, outline ->
        Map.put(hexagon, :outline, outline)
      end)
    end

    # A run of hexagons whose borders are as wide and dashed alike.
    defp polygons([%{line: {width, line_type}} | _rest] = drawn, geom) do
      %Polygons{
        outlines: Enum.map(drawn, fn hexagon -> hexagon.outline end),
        offsets: :none,
        stroke_width: Mark.stroke_width(width),
        color: Enum.map(drawn, fn hexagon -> Mark.hex(hexagon.border) end),
        color_opacity: Enum.map(drawn, fn hexagon -> Mark.own_opacity(hexagon.border) end),
        fill: Enum.map(drawn, fn hexagon -> Mark.hex(hexagon.fill) end),
        fill_opacity: Enum.map(drawn, fn hexagon -> hexagon.fill_opacity end),
        dashes: Mark.dashes(line_type, width),
        line_end: geom.line_end,
        line_join: geom.line_join,
        mitre_limit: geom.mitre_limit
      }
    end

    # A legend's key, `draw_key_polygon()`'s, its ends and corners the layer's.
    @impl Giggly.Geom
    def draw_key(geom, key, _installed_fonts),
      do: Rect.polygon_key(key, geom.line_end, geom.line_join)

    # The room a key's rectangle needs, its border's width twice, in millimetres, either way, as
    # ggplot2's `draw_key_polygon()` sizes its glyph, `linewidth / 5` centimetres; a missing width
    # needs none.
    @impl Giggly.Geom
    def key_size(_geom, key, _installed_fonts) do
      side =
        case Map.fetch!(key, :linewidth) do
          nil -> 0.0
          line_width -> 2 * line_width * @points_per_millimetre
        end

      {side, side}
    end
  end
end
