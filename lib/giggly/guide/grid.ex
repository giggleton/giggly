defmodule Giggly.Guide.Grid do
  @moduledoc false

  # A panel's background and grid, ggplot2's `guide_grid()`: the background filling the panel, and
  # a line across it at each break and minor break, which the coordinate system has already placed
  # (`Giggly.Coord.grid/2`). Use it through `Giggly.Guide`.
  #
  # It looks as the theme says (`Giggly.Theme`): the panel's background, then its minor grid lines
  # and its major ones over them. They are drawn in ggplot2's order: the background, the minor lines
  # at the y axis's minor breaks, then at the x axis's, then the major lines at the y axis's breaks
  # and then at the x axis's, so a major line is drawn over a minor one and an x line over a y.

  alias Giggly.Scene.{Polylines, Rect}
  alias Giggly.Theme

  # The panel's background and the lines of `grid`, in `theme`'s look and ggplot2's order, placed in
  # the panel's cell.
  @doc false
  @spec draw(Giggly.Coord.grid(), Theme.t()) :: [Giggly.Scene.primitive()]
  def draw(%{major: major, minor: minor, background: :panel}, %Theme{
        panel_background: background,
        panel_grid_major: major_look,
        panel_grid_minor: minor_look
      }) do
    [
      %Rect{fill: background.fill, color: background.color, stroke_width: background.line_width},
      lines(minor.y, minor_look),
      lines(minor.x, minor_look),
      lines(major.y, major_look),
      lines(major.x, major_look)
    ]
  end

  defp lines(lines, look),
    do: %Polylines{lines: lines, stroke_width: look.line_width, color: look.color}
end
