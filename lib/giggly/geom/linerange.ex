defmodule Giggly.Geom.Linerange do
  @moduledoc false

  # Line ranges, ggplot2's `GeomLinerange`, which `geom_linerange()` draws with: a vertical line
  # for each row, from its `ymin` to its `ymax` at its `x`, or, turned, a horizontal one from its
  # `xmin` to its `xmax` at its `y`. Its parameters are which way it runs (`orientation`: `:x`,
  # `:y`, or `:none` to take it from the ranges given) and how a line's ends are drawn
  # (`line_end`, ggplot2's `lineend`). Point ranges (`Giggly.Geom.Pointrange`) draw their lines
  # with it, as ggplot2's `GeomPointrange` draws through `GeomLinerange`. Use it through
  # `Giggly.Geom`.
  #
  # Line ranges use `:x`, `:y`, `:xmin`, `:xmax`, `:ymin`, `:ymax`, `:group`, `:alpha`, `:color`,
  # `:linetype` and `:linewidth`, and need one of `:x` and `:y`, one of `:ymin` and `:xmin` and
  # one of `:ymax` and `:xmax`, ggplot2's `"x|y"`, `"ymin|xmin"` and `"ymax|xmax"`; `Giggly.Plot`
  # makes sure a layer has the three its orientation draws with.
  #
  # While the plot is assembled (`setup_data/3`), a line range runs along y where the layer says
  # so, or, where it does not, where it is given no `ymin` or `ymax`, as ggplot2's
  # `has_flipped_aes(range_is_orthogonal = TRUE)` reads a range, and writes that in `flipped_aes`.
  #
  # Each panel's lines are drawn as ggplot2's `GeomLinerange` draws them: each row a segment from
  # `{x, ymin}` to `{x, ymax}`, or turned from `{xmin, y}` to `{xmax, y}`, drawn as
  # `Giggly.Geom.Segment` draws one, with the layer's line ends, round corners and no arrowheads,
  # as `GeomLinerange` hands its rows to `GeomSegment$draw_panel()` with its `lineend` alone; so a
  # row missing a position, its width or its line type draws nothing, and under radial coordinates
  # each line follows the panel's curves. A line range the layer neither maps nor sets a look for
  # looks as a path does, ggplot2's `GeomLinerange$default_aes` being `GeomPath$default_aes`.
  #
  # Its legend key is ggplot2's `draw_key_linerange()`: a path's key, a line across the middle
  # from a tenth of the key's width to nine tenths, for a horizontal layer, which the legend says
  # in the key's `flipped_aes`, and otherwise `draw_key_vpath()`'s, up the middle from a tenth of
  # its height to nine tenths; either with the layer's line ends, needing a path's room.

  alias Giggly.{DataFrame, Geom}
  alias Giggly.Geom.Ribbon

  @enforce_keys [:orientation, :line_end]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          orientation: :none | :x | :y,
          line_end: Giggly.Scene.Polylines.line_end()
        }

  # The aesthetics a layer of line ranges can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics,
    do: [:alpha, :color, :group, :linetype, :linewidth, :x, :xmax, :xmin, :y, :ymax, :ymin]

  # The aesthetics a layer of line ranges cannot be drawn without: one of each pair, ggplot2's
  # `"x|y"`, `"ymin|xmin"` and `"ymax|xmax"`.
  @doc false
  @spec required_aesthetics() :: [[atom()]]
  def required_aesthetics, do: [[:x, :y], [:ymin, :xmin], [:ymax, :xmax]]

  # `frame` with `flipped_aes` written in every row, true where the line ranges run along y: as
  # `orientation` says, or, where it is `:none`, where the rows have no `ymin` or `ymax`, as
  # ggplot2's `has_flipped_aes(range_is_orthogonal = TRUE)` reads the range, which point ranges
  # share.
  @doc false
  @spec oriented(DataFrame.t(), :none | :x | :y) :: DataFrame.t()
  def oriented(frame, orientation) do
    flipped = flipped?(orientation, DataFrame.names(frame))
    DataFrame.put(frame, :flipped_aes, List.duplicate(flipped, DataFrame.row_count(frame)))
  end

  defp flipped?(:x, _names), do: false
  defp flipped?(:y, _names), do: true
  defp flipped?(:none, names), do: not Enum.any?([:ymin, :ymax], fn name -> name in names end)

  # The primitives a panel's line ranges are drawn with, under `coord` in the panel `panel_params`
  # describes, each row's line ended as `line_end` says, which point ranges share.
  @doc false
  @spec draw(
          Giggly.Scene.Polylines.line_end(),
          DataFrame.t(),
          Giggly.Coord.t(),
          Giggly.Coord.panel_params(),
          boolean()
        ) :: [Giggly.Scene.primitive()]
  def draw(line_end, frame, coord, panel_params, installed_fonts) do
    flipped = flipped_aes(frame)

    segments =
      frame
      |> Ribbon.flip(flipped)
      |> with_ends()
      |> Ribbon.flip(flipped)

    Geom.draw_panel(
      %Geom.Segment{line_end: line_end, line_join: :round, arrow: :none},
      segments,
      coord,
      panel_params,
      installed_fonts
    )
  end

  # Each vertical range's segment, from its `ymin` to its `ymax` at its `x`, as `GeomLinerange`
  # transforms its rows into `GeomSegment`'s.
  defp with_ends(frame) do
    frame
    |> DataFrame.put(:xend, DataFrame.pull(frame, :x))
    |> DataFrame.put(:y, DataFrame.pull(frame, :ymin))
    |> DataFrame.put(:yend, DataFrame.pull(frame, :ymax))
  end

  # Whether the rows run along y, as `oriented/2` wrote it; a table of no rows runs along x, which
  # error bars and crossbars share.
  @doc false
  @spec flipped_aes(DataFrame.t()) :: boolean()
  def flipped_aes(frame) do
    case DataFrame.pull(frame, :flipped_aes) do
      [flipped | _rest] -> flipped
      [] -> false
    end
  end

  # A legend's key, ggplot2's `draw_key_linerange()`, across the key for a horizontal layer and up
  # it otherwise, which point ranges share.
  @doc false
  @spec key(%{optional(atom()) => term()}, Giggly.Scene.Polylines.line_end()) :: [
          Giggly.Scene.Segments.t()
        ]
  def key(key, line_end) do
    ends =
      if Map.fetch!(key, :flipped_aes),
        do: {{0.1, 0.5}, {0.9, 0.5}},
        else: {{0.5, 0.1}, {0.5, 0.9}}

    Geom.Path.line_key(key, ends, line_end, :none)
  end

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.Geom

    @impl Giggly.Geom
    def default_aesthetics(geom, element) do
      geom
      |> path()
      |> Geom.default_aesthetics(element)
    end

    # ggplot2's `GeomLinerange$setup_data()`: the orientation written in `flipped_aes`.
    @impl Giggly.Geom
    def setup_data(geom, frame, _axis_kinds), do: Geom.Linerange.oriented(frame, geom.orientation)

    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params, installed_fonts),
      do: Geom.Linerange.draw(geom.line_end, frame, coord, panel_params, installed_fonts)

    @impl Giggly.Geom
    def draw_key(geom, key, _installed_fonts), do: Geom.Linerange.key(key, geom.line_end)

    @impl Giggly.Geom
    def key_size(geom, key, installed_fonts) do
      geom
      |> path()
      |> Geom.key_size(key, installed_fonts)
    end

    # The path a line range looks as, ggplot2's `GeomLinerange$default_aes` being
    # `GeomPath$default_aes`, whose key's room it needs.
    defp path(geom) do
      %Geom.Path{line_end: geom.line_end, line_join: :round, mitre_limit: 10.0, arrow: :none}
    end
  end
end
