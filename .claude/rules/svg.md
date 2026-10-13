---
paths:
  - "lib/giggly/svg.ex"
  - "test/golden/**"
---

# The SVG backend

`Giggly.SVG` draws a `Giggly.Scene` as an SVG document. Why it follows svglite and draws at
720 by 576 points: design-log §4, the entry beginning "The coordinate system arrives with
drawing"; why labels are drawn at their measured widths, and in which fonts: the entry beginning
"Axes are drawn".

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
  `fill`, polylines with `points`
  and a `style` of `stroke-width`, `stroke` and `stroke-linecap: butt`, and text with `x` and
  `y` (or, turned 90 degrees, `transform='translate(x,y) rotate(-90)'`), `text-anchor`, a
  `style` of `font-size` (in `px`, the user unit), `fill` (left out for black, SVG's default,
  as svglite leaves it out) and `font-family`, and `textLength` with
  `lengthAdjust='spacingAndGlyphs'`. Output can then be set beside the SVG
  in ggplot2's own visual-test snapshots.
- **A label is drawn at the width `Giggly.Font` measured** (`textLength`), so the drawing agrees
  with the layout whatever font the browser picks. Its `font-family` lists the fonts with those
  widths (`"Liberation Sans", Arial, Helvetica`) and then `sans-serif`, never vdiffr's `sans`,
  which is not a CSS generic family. Text escapes `&`, `<` and `>`, as svglite does.
- **The backend measures nothing.** Every size reaches it as points or as `:rest`.
- **A polyline's fill is left unset**, which SVG fills black: ticks have no area, so it shows
  nothing; the first polyline with area (a path geom) sets `fill: none`.
- **A golden changes only on purpose, checked against ggplot2's drawing of the same plot.**
  `test/golden/` holds whole documents compared byte for byte; a change to one is reviewed as a
  change to the product. Beside each golden is the R script that draws its plot with ggplot2 and
  vdiffr (`point.R`), never run by the suite; its header gives the Docker command and the
  element-by-element comparison, which leaves out only what svglite writes and Giggly does not (its
  XML declaration, stylesheet, page rectangle and clip groups), the font list, and a circle's
  black stroke. Any other difference is a finding or a stated departure.

## How it works

`draw(scene, width, height)` lays the columns out across `width` and the rows down `height`:
each size in points takes its length, and the one `:rest` takes what they leave; a scene with
none or several in a direction raises `MatchError`. Each cell's box runs from its first column's
and row's start to its last one's end, a rectangle fills it, and each other primitive is written in it
at `(left + x * box_width, top + (1 - y) * box_height)`, since a cell's y runs up and SVG's runs
down; a label's baseline is a further `baseline_offset` points toward its top, which is up for
level text and left for text turned 90 degrees. It returns iodata.
`Giggly.to_svg/1` draws at 720 by 576 points, the size of ggplot2's snapshots (vdiffr's default),
until a size can be given.
