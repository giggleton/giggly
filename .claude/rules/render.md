---
paths:
  - "lib/giggly/render.ex"
---

# Rendering

`Giggly.Render` turns an assembled plot into a scene, as ggplot2's `ggplot_gtable()` turns a
built plot into a table of grobs. Why rendering is a stage of its own and is called this:
design-log §4, the entry beginning "The coordinate system arrives with drawing"; why axes are
cells beside the panel and the margin arrived with them: the entry beginning "Axes are drawn";
why rendering draws in a resolved theme: the entry beginning "The theme is a resolved value", and
why the assembly resolves it: the entry beginning "Each layer's defaults are filled in"; why it
arranges the panels a facet lays out: the entry beginning "`facet_wrap` is built in steps"; why
every plot's cells are drawn in facets' order: the entry beginning "Every plot's cells are drawn in
ggplot2's facets' order"; where the legends go and why a box is placed by a hang: the entry
beginning "Legends go where the theme puts them".

## Rules

- **Rendering reads the assembled plot and builds the scene; it computes no positions.** Each
  layer's geom draws the rows the assembly hands it (`drawn_data`) in each panel, and the guide's
  modules draw the panel's background and grid
  lines (`Guide.Grid`), axes (`Guide.Axis`) and strips (`Guide.Strip`), handed the plot's coordinate system and that panel's params, which
  rendering passes on unread; rendering arranges what they draw into cells, the panel's background
  and grid under its layers and any axis inside the panel over them, as ggplot2's coordinate
  system draws its background and foreground (`render_bg`, `render_fg`). **Rendering draws the
  panel's border itself, last in the panel's cell**, a `Rect` filling it as the plot's background
  does, **never filled**, as `render_fg()` draws `panel.border` with `fill = NA`: a `fill:` the
  border's element gives is taken and unused, as R's is (design-log §4, the entry beginning "The
  panel's border is never filled"). **With
  `panel_ontop` the background and grid are drawn after the layers**, under the foreground, as
  ggplot2's `draw_panel()` orders them. The panel's
  cell is clipped when the assembly says the coordinate system clips panels; each strip's cell is
  clipped, as `theme_gray()`'s `strip.clip = "on"` says; the plot's background is clipped to the
  table, as `table_add_background()` adds it, which shows only when the table keeps its
  proportions and fills the drawing one way alone, its cell kept, empty, where the theme removes
  it, as svglite writes the clip; every other cell is not.
- **Rendering reads the complete theme the assembly worked out, and hands it on.** The assembly
  completes the plot's theme (`Theme.complete/1`) where ggplot2's build does; the guide and
  rendering itself read its elements, each colour beside its opacity, which every primitive drawn
  from the theme carries. A geom is handed no theme: the marks take their look from their rows,
  which hold the theme's defaults where the layer leaves its look unset.
- **Rendering arranges the panels as the layout table says, knowing no facet.** Each layout row
  gives a panel's row and column, whether it draws its bottom and left axes, and its strip labels
  above it and right of it;
  a facet says where things go, and rendering lays them out as ggplot2's facets lay them out. An
  arrangement those columns cannot express grows a case here.
- **The panels share what the margin, axes, strips, titles and panel spacing leave, equally**,
  each one share wide; a plot whose coordinate system keeps an aspect ratio (the assembly's
  `aspect_ratio`, radially 1) gives each panel row that ratio as its weight and keeps the scene's
  proportions, as ggplot2's facets give the panel rows the ratio in null units and respect the
  table, so the panels keep their shape and the table is centred in the drawing.
  The margin is the theme's, each side its own, and so is the spacing between panels, across
  (`panel_spacing_x`) and down (`panel_spacing_y`). Above each row
  of panels are its strips, a row per strip layer its panels have, each as tall as the tallest
  strip above any panel; right of the last column a column per strip layer the panels have there,
  each as wide as the widest, against the panels and before any legend, as ggplot2's `facet_grid`
  seams them on with its strips inside; below each row a row as
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
  column by column; the strips from the last row of panels to the first, left to right; the strips
  right of the panels, top to bottom and left to right; the bottom axes as the strips above; the
  left axes from the last column to the first, top to bottom; then the x title and the y title,
  the legends, and the plot's subtitle, title, caption and tag. ggplot2's plot without a facet
  draws its y axis before its x axis, which Giggly does not follow (design-log §4).
- **Layers are drawn in the order they were added**, so a later layer is drawn over an earlier
  one.
- **A layer's rows are split by panel, and each panel's are drawn by the layer's geom alone**, as
  ggplot2's `draw_layer()` splits by `PANEL`; a geom never sees another panel's rows. A panel
  where the layer has no rows, as one only another table makes, draws nothing of it, as ggplot2
  gives it an empty grob, and its geom is not called.
- **A plot's legends go where the theme puts them (`legend_position`), as ggplot2's
  `table_add_legends()` places its guide boxes**: a column right of the panels, or left of the y
  title inside the tag's column; a row above the panels below the plot's title and subtitle, or
  below the x title above the caption; each the theme's legend spacing from the panels and as
  wide or as tall as the box; inside the panels with no room of their own; **or nowhere
  (`:none`), neither column nor spacing**. A box beside the panels spans the panels' rows or
  columns, or with `legend_location: :plot` every row from the first strip to the x title or
  every column between the tag and the right margin; a box inside spans every panel, the first
  row's strips left out, whatever the location, as `find_panel()` finds them. **The box is placed
  in its cell by a `{:at, ...}` hang, as grid places a viewport**: beside the panels its
  justification's point at the same point of its cell, inside its justification's point at
  `legend_position_inside`, so the placement is data on the cell and the generic layout code lays
  it out. Each legend runs as `legend_direction` says, or across above or below the panels and
  down elsewhere, as ggplot2's `Guides$draw()` decides, and that direction by position is handed
  to `Guide.Box.draw/3` for its own defaults.
  Each legend is drawn by the guide its scale names (`Guide.draw/3`) and the legends are stacked
  in the guide's box (`Guide.Box.draw/3`), in the order the assembly gives them; the cell is
  drawn after the axes' titles and before the plot's labels. Each key's glyphs are drawn by the geom
  of every layer that maps one of the legend's aesthetics and draws in that key (`Geom.draw_key/2`),
  in layer order, at the key's values of the aesthetics that layer maps, with what it sets, both
  laid over its geom's defaults under the theme (the layer's `defaults`), and with whether its marks
  are horizontal (`flipped_aes`, the assembly's `flipped`), as ggplot2 hands `draw_key` the layer's
  `flipped_aes`, so a box's key is turned, and handed to the guide with the
  room each glyph needs (`Geom.key_size/2`), which the guide sizes the key by, so rendering
  measures nothing itself; a key no layer draws in keeps its background and label.
