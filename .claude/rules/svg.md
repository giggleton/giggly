---
paths:
  - "lib/giggly/svg.ex"
  - "test/golden/**"
---

# The SVG backend

`Giggly.SVG` draws a `Giggly.Scene` as an SVG document. Why it follows svglite and draws at
720 by 576 points: design-log §4, the entry beginning "The coordinate system arrives with
drawing".

## Rules

- **SVG reads only the scene.** Its boundary lists `Giggly.Scene` alone; everything about a plot
  reaches it as primitives.
- **The output is the product, so its strings are behaviour.** An attribute, an element or a
  number's format that changes changes the golden; a surviving mutant in a literal here is a
  finding, never message wording.
- **The document's unit is the point, written as svglite writes it:** `width` and `height` in
  `pt`, a `viewBox` of the size in points, numbers with two decimals, circles with
  `cx`/`cy`/`r` and a `style` of `stroke-width`, `stroke` and `fill`. Output can then be set
  beside the SVG in ggplot2's own visual-test snapshots.
- **A golden changes only on purpose.** `test/golden/` holds whole documents compared byte for
  byte; a change to one is reviewed as a change to the product, with the positions it shows
  checked independently.

## How it works

`draw(scene, width, height)` takes the one-cell scene (one row track, one column track, the cell
at row 1 and column 1), whose cell is the whole drawing, and writes each primitive in it: a
point at `(x * width, (1 - y) * height)`, since a cell's y runs up and SVG's runs down. Any other
scene raises `FunctionClauseError` until tracks can share the drawing. It returns iodata.
`Giggly.to_svg/1` draws at 720 by 576 points, the size of ggplot2's snapshots (vdiffr's default),
until a size can be given.
