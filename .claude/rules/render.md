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
  layer's geom draws in each panel, and the guide's modules draw the panel's background and grid
  lines (`Guide.Grid`), axes (`Guide.Axis`) and strips (`Guide.Strip`), handed the plot's coordinate system and that panel's params, which
  rendering passes on unread; rendering arranges what they draw into cells, the panel's background
  and grid under its layers and any axis inside the panel over them, as ggplot2's coordinate
  system draws its background and foreground (`render_bg`, `render_fg`). The panel's
  cell is clipped when the assembly says the coordinate system clips panels; each strip's cell is
  clipped, as `theme_gray()`'s `strip.clip = "on"` says; the plot's background is clipped to the
  table, as `table_add_background()` adds it, which shows only when the table keeps its
  proportions and fills the drawing one way alone; every other cell is not.
- **Rendering resolves the plot's theme, once, and hands the complete theme on.** The assembly
  carries the theme's name; `Theme.complete/1` turns it into the elements, which the guide and
  rendering itself read. A geom is handed no theme: the point keeps its own look until default
  aesthetics are filled from the theme in the assembly.
- **Rendering arranges the panels as the layout table says, knowing no facet.** Each layout row
  gives a panel's row and column, whether it draws its bottom and left axes, and its strip labels;
  a facet says where things go, and rendering lays them out as ggplot2's facets lay them out. An
  arrangement those columns cannot express grows a case here.
- **The panels share what the margin, axes, strips, titles and panel spacing leave, equally**,
  each one share wide; a plot whose coordinate system keeps an aspect ratio (the assembly's
  `aspect_ratio`, radially 1) gives each panel row that ratio as its weight and keeps the scene's
  proportions, as ggplot2's facets give the panel rows the ratio in null units and respect the
  table, so the panels keep their shape and the table is centred in the drawing.
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
- **The plot's labels (`Guide.Title`) take rows and a column of their own**, as ggplot2's
  `table_add_titles()` and `table_add_tag()` add them: the title's and the subtitle's rows above
  the panels and the caption's below the x title, each spanning the panels' columns
  (`plot.title.position = "panel"`), and the tag's row above everything and column left of
  everything inside the margin, its cell where they cross (`plot.tag.position = "topleft"`). A
  label of `:none` takes a row or column of no size.
- **Every plot's cells are drawn in ggplot2's facets' order**: the background first, over the
  whole table, margin included, as ggplot2's `table_add_background()` adds it; then the panels
  column by column; the strips from the last row of panels to the first, left to right; the bottom
  axes in that order; the left axes from the last column to the first, top to bottom; then the x
  title and the y title, the legends, and the plot's subtitle, title, caption and tag. ggplot2's
  plot without a facet draws its y axis before its x axis, which Giggly does not follow
  (design-log §4).
- **Layers are drawn in the order they were added**, so a later layer is drawn over an earlier
  one.
- **A layer's rows are split by panel, and each panel's are drawn by the layer's geom alone**, as
  ggplot2's `draw_layer()` splits by `PANEL`; a geom never sees another panel's rows.
- **A plot with legends gives them a column right of the panels**, the theme's legend spacing
  from them, as wide as the widest, before the margin, as ggplot2 places its guide box `"right"`.
  Each legend is drawn by the guide its scale names (`Guide.draw/3`) and the legends are stacked
  in the guide's box (`Guide.Box.draw/2`), in the order the assembly gives them; its cell spans
  the panels' rows, from the first's top to the last's bottom, the strips above the first row left
  out, and its table is centred down it; the cell is drawn after the axes' titles and before the
  plot's labels. Each key's glyphs are drawn by the geom of every layer that maps one of the
  legend's aesthetics and draws in that key (`Geom.draw_key/3`), in layer order, at the key's
  values of the aesthetics that layer maps and with what it sets, and handed to the guide; a key
  no layer draws in keeps its background and label.
