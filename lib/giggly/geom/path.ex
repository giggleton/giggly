defmodule Giggly.Geom.Path do
  @moduledoc false

  # Paths, ggplot2's `GeomPath`, which `geom_path()` draws with: a line through each group's rows
  # in the order the data gives them. Its parameters are how a line's ends are drawn (`line_end`,
  # ggplot2's `lineend`), how it turns a corner (`line_join`, `linejoin`) and how far a mitred
  # corner may reach (`mitre_limit`, `linemitre`). Lines (`Giggly.Geom.Line`) draw as a path once
  # their rows are in order. Use it through `Giggly.Geom`.
  #
  # Paths use `:x`, `:y`, `:group`, `:alpha`, `:color`, `:linetype` and `:linewidth`, and need `:x`
  # and `:y`; an aesthetic joins the accepted list with the scale that maps it, so a mapping never
  # silently does nothing.
  #
  # A path is drawn as ggplot2's `GeomPath` draws one. Rows missing `x` or `y` (`nil`, or the float
  # `:nan`), a width or a line type, or whose colour is `:none`, R's `NA`, or missing, at the start
  # or end of a group are dropped, as `handle_na()` drops them, and one missing a position in the
  # middle breaks the line there, as grid breaks a polyline; ggplot2 also warns of the rows it
  # drops, which a pure pipeline cannot. The rows are put in group order, keeping each group's own
  # order, and cut into steps that follow the panel's curves (`Giggly.Coord.munch/3`); a group of
  # fewer than two rows is not drawn. Where every group keeps one colour, alpha, width and line
  # type all along it, each group is one line, drawn in its first row's look; where any group's
  # vary, every group is drawn a segment from each row to the next, each in the colour, alpha and
  # width of the row it starts from, and a segment touching a missing position, or starting from a
  # row missing its width, is not drawn, as R's graphics engine draws no line of no width.
  #
  # Every line looks as ggplot2's default line does unless its row says otherwise: solid, 0.5 mm
  # wide, which grid draws 1.07 points wide, and black; or in its row's line type, as wide as its
  # row's `linewidth`, in millimetres, and in its row's colour, each mapped or set. A row's
  # `alpha`, where its table has one, makes its line that opaque, replacing its colour's own; a row
  # without one keeps its colour's (`Giggly.Geom.Mark`). A dashed line is drawn with its dashes as
  # svglite writes them (`Mark.dashes/2`), and a blank one is not drawn, as R's graphics engine
  # draws no line of R's `"blank"`. While any line is in a line type but solid, blank included, no
  # line's colour, alpha, width or line type may change along it: where one does, the panel is
  # refused, as ggplot2's `GeomPath` aborts, since segments would dash each piece afresh. The lines
  # are drawn in group order, each run of lines alike in width and line type one primitive, and the
  # segments in row order, each run alike in width one.

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
  def accepted_aesthetics, do: [:alpha, :color, :group, :linetype, :linewidth, :x, :y]

  # The aesthetics a layer of paths cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame}
    alias Giggly.Geom.Mark
    alias Giggly.Scene.{Polylines, Segments}

    # ggplot2's default line: its width in millimetres, its line type, solid, and its ink.
    @line_width 0.5
    @line_type {}
    @color "#000000"

    # A legend's key, `draw_key_path()`: a line across the middle of the key, from a tenth of its
    # width to nine tenths, its corners grid's default, round.
    @key_start {0.1, 0.5}
    @key_end {0.9, 0.5}

    # Points in a millimetre, grid's `"mm"` in the scene's points, which a key's room is measured
    # in.
    @points_per_millimetre 72 / 25.4

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

      rows =
        coord
        |> Coord.munch(kept, panel_params)
        |> without_short_groups()
        |> rows()

      draw_lines(geom, rows, solid?(rows), constant?(rows))
    end

    # The panel's lines: refused where a line's look varies along it while any line is not solid,
    # as ggplot2's `GeomPath` aborts; else each group a line where every group's look is constant,
    # or a segment from each row to the next where any varies.
    defp draw_lines(_geom, _rows, false, false) do
      raise ArgumentError,
            "a path or line cannot vary its colour, alpha, width or line type along it while " <>
              "any line of its layer is not :solid, as ggplot2 refuses; give each group one " <>
              "colour, alpha, width and line type, or draw every line :solid"
    end

    defp draw_lines(geom, rows, _solid, true), do: draw_polylines(geom, rows)
    defp draw_lines(geom, rows, true, false), do: draw_segments(geom, rows)

    # A legend's key, in the key's colour at its alpha, width and line type; a colour of `:none`, a
    # blank line type, or a missing width or line type, R's `NA`, draws nothing, as
    # `draw_key_path()` draws a missing line type blank and R's graphics engine draws no line of a
    # missing width.
    @impl Giggly.Geom
    def draw_key(geom, key) do
      look =
        {Map.get(key, :color, @color), Map.get(key, :linewidth, @line_width),
         Map.get(key, :linetype, @line_type)}

      case look do
        {color, line_width, line_type}
        when :none in [color, line_type] or is_nil(line_width) or is_nil(line_type) ->
          []

        {color, line_width, line_type} ->
          [
            %Segments{
              starts: [@key_start],
              ends: [@key_end],
              offsets: :none,
              stroke_width: Mark.stroke_width(line_width),
              dashes: Mark.dashes(line_type, line_width),
              color: [Mark.hex(color)],
              opacity: [Mark.opacity(color, Map.get(key, :alpha))],
              line_end: geom.line_end,
              line_join: :round,
              mitre_limit: 10.0
            }
          ]
      end
    end

    # The room a key's line needs, its width in millimetres either way, as ggplot2's
    # `set_key_size()` reads a path's key, which has no `size`; a missing width needs none.
    @impl Giggly.Geom
    def key_size(_geom, key) do
      side =
        case Map.get(key, :linewidth, @line_width) do
          nil -> 0.0
          line_width -> line_width * @points_per_millimetre
        end

      {side, side}
    end

    # Each group a line, in its first row's colour, alpha, width and line type, broken where a
    # position is missing, as grid breaks a polyline; a piece of one point draws nothing. Each run
    # of lines alike in width and line type is one primitive, and a blank run draws nothing.
    defp draw_polylines(geom, rows) do
      rows
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
      |> Enum.chunk_by(fn {_line, look} -> {look.linewidth, look.linetype} end)
      |> Enum.reject(fn [{_line, look} | _rest] -> look.linetype == :none end)
      |> Enum.map(fn [{_line, look} | _rest] = lines ->
        %Polylines{
          lines: Enum.map(lines, fn {line, _look} -> line end),
          offsets: :none,
          stroke_width: Mark.stroke_width(look.linewidth),
          dashes: Mark.dashes(look.linetype, look.linewidth),
          color: Enum.map(lines, fn {_line, row} -> Mark.hex(row.color) end),
          opacity: Enum.map(lines, fn {_line, row} -> Mark.opacity(row.color, row.alpha) end),
          line_end: geom.line_end,
          line_join: geom.line_join,
          mitre_limit: geom.mitre_limit
        }
      end)
    end

    # A segment from each row to the next of its group, in the colour, alpha and width of the row it
    # starts from, solid, the one line type a line whose look varies along it is drawn in; a segment
    # touching a missing position, or starting from a row missing its width, is not drawn. Each run
    # of segments alike in width is one primitive.
    defp draw_segments(geom, rows) do
      rows
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.filter(fn [from, to] ->
        from.group == to.group and placed?(from) and placed?(to) and is_number(from.linewidth)
      end)
      |> Enum.chunk_by(fn [from, _to] -> from.linewidth end)
      |> Enum.map(fn [[first, _to] | _rest] = segments ->
        %Segments{
          starts: Enum.map(segments, fn [from, _to] -> position(from) end),
          ends: Enum.map(segments, fn [_from, to] -> position(to) end),
          offsets: :none,
          stroke_width: Mark.stroke_width(first.linewidth),
          dashes: :none,
          color: Enum.map(segments, fn [from, _to] -> Mark.hex(from.color) end),
          opacity: Enum.map(segments, fn [from, _to] -> Mark.opacity(from.color, from.alpha) end),
          line_end: geom.line_end,
          line_join: geom.line_join,
          mitre_limit: geom.mitre_limit
        }
      end)
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

    # Whether every group keeps one colour, alpha, width and line type all along it, ggplot2's test
    # for drawing a group as one line rather than segments; a table without alpha is opaque
    # throughout.
    defp constant?(rows) do
      rows
      |> Enum.group_by(fn row -> row.group end, fn row ->
        {row.color, row.alpha, row.linewidth, row.linetype}
      end)
      |> Enum.all?(fn {_group, looks} -> match?([_one], Enum.uniq(looks)) end)
    end

    # Whether every group is solid all along it, ggplot2's test for whether a line may be drawn as
    # segments.
    defp solid?(rows) do
      rows
      |> Enum.group_by(fn row -> row.group end, fn row -> row.linetype end)
      |> Enum.all?(fn {_group, line_types} -> Enum.uniq(line_types) == [@line_type] end)
    end

    # Each row's positions, group, colour, black for a table without one, alpha, `nil` for a table
    # without one, width, 0.5 for a table without one, and line type, solid for a table without
    # one, a missing width or line type `nil`.
    defp rows(frame) do
      Enum.zip_with(
        [
          DataFrame.pull(frame, :x),
          DataFrame.pull(frame, :y),
          DataFrame.pull(frame, :group),
          Mark.colors(frame, :color, @color),
          Mark.values(frame, :alpha, nil),
          Mark.values(frame, :linewidth, @line_width),
          Mark.values(frame, :linetype, @line_type)
        ],
        fn [x_position, y_position, group, color, alpha, line_width, line_type] ->
          %{
            x: x_position,
            y: y_position,
            group: group,
            color: color,
            alpha: alpha,
            linewidth: line_width,
            linetype: line_type
          }
        end
      )
    end

    # A row with both positions, a colour, a width and a line type, before it is placed, as R's
    # `complete.cases()` finds one, an infinite position counting as present and a colour of
    # `:none` as missing, a colour read by `Mark.colors/3` so a missing one is `:none` too, and a
    # blank line type, held as `:none` where a layer sets it, as present.
    defp complete?(row) do
      not missing?(row.x) and not missing?(row.y) and row.color != :none and
        not is_nil(row.linewidth) and not is_nil(row.linetype)
    end

    defp missing?(position), do: position in [nil, :nan]

    # A row placed in the panel, both its positions numbers.
    defp placed?(row), do: is_number(row.x) and is_number(row.y)

    defp position(row), do: {row.x, row.y}
  end
end
