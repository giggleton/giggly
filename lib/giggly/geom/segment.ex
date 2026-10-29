defmodule Giggly.Geom.Segment do
  @moduledoc false

  # Segments, ggplot2's `GeomSegment`, which `geom_segment()` draws with: a straight line for each
  # row, from its `x` and `y` to its `xend` and `yend`. Its parameters are how a line's ends are
  # drawn (`line_end`, ggplot2's `lineend`) and how it turns a corner (`line_join`, `linejoin`), at
  # grid's mitre limit, 10, since ggplot2's segments take no `linemitre`. Use it through
  # `Giggly.Geom`.
  #
  # Segments use `:x`, `:y`, `:xend`, `:yend`, `:group`, `:alpha`, `:color`, `:linetype` and
  # `:linewidth`, and need `:x`, `:y` and one of `:xend` and `:yend`, ggplot2's `"xend|yend"`; a
  # layer mapping only one has the other copied from `x` or `y` as each panel is drawn, as
  # `GeomSegment$draw_panel()` copies it, so the layer's table holds only what was mapped. An
  # aesthetic joins the accepted list with the scale that maps it, so a mapping never silently
  # does nothing.
  #
  # A segment is drawn as ggplot2's `GeomSegment` draws one. A row missing a position (`nil`, or
  # the float `:nan`), its width or its line type is not drawn, as `remove_missing()` drops it; an
  # infinite position counts as present and reaches the panel's edge; ggplot2 also warns of the
  # rows it drops, which a pure pipeline cannot. Under a coordinate system whose straight lines
  # stay straight (`Giggly.Coord.linear?/1`), the rows are placed and drawn in their order, each a
  # straight line in its own colour, alpha, width and line type, as grid's `segmentsGrob()` draws
  # them, each run alike in width and line type one primitive; a blank line type draws none, as R's
  # graphics engine draws no line of it, and a colour of `:none`, R's `NA`, a line of no stroke, as
  # svglite writes one. Under one whose lines curve, each row becomes a path of two rows, its start
  # and its end, in a group of its own, drawn as `Giggly.Geom.Path` draws one with the segments'
  # line ends and grid's round corners, as `GeomSegment` hands its rows to `GeomPath$draw_panel()`
  # with its `lineend` alone, so each follows the panel's curves.
  #
  # A segment the layer neither maps nor sets a look for looks as a path does, ggplot2's
  # `GeomSegment$default_aes` being `GeomPath$default_aes`, and its legend key is a path's,
  # `draw_key_path()`, with the segments' line ends.

  @enforce_keys [:line_end, :line_join]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          line_end: Giggly.Scene.Polylines.line_end(),
          line_join: Giggly.Scene.Polylines.line_join()
        }

  # The aesthetics a layer of segments can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics,
    do: [:alpha, :color, :group, :linetype, :linewidth, :x, :xend, :y, :yend]

  # The aesthetics a layer of segments cannot be drawn without: both of its start's positions and
  # one of its end's.
  @doc false
  @spec required_aesthetics() :: [atom() | [atom()]]
  def required_aesthetics, do: [:x, :y, [:xend, :yend]]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame, Geom}
    alias Giggly.Geom.Mark
    alias Giggly.Scene.Segments

    # grid's mitre limit, which ggplot2's segments are drawn at.
    @mitre_limit 10.0

    @impl Giggly.Geom
    def default_aesthetics(geom, element) do
      geom
      |> path()
      |> Geom.default_aesthetics(element)
    end

    # A segment is drawn from its start to its end alone, in the data's order.
    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds), do: frame

    # The panel's segments: straight lines where the coordinate system keeps them straight, else
    # each a path of its two ends.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params) do
      complete =
        frame
        |> with_both_ends()
        |> complete()

      if Coord.linear?(coord) do
        draw_segments(geom, Coord.transform(coord, complete, panel_params))
      else
        geom
        |> path()
        |> Geom.draw_panel(pieces(complete), coord, panel_params)
      end
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

    # The path a segment's two ends are drawn as, and its legend key, with the segments' line ends
    # and grid's round corners, as `GeomSegment` hands `GeomPath$draw_panel()` its `lineend` alone.
    defp path(geom),
      do: %Geom.Path{line_end: geom.line_end, line_join: :round, mitre_limit: @mitre_limit}

    # The frame with an `xend` and a `yend`, either the layer leaves out copied from its `x` or
    # `y`.
    defp with_both_ends(frame) do
      names = DataFrame.names(frame)

      [xend: :x, yend: :y]
      |> Enum.reject(fn {finish, _start} -> finish in names end)
      |> Enum.reduce(frame, fn {finish, start}, ended ->
        DataFrame.put(ended, finish, DataFrame.pull(ended, start))
      end)
    end

    # The rows with all four positions, a width and a line type, in their order, as
    # `remove_missing()` keeps them; an infinite position counts as present.
    defp complete(frame) do
      kept =
        [:x, :y, :xend, :yend, :linewidth, :linetype]
        |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
        |> Enum.zip_with(fn values -> not Enum.any?(values, &missing?/1) end)
        |> Enum.with_index()
        |> Enum.filter(fn {complete, _index} -> complete end)
        |> Enum.map(fn {_complete, index} -> index end)

      DataFrame.slice(frame, kept)
    end

    defp missing?(value), do: value in [nil, :nan]

    # Each row a straight line from its start to its end, in its colour at its alpha, width and line
    # type, in row order, each run alike in width and line type one primitive; a blank line type
    # draws none, and a colour of `:none` a line of no stroke, as svglite writes one.
    defp draw_segments(geom, placed) do
      colors = Mark.colors(placed, :color)

      [:x, :y, :xend, :yend, :alpha, :linewidth, :linetype]
      |> Enum.map(fn name -> DataFrame.pull(placed, name) end)
      |> List.insert_at(4, colors)
      |> Enum.zip_with(fn [x, y, xend, yend, color, alpha, line_width, line_type] ->
        %{
          start: {x, y},
          end: {xend, yend},
          color: color,
          opacity: Mark.opacity(color, alpha),
          line: {line_width, line_type}
        }
      end)
      |> Enum.reject(fn %{line: {_line_width, line_type}} -> line_type == :none end)
      |> Enum.chunk_by(fn segment -> segment.line end)
      |> Enum.map(fn [%{line: {line_width, line_type}} | _rest] = segments ->
        %Segments{
          starts: Enum.map(segments, fn segment -> segment.start end),
          ends: Enum.map(segments, fn segment -> segment.end end),
          offsets: :none,
          stroke_width: Mark.stroke_width(line_width),
          dashes: Mark.dashes(line_type, line_width),
          color: Enum.map(segments, fn segment -> Mark.hex(segment.color) end),
          opacity: Enum.map(segments, fn segment -> segment.opacity end),
          line_end: geom.line_end,
          line_join: geom.line_join,
          mitre_limit: @mitre_limit
        }
      end)
    end

    # Each row as a path of two rows, its start and then its end, in a group of its own numbered
    # by its place, as `GeomSegment` stacks its starts and ends and orders them by group; every
    # other column is the row's.
    defp pieces(frame) do
      count = DataFrame.row_count(frame)
      doubled = Enum.flat_map(0..(count - 1)//1, fn index -> [index, index] end)

      others =
        frame
        |> DataFrame.names()
        |> Enum.reject(fn name -> name in [:x, :y, :xend, :yend, :group] end)

      frame
      |> DataFrame.slice(doubled)
      |> DataFrame.select(Enum.map(others, fn name -> {name, name} end))
      |> DataFrame.put(:x, interleaved(frame, :x, :xend))
      |> DataFrame.put(:y, interleaved(frame, :y, :yend))
      |> DataFrame.put(:group, Enum.map(doubled, fn index -> index + 1 end))
    end

    # Each row's `start` and then its `finish`.
    defp interleaved(frame, start, finish) do
      finishes = DataFrame.pull(frame, finish)

      frame
      |> DataFrame.pull(start)
      |> Enum.zip_with(finishes, fn from, to -> [from, to] end)
      |> Enum.concat()
    end
  end
end
