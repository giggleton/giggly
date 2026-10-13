---
paths:
  - "lib/giggly/guide.ex"
  - "lib/giggly/guide/**"
---

# Guides

`Giggly.Guide` draws the axes beside a panel, ggplot2's `guide_axis()`. Why a domain of its own,
and why it is called a guide: design-log §4, the entry beginning "Axes are drawn".

## Rules

- **A guide takes its breaks from the coordinate system, already placed** (`Coord.axes/1`), so
  ticks and marks are placed by one rule. Which side of the panel an axis is drawn on is the
  coordinate system's call; a guide draws the sides it is given.
- **A guide measures what it draws and reports how far it reaches from the panel, in points.**
  That is the fixed width or height of the axis's column or row in the scene, measured when the
  scene is built, as ggplot2's `measure_grobs` measures an axis while building its table.
- **Primitives are placed in the axis's cell.** Along the panel's side, at the break's place (the
  cell spans the side); across it, at fractions of the axis's own depth. A label's baseline is the
  one position in points, offset from its anchor, since a label centred on a break sits half a
  line below it whatever height the panel turns out to be.
- **The look is `theme_grey()`'s, held as module attributes until a theme can be set.** ggplot2
  gives lengths in TeX points, converted here by 72 / 72.27; line widths in millimetres, drawn as
  `.pt` line-width units of 1/96 inch.
- **An axis with no breaks draws nothing and takes no room**, as ggplot2's exits early.
- **Drawing order follows ggplot2's:** below the panel the ticks and then the labels, to its left
  the labels and then the ticks.
- **What waits for its first reader:** axis titles (the next step), axes above or to the right,
  angled, dodged or thinned labels, the axis line (blank in `theme_grey()`), minor ticks, and a
  guide behaviour (the first legend).

## How it works

`axes(panel_params)` asks `Coord.axes/1` for each side's placed breaks and hands each to
`Guide.Axis.draw/2`, which returns `{size, primitives}`. Below the panel: a `Scene.Polylines` of
one two-point line per tick, from the tick's end up to the panel's edge, then a `Scene.Text` of
the labels centred on their ticks with their tops at the gap and their baselines an ascent below.
To its left: the labels ending at the gap, centred on their ticks with baselines half an ascent
below them, then the ticks. Below the panel the axis is as tall as tick, gap, ascent and descent;
to its left as wide as tick, gap and the widest label.
