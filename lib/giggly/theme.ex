defmodule Giggly.Theme do
  @moduledoc false

  # Themes: the look a plot is drawn in, apart from its data. In ggplot2 a theme gives every part of
  # a plot that is not a mark its colours, sizes, line widths and spacing: the background, the axes
  # and their titles, the strips, the legends.
  #
  # A theme is a tree of elements, as ggplot2's is (`.element_tree`, in its `theme-elements.R`):
  # each element is a line, a rectangle or a text, or a length or a margin, and each but the roots
  # names the element it inherits from, `axis_text_x_bottom` from `axis_text_x`, that from
  # `axis_text`, that from `text`. An element holds only the properties it sets; one it leaves out,
  # or an element left out altogether, is its parent's, worked out when the plot is drawn, as
  # ggplot2's `calc_element()` works it out: a size or a line width given as `{:rel, share}` is that
  # share of the parent's, and a length or a margin given so is that share of its parent's.
  # `elements/0` lists the tree as far as Giggly draws it: what something draws, and what that
  # inherits from.
  #
  # A plot records its theme as the complete theme it chose, by name with its base sizes, or
  # `:none` for none, and the settings `Giggly.Plot.theme/2` has merged into it (`plot_theme`).
  # `merge/2` merges settings as ggplot2 adds a `theme()` to a plot's (`add_theme()`): a line's, a
  # rectangle's or a text's properties replace only the properties they give, and a length or a
  # margin replaces the one before. Each complete theme is a function here that builds its
  # elements from its base sizes, as ggplot2's are functions (`theme_gray()`); themes differ only
  # in their values, so none is a module implementing a behaviour, as each facet and coordinate
  # system is. They are ggplot2's eight: `gray/1`, its default; `bw/1`, `light/1` and `dark/1`,
  # built from it by replacing some of its elements whole, as ggplot2's `%+replace%` replaces
  # them; `linedraw/1`, `minimal/1` and `classic/1`, built from `bw/1` so; and `void/1`, a tree of
  # its own. `complete/1` lays the plot's settings over its complete theme, as ggplot2 completes a
  # plot's theme when it builds the plot (`plot_theme()`), and works out every element something
  # draws, each length and line width in points (1/72 inch) and each colour a hex string and its
  # opacity apart, so nothing that reads the complete theme converts anything.
  #
  # The settings are laid over a plot's complete theme as ggplot2 lays them. A plot that chose none
  # merges its settings among themselves and lays them over `gray/1` at its default sizes as one,
  # as ggplot2 adds a plot's theme to its default theme. A plot that chose one has each setting laid
  # over it in turn, so a setting given after a removal of the same element replaces the complete
  # theme's element whole, which the settings record as `{:replace, element}`: ggplot2's
  # `add_theme()` lays the removal over the complete theme's element, and the setting over the
  # removal, which it replaces. Settings given before a complete theme are dropped with the theme
  # they were laid over, as ggplot2's are.
  #
  # A length is held as an amount in a unit, as grid holds one: ggplot2's points (`:pt`, TeX's,
  # 1/72.27 inch), `:cm`, `:mm`, `:in`, or `:lines`, grid's lines of text at its own defaults, a
  # 12-point font at a line height of 1.2, as grid works out ggplot2's `unit(1.2, "lines")`; and
  # converted into points only once worked out, so a share of one is taken in its own unit, as grid
  # takes it. A line width is in millimetres, as ggplot2 gives it, and a text's size in points.
  #
  # A line or a rectangle's border is drawn in its line type, held as its dash pattern, as a
  # layer's is, and worked out into its dashes in points as svglite writes them, each length of the
  # pattern times the line's width in R's line-width units, or 1 where it is narrower. A line of
  # the blank line type draws nothing but keeps its room, as R's graphics engine draws none, and a
  # rectangle's border of it is no border. A line's end is as its element gives it; a rectangle's
  # fill may be `:none`, ggplot2's `NA`. A colour may have an alpha of its own, as `theme_void()`'s
  # transparent paper has, worked out as the opacity it is drawn at.
  #
  # A line, a rectangle or a text set to `:none` is removed, ggplot2's `element_blank()`: it draws
  # nothing and takes no room, and works out as `:none` in the complete theme. ggplot2's rule for
  # what inherits a removal, which `calc_element()` holds, holds here: a complete theme's elements
  # take a removed parent's removal (ggplot2's `inherit.blank`, which a complete theme sets on every
  # element), so a removed parent takes them with it; an element a setting gives skips every removed
  # element above it and inherits from the next one up, as a `theme()`'s elements do. A setting
  # given after a removal replaces it, as ggplot2's `merge_element()` drops a blank. A root
  # (`line`, `rect`, `text`) whose element leaves a property unset, as one a setting replaces whole
  # may, takes it from `theme_gray()`'s at its default sizes, whatever the complete theme, as
  # ggplot2 fills a root from its default theme; but a removed root that an element skips gives
  # it nothing, so a property nothing above gives falls to grid's own default, as R draws it:
  # black, a white fill, a solid line 1/96 inch wide with round ends, text 12 points with its lines
  # 1.2 apart and no margin. A share of a property its parent leaves unset is nothing too, and one
  # with nothing above it to be a share of is the share itself, in points or millimetres, as R's
  # graphics engine takes it; a share inherited from a parent whose own is still a share is taken of
  # it again, as ggplot2's `combine_elements()` fills a property and then works out its share.
  #
  # When a plot is rendered, every function that draws something other than a mark takes the
  # complete theme and reads the elements it draws. A theme holds sizes, colours, line widths, line
  # types and ends, and spacing, and whether the panel's background and grid are drawn over its
  # layers; how text is aligned and turned is the drawing's until a theme can set it.

  # A theme is values: it calls nothing, and the complete theme is this module's struct, which a
  # boundary listing this one reads.
  use Boundary, deps: [], exports: []

  @enforce_keys [
    :plot_background,
    :plot_margin,
    :panel_background,
    :panel_grid_major_x,
    :panel_grid_major_y,
    :panel_grid_minor_x,
    :panel_grid_minor_y,
    :panel_border,
    :panel_ontop,
    :axis_ticks_x_bottom,
    :axis_ticks_y_left,
    :axis_ticks_theta,
    :axis_ticks_r,
    :axis_ticks_length_x_bottom,
    :axis_ticks_length_y_left,
    :axis_ticks_length_theta,
    :axis_ticks_length_r,
    :axis_line_x_bottom,
    :axis_line_y_left,
    :axis_line_theta,
    :axis_line_r,
    :axis_text_x_bottom,
    :axis_text_y_left,
    :axis_text_theta,
    :axis_text_r,
    :axis_title_x_bottom,
    :axis_title_y_left,
    :panel_spacing_x,
    :panel_spacing_y,
    :strip_background_x,
    :strip_text_x_top,
    :legend_background,
    :legend_margin,
    :legend_key,
    :legend_key_width,
    :legend_key_height,
    :legend_title,
    :legend_text,
    :legend_ticks,
    :legend_ticks_length,
    :legend_spacing_y,
    :legend_box_spacing,
    :legend_position,
    :plot_title,
    :plot_subtitle,
    :plot_caption,
    :plot_tag
  ]
  defstruct @enforce_keys

  @typedoc "A complete theme's name, as a plot records it."
  @type name :: :gray | :bw | :linedraw | :light | :dark | :minimal | :classic | :void

  @typedoc """
  A complete theme a plot chose: its name and its base sizes, its text's size in points and its
  lines' and borders' widths in millimetres.
  """
  @type chosen :: %{
          name: name(),
          base_size: float(),
          base_line_size: float(),
          base_rect_size: float()
        }

  @typedoc """
  A unit a length is given in: ggplot2's points (`:pt`, 1/72.27 inch), centimetres, millimetres,
  inches, or grid's lines of text.
  """
  @type unit :: :pt | :cm | :mm | :in | :lines

  @typedoc "A length as a setting gives it: an amount in a unit, or a share of its parent's."
  @type measure :: {number(), unit()} | {:rel, number()}

  @typedoc "Space on each side of something, each side a length."
  @type sides :: %{top: measure(), right: measure(), bottom: measure(), left: measure()}

  @typedoc """
  An element as a setting gives it: a line's, a rectangle's or a text's properties, those left out
  inherited; a length; or a margin, its sides or a share of its parent's.
  """
  @type element :: %{optional(atom()) => term()} | measure() | sides() | {:rel, number()}

  @typedoc """
  Settings by element, as `Giggly.Plot.theme/2` merges them: each an element, or one that
  replaces the complete theme's element whole, `{:replace, element}`.
  """
  @type settings :: %{optional(atom()) => element() | {:replace, element()}}

  @typedoc """
  A plot's theme: the complete theme it chose, `:none` for none, which draws it in `theme_gray()`
  at its default sizes, and the settings laid over it.
  """
  @type plot_theme :: %{complete: chosen() | :none, settings: settings()}

  @typedoc """
  What kind of value an element is; a position says where something goes, and a boolean whether
  something is done.
  """
  @type kind :: :line | :rect | :text | :length | :margin | :position | :boolean

  @typedoc """
  How a line or a border is dashed: `:none` for a solid one, or the lengths in points of its
  dashes and of the gaps between them, in turn.
  """
  @type dashes :: :none | [float()]

  @typedoc """
  A rectangle's look: its `fill`, an `#RRGGBB` or `:none` for none (ggplot2's `NA`), drawn at
  `fill_opacity`, from 0 to 1, the `color` of its border, an `#RRGGBB` or `:none` for no border,
  drawn at `color_opacity`, the border's `line_width`, in points, and its `dashes`; or `:none`,
  removed.
  """
  @type rect ::
          %{
            fill: String.t() | :none,
            fill_opacity: float(),
            color: String.t() | :none,
            color_opacity: float(),
            line_width: float(),
            dashes: dashes()
          }
          | :none

  @typedoc """
  A line's `color`, an `#RRGGBB` drawn at `opacity`, from 0 to 1, its `line_width`, in points, how
  its ends are drawn, `line_end`, and its `dashes`, `:blank` for a line of the blank line type,
  which draws nothing but keeps its room; or `:none`, removed.
  """
  @type line ::
          %{
            color: String.t(),
            opacity: float(),
            line_width: float(),
            line_end: :butt | :round | :square,
            dashes: dashes() | :blank
          }
          | :none

  @typedoc "Space on each side of something, in points."
  @type margin :: %{top: float(), right: float(), bottom: float(), left: float()}

  @typedoc """
  Text's `size`, its `color`, an `#RRGGBB` drawn at `opacity`, from 0 to 1, and its `margin`: the
  space in points on each side of it, of which the drawing counts the sides ggplot2 counts; or
  `:none`, removed.
  """
  @type text ::
          %{size: float(), color: String.t(), opacity: float(), margin: margin()} | :none

  @typedoc """
  A title's text, which may run over several lines: its `size`, `color`, `opacity` and `margin`,
  as text's, and its `line_spacing`, the distance in points from one line's baseline to the
  next's; or `:none`, removed.
  """
  @type title ::
          %{
            size: float(),
            color: String.t(),
            opacity: float(),
            margin: margin(),
            line_spacing: float()
          }
          | :none

  @typedoc """
  A complete theme: the plot's background, drawn over the whole drawing, and the margin around
  what is drawn on it; the panel's background and its major and minor grid lines, by the axis
  whose breaks they mark, the panel's border, and whether the background and grid are drawn over
  the layers; each axis's ticks, their length, its line, its labels and its title, by axis and
  side, a radial panel's angle axis (`theta`) and radius axis (`r`) apart; the space between
  panels across and down; the background and text of the strips above each panel; and a legend's
  background, the margin inside it, each key's background, width and height, the title, the
  labels, a colour bar's ticks and how far each reaches into the bar, the space between one
  legend and the next below it, the space between the panels and the legends, and where the
  legends go, `:right` or `:none` for no legends; and the plot's title, subtitle, caption and tag.
  Every length is in points; a line, a rectangle or a text the theme removes is `:none`.
  """
  @type t :: %__MODULE__{
          plot_background: rect(),
          plot_margin: margin(),
          panel_background: rect(),
          panel_grid_major_x: line(),
          panel_grid_major_y: line(),
          panel_grid_minor_x: line(),
          panel_grid_minor_y: line(),
          panel_border: rect(),
          panel_ontop: boolean(),
          axis_ticks_x_bottom: line(),
          axis_ticks_y_left: line(),
          axis_ticks_theta: line(),
          axis_ticks_r: line(),
          axis_ticks_length_x_bottom: float(),
          axis_ticks_length_y_left: float(),
          axis_ticks_length_theta: float(),
          axis_ticks_length_r: float(),
          axis_line_x_bottom: line(),
          axis_line_y_left: line(),
          axis_line_theta: line(),
          axis_line_r: line(),
          axis_text_x_bottom: text(),
          axis_text_y_left: text(),
          axis_text_theta: text(),
          axis_text_r: text(),
          axis_title_x_bottom: title(),
          axis_title_y_left: title(),
          panel_spacing_x: float(),
          panel_spacing_y: float(),
          strip_background_x: rect(),
          strip_text_x_top: text(),
          legend_background: rect(),
          legend_margin: margin(),
          legend_key: rect(),
          legend_key_width: float(),
          legend_key_height: float(),
          legend_title: title(),
          legend_text: text(),
          legend_ticks: line(),
          legend_ticks_length: float(),
          legend_spacing_y: float(),
          legend_box_spacing: float(),
          legend_position: :right | :none,
          plot_title: title(),
          plot_subtitle: title(),
          plot_caption: title(),
          plot_tag: title()
        }

  # ggplot2's element tree, as far as Giggly draws: each element, its kind, the element it inherits
  # what it leaves unset from (`:none` for a root), and what it styles, in ggplot2's order.
  @elements [
    {:line, :line, :none, "Every line."},
    {:rect, :rect, :none, "Every rectangle: backgrounds and borders."},
    {:text, :text, :none, "Every text."},
    {:title, :text, :text, "Every title: the axes', the legends' and the plot's."},
    {:spacing, :length, :none, "Every spacing between parts of the plot."},
    {:margins, :margin, :none, "Every margin inside a part of the plot."},
    {:axis_line, :line, :line, "The axes' lines, along the panels' edges."},
    {:axis_text, :text, :text, "The axes' tick labels."},
    {:axis_ticks, :line, :line, "The axes' ticks."},
    {:axis_title, :text, :title, "The axes' titles."},
    {:axis_line_x, :line, :axis_line, "The x axis's line."},
    {:axis_line_x_bottom, :line, :axis_line_x, "The line of the x axis below the panels."},
    {:axis_line_y, :line, :axis_line, "The y axis's line."},
    {:axis_line_y_left, :line, :axis_line_y, "The line of the y axis left of the panels."},
    {:axis_line_theta, :line, :axis_line_x, "The line round a radial panel's circle."},
    {:axis_line_r, :line, :axis_line_y, "The line of a radial panel's radius axis."},
    {:axis_text_x, :text, :axis_text, "The x axis's tick labels."},
    {:axis_text_x_bottom, :text, :axis_text_x, "The tick labels of the x axis below the panels."},
    {:axis_text_y, :text, :axis_text, "The y axis's tick labels."},
    {:axis_text_y_left, :text, :axis_text_y, "The tick labels of the y axis left of the panels."},
    {:axis_text_theta, :text, :axis_text_x, "The tick labels round a radial panel."},
    {:axis_text_r, :text, :axis_text_y, "The tick labels of a radial panel's radius axis."},
    {:axis_ticks_length, :length, :spacing, "How long the axes' ticks are."},
    {:axis_ticks_length_x, :length, :axis_ticks_length, "How long the x axis's ticks are."},
    {:axis_ticks_length_x_bottom, :length, :axis_ticks_length_x,
     "How long the ticks of the x axis below the panels are."},
    {:axis_ticks_length_y, :length, :axis_ticks_length, "How long the y axis's ticks are."},
    {:axis_ticks_length_y_left, :length, :axis_ticks_length_y,
     "How long the ticks of the y axis left of the panels are."},
    {:axis_ticks_length_theta, :length, :axis_ticks_length_x,
     "How long the ticks round a radial panel are."},
    {:axis_ticks_length_r, :length, :axis_ticks_length_y,
     "How long the ticks of a radial panel's radius axis are."},
    {:axis_ticks_x, :line, :axis_ticks, "The x axis's ticks."},
    {:axis_ticks_x_bottom, :line, :axis_ticks_x, "The ticks of the x axis below the panels."},
    {:axis_ticks_y, :line, :axis_ticks, "The y axis's ticks."},
    {:axis_ticks_y_left, :line, :axis_ticks_y, "The ticks of the y axis left of the panels."},
    {:axis_ticks_theta, :line, :axis_ticks_x, "The ticks round a radial panel."},
    {:axis_ticks_r, :line, :axis_ticks_y, "The ticks of a radial panel's radius axis."},
    {:axis_title_x, :text, :axis_title, "The x axis's title."},
    {:axis_title_x_bottom, :text, :axis_title_x, "The title of the x axis below the panels."},
    {:axis_title_y, :text, :axis_title, "The y axis's title."},
    {:axis_title_y_left, :text, :axis_title_y, "The title of the y axis left of the panels."},
    {:legend_background, :rect, :rect, "Each legend's background."},
    {:legend_margin, :margin, :margins, "The margin inside each legend's edge."},
    {:legend_spacing, :length, :spacing, "The space between legends."},
    {:legend_spacing_y, :length, :legend_spacing,
     "The space between a legend and the next below it."},
    {:legend_key, :rect, :panel_background, "The background of each legend key."},
    {:legend_key_size, :length, :spacing, "How big each legend key is."},
    {:legend_key_height, :length, :legend_key_size, "How tall each legend key is."},
    {:legend_key_width, :length, :legend_key_size, "How wide each legend key is."},
    {:legend_key_spacing, :length, :spacing,
     "The space between a legend's keys and its labels, and below its title."},
    {:legend_axis_line, :line, :line, "The line along a legend's axis."},
    {:legend_ticks, :line, :legend_axis_line, "A colour bar's ticks."},
    {:legend_ticks_length, :length, :legend_key_size,
     "How far a colour bar's ticks reach into it."},
    {:legend_text, :text, :text, "The legends' labels."},
    {:legend_title, :text, :title, "The legends' titles."},
    {:legend_position, :position, :none,
     "Where the legends go: `:right`, beside the panels, or `:none`, for no legends."},
    {:legend_box_spacing, :length, :spacing, "The space between the panels and the legends."},
    {:panel_background, :rect, :rect, "The panels' background, under the layers."},
    {:panel_border, :rect, :rect, "The panels' border, drawn over the layers and never filled."},
    {:panel_spacing, :length, :spacing, "The space between panels."},
    {:panel_spacing_x, :length, :panel_spacing, "The space between panels side by side."},
    {:panel_spacing_y, :length, :panel_spacing, "The space between panels one above another."},
    {:panel_grid, :line, :line, "The panels' grid lines."},
    {:panel_grid_major, :line, :panel_grid, "The grid lines at the axes' breaks."},
    {:panel_grid_minor, :line, :panel_grid, "The grid lines between the axes' breaks."},
    {:panel_grid_major_x, :line, :panel_grid_major, "The grid lines at the x axis's breaks."},
    {:panel_grid_major_y, :line, :panel_grid_major, "The grid lines at the y axis's breaks."},
    {:panel_grid_minor_x, :line, :panel_grid_minor,
     "The grid lines between the x axis's breaks."},
    {:panel_grid_minor_y, :line, :panel_grid_minor,
     "The grid lines between the y axis's breaks."},
    {:panel_ontop, :boolean, :none,
     "Whether the panels' background and grid lines are drawn over the layers, `true`, or " <>
       "under them, `false`."},
    {:strip_background, :rect, :rect, "The strips' background."},
    {:strip_background_x, :rect, :strip_background, "The background of the strips above panels."},
    {:strip_text, :text, :text, "The strips' labels."},
    {:strip_text_x, :text, :strip_text, "The labels of the strips above or below panels."},
    {:strip_text_x_top, :text, :strip_text_x, "The labels of the strips above panels."},
    {:plot_background, :rect, :rect, "The background of the whole plot."},
    {:plot_margin, :margin, :margins, "The margin round the whole plot."},
    {:plot_title, :text, :title, "The plot's title."},
    {:plot_subtitle, :text, :text, "The plot's subtitle."},
    {:plot_caption, :text, :text, "The plot's caption."},
    {:plot_tag, :text, :text, "The plot's tag."}
  ]

  @kinds Map.new(@elements, fn {name, kind, _parent, _description} -> {name, kind} end)
  @parents Map.new(@elements, fn {name, _kind, parent, _description} -> {name, parent} end)

  # The elements that are a line, a rectangle or a text, which a setting may remove.
  @drawn_kinds for {name, kind, _parent, _description} <- @elements,
                   kind in [:line, :rect, :text],
                   into: %{},
                   do: {name, kind}

  # grid's own defaults, which a property nothing in the theme gives falls to, as R draws it: black,
  # a white fill, a line 1/96 inch wide, which svglite writes in points, with round ends, and a
  # 12-point font with its lines 1.2 apart, which also make grid's line of text.
  @grid_color "#000000"
  @grid_fill "#FFFFFF"
  @grid_line_width 72 / 96
  @grid_line_end :round
  @grid_font_size 12
  @grid_line_height 1.2

  # ggplot2's line widths are millimetres, which grid draws as `.pt` line-width units each, and a
  # line-width unit is 1/96 inch, which svglite writes in points.
  @font_points_per_millimetre 72.27 / 25.4

  # R's graphics engine spaces lines of text 1.2 font sizes apart, times a text's `lineheight`.
  @line_spacing_per_size 1.2

  # The margin of no space at all, ggplot2's `margin()`.
  @no_margin %{top: {0, :pt}, right: {0, :pt}, bottom: {0, :pt}, left: {0, :pt}}

  # The complete themes, by name.
  @names [:gray, :bw, :linedraw, :light, :dark, :minimal, :classic, :void]

  # A complete theme's sizes unless a plot gives others, as ggplot2's take them: an 11-point base
  # size, and lines and borders `base_size / 22` millimetres wide.
  @default_base_size 11.0
  @default_sizes %{
    base_size: @default_base_size,
    base_line_size: @default_base_size / 22,
    base_rect_size: @default_base_size / 22
  }

  # Every complete theme's ink and paper, black on white, and `theme_void()`'s paper, its ink with
  # no alpha (`alpha(ink, 0)`).
  @ink "#000000"
  @paper "#FFFFFF"
  @clear_paper "#00000000"

  # `col_mix(ink, paper, amount)` for black ink on white paper, as ggplot2 rounds it, each named
  # for its amount as a percentage.
  @ink_toward_paper_10 "#1A1A1A"
  @ink_toward_paper_15 "#262626"
  @ink_toward_paper_20 "#333333"
  @ink_toward_paper_30_2 "#4D4D4D"
  @ink_toward_paper_42 "#6B6B6B"
  @ink_toward_paper_49_9 "#7F7F7F"
  @ink_toward_paper_70_2 "#B3B3B3"
  @ink_toward_paper_85 "#D9D9D9"
  @ink_toward_paper_85_1 "#D9D9D9"
  @ink_toward_paper_87_1 "#DEDEDE"
  @ink_toward_paper_89_9 "#E5E5E5"
  @ink_toward_paper_92 "#EBEBEB"

  # A colour bar's ticks when the theme sets none: `guide_colourbar()`'s own default, white and
  # 0.5 / .pt millimetres wide, made as a setting is, so it skips a removed `line`.
  @colorbar_ticks %{
    color: @paper,
    linewidth: 0.5 / @font_points_per_millimetre,
    inherit_blank: false
  }

  # The elements a setting may give, each its name, kind, the element it inherits from (`:none`
  # for a root) and what it styles, in ggplot2's order, for `Giggly.Plot.theme/2` to check its
  # settings against and document.
  @doc false
  @spec elements() :: [{atom(), kind(), atom(), String.t()}]
  def elements, do: @elements

  # A plot's theme with the complete theme `name` chosen, at the sizes `sizes` gives, its text's
  # in points and its lines' and borders' in millimetres, and any it leaves out ggplot2's
  # defaults: 11 points, and `base_size / 22` for each width. Its settings are none, as ggplot2
  # drops a plot's earlier settings with the theme a complete theme replaces.
  @doc false
  @spec choose(name(), keyword()) :: plot_theme()
  def choose(name, sizes) when name in @names do
    base_size = Keyword.get(sizes, :base_size, @default_base_size) / 1

    chosen = %{
      name: name,
      base_size: base_size,
      base_line_size: Keyword.get(sizes, :base_line_size, base_size / 22) / 1,
      base_rect_size: Keyword.get(sizes, :base_rect_size, base_size / 22) / 1
    }

    %{complete: chosen, settings: %{}}
  end

  # `plot_theme` with the settings `new` merged into its own, as ggplot2 adds a `theme()` to a
  # plot's (`add_theme()`): a line's, a rectangle's or a text's properties replace only the
  # properties they give, and anything else replaces the element before: a length, a margin, a
  # position, a removal (`:none`), and an element given after a removal, as ggplot2's
  # `merge_element()` drops a blank. Under a complete theme the plot chose, an element given after
  # a removal replaces the complete theme's element whole, `{:replace, element}`, since ggplot2
  # has laid the removal over it; the properties given after that replace only their own.
  @doc false
  @spec merge(plot_theme(), settings()) :: plot_theme()
  def merge(%{complete: complete, settings: settings} = plot_theme, new) do
    merged =
      Map.merge(settings, new, fn name, old_element, new_element ->
        merged_element(complete, Map.fetch!(@kinds, name), old_element, new_element)
      end)

    %{plot_theme | settings: merged}
  end

  defp merged_element(complete, kind, :none, new)
       when complete != :none and kind in [:line, :rect, :text] and is_map(new),
       do: {:replace, new}

  defp merged_element(_complete, kind, {:replace, old}, new)
       when kind in [:line, :rect, :text] and is_map(new),
       do: {:replace, Map.merge(old, new)}

  defp merged_element(_complete, kind, old, new)
       when kind in [:line, :rect, :text] and is_map(old) and is_map(new),
       do: Map.merge(old, new)

  defp merged_element(_complete, _kind, _old, new), do: new

  # The complete theme `plot_theme` draws in: its settings laid over its complete theme, and every
  # element something draws worked out. A setting's line, rectangle or text is marked to skip a
  # removed element above it (`inherit_blank: false`, ggplot2's `inherit.blank` as a `theme()`
  # sets it); the complete theme's are not, so they take a removed parent's removal.
  @doc false
  @spec complete(plot_theme()) :: t()
  def complete(%{complete: complete, settings: settings}) do
    marked =
      Map.new(settings, fn
        {name, {:replace, element}} ->
          {name, {:replace, Map.put(element, :inherit_blank, false)}}

        {name, element} when is_map(element) and is_map_key(@drawn_kinds, name) ->
          {name, Map.put(element, :inherit_blank, false)}

        setting ->
          setting
      end)

    complete
    |> tree()
    |> lay_over(marked)
    |> worked_out()
  end

  # The elements of the complete theme a plot chose, at its sizes, or of theme_gray() at its
  # default sizes for a plot that chose none.
  defp tree(:none), do: gray(@default_sizes)
  defp tree(%{name: :gray} = sizes), do: gray(sizes)
  defp tree(%{name: :bw} = sizes), do: bw(sizes)
  defp tree(%{name: :linedraw} = sizes), do: linedraw(sizes)
  defp tree(%{name: :light} = sizes), do: light(sizes)
  defp tree(%{name: :dark} = sizes), do: dark(sizes)
  defp tree(%{name: :minimal} = sizes), do: minimal(sizes)
  defp tree(%{name: :classic} = sizes), do: classic(sizes)
  defp tree(%{name: :void} = sizes), do: void(sizes)

  # `elements` with `settings` laid over them, as ggplot2's `add_theme()` lays a `theme()` over a
  # complete theme: a line's, a rectangle's or a text's properties replace only the properties
  # they give, one that replaces an element replaces it whole, and anything else replaces the
  # element before.
  defp lay_over(elements, settings) do
    Map.merge(elements, settings, fn name, old_element, new_element ->
      case {Map.fetch!(@kinds, name), new_element} do
        {_kind, {:replace, element}} ->
          element

        {kind, element}
        when kind in [:line, :rect, :text] and is_map(old_element) and is_map(element) ->
          Map.merge(old_element, element)

        {_kind, element} ->
          element
      end
    end)
  end

  # Every element something draws, worked out from `theme`'s elements as ggplot2's
  # `calc_element()` works each out, each length in points and each line width in points.
  defp worked_out(theme) do
    gap = distance(theme, :legend_key_spacing)
    text_margin = text_margin(calculated(theme, :text))
    legend_title_theme = beside_keys(theme, text_margin, :bottom, gap)
    legend_text_theme = beside_keys(theme, text_margin, :left, gap)
    legend_ticks_theme = Map.put_new(theme, :legend_ticks, @colorbar_ticks)

    %__MODULE__{
      plot_background: rect(theme, :plot_background),
      plot_margin: margin(theme, :plot_margin),
      panel_background: rect(theme, :panel_background),
      panel_grid_major_x: line(theme, :panel_grid_major_x),
      panel_grid_major_y: line(theme, :panel_grid_major_y),
      panel_grid_minor_x: line(theme, :panel_grid_minor_x),
      panel_grid_minor_y: line(theme, :panel_grid_minor_y),
      panel_border: rect(theme, :panel_border),
      panel_ontop: calculated(theme, :panel_ontop),
      axis_ticks_x_bottom: line(theme, :axis_ticks_x_bottom),
      axis_ticks_y_left: line(theme, :axis_ticks_y_left),
      axis_ticks_theta: line(theme, :axis_ticks_theta),
      axis_ticks_r: line(theme, :axis_ticks_r),
      axis_ticks_length_x_bottom: distance(theme, :axis_ticks_length_x_bottom),
      axis_ticks_length_y_left: distance(theme, :axis_ticks_length_y_left),
      axis_ticks_length_theta: distance(theme, :axis_ticks_length_theta),
      axis_ticks_length_r: distance(theme, :axis_ticks_length_r),
      axis_line_x_bottom: line(theme, :axis_line_x_bottom),
      axis_line_y_left: line(theme, :axis_line_y_left),
      axis_line_theta: line(theme, :axis_line_theta),
      axis_line_r: line(theme, :axis_line_r),
      axis_text_x_bottom: text(theme, :axis_text_x_bottom),
      axis_text_y_left: text(theme, :axis_text_y_left),
      axis_text_theta: text(theme, :axis_text_theta),
      axis_text_r: text(theme, :axis_text_r),
      axis_title_x_bottom: title(theme, :axis_title_x_bottom),
      axis_title_y_left: title(theme, :axis_title_y_left),
      panel_spacing_x: distance(theme, :panel_spacing_x),
      panel_spacing_y: distance(theme, :panel_spacing_y),
      strip_background_x: rect(theme, :strip_background_x),
      strip_text_x_top: text(theme, :strip_text_x_top),
      legend_background: rect(theme, :legend_background),
      legend_margin: margin(theme, :legend_margin),
      legend_key: rect(theme, :legend_key),
      legend_key_width: distance(theme, :legend_key_width),
      legend_key_height: distance(theme, :legend_key_height),
      legend_title: title(legend_title_theme, :legend_title),
      legend_text: text(legend_text_theme, :legend_text),
      legend_ticks: line(legend_ticks_theme, :legend_ticks),
      legend_ticks_length: distance(theme, :legend_ticks_length),
      legend_spacing_y: distance(theme, :legend_spacing_y),
      legend_box_spacing: distance(theme, :legend_box_spacing),
      legend_position: calculated(theme, :legend_position),
      plot_title: title(theme, :plot_title),
      plot_subtitle: title(theme, :plot_subtitle),
      plot_caption: title(theme, :plot_caption),
      plot_tag: title(theme, :plot_tag)
    }
  end

  # The root text's margin, which a legend widens beside its keys: none for a removed root text, as
  # ggplot2's legend takes a blank's margin as `margin()`.
  defp text_margin(:none), do: @no_margin
  defp text_margin(text), do: text.margin

  # `theme` with its root text's margin widened by `gap` on `side`, the side facing a legend's keys,
  # as ggplot2's legend lays a text element over the theme to give its title and labels their
  # default margins, which a margin the title's or the labels' own element sets replaces. Laid over
  # a removed root text, it replaces the removal, and the root takes the rest from theme_gray()'s,
  # so a legend's title and labels are drawn where every other text is removed, as ggplot2's are.
  defp beside_keys(theme, margin, side, gap) do
    widened = Map.update!(margin, side, fn length -> {points(length) + gap, :points} end)
    lay_over(theme, %{text: %{margin: widened}})
  end

  # The element `name` of `theme` worked out: what it sets, and what it leaves unset taken from
  # the element it inherits from, worked out in turn, as ggplot2's `calc_element()` works it out;
  # `:none` for one removed, or one that takes a removed parent's removal. From an element a
  # setting gives up, `skip_removed`, every removed element is passed over as though unset, and a
  # removed root passed over gives nothing, `nil`.
  defp calculated(theme, name, skip_removed \\ false) do
    element =
      case Map.get(theme, name) do
        :none when skip_removed -> nil
        element -> element
      end

    case {element, Map.fetch!(@parents, name)} do
      {:none, _parent} ->
        :none

      {element, :none} ->
        root(name, element)

      {element, parent} ->
        skips = skip_removed or skips_removed?(element)
        inherit(Map.fetch!(@kinds, name), element, calculated(theme, parent, skips))
    end
  end

  # A root as its element gives it, a property a line, a rectangle or a text leaves unset taken
  # from theme_gray()'s at its default sizes, as ggplot2 fills a root from its default theme;
  # nothing for a removed root passed over.
  defp root(_name, nil), do: nil

  defp root(name, element) when is_map_key(@drawn_kinds, name) do
    @default_sizes
    |> gray()
    |> Map.fetch!(name)
    |> Map.merge(element)
  end

  defp root(_name, element), do: element

  # Whether an element skips a removed element above it: one a setting gives does.
  defp skips_removed?(%{inherit_blank: false}), do: true
  defp skips_removed?(_element), do: false

  # An element given nothing takes its parent's whole, and one that takes a removed parent's
  # removal is removed; a share of a length or a margin is that share of its parent's, in the
  # parent's unit; a line's, a rectangle's or a text's properties take what they leave unset from
  # the parent's, and a size or a line width given as a share is worked out against the parent's,
  # as ggplot2's `combine_elements()` combines them. Under a removed root passed over, an element
  # is as it is.
  defp inherit(_kind, nil, parent), do: parent
  defp inherit(_kind, _element, :none), do: :none
  defp inherit(_kind, element, nil), do: element

  defp inherit(:length, {:rel, share}, {amount, unit}), do: {share * amount, unit}

  defp inherit(:margin, {:rel, share}, parent) do
    Map.new(parent, fn {side, {amount, unit}} -> {side, {share * amount, unit}} end)
  end

  defp inherit(kind, element, _parent) when kind in [:length, :margin], do: element

  defp inherit(_kind, element, parent) do
    parent
    |> Map.merge(element)
    |> relative(:size, parent)
    |> relative(:linewidth, parent)
  end

  # A share of a size or a line width, once the element has taken what it leaves unset, worked out
  # against the parent's: that share of the parent's amount; a share of a share where the parent's
  # is still one, so one inherited from such a parent is taken of it again; and nothing where the
  # parent leaves it unset, as ggplot2's `combine_elements()` multiplies them.
  defp relative(element, property, parent) do
    case {element, parent} do
      {%{^property => {:rel, share}}, %{^property => {:rel, parent_share}}} ->
        %{element | property => {:rel, parent_share * share}}

      {%{^property => {:rel, share}}, %{^property => amount}} ->
        %{element | property => amount * share}

      {%{^property => {:rel, _share}}, %{}} ->
        Map.delete(element, property)

      {%{}, %{}} ->
        element
    end
  end

  # A length in points, worked out as grid works it out, through inches in grid's order of
  # operations: TeX's points over 72.27, centimetres over 2.54, millimetres over 10 and then 2.54,
  # and lines of text as that many font sizes times the line height over 72; then times 72. A sum
  # already in points is as it is.
  defp points({amount, :points}), do: amount
  defp points({amount, :pt}), do: amount / 72.27 * 72
  defp points({amount, :cm}), do: amount / 2.54 * 72
  defp points({amount, :mm}), do: amount / 10 / 2.54 * 72
  defp points({amount, :in}), do: amount * 72.0

  defp points({amount, :lines}),
    do: amount * @grid_font_size * @grid_line_height / 72 * 72

  # Each kind of element `name` of `theme` worked out, in the scene's units.
  defp distance(theme, name) do
    theme
    |> calculated(name)
    |> points()
  end

  defp margin(theme, name) do
    theme
    |> calculated(name)
    |> margin_points()
  end

  defp margin_points(sides), do: Map.new(sides, fn {side, length} -> {side, points(length)} end)

  # A line, a rectangle or a text worked out, `:none` for one removed, a property nothing above it
  # gives grid's default. A rectangle's border of the blank line type is no border, as R's graphics
  # engine draws none.
  defp rect(theme, name) do
    case calculated(theme, name) do
      :none ->
        :none

      rect ->
        {fill, fill_opacity} = paint(Map.get(rect, :fill, @grid_fill))
        {color, color_opacity} = paint(Map.get(rect, :color, @grid_color))

        look = %{
          fill: fill,
          fill_opacity: fill_opacity,
          color: color,
          color_opacity: color_opacity,
          line_width: line_width(rect),
          dashes: dashes(rect)
        }

        case look.dashes do
          :blank -> %{look | color: :none, color_opacity: 0.0, dashes: :none}
          _dashes -> look
        end
    end
  end

  defp line(theme, name) do
    case calculated(theme, name) do
      :none ->
        :none

      line ->
        {color, opacity} = paint(Map.get(line, :color, @grid_color))

        %{
          color: color,
          opacity: opacity,
          line_width: line_width(line),
          line_end: Map.get(line, :lineend, @grid_line_end),
          dashes: dashes(line)
        }
    end
  end

  defp text(theme, name) do
    case calculated(theme, name) do
      :none -> :none
      text -> text_look(text)
    end
  end

  defp title(theme, name) do
    case calculated(theme, name) do
      :none ->
        :none

      text ->
        look = text_look(text)
        line_height = Map.get(text, :lineheight, @grid_line_height)
        Map.put(look, :line_spacing, line_height * @line_spacing_per_size * look.size)
    end
  end

  defp text_look(text) do
    {color, opacity} = paint(Map.get(text, :color, @grid_color))

    %{
      size: size(text),
      color: color,
      opacity: opacity,
      margin:
        text
        |> Map.get(:margin, @no_margin)
        |> margin_points()
    }
  end

  # A colour as the drawing paints it: its `#RRGGBB` and its opacity apart, its alpha over 255,
  # opaque for a colour without one; no colour at none.
  defp paint(:none), do: {:none, 0.0}
  defp paint(<<"#", _digits::binary-size(6)>> = color), do: {color, 1.0}

  defp paint(<<"#", digits::binary-size(6), alpha::binary-size(2)>>),
    do: {"#" <> digits, String.to_integer(alpha, 16) / 255}

  # A text's size in points, as a float: grid's default where nothing gives one, and a share with
  # nothing above it to be a share of the share itself, as R's graphics engine takes it.
  defp size(%{size: {:rel, share}}), do: share / 1
  defp size(%{size: size}), do: size / 1
  defp size(%{}), do: @grid_font_size / 1

  # A line width in points, from millimetres, in R's order of operations: its line-width units
  # (`line_width_units/1`) over 96 and times 72, as svglite writes them; grid's default where
  # nothing gives one.
  defp line_width(%{linewidth: _linewidth} = element), do: line_width_units(element) / 96 * 72
  defp line_width(%{}), do: @grid_line_width

  # How a line or a border is dashed, in points, as svglite writes R's line type (`scale_lty()`):
  # each length of its pattern times its width in R's line-width units, `linewidth * .pt`, or 1
  # where it is narrower; `:none` for a solid one, the line type nothing gives grid's, and
  # `:blank` for the blank line type, `:none` as a setting holds it.
  defp dashes(element) do
    case Map.get(element, :linetype, {}) do
      {} ->
        :none

      :none ->
        :blank

      pattern ->
        unit = max(line_width_units(element), 1.0)

        pattern
        |> Tuple.to_list()
        |> Enum.map(fn length -> length * unit end)
    end
  end

  # A line width in R's line-width units, as ggplot2 hands one to R's graphics engine, `linewidth *
  # .pt`: 1, grid's default, where nothing gives one, and a share with nothing above it to be a
  # share of the share itself in millimetres.
  defp line_width_units(%{linewidth: {:rel, share}}), do: share * @font_points_per_millimetre
  defp line_width_units(%{linewidth: linewidth}), do: linewidth * @font_points_per_millimetre
  defp line_width_units(%{}), do: 1.0

  # ggplot2's default theme, `theme_gray()` (defined there as `theme_grey()`), at its base sizes:
  # the text's in points, and the lines' and the borders' widths in millimetres, black ink on white
  # paper; its elements as `theme_gray()` gives them, in ggplot2's `theme-defaults.R`, each leaving
  # unset what it inherits, as far as Giggly draws.
  #
  # `half_line`, half the base size, spaces most things, and each colour is ink mixed toward paper
  # by ggplot2's `col_mix()`. Lines are solid ink, `base_line_size` wide, their ends cut square;
  # rectangles are filled with paper and bordered in solid ink `base_rect_size` wide; text is ink
  # at the base size, its lines 0.9 lines of R's graphics engine apart. The spacing is `half_line`
  # and so is every margin.
  #
  # The plot's background is bordered in paper. The panel's background is light grey (ink mixed
  # 92% toward paper) with no border, drawn under the layers, and its grid lines are paper, the
  # minor ones half as wide; there is no border over the panel. An axis draws no line; its ticks
  # are dark grey (20% toward paper), half the spacing long; its labels are grey
  # (30.2% toward paper), 0.8 of the base size, `0.8 * half_line / 2` from the ticks (a radius
  # axis's on both sides); its title is `half_line / 2` from the labels. A strip is light grey
  # (85% toward paper) with no border, and its text near black (10% toward paper), 0.8 of the base
  # size, with `0.8 * half_line` around it.
  #
  # A legend has no border; the space between legends, and between the panels and the legends, is
  # twice the spacing; each key is 1.2 lines square on the panel's background (`legend_key`
  # inherits it), whatever the base size; its labels are 0.8 of the base size; a colour bar's
  # ticks reach a fifth of a key into the bar. The plot's title is 1.2 times the base size with
  # `half_line` below it, its subtitle at the base size with `half_line` below it, its caption 0.8
  # of it with `half_line` above it, and its tag 1.2 times it.
  defp gray(%{base_size: base_size, base_line_size: line_size, base_rect_size: rect_size}) do
    half_line = base_size / 2

    %{
      line: %{color: @ink, linewidth: line_size, linetype: {}, lineend: :butt},
      rect: %{fill: @paper, color: @ink, linewidth: rect_size, linetype: {}},
      text: %{color: @ink, size: base_size, lineheight: 0.9, margin: @no_margin},
      title: %{},
      spacing: {half_line, :pt},
      margins: sides(half_line, half_line, half_line, half_line),
      axis_line: :none,
      axis_text: %{size: {:rel, 0.8}, color: @ink_toward_paper_30_2},
      axis_text_x: %{margin: sides(0.8 * half_line / 2, 0, 0, 0)},
      axis_text_y: %{margin: sides(0, 0.8 * half_line / 2, 0, 0)},
      axis_text_r: %{margin: sides(0, 0.8 * half_line / 2, 0, 0.8 * half_line / 2)},
      axis_ticks: %{color: @ink_toward_paper_20},
      axis_ticks_length: {:rel, 0.5},
      axis_title_x: %{margin: sides(half_line / 2, 0, 0, 0)},
      axis_title_y: %{margin: sides(0, half_line / 2, 0, 0)},
      legend_background: %{color: :none},
      legend_spacing: {:rel, 2},
      legend_key_size: {1.2, :lines},
      legend_text: %{size: {:rel, 0.8}},
      legend_ticks_length: {:rel, 0.2},
      legend_box_spacing: {:rel, 2},
      legend_position: :right,
      panel_background: %{fill: @ink_toward_paper_92, color: :none},
      panel_border: :none,
      panel_grid: %{color: @paper},
      panel_grid_minor: %{linewidth: {:rel, 0.5}},
      panel_ontop: false,
      strip_background: %{fill: @ink_toward_paper_85, color: :none},
      strip_text: %{
        color: @ink_toward_paper_10,
        size: {:rel, 0.8},
        margin: strip_margin(half_line)
      },
      plot_background: %{color: @paper},
      plot_title: %{size: {:rel, 1.2}, margin: sides(0, 0, half_line, 0)},
      plot_subtitle: %{margin: sides(0, 0, half_line, 0)},
      plot_caption: %{size: {:rel, 0.8}, margin: sides(half_line, 0, 0, 0)},
      plot_tag: %{size: {:rel, 1.2}}
    }
  end

  # `theme_bw()`: theme_gray()'s elements, these replaced whole. The panel is white, bordered dark
  # grey (20% toward paper), with light grey grid lines (92%), the minor ones half as wide, and a
  # strip is light grey (85.1%) bordered as the panel is.
  defp bw(sizes) do
    sizes
    |> gray()
    |> Map.merge(%{
      panel_background: %{fill: @paper, color: :none},
      panel_border: %{color: @ink_toward_paper_20},
      panel_grid: %{color: @ink_toward_paper_92},
      panel_grid_minor: %{linewidth: {:rel, 0.5}},
      strip_background: %{fill: @ink_toward_paper_85_1, color: @ink_toward_paper_20}
    })
  end

  # `theme_linedraw()`: theme_bw()'s elements, these replaced whole, every grey made ink or paper.
  # The axes' labels are ink, and their ticks ink half a line wide; the panel's border is ink, and
  # its grid lines ink a tenth of a line wide, the minor ones a twentieth; a strip is ink with its
  # text paper.
  defp linedraw(%{base_size: base_size} = sizes) do
    sizes
    |> bw()
    |> Map.merge(%{
      axis_text: %{color: @ink, size: {:rel, 0.8}},
      axis_ticks: %{color: @ink, linewidth: {:rel, 0.5}},
      panel_border: %{color: @ink, linewidth: {:rel, 1}},
      panel_grid: %{color: @ink},
      panel_grid_major: %{linewidth: {:rel, 0.1}},
      panel_grid_minor: %{linewidth: {:rel, 0.05}},
      strip_background: %{fill: @ink},
      strip_text: %{color: @paper, size: {:rel, 0.8}, margin: strip_margin(base_size / 2)}
    })
  end

  # `theme_light()`: theme_gray()'s elements, these replaced whole. The panel is white, bordered
  # light grey (70.2% toward paper); its grid lines are lighter grey (87.1%), half a line wide, the
  # minor ones a quarter; the axes' ticks are the border's grey, half a line wide; a strip is the
  # border's grey with its text paper.
  defp light(%{base_size: base_size} = sizes) do
    sizes
    |> gray()
    |> Map.merge(%{
      panel_background: %{fill: @paper, color: :none},
      panel_border: %{color: @ink_toward_paper_70_2, linewidth: {:rel, 1}},
      panel_grid: %{color: @ink_toward_paper_87_1},
      panel_grid_major: %{linewidth: {:rel, 0.5}},
      panel_grid_minor: %{linewidth: {:rel, 0.25}},
      axis_ticks: %{color: @ink_toward_paper_70_2, linewidth: {:rel, 0.5}},
      strip_background: %{fill: @ink_toward_paper_70_2, color: :none},
      strip_text: %{color: @paper, size: {:rel, 0.8}, margin: strip_margin(base_size / 2)}
    })
  end

  # `theme_dark()`: theme_gray()'s elements, these replaced whole. The panel is mid grey (49.9%
  # toward paper), and so is a legend key, which inherits it; its grid lines are darker (42%), half
  # a line wide, the minor ones a quarter; the axes' ticks are theme_gray()'s, half a line wide; a
  # strip is near black (15%) with its text near white (89.9%).
  defp dark(%{base_size: base_size} = sizes) do
    sizes
    |> gray()
    |> Map.merge(%{
      panel_background: %{fill: @ink_toward_paper_49_9, color: :none},
      panel_grid: %{color: @ink_toward_paper_42},
      panel_grid_major: %{linewidth: {:rel, 0.5}},
      panel_grid_minor: %{linewidth: {:rel, 0.25}},
      axis_ticks: %{color: @ink_toward_paper_20, linewidth: {:rel, 0.5}},
      strip_background: %{fill: @ink_toward_paper_15, color: :none},
      strip_text: %{
        color: @ink_toward_paper_89_9,
        size: {:rel, 0.8},
        margin: strip_margin(base_size / 2)
      }
    })
  end

  # `theme_minimal()`: theme_bw()'s elements, these replaced whole. No ticks, and the labels of
  # the axes below and left of the panels `0.45 * base_size` from them in their stead; no
  # background to the panels, the strips, the legends or their keys, and no border; the plot's
  # background is paper with no border.
  defp minimal(%{base_size: base_size} = sizes) do
    sizes
    |> bw()
    |> Map.merge(%{
      axis_ticks: :none,
      axis_text_x_bottom: %{margin: sides(0.45 * base_size, 0, 0, 0)},
      axis_text_y_left: %{margin: sides(0, 0.45 * base_size, 0, 0)},
      legend_background: :none,
      legend_key: :none,
      panel_background: :none,
      panel_border: :none,
      strip_background: :none,
      plot_background: %{fill: @paper, color: :none}
    })
  end

  # `theme_classic()`: theme_bw()'s elements, these replaced whole. No border and no grid lines;
  # the axes' lines drawn in ink with square ends, their ticks and labels ink, since each element
  # replaced leaves its colour to `line` and `text`; a strip is paper bordered in ink twice as wide
  # as a border, which its clipping halves.
  defp classic(sizes) do
    sizes
    |> bw()
    |> Map.merge(%{
      panel_border: :none,
      panel_grid: :none,
      axis_text: %{size: {:rel, 0.8}},
      axis_line: %{lineend: :square},
      axis_ticks: %{},
      strip_background: %{linewidth: {:rel, 2}}
    })
  end

  # `theme_void()`, a tree of its own, which draws only the legends, the strips' text and the
  # plot's titles: no lines at all; rectangles filled with its paper, ink with no alpha, with no
  # border, so the plot's background is drawn and seen through; no axes, their ticks of no length;
  # no background to the panels, the strips or the legends, nor to the legends' keys, which inherit
  # the panels'; the strips' text with no margin of its own; no margin round the plot or inside a
  # legend, legends a spacing apart and 0.2 centimetres from the panels; and the plot's title and
  # subtitle with `half_line` above them, as its caption has.
  defp void(%{base_size: base_size}) do
    half_line = base_size / 2

    %{
      line: :none,
      rect: %{fill: @clear_paper, color: :none, linewidth: 0, linetype: {}},
      text: %{color: @ink, size: base_size, lineheight: 0.9, margin: @no_margin},
      title: %{},
      spacing: {half_line, :pt},
      margins: sides(half_line, half_line, half_line, half_line),
      axis_text: :none,
      axis_title: :none,
      axis_ticks_length: {:rel, 0},
      legend_key_size: {1.2, :lines},
      legend_position: :right,
      legend_text: %{size: {:rel, 0.8}},
      legend_title: %{},
      legend_key_spacing: {:rel, 1},
      legend_margin: sides(0, 0, 0, 0),
      legend_box_spacing: {0.2, :cm},
      legend_ticks_length: {:rel, 0.2},
      legend_background: :none,
      strip_text: %{size: {:rel, 0.8}},
      strip_background: :none,
      panel_ontop: false,
      panel_background: :none,
      panel_border: :none,
      plot_margin: sides(0, 0, 0, 0),
      plot_title: %{size: {:rel, 1.2}, margin: sides(half_line, 0, 0, 0)},
      plot_subtitle: %{margin: sides(half_line, 0, 0, 0)},
      plot_caption: %{size: {:rel, 0.8}, margin: sides(half_line, 0, 0, 0)},
      plot_tag: %{size: {:rel, 1.2}},
      plot_background: %{}
    }
  end

  # The margin round a strip's text, `0.8 * half_line` on every side.
  defp strip_margin(half_line) do
    sides(0.8 * half_line, 0.8 * half_line, 0.8 * half_line, 0.8 * half_line)
  end

  # A margin of ggplot2's points on each side, top, right, bottom and left.
  defp sides(top, right, bottom, left) do
    %{top: {top, :pt}, right: {right, :pt}, bottom: {bottom, :pt}, left: {left, :pt}}
  end
end
