defmodule Giggly.Geom.Hline do
  @moduledoc false

  # Horizontal reference lines, ggplot2's `GeomHline`, which `geom_hline()` draws with: a line
  # across the whole panel at each row's `yintercept`. Its one parameter is how a line's ends are
  # drawn (`line_end`, ggplot2's `lineend`). Use it through `Giggly.Geom`.
  #
  # Horizontal lines use `:yintercept`, `:group`, `:alpha`, `:color`, `:linetype` and
  # `:linewidth`, and need `:yintercept`, which the y scale trains on and transforms as it does
  # `y`. A line is drawn as ggplot2's `GeomHline` draws one: each panel's rows, the repeats
  # dropped, as `unique0()` drops them, are segments (`Giggly.Geom.Segment`) from the start of the
  # panel's x extent to its end (`Giggly.Coord.extents/2`) at their `yintercept`, drawn with the
  # lines' ends and a segment's round corners, as `GeomHline` hands them to
  # `GeomSegment$draw_panel()` with its `lineend` alone. So a line follows the panel's curves
  # where a segment does, a circle under radial coordinates, and a row missing its `yintercept`, a
  # width or a line type is not drawn. Its look, when the layer neither maps nor sets one, is a
  # path's, as `GeomHline$default_aes` is `GeomPath`'s, and its legend key is a path's,
  # `draw_key_path()`, with the lines' ends.

  @enforce_keys [:line_end]
  defstruct @enforce_keys

  @type t :: %__MODULE__{line_end: Giggly.Scene.Polylines.line_end()}

  # The aesthetics a layer of horizontal lines can use, from its own mapping alone, since it takes
  # nothing from the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:alpha, :color, :group, :linetype, :linewidth, :yintercept]

  # The aesthetics a layer of horizontal lines cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:yintercept]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame, Geom}

    @impl Giggly.Geom
    def default_aesthetics(geom, element) do
      geom
      |> segment()
      |> Geom.default_aesthetics(element)
    end

    # A line is drawn at its `yintercept` alone, in the data's order.
    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds), do: frame

    # The panel's lines: each distinct row a segment across the panel's x extent at its
    # `yintercept`, its `yend` left for the segment to copy from its `y`.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params, installed_fonts) do
      %{x: {low, high}} = Coord.extents(coord, panel_params)
      lines = DataFrame.distinct(frame)
      count = DataFrame.row_count(lines)
      intercepts = DataFrame.pull(lines, :yintercept)

      # Every column but `yintercept`, which the coordinate system would place as a position.
      kept = for name <- DataFrame.names(lines), name != :yintercept, do: {name, name}

      segments =
        lines
        |> DataFrame.select(kept)
        |> DataFrame.put(:x, List.duplicate(low, count))
        |> DataFrame.put(:xend, List.duplicate(high, count))
        |> DataFrame.put(:y, intercepts)

      geom
      |> segment()
      |> Geom.draw_panel(segments, coord, panel_params, installed_fonts)
    end

    @impl Giggly.Geom
    def draw_key(geom, key, installed_fonts) do
      geom
      |> segment()
      |> Geom.draw_key(key, installed_fonts)
    end

    @impl Giggly.Geom
    def key_size(geom, key, installed_fonts) do
      geom
      |> segment()
      |> Geom.key_size(key, installed_fonts)
    end

    # The segments the lines are drawn as, with the lines' ends and a segment's round corners, as
    # `GeomHline` hands `GeomSegment$draw_panel()` its `lineend` alone, and no arrowheads.
    defp segment(geom),
      do: %Geom.Segment{line_end: geom.line_end, line_join: :round, arrow: :none}
  end
end
