defmodule Giggly.Geom.Vline do
  @moduledoc false

  # Vertical reference lines, ggplot2's `GeomVline`, which `geom_vline()` draws with: a line up the
  # whole panel at each row's `xintercept`. Its one parameter is how a line's ends are drawn
  # (`line_end`, ggplot2's `lineend`). Use it through `Giggly.Geom`.
  #
  # Vertical lines use `:xintercept`, `:group`, `:alpha`, `:color`, `:linetype` and `:linewidth`,
  # and need `:xintercept`, which the x scale trains on and transforms as it does `x`. A line is
  # drawn as ggplot2's `GeomVline` draws one: each panel's rows, the repeats dropped, as
  # `unique0()` drops them, are segments (`Giggly.Geom.Segment`) from the start of the panel's y
  # extent to its end (`Giggly.Coord.extents/2`) at their `xintercept`, drawn with the lines' ends
  # and a segment's round corners, as `GeomVline` hands them to `GeomSegment$draw_panel()` with
  # its `lineend` alone. So a line follows the panel's curves where a segment does, a spoke under
  # radial coordinates, and a row missing its `xintercept`, a width or a line type is not drawn.
  # Its look, when the layer neither maps nor sets one, is a path's, as `GeomVline$default_aes`
  # is `GeomPath`'s. Its legend key is `draw_key_vline()`'s: a line up the middle of the key from
  # its bottom to its top, with the lines' ends, needing a path's room.

  @enforce_keys [:line_end]
  defstruct @enforce_keys

  @type t :: %__MODULE__{line_end: Giggly.Scene.Polylines.line_end()}

  # The aesthetics a layer of vertical lines can use, from its own mapping alone, since it takes
  # nothing from the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:alpha, :color, :group, :linetype, :linewidth, :xintercept]

  # The aesthetics a layer of vertical lines cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:xintercept]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame, Geom}
    alias Giggly.Geom.{Mark, Path}

    # A legend's key, `draw_key_vline()`: a line up the middle of the key, from its bottom to its
    # top.
    @key_line {{0.5, 0.0}, {0.5, 1.0}}

    @impl Giggly.Geom
    def default_aesthetics(geom, element) do
      geom
      |> segment()
      |> Geom.default_aesthetics(element)
    end

    # A line is drawn at its `xintercept` alone, in the data's order.
    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds), do: frame

    # The panel's lines: each distinct row a segment up the panel's y extent at its `xintercept`,
    # its `xend` left for the segment to copy from its `x`.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params, installed_fonts) do
      %{y: {low, high}} = Coord.extents(coord, panel_params)
      lines = DataFrame.distinct(frame)
      count = DataFrame.row_count(lines)
      intercepts = DataFrame.pull(lines, :xintercept)

      # Every column but `xintercept`, which the coordinate system would place as a position.
      kept = for name <- DataFrame.names(lines), name != :xintercept, do: {name, name}

      segments =
        lines
        |> DataFrame.select(kept)
        |> DataFrame.put(:x, intercepts)
        |> DataFrame.put(:y, List.duplicate(low, count))
        |> DataFrame.put(:yend, List.duplicate(high, count))
        |> Mark.opaque_alphas()

      geom
      |> segment()
      |> Geom.draw_panel(segments, coord, panel_params, installed_fonts)
    end

    @impl Giggly.Geom
    def draw_key(geom, key, _installed_fonts),
      do: Path.line_key(key, @key_line, geom.line_end, :none)

    # A path's room, as `draw_key_vline()` sets no size of its own without an arrow.
    @impl Giggly.Geom
    def key_size(geom, key, installed_fonts) do
      geom
      |> segment()
      |> Geom.key_size(key, installed_fonts)
    end

    # The segments the lines are drawn as, with the lines' ends and a segment's round corners, as
    # `GeomVline` hands `GeomSegment$draw_panel()` its `lineend` alone, and no arrowheads.
    defp segment(geom),
      do: %Geom.Segment{line_end: geom.line_end, line_join: :round, arrow: :none}
  end
end
