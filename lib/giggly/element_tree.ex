defmodule Giggly.ElementTree do
  @moduledoc false

  # The theme's element tree: ggplot2's `.element_tree`, as far as Giggly draws, each element named
  # as ggplot2 names it, its dots underscores. An element arrives with its first reader: the tree
  # holds what something draws, and what that inherits from.
  #
  # `Giggly.Theme` works out each element's kind and parent from it, and `Giggly.Plot` builds
  # `theme/2`'s options (`Giggly.Plot.Options`) and their documentation from it, so the vocabulary
  # has one home. Both read it while compiling, in module attributes, so it is a module of its own:
  # `Giggly.Plot` is recompiled when the tree changes, never when `Giggly.Theme` does. It is a boundary beside
  # `Giggly.Theme` rather than inside it, so only the boundaries that list it may read it.

  # The tree is values: it calls nothing.
  use Boundary, deps: [], exports: []

  @typedoc """
  What kind of value an element is: a line, a rectangle or a text, a length or a margin; where the
  legends go (`:position`); a point of the panels (`:point`); which point of a box is placed
  (`:justification`, by name or number, or `:box_justification`, by name alone); which way keys or
  legends run (`:direction`); what a box lines up with (`:location`); or whether something is
  done (`:boolean`).
  """
  @type kind ::
          :line
          | :rect
          | :text
          | :length
          | :margin
          | :position
          | :point
          | :justification
          | :box_justification
          | :direction
          | :location
          | :boolean

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
    {:legend_spacing_x, :length, :legend_spacing,
     "The space between a legend and the next beside it."},
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
     "Where the legends go: `:right`, `:left`, `:top` or `:bottom`, beside the panels on that " <>
       "side, `:inside`, over them, or `:none`, for no legends."},
    {:legend_position_inside, :point, :none,
     "Where the legends' box goes when they are inside the panels: `{x, y}`, each a share of " <>
       "the panels' width or height from their left or bottom; at its justification unless " <>
       "given."},
    {:legend_direction, :direction, :none,
     "Which way each legend's keys run: `:horizontal` or `:vertical`; across above or below " <>
       "the panels and down elsewhere unless given."},
    {:legend_justification, :justification, :none,
     "Which point of the legends' box is placed where it goes: `:center`, a side (`:left`, " <>
       "`:right`, `:top`, `:bottom`), or `{horizontal, vertical}`, each a share of the box's " <>
       "width or height or `:left`, `:center` or `:right` across and `:bottom`, `:center` or " <>
       "`:top` up; beside the panels, the same point of the room beside them."},
    {:legend_justification_top, :justification, :legend_justification,
     "The justification of legends above the panels."},
    {:legend_justification_bottom, :justification, :legend_justification,
     "The justification of legends below the panels."},
    {:legend_justification_left, :justification, :legend_justification,
     "The justification of legends left of the panels."},
    {:legend_justification_right, :justification, :legend_justification,
     "The justification of legends right of the panels."},
    {:legend_justification_inside, :justification, :legend_justification,
     "The justification of legends inside the panels."},
    {:legend_location, :location, :none,
     "What legends beside the panels line up with: `:panel`, the panels, or `:plot`, the " <>
       "axes and their titles too."},
    {:legend_box, :direction, :none,
     "How several legends are arranged: `:horizontal`, side by side, or `:vertical`, one " <>
       "above another; side by side above or below the panels and one above another " <>
       "elsewhere unless given."},
    {:legend_box_just, :box_justification, :none,
     "Which point of each legend is placed at the same point of its room in the box: as " <>
       "`:legend_justification` takes, by name alone; at the box's top, centred across above " <>
       "or below the panels and at its left elsewhere, unless given."},
    {:legend_box_margin, :margin, :margins, "The margin inside the legends' box."},
    {:legend_box_background, :rect, :none,
     "The background of the legends' box, over its margin too, drawn as its own setting gives " <>
       "it: what that leaves unset is the drawing's default, a white fill and a solid black " <>
       "border 0.75 points wide, never `:rect`'s."},
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

  # Every element, each its name, kind, the element it inherits from (`:none` for a root) and what
  # it styles, in ggplot2's order, for `Giggly.Theme` to work a theme out by and for
  # `Giggly.Plot.theme/2` to check its settings against and document.
  @doc false
  @spec elements() :: [{atom(), kind(), atom(), String.t()}]
  def elements, do: @elements
end
