defmodule Giggly.Geom.Tile do
  @moduledoc false

  # Tiles, ggplot2's `GeomTile`: one rectangle per row, centred on its x and y and as wide as its
  # `width` and as tall as its `height`. Use it through `Giggly.Geom`.
  #
  # Tiles use `:x`, `:y`, `:group`, `:alpha`, `:color`, `:fill`, `:height`, `:linetype`,
  # `:linewidth` and `:width`, and need `:x` and `:y`; an aesthetic joins the accepted list with the
  # scale that maps it, or, as `:width` and `:height`, which no scale maps, with the setup that
  # reads it, so a mapping never silently does nothing.
  #
  # While the plot is assembled, each row becomes a rectangle in data space (`setup_data/3`), as
  # ggplot2's `GeomTile$setup_data()` makes one: as wide as its `width`, the one a layer maps or
  # sets, or else the closest spacing of the x positions in its own panel (`Giggly.Resolution`, not
  # counting from zero), 1 on a discrete axis, as ggplot2's `compute_data_size()` reads a mapped
  # discrete position; and as tall as its `height`, likewise from the y positions. The `width` and
  # `height` columns are then dropped. A width or height that is not a number is refused, an
  # expression's, whose type is known only once it has run, as ggplot2 fails at `x - width / 2`. A
  # row missing its x or its width has no `xmin` or `xmax`, and one missing its y or its height no
  # `ymin` or `ymax`, so it is not drawn.
  #
  # A tile is then drawn, and its legend key too, as a rectangle (`Giggly.Geom.Rect`), as ggplot2's
  # `GeomTile` draws with its parent `GeomRect`; only its defaults are its own: a fill of the
  # theme's ink mixed 20% toward its paper, `#333333` on white paper, and a border 0.4 times the
  # theme's borders' width, 0.2 mm at its default sizes, which shows only when a colour is given.

  defstruct []

  @type t :: %__MODULE__{}

  # The aesthetics a layer of tiles can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics,
    do: [:alpha, :color, :fill, :group, :height, :linetype, :linewidth, :width, :x, :y]

  # The aesthetics a layer of tiles cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{DataFrame, Geom, Resolution}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Geom.Rect
    alias Scales.ColorOperations

    # How far a tile's default fill is mixed from the theme's ink toward its paper, ggplot2's
    # `col_mix(ink, paper, 0.2)`.
    @fill_toward_paper 0.2

    # A tile's default border's share of the theme's borders' width, ggplot2's
    # `0.4 * borderwidth`.
    @border_share 0.4

    @impl Giggly.Geom
    def setup_data(_geom, frame, axis_kinds) do
      Enum.each([:width, :height], fn size -> check_size(frame, size) end)

      kept =
        frame
        |> DataFrame.names()
        |> Enum.reject(fn name -> name in [:width, :height] end)
        |> Enum.map(fn name -> {name, name} end)

      sides = [{:x, :width, :xmin, :xmax}, {:y, :height, :ymin, :ymax}]

      Enum.reduce(sides, DataFrame.select(frame, kept), fn {position, size, low, high}, edged ->
        positions = DataFrame.pull(frame, position)
        sizes = sizes(frame, position, size, Map.fetch!(axis_kinds, position))

        lows = Enum.zip_with(positions, sizes, fn value, extent -> edge(value, extent, -0.5) end)
        highs = Enum.zip_with(positions, sizes, fn value, extent -> edge(value, extent, 0.5) end)

        edged
        |> DataFrame.put(low, lows)
        |> DataFrame.put(high, highs)
      end)
    end

    # A tile is drawn as wide as its width and as tall as its height, so each must be a number.
    # `Giggly.Plot` refuses a column or a constant that is not at the call; an expression's type is
    # known only once it has run, so one that computes anything else is refused here, where
    # ggplot2 fails at `x - width / 2`.
    defp check_size(frame, size) do
      case DataFrame.dtypes(frame) do
        %{^size => dtype} when dtype not in [:integer, :float, :null] ->
          raise ArgumentError,
                "a tile is drawn as #{size_words(size)}, so a #{size} must be a number, but " <>
                  "the layer's #{size} is a #{inspect(dtype)} column"

        _numbers_or_none ->
          :ok
      end
    end

    defp size_words(:width), do: "wide as its width"
    defp size_words(:height), do: "tall as its height"

    # Each row's width or height, ggplot2's `compute_data_size()` by panel: the one the layer maps
    # or sets, or else the closest spacing of the positions in the row's own panel, 1 on a discrete
    # axis.
    defp sizes(frame, position, size, kind) do
      if size in DataFrame.names(frame),
        do: DataFrame.pull(frame, size),
        else: panel_resolutions(frame, position, kind == :discrete)
    end

    defp panel_resolutions(frame, position, discrete) do
      panels = DataFrame.pull(frame, :panel)

      resolutions =
        panels
        |> Enum.zip(DataFrame.pull(frame, position))
        |> Enum.group_by(fn {panel, _position} -> panel end, fn {_panel, value} -> value end)
        |> Map.new(fn {panel, panel_positions} ->
          {panel, Resolution.of(panel_positions, zero: false, discrete: discrete)}
        end)

      Enum.map(panels, fn panel -> Map.fetch!(resolutions, panel) end)
    end

    # A position moved by a share of its tile's size to an edge, in R's arithmetic, so an infinite
    # tile's edge is at an infinity or NaN; a missing one stays missing.
    defp edge(position, size, share),
      do: Arithmetic.add(position, Arithmetic.multiply(size, share))

    # ggplot2's `GeomTile$default_aes`: no border, a fill of the theme's ink mixed toward its
    # paper, and a share of the theme's borders' width, in their line type; its default width and
    # height, which R adds back once they have been read, are left out, since they are not the
    # sizes the tile is drawn at.
    @impl Giggly.Geom
    def default_aesthetics(_geom, element) do
      [
        color: nil,
        fill: ColorOperations.mix(element.ink, element.paper, @fill_toward_paper),
        linewidth: @border_share * element.borderwidth,
        linetype: element.bordertype,
        alpha: nil
      ]
    end

    # Each tile as a rectangle, ggplot2's `GeomRect` drawing it.
    @impl Giggly.Geom
    def draw_panel(_geom, frame, coord, panel_params, installed_fonts),
      do: Geom.draw_panel(%Rect{}, frame, coord, panel_params, installed_fonts)

    # A legend's key, and the room it needs, as a rectangle's.
    @impl Giggly.Geom
    def draw_key(_geom, key, installed_fonts), do: Geom.draw_key(%Rect{}, key, installed_fonts)

    @impl Giggly.Geom
    def key_size(_geom, key, installed_fonts), do: Geom.key_size(%Rect{}, key, installed_fonts)
  end
end
