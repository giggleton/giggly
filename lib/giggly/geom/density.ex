defmodule Giggly.Geom.Density do
  @moduledoc false

  # Densities, ggplot2's `GeomDensity`, which `geom_density()` draws with: an area
  # (`Giggly.Geom.Area`) with a density's look, its band from 0 to each group's curve, set up and
  # drawn as an area is, as ggplot2's `GeomDensity` is a `GeomArea` with defaults of its own: the
  # theme's ink, no fill, the lines' width and line type rather than the borders', and a weight of
  # 1. Its parameters are an area's: which way it runs (`orientation`, the stat's where it gives
  # one, as a density does), which edges are outlined (`outline_type`, ggplot2's `geom_density()`
  # outlining the upper one), and how its outlines' ends and corners are drawn. Use it through
  # `Giggly.Geom`.
  #
  # Densities use `:x`, `:y`, `:group`, `:weight`, `:alpha`, `:color`, `:fill`, `:linetype` and
  # `:linewidth`; the density before them needs one of `:x` and `:y`, and gives the other.

  alias Giggly.Scene.Polylines

  @enforce_keys [:orientation, :outline_type, :line_end, :line_join, :mitre_limit]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          orientation: :x | :y,
          outline_type: Giggly.Geom.Ribbon.outline_type(),
          line_end: Polylines.line_end(),
          line_join: Polylines.line_join(),
          mitre_limit: float()
        }

  # The aesthetics a layer of densities can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics,
    do: [:alpha, :color, :fill, :group, :linetype, :linewidth, :weight, :x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.Geom
    alias Giggly.Geom.Area

    # ggplot2's `GeomDensity$default_aes`, in its order: the theme's ink, no fill, a weight of 1,
    # no alpha, and the lines' width and line type.
    @impl Giggly.Geom
    def default_aesthetics(_geom, element) do
      [
        color: element.ink,
        fill: nil,
        weight: 1.0,
        alpha: nil,
        linewidth: element.linewidth,
        linetype: element.linetype
      ]
    end

    @impl Giggly.Geom
    def setup_data(geom, frame, axis_kinds) do
      geom
      |> area()
      |> Geom.setup_data(frame, axis_kinds)
    end

    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params) do
      geom
      |> area()
      |> Geom.draw_panel(frame, coord, panel_params)
    end

    @impl Giggly.Geom
    def draw_key(geom, key) do
      geom
      |> area()
      |> Geom.draw_key(key)
    end

    @impl Giggly.Geom
    def key_size(geom, key) do
      geom
      |> area()
      |> Geom.key_size(key)
    end

    # The area a density is drawn as.
    defp area(geom) do
      %Area{
        orientation: geom.orientation,
        outline_type: geom.outline_type,
        line_end: geom.line_end,
        line_join: geom.line_join,
        mitre_limit: geom.mitre_limit
      }
    end
  end
end
