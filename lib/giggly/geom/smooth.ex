defmodule Giggly.Geom.Smooth do
  @moduledoc false

  # Smooths, ggplot2's `GeomSmooth`, which `geom_smooth()` and `stat_smooth()` draw with: each
  # group's curve through its rows in order along x, and, where the layer shows its standard error
  # (`se`), the band from its `ymin` to its `ymax` beneath it; turned, along y. Its parameters are
  # whether the band is shown, and how the line's ends and corners are drawn (`line_end`,
  # `line_join`, `mitre_limit`, ggplot2's `lineend`, `linejoin` and `linemitre`). Use it through
  # `Giggly.Geom`.
  #
  # Smooths use `:x`, `:y`, `:group`, `:alpha`, `:color`, `:fill`, `:linetype` and `:linewidth`;
  # what they cannot be drawn without, `:x` and `:y`, the stat before them needs, so a layer is
  # checked against the stat's requirements, and the stat writes the band, so it is not a smooth's
  # to map.
  #
  # While the plot is assembled (`setup_data/3`), its rows run along y where its stat says so in
  # `flipped_aes`, written afresh into every row, and are put in order of panel, group and the
  # position they run along, as ggplot2's `GeomSmooth` sets up its rows as `GeomLine` does.
  #
  # A panel is drawn a group at a time, in the order of the groups, each whole before the next, as
  # ggplot2's `GeomSmooth$draw_group()` draws one: first its band, where `se`, as a ribbon is
  # drawn (`Giggly.Geom.Ribbon`), outlined both ways with no colour, its ends cut square and its
  # corners round, a row missing an end leaving the band off there, so a curve
  # of no degrees of freedom has none; then its line, as a line is drawn (`Giggly.Geom.Path`), in
  # its colour's own alpha, never the row's, which fills the band.
  #
  # A smooth the layer neither maps nor sets a look for looks as ggplot2's default smooth does
  # under the plot's theme: its line in the theme's accent, `#3366FF`, twice as wide as the theme's
  # lines and in their line type; its band the theme's ink mixed 60% toward its paper, `#999999`
  # on white paper and `#00000066` on `theme_void()`'s clear paper, at an alpha of 0.4. Its legend
  # key is ggplot2's `draw_key_smooth()`: where `se`, the band's fill at the key's alpha over the
  # whole key, unbordered at grid's default width, then a line's key across it, at an alpha of 1,
  # needing a line's room.

  @enforce_keys [:se, :line_end, :line_join, :mitre_limit]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          se: boolean(),
          line_end: Giggly.Scene.Polylines.line_end(),
          line_join: Giggly.Scene.Polylines.line_join(),
          mitre_limit: float()
        }

  # The aesthetics a layer of smooths can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:alpha, :color, :fill, :group, :linetype, :linewidth, :x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{ColorOperations, DataFrame, Geom}
    alias Giggly.Geom.{Mark, Ribbon}
    alias Giggly.Scene.Rectangles

    # How far a smooth's default band is mixed from the theme's ink toward its paper, ggplot2's
    # `col_mix(ink, paper, 0.6)`, and its alpha.
    @fill_toward_paper 0.6
    @band_alpha 0.4

    # The band ggplot2's `GeomSmooth` draws a group's band with: `GeomRibbon$draw_group()` at its
    # defaults, both edges outlined, the ends cut square and the corners round.
    @band %{outline_type: :both, line_end: :butt, line_join: :round, mitre_limit: 10.0}

    # grid's default line width, 1, which svglite writes 0.75 points wide: the width of the key's
    # unbordered band.
    @default_stroke_width 0.75

    # ggplot2's `GeomSmooth$default_aes`: the theme's accent, a fill of its ink mixed toward its
    # paper, twice its lines' width, their line type, a weight of 1 and an alpha of 0.4.
    @impl Giggly.Geom
    def default_aesthetics(_geom, element) do
      [
        color: element.accent,
        fill: ColorOperations.mix(element.ink, element.paper, @fill_toward_paper),
        linewidth: 2 * element.linewidth,
        linetype: element.linetype,
        weight: 1.0,
        alpha: @band_alpha
      ]
    end

    # ggplot2's `GeomLine$setup_data()`, which `GeomSmooth` sets up with: the stat's orientation
    # written in `flipped_aes`, and the rows in order along it.
    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds) do
      flipped = flipped_aes(frame)

      frame
      |> DataFrame.put(:flipped_aes, List.duplicate(flipped, DataFrame.row_count(frame)))
      |> Ribbon.flip(flipped)
      |> Ribbon.in_order()
      |> Ribbon.flip(flipped)
    end

    # The orientation the stat wrote, the first boolean in the rows' `flipped_aes`, or along x for
    # rows of none.
    defp flipped_aes(frame) do
      frame
      |> DataFrame.pull(:flipped_aes)
      |> Enum.find(false, fn flipped -> is_boolean(flipped) end)
    end

    # Each group's band, where `se`, then its line, the groups in order. The stat writes a band
    # wherever `se` asks for one, so the band's ends are always there to draw.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params) do
      frame
      |> DataFrame.split(:group)
      |> Enum.sort_by(fn {group, _rows} -> group end)
      |> Enum.flat_map(fn {_group, rows} ->
        band(geom.se, rows, coord, panel_params) ++ line(geom, rows, coord, panel_params)
      end)
    end

    defp band(false, _rows, _coord, _panel_params), do: []

    defp band(true, rows, coord, panel_params) do
      uncoloured = DataFrame.put(rows, :color, List.duplicate(nil, DataFrame.row_count(rows)))
      Ribbon.draw(@band, uncoloured, coord, panel_params, [:x, :ymin, :ymax])
    end

    defp line(geom, rows, coord, panel_params) do
      own_alpha = DataFrame.put(rows, :alpha, List.duplicate(nil, DataFrame.row_count(rows)))

      geom
      |> path()
      |> Geom.draw_panel(own_alpha, coord, panel_params)
    end

    # A legend's key, ggplot2's `draw_key_smooth()`: where `se`, the band's fill at the key's alpha
    # over the whole key, then a line's key at an alpha of 1.
    @impl Giggly.Geom
    def draw_key(geom, key) do
      opaque = Map.put(key, :alpha, 1.0)

      line =
        geom
        |> path()
        |> Geom.draw_key(opaque)

      band_key(geom.se, key) ++ line
    end

    defp band_key(false, _key), do: []

    defp band_key(true, key) do
      fill = Mark.key_color(key, :fill)

      [
        %Rectangles{
          xmin: [0.0],
          xmax: [1.0],
          ymin: [0.0],
          ymax: [1.0],
          offsets: :none,
          fill: [Mark.hex(fill)],
          fill_opacity: [Mark.opacity(fill, Map.fetch!(key, :alpha))],
          color: [:none],
          color_opacity: [0.0],
          stroke_width: @default_stroke_width,
          dashes: :none,
          line_end: :round,
          line_join: :round,
          mitre_limit: 10.0
        }
      ]
    end

    # The room a smooth's key needs, a line's.
    @impl Giggly.Geom
    def key_size(geom, key) do
      geom
      |> path()
      |> Geom.key_size(key)
    end

    # The path a smooth's line is drawn as, with its ends and corners.
    defp path(geom) do
      %Geom.Path{
        line_end: geom.line_end,
        line_join: geom.line_join,
        mitre_limit: geom.mitre_limit
      }
    end
  end
end
