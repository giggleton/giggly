defmodule Giggly.Guide do
  @moduledoc """
  Guides: what lets a reader turn marks back into data. In ggplot2, axes and legends are both
  guides (`guide_axis()`, `guide_legend()`), each drawing what it is given of a scale's breaks;
  so far Giggly draws axes (`Giggly.Guide.Axis`).

  When a plot is rendered, `axes/1` takes a panel's params and draws an axis on each side of the
  panel that the coordinate system puts one, from that axis's breaks already placed along the
  side (`Giggly.Coord.axes/1`), so ticks and marks are placed by one rule. Each axis comes back
  as its size and its primitives, ready to be a cell of the scene beside the panel.
  """

  # A guide asks the coordinate system where the breaks go, measures text, and draws primitives.
  use Boundary, deps: [Giggly.Coord, Giggly.Font, Giggly.Scene], exports: []

  alias Giggly.{Coord, Guide, Scene}

  @typedoc """
  A drawn axis: how far it reaches out from the panel, in points (its width beside the panel or
  its height below it), and what it draws, placed in a cell that deep and as long as the panel's
  side.
  """
  @type drawn_axis :: {float(), [Scene.primitive()]}

  @doc """
  The axis drawn on each side of the panel that `panel_params` describes, by side. An axis with
  no breaks, as on a plot no layer maps, draws nothing and takes no room:

      iex> params = Giggly.Coord.panel_params(:cartesian, {{0.0, 1.0}, []}, {{0.0, 1.0}, []})
      iex> Giggly.Guide.axes(params)
      %{bottom: {0.0, []}, left: {0.0, []}}
  """
  @spec axes(Coord.panel_params()) :: %{Coord.side() => drawn_axis()}
  def axes(panel_params) do
    panel_params
    |> Coord.axes()
    |> Map.new(fn {side, breaks} -> {side, Guide.Axis.draw(breaks, side)} end)
  end
end
