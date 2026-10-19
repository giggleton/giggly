defmodule Giggly.Geom.Path do
  @moduledoc false

  # Paths, ggplot2's `GeomPath`, which `geom_path()` draws with: a line through each group's rows
  # in the order the data gives them. Its parameters are how a line's ends are drawn (`line_end`,
  # ggplot2's `lineend`), how it turns a corner (`line_join`, `linejoin`) and how far a mitred
  # corner may reach (`mitre_limit`, `linemitre`). Lines (`Giggly.Geom.Line`) draw as a path once
  # their rows are in order. Use it through `Giggly.Geom`.
  #
  # Paths use `:x`, `:y`, `:group`, `:alpha` and `:color`, and need `:x` and `:y`; an aesthetic
  # joins the accepted list with the scale that maps it, so a mapping never silently does nothing.
  #
  # A path is drawn as ggplot2's `GeomPath` draws one. Rows missing `x` or `y` (`nil`, or the float
  # `:nan`), or whose colour is `:none`, R's `NA`, or missing, at the start or end of a group are
  # dropped, as `handle_na()` drops them, and one missing a position in the middle breaks the line
  # there, as grid breaks a polyline; ggplot2 also warns of the rows it drops, which a pure
  # pipeline cannot. The rows are put in group order, keeping each group's own order, and cut into
  # steps that follow the panel's curves (`Giggly.Coord.munch/3`); a group of fewer than two rows
  # is not drawn. Where every group keeps one colour and one alpha all along it, each group is one
  # line, drawn in its first row's colour and alpha; where any group's vary, every group is drawn a
  # segment from each row to the next, each in the colour and alpha of the row it starts from, and
  # a segment touching a missing position is not drawn.
  #
  # Every line looks as ggplot2's default line does, until aesthetics such as linetype can be
  # mapped: solid, 0.5 mm wide, which grid draws 1.07 points wide, or as wide as the `linewidth` a
  # layer sets, in millimetres, and black, or its row's colour, mapped or set. A row's `alpha`,
  # where its table has one, makes its line that opaque, replacing its colour's own; a row without
  # one keeps its colour's (`Giggly.Geom.Mark`).

  @enforce_keys [:line_end, :line_join, :mitre_limit]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          line_end: Giggly.Scene.Polylines.line_end(),
          line_join: Giggly.Scene.Polylines.line_join(),
          mitre_limit: float()
        }

  # The aesthetics a layer of paths can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:alpha, :color, :group, :x, :y]

  # The aesthetics a layer of paths cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame}
    alias Giggly.Geom.Mark
    alias Giggly.Scene.{Polylines, Segments}

    # ggplot2's default line: its width in millimetres and its ink.
    @line_width 0.5
    @color "#000000"

    # ggplot2's `.pt` (font points per millimetre), and the line-width units and points in an inch:
    # a line `linewidth` millimetres wide is drawn `linewidth * .pt` units of 1/96 inch wide, which
    # svglite writes in points.
    @font_points_per_millimetre 72.27 / 25.4
    @line_width_units_per_inch 96
    @points_per_inch 72

    # A legend's key, `draw_key_path()`: a line across the middle of the key, from a tenth of its
    # width to nine tenths, its corners grid's default, round.
    @key_start {0.1, 0.5}
    @key_end {0.9, 0.5}

    # A path is drawn at its x and y alone, in the data's order.
    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds), do: frame

    # The panel's lines.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params) do
      kept =
        frame
        |> trimmed()
        |> by_group()

      drawn =
        coord
        |> Coord.munch(kept, panel_params)
        |> without_short_groups()

      case DataFrame.row_count(drawn) do
        0 -> []
        _rows -> [draw(geom, drawn, constant?(drawn))]
      end
    end

    # A legend's key, in the key's colour at its alpha; a colour of `:none` draws nothing.
    @impl Giggly.Geom
    def draw_key(geom, key, _size) do
      case Map.get(key, :color, @color) do
        :none ->
          []

        color ->
          [
            %Segments{
              starts: [@key_start],
              ends: [@key_end],
              stroke_width: points(Map.get(key, :linewidth, @line_width)),
              color: [Mark.hex(color)],
              opacity: [Mark.opacity(color, Map.get(key, :alpha))],
              line_end: geom.line_end,
              line_join: :round,
              mitre_limit: 10.0
            }
          ]
      end
    end

    # Each group a line, in its first row's colour and alpha, broken where a position is missing, as
    # grid breaks a polyline; a piece of one point draws nothing.
    defp draw(geom, frame, true) do
      {lines, looks} =
        frame
        |> rows()
        |> Enum.chunk_by(fn row -> row.group end)
        |> Enum.flat_map(fn [first | _rest] = group_rows ->
          group_rows
          |> Enum.chunk_by(fn row -> placed?(row) end)
          |> Enum.filter(fn
            [first_row, _second_row | _rest] -> placed?(first_row)
            [_lone_row] -> false
          end)
          |> Enum.map(fn piece -> {Enum.map(piece, &position/1), first} end)
        end)
        |> Enum.unzip()

      %Polylines{
        lines: lines,
        offsets: :none,
        stroke_width: stroke_width(frame),
        color: Enum.map(looks, fn row -> Mark.hex(row.color) end),
        opacity: Enum.map(looks, fn row -> Mark.opacity(row.color, row.alpha) end),
        line_end: geom.line_end,
        line_join: geom.line_join,
        mitre_limit: geom.mitre_limit
      }
    end

    # A segment from each row to the next of its group, in the colour and alpha of the row it starts
    # from; a segment touching a missing position is not drawn.
    defp draw(geom, frame, false) do
      segments =
        frame
        |> rows()
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.filter(fn [from, to] ->
          from.group == to.group and placed?(from) and placed?(to)
        end)

      %Segments{
        starts: Enum.map(segments, fn [from, _to] -> position(from) end),
        ends: Enum.map(segments, fn [_from, to] -> position(to) end),
        stroke_width: stroke_width(frame),
        color: Enum.map(segments, fn [from, _to] -> Mark.hex(from.color) end),
        opacity: Enum.map(segments, fn [from, _to] -> Mark.opacity(from.color, from.alpha) end),
        line_end: geom.line_end,
        line_join: geom.line_join,
        mitre_limit: geom.mitre_limit
      }
    end

    # The rows of each group from its first with both positions to its last, as ggplot2's
    # `keep_mid_true()` keeps them, a group's rows in their order wherever they are in the frame.
    defp trimmed(frame) do
      kept =
        frame
        |> rows()
        |> Enum.with_index()
        |> Enum.group_by(fn {row, _index} -> row.group end)
        |> Enum.flat_map(fn {_group, group_rows} ->
          group_rows
          |> Enum.drop_while(fn {row, _index} -> not complete?(row) end)
          |> Enum.reverse()
          |> Enum.drop_while(fn {row, _index} -> not complete?(row) end)
          |> Enum.map(fn {_row, index} -> index end)
        end)
        |> Enum.sort()

      DataFrame.slice(frame, kept)
    end

    # The rows in group order, each group's in their own, as ggplot2's `order(data$group)` keeps
    # ties in place.
    defp by_group(frame) do
      order =
        frame
        |> DataFrame.pull(:group)
        |> Enum.with_index()
        |> Enum.sort_by(fn {group, _index} -> group end)
        |> Enum.map(fn {_group, index} -> index end)

      DataFrame.slice(frame, order)
    end

    # The rows of groups of at least two rows, counting rows missing a position.
    defp without_short_groups(frame) do
      sizes =
        frame
        |> DataFrame.pull(:group)
        |> Enum.frequencies()

      kept =
        frame
        |> DataFrame.pull(:group)
        |> Enum.with_index()
        |> Enum.filter(fn {group, _index} -> Map.fetch!(sizes, group) > 1 end)
        |> Enum.map(fn {_group, index} -> index end)

      DataFrame.slice(frame, kept)
    end

    # Whether every group keeps one colour and one alpha all along it, ggplot2's test for drawing a
    # group as one line rather than segments; a table without alpha is opaque throughout.
    defp constant?(frame) do
      frame
      |> rows()
      |> Enum.group_by(fn row -> row.group end, fn row -> {row.color, row.alpha} end)
      |> Enum.all?(fn {_group, looks} -> match?([_one], Enum.uniq(looks)) end)
    end

    # Each row's positions, group, colour, black for a table without one, and alpha, `nil` for a
    # table without one.
    defp rows(frame) do
      Enum.zip_with(
        [
          DataFrame.pull(frame, :x),
          DataFrame.pull(frame, :y),
          DataFrame.pull(frame, :group),
          Mark.colors(frame, :color, @color),
          Mark.values(frame, :alpha, nil)
        ],
        fn [x_position, y_position, group, color, alpha] ->
          %{x: x_position, y: y_position, group: group, color: color, alpha: alpha}
        end
      )
    end

    # A row with both positions and a colour, before it is placed, as R's `complete.cases()` finds
    # one, an infinite position counting as present and a colour of `:none` as missing, a colour
    # read by `Mark.colors/3` so a missing one is `:none` too.
    defp complete?(row),
      do: not missing?(row.x) and not missing?(row.y) and row.color != :none

    defp missing?(position), do: position in [nil, :nan]

    # A row placed in the panel, both its positions numbers.
    defp placed?(row), do: is_number(row.x) and is_number(row.y)

    defp position(row), do: {row.x, row.y}

    # The layer's line width in points, from the width it sets in millimetres, the same in every
    # row, or ggplot2's default.
    defp stroke_width(frame) do
      frame
      |> Mark.set(:linewidth, @line_width)
      |> points()
    end

    # A line `millimetres` wide, in points, worked out in ggplot2's and svglite's order.
    defp points(millimetres),
      do:
        millimetres * @font_points_per_millimetre / @line_width_units_per_inch * @points_per_inch
  end
end
