---
paths:
  - "lib/giggly/render.ex"
---

# Rendering

`Giggly.Render` turns an assembled plot into a scene, as ggplot2's `ggplot_gtable()` turns a
built plot into a table of grobs. Why rendering is a stage of its own and is called this:
design-log §4, the entry beginning "The coordinate system arrives with drawing"; why axes are
cells beside the panel and the margin arrived with them: the entry beginning "Axes are drawn".

## Rules

- **Rendering reads the assembled plot and builds the scene; it computes no positions.** Each
  layer's geom draws in each panel, and the guide draws the panel's axes (`Giggly.Guide`), with
  that panel's params, which rendering passes on unread; rendering arranges what they draw into
  cells.
- **The panel takes what the plot margin, its axes and their titles leave.** The margin is
  `theme_grey()`'s, 5.5 TeX points each side, converted to points where it is declared; each
  axis's and each title's column or row is as wide or tall as the guide measures it. The panel is
  drawn first, then its axes, the y axis before the x, then the titles, the x title before the y,
  as ggplot2 orders them.
- **Layers are drawn in the order they were added**, so a later layer is drawn over an earlier
  one.
- **One panel until `facet_wrap`.** Rendering matches exactly one layout row, at row 1 and column
  1, and hands each layer's whole frame to its geom; splitting a layer's rows by panel, placing
  several panels among their axes (perhaps in the facet, as ggplot2's `draw_panels()`), arrives
  with the second panel, where that match fails loudly until it does.

## How it works

`scene(assembly)` reads the layout's one row, takes that panel's params, has
`Geom.draw_panel/3` draw each layer's frame with its geom and `Guide.axes/2` draw its axes and
their titles from the assembly's titles, and returns a scene whose columns are margin, y title,
y axis, panel and margin and whose rows are margin, panel, x axis, x title and margin, the
panel's column and row `:rest` and the others in points.
`Giggly.to_svg/1` runs the assembly, renders, and has `Giggly.SVG` draw the scene.
