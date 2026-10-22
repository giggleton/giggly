defmodule Giggly.Geom.Boxplot do
  @moduledoc false

  # Box plots, ggplot2's `GeomBoxplot`: a box for each row of the box plot's summary
  # (`Giggly.Stat.Boxplot`), from its `lower` hinge to its `upper`, a line across it at its `middle`,
  # whiskers out to `ymin` and `ymax`, and its `outliers` drawn as points. Its fields are R's
  # parameters: `outliers`, whether a box keeps its outliers; `notch` and `notchwidth`, the notches'
  # width as a share of the box's; `staplewidth`, the staples' share of the box's width, 0 for none;
  # `varwidth`, whether each box is as wide as the square root of its rows makes it beside the
  # others; and the look of each part, `outlier`, `whisker`, `staple`, `median` and `box`, each a map
  # holding only the looks the layer gives, as ggplot2's `outlier_gp` and the others hold them once
  # compacted, so a look a map lacks is the box's own, and `:none` is R's `NA`. Each is given by
  # `Giggly.Plot.geom_boxplot/3`, whose defaults are R's. Use it through `Giggly.Geom`.
  #
  # Boxes use `:x`, `:y`, `:group`, `:alpha`, `:color`, `:fill`, `:linetype` and `:linewidth`, and
  # `:shape` and `:size`, which only the outliers read, as ggplot2's do. What they are drawn from is
  # what the summary writes, which no mapping gives, so a layer is checked against the summary's
  # facts and the geom declares no required aesthetics.
  #
  # While the plot is assembled (`setup_data/3`), each box is set up as ggplot2's
  # `GeomBoxplot$setup_data()` sets it, along the axis its stat wrote in `flipped_aes`, a horizontal
  # box worked as a vertical one, x and y swapped and swapped back, as ggplot2's `flip_data()` does:
  # its `outliers` dropped where the layer keeps none, so the axes fit its whiskers; its `ymin_final`
  # and `ymax_final` the lesser of its lower whisker's end and its outliers and the greater of its
  # upper whisker's end and them, which the y scale trains on; its sides, `xmin` and `xmax`, its x
  # less and plus half its width, or, with `varwidth`, half its width times its `relvarwidth` over
  # the greatest in the layer, in R's arithmetic (`Giggly.DataFrame.Arithmetic`); and its `width`
  # and `relvarwidth` dropped. The position then dodges those sides.
  #
  # Each panel's boxes are drawn as ggplot2's `draw_group()` draws one, box by box in the order of
  # their groups, as ggplot2 splits a panel by group, each placed through the coordinate system
  # (`Giggly.Coord.transform/3`) and drawn whole before the next, its parts in R's order: its
  # outliers, as points (`Giggly.Geom.Point`) at its x, in the outliers' look, else its own colour,
  # fill, shape, size and alpha, `:circle` and 1.5 by default, their stroke the look's; its staples,
  # where `staplewidth` is not 0, across the ends of its whiskers, the upper first, `staplewidth` of
  # its width; its whiskers, from `upper` to `ymax` and from `lower` to `ymin`; its box, a polygon
  # round its hinges and sides, pinched in to its median between its notches where `notch` is set,
  # `1 - notchwidth` of half its width; and its median across it, as far in. Each line is in its
  # part's look, else the box's colour, line type and width, and never takes the box's alpha, as
  # ggplot2 draws each with `alpha = NA`; the median is twice the box's width, ggplot2's `fatten`,
  # unless its look gives a width; the box's fill takes the alpha and its border does not. A box is
  # `#333333`, ink mixed 20% toward paper, filled white, its lines 0.5 mm wide and solid, as
  # ggplot2's default box. Staples and whiskers are cut square at their ends, as ggplot2's
  # `GeomSegment` draws them; the box and its median are cut square and mitred at their corners, as
  # `GeomCrossbar` draws them. A line whose colour is `:none` or missing, whose line type is blank or
  # whose width is missing is not drawn, as R's graphics engine draws none, and a box's border so is
  # left off, its fill drawn. A box in radial coordinates is drawn between its placed corners, not
  # curved.
  #
  # Its legend key is ggplot2's `draw_key_boxplot()`, by fractions of the key: whiskers from a tenth
  # to a quarter of the way up and from three quarters to nine tenths, a box three quarters wide and
  # half as tall in the middle, a median across it from an eighth to seven eighths, and staples
  # across the whiskers' ends, `0.75 * staplewidth` of the key wide, drawn though they have no length
  # at a `staplewidth` of 0, as ggplot2 draws them; each line in its part's look, else the key's
  # colour, line type and width, the median not doubled, the box filled in the key's fill at its
  # alpha, every line cut square and mitred; turned for a horizontal layer, which the legend says in
  # the key's `flipped_aes`, as ggplot2 hands `draw_key` the layer's `flipped_aes`. It needs its
  # `size` and `linewidth` added, in millimetres, as ggplot2's `set_key_size()` reads a key with no
  # size of its own, a missing one counting 0.

  @enforce_keys [
    :outliers,
    :outlier,
    :whisker,
    :staple,
    :median,
    :box,
    :notch,
    :notchwidth,
    :staplewidth,
    :varwidth
  ]
  defstruct @enforce_keys

  # A part's look as a layer gives it: an outlier's colour, fill, shape, size, stroke and alpha, or
  # a line's colour, line type and width, each only where given.
  @type look :: %{optional(atom()) => term()}

  @type t :: %__MODULE__{
          outliers: boolean(),
          outlier: look(),
          whisker: look(),
          staple: look(),
          median: look(),
          box: look(),
          notch: boolean(),
          notchwidth: float(),
          staplewidth: float(),
          varwidth: boolean()
        }

  # The aesthetics a layer of boxes can use, from its own mapping or the plot's, beside those its
  # summary reads.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics,
    do: [:alpha, :color, :fill, :group, :linetype, :linewidth, :shape, :size, :x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Aesthetics, Coord, DataFrame, Geom}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Geom.{Mark, Point}
    alias Giggly.Scene.{Polygons, Polylines, Rectangles, Segments}

    # ggplot2's default box: its colour, ink mixed 20% toward paper, its fill, the paper, its lines'
    # width in millimetres and line type, solid, and its outliers' shape and size.
    @color "#333333"
    @fill "#FFFFFF"
    @line_width 0.5
    @line_type {}
    @shape :circle
    @size 1.5
    @stroke 0.5

    # ggplot2's median, `fatten` times the box's line width.
    @median_fatten 2

    # Points in a millimetre, grid's `"mm"` in the scene's points, which a key's room is measured in.
    @points_per_millimetre 72 / 25.4

    @mitre_limit 10.0

    # The columns a box is drawn from, beside its look.
    @drawn [:x, :xmin, :xmax, :lower, :middle, :upper, :ymin, :ymax, :notchlower, :notchupper]

    @impl Giggly.Geom
    def setup_data(geom, frame, _axis_kinds) do
      flipped = flipped?(frame)

      frame
      |> flip(flipped)
      |> kept_outliers(geom.outliers)
      |> finals()
      |> sides(geom.varwidth)
      |> flip(flipped)
    end

    # The orientation the box plot's summary wrote, vertical where it wrote none.
    defp flipped?(frame) do
      if :flipped_aes in DataFrame.names(frame) do
        frame
        |> DataFrame.pull(:flipped_aes)
        |> Enum.find(false, fn flipped -> is_boolean(flipped) end)
      else
        false
      end
    end

    defp flip(frame, false), do: frame

    defp flip(frame, true) do
      renames =
        frame
        |> DataFrame.names()
        |> Aesthetics.flipped()

      DataFrame.select(frame, renames)
    end

    # The table without its outliers where the layer keeps none, as ggplot2 drops the column.
    defp kept_outliers(frame, true), do: frame
    defp kept_outliers(frame, false), do: without(frame, [:outliers])

    # Each box's `ymin_final` and `ymax_final`, R's `pmin()` of its outliers' least and its lower
    # whisker's end and `pmax()` of their greatest and its upper's, where the table keeps outliers;
    # a box with none reaches its whiskers' ends, as R's `min()` of none is infinite.
    defp finals(frame) do
      if :outliers in DataFrame.names(frame) do
        outliers = DataFrame.pull(frame, :outliers)
        low_ends = DataFrame.pull(frame, :ymin)
        high_ends = DataFrame.pull(frame, :ymax)

        frame
        |> DataFrame.put(:ymin_final, Enum.zip_with(outliers, low_ends, &least/2))
        |> DataFrame.put(:ymax_final, Enum.zip_with(outliers, high_ends, &greatest/2))
      else
        frame
      end
    end

    defp least(outliers, whisker_end) do
      outliers
      |> Enum.reduce(whisker_end, &Arithmetic.lesser/2)
      |> as_float()
    end

    defp greatest(outliers, whisker_end) do
      outliers
      |> Enum.reduce(whisker_end, &Arithmetic.greater/2)
      |> as_float()
    end

    # Each box's sides, its x less and plus half its width, or half its width times its share of the
    # layer's greatest `relvarwidth` with `varwidth`, in R's order; its `width` and `relvarwidth`
    # then dropped.
    defp sides(frame, varwidth) do
      x_positions = DataFrame.pull(frame, :x)
      halves = halves(frame, varwidth)

      frame
      |> without([:width, :relvarwidth])
      |> DataFrame.put(:xmin, Enum.zip_with(x_positions, halves, &Arithmetic.subtract/2))
      |> DataFrame.put(:xmax, Enum.zip_with(x_positions, halves, &Arithmetic.add/2))
    end

    defp halves(frame, false) do
      frame
      |> DataFrame.pull(:width)
      |> Enum.map(fn width -> Arithmetic.divide(width, 2) end)
    end

    defp halves(frame, true) do
      relative = DataFrame.pull(frame, :relvarwidth)
      greatest = Enum.max(relative, fn -> nil end)

      frame
      |> DataFrame.pull(:width)
      |> Enum.zip_with(relative, fn width, share ->
        share
        |> Arithmetic.divide(greatest)
        |> Arithmetic.multiply(width)
        |> Arithmetic.divide(2)
      end)
    end

    defp without(frame, names) do
      kept =
        frame
        |> DataFrame.names()
        |> Enum.reject(fn name -> name in names end)
        |> Enum.map(fn name -> {name, name} end)

      DataFrame.select(frame, kept)
    end

    # Each box, in the order of their groups, drawn whole before the next.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params) do
      flipped = flipped?(frame)
      placing = {flipped, coord, panel_params}

      frame
      |> flip(flipped)
      |> boxes()
      |> Enum.sort_by(fn box -> box.group end)
      |> Enum.flat_map(fn box ->
        Enum.concat([
          outliers(geom, box, placing),
          staples(geom, box, placing),
          whiskers(geom, box, placing),
          crossbar(geom, box, placing)
        ])
      end)
    end

    # Each row of a vertical table as a box: where it is drawn and how it looks.
    defp boxes(frame) do
      looks = [
        color: Mark.colors(frame, :color, @color),
        fill: Mark.colors(frame, :fill, @fill),
        alpha: Mark.values(frame, :alpha, nil),
        linetype: Mark.line_types(frame),
        linewidth: Mark.values(frame, :linewidth, @line_width),
        shape: Mark.values(frame, :shape, @shape),
        size: Mark.values(frame, :size, @size),
        outliers:
          frame
          |> Mark.values(:outliers, [])
          |> Enum.map(fn listed -> listed || [] end),
        group: DataFrame.pull(frame, :group)
      ]

      columns = Enum.map(@drawn, fn name -> {name, DataFrame.pull(frame, name)} end) ++ looks
      names = Keyword.keys(columns)

      columns
      |> Keyword.values()
      |> Enum.zip_with(fn values ->
        names
        |> Enum.zip(values)
        |> Map.new()
      end)
    end

    # A box's outliers as points at its x, in the outliers' look, else the box's.
    defp outliers(_geom, %{outliers: []}, _placing), do: []

    defp outliers(geom, box, {flipped, coord, panel_params}) do
      look = geom.outlier
      count = length(box.outliers)
      positions = List.duplicate(box.x, count)

      {x_positions, y_positions} =
        if flipped, do: {box.outliers, positions}, else: {positions, box.outliers}

      points =
        DataFrame.new(
          x: x_positions,
          y: y_positions,
          color: List.duplicate(missing_for_none(Map.get(look, :color, box.color)), count),
          fill: List.duplicate(missing_for_none(Map.get(look, :fill, box.fill)), count),
          shape: List.duplicate(Map.get(look, :shape, box.shape), count),
          size: List.duplicate(Map.get(look, :size, box.size), count),
          stroke: List.duplicate(Map.get(look, :stroke, @stroke), count),
          alpha: List.duplicate(Map.get(look, :alpha, box.alpha), count)
        )

      Geom.draw_panel(%Point{}, points, coord, panel_params)
    end

    # A colour the box reads as `:none` held as a missing one, as a column holds R's `NA`.
    defp missing_for_none(:none), do: nil
    defp missing_for_none(color), do: color

    # A box's staples across its whiskers' ends, the upper first, where they have a width.
    defp staples(%{staplewidth: staplewidth}, _box, _placing) when staplewidth == 0, do: []

    defp staples(geom, box, placing) do
      left = staple_end(box.xmin, box.x, geom.staplewidth)
      right = staple_end(box.xmax, box.x, geom.staplewidth)

      segments(
        [{{left, box.ymax}, {right, box.ymax}}, {{left, box.ymin}, {right, box.ymin}}],
        line_look(geom.staple, box),
        {:butt, :round},
        placing
      )
    end

    # A staple's end, R's `(xmin - x) * staplewidth + x`.
    defp staple_end(side, x_position, staplewidth) do
      side
      |> Arithmetic.subtract(x_position)
      |> Arithmetic.multiply(staplewidth)
      |> Arithmetic.add(x_position)
    end

    # A box's whiskers, from its upper hinge to `ymax` and from its lower to `ymin`.
    defp whiskers(geom, box, placing) do
      segments(
        [{{box.x, box.upper}, {box.x, box.ymax}}, {{box.x, box.lower}, {box.x, box.ymin}}],
        line_look(geom.whisker, box),
        {:butt, :round},
        placing
      )
    end

    # A box and its median, as ggplot2's `GeomCrossbar` draws them, pinched in at the notches where
    # the layer notches its boxes.
    defp crossbar(geom, box, placing) do
      notched = geom.notch and is_number(box.notchlower) and is_number(box.notchupper)
      indent = if notched, do: indent(box, geom.notchwidth), else: 0.0

      outlined = outline(box, notched, indent)
      box_look = line_look(geom.box, box)
      median_start = Arithmetic.add(box.xmin, indent)
      median_end = Arithmetic.subtract(box.xmax, indent)
      median = [{{median_start, box.middle}, {median_end, box.middle}}]
      median_look = median_look(geom.median, box)

      drawn_box = polygon(outlined, box_look, box, placing)
      Enum.concat(drawn_box, segments(median, median_look, {:butt, :mitre}, placing))
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

    # A line's look, `{color, width, line type}`: the part's, else the box's.
    defp line_look(part, box) do
      {Map.get(part, :color, box.color), Map.get(part, :linewidth, box.linewidth),
       Map.get(part, :linetype, box.linetype)}
    end

    # The median's look: its own, else the box's, twice as wide.
    defp median_look(median, box) do
      {Map.get(median, :color, box.color),
       Map.get(median, :linewidth, Arithmetic.multiply(box.linewidth, @median_fatten)),
       Map.get(median, :linetype, box.linetype)}
    end

    # Straight lines in one look, each `{start, end}` in a vertical box's terms, placed in the
    # panel; none where the look draws no line, and a line with an end missing left out.
    defp segments(lines, {color, width, line_type}, {line_end, line_join}, placing) do
      color = color || :none

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
            mitre_limit: @mitre_limit
          }
        ]
      end
    end

    # The box round its outline, in a vertical box's terms, placed in the panel, filled at its
    # alpha and bordered in its look, left off where the look draws no line; none where a corner is
    # missing.
    defp polygon(outline, {color, width, line_type}, box, placing) do
      placed = place(outline, placing)
      border = if drawn_line?(color || :none, width, line_type), do: color, else: :none
      border_width = width || 0.0

      if Enum.all?(placed, &placed?/1) do
        [
          %Polygons{
            outlines: [placed],
            offsets: :none,
            stroke_width: Mark.stroke_width(border_width),
            color: [Mark.hex(border)],
            color_opacity: [Mark.own_opacity(border)],
            fill: [Mark.hex(box.fill)],
            fill_opacity: [Mark.opacity(box.fill, box.alpha)],
            dashes: Mark.dashes(line_type, border_width),
            line_end: :butt,
            line_join: :mitre,
            mitre_limit: @mitre_limit
          }
        ]
      else
        []
      end
    end

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

    # A legend's key, ggplot2's `draw_key_boxplot()`, turned for a horizontal layer.
    @impl Giggly.Geom
    def draw_key(geom, key) do
      base = %{
        color: Map.get(key, :color, @color),
        linewidth: Map.get(key, :linewidth, @line_width),
        linetype: Map.get(key, :linetype, @line_type) || :none
      }

      fill = Map.get(key, :fill, @fill)
      turn = if Map.get(key, :flipped_aes, false), do: &turned/1, else: &Function.identity/1
      reach = 0.375 * geom.staplewidth

      Enum.concat([
        key_lines(
          [[{0.5, 0.1}, {0.5, 0.25}], [{0.5, 0.75}, {0.5, 0.9}]],
          geom.whisker,
          base,
          turn
        ),
        key_box(line_look(geom.box, base), fill, Map.get(key, :alpha), turn),
        key_lines([[{0.125, 0.5}, {0.875, 0.5}]], geom.median, base, turn),
        key_lines(
          [[{0.5 + reach, 0.1}, {0.5 - reach, 0.1}], [{0.5 + reach, 0.9}, {0.5 - reach, 0.9}]],
          geom.staple,
          base,
          turn
        )
      ])
    end

    defp turned({across, up}), do: {up, across}

    defp key_lines(lines, part, base, turn) do
      {color, width, line_type} = line_look(part, base)
      color = color || :none
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
            line_end: :butt,
            line_join: :mitre,
            mitre_limit: @mitre_limit
          }
        ]
      else
        []
      end
    end

    # The key's box, three quarters of the key wide and half as tall, in its middle.
    defp key_box({color, width, line_type}, fill, alpha, turn) do
      border = if drawn_line?(color || :none, width, line_type), do: color, else: :none
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
          line_end: :butt,
          line_join: :mitre,
          mitre_limit: @mitre_limit
        }
      ]
    end

    # The room a key needs, its size and line width added, in millimetres, either way, a missing
    # one counting 0, as ggplot2's `set_key_size()` reads a key with no size of its own.
    @impl Giggly.Geom
    def key_size(_geom, key) do
      side =
        [Map.get(key, :size, @size), Map.get(key, :linewidth, @line_width)]
        |> Enum.map(fn millimetres -> millimetres || 0.0 end)
        |> Enum.sum()
        |> Kernel.*(@points_per_millimetre)

      {side, side}
    end

    defp as_float(value) when is_integer(value), do: value / 1
    defp as_float(value), do: value
  end
end
