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
is built, step by step: the entry beginning "`facet_wrap` is built in steps"; how `facet_grid`
is: the entry beginning "`facet_grid` is Phase 3's thirteenth increment".

## Rules

- **The facet runs first, on the tables as read,** before any mapping is evaluated: a facet
  splits on the data's own columns, which evaluation discards. It lays the panels out from the
  plot's data and every layer's table together, the plot's first and then each layer's in the
  order added (`layout/3`), and then gives each layer's table its panels (`assign_panels/3`). It
  writes `:panel`; nothing else writes it, and every later stage works panel by panel from that
  column alone.
- **The panels are those every table makes, as ggplot2's `combine_vars()` makes them** (checked
  in R 4.6.1 with ggplot2 4.0.3): each combination in a table holding every facet column, then,
  table by table, each combination of the columns a table holds only some of with each of the
  others' values made so far, so a value only a layer's table holds makes a panel, and the plot's
  data makes panels though no layer draws it. A table holding none of the columns, or no rows,
  makes none. **Unless some table holds every facet column the layout raises**, naming what each
  table lacks, as ggplot2's "At least one layer must contain all faceting variables": this, not
  `facet_wrap/3`, is where a misspelt facet column is reported (design-log §4, the entry beginning
  "A column the plot names"). **A grid combines its rows' columns and its columns' columns
  apart**, each side refused alone, as ggplot2's `facet_grid` calls `combine_vars()` once for
  each, and then crosses them: every row's values with every column's, so a pair no table holds is
  a panel, drawn empty, as `df.grid()` crosses them. What the two facets share, combining and
  repeating, is `Facet.Combinations`'s.
- **A table lacking some facet columns is repeated in each panel of the values it has**, as
  ggplot2's `map_data()` repeats it: all its rows, in their order, once for each combination of
  the missing columns' values in the layout, in panel order, so one lacking them all is drawn in
  every panel, and the table a stage sees may have more rows than the one given.
- **No stage sees the facet.** A geom, stat, scale or coordinate system reads `panel` and the
  layout table; never the facet's settings or the variables it splits on.
- **The layout table holds only what a stage reads.** One row per panel: `panel`; the `row` and
  `column` rendering puts the panel's cell at (ggplot2's `ROW` and `COL`, spelled out); and the
  `scale_x`/`scale_y` ids scale training routes by; and what rendering arranges, which is the
  facet's say: `axis_bottom` and `axis_left`, whether the panel draws each axis, and `strip`, its
  strip labels top to bottom. Each column a facet splits on joins it, by its name in the data,
  as in ggplot2's, a grid's rows' columns before its columns', and each row's panel is found from
  its values there.
- **A wrapped panel draws an axis on each side with no panel beside it**, ggplot2's axes at the
  margins: below the last row and below a panel with an empty cell under it, left of the first
  column. **On a free axis (`scales: :free_x`, `:free_y` or `:free`) each panel has a scale of its
  own, its id the panel's, and draws its own axis**, as ggplot2's layout numbers `SCALE_X` and
  `SCALE_Y` by panel and its `facet_wrap` draws every axis of a free scale. Its strips are one per
  facet column, the value written as ggplot2's `label_value()` writes it, R's `as.character()`
  (`Giggly.AsCharacter`, which the facet lists: `4` for a whole float, `TRUE`), a missing value
  `NA`. The null facet's one panel draws both axes and has no strip. **A grid's panels draw an
  axis only at its margins, free scales or not**, below the last row and left of the first
  column, ggplot2's `axes = "margins"`; **on a free axis each column of panels shares an x scale
  and each row a y scale, its id the column's or the row's**, as ggplot2 numbers `SCALE_X` by
  `COL` and `SCALE_Y` by `ROW`; its first row's panels have the strips of its columns' columns.
- **Panels made from values are ordered column by column, as R's vctrs combines the tables'
  columns** (checked in R 4.6.1): a column every table holding it holds as a category by its
  levels, the first table's and then those each later one adds; any other as a discrete scale
  orders its levels, by the key the assembly hands the facet (`Scale.level_key/1`), so a factor
  beside text in another table sorts as text; a missing value last, strings by bytes rather than
  R's locale. Only the combinations the tables make get a panel, so a level no row holds makes
  none. A factor in one table beside numbers in another, where R fails, sorts by the key.
- **`facet_wrap` lays its panels out as ggplot2 does**, row by row: with neither `nrow:` nor
  `ncol:`, by R's `n2mfrow()` with rows and columns swapped, as ggplot2's `wrap_dims()` takes it;
  given one, the other is as many as the panels need; given both, they must hold every panel, or
  the layout raises when the plot is run, as ggplot2's does. Tables with no rows make no panel,
  and that raises too. **A grid numbers its panels a row at a time, left to right**, its rows and
  its columns each ordered as panels made from values are.
- **A panel id is an integer.** It is never discrete, so it never enters the group key, and a
  layer with no rows in a panel still lines up with the others through the layout table.
- **A plot always records its facet as a struct of its kind, `%Facet.Null{}` included.**
  `Giggly.Facet` is a protocol; each facet is one module holding its struct, whose fields are its
  parameters, and its computing, in a `defimpl` that opens by classifying itself into this
  boundary. The boundary exports the kinds, whose structs a plot records; what they compute with
  stays in their implementations and in `Facet.Combinations`, which it does not export.
  `facet_wrap` arrives as `%Facet.Wrap{}` and `facet_grid` as `%Facet.Grid{}`, touching only
  `Plot`, `Facet`, the assembly and rendering, never a geom.
