---
paths:
  - "lib/giggly/guide.ex"
  - "lib/giggly/guide/**"
---

# Guides

`Giggly.Guide` is the protocol the guides of aesthetics other than position are drawn through, a
legend (`Guide.Legend`, ggplot2's `guide_legend()`) so far; its namespace also draws the axes
beside a panel and their titles (`Guide.Axis`, ggplot2's `guide_axis()`), the axis around a radial
panel's circle (`Guide.AxisTheta`, `guide_axis_theta()`), the panel's background and grid lines
(`Guide.Grid`, `guide_grid()`), the strips that label a facet's panels (`Guide.Strip`, which
ggplot2's facets draw with `render_strips()`), and the box the legends stack in (`Guide.Box`,
`package_box()`). Why a protocol and why a scale names its guide: design-log §4, the entry
beginning "The guide protocol sits at `Giggly.Guide`"; why a domain of its own, and why it is called
a guide: the entry beginning "Axes are drawn"; which name titles an axis: the entry beginning "An
axis is titled"; why the grid is drawn here but placed by the coordinate system: the entry beginning "The
panel's grid lines are placed by the coordinate system".

## Rules

- **The root is a protocol and holds nothing else** (`defprotocol` allows only its functions):
  `draw/3` draws a guide of an aesthetic other than position, as a table of its own, for the box.
  **A kind is one module**, its struct, whose fields are its parameters, and its drawing, in a
  `defimpl Giggly.Guide` whose first line classifies it into this boundary. A scale names its guide
  (`:axis` for a position, `:legend`), and the assembly builds the kind's struct. **A guide never
  sees a scale or calls a geom**: the assembly works out its keys from the scale, and rendering has
  each layer's geom draw its glyphs in them. The boundary exports the modules rendering draws with
  (`Axis`, `Box`, `Grid`, `Strip`) and the kinds, whose structs the assembly builds, never a kind's
  drawing.
- **A guide takes its breaks from the coordinate system, already placed** (`Coord.axes/2`), so
  ticks and marks are placed by one rule. Where an axis is drawn, which aesthetic's title goes
  there, and the look it is drawn in are the coordinate system's call; a guide draws the sides it
  is given, in the looks it is given, with the titles it is handed by aesthetic. An axis the
  coordinate system puts inside the panel (`:theta`) is drawn by `Axis.draw_inside/3` over the
  panel's layers, takes no title of its own, and is neither measured nor given room, as ggplot2's
  `guide_axis_theta()` is not.
- **An axis's title is drawn by its guide, in a cell of its own beyond the axis**, as ggplot2 lays
  out its axis titles: centred on the panel's side, hanging from the cell's edge away from the
  axis, turned 90 degrees on the left. A title of `:none` draws nothing and takes no room.
- **The grid's lines and the background's shape come from the coordinate system** (`Coord.grid/2`):
  a background filling the panel is a rectangle, any other the polygon round its outline. The guide
  gives them the theme's look and ggplot2's order: the panel's background, the minor lines at the y
  axis's minor breaks, then the x axis's, then the major lines at the y axis's breaks, then the x
  axis's. A group with no lines is drawn as an empty primitive, which draws nothing.
- **A guide measures what it draws and reports how far it reaches from the panel, in points.**
  That is the fixed width or height of the axis's column or row in the scene, measured when the
  scene is built, as ggplot2's `measure_grobs` measures an axis while building its table.
- **Primitives are placed in the axis's cell.** Along the panel's side, at the break's place (the
  cell spans the side); across it, at fractions of the axis's own depth. A label's baseline is
  offset from its anchor in points, since a label centred on a break sits half a line below it
  whatever height the panel turns out to be. The angle axis is placed in the panel's cell: each
  tick and label at its break on the circle's edge, offset outward along the break's angle in
  points, each label justified by that angle, as ggplot2 justifies it.
- **The look is the theme's** (`Giggly.Theme`), handed in by rendering already in points: the
  ticks' colour, width and length, the labels' and titles' size, colour and margin. How a label is
  hung from its tick, the radius axis's labels centred between two margins (`axis.text.r`), the
  angle axis's labels justified by their angles, and the y title's 90-degree turn are the guide's
  until a theme can set them.
- **An axis with no breaks draws nothing and takes no room**, as ggplot2's exits early.
- **Drawing order follows ggplot2's:** below the panel the ticks and then the labels, to its left
  and round a radial panel's circle the labels and then the ticks.
- **A strip is one label on a background as wide as its panel**, ggplot2's `label_value()` text
  centred, its baseline half an ascent below the middle, the strip text's margin above and below a
  line of text, so it is as tall as the margin twice, an ascent and the deepest descent. A panel
  has one strip per facet column, top to bottom, each drawn alone, as ggplot2's `assemble_strips()`
  stacks them.
- **An axis is drawn per panel, its title once per plot.** `Axis.draw/3` draws one panel's axes;
  `Axis.titles/4` the plot's titles, from any panel's params, since every panel puts the same
  aesthetic on each side.
- **What waits for its first reader:** axes above or to the right, angled, dodged or thinned
  labels, the axis line (blank in `theme_grey()`), minor ticks, a title set by `labs/2`, axes as
  kinds of the protocol (ggplot2's `guide_axis()` is one, and `guides(x =)` would choose it), and
  `guide_axis_theta()`'s options and merging its first and last labels when they meet (`expand =
  FALSE`).
- **A legend is a table of its own (`Guide.Legend`, drawn by `draw/3` as a nested
  `Giggly.Scene`), laid out as ggplot2's `GuideLegend` lays out a vertical legend at its
  defaults**: the legend margin inside
  the edge; the title above, as tall as a line of its text, left-aligned and centred down its row
  by half its ascent, as grid centres text, the title's margin below; a row per key, the key
  square on the key background with each layer's glyph over it, its label the text margin to its
  right, centred as the title is; the label column as wide as the widest label, or wider when the
  title is, leaving the room at the labels' right. Drawn in ggplot2's order: background, title,
  each key's background and glyphs, then the labels. Every size is in points.
- **A plot's legends are stacked in a box (`Box.draw/2`), as ggplot2's `package_box()` stacks them
  on the right**: a column as wide as the widest legend, each in a row as tall as it is, in the
  order given, `legend.spacing.y` between, each hung from the column's left (`legend.box.just`,
  left and top), with no margin or background of its own (`theme_gray()`'s); `Box.draw/2` returns
  the box's width and its table, which rendering centres down the panels.
