---
paths:
  - "lib/giggly/facet.ex"
  - "lib/giggly/facet/**"
  - "test/giggly/facet_test.exs"
---

# The facet

`Giggly.Facet` decides which panel each row of a plot's data is drawn in, and where each panel
sits. Why it runs where it does and why `panel` is an integer: design-log §4, the entry beginning
"Two reserved frame columns"; why the plot records its facet, the null facet included: the entry
beginning "The coordinate system arrives with drawing", which amends the entry beginning "The
facet assigns panels"; why a facet is a struct of its kind with a protocol at the root: the entry
beginning "Each facet, coordinate system, geom, stat and position is a struct"; how `facet_wrap`
is built, step by step: the entry beginning "`facet_wrap` is built in steps".

## Rules

- **The facet runs first, on the plot's data as read,** before any mapping is evaluated: a facet
  splits on the data's own columns, which evaluation discards. It writes `:panel`; nothing else
  writes it, and every later stage works panel by panel from that column alone.
- **No stage sees the facet.** A geom, stat, scale or coordinate system reads `panel` and the
  layout table; never the facet's settings or the variables it splits on.
- **The layout table holds only what a stage reads.** One row per panel: `panel`; the `row` and
  `column` rendering puts the panel's cell at (ggplot2's `ROW` and `COL`, spelled out); and the
  `scale_x`/`scale_y` ids scale training routes by; and what rendering arranges, which is the
  facet's say: `axis_bottom` and `axis_left`, whether the panel draws each axis, and `strip`, its
  strip labels top to bottom. Under `facet_wrap` each column it splits on joins it, by its name
  in the data, as in ggplot2's, and each row's panel is found from its values there.
- **A wrapped panel draws an axis on each side with no panel beside it**, ggplot2's axes at the
  margins: below the last row and below a panel with an empty cell under it, left of the first
  column. **On a free axis (`scales: :free_x`, `:free_y` or `:free`) each panel has a scale of its
  own, its id the panel's, and draws its own axis**, as ggplot2's layout numbers `SCALE_X` and
  `SCALE_Y` by panel and its `facet_wrap` draws every axis of a free scale. Its strips are one per facet column, the value written as ggplot2's `label_value()`
  writes it, here `to_string/1`, a missing value `NA`. The null facet's one panel draws both axes
  and has no strip.
- **Panels made from values are ordered as a discrete scale orders its levels**, by the key the
  assembly hands the facet (`Scale.level_key/1`): column by column, a missing value last, strings
  by bytes rather than R's locale. Only the combinations that occur get a panel.
- **`facet_wrap` lays its panels out as ggplot2 does**, row by row: with neither `nrow:` nor
  `ncol:`, by R's `n2mfrow()` with rows and columns swapped, as ggplot2's `wrap_dims()` takes it;
  given one, the other is as many as the panels need; given both, they must hold every panel, or
  the layout raises when the plot is run, as ggplot2's does. Data with no rows makes no panel and
  raises too.
- **A panel id is an integer.** It is never discrete, so it never enters the group key, and a
  layer with no rows in a panel still lines up with the others through the layout table.
- **A plot always records its facet as a struct of its kind, `%Facet.Null{}` included.**
  `Giggly.Facet` is a protocol; each facet is one module holding its struct, whose fields are its
  parameters, and its computing, in a `defimpl` that opens by classifying itself into this
  boundary. The boundary exports the kinds, whose structs a plot records; what they compute with
  stays in their implementations. `facet_wrap` arrives as `%Facet.Wrap{}`, touching only `Plot`,
  `Facet`, the assembly and rendering, never a geom.

## How it works

`layout(facet, frame, order_key)` and `assign_panels(facet, frame, layout)` dispatch on the
facet's struct. `Facet.Null` is ggplot2's null facet, with no parameters: its `assign_panels/3`
(`FacetNull$map_data()`) puts a `:panel` column of 1s on the frame, and its `layout/3`
(`layout_null()`) is a one-row frame of `:panel`, `:row`, `:column`, `:scale_x` and `:scale_y`,
all 1. `Facet.Wrap` is `facet_wrap()`, its struct the columns it splits on (by their names in the
data), `nrow` and `ncol`, each `:none` when not given, and `scales`: its `layout/3` takes the combinations of
those columns' values that occur, sorts them by the order key applied to each value, places panel
`i` at row `div(i - 1, ncol) + 1` and column `rem(i - 1, ncol) + 1`, and puts each facet column
beside them; its `assign_panels/3` looks each row's values up in those columns. The assembly calls
`layout/3` and then `assign_panels/3` once, on the plot's data, and each layer's evaluation carries
the column across with `DataFrame.put/3` after choosing the layer's aesthetics, so every layer
frame ends `…, :panel, :group`. The boundary lists `Giggly.DataFrame` and nothing else, and
exports `Null` and `Wrap`.
