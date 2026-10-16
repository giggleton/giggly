defmodule Giggly.Guide do
  @moduledoc false

  # Guides: what lets a reader turn marks back into data. In ggplot2, axes and legends are both
  # guides (`guide_axis()`, `guide_legend()`), each drawing what it is given of a scale's breaks;
  # so far Giggly draws axes (`Giggly.Guide.Axis`), the axis around a radial panel's circle
  # (`Giggly.Guide.AxisTheta`), ggplot2's `guide_axis_theta()`, the panel's background and grid lines
  # (`Giggly.Guide.Grid`), which ggplot2 draws with `guide_grid()`, the strips that label a
  # facet's panels with their values (`Giggly.Guide.Strip`), which ggplot2's facets draw with
  # `render_strips()`: a strip, like an axis, tells a reader what data the marks beside it show;
  # and a legend for an aesthetic other than position (`Giggly.Guide.Legend`), `guide_legend()`,
  # its keys drawn with glyphs rendering has each layer's geom draw, laid out as a table of its own.
  #
  # When a plot is rendered, `axes/3` takes the plot's coordinate system, a panel's params and the
  # plot's complete theme (`Giggly.Theme`), and draws an axis on each side of the panel that the
  # coordinate system puts one, from that axis's breaks already placed along the side
  # (`Giggly.Coord.axes/2`), in the look the coordinate system names, so ticks and marks are placed
  # by one rule; `axes_inside/3` draws the axes the coordinate system puts inside the panel, over
  # its layers, a radial panel's angle axis, as ggplot2's coordinate system draws its foreground
  # (`render_fg()`); `titles/4` draws the title
  # of the aesthetic the coordinate system says each side shows, once for the plot, however many
  # panels it has; `strips/2` draws a panel's strips from its labels. Each comes back as a size and
  # primitives, ready to be cells of the scene beside the panel. `grid/3` draws the panel's
  # background and its grid lines, placed by the coordinate system (`Giggly.Coord.grid/2`), under
  # whatever the panel's layers draw.

  # A guide asks the coordinate system where the breaks go, reads its look from the theme,
  # measures text, and draws primitives.
  use Boundary, deps: [Giggly.Coord, Giggly.Font, Giggly.Scene, Giggly.Theme], exports: []

  alias Giggly.{Coord, Guide, Scene, Theme}

  @typedoc """
  Something drawn beside the panel: how far it reaches out, in points (its width beside the panel
  or its height above or below it), and what it draws, placed in a cell that deep and as long as
  the panel's side.
  """
  @type drawn :: {float(), [Scene.primitive()]}

  # The axis drawn on each side of the panel that `panel_params` describes under `coord`, by side,
  # in the look the coordinate system names and `theme`'s. An axis with no breaks draws nothing and
  # takes no room.
  @doc false
  @spec axes(Coord.t(), Coord.panel_params(), Theme.t()) :: %{Coord.side() => drawn()}
  def axes(coord, panel_params, theme) do
    coord
    |> sides(panel_params)
    |> Map.new(fn {side, {_aesthetic, look, breaks}} ->
      {side, Guide.Axis.draw(breaks, side, look, theme)}
    end)
  end

  # The axes drawn inside the panel that `panel_params` describes under `coord`, over its layers,
  # in `theme`'s look, placed in the panel's cell: a radial panel's angle axis, around its circle;
  # none for a panel whose axes are all on its sides.
  @doc false
  @spec axes_inside(Coord.t(), Coord.panel_params(), Theme.t()) :: [Scene.primitive()]
  def axes_inside(coord, panel_params, theme) do
    case Coord.axes(coord, panel_params) do
      %{theta: {_aesthetic, :theta, breaks}} -> Guide.AxisTheta.draw(breaks, theme)
      %{} -> []
    end
  end

  # The title of the axis on each side of a panel that `panel_params` describes under `coord`, by
  # side, given each aesthetic's title, `:none` for none, in `theme`'s look. A title of `:none`
  # draws nothing and takes no room.
  @doc false
  @spec titles(
          Coord.t(),
          Coord.panel_params(),
          %{(:x | :y) => String.t() | :none},
          Theme.t()
        ) :: %{Coord.side() => drawn()}
  def titles(coord, panel_params, guide_titles, theme) do
    coord
    |> sides(panel_params)
    |> Map.new(fn {side, {aesthetic, _look, _breaks}} ->
      title =
        guide_titles
        |> Map.fetch!(aesthetic)
        |> Guide.Axis.title(side, theme)

      {side, title}
    end)
  end

  # The axes the coordinate system puts on the panel's sides.
  defp sides(coord, panel_params) do
    coord
    |> Coord.axes(panel_params)
    |> Map.take([:bottom, :left])
  end

  # A legend titled `title`, a key for each of `keys`, its label and the glyphs each layer draws in
  # it, in `theme`'s look: its width in points and its table, for rendering to place right of the
  # panels, ggplot2's `guide_legend()`.
  @doc false
  @spec legend(String.t(), [{String.t(), [Scene.primitive()]}], Theme.t()) :: {float(), Scene.t()}
  def legend(title, keys, theme), do: Guide.Legend.draw(title, keys, theme)

  # A panel's strips, one for each of `labels`, top to bottom, in `theme`'s look: ggplot2's
  # `render_strips()` for strips above a panel. A panel with no labels has no strips.
  @doc false
  @spec strips([String.t()], Theme.t()) :: [drawn()]
  def strips(labels, theme), do: Enum.map(labels, fn label -> Guide.Strip.draw(label, theme) end)

  # The background and grid lines of the panel that `panel_params` describes under `coord`, in
  # `theme`'s look, in drawing order, placed in the panel's cell.
  @doc false
  @spec grid(Coord.t(), Coord.panel_params(), Theme.t()) :: [Scene.primitive()]
  def grid(coord, panel_params, theme) do
    coord
    |> Coord.grid(panel_params)
    |> Guide.Grid.draw(theme)
  end
end
