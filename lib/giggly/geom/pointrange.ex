defmodule Giggly.Geom.Pointrange do
  @moduledoc false

  # Point ranges, ggplot2's `GeomPointrange`, which `geom_pointrange()` draws with: a line range
  # (`Giggly.Geom.Linerange`) for each row with a point at its `x` and `y` on it, for a value and
  # the interval round it. Its parameters are a line range's: which way it runs (`orientation`:
  # `:x`, `:y`, or `:none` to take it from the ranges given) and how a line's ends are drawn
  # (`line_end`, ggplot2's `lineend`). Use it through `Giggly.Geom`.
  #
  # Point ranges use a line range's aesthetics and a point's, `:fill`, `:shape`, `:size` and
  # `:stroke`, and need `:x` and `:y`, one of `:ymin` and `:xmin` and one of `:ymax` and `:xmax`,
  # ggplot2's `"x"`, `"y"`, `"ymin|xmin"` and `"ymax|xmax"`; `Giggly.Plot` makes sure a layer has
  # the range its orientation draws with. While the plot is assembled (`setup_data/3`), a point
  # range takes its orientation as a line range does.
  #
  # Each panel is drawn as ggplot2's `GeomPointrange` draws it: every row's line, as a line range
  # draws it, and then every row's point, as `Giggly.Geom.Point` draws one, at four times its
  # size, ggplot2's `fatten` of 4, so a later row's line is drawn under an earlier row's point. A
  # point range the layer neither maps nor sets a look for looks as ggplot2's default point range
  # does under the plot's theme: the theme's ink, a size of a third of its points' (0.5 at its
  # default sizes, so a point drawn at 2), its lines' width and line type, its point shape, no
  # fill, no alpha, and twice its borders' width as the point's stroke (1 at its default sizes).
  #
  # Its legend key is ggplot2's `draw_key_pointrange()`: a line range's key, and over it a point's
  # key at four times the key's size, needing its `size` and `linewidth` added, in millimetres,
  # as `set_key_size()` reads a key whose glyph gives no size.

  @enforce_keys [:orientation, :line_end]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          orientation: :none | :x | :y,
          line_end: Giggly.Scene.Polylines.line_end()
        }

  # The aesthetics a layer of point ranges can use, from its own mapping or the plot's.
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
      :shape,
      :size,
      :stroke,
      :x,
      :xmax,
      :xmin,
      :y,
      :ymax,
      :ymin
    ]
  end

  # The aesthetics a layer of point ranges cannot be drawn without: its point's place, and one of
  # each of its range's ends, ggplot2's `"ymin|xmin"` and `"ymax|xmax"`.
  @doc false
  @spec required_aesthetics() :: [atom() | [atom()]]
  def required_aesthetics, do: [:x, :y, [:ymin, :xmin], [:ymax, :xmax]]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{DataFrame, Geom}
    alias Giggly.Geom.Linerange

    # ggplot2's `fatten`, how many times its size a point range's point is drawn.
    @fatten 4

    # Points in a millimetre, grid's `"mm"` in the scene's points, which a key's room is measured
    # in.
    @points_per_millimetre 72 / 25.4

    # ggplot2's `GeomPointrange$default_aes`: the theme's ink, a third of its points' size, its
    # lines' width and line type, its point shape, no fill, no alpha, and twice its borders' width
    # as the point's stroke.
    @impl Giggly.Geom
    def default_aesthetics(_geom, element) do
      [
        color: element.ink,
        size: element.pointsize / 3,
        linewidth: element.linewidth,
        linetype: element.linetype,
        shape: element.pointshape,
        fill: nil,
        alpha: nil,
        stroke: element.borderwidth * 2
      ]
    end

    # ggplot2's `GeomPointrange$setup_data()`, a line range's.
    @impl Giggly.Geom
    def setup_data(geom, frame, _axis_kinds), do: Linerange.oriented(frame, geom.orientation)

    # Every row's line, then every row's point, at four times its size.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params, installed_fonts) do
      lines = Linerange.draw(geom.line_end, frame, coord, panel_params, installed_fonts)

      points =
        Geom.draw_panel(
          %Geom.Point{},
          DataFrame.put(frame, :size, Enum.map(DataFrame.pull(frame, :size), &fattened/1)),
          coord,
          panel_params,
          installed_fonts
        )

      lines ++ points
    end

    # A legend's key: a line range's, and a point's at four times the key's size over it.
    @impl Giggly.Geom
    def draw_key(geom, key, installed_fonts) do
      point = Geom.draw_key(%Geom.Point{}, Map.update!(key, :size, &fattened/1), installed_fonts)
      Linerange.key(key, geom.line_end) ++ point
    end

    # The room a key needs, its size and its line's width added, in millimetres either way, a
    # missing one counting 0.
    @impl Giggly.Geom
    def key_size(_geom, key, _installed_fonts) do
      side =
        [Map.fetch!(key, :size), Map.fetch!(key, :linewidth)]
        |> Enum.map(fn millimetres -> millimetres || 0.0 end)
        |> Enum.sum()
        |> Kernel.*(@points_per_millimetre)

      {side, side}
    end

    defp fattened(nil), do: nil
    defp fattened(size), do: size * @fatten
  end
end
