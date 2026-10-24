defmodule Giggly.Geom.Bar do
  @moduledoc false

  # Bars, ggplot2's `GeomBar`, which `geom_col()` draws with: one rectangle per row, from 0 to its
  # y and placed against its x as `just` says, ggplot2's parameter: 0.5 centres it, 0 puts its
  # lower edge on the x and 1 its upper edge. Use it through `Giggly.Geom`.
  #
  # Bars use `:x`, `:y`, `:group`, `:alpha`, `:color`, `:fill`, `:linetype`, `:linewidth` and
  # `:width`, and need `:x` and `:y`; an aesthetic joins the accepted list with the scale that maps
  # it, or, as `:width`, which no scale maps, with the setup that reads it, so a mapping never
  # silently does nothing.
  #
  # A bar is horizontal when its stat says so in a `flipped_aes` column, as counting along y does,
  # or else when y is the one discrete axis, as ggplot2's `GeomBar` decides (`has_flipped_aes()`);
  # it writes the orientation in `flipped_aes` for the position to read, and makes a horizontal bar
  # as a vertical one, x and y swapped and swapped back, as ggplot2's `flip_data()` does.
  #
  # While the plot is assembled, each row becomes a rectangle in data space (`setup_data/2`), as
  # ggplot2's `GeomBar$setup_data()` makes one: from the lower of its y and 0 to the higher, and as
  # wide as its `width`, the one its stat gave it, as counting does, or a layer maps or sets, or
  # else 0.9 of the closest spacing of the x positions (`Giggly.Resolution`, not counting from
  # zero), the smallest found in any panel, placed by `just`; the `width` column is then dropped. A
  # width that is not a number is refused, an expression's, whose type is known only once it has
  # run, as ggplot2 fails at `width * just`. A row missing its x or its width has no width, and
  # one missing its y no height, so neither is drawn; an infinite y is not taken yet. The position
  # then stacks or moves those rectangles, and the scales are trained again to cover them.
  #
  # A bar is then drawn, and its legend key too, as a rectangle (`Giggly.Geom.Rect`), as ggplot2's
  # `GeomBar` draws with its parent `GeomRect`, so a bar looks as ggplot2's default bar does.

  # Every field is given by the function that adds the layer, its defaults there.
  @enforce_keys [:just]
  defstruct @enforce_keys

  @type t :: %__MODULE__{just: float()}

  # The aesthetics a layer of bars can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics,
    do: [:alpha, :color, :fill, :group, :linetype, :linewidth, :width, :x, :y]

  # The aesthetics a layer of bars cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Aesthetics, DataFrame, Geom, Resolution}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Geom.Rect

    # ggplot2's default bar: its share of the spacing of the x positions.
    @width_share 0.9

    @impl Giggly.Geom
    def setup_data(geom, frame, axis_kinds) do
      check_width(frame)
      flipped = flipped?(frame, axis_kinds)
      orientation = List.duplicate(flipped, DataFrame.row_count(frame))

      frame
      |> DataFrame.put(:flipped_aes, orientation)
      |> flip(flipped)
      |> edges(geom.just)
      |> flip(flipped)
    end

    # A bar is drawn as wide as its width, so a width must be a number. `Giggly.Plot` refuses a
    # column or a constant that is not at the call; an expression's type is known only once it has
    # run, so one that computes anything else is refused here, where ggplot2 fails at
    # `width * just`.
    defp check_width(frame) do
      case DataFrame.dtypes(frame) do
        %{width: dtype} when dtype not in [:integer, :float, :null] ->
          raise ArgumentError,
                "a bar is drawn as wide as its width, so a width must be a number, but the " <>
                  "layer's width is a #{inspect(dtype)} column"

        _numbers_or_no_width ->
          :ok
      end
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

    defp edges(frame, just) do
      widths = widths(frame)
      x_positions = DataFrame.pull(frame, :x)
      y_positions = DataFrame.pull(frame, :y)

      kept =
        frame
        |> DataFrame.names()
        |> Enum.reject(fn name -> name == :width end)
        |> Enum.map(fn name -> {name, name} end)

      xmins = Enum.zip_with(x_positions, widths, fn x, width -> edge(x, width, -just) end)
      xmaxes = Enum.zip_with(x_positions, widths, fn x, width -> edge(x, width, 1 - just) end)

      frame
      |> DataFrame.select(kept)
      |> DataFrame.put(:xmin, xmins)
      |> DataFrame.put(:xmax, xmaxes)
      |> DataFrame.put(:ymin, Enum.map(y_positions, fn y -> toward_zero(y, :lower) end))
      |> DataFrame.put(:ymax, Enum.map(y_positions, fn y -> toward_zero(y, :higher) end))
    end

    # A bar's defaults are a rectangle's, as ggplot2's `GeomBar` takes `GeomRect`'s `default_aes`;
    # its default width, which R adds back once the width has been read, is left out, since it is
    # not the width the bar is drawn at.
    @impl Giggly.Geom
    def default_aesthetics(_geom, element), do: Geom.default_aesthetics(%Rect{}, element)

    # Each bar as a rectangle, ggplot2's `GeomRect` drawing it.
    @impl Giggly.Geom
    def draw_panel(_geom, frame, coord, panel_params),
      do: Geom.draw_panel(%Rect{}, frame, coord, panel_params)

    # A legend's key, and the room it needs, as a rectangle's.
    @impl Giggly.Geom
    def draw_key(_geom, key), do: Geom.draw_key(%Rect{}, key)

    @impl Giggly.Geom
    def key_size(_geom, key), do: Geom.key_size(%Rect{}, key)

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

    # An x position moved by a share of its bar's width to an edge, in R's arithmetic, so an
    # infinite bar's edge is at an infinity or NaN; a missing one stays missing.
    defp edge(x, width, share), do: Arithmetic.add(x, Arithmetic.multiply(width, share))

    # The lower or higher of a y position and 0, as R's `pmin(y, 0)` and `pmax(y, 0)` give it, a
    # double: an infinite bar runs from 0 to its infinity, at the panel's edge; a missing one stays
    # missing.
    defp toward_zero(y, :lower) when is_number(y), do: min(y / 1, 0.0)
    defp toward_zero(y, :higher) when is_number(y), do: max(y / 1, 0.0)
    defp toward_zero(:infinity, :lower), do: 0.0
    defp toward_zero(:neg_infinity, :higher), do: 0.0
    defp toward_zero(other, _end) when other in [nil, :nan, :infinity, :neg_infinity], do: other
  end
end
