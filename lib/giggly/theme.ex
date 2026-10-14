defmodule Giggly.Theme do
  @moduledoc false

  # Themes: the look a plot is drawn in, apart from its data. In ggplot2 a theme gives every part of
  # a plot that is not a mark its colours, sizes, line widths and spacing: the background, the axes
  # and their titles.
  #
  # A plot records its theme by name, and the name is resolved here into the complete theme, every
  # element it draws already worked out (ggplot2's `complete_theme()`): each length in points (1/72
  # inch), each colour as a hex string. Each theme is a module implementing this behaviour. There is
  # one so far, ggplot2's default, `theme_gray()` (`Giggly.Theme.Gray`), and nothing can change it
  # yet; the elements a user sets, and how an element inherits what it leaves unset from its parent,
  # arrive with the first theme setting a user can make.
  #
  # When a plot is rendered, every function that draws something other than a mark takes the
  # complete theme and reads the elements it draws. A theme holds sizes, colours, line widths and
  # spacing; how text is aligned and turned is the drawing's until a theme can set it.

  # A theme is values: it calls nothing, and the complete theme is this module's struct, which a
  # boundary listing this one reads.
  use Boundary, deps: [], exports: []

  alias Giggly.Theme

  @enforce_keys [
    :plot_background,
    :plot_margin,
    :panel_background,
    :panel_grid_major,
    :panel_grid_minor,
    :axis_ticks,
    :axis_ticks_length,
    :axis_text,
    :axis_title
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
  axis's ticks, their length in points, its labels and its title.
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
          axis_title: text()
        }

  # The complete theme.
  @doc false
  @callback complete() :: t()

  # The complete theme named `name`: every element it draws, worked out.
  @doc false
  @spec complete(name()) :: t()
  def complete(:gray), do: Theme.Gray.complete()
end
