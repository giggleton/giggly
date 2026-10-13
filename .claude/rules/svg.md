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
  `cx`/`cy`/`r` and a `style` of `stroke-width`, `stroke` and `fill`, polylines with `points`
  and a `style` of `stroke-width`, `stroke` and `stroke-linecap: butt`, and text with `x`, `y`,
  `text-anchor`, a `style` of `font-size` (in `px`, the user unit), `fill` and `font-family`,
  and `textLength` with `lengthAdjust='spacingAndGlyphs'`. Output can then be set beside the SVG
  in ggplot2's own visual-test snapshots.
- **A label is drawn at the width `Giggly.Font` measured** (`textLength`), so the drawing agrees
  with the layout whatever font the browser picks. Its `font-family` lists the fonts with those
  widths (`"Liberation Sans", Arial, Helvetica`) and then `sans-serif`, never vdiffr's `sans`,
  which is not a CSS generic family. Text escapes `&`, `<` and `>`, as svglite does.
- **The backend measures nothing.** Every size reaches it as points or as `:rest`.
- **A polyline's fill is left unset**, which SVG fills black: ticks have no area, so it shows
  nothing; the first polyline with area (a path geom) sets `fill: none`.
- **A golden changes only on purpose.** `test/golden/` holds whole documents compared byte for
  byte; a change to one is reviewed as a change to the product, with the positions it shows
  checked independently.

## How it works

`draw(scene, width, height)` lays the columns out across `width` and the rows down `height`:
each size in points takes its length, and the one `:rest` takes what they leave; a scene with
none or several in a direction raises `MatchError`. Each cell's box is its column's and row's span, and each primitive is written in it
at `(left + x * box_width, top + (1 - y) * box_height)`, since a cell's y runs up and SVG's runs
down; a label's baseline is a further `baseline_offset` points up. It returns iodata.
`Giggly.to_svg/1` draws at 720 by 576 points, the size of ggplot2's snapshots (vdiffr's default),
until a size can be given.
