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
  rendering builds and a backend reads (`Cell`, `Points`, `Polylines`, `Text`); nothing in it
  knows SVG or a font.
- **A column's width or a row's height is a number of points or `:rest`.** A size in points is
  measured when the scene is built (an axis, a margin); `:rest` is what the fixed sizes leave of
  the drawing, which the panel takes (grid's `"null"` unit). Exactly one column and one row are
  `:rest` until `facet_wrap` brings panels to share it, by weight; `SVG.draw/3` refuses any other
  shape. Nothing is measured later, so a backend needs no font. The docs say widths and heights,
  not "tracks".
- **Primitives are placed in their cell's units, 0 to 1 across and up, and sized in points.** A
  primitive never knows the cell's size; the backend places it in the cell's box. The one position
  in points is a text's `baseline_offset`, from its anchor to its baseline.
- **A text carries each label's measured width**, which the backend draws it at.
- **A cell sits at a row and a column, counting from 1, and cells are drawn in the order listed.**
  Spanning cells, names, clipping, z-order beyond list order and aspect ratio arrive with their
  first reader.

## How it works

`%Giggly.Scene{}` holds the column widths (left to right), the row heights (top to bottom), each
`{:points, size}` or `:rest`, and the cells. `Scene.Cell` holds a row, a column and its
primitives in drawing order. The primitives are named after grid's: `Scene.Points`
(`pointsGrob()` for shape 19: positions, one radius, one outline width, one colour),
`Scene.Polylines` (`polylineGrob()`: lines of `{x, y}` points, one stroke width and colour,
square-cut ends) and `Scene.Text` (`textGrob()`: positions, labels and their measured widths, one
size and colour, an angle of 0 or 90 degrees, an anchor of `:middle` or `:end`, and the baseline
offset, measured toward the text's top, which is to the left for text turned 90 degrees).
