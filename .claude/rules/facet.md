---
paths:
  - "lib/giggly/facet.ex"
  - "lib/giggly/facet/**"
---

# The facet

`Giggly.Facet` decides which panel each row of a plot's data is drawn in, and where each panel
sits. Why it runs where it does and why `panel` is an integer: design-log §4, the entry beginning
"Two reserved frame columns"; why the plot records its facet, the null facet included: the entry
beginning "The coordinate system arrives with drawing", which amends the entry beginning "The
facet assigns panels"; why a facet is a struct of its kind with a protocol at the root: the entry beginning "Each facet, coordinate system, geom, stat and position is a struct".

## Rules

- **The facet runs first, on the plot's data as read,** before any mapping is evaluated: a facet
  splits on the data's own columns, which evaluation discards. It writes `:panel`; nothing else
  writes it, and every later stage works panel by panel from that column alone.
- **No stage sees the facet.** A geom, stat, scale or coordinate system reads `panel` and the
  layout table; never the facet's settings or the variables it splits on.
- **The layout table holds only what a stage reads.** One row per panel: `panel`; the `row` and
  `column` rendering puts the panel's cell at (ggplot2's `ROW` and `COL`, spelled out); and the
  `scale_x`/`scale_y` ids scale training routes by. Under `facet_wrap` the facet variables'
  columns join it, as in ggplot2's.
- **A panel id is an integer.** It is never discrete, so it never enters the group key, and a
  layer with no rows in a panel still lines up with the others through the layout table.
- **A plot always records its facet as a struct of its kind, `%Facet.Null{}` included.**
  `Giggly.Facet` is a protocol; each facet is one module holding its struct, whose fields are its
  parameters, and its computing, in a `defimpl` that opens by classifying itself into this
  boundary. The boundary exports the kinds, whose structs a plot records; what they compute with
  stays in their implementations. `facet_wrap` arrives as `%Facet.Wrap{}`, touching only `Plot`,
  `Facet`, the assembly and rendering, never a geom.

## How it works

`layout(facet)` and `assign_panels(facet, frame)` dispatch on the facet's struct. `Facet.Null` is
ggplot2's null facet, with no parameters: its `assign_panels/2` (`FacetNull$map_data()`) puts a
`:panel` column of 1s on the frame, and its `layout/1` (`layout_null()`) is a one-row frame of
`:panel`, `:row`, `:column`, `:scale_x` and `:scale_y`, all 1. The assembly calls
`assign_panels/2` once, on the plot's data, and each layer's evaluation carries the column across
with `DataFrame.put/3` after choosing the layer's aesthetics, so every layer frame ends
`…, :panel, :group`. The boundary lists `Giggly.DataFrame` and nothing else, and exports `Null`.
