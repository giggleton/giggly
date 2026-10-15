---
paths:
  - "lib/giggly/scene.ex"
  - "lib/giggly/scene/**"
---

# The scene

`Giggly.Scene` is what a plot draws, independent of any output format: a table whose cells hold
primitives. Why it is a table from the first drawing: design-log §4, the entry beginning "The
coordinate system arrives with drawing"; why sizes are measured when it is built and what waits:
the entry beginning "Axes are drawn"; why there is a scene between rendering and SVG at all: the
entry beginning "Three top-level values".

## Rules

- **A scene is values and calls nothing.** Its boundary lists nothing and exports the structs
  rendering builds and a backend reads (`Cell`, `Circles`, `Polylines`, `Rect`, `Text`); nothing in
  it knows SVG, a font or a theme.
- **A column's width or a row's height is a number of points or `:rest`.** A size in points is
  measured when the scene is built (an axis, a margin); `:rest` is a share of what the fixed sizes
  leave of the drawing, which a panel takes (grid's `"null"` unit): the columns that are `:rest`
  share the width equally, and the rows the height, so every panel is one size. Weights arrive
  with the first panels of different sizes (`space = "free"`, an aspect ratio). Nothing is
  measured later, so a backend needs no font. The docs say widths and heights, not "tracks".
- **A cell's box is its rows and columns, unless it hangs.** `hang: {:top, height}` makes the box
  `height` points tall from the top of its rows, and `hang: {:right, width}` `width` points wide
  ending at the right of its columns, whatever they measure: ggplot2 measures an axis below a
  panel with an empty cell under it as taking no room, and the axis hangs into the empty space;
  and a left axis narrower than its column (free y scales) sits against its panel. Every bottom
  axis hangs from its panel's edge at its own height, and every left axis at its own width, which
  are the row's and the column's when it is the one that measures them.
- **Primitives are placed in their cell's units, 0 to 1 across and up, and sized in points.** A
  primitive never knows the cell's size; the backend places it in the cell's box. The one position
  in points is a text's `baseline_offset`, from its anchor to its baseline.
- **A text carries each label's measured width**, which the backend draws it at.
- **A cell spans a range of rows and a range of columns, counting from 1, and cells are drawn in
  the order listed.** Most span one of each; the plot's background spans the whole table (gtable's
  `t`, `l`, `b` and `r`). Names, z-order beyond list order and aspect ratio arrive with their first
  reader.
- **Every cell says whether it is clipped, `:on` or `:off`**, as gtable's `clip` does: what is
  drawn in a clipped cell is cut off at its box. Only the panel's is `:on`, when its coordinate
  system clips it.
- **A rectangle fills its cell**, as grid's `rectGrob()` does at its default place and size, which
  is how ggplot2 draws a background; a rectangle placed and sized within its cell arrives with the
  first geom that draws one (bars).

## How it works

`%Giggly.Scene{}` holds the column widths (left to right), the row heights (top to bottom), each
`{:points, size}` or `:rest`, and the cells. `Scene.Cell` holds the ranges of rows and columns it
spans, whether it is clipped, whether it hangs (`:none`, `{:top, height}` or `{:right, width}`),
and its primitives in drawing order. The primitives are named after
grid's: `Scene.Circles` (`circleGrob()`: positions, one radius, one outline width, one colour; what
R's graphics engine draws for shape 19, ggplot2's default point), `Scene.Polylines`
(`polylineGrob()`: lines of `{x, y}` points, one stroke width and colour, square-cut ends),
`Scene.Rect` (`rectGrob()` filling its cell: a fill, a border colour or `:none`, and the border's
width) and `Scene.Text` (`textGrob()`: positions, labels and their measured widths, one size and
colour, an angle of 0 or 90 degrees, an anchor of `:middle` or `:end`, and the baseline offset,
measured toward the text's top, which is to the left for text turned 90 degrees).
