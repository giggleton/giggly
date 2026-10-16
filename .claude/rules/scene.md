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
entry beginning "Three values with one function"; why a position can be offset in points: the entry
beginning "A primitive's position is a place in its cell plus an offset in points"; why a share
has a weight and a scene can keep its proportions: the entry beginning "A `:rest` size has a
weight".

## Rules

- **A scene is values and calls nothing.** Its boundary lists nothing and exports the structs
  rendering builds and a backend reads (`Cell`, `Circles`, `Polygons`, `Polylines`, `Rect`,
  `Rectangles`, `Segments`, `Text`); nothing in it knows SVG, a font or a theme.
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
- **Circles, placed rectangles, polylines and segments carry an opacity for each mark**, from 0 to
  1: a circle's `opacity` its outline and fill alike, a rectangle's `fill_opacity` its fill alone,
  a polyline's or segment's `opacity` its stroke, as grid's colours carry the alpha ggplot2 gives
  them. One per mark, as grid's graphical parameters are, so a mapped aesthetic needs no primitive
  per value; colour and size will take the same route. **A colour is `#RRGGBB` beside its
  opacity**, never with an alpha of its own: a placed rectangle's border carries one
  `color_opacity`, its colour's own alpha, since ggplot2 never gives a border the row's; its `fill`
  and `color` may be `:none`, R's `NA`, which draws none.
- **A line carries grid's `lineend`, `linejoin` and `linemitre`**: `Polylines` (grid's
  `polylineGrob()`, a line through points, one per tick, grid line or group) and `Segments`
  (`segmentsGrob()`, one straight piece per segment, for a line whose look varies along it and a
  path's legend key) say how their ends (`:butt`, `:round`, `:square`) and corners (`:round`,
  `:mitre`, `:bevel`) are drawn and their mitre limit; the guides' lines are theme_gray()'s, butt
  and round.
- **A cell spans a range of rows and a range of columns, counting from 1, and cells are drawn in
  the order listed.** Most span one of each; the plot's background spans the whole table (gtable's
  `t`, `l`, `b` and `r`). Names and z-order beyond list order arrive with their first reader.
- **Every cell says whether it is clipped, `:on` or `:off`**, as gtable's `clip` does: what is
  drawn in a clipped cell is cut off at its box. Rendering sets which are
  (`.claude/rules/render.md`).
- **A rectangle (`Rect`) fills its cell**, as grid's `rectGrob()` does at its default place and
  size, which is how ggplot2 draws a background; **rectangles placed and sized within their cell
  (`Rectangles`)** run from `xmin` to `xmax` and `ymin` to `ymax` in the cell's units, as ggplot2's
  `GeomRect` draws a bar. A background that is not rectangular is a polygon (`Polygons`), closed
  round its outline.
- **A cell may hold a scene of its own among its primitives**, a table laid out in the cell's box
  as gtable nests one table in another: its sizes in points take their length and its shares split
  what is left of the box, and a table of sizes in points alone is centred in the box both ways,
  as grid centres a fixed table in its viewport. A nested scene never keeps its proportions. A
  legend is one.
