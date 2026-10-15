defmodule Giggly.Guide do
  @moduledoc false

  # Guides: what lets a reader turn marks back into data. In ggplot2, axes and legends are both
  # guides (`guide_axis()`, `guide_legend()`), each drawing what it is given of a scale's breaks;
  # so far Giggly draws axes (`Giggly.Guide.Axis`), and the panel's background and grid lines
  # (`Giggly.Guide.Grid`), which ggplot2 draws with `guide_grid()`.
  #
  # When a plot is rendered, `axes/3` takes a panel's params, the axes' titles and the plot's
  # complete theme (`Giggly.Theme`), and draws an axis on each side of the panel that the coordinate
  # system puts one, from that axis's breaks already placed along the side
  # (`Giggly.Coord.axes/1`), so ticks and marks are placed by one rule, and the title of the
  # aesthetic the coordinate system says that side shows, each in the theme's look. The axis and its
  # title each come back as a size and primitives, ready to be cells of the scene beside the panel.
  # `grid/2` draws the panel's background and its grid lines, placed by the coordinate system
  # (`Giggly.Coord.grid/1`), under whatever the panel's layers draw.

  # A guide asks the coordinate system where the breaks go, reads its look from the theme,
  # measures text, and draws primitives.
  use Boundary, deps: [Giggly.Coord, Giggly.Font, Giggly.Scene, Giggly.Theme], exports: []

  alias Giggly.{Coord, Guide, Scene, Theme}

  @typedoc """
  Something drawn beside the panel: how far it reaches out, in points (its width beside the panel
  or its height below it), and what it draws, placed in a cell that deep and as long as the
  panel's side.
  """
  @type drawn_axis :: {float(), [Scene.primitive()]}

  # The axis and its title drawn on each side of the panel that `panel_params` describes, by side,
  # given each aesthetic's title, `:none` for none, in `theme`'s look. An axis with no breaks, and
  # a title of `:none`, draw nothing and take no room.
  @doc false
  @spec axes(Coord.panel_params(), %{(:x | :y) => String.t() | :none}, Theme.t()) ::
          %{Coord.side() => %{axis: drawn_axis(), title: drawn_axis()}}
  def axes(panel_params, guide_titles, theme) do
    panel_params
    |> Coord.axes()
    |> Map.new(fn {side, {aesthetic, breaks}} ->
      title =
        guide_titles
        |> Map.fetch!(aesthetic)
        |> Guide.Axis.title(side, theme)

      {side, %{axis: Guide.Axis.draw(breaks, side, theme), title: title}}
    end)
  end

  # The background and grid lines of the panel that `panel_params` describes, in `theme`'s look,
  # in drawing order, placed in the panel's cell.
  @doc false
  @spec grid(Coord.panel_params(), Theme.t()) :: [Scene.primitive()]
  def grid(panel_params, theme) do
    panel_params
    |> Coord.grid()
    |> Guide.Grid.draw(theme)
  end
end
