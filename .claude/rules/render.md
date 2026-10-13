---
paths:
  - "lib/giggly/render.ex"
---

# Rendering

`Giggly.Render` turns an assembled plot into a scene, as ggplot2's `ggplot_gtable()` turns a
built plot into a table of grobs. Why rendering is a stage of its own and is called this:
design-log §4, the entry beginning "The coordinate system arrives with drawing"; why axes are
cells beside the panel and the margin arrived with them: the entry beginning "Axes are drawn";
why rendering resolves the theme: the entry beginning "The theme is a resolved value".

## Rules

- **Rendering reads the assembled plot and builds the scene; it computes no positions.** Each
  layer's geom draws in each panel, and the guide draws the panel's background, grid lines and
  axes (`Giggly.Guide`), with that panel's params, which rendering passes on unread; rendering
  arranges what they draw into cells, the panel's background and grid under its layers, as
  ggplot2's coordinate system draws them (`render_bg`). The panel's cell is clipped when the
  assembly says the coordinate system clips that panel; every other cell is not.
- **Rendering resolves the plot's theme, once, and hands the complete theme on.** The assembly
  carries the theme's name; `Theme.complete/1` turns it into the elements, which the guide and
  rendering itself read. A geom is handed no theme: the point keeps its own look until default
  aesthetics are filled from the theme in the assembly.
- **The panel takes what the plot margin, its axes and their titles leave.** The margin is the
  theme's, on every side; each axis's and each title's column or row is as wide or tall as the
  guide measures it.
- **The plot's background is drawn first, in a cell spanning the whole table, margin included**,
  as ggplot2's `table_add_background()` adds it, so a page that is not white shows the plot as
  ggplot2 draws it. Then the panel, then its axes, the y axis before the x, then the titles, the
  x title before the y, as ggplot2 orders them.
- **Layers are drawn in the order they were added**, so a later layer is drawn over an earlier
  one.
- **One panel until `facet_wrap`.** Rendering matches exactly one layout row, at row 1 and column
  1, and hands each layer's whole frame to its geom; splitting a layer's rows by panel, placing
  several panels among their axes (perhaps in the facet, as ggplot2's `draw_panels()`), arrives
  with the second panel, where that match fails loudly until it does.

## How it works

`scene(assembly)` resolves the assembly's theme name with `Theme.complete/1`, reads the layout's
one row, takes that panel's params, has `Guide.grid/2` draw the panel's background and grid lines
and `Geom.draw_panel/3` each layer's frame over them, and `Guide.axes/3` draw its axes and their titles from the assembly's titles in the theme's look,
and returns a scene whose columns are margin, y title, y axis, panel and margin and whose rows are
margin, panel, x axis, x title and margin, the panel's column and row `:rest` and the others in
points. Its first cell spans every row and column and holds a `Scene.Rect` in the theme's
`plot_background`.
`Giggly.to_svg/2` runs the assembly, renders, and has `Giggly.SVG` draw the scene.
