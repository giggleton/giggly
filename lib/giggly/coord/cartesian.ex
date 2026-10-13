defmodule Giggly.Coord.Cartesian do
  @moduledoc """
  Cartesian coordinates, ggplot2's `coord_cartesian()`: x across the panel and y up it, each
  rescaled from its axis's extent to 0 to 1. Its struct is a panel's params: the x and y extents,
  already widened by the scales, and each axis's breaks and minor breaks. Use it through
  `Giggly.Coord`.

  An infinite position is put at the panel's edge, as ggplot2's `squish_infinite()` puts it, so a
  mark can reach the edge whatever the range; a missing one (`nil`, or the float `:nan`) stays
  missing for the geom to drop. The x axis is drawn below the panel and the y axis to its left,
  ggplot2's default places, each break placed by the same rescale as the data. Its grid lines are
  straight, each crossing the panel from edge to edge at a break or a minor break, placed the same
  way.
  """

  @behaviour Giggly.Coord

  alias Giggly.{Aesthetics, DataFrame}

  @enforce_keys [:x_range, :y_range, :x_breaks, :y_breaks, :x_minor_breaks, :y_minor_breaks]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          x_range: {number(), number()},
          y_range: {number(), number()},
          x_breaks: [Giggly.Coord.break()],
          y_breaks: [Giggly.Coord.break()],
          x_minor_breaks: [number()],
          y_minor_breaks: [number()]
        }

  @impl Giggly.Coord
  def panel_params({x_range, x_breaks, x_minor_breaks}, {y_range, y_breaks, y_minor_breaks}) do
    %__MODULE__{
      x_range: x_range,
      y_range: y_range,
      x_breaks: x_breaks,
      y_breaks: y_breaks,
      x_minor_breaks: x_minor_breaks,
      y_minor_breaks: y_minor_breaks
    }
  end

  @impl Giggly.Coord
  def transform(frame, %__MODULE__{x_range: x_range, y_range: y_range}) do
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

  @impl Giggly.Coord
  def axes(%__MODULE__{
        x_range: x_range,
        y_range: y_range,
        x_breaks: x_breaks,
        y_breaks: y_breaks
      }) do
    %{bottom: {:x, place_breaks(x_breaks, x_range)}, left: {:y, place_breaks(y_breaks, y_range)}}
  end

  @impl Giggly.Coord
  def grid(%__MODULE__{} = params) do
    major_x = Enum.map(params.x_breaks, fn {position, _label} -> position end)
    major_y = Enum.map(params.y_breaks, fn {position, _label} -> position end)

    %{
      major: %{x: x_lines(major_x, params.x_range), y: y_lines(major_y, params.y_range)},
      minor: %{
        x: x_lines(params.x_minor_breaks, params.x_range),
        y: y_lines(params.y_minor_breaks, params.y_range)
      }
    }
  end

  # ggplot2 runs each grid line from minus to plus infinity, which the panel's edges squish to 0
  # and 1: an x line up the panel from its bottom, a y line across it from its left.
  defp x_lines(positions, range) do
    Enum.map(positions, fn position ->
      place = rescale(position, range)
      [{place, rescale(:neg_infinity, range)}, {place, rescale(:infinity, range)}]
    end)
  end

  defp y_lines(positions, range) do
    Enum.map(positions, fn position ->
      place = rescale(position, range)
      [{rescale(:neg_infinity, range), place}, {rescale(:infinity, range), place}]
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

  defp rescale(:infinity, _range), do: 1.0
  defp rescale(:neg_infinity, _range), do: 0.0
  defp rescale(value, {low, high}) when is_number(value), do: (value - low) / (high - low)
  defp rescale(missing, _range), do: missing
end
