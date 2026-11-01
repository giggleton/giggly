defmodule Giggly.Geom.Crossbar do
  @moduledoc false

  # Crossbars, ggplot2's `GeomCrossbar`, which `geom_crossbar()` draws with: for each row a box
  # from its `ymin` to its `ymax`, as wide as its `width`, with a line across it at its `y`, or,
  # turned, from its `xmin` to its `xmax` with a line up it at its `x`. Box plots
  # (`Giggly.Geom.Boxplot`) draw their boxes and medians with it, as ggplot2's `GeomBoxplot` draws
  # through `GeomCrossbar`, so the box's drawing has this one home. Its parameters are which way it
  # runs (`orientation`: `:x`, `:y`, or `:none` to take it from the ranges given), the look of its
  # line across (`middle`) and of its box's border (`box`), each a map holding only the colour,
  # line type and width the layer gives, as ggplot2's `middle_gp` and `box_gp` hold them once
  # compacted, and how its lines' ends and corners are drawn (`line_end`, `line_join`, ggplot2's
  # `lineend` and `linejoin`), at grid's mitre limit. Use it through `Giggly.Geom`.
  #
  # Crossbars use a line range's aesthetics, `:fill` and `:width`, and need `:x` and `:y`, one of
  # `:ymin` and `:xmin` and one of `:ymax` and `:xmax`, ggplot2's `"x"`, `"y"`, `"ymin|xmin"` and
  # `"ymax|xmax"`; `Giggly.Plot` makes sure a layer has the range its orientation draws with. While
  # the plot is assembled (`setup_data/3`), a crossbar is set up as an error bar is
  # (`Giggly.Geom.Errorbar.with_sides/3`), its orientation written in `flipped_aes` and its sides
  # its x less and plus half its width.
  #
  # Each panel is drawn as ggplot2's `GeomCrossbar` draws it: every row's box, then every row's line
  # across, so a later box covers no line. A box (`parts/3`) is a polygon round its range and sides,
  # pinched in to its middle between its notches where a box plot notches it, `1 - notchwidth` of
  # half its width, filled with its fill at its alpha and bordered in its colour, line type and
  # width, or its `box` look's, never at its alpha; its line across runs from side to side, as far
  # in where notched, in its `middle` look, else its colour and line type and its width times the
  # layer's `fatten` (2.5 for a crossbar, 2 for a box plot's median), never at its alpha. A line
  # whose colour is `:none` or missing, whose line type is blank or whose width is missing is not
  # drawn, a box's border so left off, its fill drawn; a line missing an end is left out, and a box
  # missing a corner, one a scale's limits cut, is drawn in the runs of two corners or more left, as
  # grid splits a polygon at a missing point. A box in radial coordinates is drawn between its
  # placed corners, not curved. A crossbar the layer neither maps nor sets a look for looks as
  # ggplot2's default crossbar does under the plot's theme: the theme's ink, no fill, its borders'
  # width and line type.
  #
  # Its legend key is ggplot2's `draw_key_crossbar()` (`key/5`, which a box plot's key draws
  # inside its whiskers and staples): a box three quarters of the key wide and half as tall in its
  # middle, filled at the key's alpha and bordered in the `box` look, else the key's, and a line
  # across it from an eighth of the key to seven eighths in the `middle` look, else the key's, not
  # widened; turned for a horizontal layer, which the legend says in the key's `flipped_aes`. It
  # needs a path's room, its line's width either way.

  alias Giggly.{Coord, DataFrame}
  alias Giggly.DataFrame.Arithmetic
  alias Giggly.Geom.Mark
  alias Giggly.Scene.{Polygons, Polylines, Rectangles, Segments}

  @enforce_keys [:orientation, :middle, :box, :line_end, :line_join]
  defstruct @enforce_keys

  # A line's look as a layer gives it: its colour, line type and width, each only where given.
  @type look :: %{optional(:color | :linetype | :linewidth) => term()}

  @type t :: %__MODULE__{
          orientation: :none | :x | :y,
          middle: look(),
          box: look(),
          line_end: Polylines.line_end(),
          line_join: Polylines.line_join()
        }

  @typedoc """
  A box as it is drawn, in a vertical box's terms: its middle `x` and its sides, its range from
  `lower` to `upper`, its `middle` and its notches, `nil` where it has none, and its colour, fill,
  alpha, line type and width.
  """
  @type box :: %{
          required(:x) => term(),
          required(:xmin) => term(),
          required(:xmax) => term(),
          required(:lower) => term(),
          required(:upper) => term(),
          required(:middle) => term(),
          required(:notchlower) => term(),
          required(:notchupper) => term(),
          required(:color) => term(),
          required(:fill) => term(),
          required(:alpha) => term(),
          required(:linetype) => term(),
          required(:linewidth) => term(),
          optional(atom()) => term()
        }

  @typedoc """
  How a layer draws its boxes: its `box` and `middle` looks, how many times the box's width the
  middle line is (`fatten`), whether its boxes are notched and how far (`notch`, `notchwidth`),
  and its lines' ends and corners.
  """
  @type style :: %{
          box: look(),
          middle: look(),
          fatten: number(),
          notch: boolean(),
          notchwidth: number(),
          line_end: Polylines.line_end(),
          line_join: Polylines.line_join()
        }

  @typedoc """
  Where a box is placed: whether it is turned, and the coordinate system and panel params it is
  placed through.
  """
  @type placing :: {boolean(), Coord.t(), Coord.panel_params()}

  @mitre_limit 10.0

  # The aesthetics a layer of crossbars can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics do
    [
      :alpha,
      :color,
      :fill,
      :group,
      :linetype,
      :linewidth,
      :width,
      :x,
      :xmax,
      :xmin,
      :y,
      :ymax,
      :ymin
    ]
  end

  # The aesthetics a layer of crossbars cannot be drawn without: its middle's place, and one of
  # each of its range's ends, ggplot2's `"ymin|xmin"` and `"ymax|xmax"`.
  @doc false
  @spec required_aesthetics() :: [atom() | [atom()]]
  def required_aesthetics, do: [:x, :y, [:ymin, :xmin], [:ymax, :xmax]]

  # A box's polygon and its line across, placed in the panel as `placing` says, as `style` draws
  # them: ggplot2's `GeomCrossbar$draw_panel()` for one box, which a box plot draws box by box and
  # a crossbar layer every box before every line.
  @doc false
  @spec parts(box(), style(), placing()) :: {[Polygons.t()], [Segments.t()]}
  def parts(box, style, placing) do
    notched = style.notch and is_number(box.notchlower) and is_number(box.notchupper)
    indent = if notched, do: indent(box, style.notchwidth), else: 0.0
    middle_start = Arithmetic.add(box.xmin, indent)
    middle_end = Arithmetic.subtract(box.xmax, indent)
    middle = [{{middle_start, box.middle}, {middle_end, box.middle}}]
    ends = {style.line_end, style.line_join}

    {polygon(outline(box, notched, indent), line_look(style.box, box), box, ends, placing),
     segments(middle, middle_look(style.middle, box, style.fatten), ends, placing)}
  end

  # How far a notch reaches in from each side, R's `(1 - notchwidth) * (xmax - xmin) / 2`.
  defp indent(box, notchwidth) do
    (1 - notchwidth)
    |> Arithmetic.multiply(Arithmetic.subtract(box.xmax, box.xmin))
    |> Arithmetic.divide(2)
  end

  # The box's outline in ggplot2's order, closed where it began.
  defp outline(box, false, _indent) do
    [
      {box.xmin, box.upper},
      {box.xmin, box.lower},
      {box.xmax, box.lower},
      {box.xmax, box.upper},
      {box.xmin, box.upper}
    ]
  end

  defp outline(box, true, indent) do
    inner_left = Arithmetic.add(box.xmin, indent)
    inner_right = Arithmetic.subtract(box.xmax, indent)

    [
      {box.xmin, box.upper},
      {box.xmin, box.notchupper},
      {inner_left, box.middle},
      {box.xmin, box.notchlower},
      {box.xmin, box.lower},
      {box.xmax, box.lower},
      {box.xmax, box.notchlower},
      {inner_right, box.middle},
      {box.xmax, box.notchupper},
      {box.xmax, box.upper},
      {box.xmin, box.upper}
    ]
  end

  # A line's look, `{color, width, line type}`: the part's, else `base`'s, a box or a key, which a
  # box plot's whiskers and staples share.
  @doc false
  @spec line_look(look(), map()) :: {term(), term(), term()}
  def line_look(part, base) do
    {Map.get(part, :color, base.color), Map.get(part, :linewidth, base.linewidth),
     Map.get(part, :linetype, base.linetype)}
  end

  # The middle line's look: its own, else the box's, `fatten` times as wide.
  defp middle_look(middle, box, fatten) do
    {Map.get(middle, :color, box.color),
     Map.get(middle, :linewidth, Arithmetic.multiply(box.linewidth, fatten)),
     Map.get(middle, :linetype, box.linetype)}
  end

  # Straight lines in one look, each `{start, end}` in a vertical box's terms, placed in the panel
  # as `placing` says, with `ends`' line ends and corners: none where the look draws no line, and a
  # line with an end missing left out, which a box plot's whiskers and staples share.
  @doc false
  @spec segments(
          [{{term(), term()}, {term(), term()}}],
          {term(), term(), term()},
          {Polylines.line_end(), Polylines.line_join()},
          placing()
        ) :: [Segments.t()]
  def segments(lines, {color, width, line_type}, {line_end, line_join}, placing) do
    placed =
      lines
      |> Enum.flat_map(fn {start, finish} -> [start, finish] end)
      |> place(placing)
      |> Enum.chunk_every(2)
      |> Enum.filter(fn ends -> Enum.all?(ends, &placed?/1) end)

    count = length(placed)
    hex = Mark.hex(color)
    opacity = Mark.own_opacity(color)

    if not drawn_line?(color, width, line_type) or count == 0 do
      []
    else
      [
        %Segments{
          starts: Enum.map(placed, fn [start, _finish] -> start end),
          ends: Enum.map(placed, fn [_start, finish] -> finish end),
          offsets: :none,
          stroke_width: Mark.stroke_width(width),
          dashes: Mark.dashes(line_type, width),
          color: List.duplicate(hex, count),
          opacity: List.duplicate(opacity, count),
          line_end: line_end,
          line_join: line_join,
          mitre_limit: @mitre_limit,
          arrows: :none
        }
      ]
    end
  end

  # The box round its outline, in a vertical box's terms, placed in the panel, filled at its
  # alpha and bordered in its look, left off where the look draws no line. A missing corner, one
  # a scale's limits cut, splits the outline, as grid splits a polygon at a missing point, and
  # each run of two corners or more is drawn as a piece of its own.
  defp polygon(outline, {color, width, line_type}, box, {line_end, line_join}, placing) do
    pieces =
      outline
      |> place(placing)
      |> Enum.chunk_by(&placed?/1)
      |> Enum.filter(&drawn_piece?/1)

    border = if drawn_line?(color, width, line_type), do: color, else: :none
    border_width = width || 0.0
    count = length(pieces)
    border_color = Mark.hex(border)
    border_opacity = Mark.own_opacity(border)
    fill = Mark.hex(box.fill)
    fill_opacity = Mark.opacity(box.fill, box.alpha)

    if count == 0 do
      []
    else
      [
        %Polygons{
          outlines: pieces,
          offsets: :none,
          stroke_width: Mark.stroke_width(border_width),
          color: List.duplicate(border_color, count),
          color_opacity: List.duplicate(border_opacity, count),
          fill: List.duplicate(fill, count),
          fill_opacity: List.duplicate(fill_opacity, count),
          dashes: Mark.dashes(line_type, border_width),
          line_end: line_end,
          line_join: line_join,
          mitre_limit: @mitre_limit
        }
      ]
    end
  end

  # A run of placed corners long enough to draw, two or more, as grid draws a piece of a polygon.
  defp drawn_piece?([first, _second | _rest]), do: placed?(first)
  defp drawn_piece?([_alone]), do: false

  defp drawn_line?(color, width, line_type),
    do: color != :none and is_number(width) and line_type != :none

  defp placed?({x_position, y_position}), do: is_number(x_position) and is_number(y_position)

  # Points in a vertical box's terms, `{along, up}`, placed in the panel through the coordinate
  # system, a horizontal box's turned first.
  defp place(points, {flipped, coord, panel_params}) do
    {x_positions, y_positions} =
      points
      |> Enum.map(fn {along, up} -> if flipped, do: {up, along}, else: {along, up} end)
      |> Enum.unzip()

    placed = Coord.transform(coord, DataFrame.new(x: x_positions, y: y_positions), panel_params)
    across = DataFrame.pull(placed, :x)
    up = DataFrame.pull(placed, :y)
    Enum.zip(across, up)
  end

  # A crossbar's legend key, `draw_key_crossbar()`, inside a box plot's whiskers and staples too:
  # its box, three quarters of the key wide and half as tall in its middle, in the `box` look, and
  # its line across in the `middle` look, each else `base`'s, the key's colour, width and line
  # type, the box filled with `fill` at `alpha`, turned by `turn`, with `ends`' line ends and
  # corners.
  @doc false
  @spec key(
          map(),
          {term(), term()},
          {look(), look()},
          (tuple() -> tuple()),
          {Polylines.line_end(), Polylines.line_join()}
        ) :: [Rectangles.t() | Polylines.t()]
  def key(base, {fill, alpha}, {box, middle}, turn, ends) do
    drawn_box =
      box
      |> line_look(base)
      |> key_box(fill, alpha, turn, ends)

    Enum.concat(drawn_box, key_lines([[{0.125, 0.5}, {0.875, 0.5}]], middle, base, turn, ends))
  end

  # Lines in a key, each a list of points in a vertical key's terms, in `part`'s look, else
  # `base`'s, turned by `turn`, with `ends`' line ends and corners, which a box plot's whiskers and
  # staples share.
  @doc false
  @spec key_lines(
          [[{number(), number()}]],
          look(),
          map(),
          (tuple() -> tuple()),
          {Polylines.line_end(), Polylines.line_join()}
        ) :: [Polylines.t()]
  def key_lines(lines, part, base, turn, {line_end, line_join}) do
    {color, width, line_type} = line_look(part, base)
    count = length(lines)
    hex = Mark.hex(color)
    opacity = Mark.own_opacity(color)

    if drawn_line?(color, width, line_type) do
      [
        %Polylines{
          lines: Enum.map(lines, fn points -> Enum.map(points, turn) end),
          offsets: :none,
          stroke_width: Mark.stroke_width(width),
          dashes: Mark.dashes(line_type, width),
          color: List.duplicate(hex, count),
          opacity: List.duplicate(opacity, count),
          line_end: line_end,
          line_join: line_join,
          mitre_limit: @mitre_limit,
          arrows: :none
        }
      ]
    else
      []
    end
  end

  defp key_box({color, width, line_type}, fill, alpha, turn, {line_end, line_join}) do
    border = if drawn_line?(color, width, line_type), do: color, else: :none
    border_width = width || 0.0
    {xmin, ymin} = turn.({0.125, 0.25})
    {xmax, ymax} = turn.({0.875, 0.75})

    [
      %Rectangles{
        xmin: [xmin],
        xmax: [xmax],
        ymin: [ymin],
        ymax: [ymax],
        offsets: :none,
        fill: [Mark.hex(fill)],
        fill_opacity: [Mark.opacity(fill, alpha)],
        color: [Mark.hex(border)],
        color_opacity: [Mark.own_opacity(border)],
        stroke_width: Mark.stroke_width(border_width),
        dashes: Mark.dashes(line_type, border_width),
        line_end: line_end,
        line_join: line_join,
        mitre_limit: @mitre_limit
      }
    ]
  end

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{DataFrame, Geom}
    alias Giggly.Geom.{Linerange, Mark, Ribbon}

    # ggplot2's `fatten` for a crossbar, how many times the box's width its line across is.
    @fatten 2.5

    # ggplot2's `GeomCrossbar$default_aes`: the theme's ink, no fill, its borders' width and line
    # type, and no alpha.
    @impl Giggly.Geom
    def default_aesthetics(_geom, element) do
      [
        color: element.ink,
        fill: nil,
        linewidth: element.borderwidth,
        linetype: element.bordertype,
        alpha: nil
      ]
    end

    # ggplot2's `GeomCrossbar$setup_data()`, an error bar's.
    @impl Giggly.Geom
    def setup_data(geom, frame, axis_kinds),
      do: Geom.Errorbar.with_sides(frame, geom.orientation, axis_kinds)

    # Every row's box, then every row's line across.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params, _installed_fonts) do
      flipped = Linerange.flipped_aes(frame)
      placing = {flipped, coord, panel_params}

      style = %{
        box: geom.box,
        middle: geom.middle,
        fatten: @fatten,
        notch: false,
        notchwidth: 0.5,
        line_end: geom.line_end,
        line_join: geom.line_join
      }

      {polygons, lines} =
        frame
        |> Ribbon.flip(flipped)
        |> boxes()
        |> Enum.map(fn box -> Geom.Crossbar.parts(box, style, placing) end)
        |> Enum.unzip()

      polygons
      |> Enum.concat()
      |> Enum.concat(Enum.concat(lines))
    end

    # Each row of a vertical table as a box, its range and middle its `ymin`, `ymax` and `y`.
    defp boxes(frame) do
      columns = [
        x: DataFrame.pull(frame, :x),
        xmin: DataFrame.pull(frame, :xmin),
        xmax: DataFrame.pull(frame, :xmax),
        lower: DataFrame.pull(frame, :ymin),
        upper: DataFrame.pull(frame, :ymax),
        middle: DataFrame.pull(frame, :y),
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
        |> Map.merge(%{notchlower: nil, notchupper: nil})
      end)
    end

    # A legend's key, `draw_key_crossbar()`, turned for a horizontal layer.
    @impl Giggly.Geom
    def draw_key(geom, key, _installed_fonts) do
      base = %{
        color: Mark.key_color(key, :color),
        linewidth: Map.fetch!(key, :linewidth),
        linetype: Map.fetch!(key, :linetype) || :none
      }

      fill = {Mark.key_color(key, :fill), Map.fetch!(key, :alpha)}
      turn = if Map.fetch!(key, :flipped_aes), do: &turned/1, else: &Function.identity/1

      Geom.Crossbar.key(
        base,
        fill,
        {geom.box, geom.middle},
        turn,
        {geom.line_end, geom.line_join}
      )
    end

    defp turned({across, up}), do: {up, across}

    # The room a key needs, its line's width either way, as a path's.
    @impl Giggly.Geom
    def key_size(_geom, key, installed_fonts) do
      path = %Geom.Path{line_end: :butt, line_join: :round, mitre_limit: 10.0, arrow: :none}
      Geom.key_size(path, key, installed_fonts)
    end
  end
end
