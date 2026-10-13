defmodule Giggly.Theme.Gray do
  @moduledoc """
  ggplot2's default theme, `theme_gray()` (defined there as `theme_grey()`), at its default
  arguments: an 11-point base size, black ink on white paper, and lines and borders half a
  millimetre wide. Use it through `Giggly.Theme`.

  Every element is worked out from those arguments as `theme_gray()` works it out: `half_line`,
  half the base size, spaces most things, and each colour is ink mixed toward paper by ggplot2's
  `col_mix()`. ggplot2 gives lengths in TeX points (1/72.27 inch) and line widths in millimetres,
  which grid draws as `.pt` line-width units of 1/96 inch each; each is converted here into the
  scene's points (1/72 inch), so nothing that reads the theme converts anything.

  The plot's background is white with a white border, and the plot margin is `half_line` on every
  side. The panel's background is light grey (ink mixed 92% toward paper) with no border, and its
  grid lines are paper white, the major ones as wide as a line and the minor ones half that. An
  axis's ticks are dark grey (ink mixed 20% toward paper), `half_line / 2` long and as wide
  as a line; its labels are grey (30.2% toward paper), 0.8 of the base size, `0.8 * half_line / 2`
  from the ticks; its title is black at the base size, `half_line / 2` from the labels.
  """

  @behaviour Giggly.Theme

  # Scene points per TeX point (grid's "pt"), the unit ggplot2's theme gives lengths in.
  @points_per_theme_point 72 / 72.27

  # ggplot2's line widths are millimetres, which grid draws as `.pt` line-width units each, and a
  # line-width unit is 1/96 inch.
  @points_per_millimetre_of_line 72.27 / 25.4 * (72 / 96)

  # `theme_gray()`'s arguments.
  @base_size 11.0
  @base_line_size @base_size / 22
  @base_rect_size @base_size / 22
  @ink "#000000"
  @paper "#FFFFFF"

  @half_line @base_size / 2

  # `col_mix(ink, paper, amount)` for black ink on white paper, as ggplot2 rounds it.
  @ink_toward_paper_20 "#333333"
  @ink_toward_paper_30_2 "#4D4D4D"
  @ink_toward_paper_92 "#EBEBEB"

  @impl Giggly.Theme
  def complete do
    %Giggly.Theme{
      plot_background: %{
        fill: @paper,
        color: @paper,
        line_width: @base_rect_size * @points_per_millimetre_of_line
      },
      plot_margin: @half_line * @points_per_theme_point,
      panel_background: %{
        fill: @ink_toward_paper_92,
        color: :none,
        line_width: @base_rect_size * @points_per_millimetre_of_line
      },
      panel_grid_major: %{
        color: @paper,
        line_width: @base_line_size * @points_per_millimetre_of_line
      },
      panel_grid_minor: %{
        color: @paper,
        line_width: 0.5 * @base_line_size * @points_per_millimetre_of_line
      },
      axis_ticks: %{
        color: @ink_toward_paper_20,
        line_width: @base_line_size * @points_per_millimetre_of_line
      },
      axis_ticks_length: @half_line / 2 * @points_per_theme_point,
      axis_text: %{
        size: 0.8 * @base_size,
        color: @ink_toward_paper_30_2,
        margin: 0.8 * @half_line / 2 * @points_per_theme_point
      },
      axis_title: %{
        size: @base_size,
        color: @ink,
        margin: @half_line / 2 * @points_per_theme_point
      }
    }
  end
end
