defmodule Giggly.Geom.Rug do
  @moduledoc false

  # Rugs, ggplot2's `GeomRug`, which `geom_rug()` draws with: a short line at the panel's edge for
  # each row, at its `x` along the bottom or top and at its `y` along the left or right, so the
  # margins show each axis's distribution. Its parameters are the sides it draws along (`sides`,
  # each of `:bottom`, `:top`, `:left` and `:right`, ggplot2's `sides` string), how long each line
  # is (`length`: a share of the panel, `{share, :npc}`, or a number of points,
  # `{points, :points}`, ggplot2's `length` unit) and how its ends are drawn (`line_end`,
  # ggplot2's `lineend`). Use it through `Giggly.Geom`.
  #
  # Rugs use `:x`, `:y`, `:group`, `:alpha`, `:color`, `:linetype` and `:linewidth`, and need one
  # of `:x` and `:y`, where ggplot2's `GeomRug` needs neither and draws nothing with neither; a
  # side whose axis the layer does not map draws nothing, as in ggplot2.
  #
  # A rug is drawn as ggplot2's `GeomRug` draws one. Its rows are those its sides can draw, as
  # `GeomRug$handle_na()` keeps them: along the bottom or top, the rows with an `x`, and along the
  # left or right, those with a `y`, a missing position being `nil` or the float `:nan`; where it
  # draws along both axes, the rows with an `x` and then those with a `y`, a row repeated in every
  # column kept once, where it first appears, as `vctrs::vec_set_union()` joins them
  # (`Giggly.DataFrame.distinct/1`), so translucent lines repeating a row darken along one axis's
  # sides alone. The rows are placed through the
  # coordinate system (`Giggly.Coord.transform/3`), an infinite position at the panel's edge, and
  # the sides drawn in ggplot2's order, bottom, top, left, right, whatever the order given: each a
  # straight line per row with a place on its axis, from the panel's edge inward, in its row's
  # colour at its alpha, width and line type, as grid's `segmentsGrob()` draws one, each run of a
  # side's lines alike in width and line type one primitive. A row missing its width or line
  # type, or of a blank line type, draws no line, as R's graphics engine draws none, and a colour
  # of `:none`, R's `NA`, a line of no stroke, as svglite writes one. A share of the panel puts a
  # line's inner end that far in, a place in the cell; a number of points leaves it at the edge,
  # moved in by that many, as grid works out `unit(1, "npc") - unit(12, "pt")`. Under coordinates
  # whose lines curve the lines are straight all the same, from the panel's square edges at each
  # row's place, as ggplot2's are; radial coordinates refuse a rug missing `x` or `y`
  # (`Giggly.Coord.transform/3`), as ggplot2's fail to place a row without both.
  #
  # A rug the layer neither maps nor sets a look for looks as a path does, ggplot2's
  # `GeomRug$default_aes` being `GeomPath$default_aes`, and its legend key is a path's,
  # `draw_key_path()`, with the rug's line ends.

  @enforce_keys [:sides, :length, :line_end]
  defstruct @enforce_keys

  @typedoc "A side of the panel a rug is drawn along."
  @type side :: :bottom | :top | :left | :right

  @type t :: %__MODULE__{
          sides: [side()],
          length: {float(), :npc | :points},
          line_end: Giggly.Scene.Polylines.line_end()
        }

  # The aesthetics a layer of rugs can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:alpha, :color, :group, :linetype, :linewidth, :x, :y]

  # The aesthetics a layer of rugs cannot be drawn without: one of its positions.
  @doc false
  @spec required_aesthetics() :: [atom() | [atom()]]
  def required_aesthetics, do: [[:x, :y]]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame, Geom}
    alias Giggly.Geom.Mark
    alias Giggly.Scene.Segments

    # grid's mitre limit, which ggplot2's rugs are drawn at.
    @mitre_limit 10.0

    # Each side in the order ggplot2 draws them: the axis whose places it draws, the edge it is
    # drawn from, 0 or 1 across the other axis, and which way is in from there.
    @sides [
      bottom: {:x, 0.0, 1.0},
      top: {:x, 1.0, -1.0},
      left: {:y, 0.0, 1.0},
      right: {:y, 1.0, -1.0}
    ]

    @impl Giggly.Geom
    def default_aesthetics(geom, element) do
      geom
      |> path()
      |> Geom.default_aesthetics(element)
    end

    # A rug is drawn at its rows' places alone, in the data's order.
    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds), do: frame

    # The panel's rugs: each side the layer gives, in ggplot2's order, from the rows its sides can
    # draw.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params) do
      sides = Enum.filter(@sides, fn {side, _drawing} -> side in geom.sides end)

      axes =
        sides
        |> Enum.map(fn {_side, {axis, _edge, _inward}} -> axis end)
        |> Enum.uniq()

      placed = Coord.transform(coord, drawable(frame, axes), panel_params)
      names = DataFrame.names(placed)

      sides
      |> Enum.filter(fn {_side, {axis, _edge, _inward}} -> axis in names end)
      |> Enum.flat_map(fn {_side, drawing} -> draw_side(geom, placed, drawing) end)
    end

    @impl Giggly.Geom
    def draw_key(geom, key) do
      geom
      |> path()
      |> Geom.draw_key(key)
    end

    @impl Giggly.Geom
    def key_size(geom, key) do
      geom
      |> path()
      |> Geom.key_size(key)
    end

    # The path a rug's legend key is drawn as, with the rug's line ends and grid's round corners.
    defp path(geom) do
      %Geom.Path{
        line_end: geom.line_end,
        line_join: :round,
        mitre_limit: @mitre_limit,
        arrow: :none
      }
    end

    # The rows the sides draw from: along both axes, the rows with an `x` and then those with a
    # `y`, each repeated row kept once, as `vctrs::vec_set_union()` joins them; along one, every
    # row, each side leaving out those missing its place.
    defp drawable(frame, [:x, :y]) do
      frame
      |> DataFrame.slice(present(frame, :x) ++ present(frame, :y))
      |> DataFrame.distinct()
    end

    defp drawable(frame, _axes), do: frame

    # The indices of the rows with a place on `axis`, or none where the layer has no such column:
    # ggplot2 then joins every row, but those it adds either repeat a row with a place on the
    # other axis or have none, and the missing axis's sides draw nothing, so they draw nothing.
    defp present(frame, axis) do
      if axis in DataFrame.names(frame) do
        frame
        |> DataFrame.pull(axis)
        |> Enum.with_index()
        |> Enum.reject(fn {place, _index} -> missing?(place) end)
        |> Enum.map(fn {_place, index} -> index end)
      else
        []
      end
    end

    # One side's lines: a straight line for each row with a place on the side's axis, a width and
    # a line type that is not blank, from the edge in, in its colour at its alpha, width and line
    # type, in row order, each run alike in width and line type one primitive.
    defp draw_side(geom, placed, {axis, edge, inward}) do
      colors = Mark.colors(placed, :color)

      [axis, :alpha, :linewidth, :linetype]
      |> Enum.map(fn name -> DataFrame.pull(placed, name) end)
      |> List.insert_at(1, colors)
      |> Enum.zip_with(fn [place, color, alpha, line_width, line_type] ->
        %{
          place: place,
          color: color,
          opacity: Mark.opacity(color, alpha),
          line: {line_width, line_type}
        }
      end)
      |> Enum.reject(fn %{place: place, line: {line_width, line_type}} ->
        missing?(place) or missing?(line_width) or line_type in [nil, :none]
      end)
      |> Enum.chunk_by(fn line -> line.line end)
      |> Enum.map(fn [%{line: {line_width, line_type}} | _rest] = lines ->
        {starts, ends, offsets} = ends(geom.length, axis, edge, inward, lines)

        %Segments{
          starts: starts,
          ends: ends,
          offsets: offsets,
          stroke_width: Mark.stroke_width(line_width),
          dashes: Mark.dashes(line_type, line_width),
          color: Enum.map(lines, fn line -> Mark.hex(line.color) end),
          opacity: Enum.map(lines, fn line -> line.opacity end),
          line_end: geom.line_end,
          line_join: :round,
          mitre_limit: @mitre_limit,
          arrows: :none
        }
      end)
    end

    defp missing?(value), do: value in [nil, :nan]

    # Each line's start at the edge and its end: a share of the panel in from the edge, or at the
    # edge and moved that many points in.
    defp ends({share, :npc}, axis, edge, inward, lines) do
      inner = edge + inward * share
      starts = Enum.map(lines, fn line -> at(axis, line.place, edge) end)
      ends = Enum.map(lines, fn line -> at(axis, line.place, inner) end)
      {starts, ends, :none}
    end

    defp ends({points, :points}, axis, edge, inward, lines) do
      starts = Enum.map(lines, fn line -> at(axis, line.place, edge) end)
      moved = at(axis, 0.0, inward * points)
      offsets = Enum.map(lines, fn _line -> {{0.0, 0.0}, moved} end)
      {starts, starts, offsets}
    end

    # The point at `place` along `axis` and `across` the other.
    defp at(:x, place, across), do: {place, across}
    defp at(:y, place, across), do: {across, place}
  end
end
