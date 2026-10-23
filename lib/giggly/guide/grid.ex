defmodule Giggly.Guide.Grid do
  @moduledoc false

  # A panel's background and grid, ggplot2's `guide_grid()`: the background, filling the panel or
  # the shape the coordinate system gives it, a radial panel's disc, and a line through it at each
  # break and minor break, all of which the coordinate system has already placed
  # (`Giggly.Coord.grid/2`), drawn under whatever the panel's layers draw.
  #
  # It looks as the theme says (`Giggly.Theme`): the panel's background, then its minor grid lines
  # and its major ones over them, each line in the look of the axis whose breaks it marks
  # (`panel_grid_minor_y` and the rest). They are drawn in ggplot2's order: the background, the
  # minor lines at the y axis's minor breaks, then at the x axis's, then the major lines at the y
  # axis's breaks and then at the x axis's, so a major line is drawn over a minor one and an x line
  # over a y. A background or a group of lines the theme removes draws nothing.

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
  defp grid(%{major: major, minor: minor, background: shape}, %Theme{} = theme) do
    Enum.concat([
      background(shape, theme.panel_background),
      lines(minor.y, theme.panel_grid_minor_y),
      lines(minor.x, theme.panel_grid_minor_x),
      lines(major.y, theme.panel_grid_major_y),
      lines(major.x, theme.panel_grid_major_x)
    ])
  end

  # A background filling the panel is a rectangle, as ggplot2's is; any other is the polygon round
  # its outline, as ggplot2 draws a munched background.
  defp background(_shape, :none), do: []

  defp background(:panel, look),
    do: [%Rect{fill: look.fill, color: look.color, stroke_width: look.line_width}]

  defp background(outline, look) do
    [
      %Polygons{
        outlines: [outline],
        offsets: :none,
        stroke_width: look.line_width,
        color: [look.color],
        color_opacity: [1.0],
        fill: [look.fill],
        fill_opacity: [1.0],
        dashes: :none,
        line_end: :round,
        line_join: :round,
        mitre_limit: 10.0
      }
    ]
  end

  # Lines in the theme's look, opaque, their ends as the theme says and their corners round, as
  # `theme_gray()`'s `line` element draws every line.
  defp lines(_lines, :none), do: []

  defp lines(lines, look) do
    [
      %Polylines{
        lines: lines,
        offsets: :none,
        stroke_width: look.line_width,
        dashes: :none,
        color: List.duplicate(look.color, length(lines)),
        opacity: List.duplicate(1.0, length(lines)),
        line_end: look.line_end,
        line_join: :round,
        mitre_limit: 10.0
      }
    ]
  end
end
