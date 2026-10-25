defmodule Giggly.Geom.Area do
  @moduledoc false

  # Areas, ggplot2's `GeomArea`, which `geom_area()` draws with: the band from 0 to each group's
  # `y` along its `x`, or, turned, from 0 to its `x` up its `y`. It is ggplot2's `GeomRibbon` with
  # its band set up from its y, so it is drawn as a ribbon (`Giggly.Geom.Ribbon`), with the same
  # parameters: which way it runs (`orientation`, `:x` unless the layer says `:y`, as ggplot2 takes
  # an area's orientation to be ambiguous), which edges are outlined (`outline_type`, ggplot2's
  # `geom_area()` outlining the upper one), and how its outlines' ends and corners are drawn. Use
  # it through `Giggly.Geom`.
  #
  # Areas use `:x`, `:y`, `:group`, `:alpha`, `:color`, `:fill`, `:linetype` and `:linewidth`, and
  # need `:x` and `:y`, which the stat before them needs too; an aesthetic joins the accepted list
  # with the scale that maps it, so a mapping never silently does nothing.
  #
  # While the plot is assembled (`setup_data/3`), an area runs along y where its stat says so in
  # `flipped_aes`, as aligning does, or else where the layer says so, writes that in `flipped_aes`,
  # puts its rows in order of panel, group and the position it runs along, as a ribbon's, and runs
  # from a `ymin` of 0 to a `ymax` of its `y` (`xmin` and `xmax`, turned), as
  # `GeomArea$setup_data()` sets them, so stacking piles the bands. It is then drawn as a ribbon,
  # a row dropped where it is missing its `x` or `y`, as ggplot2's `GeomArea` reads its required
  # aesthetics; its defaults and its legend key are a ribbon's.

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

  # The aesthetics a layer of areas can use, from its own mapping or the plot's. What it cannot be
  # drawn without, `:x` and `:y`, the stat that runs before it needs, aligning or a density, so a
  # layer is checked against the stat's requirements.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:alpha, :color, :fill, :group, :linetype, :linewidth, :x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{DataFrame, Geom}
    alias Giggly.Geom.Ribbon

    # An area's defaults are a ribbon's, as ggplot2's `GeomArea` takes `GeomRibbon`'s
    # `default_aes`.
    @impl Giggly.Geom
    def default_aesthetics(geom, element) do
      geom
      |> ribbon()
      |> Geom.default_aesthetics(element)
    end

    # ggplot2's `GeomArea$setup_data()`: the orientation written in `flipped_aes`, the rows in order
    # along it, and each band from 0 to its y.
    @impl Giggly.Geom
    def setup_data(geom, frame, _axis_kinds) do
      flipped = flipped?(geom, frame)
      rows = DataFrame.row_count(frame)

      ordered =
        frame
        |> DataFrame.put(:flipped_aes, List.duplicate(flipped, rows))
        |> Ribbon.flip(flipped)
        |> Ribbon.in_order()

      ordered
      |> DataFrame.put(:ymin, List.duplicate(0.0, rows))
      |> DataFrame.put(:ymax, DataFrame.pull(ordered, :y))
      |> Ribbon.flip(flipped)
    end

    # The stat's orientation where it gave one, as aligning does, else the layer's.
    defp flipped?(geom, frame) do
      stat_flipped =
        if :flipped_aes in DataFrame.names(frame) do
          frame
          |> DataFrame.pull(:flipped_aes)
          |> Enum.find(fn flipped -> is_boolean(flipped) end)
        end

      case stat_flipped do
        nil -> geom.orientation == :y
        flipped -> flipped
      end
    end

    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params),
      do: Ribbon.draw(geom, frame, coord, panel_params, [:x, :y])

    @impl Giggly.Geom
    def draw_key(geom, key) do
      geom
      |> ribbon()
      |> Geom.draw_key(key)
    end

    @impl Giggly.Geom
    def key_size(geom, key) do
      geom
      |> ribbon()
      |> Geom.key_size(key)
    end

    # The ribbon an area is drawn as.
    defp ribbon(geom) do
      %Ribbon{
        orientation: geom.orientation,
        outline_type: geom.outline_type,
        line_end: geom.line_end,
        line_join: geom.line_join,
        mitre_limit: geom.mitre_limit
      }
    end
  end
end
