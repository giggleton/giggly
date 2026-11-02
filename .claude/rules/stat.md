---
paths:
  - "lib/giggly/stat.ex"
  - "lib/giggly/stat/**"
  - "lib/giggly/tensor.ex"
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
  `compute_panel()` does. **Counting, binning, hexagonal binning, the box plot's summary,
  smoothing and densities carry a group's constant columns** (`Giggly.Stat.Carry`): a column holding one
  value within every group goes to that group's rows with its type, a factor's category included
  with its levels and ordered flag, as R carries a factor, and one that varies within any group is
  dropped (ggplot2 also warns, which a pure pipeline cannot), smoothing reading only the groups it
  fits and densities only those of panels given rows, as ggplot2 reads only those its stat gives
  rows; counting at each place keeps only the
  columns it counts over.
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
  others' places has no frame operation. **Smoothing's straight line is three passes of sums
  through the frame**, its arithmetic the frame's `+ - * /`, pulling a row a group; **its loess
  pulls each group's rows**, by the frame's `list` aggregate, since no engine could run it; **its
  gam sums each group's rows by knot interval through the frame**, each group split off and cut at
  its own knots, pulling a row an interval. **A bootstrap summary pulls each position's
  values**, by the frame's `list` aggregate, as a summary function does, since resampling has
  no frame operation, and hands its resample means back to the frame for their quantiles. **A
  density is four passes
  through the frame**, its grid points `floor` in an expression, pulling a row a group and its
  totals at each grid point.
- **A stat names the computed column each aesthetic takes by default, `default_mapping/1`**,
  ggplot2's `after_stat()` defaults (`%{x: :count, y: :count}` for counting). The assembly puts it
  into an aesthetic the layer maps to nothing, and titles that aesthetic's guide by it as a
  fallback, which any layer's column or expression replaces.
- **A stat names what a mapping's after_stat can read: its computed variables as ggplot2
  documents them** (`computed_variables/0`: counting's `count` and `prop`, not the `width` and
  `flipped_aes` its table also holds; the box plot's summary's whiskers, hinges, notches and
  `width`, each in either orientation, not its `outliers` or `relvarwidth`; smoothing's `y`,
  `ymin`, `ymax` and `se`, each in either orientation; a density's `density`, `count`, `scaled`,
  `ndensity`, `wdensity` and `n`; a violin's `density`, `scaled`, `count`, `violinwidth`, `n`,
  `width` and `quantile`; hexagonal binning's `count`, `density`, `ncount` and
  `ndensity`, not the `width` and `height` its table also holds), **and the aesthetics
  it consumes** (`dropped_aesthetics/0`, ggplot2's `dropped_aes`: counting's, hexagonal
  binning's, smoothing's, a density's and a violin's `weight`, the box plot's summary's `x`, `y`
  and `weight`, and counting at each
  place's, which `StatSum` sums without declaring), module functions beside its accepted aesthetics,
  which `Plot` reads at the call. A stat with neither, the identity, computes nothing an after_stat
  can read.
- **Counting is ggplot2's `stat_count()`**: a row per distinct x of each group, its `count` the rows
  there or the sum of their weights, a missing weight (`nil` or NaN) adding nothing and an
  infinite one making the count infinite, its `prop` the count's share of its group's total, the
  sum of its counts' magnitudes, divided as R divides (`Giggly.DataFrame.Arithmetic`: NaN for a
  total of zero or an infinite count over an infinite total, 0 for a finite one), and its `width`
  the one the layer sets, the stat's `width`, as `stat_count()` takes it, else 0.9 of the layer's
  x spacing counting from zero (`Giggly.Resolution`), 1 on a discrete axis. A weight that is not a
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
- **Hexagonal binning is ggplot2's `stat_bin_hex()`, each row in the hexagon hexbin puts it in**
  (design-log §4, the entries beginning "`geom_hex()` puts each row" and "`geom_hex()`'s `bins:`
  and `binwidth:`"): per panel and per group, the rows at a finite x and y; the bins `binwidth`
  wide and high, else each panel's axis's extent unwidened over its own `bins`, as ggplot2's
  documentation describes a pair, not as its 4.0.3 divides x's twice; each group's hexagons from
  its own least and greatest x and y, rounded out to the bins and a millionth beyond, as
  `hex_bounds()` does; a row's hexagon the nearer of two lattices' nearest centres, computed in
  the frame (`floor`, arithmetic, `<`, `if_else`), with hexbin's single-precision √3, and its
  centre with the double √3, as `hcell2xy()`, so `layer_data/2` holds R's doubles. A row per
  hexagon with rows, in hexbin's order, its `count` the rows or their weights' sum, as R's
  `sum()` adds them, a hexagon whose sum is missing or NaN left out, as `na.omit()` leaves it,
  an infinite one counted; `density` the count over the group's total, `ncount` and `ndensity`
  over the group's largest, divided as R divides. **Where ggplot2's binning fails the whole panel
  is given no rows**, as it catches the failure per panel: bins of no width, as an axis of no
  extent gives `bins`, or hexagons that would not span a group's rows, which hexbin refuses. A
  discrete axis is binned on its positions; fill takes `count` by default; it needs `x` and `y`
  and consumes `weight`. A weight that is not a number is refused when the plot is run.
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
- **Summarising is ggplot2's `stat_summary()`** (design-log §4, the entries beginning "A
  summary's values are names", "A summary carries a column cell by cell", "The Hmisc summaries
  take" and "`mean_cl_boot` draws its resamples"): per panel, group
  and x, in that order, the rows at a finite x and y; `y`, `ymin` and `ymax` from `fun_data`,
  `{:mean_se, mult: mult}`, the frame's `mean`, and its `variance` over its `count`,
  square-rooted and times `mult` in R's order, missing for one value; Hmisc's `:mean_sdl` and
  `:mean_cl_normal`, centred on the frame's `sum` over its `count`, their squared distances from
  it the frame's, the normal's t `Giggly.Stat.TDistribution`'s; `:median_hilow`, the frame's
  quantiles; `:mean_cl_boot`, the frame's `mean` and the quantiles, the frame's, of each
  position's resample means, drawn by `:rand`'s `exsss` from its seed afresh, never R's numbers;
  the ends missing for one value but the median's; or from `fun`, `fun_min`
  and `fun_max`, each a frame aggregate by name (`:median` the type 7 quantile at one half), a
  function of the values the frame's `list` pulls, which must return a number, or missing;
  `flipped_aes`, along y by `orientation` or where y alone is discrete, flipped and flipped back.
  It carries no group's constant columns: each other column goes to each cell holding one of its
  values, missing in a cell holding more, dropped where every cell does, a column it writes
  never, a range it does not write as R carries it. It computes nothing an after_stat can read
  and consumes nothing.
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
  one as any set aesthetic does, else 0.75 of the layer's x spacing from zero, 1 on a discrete
  axis. The orientation and the spacing are read from every row, as R reads them; then a row
  missing its x or y, or at an infinite one, is left out, and a group left with none has no box.
  **It runs along the axis R's `has_flipped_aes()` picks for a box plot**: `orientation`, else the
  one axis mapped (y at x 0, or x), else the continuous axis beside a discrete one, else y where
  every group holds one x and x where every group holds one y, else y, where R also warns. A width
  that is not a number is refused when the plot is run.
- **Smoothing is ggplot2's `stat_smooth()` with `method = "lm"`, R's `lm(y ~ x, weights =
  weight)` read through `predict()`, or `method = "loess"` or `"gam"`, below** (design-log §4, the
  entries beginning "A linear smooth fits
  the slope" and "A smooth given no method is fitted as ggplot2 chooses"): per panel and per
  group, `n` rows at R's `seq()` from the group's least x to its greatest, or across the unwidened
  extent of the panel's axis it runs along with `fullrange`, its y axis along y, where ggplot2
  reads `scales$x` (design-log §4, the entry beginning "A full-range smooth spans"); `y` the
  weighted mean of y plus the slope times the distance from the weighted mean
  of x; with `se`, `se` the residuals' variance times one over the weights' total plus that
  distance squared over x's sum of squares, square-rooted, and `ymin` and `ymax` `y` ∓ `se` times
  Giggly's t quantile at `level` (`Giggly.Stat.TDistribution`: Abramowitz and Stegun 26.7.3-4,
  bisected, or for a fraction of degrees of freedom the incomplete beta function, R's `qt()` within
  1e-12 up to a level of 0.999 but at the fewest degrees of freedom, where R's own drifts,
  design-log §4, the entry beginning "The t quantile keeps"); and
  `flipped_aes`, along y with x and y swapped. Its values are R's within
  1e-12 of the largest magnitude the group's column holds, its x R's to the last digit. A row
  missing or infinite in x or y is left out; a group of fewer than two distinct x is fitted
  nothing. **Its weights are R's `lm()`'s**: a missing one leaves its row out, a negative or
  infinite one fits the group nothing, where ggplot2 also warns, and a zero one leaves its row out
  of the fit and of the degrees of freedom, the rows weighted above 0 less two, so a group of
  only zero weights is fitted nothing. Weighted rows at one x give a flat curve at their weighted
  mean with a degree of freedom more, as R drops a slope it cannot fit; otherwise the slope is
  fitted however little x varies. Of no degrees of freedom, `se` and the band are NaN. **A smooth
  given no method (`:none`) is fitted by loess where the largest group in any panel has under
  1,000 rows**, every row counted, and by gam from there. A weight that is not a
  number is refused when the plot is run.
- **A loess smooth is R's `loess(y ~ x, weights = weight, span = span)` fitted directly at each
  place, as `surface = "direct"`** (`Giggly.Stat.Loess`; design-log §4, the entries beginning
  "loess is Giggly's own", "A loess band takes its first trace", "A loess curve stops at its rows"
  and "A loess group whose neighbourhoods cannot hold a quadratic"), in plain Elixir on each
  group's rows: at each place a quadratic fitted by weighted least squares to the ⌊n × span⌋
  nearest rows, tricube-weighted by distance over the qth nearest's (past a span of 1 every row,
  over the largest distance times the span's square root, as R takes it), times each row's
  weight; with `se`, `se` the residuals' scale over the first trace δ₁ of (I - L)ᵀ(I - L) times
  the operator's weights squared over each row's weight, square-rooted, and the band at the t
  quantile with δ₁ degrees of freedom. Its values are R's direct loess within 1e-12 of the largest
  magnitude a group's column holds, its band R's at δ₁; its places past the rows are missing. A
  row missing its weight is left out, a row of weight 0 kept, making `se` NaN, as R's; a negative
  or infinite weight, or a neighbourhood at a place, or with `se` at a row, holding fewer than
  three distinct x weighed above 0, fits its group nothing. Every curve and golden is checked
  against ggplot2 drawing R's loess so (`test/golden/giggly_loess.R`).
- **A gam smooth is mgcv's `gam(y ~ s(x, bs = "cs"), weights = weight, method = "REML")`**
  (`Giggly.Stat.Gam`; design-log §4, the entries beginning "gam is Giggly's own" and "A gam's
  shrinkage"), from Wood's published method: a natural cubic regression spline with 10 knots at
  the type-7 quantiles of the group's distinct x, straight past its end knots, held to sum to 0
  over the rows, unweighted; its penalty S = Dᵀ B⁻¹ D with the constant and the straight line
  through the knots each given 0.055 of S's smallest positive eigenvalue, where mgcv's "cs" gives
  0.1 and 0.01 along directions its rounding picks; λ minimising REML, searched over 61 values of
  log λ a step apart and narrowed by golden section; `se` mgcv's Bayesian standard error, its
  scale the weighted residuals over every row less the effective degrees of freedom, and the band
  at Giggly's normal quantile (`Giggly.Stat.NormalDistribution`), as ggplot2 reads a gam's band.
  Its values are within 1e-6 of the range of the group's y of mgcv fitting that model, its
  standard errors 1e-5 relatively, its places R's to the last digit; R's own, over diamonds,
  within 1e-3. Its 10 by 10 algebra is plain Elixir (`Giggly.Stat.Matrix`), never Nx. A row
  missing its weight is left out; a row of weight 0 places the knots and counts for the
  constraint and the scale, but not REML; a negative or infinite weight, fewer than 10 distinct
  x, or rows weighted above 0 sharing one y fit its group nothing, where mgcv fails; rows on a
  straight line are fitted the line with a band of no width, where R's is rounding's. Every curve
  and golden is checked against ggplot2 drawing mgcv's gam so (`test/golden/giggly_gam.R`), and
  one golden against R's own (`test/golden/smooth_gam.R`).
- **Densities are ggplot2's `stat_density()`, R's `density()`** (design-log §4, the entry beginning
  "A density takes ggplot2's options"): per panel and per group, along whichever of x and y is
  mapped, exactly one, flipped and flipped back; `n` places at R's `seq()` across the panel's axis
  short of its widening, or the group's own extent with `trim`; the bandwidth a number, or
  Silverman's rule (`:nrd0`, falling back as `bw.nrd0()` does) or Scott's (`:nrd`) from the
  group's rows inside the bounds, unweighted, by the frame's `variance`, `quantile` and `first`,
  times `adjust`; each row's share of its group's weights spread linearly over a grid of at least
  512 points, a power of two past that, four bandwidths past the places either end, so every row
  lands inside it, the parts summed plain, lower and upper apart; convolved with one of
  R's seven kernels through `Giggly.Tensor`, raised to 0, and read at the places by R's `approx()`
  formula (`Giggly.Stat.Curve`, which also spaces smoothing's places and reads aligning's
  groups). Its values are R's within 1e-12 of the largest magnitude the group's column holds, its
  places R's to the last digit. **With a finite bound** the rows outside are left out, the rest's
  shares divided by what they leave where that is above 0, and the curve worked out on the axis
  widened by its width beyond each finite bound, on `n` times one more than their count of places,
  then folded back inside, as `reflect_density()` does. A row missing or infinite in x is left out;
  a group of fewer than two rows inside the bounds is one row of missing values. **Where R's
  `density()` fails the whole panel is given no rows**, as ggplot2 catches the failure per panel:
  a share missing, infinite or below 0, which weights totalling 0 make too, a bandwidth not finite
  and above 0, or a missing share total with rows outside the bounds. A weight that is not a number
  is refused when the plot is run; a discrete axis is computed on, as R computes it. Its estimate
  is `Giggly.Stat.KernelDensity`, ggplot2's `compute_density()`, which a violin's densities
  compute with too.
- **A violin's densities are ggplot2's `stat_ydensity()`**, through the density's estimate: per
  panel and per group, the rows finite in x, y and weight; a group of fewer than two left out, or
  with `drop: false` one row of its x, y and `n`; 512 places across the group's y, widened by
  three of the rule's bandwidths, before `adjust`, without `trim`, **the bandwidth from all the
  group's rows**, where a density's reads those inside the bounds (R draws it so); `x` the
  group's, or its x range's middle, `width` 0.9 of that range, else the stat's; a row for each
  of `quantiles`, in their order, at the frame's type 7 quantile of the group's y, unweighted as R
  takes it, its other columns read along the curve by R's `approx()` formula, a curve row at its
  y left out; `quantiles: :none` writes no `quantile` column, R's `NULL`, and `[]` one of missing
  values, R's `numeric(0)`; `violinwidth` by `scale` over the panel's greatest density and most
  rows. Its values are R's within 1e-12 of the largest magnitude a column holds. **A panel is
  given no rows where its estimate fails or a group with quantiles has fewer than two rows inside
  the bounds**, which R's `approx()` cannot read; without quantiles that group is one row of its
  x and width. It runs along the axis `has_flipped_aes()` picks for a violin, the box plot's rule
  without its one-axis case, since a violin needs both. With `drop: false` and the first group a
  short one, R's `layer_data()` orders its columns otherwise; Giggly keeps its usual order.
- **`Giggly.Tensor` is the one module that builds a tensor, and a stat reaches Nx only through it**
  (design-log §4, the entry beginning "Nx is a core dependency"): lists in and out, every tensor on
  `Nx.BinaryBackend` in 64-bit floats, so a user's default backend never reaches a drawing, the
  transform's threshold 0 (`eps: 0`), and a `defn`, when one arrives, through `Nx.Defn.Evaluator`.
  Its boundary lists Nx, as the root does, and Stat lists it; it is held here, beside its callers.
