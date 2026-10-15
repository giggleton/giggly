---
paths:
  - "lib/giggly/render.ex"
---

# Rendering

`Giggly.Render` turns an assembled plot into a scene, as ggplot2's `ggplot_gtable()` turns a
built plot into a table of grobs. Why rendering is a stage of its own and is called this:
design-log §4, the entry beginning "The coordinate system arrives with drawing"; why axes are
cells beside the panel and the margin arrived with them: the entry beginning "Axes are drawn";
why rendering resolves the theme: the entry beginning "The theme is a resolved value"; why it
arranges the panels a facet lays out: the entry beginning "`facet_wrap` is built in steps"; why
every plot's cells are drawn in facets' order: the entry beginning "Every plot's cells are drawn in
ggplot2's facets' order".

## Rules

- **Rendering reads the assembled plot and builds the scene; it computes no positions.** Each
  layer's geom draws in each panel, and the guide draws the panel's background, grid lines and
  axes (`Giggly.Guide`), handed the plot's coordinate system and that panel's params, which
  rendering passes on unread; rendering arranges what they draw into cells, the panel's background
  and grid under its layers, as ggplot2's coordinate system draws them (`render_bg`). The panel's
  cell is clipped when the assembly says the coordinate system clips panels; each strip's cell is
  clipped, as `theme_gray()`'s `strip.clip = "on"` says; every other cell is not.
- **Rendering resolves the plot's theme, once, and hands the complete theme on.** The assembly
  carries the theme's name; `Theme.complete/1` turns it into the elements, which the guide and
  rendering itself read. A geom is handed no theme: the point keeps its own look until default
  aesthetics are filled from the theme in the assembly.
- **Rendering arranges the panels as the layout table says, knowing no facet.** Each layout row
  gives a panel's row and column, whether it draws its bottom and left axes, and its strip labels;
  a facet says where things go, and rendering lays them out as ggplot2's facets lay them out. An
  arrangement those columns cannot express grows a case here.
- **The panels share what the margin, axes, strips, titles and panel spacing leave, equally.**
  The margin is the theme's, on every side, and so is the spacing between panels. Above each row
  of panels are its strips, a row per strip layer as tall as its tallest strip; below it a row as
  tall as its tallest measured bottom axis, and left of each column a column as wide as its widest
  measured left axis. **A bottom axis with an empty cell under it is not measured**, as ggplot2's
  `measure_axes()` sets it to nothing, so it hangs into the empty space (`Scene.Cell`'s `hang`);
  one over another panel, which free x scales draw, is measured. No left axis has an empty cell to
  its left, since panels fill the layout a row at a time. Each axis hangs from its panel's edge at
  its own size, so a left axis narrower than its column sits against its panel. The titles are
  drawn once each, centred on the span of panels, not the strips above them, as ggplot2 spans its
  title cells over the panel rows and columns.
- **Every plot's cells are drawn in ggplot2's facets' order**: the background first, over the
  whole table, margin included, as ggplot2's `table_add_background()` adds it; then the panels
  column by column; the strips from the last row of panels to the first, left to right; the bottom
  axes in that order; the left axes from the last column to the first, top to bottom; then the x
  title and the y title. ggplot2's plot without a facet draws its y axis before its x axis, which
  Giggly does not follow (design-log §4).
- **Layers are drawn in the order they were added**, so a later layer is drawn over an earlier
  one.
- **A layer's rows are split by panel, and each panel's are drawn by the layer's geom alone**, as
  ggplot2's `draw_layer()` splits by `PANEL`; a geom never sees another panel's rows.

## How it works

`scene(assembly)` resolves the assembly's theme name with `Theme.complete/1` and splits each
layer's frame by panel (`DataFrame.split/2`). For each layout row it takes the panel's params, has
`Guide.grid/3` draw the panel's background and grid lines and `Geom.draw_panel/4` each layer's rows
in that panel over them, `Guide.axes/3` its axes (kept where the layout says the panel draws them)
and `Guide.strips/2` its strips. `Guide.titles/4` draws the titles from the first panel's params.
The scene's columns are named as they are built — the margin, the y title, then for each column of
panels its left axes and its panels with the panel spacing between, then the margin — and so are
its rows — the margin, then for each row of panels its strip layers, its panels and its bottom
axes with the spacing between, then the x title and the margin — and each cell is placed by those
names. The panels' columns and rows are `:rest` and every other size is in points. The first cell
spans every row and column and holds a `Scene.Rect` in the theme's `plot_background`.
`Giggly.to_svg/2` runs the assembly, renders, and has `Giggly.SVG` draw the scene.
