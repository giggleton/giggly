defmodule Giggly.Guide.Box do
  @moduledoc false

  # The box the plot's guides of aesthetics other than position are stacked in, as ggplot2's
  # `package_box()` stacks them: in a column, each guide in its own row as tall as it is, the
  # theme's spacing down between (`legend_spacing_y`), or in a row, each in its own column as wide
  # as it is, the spacing across between (`legend_spacing_x`), as the theme arranges them
  # (`legend_box`), in a row above or below the panels and in a column elsewhere where it does not;
  # in the order given. Each guide's own point is placed at the same point of its room, the column
  # as wide as the widest guide or the row as tall as the tallest, by the theme's justification
  # (`legend_box_just`), or at its room's top, left in a column beside or inside the panels and
  # centred across in a row above or below them, as ggplot2 justifies them by where the box goes
  # whatever their arrangement. Round the guides, the box's margin (`legend_box_margin`), and
  # under them its background (`legend_box_background`), over the margin too; theme_gray() gives
  # it neither.

  alias Giggly.{Scene, Theme}
  alias Giggly.Scene.{Cell, Rect}

  # The guides, each its width and table as `Giggly.Guide.draw/3` draws it, stacked in a box where
  # legends run `direction`, across above or below the panels and down elsewhere, in `theme`'s
  # arrangement, spacing and justification: its width and height in points and its table, for
  # rendering to place beside or inside the panels.
  @doc false
  @spec draw([{float(), Scene.t()}], Theme.direction(), Theme.t()) ::
          {float(), float(), Scene.t()}
  def draw(guides, direction, %Theme{legend_box_margin: margin} = theme) do
    sizes = Enum.map(guides, fn {width, scene} -> {width, height(scene)} end)
    justification = justification(theme.legend_box_just, direction)

    {widths, heights, places} =
      arrange(
        sizes,
        arrangement(theme.legend_box, direction),
        {theme.legend_spacing_x, theme.legend_spacing_y}
      )

    widths = Enum.concat([[margin.left], widths, [margin.right]])
    heights = Enum.concat([[margin.top], heights, [margin.bottom]])

    cells =
      Enum.zip_with([guides, sizes, places], fn [{_width, scene}, size, {row, column}] ->
        %Cell{
          rows: row..row,
          columns: column..column,
          clip: :off,
          hang: {:at, justification, justification, size},
          primitives: [scene]
        }
      end)

    box = %Scene{
      widths: Enum.map(widths, fn width -> {:points, width} end),
      heights: Enum.map(heights, fn height -> {:points, height} end),
      keep_proportions: false,
      cells: background(length(widths), length(heights), theme.legend_box_background) ++ cells
    }

    {Enum.sum(widths), Enum.sum(heights), box}
  end

  defp arrangement(:none, direction), do: direction
  defp arrangement(arrangement, _direction), do: arrangement

  # Where each legend sits in its room where the theme leaves it: at its room's top, at its left
  # down a column and centred across a row.
  defp justification(:none, :vertical), do: {0.0, 1.0}
  defp justification(:none, :horizontal), do: {0.5, 1.0}
  defp justification(justification, _direction), do: justification

  # The guides of `sizes` arranged in a column or a row, `spacing` apart: the box's widths and
  # heights inside its margin, and each guide's row and column, the margin's first.
  defp arrange(sizes, :vertical, {_across, down}) do
    {widths, heights} = Enum.unzip(sizes)
    places = Enum.map(0..(length(sizes) - 1)//1, fn index -> {2 + 2 * index, 2} end)
    {[Enum.max(widths)], Enum.intersperse(heights, down), places}
  end

  defp arrange(sizes, :horizontal, {across, _down}) do
    {widths, heights} = Enum.unzip(sizes)
    places = Enum.map(0..(length(sizes) - 1)//1, fn index -> {2, 2 + 2 * index} end)
    {Enum.intersperse(widths, across), [Enum.max(heights)], places}
  end

  # The box's background over the whole of it, its margin included, none where the theme removes
  # it.
  defp background(_columns, _rows, :none), do: []

  defp background(columns, rows, look) do
    [
      %Cell{
        rows: 1..rows,
        columns: 1..columns,
        clip: :off,
        hang: :none,
        primitives: [
          %Rect{
            fill: look.fill,
            fill_opacity: look.fill_opacity,
            color: look.color,
            color_opacity: look.color_opacity,
            stroke_width: look.line_width,
            dashes: look.dashes
          }
        ]
      }
    ]
  end

  # A guide's height in points, the sum of its rows'.
  defp height(%Scene{heights: heights}),
    do: Enum.sum(for {:points, height} <- heights, do: height)
end
