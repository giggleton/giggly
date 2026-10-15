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
entry beginning "Three top-level values"; why a position can be offset in points: the entry
beginning "A primitive's position is a place in its cell plus an offset in points"; why a share
has a weight and a scene can keep its proportions: the entry beginning "A `:rest` size has a
weight".

## Rules

- **A scene is values and calls nothing.** Its boundary lists nothing and exports the structs
  rendering builds and a backend reads (`Cell`, `Circles`, `Polygons`, `Polylines`, `Rect`,
  `Text`); nothing in it knows SVG, a font or a theme.
- **A column's width or a row's height is a number of points or a share, `{:rest, weight}`.** A
  size in points is measured when the scene is built (an axis, a margin); a share is a part of
  what the fixed sizes leave of the drawing, which a panel takes (grid's `"null"` unit): the
  shares split the width, and the height, in proportion to their weights. **A scene that keeps
  its proportions** (`keep_proportions`, gtable's `respect`) gives every share one scale, the
  largest that fits both ways, so a panel keeps the shape its weights give it, and the table is
  centred in the drawing, its background covering the table alone. Nothing is measured later, so
  a backend needs no font. The docs say widths and heights, not "tracks".
- **A cell's box is its rows and columns, unless it hangs.** `hang: {:top, height}` makes the box
  `height` points tall from the top of its rows, and `hang: {:right, width}` `width` points wide
  ending at the right of its columns, whatever they measure: ggplot2 measures an axis below a
  panel with an empty cell under it as taking no room, and the axis hangs into the empty space;
  and a left axis narrower than its column (free y scales) sits against its panel. Every bottom
  axis hangs from its panel's edge at its own height, and every left axis at its own width, which
  are the row's and the column's when it is the one that measures them.
- **Primitives are placed in their cell's units, 0 to 1 across and up, offset from there in
  points, and sized in points**, as grid adds a unit in points to one in the viewport's own. A
  primitive never knows the cell's size; the backend places it in the cell's box and moves it by
  its offset: a polyline's points by their `offsets`, `{across, up}` (`:none` for none), and a
  text's anchor by its `offset`, `{along, up}` in the text's own frame. A text's anchor is at its
  `hjust` of the label's width, any fraction from its start (0) to its end (1).
- **A text carries each label's measured width**, which the backend draws it at.
- **A cell spans a range of rows and a range of columns, counting from 1, and cells are drawn in
  the order listed.** Most span one of each; the plot's background spans the whole table (gtable's
  `t`, `l`, `b` and `r`). Names and z-order beyond list order arrive with their first reader.
- **Every cell says whether it is clipped, `:on` or `:off`**, as gtable's `clip` does: what is
  drawn in a clipped cell is cut off at its box. Rendering sets which are
  (`.claude/rules/render.md`).
- **A rectangle fills its cell**, as grid's `rectGrob()` does at its default place and size, which
  is how ggplot2 draws a background; a rectangle placed and sized within its cell arrives with the
  first geom that draws one (bars). A background that is not rectangular is a polygon
  (`Polygons`), closed round its outline.
