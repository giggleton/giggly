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
- **The document's unit is the point, written as svglite writes it:** `width` and `height` in `pt`,
  a `viewBox` of the size in points, positions with two decimals, circles with `cx`/`cy`/`r` and a
  `style` of `stroke-width`, `stroke`, `stroke-opacity`, `fill` and `fill-opacity`, rectangles with
  `x`, `y`, `width` and `height` and a `style` of `stroke-width`, `stroke` (`none` for no border),
  the dashes below and `fill` (`none` for no fill), placed rectangles likewise, hung from their
  top left corner as grid hangs ggplot2's bars, whichever way round their corners are given, as
  svglite writes one, a `stroke-opacity` after the `stroke`, the line style below before the
  `fill` (`stroke-linecap: butt; stroke-linejoin: miter` for `GeomRect`'s, none for a point's
  square), and a `fill-opacity` after it, polygons with `points` and a `style` of
  `stroke-width`, `stroke`, `stroke-opacity`, the
  dashes and line style below (`stroke-linecap: butt; stroke-linejoin: miter` for a box plot's
  box, none for a point's polygon or a radial background), `fill` and `fill-opacity`, polylines
  with `points` and a `style` of `stroke-width`, `stroke` and `stroke-opacity`, the line style
  below, and `fill: none`, segments as `<line>` with `x1`, `y1`,
  `x2` and `y2` and the same `style` but `fill`, and text with `x` and `y` (or, turned,
  `transform='translate(x,y) rotate(-angle)'`, the angle in whole degrees as vdiffr writes it with
  `%0.0f`, a tie to the even one), `text-anchor` (left out for text anchored at its start, as
  svglite leaves it out), a `style` of `font-size` (in `px`, the user unit), the face as vdiffr
  writes it (`font-weight: bold;`, `font-style: italic;`, both for bold italic), `fill` and
  `fill-opacity` (left out for opaque black, SVG's default, as vdiffr leaves it out) and
  `font-family`, and `textLength` with `lengthAdjust='spacingAndGlyphs'`. Output can then be set
  beside the SVG in ggplot2's own visual-test snapshots.
- **A gradient is written as svglite writes one**: a `<defs>` of its own holding a
  `<linearGradient>` (`gradientUnits='userSpaceOnUse'`, `spreadMethod='pad'`) from the rectangle's
  bottom edge to its top at its middle, or from its left edge to its right for one running across,
  in the drawing's points, each `<stop>` at its offset,
  written as an opacity is between 0 and 1 and with two decimals at the ends, in its colour,
  `stop-opacity='1.00'`; then the `<rect>` filled `url(#…)` and stroked `none`. **Its id comes from
  its content**, `lg` and the MD5 of what the gradient holds, where svglite's counts up from
  `pat-0`, so two drawings on one page share an id only when they share the gradient.
- **Each mark is written in its own colour and opacity**, as svglite writes each element's own
  `gp`, so a mapped colour needs no element of its own per value.
- **A dashed line is written as svglite writes R's line type**: `stroke-dasharray` right after
  its stroke and the stroke's opacity, before its ends and corners, each length in points with two
  decimals, joined by commas, written on a border of no colour too, as svglite writes it whatever
  the colour; a solid line writes none, SVG's default.
- **An opacity is written as svglite writes the alpha of an R colour**: R holds it as a byte, the
  opacity times 255 rounded half to even, and svglite writes the byte over 255 as it writes any
  number below 1 (`write_double()`), with as many decimals as reach its first significant digit
  and one more (`0.024`, `0.0078`, from 0.1 up two), or nothing for 255, opaque. So 0.998 is
  written `1.00`, and 0.999 not at all. **A stroke's width, a circle's radius and a gradient stop's
  offset are written as svglite writes any number** (`0.040` for a line 0.04 points wide), as are
  opacities; **a position or an extent keeps two decimals**, though svglite writes one below 0.1
  with more, since a position that near 0 is layout's rounding error, which grid's arithmetic and
  Giggly's leave apart (5.7e-14 for grid's 0 at a radial panel's top). **No colour,
  `:none`, or a wholly transparent one, byte 0, is a stroke of `none` and a fill of `none`**; the
  element is still written. svglite skips such a fill and its stylesheet makes it `none`; without
  that stylesheet SVG fills a shape black, so Giggly writes `fill: none`.
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
  the whole drawing, around everything else, does nothing visible and is left out. **Clipped
  cells in a row that share a box are one group, and a box's clip path is defined once**, where
  it is first used, a later group naming it again, as svglite starts a group only where the
  clipping changes and writes each clip path once: theme_void()'s panel, filling the drawing,
  shares the background's group.
- **A label is drawn at the width `Giggly.Font` measured** (`textLength`), so the drawing agrees
  with the layout whatever font the browser picks. **Its `font-family` is written by its family**
  (design-log §4, the entry beginning "A text's family is the theme's"): `""` and R's `"sans"` the
  fonts with those widths (`"Liberation Sans", Arial, Helvetica`) and then `sans-serif`, never
  vdiffr's `sans`, which is not a CSS generic family; R's `"serif"` and `"mono"` CSS's `serif` and
  `monospace`; any other name, R's `"symbol"` included, a CSS string, its quotes and backslashes
  escaped for CSS and the whole for the attribute, then the default list, for a browser that lacks
  it. Each is drawn at the measured width all the same, and so is a bold or italic label, measured
  as plain text, as vdiffr measures every face but the symbol one. **An empty label is not
  written**, as svglite writes none, though the room measured for it stays. Text escapes `&`, `<`
  and `>`, as svglite does.
- **A text checking overlap is drawn as grid's `textGrob(check.overlap = TRUE)` draws one**: each
  label's box placed and turned with it, in order, and left out when an edge of it crosses an edge
  of a box drawn before (`intersect()`): two edges along one line cross where they overlap, two
  others only where each passes strictly between the other's ends (`linesIntersect()`), so a box
  wholly inside another crosses nothing, as grid's does not.
- **The backend measures nothing.** Every size reaches it as points or as a share.
- **The root declares svglite's stylesheet for lines as attributes: `stroke-linecap='round'
  stroke-linejoin='round' stroke-miterlimit='10.00'`**, which every element inherits and any CSS
  outranks (design-log §4, the entry beginning "The document's root declares"). So a line writes
  only what svglite writes: `stroke-linecap` when its ends are not round, `stroke-linejoin` when its
  corners are not round (`miter`, `bevel`), and `stroke-miterlimit` only for mitred corners whose
  limit is not 10.
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
  not (its XML declaration, stylesheet, page rectangle and clip groups), the font list, which
  vdiffr writes `sans` for every family, and a
  black stroke and a `fill: none`, which svglite leaves to its stylesheet; a golden with lines
  compares `<line>` elements too. **vdiffr's device draws no gradient**, and writes a colour bar's
  rectangle unfilled: that `fill` is the one difference there, and the gradient is checked against
  svglite 2.2.2's own drawing (the Docker image `giggly-r:ggplot2-4.0.3-svglite`, with the
  Liberation fonts), its stops line for line and its ends against its own rectangle, since svglite
  measures with the font files and sits a hundredth of a point from vdiffr.
  Any other difference is a finding or a stated departure, named in the script's header: the
  plain plot's axes drawn in the other order, a background edge written as R's rounding error.
- **A nested scene is laid out in its cell's box as the whole scene is in the drawing**, from the
  box's top left, its sizes in points taking their length and its shares what is left; its cells
  are then written as any other. **A cell's box is worked out by the generic table code before
  anything is written** (`hang/2`, every hang form, `{:at, ...}` as grid places a viewport), the
  layout a second backend would share; nothing that writes a primitive places a legend.
