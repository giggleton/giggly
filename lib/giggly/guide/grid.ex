defmodule Giggly.Guide.Grid do
  @moduledoc false

  # A panel's background and grid, ggplot2's `guide_grid()`: the background, filling the panel or
  # the shape the coordinate system gives it, a radial panel's disc, and a line through it at each
  # break and minor break, all of which the coordinate system has already placed
  # (`Giggly.Coord.grid/2`), drawn under whatever the panel's layers draw.
  #
  # It looks as the theme says (`Giggly.Theme`): the panel's background, then its minor grid lines
  # and its major ones over them. They are drawn in ggplot2's order: the background, the minor lines
  # at the y axis's minor breaks, then at the x axis's, then the major lines at the y axis's breaks
  # and then at the x axis's, so a major line is drawn over a minor one and an x line over a y.

  alias Giggly.{Coord, Theme}
  alias Giggly.Scene.{Polygons, Polylines, Rect}

  # The background and grid lines of the panel that `panel_params` describes under `coord`, in
  # `theme`'s look, in drawing order, placed in the panel's cell.
  @doc false
  @spec draw(Coord.t(), Coord.panel_params(), Theme.t()) :: [Giggly.Scene.primitive()]
  def draw(coord, panel_params, theme) do
    coord
    |> Coord.grid(panel_params)
    |> grid(theme)
  end

  # The panel's background and the lines of `grid`, in `theme`'s look and ggplot2's order, placed in
  # the panel's cell.
  defp grid(%{major: major, minor: minor, background: shape}, %Theme{
         panel_background: background,
         panel_grid_major: major_look,
         panel_grid_minor: minor_look
       }) do
    [
      background(shape, background),
      lines(minor.y, minor_look),
      lines(minor.x, minor_look),
      lines(major.y, major_look),
      lines(major.x, major_look)
    ]
  end

  # A background filling the panel is a rectangle, as ggplot2's is; any other is the polygon round
  # its outline, as ggplot2 draws a munched background.
  defp background(:panel, look),
    do: %Rect{fill: look.fill, color: look.color, stroke_width: look.line_width}

  defp background(outline, look) do
    %Polygons{
      outlines: [outline],
      fill: look.fill,
      color: look.color,
      stroke_width: look.line_width
    }
  end

  # Lines in the theme's look, opaque, their ends cut square and their corners round, as
  # `theme_gray()`'s `line` element draws every line.
  defp lines(lines, look) do
    %Polylines{
      lines: lines,
      offsets: :none,
      stroke_width: look.line_width,
      color: List.duplicate(look.color, length(lines)),
      opacity: List.duplicate(1.0, length(lines)),
      line_end: :butt,
      line_join: :round,
      mitre_limit: 10.0
    }
  end
end
