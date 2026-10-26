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
  # `Giggly.ElementTree` lists the tree as far as Giggly draws it: what something draws, and what
  # that inherits from.
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
  # A complete theme also gives the layers their defaults, ggplot2's `element_geom()` (`geom`),
  # which every complete theme sets from its base sizes and its paper, `theme_void()`'s clear, and
  # no setting reaches: the ink and paper a layer's default colours are mixed from, the widths of
  # its lines and borders, its text's family and size, and its points' size and shape, in a layer's
  # millimetres, since they become the values of a layer's aesthetics. The assembly reads it to fill
  # in what each layer leaves unset.
  #
  # Where the legends go is the theme's too, as ggplot2's is: beside the panels on a side, inside
  # them at a point of them, or nowhere; which way each legend's keys run; which point of the
  # legends' box is placed there, a justification for each place, by name or by share as grid's
  # `valid.just()` reads one, centred where nothing gives one, as `theme_void()` gives none; what a
  # box beside the panels lines up with; and how several legends are arranged in the box and
  # where each sits in it. Which way the keys run, how the legends are arranged and where each sits
  # are `:none` where the theme leaves them to where the legends go, which the drawing works out as
  # ggplot2's guides do. A theme that sets no space between legends, as `theme_void()` sets none,
  # has half a line between them, as ggplot2's guide box fills it in. The box's background is
  # worked out as its own setting gives it, inheriting nothing, as ggplot2's guide box draws it
  # without working it out through the tree. A legend's title and labels
  # are worked out for each side of its keys they are drawn on, as ggplot2's legend works them out
  # for where it puts them.
  #
  # A text's family, its face, its angle and its justification are the theme's too, as ggplot2's
  # `element_text()` gives them, and so is the spacing of a title's lines: the y axis's title is
  # turned 90 degrees because `theme_gray()` turns it, and a tick label hangs from its tick because
  # the theme justifies it so. A legend's title and labels take their justification from the text
  # their side lays over the theme, as their margins do. A family is a font's name, `""` the
  # device's own: a complete theme's `base_family` is its root text's family and its layers', and
  # its `header_family`, where given, is `title`'s, which the axes' titles, the legends' titles and
  # the plot's title inherit, as ggplot2's tree gives no other text `title` for a parent.
  #
  # When a plot is rendered, every function that draws something other than a mark takes the
  # complete theme and reads the elements it draws. A theme holds sizes, colours, line widths, line
  # types and ends, spacing, text's families, faces, angles and justification, and whether the
  # panel's background and grid are drawn over its layers.

  # A theme is values: it calls nothing, and reads only its element tree, while compiling. The
  # complete theme is this module's struct, which a boundary listing this one reads.
  use Boundary, deps: [Giggly.ElementTree], exports: []

  alias Giggly.ElementTree

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
    :strip_background_y,
    :strip_text_x_top,
    :strip_text_y_right,
    :legend_background,
    :legend_margin,
    :legend_key,
    :legend_key_width,
    :legend_key_height,
    :legend_key_spacing,
    :legend_title_top,
    :legend_title_left,
    :legend_text_right,
    :legend_text_bottom,
    :legend_ticks,
    :legend_ticks_length,
    :legend_spacing_x,
    :legend_spacing_y,
    :legend_position,
    :legend_position_inside,
    :legend_direction,
    :legend_justification_top,
    :legend_justification_bottom,
    :legend_justification_left,
    :legend_justification_right,
    :legend_justification_inside,
    :legend_location,
    :legend_box,
    :legend_box_just,
    :legend_box_margin,
    :legend_box_background,
    :legend_box_spacing,
    :plot_title,
    :plot_subtitle,
    :plot_caption,
    :plot_tag,
    :geom
  ]
  defstruct @enforce_keys

  @typedoc "A complete theme's name, as a plot records it."
  @type name :: :gray | :bw | :linedraw | :light | :dark | :minimal | :classic | :void

  @typedoc """
  A complete theme a plot chose: its name, its base sizes, its text's size in points and its
  lines' and borders' widths in millimetres, and its families, its text's and its layers'
  (`base_family`, `""` the device's own) and its titles' (`header_family`, `:none` where the
  titles take the base family).
  """
  @type chosen :: %{
          name: name(),
          base_size: float(),
          base_line_size: float(),
          base_rect_size: float(),
          base_family: String.t(),
          header_family: String.t() | :none
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
  Where the legends go: beside the panels on a side, inside them, or nowhere, `:none`.
  """
  @type position :: :right | :left | :top | :bottom | :inside | :none

  @typedoc "Which way a legend's keys, or several legends, run."
  @type direction :: :horizontal | :vertical

  @typedoc """
  A point of something, `{x, y}`, each a share of its width or height from its left or its
  bottom, as grid's `npc` units are, and may lie beyond it.
  """
  @type point :: {float(), float()}

  @typedoc """
  Which point of a box is placed, as a setting gives it: `:center`; a side, `:left`, `:right`,
  `:top` or `:bottom`, the middle of that side; or `{horizontal, vertical}`, each a share of the
  box's width or height or the name of one, `:left`, `:center` or `:right` across and
  `:bottom`, `:center` or `:top` up, as grid's `valid.just()` reads them.
  """
  @type justification ::
          :center
          | :left
          | :right
          | :top
          | :bottom
          | {:left | :center | :right | number(), :bottom | :center | :top | number()}

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

  @typedoc "A text's face: plain, bold, italic, or bold and italic."
  @type face :: :plain | :bold | :italic | :bold_italic

  @typedoc """
  Text's `size`, its `color`, an `#RRGGBB` drawn at `opacity`, from 0 to 1, its `family`, a font's
  name, `""` the device's own, its `face`, the `angle` it is turned, in degrees anticlockwise, its
  `hjust` and `vjust`, where it sits across and up as shares of its width and height, in its own
  turned frame, and its `margin`: the space in points on each side of it, of which the drawing
  counts the sides ggplot2 counts; or `:none`, removed.
  """
  @type text ::
          %{
            size: float(),
            color: String.t(),
            opacity: float(),
            family: String.t(),
            face: face(),
            angle: float(),
            hjust: float(),
            vjust: float(),
            margin: margin()
          }
          | :none

  @typedoc """
  A title's text, which may run over several lines: its `size`, `color`, `opacity`, `family`,
  `face`, `angle`, `hjust`, `vjust` and `margin`, as text's, and its `line_spacing`, the distance
  in points from one line's baseline to the next's; or `:none`, removed.
  """
  @type title ::
          %{
            size: float(),
            color: String.t(),
            opacity: float(),
            family: String.t(),
            face: face(),
            angle: float(),
            hjust: float(),
            vjust: float(),
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
  panels across and down; the background and text of the strips above and right of the panels; a
  legend's background, the margin inside it, each key's background, width and height, the space
  between its keys, its title above its keys or left of them, its labels right of its keys or below
  a colour bar, each with its margin facing the keys widened by the keys' spacing, a colour bar's
  ticks and how far each reaches into the bar; the space between one legend and the next beside
  it or below it; where the legends go (`legend_position`), the point of the panels an inside box
  goes at (`legend_position_inside`), which way each legend's keys run (`legend_direction`),
  which point of the box is placed there on each side (`legend_justification_top` and the rest,
  `{x, y}`), what a box beside the panels lines up with (`legend_location`), how several legends
  are arranged in the box (`legend_box`) and where each sits in it (`legend_box_just`), the
  direction, the arrangement and the place in the box `:none` where the theme leaves them to the
  position; the box's margin, background and space from the panels; the plot's title, subtitle,
  caption and tag; and the layers' defaults (`geom`). Every length is in points but the layers'
  defaults, which are in a layer's millimetres; a line, a rectangle or a text the theme removes is
  `:none`.
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
          strip_background_y: rect(),
          strip_text_x_top: text(),
          strip_text_y_right: text(),
          legend_background: rect(),
          legend_margin: margin(),
          legend_key: rect(),
          legend_key_width: float(),
          legend_key_height: float(),
          legend_key_spacing: float(),
          legend_title_top: title(),
          legend_title_left: title(),
          legend_text_right: text(),
          legend_text_bottom: text(),
          legend_ticks: line(),
          legend_ticks_length: float(),
          legend_spacing_x: float(),
          legend_spacing_y: float(),
          legend_position: position(),
          legend_position_inside: point(),
          legend_direction: direction() | :none,
          legend_justification_top: point(),
          legend_justification_bottom: point(),
          legend_justification_left: point(),
          legend_justification_right: point(),
          legend_justification_inside: point(),
          legend_location: :panel | :plot,
          legend_box: direction() | :none,
          legend_box_just: point() | :none,
          legend_box_margin: margin(),
          legend_box_background: rect(),
          legend_box_spacing: float(),
          plot_title: title(),
          plot_subtitle: title(),
          plot_caption: title(),
          plot_tag: title(),
          geom: geom()
        }

  @typedoc """
  The layers' defaults, ggplot2's `element_geom()`: the ink and paper their colours are mixed
  from and the accent a smooth is drawn in, each a colour in its one spelling; the width and line type of their lines and of their
  borders, in millimetres; their text's family, the theme's base family, `""` for the device's
  own, and its size, and their points' size, in millimetres, and shape.
  """
  @type geom :: %{
          ink: String.t(),
          paper: String.t(),
          accent: String.t(),
          linewidth: float(),
          borderwidth: float(),
          linetype: tuple(),
          bordertype: tuple(),
          family: String.t(),
          fontsize: float(),
          pointsize: float(),
          pointshape: atom()
        }

  # The element tree, read while compiling, and each element's kind and parent.
  @elements ElementTree.elements()

  @kinds Map.new(@elements, fn {name, kind, _parent, _description} -> {name, kind} end)
  @parents Map.new(@elements, fn {name, _kind, parent, _description} -> {name, parent} end)

  # The elements that are a line, a rectangle or a text, which a setting may remove.
  @drawn_kinds for {name, kind, _parent, _description} <- @elements,
                   kind in [:line, :rect, :text],
                   into: %{},
                   do: {name, kind}

  # grid's own defaults, which a property nothing in the theme gives falls to, as R draws it: black,
  # a white fill, a line 1/96 inch wide, which svglite writes in points, with round ends, and a
  # 12-point font with its lines 1.2 apart, which also make grid's line of text, in the device's
  # own family, plain, level and centred both ways, as grid's `textGrob()` draws text. R itself
  # fails on a text whose justification only a removed root would give; the drawing centres it, as
  # grid would.
  @grid_color "#000000"
  @grid_fill "#FFFFFF"
  @grid_line_width 72 / 96
  @grid_line_end :round
  @grid_font_size 12
  @grid_line_height 1.2
  @grid_family ""
  @grid_face :plain
  @grid_angle 0
  @grid_justification 0.5

  # ggplot2's line widths are millimetres, which grid draws as `.pt` line-width units each, and a
  # line-width unit is 1/96 inch, which svglite writes in points.
  @font_points_per_millimetre 72.27 / 25.4

  # R's graphics engine spaces lines of text 1.2 font sizes apart, times a text's `lineheight`.
  @line_spacing_per_size 1.2

  # The margin of no space at all, ggplot2's `margin()`.
  @no_margin %{top: {0, :pt}, right: {0, :pt}, bottom: {0, :pt}, left: {0, :pt}}

  # The complete themes, by name.
  @names [:gray, :bw, :linedraw, :light, :dark, :minimal, :classic, :void]

  # A complete theme's sizes and families unless a plot gives others, as ggplot2's take them: an
  # 11-point base size, lines and borders `base_size / 22` millimetres wide, the device's own
  # family, and titles in the base family.
  @default_base_size 11.0
  @default_base_family ""
  @default_bases %{
    base_size: @default_base_size,
    base_line_size: @default_base_size / 22,
    base_rect_size: @default_base_size / 22,
    base_family: @default_base_family,
    header_family: :none
  }

  # Every complete theme's ink and paper, black on white, and `theme_void()`'s paper, its ink with
  # no alpha (`alpha(ink, 0)`).
  @ink "#000000"
  @paper "#FFFFFF"
  @clear_paper "#00000000"

  # The accent every complete theme gives the layers, ggplot2's `element_geom(accent =)`, a
  # smooth's colour.
  @accent "#3366FF"

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

  # The space between legends when the theme sets none, as `theme_void()` sets none: half a line,
  # as ggplot2's guide box fills it in (`Guides$assemble()`), before the spacing across and down
  # inherit it.
  @legend_spacing {0.5, :lines}

  # A plot's theme with the complete theme `name` chosen, at the sizes and in the families `bases`
  # gives, sizes floats as `Giggly.Plot`'s checks keep them, its text's in points and its lines'
  # and borders' in millimetres, and any it leaves out ggplot2's defaults: 11 points,
  # `base_size / 22` for each width, the device's own family, and titles in the base family,
  # `:none`, as ggplot2's `header_family = NULL`. Its settings are none, as ggplot2 drops a plot's
  # earlier settings with the theme a complete theme replaces.
  @doc false
  @spec choose(name(), keyword()) :: plot_theme()
  def choose(name, bases) when name in @names do
    base_size = Keyword.get(bases, :base_size, @default_base_size)

    chosen = %{
      name: name,
      base_size: base_size,
      base_line_size: Keyword.get(bases, :base_line_size, base_size / 22),
      base_rect_size: Keyword.get(bases, :base_rect_size, base_size / 22),
      base_family: Keyword.get(bases, :base_family, @default_base_family),
      header_family: Keyword.get(bases, :header_family, :none)
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

  # Only a line, a rectangle or a text may be removed, so only one is ever replaced whole.
  defp merged_element(complete, _kind, :none, new) when complete != :none and is_map(new),
    do: {:replace, new}

  defp merged_element(_complete, _kind, {:replace, old}, new) when is_map(new),
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

  # The elements of the complete theme a plot chose, at its sizes and in its families, or of
  # theme_gray() at its defaults for a plot that chose none.
  defp tree(:none), do: gray(@default_bases)
  defp tree(%{name: :gray} = bases), do: gray(bases)
  defp tree(%{name: :bw} = bases), do: bw(bases)
  defp tree(%{name: :linedraw} = bases), do: linedraw(bases)
  defp tree(%{name: :light} = bases), do: light(bases)
  defp tree(%{name: :dark} = bases), do: dark(bases)
  defp tree(%{name: :minimal} = bases), do: minimal(bases)
  defp tree(%{name: :classic} = bases), do: classic(bases)
  defp tree(%{name: :void} = bases), do: void(bases)

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
    legend_ticks_theme = Map.put_new(theme, :legend_ticks, @colorbar_ticks)
    legend_spacing_theme = Map.put_new(theme, :legend_spacing, @legend_spacing)
    inside = justification(theme, :legend_justification_inside)

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
      strip_background_y: rect(theme, :strip_background_y),
      strip_text_x_top: text(theme, :strip_text_x_top),
      strip_text_y_right: text(theme, :strip_text_y_right),
      legend_background: rect(theme, :legend_background),
      legend_margin: margin(theme, :legend_margin),
      legend_key: rect(theme, :legend_key),
      legend_key_width: distance(theme, :legend_key_width),
      legend_key_height: distance(theme, :legend_key_height),
      legend_key_spacing: gap,
      legend_title_top:
        title(beside_keys(theme, {text_margin, :bottom, gap}, {0, 0.5}), :legend_title),
      legend_title_left:
        title(beside_keys(theme, {text_margin, :right, gap}, {0, 0.5}), :legend_title),
      legend_text_right:
        text(beside_keys(theme, {text_margin, :left, gap}, {0, 0.5}), :legend_text),
      legend_text_bottom:
        text(beside_keys(theme, {text_margin, :top, gap}, {0.5, 1}), :legend_text),
      legend_ticks: line(legend_ticks_theme, :legend_ticks),
      legend_ticks_length: distance(theme, :legend_ticks_length),
      legend_spacing_x: distance(legend_spacing_theme, :legend_spacing_x),
      legend_spacing_y: distance(legend_spacing_theme, :legend_spacing_y),
      legend_position: calculated(theme, :legend_position),
      legend_position_inside: inside_point(calculated(theme, :legend_position_inside), inside),
      legend_direction: given(calculated(theme, :legend_direction)),
      legend_justification_top: justification(theme, :legend_justification_top),
      legend_justification_bottom: justification(theme, :legend_justification_bottom),
      legend_justification_left: justification(theme, :legend_justification_left),
      legend_justification_right: justification(theme, :legend_justification_right),
      legend_justification_inside: inside,
      legend_location: location(calculated(theme, :legend_location)),
      legend_box: given(calculated(theme, :legend_box)),
      legend_box_just: box_justification(calculated(theme, :legend_box_just)),
      legend_box_margin: margin(theme, :legend_box_margin),
      legend_box_background: box_background(theme),
      legend_box_spacing: distance(theme, :legend_box_spacing),
      plot_title: title(theme, :plot_title),
      plot_subtitle: title(theme, :plot_subtitle),
      plot_caption: title(theme, :plot_caption),
      plot_tag: title(theme, :plot_tag),
      geom: Map.fetch!(theme, :geom)
    }
  end

  # The root text's margin, which a legend widens beside its keys: none for a removed root text, as
  # ggplot2's legend takes a blank's margin as `margin()`.
  defp text_margin(:none), do: @no_margin
  defp text_margin(text), do: text.margin

  # `theme` with its root text's margin widened by `gap` on `side`, the side facing a legend's keys,
  # and its justification `{hjust, vjust}`, as ggplot2's legend lays a text element over the theme
  # to give its title and labels their default margins and justification for that side, which
  # what the title's or the labels' own element sets replaces: a title left-aligned and centred
  # down, labels right of the keys the same, labels below a colour bar centred and hung. The root's
  # face and angle are left as they are. Laid over a removed root text, it replaces the removal,
  # and the root takes the rest from theme_gray()'s, so a legend's title and labels are drawn where
  # every other text is removed, as ggplot2's are.
  defp beside_keys(theme, {margin, side, gap}, {hjust, vjust}) do
    widened = Map.update!(margin, side, fn length -> {points(length) + gap, :points} end)
    lay_over(theme, %{text: %{margin: widened, hjust: hjust, vjust: vjust}})
  end

  # A justification worked out as grid's `valid.just()` reads one, `{x, y}`, each a share of the
  # box's width or height; centred where nothing gives one, as `theme_void()` gives none and grid
  # reads `NULL`.
  defp justification(theme, name), do: point(calculated(theme, name))

  defp point(nil), do: {0.5, 0.5}
  defp point(:center), do: {0.5, 0.5}
  defp point(:left), do: {0.0, 0.5}
  defp point(:right), do: {1.0, 0.5}
  defp point(:top), do: {0.5, 1.0}
  defp point(:bottom), do: {0.5, 0.0}
  defp point({horizontal, vertical}), do: {share(horizontal), share(vertical)}

  defp share(:left), do: 0.0
  defp share(:bottom), do: 0.0
  defp share(:center), do: 0.5
  defp share(:right), do: 1.0
  defp share(:top), do: 1.0
  defp share(amount), do: amount / 1

  # The point of the panels an inside box goes at: where a setting puts it, or at its own
  # justification, as ggplot2's guide box places it.
  defp inside_point(nil, justification), do: justification
  defp inside_point({x, y}, _justification), do: {x / 1, y / 1}

  # Where each legend sits in the box, `:none` where the theme leaves it to the legends'
  # position, which the box works out.
  defp box_justification(nil), do: :none
  defp box_justification(justification), do: point(justification)

  # What a box beside the panels lines up with: the panels unless the theme says otherwise, as
  # ggplot2's `table_add_legends()` takes `legend.location`.
  defp location(nil), do: :panel
  defp location(location), do: location

  # A direction the theme gives, `:none` where it leaves it to the legends' position.
  defp given(nil), do: :none
  defp given(direction), do: direction

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
  # from theme_gray()'s at its defaults, as ggplot2 fills a root from its default theme; nothing
  # for a removed root passed over.
  defp root(_name, nil), do: nil

  defp root(name, element) when is_map_key(@drawn_kinds, name) do
    @default_bases
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

  defp inherit(kind, element, _parent) when kind in [:length, :margin, :justification],
    do: element

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
  defp rect(theme, name), do: rect_look(calculated(theme, name))

  # The legends' box's background as its own element gives it, inheriting nothing, so what it
  # leaves unset is grid's default, as ggplot2's `package_box()` draws `legend.box.background` as
  # the theme holds it, never through `calc_element()`.
  defp box_background(theme), do: rect_look(Map.fetch!(theme, :legend_box_background))

  defp rect_look(:none), do: :none

  defp rect_look(rect) do
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
      family: Map.get(text, :family, @grid_family),
      face: Map.get(text, :face, @grid_face),
      angle: Map.get(text, :angle, @grid_angle) / 1,
      hjust: Map.get(text, :hjust, @grid_justification) / 1,
      vjust: Map.get(text, :vjust, @grid_justification) / 1,
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
  # the text's in points, and the lines' and the borders' widths in millimetres, and in its
  # families, black ink on white paper; its elements as `theme_gray()` gives them, in ggplot2's
  # `theme-defaults.R`, each leaving unset what it inherits, as far as Giggly draws.
  #
  # `half_line`, half the base size, spaces most things, and each colour is ink mixed toward paper
  # by ggplot2's `col_mix()`. Lines are solid ink, `base_line_size` wide, their ends cut square;
  # rectangles are filled with paper and bordered in solid ink `base_rect_size` wide; text is plain
  # ink at the base size in the base family, level and centred both ways, its lines 0.9 lines of
  # R's graphics engine apart, and the titles in the header family where one is given. The spacing
  # is `half_line` and so is every margin.
  #
  # The plot's background is bordered in paper. The panel's background is light grey (ink mixed
  # 92% toward paper) with no border, drawn under the layers, and its grid lines are paper, the
  # minor ones half as wide; there is no border over the panel. An axis draws no line; its ticks
  # are dark grey (20% toward paper), half the spacing long; its labels are grey
  # (30.2% toward paper), 0.8 of the base size, `0.8 * half_line / 2` from the ticks (a radius
  # axis's on both sides), the x axis's hanging from their ticks, the y axis's ending at theirs, a
  # radius axis's centred; its title is `half_line / 2` from the labels, the x axis's hanging, the
  # y axis's turned 90 degrees with its top toward the labels' far side. A strip is light grey
  # (85% toward paper) with no border, and its text near black (10% toward paper), 0.8 of the base
  # size, with `0.8 * half_line` around it, turned 90 degrees clockwise in a strip right of a panel.
  #
  # A legend has no border; the space between legends, and between the panels and the legends, is
  # twice the spacing; each key is 1.2 lines square on the panel's background (`legend_key`
  # inherits it), whatever the base size; its labels are 0.8 of the base size; its title is
  # left-aligned; a colour bar's ticks reach a fifth of a key into the bar; the legends go right of
  # the panels, centred, in a box with no margin and no background. The plot's title is 1.2 times
  # the base size with `half_line` below it, its subtitle at the base size with `half_line` below
  # it, both left-aligned and hanging, its caption 0.8 of it with `half_line` above it,
  # right-aligned and hanging, and its tag 1.2 times it, centred both ways.
  defp gray(%{base_size: base_size, base_line_size: line_size, base_rect_size: rect_size} = bases) do
    half_line = base_size / 2

    %{
      geom: geom(bases, @paper),
      line: %{color: @ink, linewidth: line_size, linetype: {}, lineend: :butt},
      rect: %{fill: @paper, color: @ink, linewidth: rect_size, linetype: {}},
      text: root_text(bases),
      title: titles(bases),
      spacing: {half_line, :pt},
      margins: sides(half_line, half_line, half_line, half_line),
      axis_line: :none,
      axis_text: %{size: {:rel, 0.8}, color: @ink_toward_paper_30_2},
      axis_text_x: %{margin: sides(0.8 * half_line / 2, 0, 0, 0), vjust: 1},
      axis_text_y: %{margin: sides(0, 0.8 * half_line / 2, 0, 0), hjust: 1},
      axis_text_r: %{margin: sides(0, 0.8 * half_line / 2, 0, 0.8 * half_line / 2), hjust: 0.5},
      axis_ticks: %{color: @ink_toward_paper_20},
      axis_ticks_length: {:rel, 0.5},
      axis_title_x: %{margin: sides(half_line / 2, 0, 0, 0), vjust: 1},
      axis_title_y: %{angle: 90, margin: sides(0, half_line / 2, 0, 0), vjust: 1},
      legend_background: %{color: :none},
      legend_spacing: {:rel, 2},
      legend_key_size: {1.2, :lines},
      legend_text: %{size: {:rel, 0.8}},
      legend_title: %{hjust: 0},
      legend_ticks_length: {:rel, 0.2},
      legend_position: :right,
      legend_justification: :center,
      legend_box_margin: sides(0, 0, 0, 0),
      legend_box_background: :none,
      legend_box_spacing: {:rel, 2},
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
      strip_text_y: %{angle: -90},
      plot_background: %{color: @paper},
      plot_title: %{size: {:rel, 1.2}, hjust: 0, vjust: 1, margin: sides(0, 0, half_line, 0)},
      plot_subtitle: %{hjust: 0, vjust: 1, margin: sides(0, 0, half_line, 0)},
      plot_caption: %{size: {:rel, 0.8}, hjust: 1, vjust: 1, margin: sides(half_line, 0, 0, 0)},
      plot_tag: %{size: {:rel, 1.2}, hjust: 0.5, vjust: 0.5}
    }
  end

  # `theme_bw()`: theme_gray()'s elements, these replaced whole. The panel is white, bordered dark
  # grey (20% toward paper), with light grey grid lines (92%), the minor ones half as wide, and a
  # strip is light grey (85.1%) bordered as the panel is.
  defp bw(bases) do
    bases
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
  defp linedraw(%{base_size: base_size} = bases) do
    bases
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
  defp light(%{base_size: base_size} = bases) do
    bases
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
  defp dark(%{base_size: base_size} = bases) do
    bases
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
  defp minimal(%{base_size: base_size} = bases) do
    bases
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
  defp classic(bases) do
    bases
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
  # the panels'; the strips' text with no margin of its own; no margin round the plot, inside a
  # legend or inside the legends' box, and no background to the box; no space set between legends,
  # which the box makes half a line, nor a justification, which centres them; legends 0.2
  # centimetres from the panels, their titles left-aligned; and the plot's title and subtitle with
  # `half_line` above them, as its caption has, each aligned as theme_gray()'s. Its text and its
  # titles take its families as theme_gray()'s do.
  defp void(%{base_size: base_size} = bases) do
    half_line = base_size / 2

    %{
      geom: geom(bases, @clear_paper),
      line: :none,
      rect: %{fill: @clear_paper, color: :none, linewidth: 0, linetype: {}},
      text: root_text(bases),
      title: titles(bases),
      spacing: {half_line, :pt},
      margins: sides(half_line, half_line, half_line, half_line),
      axis_text: :none,
      axis_title: :none,
      axis_ticks_length: {:rel, 0},
      legend_key_size: {1.2, :lines},
      legend_position: :right,
      legend_text: %{size: {:rel, 0.8}},
      legend_title: %{hjust: 0},
      legend_key_spacing: {:rel, 1},
      legend_margin: sides(0, 0, 0, 0),
      legend_box_margin: sides(0, 0, 0, 0),
      legend_box_spacing: {0.2, :cm},
      legend_ticks_length: {:rel, 0.2},
      legend_background: :none,
      legend_box_background: :none,
      strip_text: %{size: {:rel, 0.8}},
      strip_background: :none,
      panel_ontop: false,
      panel_background: :none,
      panel_border: :none,
      plot_margin: sides(0, 0, 0, 0),
      plot_title: %{size: {:rel, 1.2}, hjust: 0, vjust: 1, margin: sides(half_line, 0, 0, 0)},
      plot_subtitle: %{hjust: 0, vjust: 1, margin: sides(half_line, 0, 0, 0)},
      plot_caption: %{size: {:rel, 0.8}, hjust: 1, vjust: 1, margin: sides(half_line, 0, 0, 0)},
      plot_tag: %{size: {:rel, 1.2}, hjust: 0.5, vjust: 0.5},
      plot_background: %{}
    }
  end

  # Every complete theme's root text at its base size and in its base family: plain ink, level,
  # centred both ways, its lines 0.9 lines of R's graphics engine apart, with no margin.
  defp root_text(%{base_size: base_size, base_family: base_family}) do
    %{
      color: @ink,
      size: base_size,
      family: base_family,
      face: :plain,
      angle: 0,
      hjust: 0.5,
      vjust: 0.5,
      lineheight: 0.9,
      margin: @no_margin
    }
  end

  # Every complete theme's `title`: in its header family where one is given, and otherwise setting
  # nothing, so the titles take the root text's family, as ggplot2's `header_family = NULL` leaves
  # `title`'s family unset.
  defp titles(%{header_family: :none}), do: %{}
  defp titles(%{header_family: header_family}), do: %{family: header_family}

  # The layers' defaults, ggplot2's `element_geom()` as every complete theme sets it from its base
  # sizes: its ink, `paper` and accent; its lines' and its borders' widths `base_line_size`, never
  # `base_rect_size`, and solid; its text's family the base family, never the header family, and
  # its size the base size in millimetres (`base_size / .pt`); its points' size 1.5 times the base
  # size over 11, and the solid circle. They stay in a layer's millimetres, since they become the
  # values of a layer's aesthetics, which a layer may set instead, and no setting reaches them.
  defp geom(
         %{base_size: base_size, base_line_size: line_size, base_family: base_family},
         paper
       ) do
    %{
      ink: @ink,
      paper: paper,
      accent: @accent,
      linewidth: line_size,
      borderwidth: line_size,
      linetype: {},
      bordertype: {},
      family: base_family,
      fontsize: base_size / @font_points_per_millimetre,
      pointsize: base_size / 11 * 1.5,
      pointshape: :circle
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
