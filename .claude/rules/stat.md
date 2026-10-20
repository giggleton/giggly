---
paths:
  - "lib/giggly/stat.ex"
  - "lib/giggly/stat/**"
---

# Stats

`Giggly.Stat` runs a layer's statistical transformation on its table. Why the identity is a stat a
layer records rather than an absence: design-log §4, the entry beginning "A layer records its stat
and position"; why the layer records a struct of its kind, run through a protocol at the root:
the entry beginning "Each facet, coordinate system, geom, stat and position is a struct".

## Rules

- **A layer always records its stat, the identity included.** An absent stat cannot be told from
  a forgotten one; `%Stat.Identity{}` says the layer computes nothing on purpose, and a test can
  say so.
- **A layer records its stat as a struct of its kind, which `Plot` builds and never runs.** `Plot`
  lists this boundary to build the struct; `GigglyCredo.Check.PlotRunsNothing` keeps the protocol
  out of its files. Each stat is one module holding its struct, whose fields are its parameters,
  and its computing, in a `defimpl` that opens by classifying itself into this boundary; the
  boundary exports the kinds.
- **A stat runs after the position scales have mapped the layer's x and y columns**, so it
  computes on positions: a discrete value is its level's position.
- **A stat's arguments arrive with their first reader.** Every stat is handed the table alone:
  counting groups it by the `panel` and `group` columns through the frame and reads no scale. The
  panel's scales (ggplot2 hands `compute_layer` the layout, and binning reads the scale's range)
  arrive with the first stat that reads one, and a stat's own parameters with the option that sets
  them.
- **A stat that summarises computes per panel and per group, in that order**, as ggplot2's
  `compute_panel()` does. **Counting carries a group's constant columns**: a column holding one
  value within every group goes to that group's rows, and one that varies within any group is
  dropped (ggplot2 also warns, which a pure pipeline cannot); counting at each place keeps only
  the columns it counts over.
- **A stat sums through the frame (`DataFrame.summarise/3`), as R sums**: counting's counts plain,
  as `rowsum()` adds, every other sum, a proportion's total among them, compensated, as `sum()`
  adds in extended precision, so `layer_data/2` holds R's doubles (design-log §4, the entry
  beginning "The frame's first group-by aggregate"). Choosing the rows to count and dividing stay
  on the lists a stat pulls.
- **A stat names the computed column each aesthetic takes by default, `default_mapping/1`**,
  ggplot2's `after_stat()` defaults (`%{x: :count, y: :count}` for counting). The assembly puts it
  into an aesthetic the layer maps to nothing, and titles that aesthetic's guide by it as a
  fallback, which any layer's column or expression replaces.
- **A stat names what a mapping's after_stat can read: its computed variables as ggplot2
  documents them** (`computed_variables/0`: counting's `count` and `prop`, not the `width` and
  `flipped_aes` its table also holds), **and the aesthetics it consumes** (`dropped_aesthetics/0`,
  ggplot2's `dropped_aes`: counting's `weight`, and counting at each place's, which `StatSum`
  sums without declaring), module functions beside its accepted aesthetics, which `Plot` reads at
  the call. A stat with neither, the identity, computes nothing an
  after_stat can read.
- **Counting is ggplot2's `stat_count()`**: a row per distinct x of each group, its `count` the rows
  there or the sum of their weights, missing weights adding nothing, its `prop` the count's share of
  its group's total, the sum of its counts' magnitudes (NaN for a total of zero), and its `width`
  0.9 of the layer's x spacing counting from zero (`Giggly.Resolution`). A weight that is not a
  number is refused when the plot is run, an expression's, whose type the call cannot know. A row
  missing its x, or at an infinite one, is not counted. Counts are doubles, as R's `rowsum()` gives
  them. **It counts along whichever of x and y is mapped**, exactly one, as `stat_count()` decides
  its orientation, and writes that in a `flipped_aes` column for the bar geom and the positions; a
  horizontal layer is counted as a vertical one, flipped and flipped back, and its count goes into
  x.
- **Counting at each place is ggplot2's `stat_sum()`** (design-log §4, the entry beginning "A
  count layer counts over ggplot2's list"): per panel, a row for each combination of the columns
  ggplot2's `.all_aesthetics` names but `weight`, `group` included, in column order, so a column
  the plot's mapping carries in under another name (`linewidth`, `stroke`) is dropped and splits
  nothing; rows sorted by those columns, a missing value last. Its `n` is the rows or the sum of
  their weights, a missing or non-finite weight making it missing, as R's `sum()` does; its `prop`
  is `n` over its group's total in the panel, with no `abs()`, an infinity or NaN where the total
  is zero. A row missing its x or y, or at an infinite one, is not counted. size takes `n` by
  default; it computes `n` and `prop` and consumes `weight`.
