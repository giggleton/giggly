defmodule Giggly.Geom.Violin do
  @moduledoc false

  # Violins, ggplot2's `GeomViolin`, which `geom_violin()` draws with: for each group a polygon round
  # its densities (`Giggly.Stat.Ydensity`), mirrored about its `x`, as wide at each `y` as its
  # `violinwidth` makes it of the room between its sides. Its parameters are how its border's ends
  # and corners are drawn (`line_end`, `line_join`, `mitre_limit`, ggplot2's
  # `lineend`, `linejoin` and `linemitre`), its corners `:none` where the layer gives it none,
  # drawn round, as ggplot2's `GeomPolygon` draws them, and keyed mitred, as `draw_key_polygon()`
  # draws a key whose layer has no `linejoin`. Use it through `Giggly.Geom`.
  #
  # Violins use `:x`, `:y`, `:group`, `:weight`, `:width`, `:alpha`, `:color`, `:fill`,
  # `:linetype` and `:linewidth`. What they are drawn from is what the densities write, which no
  # mapping gives, so a layer is checked against the densities' facts and the geom declares no
  # required aesthetics.
  #
  # While the plot is assembled (`setup_data/3`), each violin is set up as ggplot2's
  # `GeomViolin$setup_data()` sets it, along the axis its stat wrote in `flipped_aes`, a horizontal
  # violin worked as a vertical one, x and y swapped and swapped back: its `width` the one its rows
  # hold, the stat's or the layer's set one, which the assembly fills in where the stat wrote none,
  # else 0.9 of the closest spacing of its x positions, counting from zero, the smallest in any
  # panel (`Giggly.Resolution`), as `compute_data_size()` reads it; and its
  # sides, `xmin` and `xmax`, its x less and plus half its width, in R's arithmetic
  # (`Giggly.DataFrame.Arithmetic`). The position then dodges those sides.
  #
  # Each panel's violins are drawn as ggplot2's `draw_group()` draws one, violin by violin in the
  # order of their groups, rows missing their `x` or `y` left out first, as `handle_na()` leaves
  # them: its outline up its left side, each row at its x less its `violinwidth` of the room to
  # `xmin`, in order of `y`, and down its right side, each at its x plus that share of the room to
  # `xmax`, rows at one `y` keeping their order both ways, as R's `order()` keeps ties, then back to
  # its first point, as `GeomViolin` closes it; placed through the coordinate system and cut into
  # steps that follow the panel's curves (`Giggly.Coord.munch/3`), as `GeomPolygon` munches it. A
  # point missing a coordinate splits the outline, as grid splits a polygon, each run of two
  # points or more drawn. A violin takes its look from its first row, as `GeomPolygon` reads a
  # group's first: filled with its fill at its alpha and bordered in its colour, never at its
  # alpha, as wide as its `linewidth` and in its line type; a border whose colour is `:none` or
  # missing, whose line type is blank or whose width is missing is left off, its fill drawn. A
  # violin the layer neither maps nor sets a look for is ggplot2's default under the plot's theme:
  # the theme's ink mixed 20% toward its paper, `#333333` on white paper, filled with its paper, as
  # wide as its borders and solid. Its legend key is a rectangle's (`Giggly.Geom.Rect`), as
  # ggplot2 draws it with `draw_key_polygon()`.

  alias Giggly.Scene.Polylines

  @enforce_keys [:line_end, :line_join, :mitre_limit]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          line_end: Polylines.line_end(),
          line_join: :none | Polylines.line_join(),
          mitre_limit: float()
        }

  # The aesthetics a layer of violins can use, from its own mapping or the plot's, beside those its
  # densities read.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics,
    do: [:alpha, :color, :fill, :group, :linetype, :linewidth, :weight, :width, :x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame, Geom, Resolution, Scene}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Geom.{Mark, Rect, Ribbon}
    alias Scales.ColorOperations

    # How far a violin's default colour is mixed from the theme's ink toward its paper, ggplot2's
    # `col_mix(ink, paper, 0.2)`.
    @color_toward_paper 0.2

    # ggplot2's default violin, its share of the spacing of the x positions.
    @width_share 0.9

    # ggplot2's `GeomViolin$default_aes`, in its order, as far as Giggly draws a violin: a weight of
    # 1, the theme's ink mixed toward its paper, a fill of its paper, its borders' width and line
    # type, and no alpha. R's `width`, which is no look, is left out.
    @impl Giggly.Geom
    def default_aesthetics(_geom, element) do
      [
        weight: 1.0,
        color: ColorOperations.mix(element.ink, element.paper, @color_toward_paper),
        fill: element.paper,
        linewidth: element.borderwidth,
        linetype: element.bordertype,
        alpha: nil
      ]
    end

    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds) do
      flipped = flipped?(frame)

      frame
      |> Ribbon.flip(flipped)
      |> with_width()
      |> sides()
      |> Ribbon.flip(flipped)
    end

    # The orientation the densities wrote in every row, vertical for a table of none.
    defp flipped?(frame) do
      frame
      |> DataFrame.pull(:flipped_aes)
      |> Enum.find(false, fn flipped -> is_boolean(flipped) end)
    end

    # Each row's width, ggplot2's `compute_data_size()` across panels: the one its rows hold, else
    # the closest spacing of the x positions in each panel, counting from zero, the smallest of
    # them, times a violin's share.
    defp with_width(frame) do
      if :width in DataFrame.names(frame),
        do: frame,
        else: DataFrame.mutate(frame, width: own_width(frame))
    end

    defp own_width(frame) do
      resolution =
        frame
        |> DataFrame.pull(:panel)
        |> Enum.zip(DataFrame.pull(frame, :x))
        |> Enum.group_by(fn {panel, _x} -> panel end, fn {_panel, x} -> x end)
        |> Enum.map(fn {_panel, panel_positions} ->
          Resolution.of(panel_positions, zero: true, discrete: false)
        end)
        |> Enum.min(fn -> 1 end)

      resolution * @width_share
    end

    # Each row's sides, its x less and plus half its width, in R's arithmetic.
    defp sides(frame) do
      x_positions = DataFrame.pull(frame, :x)

      halves =
        frame
        |> DataFrame.pull(:width)
        |> Enum.map(fn width -> Arithmetic.divide(width, 2) end)

      frame
      |> DataFrame.put(:xmin, Enum.zip_with(x_positions, halves, &Arithmetic.subtract/2))
      |> DataFrame.put(:xmax, Enum.zip_with(x_positions, halves, &Arithmetic.add/2))
    end

    # Each violin, in the order of their groups, drawn whole before the next.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params, _installed_fonts) do
      flipped = flipped?(frame)

      frame
      |> Ribbon.flip(flipped)
      |> rows()
      |> Enum.filter(fn row -> placed?(row.x) and placed?(row.y) end)
      |> Enum.group_by(fn row -> row.group end)
      |> Enum.sort_by(fn {group, _rows} -> group end)
      |> Enum.flat_map(fn {_group, violin_rows} ->
        violin(geom, violin_rows, {flipped, coord, panel_params})
      end)
    end

    # Each row of a vertical table: where it is drawn and how it looks.
    defp rows(frame) do
      columns = [
        x: DataFrame.pull(frame, :x),
        y: DataFrame.pull(frame, :y),
        xmin: DataFrame.pull(frame, :xmin),
        xmax: DataFrame.pull(frame, :xmax),
        violinwidth: DataFrame.pull(frame, :violinwidth),
        group: DataFrame.pull(frame, :group),
        color: Mark.colors(frame, :color),
        fill: Mark.colors(frame, :fill),
        alpha: DataFrame.pull(frame, :alpha),
        linetype: Mark.line_types(frame),
        linewidth: DataFrame.pull(frame, :linewidth)
      ]

      names = Keyword.keys(columns)

      columns
      |> Keyword.values()
      |> Enum.zip_with(fn values ->
        names
        |> Enum.zip(values)
        |> Map.new()
      end)
    end

    # A violin's polygon, in its first row's look, each run of its outline's placed points drawn.
    defp violin(geom, [first | _rest] = violin_rows, placing) do
      pieces =
        violin_rows
        |> outline()
        |> Enum.chunk_by(&complete?/1)
        |> Enum.filter(fn [point | _rest] -> complete?(point) end)
        |> Enum.map(fn piece -> place(piece, placing) end)
        |> Enum.filter(fn piece -> match?([_first, _second | _rest], piece) end)

      case pieces do
        [] -> []
        pieces -> [polygon(geom, pieces, first)]
      end
    end

    # The outline, in a vertical violin's terms: up its left side in order of `y`, down its right
    # side, and back to its first point, each side's rows at one `y` in their order.
    defp outline(violin_rows) do
      upward = Enum.sort_by(violin_rows, fn row -> Arithmetic.sort_key(row.y) end)
      downward = Enum.sort_by(violin_rows, fn row -> Arithmetic.sort_key(row.y) end, :desc)
      left = Enum.map(upward, fn row -> {side(row, row.xmin), row.y} end)
      right = Enum.map(downward, fn row -> {side(row, row.xmax), row.y} end)
      Enum.concat([left, right, [hd(left)]])
    end

    # Where a violin's side is at a row: its x moved its `violinwidth` of the way to `edge`, R's
    # `x - violinwidth * (x - xmin)` and `x + violinwidth * (xmax - x)`.
    defp side(row, edge) do
      reach =
        row.x
        |> Arithmetic.subtract(edge)
        |> Arithmetic.multiply(row.violinwidth)

      Arithmetic.subtract(row.x, reach)
    end

    defp complete?({along, up}), do: placed?(along) and placed?(up)

    defp placed?(value), do: value not in [nil, :nan]

    # A run of the outline placed in the panel, turned back for a horizontal violin, cut into steps
    # that follow the panel's curves.
    defp place(points, {flipped, coord, panel_params}) do
      {x_positions, y_positions} =
        points
        |> Enum.map(fn {along, up} -> if flipped, do: {up, along}, else: {along, up} end)
        |> Enum.unzip()

      groups = List.duplicate(1, length(points))
      outline = DataFrame.new(x: x_positions, y: y_positions, group: groups)
      munched = Coord.munch(coord, outline, panel_params)
      across = DataFrame.pull(munched, :x)
      up = DataFrame.pull(munched, :y)
      Enum.zip(across, up)
    end

    # A violin's polygon: filled with its fill at its alpha and bordered in its colour, width and
    # line type, a border no line draws left off, as a colour of `:none` leaves it.
    defp polygon(geom, pieces, look) do
      width = look.linewidth || 0.0
      drawn = is_number(look.linewidth) and look.linetype != :none
      border = if drawn, do: look.color, else: :none
      each = fn value -> List.duplicate(value, length(pieces)) end
      border_color = Mark.hex(border)
      border_opacity = Mark.own_opacity(border)
      fill = Mark.hex(look.fill)
      fill_opacity = Mark.opacity(look.fill, look.alpha)

      %Scene.Polygons{
        outlines: pieces,
        offsets: :none,
        stroke_width: Mark.stroke_width(width),
        color: each.(border_color),
        color_opacity: each.(border_opacity),
        fill: each.(fill),
        fill_opacity: each.(fill_opacity),
        dashes: Mark.dashes(look.linetype, width),
        line_end: geom.line_end,
        line_join: drawn_join(geom.line_join),
        mitre_limit: geom.mitre_limit
      }
    end

    # How a violin's corners are drawn: as its layer gives them, or round where it gives none.
    defp drawn_join(:none), do: :round
    defp drawn_join(line_join), do: line_join

    # A legend's key, ggplot2's `draw_key_polygon()`, its corners and ends the layer's, its corners
    # mitred where the layer gives none, and the room it needs, a rectangle's.
    @impl Giggly.Geom
    def draw_key(geom, key, _installed_fonts),
      do: Rect.polygon_key(key, geom.line_end, key_join(geom.line_join))

    defp key_join(:none), do: :mitre
    defp key_join(line_join), do: line_join

    @impl Giggly.Geom
    def key_size(_geom, key, installed_fonts), do: Geom.key_size(%Rect{}, key, installed_fonts)
  end
end
