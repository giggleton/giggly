defmodule Giggly.Guide do
  @moduledoc """
  Guides: what lets a reader turn marks back into data. In ggplot2, axes and legends are both
  guides (`guide_axis()`, `guide_legend()`), each drawing what it is given of a scale's breaks;
  so far Giggly draws axes (`Giggly.Guide.Axis`).

  When a plot is rendered, `axes/2` takes a panel's params and the axes' titles and draws an axis
  on each side of the panel that the coordinate system puts one, from that axis's breaks already
  placed along the side (`Giggly.Coord.axes/1`), so ticks and marks are placed by one rule, and
  the title of the aesthetic the coordinate system says that side shows. The axis and its title
  each come back as a size and primitives, ready to be cells of the scene beside the panel.
  """

  # A guide asks the coordinate system where the breaks go, measures text, and draws primitives.
  use Boundary, deps: [Giggly.Coord, Giggly.Font, Giggly.Scene], exports: []

  alias Giggly.{Coord, Guide, Scene}

  @typedoc """
  Something drawn beside the panel: how far it reaches out, in points (its width beside the panel
  or its height below it), and what it draws, placed in a cell that deep and as long as the
  panel's side.
  """
  @type drawn_axis :: {float(), [Scene.primitive()]}

  @doc """
  The axis and its title drawn on each side of the panel that `panel_params` describes, by side,
  given each aesthetic's title, `:none` for none. An axis with no breaks, and a title of `:none`,
  draw nothing and take no room:

      iex> params = Giggly.Coord.panel_params(:cartesian, {{0.0, 1.0}, []}, {{0.0, 1.0}, []})
      iex> Giggly.Guide.axes(params, %{x: :none, y: :none})
      %{
        bottom: %{axis: {0.0, []}, title: {0.0, []}},
        left: %{axis: {0.0, []}, title: {0.0, []}}
      }
  """
  @spec axes(Coord.panel_params(), %{(:x | :y) => String.t() | :none}) ::
          %{Coord.side() => %{axis: drawn_axis(), title: drawn_axis()}}
  def axes(panel_params, titles) do
    panel_params
    |> Coord.axes()
    |> Map.new(fn {side, {aesthetic, breaks}} ->
      title =
        titles
        |> Map.fetch!(aesthetic)
        |> Guide.Axis.title(side)

      {side, %{axis: Guide.Axis.draw(breaks, side), title: title}}
    end)
  end
end
