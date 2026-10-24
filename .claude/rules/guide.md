---
paths:
  - "lib/giggly/guide.ex"
  - "lib/giggly/guide/**"
---

# Guides

`Giggly.Guide` is the protocol the guides of aesthetics other than position are drawn through, a
legend (`Guide.Legend`, ggplot2's `guide_legend()`) and a colour bar (`Guide.Colorbar`,
`guide_colourbar()` in its gradient form); its namespace also draws the axes
beside a panel and their titles (`Guide.Axis`, ggplot2's `guide_axis()`), the axis around a radial
panel's circle (`Guide.AxisTheta`, `guide_axis_theta()`), the panel's background and grid lines
(`Guide.Grid`, `guide_grid()`), the strips that label a facet's panels (`Guide.Strip`, which
ggplot2's facets draw with `render_strips()`), the box the legends stack in (`Guide.Box`,
`package_box()`), and the plot's own labels, its title, subtitle, caption and tag (`Guide.Title`),
which `labs()` sets. Why a protocol and why a scale names its guide: design-log §4, the entry
beginning "The guide protocol sits at `Giggly.Guide`"; why a domain of its own, and why it is called
a guide: the entry beginning "Axes are drawn"; which name titles an axis: the entry beginning "An
axis is titled"; why the grid is drawn here but placed by the coordinate system: the entry beginning "The
panel's grid lines are placed by the coordinate system".

## Rules

- **The root is a protocol and holds nothing else** (`defprotocol` allows only its functions):
  `draw/3` draws a guide of an aesthetic other than position, as a table of its own, for the box,
  its keys running the way rendering hands it (`direction`, `:vertical` or `:horizontal`).
  **A kind is one module**, its struct, whose fields are its parameters, and its drawing, in a
  `defimpl Giggly.Guide` whose first line classifies it into this boundary. A scale names its guide
  (`:axis` for a position, `:legend`, `:colorbar`, `:none`) or holds a legend's struct, which
  `Plot.guide_legend/1` builds, and `Plot.guides/2` names one by aesthetic over it; the assembly
  builds the kind's struct from a name. **A guide never sees a scale or calls a geom**: the
  assembly works out its keys from the scale, and rendering has each layer's geom draw its glyphs
  in them. The boundary exports the modules rendering draws with (`Axis`, `Box`, `Grid`, `Strip`,
  `Title`) and the kinds, whose structs the assembly and `Plot` build, never a kind's drawing;
  `Plot` may build a kind's struct and call nothing that draws (`PlotRunsNothing`). The parts both
  kinds' tables are built from (the background, the title and its room, a label's cell) are
  `Guide.Parts`, as ggplot2's colour bar lays itself out through its legend's layout, and so is the
  rule every text a guide draws is placed by.
- **Every text a guide draws is placed and measured by one rule in `Guide.Parts`, ggplot2's
  `titleGrob()`** (design-log §4, the entry beginning "Text's face, angle, justification and line
  height are the theme's"): drawn in its look's family and face, turned its `angle` and justified
  by its `hjust` and `vjust` in its own turned frame (`text/4`); anchored at its justification
  turned a quarter turn at a time (`turned_justification/1`, `rotate_just()`) of its room, moved by
  the margins it counts (`anchor/2`), as a share of the room and an offset in points, so it sits
  right in a room bigger than itself; and as wide and deep as grid's box round it turned, with the
  font's descent turned (`extent/2`), an axis's or a colour bar's labels measured together as one
  grob, whatever its family. A title may break over lines (the entry beginning "A title may run
  over several lines"): each line a label of its own, its `line_spacing` below the one before,
  stacked `vjust` of the way down from its top as R's graphics engine stacks lines; tick labels,
  strips and a legend's labels stay one line.
- **A guide takes its breaks and its axis's line from the coordinate system, already placed**
  (`Coord.axes/2`), so ticks and marks are placed by one rule. Where an axis is drawn, which
  aesthetic's title goes there, and the look it is drawn in are the coordinate system's call; a
  guide draws the sides it is given, in the looks it is given, with the titles it is handed by
  aesthetic. An axis the coordinate system puts inside the panel (`:theta`) is drawn by
  `Axis.draw_inside/3` over the panel's layers, takes no title of its own, and is neither measured
  nor given room, as ggplot2's `guide_axis_theta()` is not.
- **An axis's title is drawn by its guide, in a cell of its own beyond the axis**, as ggplot2 lays
  out its axis titles, counting its margins across the axis alone: `theme_gray()`'s centred on
  the panel's side, hanging from the cell's edge away from the axis, turned 90 degrees on the
  left. A title of `:none` draws nothing and takes no room; `""` takes a line's room and draws
  nothing.
- **The plot's labels are drawn by `Guide.Title`**, each counting its margins on every side, in a
  row as deep as it is turned and its margins, the tag in a cell as wide and as deep: as
  `theme_gray()` draws them, the title and the subtitle hanging left-aligned, the caption hanging
  right-aligned, the tag centred both ways. It reports each one's depth, and the tag's width, in
  points, for rendering to lay out; a label of `:none` takes no room.
- **The grid's lines and the background's shape come from the coordinate system** (`Coord.grid/2`):
  a background filling the panel is a rectangle, any other the polygon round its outline. The guide
  gives them the theme's look and ggplot2's order: the panel's background, the minor lines at the y
  axis's minor breaks, then the x axis's, then the major lines at the y axis's breaks, then the x
  axis's. A group with no lines is drawn as an empty primitive, which draws nothing.
- **A guide measures what it draws and reports how far it reaches from the panel, in points.**
  That is the fixed width or height of the axis's column or row in the scene, measured when the
  scene is built, as ggplot2's `measure_grobs` measures an axis while building its table.
- **Primitives are placed in the axis's cell.** Along the panel's side, at the break's place (the
  cell spans the side); across it, a label at fractions of the axis's own depth and a tick hung
  from the panel's edge, reaching its length in points, so ticks are drawn however deep the cell
  is, none deep included, as ggplot2 draws an unlabelled axis's ticks of no length. A label's
  baseline is offset from its anchor in points, since a label centred on a break sits half a line
  below it whatever height the panel turns out to be. The angle axis is placed in the panel's cell:
  each tick and label at its break on the circle's edge, offset outward along the break's angle in
  points, each label justified by that angle, as ggplot2 justifies it.
- **An axis's line runs along the panel's edge and takes no room**, as ggplot2's axis draws its
  line beside the table it measures: in the axis's cell, through the places along the side the
  coordinate system gives it, at the cell's edge against the panel, so a hanging axis's and an
  axis of no depth's are drawn there too; round a radial panel, through the circle's points in
  the panel's cell. A panel draws the lines of the axes it draws, as their ticks.
- **The look is the theme's** (`Giggly.Theme`), handed in by rendering already in points: the
  ticks' and lines' colour, opacity, width, end, dashes and length, the labels' and titles' size,
  colour, opacity, family and margin, the backgrounds' fill and border each at its opacity, **each
  axis's from the elements of its look and side** (`axis_text_x_bottom`, `axis_ticks_length_y_left`,
  a radius axis's `axis_text_r`, the angle axis's `axis_text_theta`), the grid's lines from the
  axis whose breaks they mark. **A text counts the sides of its margin ggplot2 counts**: tick
  labels and the axes' titles those across the axis (an x axis's above and below, a y axis's
  either side), the angle axis's labels the widest side, strips, the plot's titles and a legend's
  title and labels every side, a colour bar's labels those across the bar (either side of one
  running up, above and below one running across). **A negative tick
  length turns the ticks into the panel and takes no room**: an axis is measured from the longer
  of 0 and its ticks, as ggplot2 measures the range from 0. **An axis's labels are each at their
  break and across the axis at their turned justification of their room beyond the ticks**, the
  room as deep as all of them turned. **The angle axis's labels are turned by the theme and
  justified by their break's angle and that turn together, whatever justification the theme
  gives**, as `guide_axis_theta()` justifies them.
- **An axis with no breaks draws only its line and takes no room**, as ggplot2's exits early. **One
  whose scale has no labels** (`{place, :none}` breaks) **draws its ticks alone and reaches only as
  far as they do**, as ggplot2's `labels = NULL` leaves the labels' room out (2.74 points, the
  ticks' length, where labels make 13.37); around a radial panel, its ticks alone.
- **An element the theme removes (`:none`) draws nothing and takes no room.** Removed ticks count
  as no length beside the panel, as ggplot2's axis sets blank ticks' length to 0, but round a
  radial panel the labels keep their offset beyond them, as `guide_axis_theta()` keeps it; removed
  labels or a removed title draw as an axis, a legend or a colour bar given none
  (`Parts.labels/2`, `Parts.title/2`); a strip whose text is removed is not drawn, its background
  with it, and takes no room; a removed background, key background, group of grid lines or of
  ticks, or axis line draws nothing. **A line of the blank line type draws nothing but keeps its
  room** (`dashes: :blank`): blank ticks keep their length, as R's engine draws no such line.
- **Drawing order follows ggplot2's:** an axis's line first; below the panel the ticks and then
  the labels, to its left and round a radial panel's circle the labels and then the ticks, and
  round the circle the line last.
- **A strip is one label on a background as wide as its panel**, ggplot2's `label_value()` text
  placed by the rule counting its margins on every side, `theme_gray()`'s centred, as tall as its
  margins and the label turned, a level one an ascent and the deepest descent. A panel has one
  strip per facet column, top to bottom, each drawn alone, as ggplot2's `assemble_strips()`
  stacks them.
- **An axis is drawn per panel, its title once per plot.** `Axis.draw/3` draws one panel's axes;
  `Axis.titles/4` the plot's titles, from any panel's params, since every panel puts the same
  aesthetic on each side.
- **What waits for its first reader:** axes above or to the right, `guide_axis()`'s `angle` and
  its justification heuristic, dodged or thinned labels, `guide_axis()`'s `cap` cutting the axis
  line back to the breaks, minor ticks, axes as kinds of the protocol (ggplot2's `guide_axis()` is
  one, and `guides(x =)` would choose it),
  `guide_axis_theta()`'s options and merging its first and last labels when they meet (`expand =
  FALSE`), `guide_legend()`'s options but `reverse` (`title`, `order`, `position`,
  `direction`, `nrow`, `ncol`, `override.aes`, `theme`), the keys filled a row at a time
  (`legend.byrow`), titles and labels on other sides of the keys, and `guide_colourbar()`'s
  options: `nbin`, `reverse`, and its raster and rectangles displays.
- **A legend is a table of its own (`Guide.Legend`, drawn by `draw/3` as a nested
  `Giggly.Scene`), laid out as ggplot2's `GuideLegend` lays one out at its defaults**: the legend
  margin inside the edge; **the keys in a grid filled a column at a time**, one column for each
  twenty keys running down, one row for each five running across, as ggplot2's `setup_params()`
  shares them out (`ceiling(n / 20)` columns, `ceiling(n / 5)` rows); each key on the key
  background with each layer's glyph over it, its label in a cell of the labels' margin and
  column right of it, placed by the rule counting every side of its margin, `theme_gray()`'s
  left-aligned and centred on the key; **each row as tall as the theme's key height, its tallest
  glyph or its tallest label turned with the labels' margins above and below, and each column of
  keys as wide as the theme's key width or its widest glyph**, from the room each glyph needs,
  which rendering hands over with it (`Geom.key_size/2`), as ggplot2's `measure_legend_keys()`
  sizes them, each key's background
  filling its whole cell and its glyphs placed in it as drawn; each column of labels as wide as its
  widest label turned and the labels' right margin; `legend_key_spacing` between a column's labels
  and the next column, and between rows running across, none between rows running down, as ggplot2
  gives a vertical legend none unless `legend.key.spacing.y` is set. **The title above keys
  running down** (`legend_title_top`), in a row as deep as it and its margins spanning the keys'
  columns, **or left of keys running across** (`legend_title_left`), in a column spanning their
  rows, placed by the rule, `theme_gray()`'s left-aligned and centred down; **a title bigger than
  the keys and their labels leaves the rest of its room either side of them, split by its turned
  justification** (`Parts.title_above/3`, `title_column/3`, as `add_title()` adds columns or rows);
  a title of `:none` takes no room, as ggplot2 leaves out a `NULL` title. **With no labels (every
  key's `:none`), the labels' margins and columns take no room**, as ggplot2 leaves them out for a
  scale's `labels = NULL` (`Parts.label_widths/2` and `Parts.label_columns/3`, which the colour bar
  shares). Drawn in ggplot2's order: background, title, each key's background and glyphs, then the
  labels. Every size is in points. **Its one parameter, `reverse`, is the assembly's to apply**,
  handing the keys over last first, so the drawing takes them in the order given.
- **A plot's legends are stacked in a box (`Box.draw/3`), as ggplot2's `package_box()` stacks
  them**: in a column, `legend_spacing_y` apart, or a row, `legend_spacing_x` apart, as
  `legend_box` says, a row above or below the panels and a column elsewhere unless it is given;
  in the order given; each legend's point at the same point of its room by `legend_box_just`, or
  at its room's top, left in a column and centred in a row, by where the box goes whatever the
  arrangement, as ggplot2 justifies them (a `{:at, ...}` hang); `legend_box_margin` round them
  and `legend_box_background` under them, over the margin too. `Box.draw/3` takes the direction
  legends run where the box goes, which rendering works out once, and returns the box's width,
  height and table, which rendering places.
- **A colour bar is drawn as ggplot2's gradient form at its defaults** (`Guide.Colorbar`, design-log
  §4, the entry beginning "The colour bar is drawn as ggplot2's gradient form"): laid out as a
  legend, its one key row the bar, running up `legend.key.width` wide and five keys long
  (`legend.key.height` times 5), or across five keys long and a key tall; the bar a
  `Scene.Gradient` through the colours the assembly sampled (`bins`, 15, ggplot2's `nbin` for the
  gradient form), from its bottom or its left, the scale's low end, to its top or its right, with
  no border; a tick in the theme's colour bar ticks (white unless the theme sets them)
  `legend.ticks.length` into each side at each break's place, the right side's and then the
  left's, or the bottom's and then the top's, each drawn from inside the bar outward; the labels
  at their ticks, placed by the rule, right of a bar running up (`legend_text_right`, left-aligned
  and centred on the tick unless set) or below one running across (`legend_text_bottom`, centred
  and hung), measured together as one grob; the title above or left of the bar as a legend's, its
  room split alike; and with no labels the ticks alone, the room laid out as a legend's. It draws no
  layer's glyph.
