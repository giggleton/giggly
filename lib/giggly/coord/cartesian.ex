defmodule Giggly.Coord.Cartesian do
  @moduledoc false

  # Cartesian coordinates, ggplot2's `coord_cartesian()`: x across the panel and y up it, each
  # rescaled from its axis's extent to 0 to 1. Its struct holds its parameters: whether each panel
  # is clipped to its edges, `:on` by default, as ggplot2's is. Its panel params hold the x and y
  # extents, already widened by the scales, and each axis's breaks and minor breaks. Run it through
  # `Giggly.Coord`.
  #
  # An infinite position is put at the panel's edge, as ggplot2's `squish_infinite()` puts it, so a
  # mark can reach the edge whatever the range; a missing one (`nil`, or the float `:nan`) stays
  # missing for the geom to drop. On an axis whose extent has equal ends, which the scale gives one
  # R's `zero_range()` calls zero wide, every position is put at the panel's middle, infinite ones
  # too, as `scales::rescale()` puts them before ggplot2 squishes anything.
  #
  # The x axis is drawn below the panel and the y axis to its left, ggplot2's default places, each
  # in its own aesthetic's look and each break placed by the same rescale as the data. Its grid
  # lines are straight, each crossing the panel from edge to edge at a break or a minor break,
  # placed the same way; the lines crossing an axis of equal ends shrink to a point at its middle,
  # as ggplot2's do. Its background fills the panel, and a panel takes whatever shape the drawing
  # leaves it, as ggplot2's `coord_cartesian()` has no aspect ratio.

  defstruct clip: :on

  @type t :: %__MODULE__{clip: :on}

  @typedoc "A panel's params under cartesian coordinates."
  @type panel_params :: %{
          x_range: {number(), number()},
          y_range: {number(), number()},
          x_breaks: [Giggly.Coord.break()],
          y_breaks: [Giggly.Coord.break()],
          x_minor_breaks: [number()],
          y_minor_breaks: [number()]
        }

  defimpl Giggly.Coord, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Coord

    alias Giggly.{Aesthetics, DataFrame}

    @impl Giggly.Coord
    def panel_params(
          _coord,
          {x_range, x_breaks, x_minor_breaks},
          {y_range, y_breaks, y_minor_breaks}
        ) do
      %{
        x_range: x_range,
        y_range: y_range,
        x_breaks: x_breaks,
        y_breaks: y_breaks,
        x_minor_breaks: x_minor_breaks,
        y_minor_breaks: y_minor_breaks
      }
    end

    @impl Giggly.Coord
    def transform(_coord, frame, %{x_range: x_range, y_range: y_range}) do
      frame
      |> DataFrame.names()
      |> Enum.reduce(frame, fn name, placed ->
        case Aesthetics.family(name) do
          :x -> rescale_column(placed, name, x_range)
          :y -> rescale_column(placed, name, y_range)
          :none -> placed
        end
      end)
    end

    # A straight line stays straight, so its points are placed as they are, as ggplot2's
    # `coord_munch()` only transforms under a linear coordinate system.
    @impl Giggly.Coord
    def munch(coord, frame, params), do: transform(coord, frame, params)

    @impl Giggly.Coord
    def axes(_coord, %{
          x_range: x_range,
          y_range: y_range,
          x_breaks: x_breaks,
          y_breaks: y_breaks
        }) do
      %{
        bottom: {:x, :x, place_breaks(x_breaks, x_range)},
        left: {:y, :y, place_breaks(y_breaks, y_range)}
      }
    end

    @impl Giggly.Coord
    def clip(%{clip: clip}), do: clip

    @impl Giggly.Coord
    def aspect(_coord, _panel_params), do: :none

    @impl Giggly.Coord
    def grid(_coord, %{x_range: x_range, y_range: y_range} = params) do
      major_x = Enum.map(params.x_breaks, fn {position, _label} -> position end)
      major_y = Enum.map(params.y_breaks, fn {position, _label} -> position end)

      %{
        major: %{x: x_lines(major_x, x_range, y_range), y: y_lines(major_y, x_range, y_range)},
        minor: %{
          x: x_lines(params.x_minor_breaks, x_range, y_range),
          y: y_lines(params.y_minor_breaks, x_range, y_range)
        },
        background: :panel
      }
    end

    # ggplot2 runs each grid line from minus to plus infinity along the other axis, through the
    # same rescale as the data, which puts its ends at that axis's edges, 0 and 1, or both at its
    # middle when its extent has equal ends: an x line up the panel from its bottom, a y line
    # across it from its left.
    defp x_lines(positions, x_range, y_range) do
      bottom = rescale(:neg_infinity, y_range)
      top = rescale(:infinity, y_range)

      Enum.map(positions, fn position ->
        place = rescale(position, x_range)
        [{place, bottom}, {place, top}]
      end)
    end

    defp y_lines(positions, x_range, y_range) do
      left = rescale(:neg_infinity, x_range)
      right = rescale(:infinity, x_range)

      Enum.map(positions, fn position ->
        place = rescale(position, y_range)
        [{left, place}, {right, place}]
      end)
    end

    defp place_breaks(breaks, range) do
      Enum.map(breaks, fn {position, label} -> {rescale(position, range), label} end)
    end

    defp rescale_column(frame, name, range) do
      rescaled =
        frame
        |> DataFrame.pull(name)
        |> Enum.map(fn value -> rescale(value, range) end)

      DataFrame.put(frame, name, rescaled)
    end

    # An extent of equal ends is one R's `zero_range()` calls zero wide, and `scales::rescale()`
    # puts every value on it at the middle, infinities included, since ggplot2 squishes them only
    # after.
    defp rescale(value, {low, low}) when is_number(value) or value in [:infinity, :neg_infinity],
      do: 0.5

    defp rescale(:infinity, _range), do: 1.0
    defp rescale(:neg_infinity, _range), do: 0.0
    defp rescale(value, {low, high}) when is_number(value), do: (value - low) / (high - low)
    defp rescale(missing, _range), do: missing
  end
end
