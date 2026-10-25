defmodule Giggly.Geom.Ribbon do
  @moduledoc false

  # Ribbons, ggplot2's `GeomRibbon`, which `geom_ribbon()` draws with: the band between each group's
  # `ymin` and `ymax` along its `x`, or, turned, between its `xmin` and `xmax` up its `y`. Its
  # parameters are which way it runs (`orientation`: `:x`, `:y`, or `:none` to take it from the
  # ranges given), which edges are outlined (`outline_type`: `:both`, the upper and the lower edge
  # each a line, `:upper`, `:lower`, or `:full`, the band's whole border), and how its outlines'
  # ends and corners are drawn (`line_end`, `line_join`, `mitre_limit`, ggplot2's `lineend`,
  # `linejoin` and `linemitre`). Areas (`Giggly.Geom.Area`) are drawn as ribbons from 0 to their y,
  # as ggplot2's `GeomArea` is a `GeomRibbon`. Use it through `Giggly.Geom`.
  #
  # Ribbons use `:x`, `:y`, `:xmin`, `:xmax`, `:ymin`, `:ymax`, `:group`, `:alpha`, `:color`,
  # `:fill`, `:linetype` and `:linewidth`, and need one of `:x` and `:y`, one of `:ymin` and `:xmin`
  # and one of `:ymax` and `:xmax`, ggplot2's `"x|y"`, `"ymin|xmin"` and `"ymax|xmax"`; an aesthetic
  # joins the accepted list with the scale that maps it, so a mapping never silently does nothing.
  #
  # While the plot is assembled (`setup_data/3`), a ribbon runs along y where the layer says so, or,
  # where it does not, where it is given no `ymin` or `ymax`, as ggplot2's `has_flipped_aes()`
  # reads a range, and writes that in `flipped_aes`; its rows are put in order of panel, group and
  # the position it runs along, ties keeping their order and a missing position last, as R's
  # `order()` puts them, and its `y` (`x`, turned) is its `ymin`, or its `ymax` where it has no
  # `ymin`, as `GeomRibbon$setup_data()` sets it.
  #
  # A ribbon is drawn as ggplot2's `GeomRibbon` draws one (`draw/5`, which areas share). First, as
  # its `handle_na()`, a row missing a position the geom needs (`nil`, or the float `:nan`; an
  # infinite one reaches the panel's edge) is dropped, and each run of the rows left in a group is
  # a piece of its own; ggplot2 also warns of the rows it drops, which a pure pipeline cannot. Each
  # piece, in the order the panel's rows give them, is drawn whole before the next: a filled polygon
  # running out along its upper edge and back along its lower, then its outline. A piece's colour,
  # fill, width, line type and alpha must stay one value all along it: where its colour, width or
  # line type varies, it is refused, as ggplot2 refuses it; where its fill or alpha does, ggplot2
  # draws a gradient under cartesian coordinates, which waits, so it is refused too. Each edge is
  # cut into steps that follow the panel's curves (`Giggly.Coord.munch/3`), as ggplot2 munches the
  # upper and the lower edge apart; a point the stacking of areas pads a group's ends with
  # (`align_padding`) is left off the upper edge.
  #
  # The polygon is filled with the piece's fill at its alpha, which replaces the fill's own, and,
  # but where its outline is `:full`, has no border: grid's `polygonGrob()` with no colour and a
  # width of 0. Its outline is in the piece's colour, never at its alpha, as wide as its
  # `linewidth`, in millimetres, and in its line type, dashed as svglite writes it
  # (`Mark.dashes/2`): the polygon's border, for `:full`, or else its upper edge, its lower edge
  # or both, each a line, the upper first; a line of fewer than two points, or of the blank line
  # type, or of a missing width, is not drawn, as R's graphics engine draws none, and a line of
  # colour `:none`, R's `NA`, ggplot2's default, is written with no stroke, as svglite writes one.
  #
  # A ribbon the layer neither maps nor sets a look for looks as ggplot2's default ribbon does
  # under the plot's theme: filled with the theme's ink mixed 20% toward its paper, `#333333` on
  # white paper and `#000000CC` on `theme_void()`'s clear paper, with no outline, its outline's
  # width and line type the theme's borders'. Its legend key is a rectangle's (`Giggly.Geom.Rect`),
  # as ggplot2's `GeomRibbon` draws its key with `draw_key_polygon()`.

  alias Giggly.{Aesthetics, Coord, DataFrame, Scene}
  alias Giggly.DataFrame.Arithmetic
  alias Giggly.Geom.Mark
  alias Giggly.Scene.{Polygons, Polylines}

  @enforce_keys [:orientation, :outline_type, :line_end, :line_join, :mitre_limit]
  defstruct @enforce_keys

  @typedoc "Which of a ribbon's edges are outlined, ggplot2's `outline.type`."
  @type outline_type :: :both | :upper | :lower | :full

  @type t :: %__MODULE__{
          orientation: :none | :x | :y,
          outline_type: outline_type(),
          line_end: Polylines.line_end(),
          line_join: Polylines.line_join(),
          mitre_limit: float()
        }

  # The look a piece of a ribbon must keep all along it.
  @looks [:color, :fill, :linewidth, :linetype, :alpha]

  # The aesthetics a layer of ribbons can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics,
    do: [:alpha, :color, :fill, :group, :linetype, :linewidth, :x, :xmax, :xmin, :y, :ymax, :ymin]

  # The aesthetics a layer of ribbons cannot be drawn without: one of each pair, ggplot2's `"x|y"`,
  # `"ymin|xmin"` and `"ymax|xmax"`.
  @doc false
  @spec required_aesthetics() :: [[atom()]]
  def required_aesthetics, do: [[:x, :y], [:ymin, :xmin], [:ymax, :xmax]]

  # The rows of `frame`, set up as a ribbon or an area is, each a band from its `ymin` to its
  # `ymax`, in order of panel, group and `x`, `flipped` swapping x and y while they are put in
  # order: ggplot2's `order(data$PANEL, data$group, data$x)` in either orientation.
  @doc false
  @spec in_order(DataFrame.t()) :: DataFrame.t()
  def in_order(frame) do
    order =
      [
        DataFrame.pull(frame, :panel),
        DataFrame.pull(frame, :group),
        DataFrame.pull(frame, :x)
      ]
      |> Enum.zip_with(fn [panel, group, position] ->
        {panel, group, Arithmetic.sort_key(position)}
      end)
      |> Enum.with_index()
      |> Enum.sort_by(fn {key, _index} -> key end)
      |> Enum.map(fn {_key, index} -> index end)

    DataFrame.slice(frame, order)
  end

  # `frame` with x and y swapped where `flipped`, and as it is otherwise, as ggplot2's `flip_data()`
  # swaps them.
  @doc false
  @spec flip(DataFrame.t(), boolean()) :: DataFrame.t()
  def flip(frame, false), do: frame

  def flip(frame, true) do
    renames =
      frame
      |> DataFrame.names()
      |> Aesthetics.flipped()

    DataFrame.select(frame, renames)
  end

  # The primitives a panel's ribbons are drawn with, `geom` saying which edges are outlined and how
  # their ends and corners are drawn, and `positions` the positions a row is dropped without, as
  # ggplot2's `GeomRibbon$handle_na()` reads its required aesthetics: a ribbon's `x`, `ymin` and
  # `ymax`, an area's `x` and `y`, each turned where the rows run along y.
  @doc false
  @spec draw(
          %{
            outline_type: outline_type(),
            line_end: atom(),
            line_join: atom(),
            mitre_limit: float()
          },
          DataFrame.t(),
          Coord.t(),
          Coord.panel_params(),
          [atom()]
        ) :: [Scene.primitive()]
  def draw(geom, frame, coord, panel_params, positions) do
    flipped = flipped_aes(frame)

    frame
    |> flip(flipped)
    |> pieces(positions)
    |> Enum.flat_map(fn piece -> draw_piece(geom, piece, flipped, coord, panel_params) end)
  end

  # The orientation `setup_data/3` wrote, the first boolean in the frame's `flipped_aes`.
  defp flipped_aes(frame) do
    frame
    |> DataFrame.pull(:flipped_aes)
    |> Enum.find(false, fn flipped -> is_boolean(flipped) end)
  end

  # Each piece of the panel's rows, ggplot2's `handle_na()`: the rows missing none of `positions`,
  # each run of them within a group, in row order, as `vec_identify_runs()` numbers a group's runs
  # around its missing rows.
  defp pieces(frame, positions) do
    columns = Enum.map(positions, fn name -> DataFrame.pull(frame, name) end)

    frame
    |> DataFrame.pull(:group)
    |> Enum.zip_with(Enum.zip_with(columns, &Function.identity/1), fn group, values ->
      {group, Enum.any?(values, &missing?/1)}
    end)
    |> Enum.with_index()
    |> Enum.chunk_by(fn {run, _index} -> run end)
    |> Enum.reject(fn [{{_group, missing}, _index} | _rest] -> missing end)
    |> Enum.map(fn run ->
      DataFrame.slice(frame, Enum.map(run, fn {_run, index} -> index end))
    end)
  end

  # A piece drawn as ggplot2's `GeomRibbon$draw_group()` draws a group: its polygon, then its
  # outline, its look one value all along it.
  defp draw_piece(geom, piece, flipped, coord, panel_params) do
    look = look(piece)
    {upper, lower} = edges(piece, flipped, coord, panel_params)
    polygon = polygon(geom, look, upper, lower)

    case geom.outline_type do
      :full -> [polygon]
      outline_type -> [polygon | outline(geom, look, outline_type, upper, lower)]
    end
  end

  # The piece's look, refused where any of it varies along the piece, as ggplot2 refuses a
  # ribbon's colour, width or line type varying along it, and draws its fill or alpha varying as
  # a gradient, which waits.
  defp look(piece) do
    varying =
      Enum.filter(@looks, fn aesthetic ->
        values =
          piece
          |> DataFrame.pull(aesthetic)
          |> Enum.uniq()

        match?([_first, _second | _rest], values)
      end)

    case varying do
      [] ->
        Map.new(@looks, fn aesthetic -> {aesthetic, Mark.set(piece, aesthetic)} end)

      _varying ->
        raise ArgumentError,
              "a ribbon or an area cannot vary its #{Enum.map_join(varying, " or ", &to_string/1)} " <>
                "along it: ggplot2 refuses a colour, width or line type that varies along one, " <>
                "and fills one whose fill or alpha varies with a gradient, which Giggly does not " <>
                "draw yet; give each group one look, or a group of its own to each look"
    end
  end

  # The piece's upper edge, out along its `ymax`, and its lower edge, back along its `ymin`, each
  # point numbered by the stretch of complete rows it belongs to, `nil` for a row missing a
  # position, as ggplot2 numbers its polygon's ids, then placed in the panel, each edge cut into
  # steps that follow the panel's curves on its own; a row the stacking of areas pads a group's
  # ends with is left off the upper edge.
  defp edges(piece, flipped, coord, panel_params) do
    x_positions = DataFrame.pull(piece, :x)
    lows = DataFrame.pull(piece, :ymin)
    highs = DataFrame.pull(piece, :ymax)

    ids =
      [x_positions, lows, highs]
      |> Enum.zip_with(fn values -> Enum.any?(values, &missing?/1) end)
      |> Enum.map_reduce(1, fn
        true, id -> {nil, id + 1}
        false, id -> {id, id}
      end)
      |> elem(0)

    kept = upper_kept(piece)

    upper =
      [x_positions, highs, ids, kept]
      |> Enum.zip_with(fn [x, high, id, keep] -> {x, high, id, keep} end)
      |> Enum.filter(fn {_x, _high, _id, keep} -> keep end)
      |> Enum.map(fn {x, high, id, _keep} -> {x, high, id} end)

    lower =
      [x_positions, lows, ids]
      |> Enum.zip_with(fn [x, low, id] -> {x, low, id} end)
      |> Enum.reverse()

    {placed(upper, flipped, coord, panel_params), placed(lower, flipped, coord, panel_params)}
  end

  # Whether each row of the piece belongs on its upper edge: all but a padding row, as ggplot2's
  # `GeomRibbon` reads `align_padding`, a missing one kept.
  defp upper_kept(piece) do
    if :align_padding in DataFrame.names(piece) do
      piece
      |> DataFrame.pull(:align_padding)
      |> Enum.map(fn padding -> padding != true end)
    else
      List.duplicate(true, DataFrame.row_count(piece))
    end
  end

  # An edge's points placed in the panel, x and y swapped back where the rows run along y, cut into
  # steps that follow the panel's curves, each step numbered as the point it starts from: ggplot2's
  # `coord_munch()` of an edge, whose points it munches one after another whatever their ids.
  defp placed(points, flipped, coord, panel_params) do
    {across, up} = if flipped, do: {:y, :x}, else: {:x, :y}

    frame =
      DataFrame.new([
        {across, Enum.map(points, fn {x, _y, _id} -> x end)},
        {up, Enum.map(points, fn {_x, y, _id} -> y end)},
        {:group, List.duplicate(1, length(points))},
        {:id, Enum.map(points, fn {_x, _y, id} -> id end)}
      ])

    munched = Coord.munch(coord, frame, panel_params)

    Enum.zip_with(
      [DataFrame.pull(munched, :x), DataFrame.pull(munched, :y), DataFrame.pull(munched, :id)],
      fn [x, y, id] -> {{x, y}, id} end
    )
  end

  # The piece's polygon, an outline for each stretch of complete rows, its upper edge and then its
  # lower, as grid's `polygonGrob()` draws a polygon for each id: filled with the fill at the
  # piece's alpha, and bordered only where the outline is `:full`.
  defp polygon(geom, look, upper, lower) do
    outlines =
      (upper ++ lower)
      |> Enum.reject(fn {_point, id} -> is_nil(id) end)
      |> Enum.group_by(fn {_point, id} -> id end, fn {point, _id} -> point end)
      |> Enum.sort_by(fn {id, _points} -> id end)
      |> Enum.map(fn {_id, points} -> points end)

    fill = color(look.fill)
    {border, width, dashes} = border(geom.outline_type, look)

    %Polygons{
      outlines: outlines,
      offsets: :none,
      stroke_width: width,
      color: Enum.map(outlines, fn _outline -> Mark.hex(border) end),
      color_opacity: Enum.map(outlines, fn _outline -> Mark.own_opacity(border) end),
      fill: Enum.map(outlines, fn _outline -> Mark.hex(fill) end),
      fill_opacity: Enum.map(outlines, fn _outline -> Mark.opacity(fill, look.alpha) end),
      dashes: dashes,
      line_end: geom.line_end,
      line_join: geom.line_join,
      mitre_limit: geom.mitre_limit
    }
  end

  # The polygon's border, its colour, width in points and dashes: the piece's outline where it is
  # `:full`, a blank line type or a missing width leaving it none, as R's graphics engine draws such
  # a border transparent, and otherwise none, grid's `col = NA` and `lwd = 0`.
  defp border(:full, %{linewidth: nil}), do: {:none, 0.0, :none}

  defp border(:full, %{linetype: line_type}) when line_type in [nil, :none],
    do: {:none, 0.0, :none}

  defp border(:full, look) do
    {color(look.color), Mark.stroke_width(look.linewidth),
     Mark.dashes(look.linetype, look.linewidth)}
  end

  defp border(_outline_type, _look), do: {:none, 0.0, :none}

  # The piece's outline as lines, the upper edge's for each stretch, then the lower edge's, as
  # ggplot2 numbers the lower edge's ids after the upper's, or one of them, in the piece's colour,
  # never at its alpha; a line of fewer than two points draws nothing, and nor does any line of the
  # blank line type or a missing width.
  defp outline(_geom, %{linetype: line_type}, _outline_type, _upper, _lower)
       when line_type in [nil, :none],
       do: []

  defp outline(_geom, %{linewidth: nil}, _outline_type, _upper, _lower), do: []

  defp outline(geom, look, outline_type, upper, lower) do
    edges =
      case outline_type do
        :both -> [upper, lower]
        :upper -> [upper]
        :lower -> [lower]
      end

    case Enum.flat_map(edges, &edge_lines/1) do
      [] ->
        []

      lines ->
        line_color = color(look.color)

        [
          %Polylines{
            lines: lines,
            offsets: :none,
            stroke_width: Mark.stroke_width(look.linewidth),
            dashes: Mark.dashes(look.linetype, look.linewidth),
            color: Enum.map(lines, fn _line -> Mark.hex(line_color) end),
            opacity: Enum.map(lines, fn _line -> Mark.own_opacity(line_color) end),
            line_end: geom.line_end,
            line_join: geom.line_join,
            mitre_limit: geom.mitre_limit
          }
        ]
    end
  end

  # An edge's lines, one for each stretch of its points numbered alike, a line of fewer than two
  # points left out, as R's graphics engine draws none.
  defp edge_lines(edge) do
    edge
    |> Enum.reject(fn {_point, id} -> is_nil(id) end)
    |> Enum.chunk_by(fn {_point, id} -> id end)
    |> Enum.map(fn stretch -> Enum.map(stretch, fn {point, _id} -> point end) end)
    |> Enum.filter(fn points -> match?([_first, _second | _rest], points) end)
  end

  # A colour as a ribbon draws it, a missing one, R's `NA`, as ggplot2's default outline is, read as
  # `:none`.
  defp color(nil), do: :none
  defp color(color), do: color

  defp missing?(value), do: value in [nil, :nan]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{ColorOperations, DataFrame, Geom}
    alias Giggly.Geom.{Rect, Ribbon}

    # How far a ribbon's default fill is mixed from the theme's ink toward its paper, ggplot2's
    # `col_mix(ink, paper, 0.2)`.
    @fill_toward_paper 0.2

    # ggplot2's `GeomRibbon$default_aes`: no outline, a fill of the theme's ink mixed toward its
    # paper, the theme's borders' width and line type, and no alpha.
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

    # ggplot2's `GeomRibbon$setup_data()`: the orientation written in `flipped_aes`, the rows in
    # order along it, and `y` the band's lower end, or its upper one where it has no lower.
    @impl Giggly.Geom
    def setup_data(geom, frame, _axis_kinds) do
      flipped = flipped?(geom.orientation, DataFrame.names(frame))

      frame
      |> DataFrame.put(:flipped_aes, List.duplicate(flipped, DataFrame.row_count(frame)))
      |> Ribbon.flip(flipped)
      |> Ribbon.in_order()
      |> with_y()
      |> Ribbon.flip(flipped)
    end

    # The layer's orientation, or, where it gives none, along y where the ribbon is given no `ymin`
    # or `ymax`, so its range is across x, as ggplot2's `has_flipped_aes(range_is_orthogonal =
    # TRUE)` reads it; `Giggly.Plot` makes sure a ribbon has a range one way or the other.
    defp flipped?(:x, _names), do: false
    defp flipped?(:y, _names), do: true

    defp flipped?(:none, names),
      do: not Enum.any?([:ymin, :ymax], fn name -> name in names end)

    defp with_y(frame) do
      lower = if :ymin in DataFrame.names(frame), do: :ymin, else: :ymax
      DataFrame.put(frame, :y, DataFrame.pull(frame, lower))
    end

    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params),
      do: Ribbon.draw(geom, frame, coord, panel_params, [:x, :ymin, :ymax])

    # A legend's key, ggplot2's `draw_key_polygon()`, its corners and ends the layer's, and the
    # room it needs, a rectangle's.
    @impl Giggly.Geom
    def draw_key(geom, key), do: Rect.polygon_key(key, geom.line_end, geom.line_join)

    @impl Giggly.Geom
    def key_size(_geom, key), do: Geom.key_size(%Rect{}, key)
  end
end
