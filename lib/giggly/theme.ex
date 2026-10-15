defmodule Giggly.Theme do
  @moduledoc false

  # Themes: the look a plot is drawn in, apart from its data. In ggplot2 a theme gives every part of
  # a plot that is not a mark its colours, sizes, line widths and spacing: the background, the axes
  # and their titles.
  #
  # A plot records its theme by name, and the name is resolved here into the complete theme, every
  # element it draws already worked out (ggplot2's `complete_theme()`): each length in points (1/72
  # inch), each colour as a hex string. Each complete theme is a function here that builds that
  # value, as ggplot2's are functions (`theme_gray()`); themes differ only in their values, so none
  # is a module implementing a behaviour, as each facet and coordinate system is. A theme derived
  # from another, as ggplot2's `theme_bw()` is from `theme_grey()`, will build on that function's
  # value by replacing elements. There is one so far, ggplot2's default, `gray/0`, and nothing can
  # change it yet; the elements a user sets, and how an element inherits what it leaves unset from
  # its parent, arrive with the first theme setting a user can make.
  #
  # When a plot is rendered, every function that draws something other than a mark takes the
  # complete theme and reads the elements it draws. A theme holds sizes, colours, line widths and
  # spacing; how text is aligned and turned is the drawing's until a theme can set it.

  # A theme is values: it calls nothing, and the complete theme is this module's struct, which a
  # boundary listing this one reads.
  use Boundary, deps: [], exports: []

  @enforce_keys [
    :plot_background,
    :plot_margin,
    :panel_background,
    :panel_grid_major,
    :panel_grid_minor,
    :axis_ticks,
    :axis_ticks_length,
    :axis_text,
    :axis_title,
    :panel_spacing,
    :strip_background,
    :strip_text
  ]
  defstruct @enforce_keys

  @typedoc "A theme's name, as a plot records it."
  @type name :: :gray

  @typedoc """
  A rectangle's look: its `fill`, the `color` of its border, `:none` for no border (ggplot2's
  `NA`), and the border's `line_width`, in points.
  """
  @type rect :: %{fill: String.t(), color: String.t() | :none, line_width: float()}

  @typedoc "A line's `color` and `line_width`, in points."
  @type line :: %{color: String.t(), line_width: float()}

  @typedoc """
  Text's `size` and `color`, and its `margin`: the space in points between it and what it labels.
  """
  @type text :: %{size: float(), color: String.t(), margin: float()}

  @typedoc """
  A complete theme: the plot's background, drawn over the whole drawing, and the margin around
  what is drawn on it, in points; the panel's background and its major and minor grid lines; each
  axis's ticks, their length in points, its labels and its title; the space between panels, in
  points; and the background and text of the strips that label each panel, the text's margin on
  every side of it.
  """
  @type t :: %__MODULE__{
          plot_background: rect(),
          plot_margin: float(),
          panel_background: rect(),
          panel_grid_major: line(),
          panel_grid_minor: line(),
          axis_ticks: line(),
          axis_ticks_length: float(),
          axis_text: text(),
          axis_title: text(),
          panel_spacing: float(),
          strip_background: rect(),
          strip_text: text()
        }

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
  @ink_toward_paper_10 "#1A1A1A"
  @ink_toward_paper_20 "#333333"
  @ink_toward_paper_30_2 "#4D4D4D"
  @ink_toward_paper_85 "#D9D9D9"
  @ink_toward_paper_92 "#EBEBEB"

  # The complete theme named `name`: every element it draws, worked out.
  @doc false
  @spec complete(name()) :: t()
  def complete(:gray), do: gray()

  # ggplot2's default theme, `theme_gray()` (defined there as `theme_grey()`), at its default
  # arguments: an 11-point base size, black ink on white paper, and lines and borders half a
  # millimetre wide.
  #
  # Every element is worked out from those arguments as `theme_gray()` works it out, in ggplot2's
  # `theme-defaults.R`: `half_line`, half the base size, spaces most things, and each colour is
  # ink mixed toward paper by ggplot2's `col_mix()`. ggplot2 gives lengths in TeX points (1/72.27
  # inch) and line widths in millimetres, which grid draws as `.pt` line-width units of 1/96 inch
  # each; each is converted here into the scene's points (1/72 inch), so nothing that reads the
  # theme converts anything.
  #
  # The plot's background is white with a white border, and the plot margin is `half_line` on every
  # side. The panel's background is light grey (ink mixed 92% toward paper) with no border, and its
  # grid lines are paper white, the major ones as wide as a line and the minor ones half that. An
  # axis's ticks are dark grey (ink mixed 20% toward paper), `half_line / 2` long and as wide
  # as a line; its labels are grey (30.2% toward paper), 0.8 of the base size, `0.8 * half_line / 2`
  # from the ticks; its title is black at the base size, `half_line / 2` from the labels. Panels are
  # `half_line` apart (ggplot2's `spacing`, which `panel.spacing` takes). A strip is light grey (85%
  # toward paper) with no border, and its text near black (10% toward paper), 0.8 of the base size,
  # with `0.8 * half_line` around it on every side.
  defp gray do
    %__MODULE__{
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
      },
      panel_spacing: @half_line * @points_per_theme_point,
      strip_background: %{
        fill: @ink_toward_paper_85,
        color: :none,
        line_width: @base_rect_size * @points_per_millimetre_of_line
      },
      strip_text: %{
        size: 0.8 * @base_size,
        color: @ink_toward_paper_10,
        margin: 0.8 * @half_line * @points_per_theme_point
      }
    }
  end
end
