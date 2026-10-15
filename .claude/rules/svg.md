---
paths:
  - "lib/giggly/svg.ex"
  - "test/golden/**"
---

# The SVG backend

`Giggly.SVG` draws a `Giggly.Scene` as an SVG document at the size it is handed. Why it follows
svglite: design-log §4, the entry beginning "The coordinate system arrives with drawing"; why
`to_svg/2` sizes a drawing in pixels: the entry beginning "A plot is drawn at the size it is
given"; why labels are drawn at their measured widths, and in which fonts: the entry beginning
"Axes are drawn"; why a scene keeping its proportions is centred: the entry beginning "A `:rest`
size has a weight".

## Rules

- **SVG reads only the scene.** Its boundary lists `Giggly.Scene` alone; everything about a plot
  reaches it as primitives.
- **The output is the product, so its strings are behaviour.** An attribute, an element or a
  number's format that changes changes the golden; a surviving mutant in a literal here is a
  finding, never message wording.
- **The document's unit is the point, written as svglite writes it:** `width` and `height` in
  `pt`, a `viewBox` of the size in points, numbers with two decimals, circles with
  `cx`/`cy`/`r` and a `style` of `stroke-width`, `stroke` and `fill`, rectangles with `x`, `y`,
  `width` and `height` and a `style` of `stroke-width`, `stroke` (`none` for no border) and
  `fill`, placed rectangles likewise, hung from their top left corner as grid hangs ggplot2's
  bars, with `stroke-linecap: butt; stroke-linejoin: miter` before the `fill`, as `GeomRect` sets
  them, polygons with `points` and the same `style` as rectangles, polylines with `points` and
  a `style` of `stroke-width`, `stroke`, `stroke-linecap: butt` and `fill: none`, and text with
  `x` and `y` (or, turned 90 degrees, `transform='translate(x,y) rotate(-90)'`), `text-anchor`
  (left out for text anchored at its start, as svglite leaves it out), a `style` of `font-size`
  (in `px`, the user unit), `fill` (left out for black, SVG's default, as svglite leaves it
  out) and `font-family`, and `textLength` with `lengthAdjust='spacingAndGlyphs'`. Output can
  then be set beside the SVG in ggplot2's own visual-test snapshots.
- **The table is laid out as grid lays out a layout.** Shares split what the sizes in points
  leave by weight; a scene keeping its proportions gives each share its weight over the weights
  of the way that runs out first, times what that way leaves, as grid allocates a respected
  layout's null units, and centres the table both ways. A table that does not keep its
  proportions starts at the drawing's edge, where grid writes its rounding error.
- **Text is anchored as R's graphics engine anchors it for svglite**, which writes only a start,
  middle or end: at the nearest of those to its `hjust`, moved along its baseline by the rest of
  its width.
- **A clipped cell is written as svglite writes a clipping viewport**: a `<defs>` holding a
  `<clipPath>` of the cell's box, then its primitives in a `<g clip-path='url(#…)'>`. The id is
  svglite's, `cp` and the base64 of the box's `left|right|top|bottom` to two decimals, so two
  drawings inlined on one page share an id only when they share the box and cannot clip each
  other wrongly. The plot's background is clipped to the table, so when the table fills the
  drawing its group is clipped to the whole drawing, as svglite's is. svglite's group clipped to
  the whole drawing, around everything else, does nothing visible and is left out.
- **A label is drawn at the width `Giggly.Font` measured** (`textLength`), so the drawing agrees
  with the layout whatever font the browser picks. Its `font-family` lists the fonts with those
  widths (`"Liberation Sans", Arial, Helvetica`) and then `sans-serif`, never vdiffr's `sans`,
  which is not a CSS generic family. Text escapes `&`, `<` and `>`, as svglite does.
- **The backend measures nothing.** Every size reaches it as points or as a share.
- **A polyline is never filled**, as grid's never is: its `style` says `fill: none`, which
  svglite leaves to a stylesheet Giggly does not write, since a stylesheet in an inlined SVG
  styles the whole page; without it SVG would fill a closed line, a radial grid's circle, black.
- **A golden is drawn at vdiffr's size, 960 by 768 pixels (720 by 576 points)**, passed to
  `to_svg/2` explicitly, so it can be set beside ggplot2's own snapshots whatever the default.
- **A golden changes only on purpose, checked against ggplot2's drawing of the same plot.**
  `test/golden/` holds whole documents compared byte for byte; a change to one is reviewed as a
  change to the product. Beside each golden is the R script that draws its plot with ggplot2 and
  vdiffr (`test/golden/*.R`), never run by the suite; its header gives the Docker command
  and the element-by-element comparison, which leaves out only what svglite writes and Giggly does
  not (its XML declaration, stylesheet, page rectangle and clip groups), the font list, and a
  circle's black stroke and a polyline's `fill: none`, which svglite leaves to its stylesheet.
  Any other difference is a finding or a stated departure, named in the script's header: the
  plain plot's axes drawn in the other order, a background edge written as R's rounding error.
