---
paths:
  - "lib/giggly/guide.ex"
  - "lib/giggly/guide/**"
---

# Guides

`Giggly.Guide` draws the axes beside a panel and their titles, ggplot2's `guide_axis()`, and the
panel's background and grid lines, ggplot2's `guide_grid()`. Why a
domain of its own, and why it is called a guide: design-log §4, the entry beginning "Axes are
drawn"; which name titles an axis: the entry beginning "An axis is titled"; why the grid is
drawn here but placed by the coordinate system: the entry beginning "The panel's grid lines are
placed by the coordinate system".

## Rules

- **A guide takes its breaks from the coordinate system, already placed** (`Coord.axes/1`), so
  ticks and marks are placed by one rule. Which side of the panel an axis is drawn on, and so
  which aesthetic's title goes there, is the coordinate system's call; a guide draws the sides it
  is given, with the titles it is handed by aesthetic.
- **An axis's title is drawn by its guide, in a cell of its own beyond the axis**, as ggplot2 lays
  out its axis titles: centred on the panel's side, hanging from the cell's edge away from the
  axis, turned 90 degrees on the left. A title of `:none` draws nothing and takes no room.
- **The grid's lines come placed from the coordinate system** (`Coord.grid/1`); the guide gives
  them the theme's look and ggplot2's order: the panel's background, the minor lines at the y
  axis's minor breaks, then the x axis's, then the major lines at the y axis's breaks, then the
  x axis's. A group with no lines is drawn as an empty primitive, which draws nothing.
- **A guide measures what it draws and reports how far it reaches from the panel, in points.**
  That is the fixed width or height of the axis's column or row in the scene, measured when the
  scene is built, as ggplot2's `measure_grobs` measures an axis while building its table.
- **Primitives are placed in the axis's cell.** Along the panel's side, at the break's place (the
  cell spans the side); across it, at fractions of the axis's own depth. A label's baseline is the
  one position in points, offset from its anchor, since a label centred on a break sits half a
  line below it whatever height the panel turns out to be.
- **The look is the theme's** (`Giggly.Theme`), handed in by rendering already in points: the
  ticks' colour, width and length, the labels' and titles' size, colour and margin. How a label is
  hung from its tick and the y title's 90-degree turn are the guide's until a theme can set them.
- **An axis with no breaks draws nothing and takes no room**, as ggplot2's exits early.
- **Drawing order follows ggplot2's:** below the panel the ticks and then the labels, to its left
  the labels and then the ticks.
- **What waits for its first reader:** axes above or to the right, angled, dodged or thinned
  labels, the axis line (blank in `theme_grey()`), minor ticks, a title set by `labs/2`, and a
  guide behaviour (the first legend).

## How it works

`axes(panel_params, titles, theme)` asks `Coord.axes/1` for each side's aesthetic and placed
breaks, and returns for each side `%{axis: …, title: …}`, each `{size, primitives}`, from
`Guide.Axis.draw/3` and `Guide.Axis.title/3` (the title of that side's aesthetic). Below the
panel: a `Scene.Polylines` of one two-point line per tick, from the tick's end up to the panel's edge, then a `Scene.Text` of
the labels centred on their ticks with their tops at the gap and their baselines an ascent below.
To its left: the labels ending at the gap, centred on their ticks with baselines half an ascent
below them, then the ticks. Below the panel the axis is as tall as tick, gap, ascent and descent;
to its left as wide as tick, gap and the widest label. A title's cell is as deep as its margin
and a line of its text; its text is anchored at its middle, at the cell's far edge, with its
baseline an ascent toward the axis. `grid(panel_params, theme)` asks `Coord.grid/1` for the
placed lines and returns, for the panel's cell, a `Scene.Rect` in the theme's `panel_background`
and four `Scene.Polylines` in `panel_grid_minor` and `panel_grid_major` (`Guide.Grid.draw/2`).
