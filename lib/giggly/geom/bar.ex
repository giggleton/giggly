defmodule Giggly.Geom.Bar do
  @moduledoc false

  # Bars, ggplot2's `GeomBar`, which `geom_col()` draws with: one rectangle per row, from 0 to its
  # y and centred on its x. It takes no parameters yet. Use it through `Giggly.Geom`.
  #
  # Bars use `:x`, `:y` and `:group`, and need `:x` and `:y`; an aesthetic joins the accepted list
  # with the scale that maps it, so a mapping never silently does nothing.
  #
  # A bar is horizontal when its stat says so in a `flipped_aes` column, as counting along y does,
  # or else when y is the one discrete axis, as ggplot2's `GeomBar` decides (`has_flipped_aes()`);
  # it writes the orientation in `flipped_aes` for the position to read, and makes a horizontal bar
  # as a vertical one, x and y swapped and swapped back, as ggplot2's `flip_data()` does.
  #
  # While the plot is assembled, each row becomes a rectangle in data space (`setup_data/2`), as
  # ggplot2's `GeomBar$setup_data()` makes one: from the lower of its y and 0 to the higher, and as
  # wide as the `width` its stat gave it, as counting does, or else 0.9 of the closest spacing of
  # the x positions (`Giggly.Resolution`, not counting from zero), the smallest found in any panel,
  # centred on its x; the `width` column is then dropped. A row missing its x has no width, and
  # one missing its y no height, so neither is drawn; an infinite y is not taken yet. The position
  # then stacks or moves those rectangles, and the scales are trained again to cover them.
  #
  # Every bar looks as ggplot2's default bar does, until aesthetics such as fill can be mapped or
  # set: filled with ink mixed 35% toward paper, `#595959`, with no border, its border's width the
  # theme's 0.5 mm all the same, as ggplot2's snapshots write it. A row's `alpha`, where its table
  # has one, makes the bar's fill that opaque and leaves its border opaque, as ggplot2's
  # `GeomRect` applies `fill_alpha()` to the fill alone; a row without one is opaque.

  defstruct []

  @type t :: %__MODULE__{}

  # The aesthetics a layer of bars can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :x, :y]

  # The aesthetics a layer of bars cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Aesthetics, Coord, DataFrame, Resolution}
    alias Giggly.Scene.Rectangles

    # ggplot2's default bar: its share of the spacing of the x positions, centred on its x
    # (`just = 0.5`), its fill, and its border's width, 0.5 mm, in points as grid draws a line.
    @width_share 0.9
    @just 0.5
    @fill "#595959"
    @stroke_width 0.5 * 72.27 / 25.4 * 72 / 96

    @impl Giggly.Geom
    def setup_data(_geom, frame, axis_kinds) do
      flipped = flipped?(frame, axis_kinds)
      orientation = List.duplicate(flipped, DataFrame.row_count(frame))

      frame
      |> DataFrame.put(:flipped_aes, orientation)
      |> flip(flipped)
      |> edges()
      |> flip(flipped)
    end

    # The stat's orientation where it gave one, else horizontal when y alone is discrete.
    defp flipped?(frame, axis_kinds) do
      if :flipped_aes in DataFrame.names(frame) do
        frame
        |> DataFrame.pull(:flipped_aes)
        |> Enum.find(false, fn flipped -> is_boolean(flipped) end)
      else
        axis_kinds == %{x: :continuous, y: :discrete}
      end
    end

    defp flip(frame, false), do: frame

    defp flip(frame, true) do
      renames =
        frame
        |> DataFrame.names()
        |> Aesthetics.flipped()

      DataFrame.select(frame, renames)
    end

    defp edges(frame) do
      widths = widths(frame)
      x_positions = DataFrame.pull(frame, :x)
      y_positions = DataFrame.pull(frame, :y)

      kept =
        frame
        |> DataFrame.names()
        |> Enum.reject(fn name -> name == :width end)
        |> Enum.map(fn name -> {name, name} end)

      xmins = Enum.zip_with(x_positions, widths, fn x, width -> edge(x, -width * @just) end)
      xmaxes = Enum.zip_with(x_positions, widths, fn x, width -> edge(x, width * (1 - @just)) end)

      frame
      |> DataFrame.select(kept)
      |> DataFrame.put(:xmin, xmins)
      |> DataFrame.put(:xmax, xmaxes)
      |> DataFrame.put(:ymin, Enum.map(y_positions, fn y -> toward_zero(y, :lower) end))
      |> DataFrame.put(:ymax, Enum.map(y_positions, fn y -> toward_zero(y, :higher) end))
    end

    @impl Giggly.Geom
    def draw_panel(_geom, frame, coord, panel_params) do
      placed = Coord.transform(coord, frame, panel_params)

      drawn =
        [:xmin, :xmax, :ymin, :ymax]
        |> Enum.map(fn name -> DataFrame.pull(placed, name) end)
        |> Enum.concat([opacities(placed)])
        |> Enum.zip_with(fn row -> row end)
        |> Enum.filter(fn [xmin, xmax, ymin, ymax, _opacity] ->
          Enum.all?([xmin, xmax, ymin, ymax], &is_number/1)
        end)

      [
        %Rectangles{
          xmin: Enum.map(drawn, fn [xmin, _xmax, _ymin, _ymax, _opacity] -> xmin end),
          xmax: Enum.map(drawn, fn [_xmin, xmax, _ymin, _ymax, _opacity] -> xmax end),
          ymin: Enum.map(drawn, fn [_xmin, _xmax, ymin, _ymax, _opacity] -> ymin end),
          ymax: Enum.map(drawn, fn [_xmin, _xmax, _ymin, ymax, _opacity] -> ymax end),
          fill: @fill,
          fill_opacity: Enum.map(drawn, fn [_xmin, _xmax, _ymin, _ymax, opacity] -> opacity end),
          color: :none,
          stroke_width: @stroke_width
        }
      ]
    end

    # Each row's fill opacity: its alpha, or opaque where its table has none.
    defp opacities(frame) do
      if :alpha in DataFrame.names(frame) do
        frame
        |> DataFrame.pull(:alpha)
        |> Enum.map(&opacity/1)
      else
        List.duplicate(1.0, DataFrame.row_count(frame))
      end
    end

    defp opacity(alpha) when is_number(alpha), do: alpha / 1
    defp opacity(missing) when missing in [nil, :nan], do: 1.0

    # Each row's width, ggplot2's `compute_data_size()`: the `width` its stat gave it, as counting
    # does, or else the closest spacing of the x positions in each panel, the smallest of them,
    # times the bar's share.
    defp widths(frame) do
      if :width in DataFrame.names(frame) do
        DataFrame.pull(frame, :width)
      else
        width = own_width(frame)
        List.duplicate(width, DataFrame.row_count(frame))
      end
    end

    defp own_width(frame) do
      panels = DataFrame.pull(frame, :panel)
      x_positions = DataFrame.pull(frame, :x)

      resolution =
        panels
        |> Enum.zip(x_positions)
        |> Enum.group_by(fn {panel, _x} -> panel end, fn {_panel, x} -> x end)
        |> Enum.map(fn {_panel, panel_positions} ->
          Resolution.of(panel_positions, zero: false)
        end)
        |> Enum.min()

      resolution * @width_share
    end

    # An x position moved by `offset` to a bar's edge; a missing one stays missing.
    defp edge(x, offset) when is_number(x), do: x + offset
    defp edge(missing, _offset) when missing in [nil, :nan], do: missing

    # The lower or higher of a y position and 0, as R's `pmin(y, 0)` and `pmax(y, 0)` give it, a
    # double; a missing one stays missing.
    defp toward_zero(y, :lower) when is_number(y), do: min(y / 1, 0.0)
    defp toward_zero(y, :higher) when is_number(y), do: max(y / 1, 0.0)
    defp toward_zero(missing, _end) when missing in [nil, :nan], do: missing
  end
end
