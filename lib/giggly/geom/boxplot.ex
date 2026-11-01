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
  # fill, shape, size and alpha, the theme's points' by default, their stroke the look's; its
  # staples, where `staplewidth` is not 0, across the ends of its whiskers, the upper first,
  # `staplewidth` of its width; its whiskers, from `upper` to `ymax` and from `lower` to `ymin`; its
  # box, a polygon round its hinges and sides, pinched in to its median between its notches where
  # `notch` is set, `1 - notchwidth` of half its width; and its median across it, as far in. Each
  # line is in its part's look, else the box's colour, line type and width, and never takes the
  # box's alpha, as ggplot2 draws each with `alpha = NA`; the median is twice the box's width,
  # ggplot2's `fatten`, unless its look gives a width; the box's fill takes the alpha and its border
  # does not. A box the layer neither maps nor sets a look for is ggplot2's default box under the
  # plot's theme: the theme's ink mixed 20% toward its paper, `#333333` on white paper, filled with
  # its paper, its lines as wide as the theme's borders, 0.5 mm at its default sizes, and solid.
  # Staples and whiskers are cut square at their ends, as ggplot2's `GeomSegment` draws them; the
  # box and its median are cut square and mitred at their corners, as `GeomCrossbar` draws them. A
  # line whose colour is `:none` or missing, whose line type is blank or whose width is missing is
  # not drawn, as R's graphics engine draws none, and a box's border so is left off, its fill drawn;
  # a line missing an end, one a scale's limits cut, is left out, and a box missing a corner is
  # drawn in the runs of two corners or more left, as grid splits a polygon at a missing point. A
  # box in radial coordinates is drawn between its placed corners, not curved.
  #
  # Its legend key is ggplot2's `draw_key_boxplot()`, by fractions of the key: whiskers from a tenth
  # to a quarter of the way up and from three quarters to nine tenths, a box three quarters wide and
  # half as tall in the middle, a median across it from an eighth to seven eighths, and staples
  # across the whiskers' ends, `0.75 * staplewidth` of the key wide, drawn though they have no length
  # at a `staplewidth` of 0, as ggplot2 draws them; each line in its part's look, else the key's
  # colour, line type and width, the median not doubled, the box filled in the key's fill at its
  # alpha, every line cut square and mitred; turned for a horizontal layer, which the legend always
  # says in the key's `flipped_aes`, as ggplot2 hands `draw_key` the layer's `flipped_aes`. It needs its
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

    alias Giggly.{Aesthetics, DataFrame, Geom}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Geom.{Crossbar, Mark, Point}
    alias Scales.ColorOperations

    # How far a box's default colour is mixed from the theme's ink toward its paper, ggplot2's
    # `col_mix(ink, paper, 0.2)`.
    @color_toward_paper 0.2

    # ggplot2's median, `fatten` times the box's line width.
    @median_fatten 2

    # Points in a millimetre, grid's `"mm"` in the scene's points, which a key's room is measured in.
    @points_per_millimetre 72 / 25.4

    # The columns a box is drawn from, beside its look.
    @drawn [:x, :xmin, :xmax, :lower, :middle, :upper, :ymin, :ymax, :notchlower, :notchupper]

    # ggplot2's `GeomBoxplot$default_aes`, as far as Giggly draws a box: the theme's ink mixed
    # toward its paper, a fill of its paper, its points' size, no alpha, its points' shape, and its
    # borders' line type and width. R's `weight` and `width`, which no box reads once it is set up,
    # are left out.
    @impl Giggly.Geom
    def default_aesthetics(_geom, element) do
      [
        color: ColorOperations.mix(element.ink, element.paper, @color_toward_paper),
        fill: element.paper,
        size: element.pointsize,
        alpha: nil,
        shape: element.pointshape,
        linetype: element.bordertype,
        linewidth: element.borderwidth
      ]
    end

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

    # The orientation the box plot's summary wrote in every row, vertical for a table of no boxes.
    defp flipped?(frame) do
      frame
      |> DataFrame.pull(:flipped_aes)
      |> Enum.find(false, fn flipped -> is_boolean(flipped) end)
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
    def draw_panel(geom, frame, coord, panel_params, installed_fonts) do
      flipped = flipped?(frame)
      placing = {flipped, coord, panel_params}

      frame
      |> flip(flipped)
      |> boxes()
      |> Enum.sort_by(fn box -> box.group end)
      |> Enum.flat_map(fn box ->
        Enum.concat([
          outliers(geom, box, placing, installed_fonts),
          staples(geom, box, placing),
          whiskers(geom, box, placing),
          crossbar(geom, box, placing)
        ])
      end)
    end

    # Each row of a vertical table as a box: where it is drawn and how it looks.
    defp boxes(frame) do
      looks = [
        color: Mark.colors(frame, :color),
        fill: Mark.colors(frame, :fill),
        alpha: DataFrame.pull(frame, :alpha),
        linetype: Mark.line_types(frame),
        linewidth: DataFrame.pull(frame, :linewidth),
        shape: DataFrame.pull(frame, :shape),
        size: DataFrame.pull(frame, :size),
        outliers: outliers(frame),
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

    # A box's outliers as points at its x, in the outliers' look, else the box's, their stroke the
    # look's, which the layer always gives.
    defp outliers(geom, box, {flipped, coord, panel_params}, installed_fonts) do
      look = geom.outlier
      count = length(box.outliers)
      positions = List.duplicate(box.x, count)

      {x_positions, y_positions} =
        if flipped, do: {box.outliers, positions}, else: {positions, box.outliers}

      points =
        DataFrame.new(
          x: x_positions,
          y: y_positions,
          color: List.duplicate(Map.get(look, :color, box.color), count),
          fill: List.duplicate(Map.get(look, :fill, box.fill), count),
          shape: List.duplicate(Map.get(look, :shape, box.shape), count),
          size: List.duplicate(Map.get(look, :size, box.size), count),
          stroke: List.duplicate(Map.fetch!(look, :stroke), count),
          alpha: List.duplicate(Map.get(look, :alpha, box.alpha), count)
        )

      Geom.draw_panel(%Point{}, points, coord, panel_params, installed_fonts)
    end

    # A box's staples across its whiskers' ends, the upper first, where they have a width.
    defp staples(%{staplewidth: staplewidth}, _box, _placing) when staplewidth == 0, do: []

    defp staples(geom, box, placing) do
      left = staple_end(box.xmin, box.x, geom.staplewidth)
      right = staple_end(box.xmax, box.x, geom.staplewidth)

      Crossbar.segments(
        [{{left, box.ymax}, {right, box.ymax}}, {{left, box.ymin}, {right, box.ymin}}],
        Crossbar.line_look(geom.staple, box),
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
      Crossbar.segments(
        [{{box.x, box.upper}, {box.x, box.ymax}}, {{box.x, box.lower}, {box.x, box.ymin}}],
        Crossbar.line_look(geom.whisker, box),
        {:butt, :round},
        placing
      )
    end

    # A box and its median, drawn as a crossbar (`Giggly.Geom.Crossbar.parts/3`), as ggplot2's
    # `GeomBoxplot` hands them to `GeomCrossbar`, its median twice the box's width, pinched in at
    # the notches where the layer notches its boxes, cut square and mitred.
    defp crossbar(geom, box, placing) do
      style = %{
        box: geom.box,
        middle: geom.median,
        fatten: @median_fatten,
        notch: geom.notch,
        notchwidth: geom.notchwidth,
        line_end: :butt,
        line_join: :mitre
      }

      {drawn_box, median} = Crossbar.parts(box, style, placing)
      Enum.concat(drawn_box, median)
    end

    # A legend's key, ggplot2's `draw_key_boxplot()`, turned for a horizontal layer: its whiskers,
    # a crossbar's key (`Giggly.Geom.Crossbar.key/5`) and its staples, cut square and mitred.
    @impl Giggly.Geom
    def draw_key(geom, key, _installed_fonts) do
      base = %{
        color: Mark.key_color(key, :color),
        linewidth: Map.fetch!(key, :linewidth),
        linetype: Map.fetch!(key, :linetype) || :none
      }

      fill = {Mark.key_color(key, :fill), Map.fetch!(key, :alpha)}
      turn = if Map.fetch!(key, :flipped_aes), do: &turned/1, else: &Function.identity/1
      reach = 0.375 * geom.staplewidth
      ends = {:butt, :mitre}

      Enum.concat([
        Crossbar.key_lines(
          [[{0.5, 0.1}, {0.5, 0.25}], [{0.5, 0.75}, {0.5, 0.9}]],
          geom.whisker,
          base,
          turn,
          ends
        ),
        Crossbar.key(base, fill, {geom.box, geom.median}, turn, ends),
        Crossbar.key_lines(
          [[{0.5 + reach, 0.1}, {0.5 - reach, 0.1}], [{0.5 + reach, 0.9}, {0.5 - reach, 0.9}]],
          geom.staple,
          base,
          turn,
          ends
        )
      ])
    end

    defp turned({across, up}), do: {up, across}

    # The room a key needs, its size and line width added, in millimetres, either way, a missing
    # one counting 0, as ggplot2's `set_key_size()` reads a key with no size of its own.
    @impl Giggly.Geom
    def key_size(_geom, key, _installed_fonts) do
      side =
        [Map.fetch!(key, :size), Map.fetch!(key, :linewidth)]
        |> Enum.map(fn millimetres -> millimetres || 0.0 end)
        |> Enum.sum()
        |> Kernel.*(@points_per_millimetre)

      {side, side}
    end

    # Each box's outliers, none where the layer keeps none, whose column `setup_data/3` dropped.
    defp outliers(frame) do
      if :outliers in DataFrame.names(frame),
        do: DataFrame.pull(frame, :outliers),
        else: List.duplicate([], DataFrame.row_count(frame))
    end

    defp as_float(value) when is_integer(value), do: value / 1
    defp as_float(value), do: value
  end
end
