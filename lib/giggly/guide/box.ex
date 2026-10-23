defmodule Giggly.Guide.Box do
  @moduledoc false

  # The box the plot's guides of aesthetics other than position are stacked in, as ggplot2's
  # `package_box()` stacks those to the right of the panels: a column as wide as the widest guide,
  # each guide in its own row as tall as it is, in the order given, the theme's legend spacing
  # between (`legend.spacing.y`), each hung from the column's left and its row's top
  # (`legend.box.just`, left and top for a vertical box). The box has no margin and no background
  # of its own, as `theme_gray()` gives it none.

  alias Giggly.{Scene, Theme}
  alias Giggly.Scene.Cell

  # The guides, each its width and table as `Giggly.Guide.draw/3` draws it, stacked in a box, in
  # `theme`'s spacing: its width in points and its table, for rendering to place right of the
  # panels.
  @doc false
  @spec draw([{float(), Scene.t()}], Theme.t()) :: {float(), Scene.t()}
  def draw(guides, %Theme{legend_spacing_y: spacing}) do
    width =
      guides
      |> Enum.map(fn {guide_width, _scene} -> guide_width end)
      |> Enum.max()

    heights =
      guides
      |> Enum.map(fn {_width, scene} -> {:points, height(scene)} end)
      |> Enum.intersperse({:points, spacing})

    cells =
      guides
      |> Enum.with_index()
      |> Enum.map(fn {{guide_width, scene}, index} ->
        row = 2 * index + 1

        %Cell{
          rows: row..row,
          columns: 1..1,
          clip: :off,
          hang: {:left, guide_width},
          primitives: [scene]
        }
      end)

    box = %Scene{
      widths: [{:points, width}],
      heights: heights,
      keep_proportions: false,
      cells: cells
    }

    {width, box}
  end

  # A guide's height in points, the sum of its rows'.
  defp height(%Scene{heights: heights}),
    do: Enum.sum(for {:points, height} <- heights, do: height)
end
