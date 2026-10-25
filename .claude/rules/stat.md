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
- **A stat's arguments arrive with their first reader.** Every stat is handed the table and each
  panel's axes (`Stat.axes/0`; design-log §4, the entry beginning "A stat is handed each panel's
  axes"), ggplot2's panel scales as plain values: each axis's extent unwidened, whether it is
  discrete, and a function through its transformation, so a stat never sees a scale and its
  boundary lists none; binning first read them. The inverse of the transformation arrives with its
  first reader (`stat_function()`), and a stat's own parameters with the option that sets them.
- **A stat that summarises computes per panel and per group, in that order**, as ggplot2's
  `compute_panel()` does. **Counting, binning and the box plot's summary carry a group's constant
  columns** (`Giggly.Stat.Carry`): a column holding one
  value within every group goes to that group's rows with its type, a factor's category included
  with its levels and ordered flag, as R carries a factor, and one that varies within any group is
  dropped (ggplot2 also warns, which a pure pipeline cannot); counting at each place keeps only
  the columns it counts over.
- **A stat sums through the frame (`DataFrame.summarise/3`), as R sums**: counting's counts plain,
  as `rowsum()` adds, every other sum, a proportion's total among them, extended, as `sum()`
  adds in its long double, so `layer_data/2` holds R's doubles (design-log §4, the entries
  beginning "The frame's first group-by aggregate" and "The frame's sums are R's").
- **A stat never pulls a column of its input, only of a table it has already summarised**
  (design-log §4, the entry beginning "A stat computes only through frame operations"): the work
  that scales with the layer's rows (choosing the rows, weighing them, counting, finding a group's
  constant columns) runs through the frame's operations, so an engine holding the table could run
  it, and what a stat works out on lists is its own small output, a share from its counts, a
  width from its counted positions. Nothing checks this but review. **Aligning pulls its panels'
  rows** (design-log §4, the entry beginning "Smoothing and densities compute over the rows"): its
  output is as large as its input, as the identity's is, and interpolating each group at the
  others' places has no frame operation.
- **A stat names the computed column each aesthetic takes by default, `default_mapping/1`**,
  ggplot2's `after_stat()` defaults (`%{x: :count, y: :count}` for counting). The assembly puts it
  into an aesthetic the layer maps to nothing, and titles that aesthetic's guide by it as a
  fallback, which any layer's column or expression replaces.
- **A stat names what a mapping's after_stat can read: its computed variables as ggplot2
  documents them** (`computed_variables/0`: counting's `count` and `prop`, not the `width` and
  `flipped_aes` its table also holds; the box plot's summary's whiskers, hinges, notches and
  `width`, each in either orientation, not its `outliers` or `relvarwidth`), **and the aesthetics
  it consumes** (`dropped_aesthetics/0`, ggplot2's `dropped_aes`: counting's `weight`, the box
  plot's summary's `x`, `y` and `weight`, and counting at each place's, which `StatSum` sums
  without declaring), module functions beside its accepted aesthetics, which `Plot` reads at the
  call. A stat with neither, the identity, computes nothing an after_stat can read.
- **Counting is ggplot2's `stat_count()`**: a row per distinct x of each group, its `count` the rows
  there or the sum of their weights, a missing weight (`nil` or NaN) adding nothing and an
  infinite one making the count infinite, its `prop` the count's share of its group's total, the
  sum of its counts' magnitudes, divided as R divides (`Giggly.DataFrame.Arithmetic`: NaN for a
  total of zero or an infinite count over an infinite total, 0 for a finite one), and its `width`
  the one the layer sets, the stat's `width`, as `stat_count()` takes it, else 0.9 of the layer's
  x spacing counting from zero (`Giggly.Resolution`). A weight that is not a
  number is refused when the plot is run, an expression's, whose type the call cannot know. A row
  missing its x, or at an infinite one, is not counted. Counts are doubles, as R's `rowsum()` gives
  them. **It counts along whichever of x and y is mapped**, exactly one, as `stat_count()` decides
  its orientation, and writes that in a `flipped_aes` column for the bar geom and the positions; a
  horizontal layer is counted as a vertical one, flipped and flipped back, and its count goes into
  x.
- **Binning is ggplot2's `stat_bin()`**: per panel and per group, one row per bin, its `count` the
  rows in it or the sum of their weights, a missing weight adding nothing and an infinite one
  making it infinite, 0 for a bin no row falls
  in, and its middle `x`, its ends `xmin` and `xmax`, its `width`, in R's arithmetic, so a break a
  transformation takes to an infinity makes a bin of infinite width, its `density` (the count over
  the width over the group's total of the counts' magnitudes, summed by the frame), and `ncount`
  and `ndensity` (over the group's largest magnitude), NaN where the group's counts are all 0, as R
  divides. **The bins are R's to the last digit** (`bin.R`), from each panel's axis: the breaks
  given, through the axis's transformation and sorted; or `binwidth` apart in transformed units,
  on a `boundary`, a `center`, or else half a width from 0, by R's `seq()`; or else `bins` spanning
  the limits, the outermost centred on them unless either limit falls on the boundary (R's `%%`,
  in doubles where R works in extended precision); 0.1 wide on an axis of zero width. Each break
  is moved outward a hundred-millionth of the median gap, R's fuzz, and a row's bin is the frame's
  `cut` against them, closed as `closed` says, the outermost at both ends; a row missing its x or at
  an infinite one is not counted. `pad` and `drop` add and leave out bins as `stat_bin()`'s do. It
  bins along whichever of x and y is mapped, as counting counts, refuses an axis that is
  discrete, and refuses bins that would number more than a million, as R does; y takes `count`
  by default, and an after_stat reads `count`, `density`, `ncount`, `ndensity` and `width`.
- **Counting at each place is ggplot2's `stat_sum()`** (design-log §4, the entry beginning "A
  count layer counts over ggplot2's list"): per panel, a row for each combination of the columns
  ggplot2's `.all_aesthetics` names but `weight`, `group` included, in column order, so a column
  the plot's mapping carries in under another name (`linewidth`, `stroke`) is dropped and splits
  nothing; rows sorted by those columns, a missing value last. Its `n` is the rows or the sum of
  their weights, a missing weight (`nil` or NaN) making it missing, the first met kept, and an
  infinite one infinite, as R's `sum()` adds; its `prop` is `n` over its group's total in the
  panel, with no `abs()`, divided as R divides, an infinity or NaN where the total is zero. A
  row missing its x or y, or at an infinite one, is not counted. size takes `n` by default; it
  computes `n` and `prop` and consumes `weight`.
- **Aligning is ggplot2's `stat_align()`, `geom_area()`'s stat, R's to the last digit**: rows
  missing or infinite in x or y left out first, as ggplot2's stats drop them; a panel of one group
  kept as it is; in a panel of several, the places are its rows' distinct x and the points where a
  group's consecutive rows (in the panel's order) cross zero, each also `adjust` either side, a
  thousandth of the places' range or a third of their smallest gap, sorted and distinct; each group
  with more than one distinct x, in group order, becomes a row at each place within its x range,
  its y R's `approx()` formula, exactly a row's y at its x, after the first and last rows at each
  shared x stand in for them, the first moved `adjust` left, padded by a row of y 0 `adjust` beyond
  each end marked `align_padding`; every other column is the group's first row's, the first at its
  lowest x where some share one. `flipped_aes` says the orientation, along y with x and y swapped,
  and the columns come x and y first where the first panel was aligned, as R binds them; it needs
  `x` and `y` and computes nothing an after_stat can read. **A padding row a scale's limits cut
  keeps its missing x in `layer_data/2`**, where ggplot2's `finish_layer()` drops it; the area
  leaves it out when drawn, so the drawing is R's (Steve, 2026-10-25: "B").
- **The box plot's summary is ggplot2's `stat_boxplot()`** (design-log §4, the entries beginning
  "A box's outliers are a list column" and "A box plot takes R's options"): per panel and per
  group, one row per box, its quartiles the frame's `quantile` (R's type 7), its outliers the rows
  more than `coef` times the box's height past a hinge, by a join of the fences and a filter,
  collected by `list` in row order, an empty list for none; its whiskers the least and greatest y
  of the rest, or, where it has outliers, the range of those and its quartiles, so a box of only
  outliers reaches its hinges; its notches `middle` ∓ 1.58 × height / √rows, `relvarwidth` √rows,
  `x` the middle of its x range, and `width` its group's first mapped width, else 0.9 of its x
  range where it holds several, else the stat's `width`, the layer's `width:`, which drops a mapped
  one as any set aesthetic does, else 0.75 of the layer's x spacing from zero. The orientation and the spacing are read from every row, as R reads them; then a row
  missing its x or y, or at an infinite one, is left out, and a group left with none has no box.
  **It runs along the axis R's `has_flipped_aes()` picks for a box plot**: `orientation`, else the
  one axis mapped (y at x 0, or x), else the continuous axis beside a discrete one, else y where
  every group holds one x and x where every group holds one y, else y, where R also warns. A width
  that is not a number is refused when the plot is run.
