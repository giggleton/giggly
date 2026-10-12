---
paths:
  - "lib/giggly/facet.ex"
---

# The facet

`Giggly.Facet` decides which panel each row of a plot's data is drawn in. Why it runs where it does
and why `panel` is an integer: design-log §4, the entry beginning "Two reserved frame columns";
why it is plain functions for now: the entry beginning "The facet assigns panels".

## Rules

- **The facet runs first, on the plot's data as read,** before any mapping is evaluated: a facet
  splits on the data's own columns, which evaluation discards. It writes `:panel`; nothing else
  writes it, and every later stage works panel by panel from that column alone.
- **No stage sees the facet.** A geom, stat, scale or coordinate system reads `panel` and the
  layout table; never the facet's settings or the variables it splits on.
- **The layout table holds only what a stage reads.** One row per panel: `panel`, and the
  `scale_x`/`scale_y` ids scale training routes by. `row` and `col` arrive with the scene, their
  first reader; under `facet_wrap` the facet variables' columns join it, as in ggplot2's.
- **A panel id is an integer.** It is never discrete, so it never enters the group key, and a
  layer with no rows in a panel still lines up with the others through the layout table.
- **One kind of facet, plain functions.** The behaviour, the plot's `facet` field and the
  dispatch arrive with the second kind (`facet_wrap`), and touch only `Plot`, `Facet` and the
  assembly.

## How it works

`assign_panels/1` is ggplot2's null facet (`FacetNull$map_data()`): it puts a `:panel` column of 1s
on the frame. `layout/0` is its `layout_null()`: a one-row frame of `:panel`, `:scale_x` and
`:scale_y`, all 1. The assembly calls `assign_panels/1` once, on the plot's data, and each layer's
evaluation carries the column across with `DataFrame.put/3` after choosing the layer's aesthetics,
so every layer frame ends `…, :panel, :group`. The boundary lists `Giggly.DataFrame` and nothing
else.
