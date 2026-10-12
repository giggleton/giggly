---
paths:
  - "lib/giggly/render.ex"
---

# Rendering

`Giggly.Render` turns an assembled plot into a scene, as ggplot2's `ggplot_gtable()` turns a
built plot into a table of grobs. Why rendering is a stage of its own and is called this:
design-log §4, the entry beginning "The coordinate system arrives with drawing".

## Rules

- **Rendering reads the assembled plot and builds the scene; it computes no positions.** Each
  layer's geom draws in each panel with that panel's params, which rendering passes on unread.
- **A panel's cell is where the layout puts it**, at its `row` and `column`; rendering does not
  decide where a panel goes.
- **Layers are drawn in the order they were added**, so a later layer is drawn over an earlier
  one.
- **One panel until `facet_wrap`.** Rendering matches exactly one layout row and hands each layer's
  whole frame to its geom; splitting a layer's rows by panel arrives with the second panel, where
  that match fails loudly until it does.

## How it works

`scene(assembly)` reads the layout's `panel`, `row` and `column`, takes that panel's params, has
`Geom.draw_panel/3` draw each layer's frame with its geom, and returns a scene of one flexible
row and column holding the panel's cell. `Giggly.to_svg/1` runs the assembly, renders, and has
`Giggly.SVG` draw the scene.
