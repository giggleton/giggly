# giggly — Design Notes

The design overview, the decision log and an index of milestones. CLAUDE.md says what applies to
every session; the area files under `.claude/rules/` give each area's invariants and the modules'
documentation how it works; this file says **why** — what was decided and what was rejected — and
indexes what shipped when, each commit's message telling its story. It is reference: read an
entry by name, never the whole file. The `docs-sync` skill routes changes here;
`.claude/rules/docs.md` is the shape.

## 1. What we're building

Giggly is a grammar-of-graphics plotting library for Elixir, modelled on R's ggplot2 and the
from-scratch successor to ggity. A plot is an immutable spec built with a pipe — data, a mapping
from aesthetics to columns, layers (each a geom, a stat and a position), scales, a facet and a
coordinate system — which a build step turns into per-panel layer tables and trained scales, and a
render step turns into a scene graph and then SVG. It is for Elixir developers, especially those
already fluent in ggplot2, who want declarative, composable charts in Phoenix LiveView, Livebook
and static files without a JavaScript rendering step.

The pre-design research — how ggplot2's build pipeline, scales, layout, facets and coords fit
together; why ggity could not grow facets or coordinate systems; and what the Elixir ecosystem
offers — is working material outside the repo, in `~/.claude/plans/giggly-research/` (its
`00-synthesis.md` is the proposed build order), as CLAUDE.md asks of plans. What is drawn from it
moves into §4, with its rejected alternatives, as each decision is ratified.

**Roadmap** (Phase 0's, as amended in §4): **1** — a scatter plot that is architecturally
complete, every seam in its null form (done); **2** — prove the seams before widening: `facet_wrap`
with free scales (done), then `coord_radial()` as a full circle with no inner radius (the §4 entry
beginning "Giggly follows ggplot2's current coordinate functions"; done); **3** — breadth, bars
first (in progress): stats, stack
and dodge, bar, line and boxplot geoms, non-position scales and guides, the theme tree; **4** — the
LiveView layer: HEEx output, per-mark attributes applied once at the scene, stable ids, optional
PNG.

## 2. Architecture & principles

Giggly is a pipeline over immutable values. `%Giggly.Plot{}` is the value the public pipe builds:
data, a mapping from aesthetics to columns, layers (each a geom, a stat and a position), scale
specs, a facet, a coord, labels and a theme. A plot describes and runs nothing; the functions in
`Giggly` take a finished plot and run it, as ggplot2's `ggsave()` and `get_layer_data()` take a
finished ggplot. `Giggly.Assembly` turns a plot into what is drawn, gaining a stage per increment
until it holds one data frame per layer in the aesthetic vocabulary with `panel` and `group`
columns, the layout table, the trained scales and the per-panel view scales (panel params).
Rendering turns that into a scene, a tree of drawing primitives sized in units inside a table
layout, and a backend (SVG first) serializes it. The assembled value and the scene are internal:
what a user inspects is asked of the plot (`Giggly.layer_data/2`), and each value is still
separate, which is how the facet and coord seams are tested without rendering anything.

The whole pipeline is pure. Its only input is the plot spec, whose data `Giggly.Plot.new/2` has
already read from a `Table.Reader` into a frame; it reads no config, no clock and no randomness
(jitter will take a seed). The impure edges are adapters at the rim: reading the input table, and
whatever a host does with the emitted iodata. `boundary` holds the shape (`mix boundary.spec`
prints the graph): every boundary is strict, each domain is a sub-boundary carved when its first
module lands with its `deps:` as its contract, a domain that owns an outside library lists it as
the root does, and the `CorePurity` check reads all of `lib/`.

Two cross-cutting rules come straight from the ggplot2 study and ggity post-mortem (§1 points at
the research): **a geom never sees a panel, a pixel or a facet variable** — facets are a column
and a lookup table, the coord is the only route from data space to the unit panel, and layout is
resolved by the scene's table of tracks, not by arithmetic in geoms; and **cross-cutting concerns
get a seam before the second user of them exists** — grouping, panels, coordinate transforms and
per-mark attributes are each applied in one place the pipeline threads through, never
re-implemented per geom.

## 3. Module map

`lib/giggly.ex` is the umbrella root and holds the functions that run a plot: `layer_data/2`
today, and `to_svg` when it is written. `Giggly.Plot` builds the plot value, `Giggly.Assembly`
runs the stages, and each other area of the pipeline is a module or namespace directly under
`lib/giggly/`, with its invariants in a `.claude/rules/<area>.md` that CLAUDE.md's status map
names — the status map is the index, and each module's documentation is its contract: an API
module's moduledoc, an internal module's opening comment.

## 4. Key design decisions (the "why", so we don't relitigate)

Each entry: **the decision (date, whose call)**, then *Rejected: the alternative* — and why. Newest
first. A decision belongs here when someone could plausibly propose undoing it; the entry is what
stops the question being reopened from scratch. A new entry is about 150 words: the decision, a
sentence or two of why, and one line per rejected alternative. What a later decision replaces is
deleted from the entry it was in, never marked superseded; git history keeps every version.

- **A loess band takes its first trace as its degrees of freedom, where R's exact statistics read
  δ₁² / δ₂ (2026-10-25, Steve: "B").** The band is the curve ∓ t × se; δ₁ = trace((I - L)ᵀ(I - L))
  costs n² and δ₂, the trace of its square, n³: 0.13 s at mpg's 234 rows, 2.2 s at 500 and 24 s at
  999, the most rows a smooth given no method sends to loess. With δ₁ the curve and `se` stay R's
  exact ones, and the band's edges sit within 2e-6 of the curve's range of R's exact band for mpg,
  5e-5 for mtcars, 2.9e-3 for 8 rows: nearer than R's own default, which approximates both traces
  by a Fortran table (2.5e-4 for mtcars, 0.14 for 8 rows). *Rejected: both traces exactly* — R's
  exact band, at 24 s for a 999-row group. *Rejected: R's table (`ehg141`)* — a port.

- **A loess curve stops at its rows: with `fullrange: true` its places past them are missing
  (2026-10-25, Steve: "A").** R's default surface gives no value outside the rows' extent, so
  ggplot2 draws the curve and band across the data alone; R's direct mode, whose fits Giggly's are,
  extrapolates each place's quadratic (50.9 at displ 0 for mpg, past every car's hwy). Giggly takes
  the direct fit inside the rows and the default's missing values outside. *Rejected:
  extrapolating* — a curve R never draws by default.

- **A loess group whose neighbourhoods cannot hold a quadratic is fitted nothing, nor one with a
  negative weight (2026-10-25, Steve: "A").** A neighbourhood needs three distinct x weighed above
  0: q = ⌊n × span⌋ of 3 or less, a tie at the qth distance, or a qth distance of 0 leaves fewer.
  R warns and returns its pivoted solver's values there ("span too small", "reciprocal condition
  number 0", the rows' own y), and fits a negative weight's neighbourhood 0, none of it a formula
  Giggly could reproduce without a port. *Rejected: Giggly's own minimum-norm fit, and negative
  weights as the formula takes them* — a curve where R draws one, but not R's curve.

- **A density takes ggplot2's options, `bounds:` and all seven kernels among them, and a failing
  estimate leaves its panel empty, as R's does (2026-10-25, Steve: "A" for bounds, "A" for the
  kernels; checked against ggplot2 4.0.3 and R 4.6.1).** `geom_density/3` and `stat_density/3`
  take `bw:` (`:nrd0`, `:nrd` or a number), `adjust:`, `kernel:`, `n:`, `trim:`, `bounds:` and
  `orientation:`, and compute `density`, `count`, `scaled`, `ndensity`, `wdensity` and `n`.
  `bounds:` folds a curve's tails back inside a finite bound on `n` times one more than the finite
  bounds' count of places, as ggplot2 does; bounds high to low are refused at the call, where R
  keeps no row. Where R's `density()` fails (a share missing, infinite or below 0, a bandwidth not
  finite and above 0) ggplot2 draws nothing for the whole panel, and so does Giggly.
  `stat_density/3` gives its area no line join, drawn round and keyed mitred, as R falls back. The
  grid's totals are summed plain, as R's binning adds in doubles: long-double sums came closer to
  R on one case of four and further on two. *Rejected: deferring `bounds:`* — on the reference
  page, and its fold is the curve's own interpolation. *Rejected: the Gaussian kernel alone* —
  each other kernel is one formula on the kernel's grid. *Deferred:* the `ucv`, `bcv` and `SJ`
  bandwidths, `position_fill()`, a density given to another geom by name.

- **A full-range smooth spans the axis it runs along, its y axis along y, where ggplot2 spans the x
  axis's extent (2026-10-25, Steve: "B").** ggplot2's `StatSmooth` flips its data to fit along y
  but reads `scales$x$dimension()` unflipped, so `geom_smooth(orientation = "y", fullrange =
  TRUE)` over mpg's `aes(displ, hwy)` runs its curve at hwy 1.6 to 7, displ's range, below every
  car's 12 to 44, and stretches the y axis to it, where `fullrange` is documented to expand the
  line to the range of the plot. Giggly reads the axis the curve runs along, its values checked
  against R's same fit along x, `aes(hwy, displ)` over a widened axis. *Rejected: R's x axis* —
  the drawing would be R's, but the curve leaves the data it was fitted to for another axis's
  numbers.

- **A linear smooth fits the slope however little x varies, where R's `lm()` drops it (2026-10-25,
  Steve: "A").** R's `lm()` reads x as one with the intercept once its spread about its mean is
  under a ten-millionth of its size (`lm.fit()`'s QR tolerance, 1e-7) and draws a flat line at the
  mean with a degree of freedom more: x from 1,000,000,000.1 to .9, or two minutes of timestamps
  in seconds since 1970. Giggly's three passes centre x first, so its size never matters, and fit
  the least-squares slope, as Scholar's regression would; a curve is flat only where its weighted
  rows hold one x, which R draws flat too. Every dataset checked (mpg, mtcars, diamonds,
  economics) fits a slope both ways. *Rejected: R's tolerance, from x's spread about its mean
  against its spread about 0* — the drawing would stay R's, but R's flat line comes from its
  method, not the data.

- **A smooth given no method is fitted as ggplot2 chooses when the plot is run: by loess where its
  largest group in any panel has under 1,000 rows, and refused from there, naming gam (2026-10-25,
  Steve: "B").** ggplot2 picks loess or gam as the plot is built, and a facet added after the layer
  changes the answer (txhousing: gam whole, loess by city). So the stat counts every row as
  `setup_params()` does; step 5 replaces the refusal with gam and keeps the count. *Rejected:
  refusing at the call* — the error would point at the line that wrote it, but the choice is the
  run's.

- **The t quantile keeps the agreed closed form for whole degrees of freedom, and takes a fraction
  from the incomplete beta function, held to R's within 1e-12 for levels up to 0.999 (2026-10-25,
  Steve: "A", and "A" for fractions, loess's step).** A loess band's degrees of freedom are its
  first trace, never whole: their share outside ±t is I_x(ν / 2, 1/2), from its continued fraction
  where t² ≥ ν and its series of positive terms below, the beta function from Stirling's series,
  within 1.6e-13 of R's `qt()` over 2,000 random cases from 0.3 to 100,000 degrees of freedom.
  *Rejected: interpolating between whole degrees of freedom* — 3.6e-3 of the quantile at 3.4, a
  small group's band; rounding them, 7%. A&S 26.7.3-4 give the share within ±t, so near a level
  of 1 the little outside it keeps fewer digits than R's `qt()`, which works from the tail: over 1 to
  100,000 degrees of freedom the quantile is within 7e-14 of R's, relatively, for levels 0.1 to
  0.99, 4e-13 at 0.999 and 1.2e-10 at 0.999999; mpg's band is within 1e-13 of its column at
  0.99999 and 1.7e-12 at 0.999999, past the bar and far below a drawing's resolution. Near a level
  of 0 R's drifts (3.5e-10 at 4 degrees of freedom, against exact decimals) where Giggly's does
  not. Powers of a rounded cos²θ drift 1e-11 at large df, so every 32nd is worked out afresh from
  the logarithm of its complement and the terms added with Neumaier's compensation, which plain
  summation misses at 0.999 (1.1e-12, at 86,377 degrees of freedom). *Rejected: a
  second series summing the tail for high levels* — the bar everywhere, for levels hardly anyone
  sets, at about three times the terms.

- **Smoothing and densities are Phase 3's twelfth increment, in five steps: ribbons and areas
  (`geom_ribbon()`, `geom_area()` with its stat_align, stacking areas), linear smooths
  (`geom_smooth()` and `stat_smooth()` with `method: :lm` and its band), densities
  (`geom_density()`, `stat_density()`), loess, and gam (2026-10-25, Steve, agreeing the proposal
  decision by decision; checked against ggplot2 4.0.3's source and R).** Stats were the thinnest
  family, nothing fitting a curve or estimating a density, and `geom_smooth()` is the layer most
  used after points: in r4ds and the ggplot2 book about 55 smooths name no method on tables under
  1,000 rows (loess), 18 use lm, one gam. A smooth with no method raises, naming what waits, until
  loess and gam land. The theme's `geom` element gains `accent` (#3366FF), the smooth's colour. The
  t quantile is Giggly's own, the t distribution's closed form for whole degrees of freedom
  (Abramowitz & Stegun 26.7.3-4) inverted by bisection: Nx and Scholar have no distributions, and
  Hex's `statistics` is good to 4 decimals. gam's use of Scholar is asked with its step.
  *Deferred:* `formula:`, `method_args:`, `xseq:`, `method: :glm`, a function as a method; the
  `ucv`, `bcv` and `SJ` bandwidths; a gradient fill along a ribbon, refused when drawn;
  `position_fill()`; `stat_align()` as a function; a geom given a stat by name; ggplot2's messages;
  a stat's `finish_layer()` (Steve: "B"), which in ggplot2 only `StatAlign` overrides, to drop a
  padding row a limit cuts, so such a row keeps its missing x in `layer_data/2`, the drawing R's;
  `annotate("ribbon")` and `annotate("area")`; a ribbon's positions set as options
  (`geom_ribbon(ymin = 0)`, which R takes without training the axes on them) (Steve: "Defer").

- **Nx is a core dependency, reached only through `Giggly.Tensor`, which takes and gives lists and
  pins every tensor to `Nx.BinaryBackend` in `f64` and every `defn` to `Nx.Defn.Evaluator`
  (2026-10-25, Steve: "Core").** A density's FFT and gam's linear algebra run on Nx; loess runs in
  plain Elixir (Steve: "A"), its 3 by 3 local fits 0.36 s at 999 rows against 12 s batched on the
  binary backend, which decodes and re-encodes every number at every step and fuses nothing. Nx
  reads its default backend and `defn` options from the application environment and
  the process dictionary on every call; so no other module builds a tensor, and a user's EXLA
  default cannot change a drawing. Nx starts its own application (a `:pg` scope for
  `Nx.Serving`), which Giggly never calls. `Nx.fft` takes `eps: 0`, since its default, 1e-10,
  zeroes a density's tails. *Rejected: an optional `giggly_nx` package* — the most-used smooth
  would raise without it, and loess and gam would need a public smoothing-method behaviour
  designed with one implementation. *Rejected: `to_tensor` on the frame* (Steve asked) — the list
  hop costs 0.05 ms at 1,024 values and 4 ms at 53,940, against 1.4 s for one gam product; should
  an engine need it, the frame hands a column as a binary of doubles and `Giggly.Tensor` pins it,
  so Nx stays out of the frame.

- **Smoothing and densities compute over the rows through the frame where an engine could, and on
  Nx only what the frame has summarised; three stats pull their rows (2026-10-25, Steve).** A
  density's count, variance (a new `variance` aggregate, R's `var()`) and quartiles, each row's
  binning slot and shares (arithmetic and `floor` in expressions) and the slots' totals (two
  grouped sums, of lower and of upper shares, merged on the summarised output) are frame
  operations; Nx sees the 1,024 binned values. lm is three passes of sums (means, centred sums,
  residuals), Scholar's centre-then-solve method, pulling a row per group. Interpolation,
  stat_align's and a density's, is R's `approx()` formula on lists. stat_align pulls the panel's
  rows, its output as large as its input, as the identity's is, so an engine would save nothing;
  loess and gam pull each group's, since no engine can run them (§7, "Engine backends"). *Rejected:
  binning or lm on pulled rows in Nx or Scholar* — every row would cross into Elixir. *Rejected: an
  operation stacking two tables for the binning* — summing in another order than R's moves the
  result 1e-16 of the peak. *Rejected: Scholar's interpolation* (Steve: "formula") — the same
  numbers to 2e-16, 14 times slower, and over every row in stat_align.

- **loess is Giggly's own: a quadratic fit at each of the curve's points, tricube-weighted over
  `span` of the nearest rows, as R's `loess(surface = "direct")`, named as a departure from R's
  default (2026-10-25, Steve).** R's default fits at a k-d tree's vertices and joins them with
  cubic pieces, its cells cut by a rule only its Fortran states. On the notebooks' 700 by 433
  drawing the direct curve sits up to 1.75 points (mpg), 2.30 (mtcars) and 5.76 (faithful) from
  R's default, a third of a point to a point on average, its band's edges up to 7.1; R's
  approximation of the band's two traces moves it less than 2.5e-4 of the curve's height, so the
  gap is the surface's alone. Its goldens are drawn by R in direct mode. *Rejected: no loess* — a
  smooth with no method would keep raising on every table under 1,000 rows, the common call.
  *Rejected: R's k-d tree* — a port. *Rejected: gam at every size* — another method, not a
  departure.

- **A stat's values reached by another route than R's are held to R's within a tolerance
  (2026-10-25, Steve).** Density (R's FFT), lm (the frame's sums against R's QR), the t quantile
  and loess in R's direct mode, its band at the first trace's degrees of freedom (the entry
  beginning "A loess band takes its first trace"), are held to 1e-12 of the largest magnitude R's
  column holds in the group, about a thousand times the gap measured (an FFT against a plain sum,
  5-8e-16 of the peak). gam is held to 1e-3 of the range of the group's y data, its standard
  errors to 1e-3 relative, since R's own optimiser, run tighter, moves its curve 2.4e-4 of its
  range and its standard errors 4.5e-4 (diamonds); its goldens are checked through their layer
  data, as 1e-3 is up to a third of a point. x columns, stat_align and stacking stay R's to the
  last digit. *Rejected: a bar per value* — a density's tails and a curve near zero are round-off
  in R itself. *Rejected: the range of a curve for gam* — it vanishes where a fit comes out flat.
  *Rejected: porting R's FFT* — Giggly ports no R or C source.

- **A text's family is the theme's, inherited as any property, and every complete theme takes
  `base_family:` and `header_family:` (2026-10-24, Steve: "Let's get family working with the
  default implementation"; checked in R).** `base_family` is the root text's family and the
  `geom` element's, so the layers'; `header_family`, where given, is `title`'s, which ggplot2's
  tree gives only the axes' titles, the legends' titles and the plot's title, so the subtitle,
  caption, tag, strips, tick labels and legend labels keep the base family, as `calc_element()`
  gives every leaf of the eight themes; unset is `:none`, R's `NULL`. `theme(text: [family:])`
  never reaches a layer. Every family is measured with the built-in table, as vdiffr measures
  each. The SVG writes `""` and `"sans"` as the default list, `"serif"` and `"mono"` as CSS's
  `serif` and `monospace`, and any other name as a CSS string before the default list.
  *Rejected: a named family written alone* — a browser lacking it draws its own default, often a
  serif, at sans widths. *Rejected: a family argument to `Giggly.Font` now* — no measure differs
  by family until the package does. *Rejected: following ggplot2's docs, which give the tag the
  header family* — R gives it the base. *Rejected: CSS's names for the Symbol font for R's
  `"symbol"`* (Steve) — what a reader sees would turn on the fonts their machine has; it is
  written as any other name.

- **A font family is a name, measured by an optional package of its own where that package has
  the family, and by the built-in Liberation Sans table otherwise (2026-10-24, Steve, after
  surveys of Hex and checks in R).** `family:`, `base_family:`, `header_family:` and a layer's
  `family:` name fonts; no font value travels in a plot. The package is a Rust NIF over
  HarfBuzz's shaping (harfrust, skrifa, wuff; Rustler and rustler_precompiled), in its own
  repository, and never depends on Giggly. Giggly will list it as an optional dependency and hold
  the adapter behind `Code.ensure_loaded?`, with no behaviour yet, keeping R's rounding itself.
  `""` and R's generic names stay on the built-in table unless a font is registered under that
  name, so the goldens never move. *Rejected: a TrueType parser of our own* — no ligatures or
  contextual forms, which svglite's HarfBuzz applies, and a thousand lines to own. *Rejected:
  Hex's parsers* — none reads GPOS kerning correctly (`truetype_metrics`, `opentype`,
  `tincture`). *Rejected: measuring by rendering (resvg, libvips)* — the ink box, not the advance
  ggplot2 lays out with. *Rejected: fonts as values passed to `to_svg/2`* — names are the only
  input. *Open:* how the package finds a family's files (a registry is recommended).

- **Text's face, angle, justification and line height are the theme's, and every text a guide
  draws is placed and measured by one rule, ggplot2's `titleGrob()` (2026-10-24, Steve, agreeing
  the proposal and its three recommendations; checked in R).** A text takes `face:`, `angle:`,
  `hjust:` and `vjust:` (numbers, as R's `element_text()` refuses words) and `lineheight:`;
  `gray/1` and `void/1` give R's defaults, the y title's 90 degrees among them, and a legend's
  title and labels take their justification from the text their side lays over the theme.
  `Guide.Parts` anchors a text at `rotate_just()` of its room, moved by the margins it counts, and
  measures grid's box round it turned with its descent, so 432 R drawings, every 15 degrees by
  each justification, matched. A face is an SVG style, measured at plain widths, as vdiffr
  measures. *Rejected: R's `"oblique"` and faces 1 to 4* — second spellings no example writes.
  *Rejected: a negative `lineheight`*, which R stacks upward. *Rejected: failing where only a
  removed root text gives a justification*, as R does — grid's centring, as every such property
  falls to grid. *Rejected: a bold glyph table* — the goldens would leave R's. *Deferred:*
  `family`, `guide_axis(angle =)`, multi-line labels and strips.

- **The mutation pass runs muex's mutants in warm VMs, each against the whole suite (2026-10-24,
  Steve).** `warm.sh` starts workers that each load the app and the tests once, then compile each
  mutant over its module, recompile what read it while compiling and now reads something else, run
  the whole suite to its first failure, and load the originals back; muex builds the mutants and
  writes the JSON report, as a library, and one `:cover` run per worker finds the lines no test
  runs. It is sound because Giggly keeps no state for a mutant to leave (`CorePurity`); a mutant
  that changes a struct's defaults is reported, not judged. Replayed over step 6's pass, every
  kill, survivor and uncovered line matched muex's, and it killed three survivors muex's test
  selection never ran against; the element tree split's pass took minutes where muex took hours.
  *Rejected: muex's sandbox runner* — a fresh `mix test` a mutant and one file's mutants at a time;
  kept for credo checks and for checking this runner. *Rejected: a runner backend patched into
  muex* — a fork of a pinned dependency, where its public functions suffice. *Rejected: selecting
  a mutant's tests by coverage* — warm, the whole suite costs seconds, and selection missed tests
  (`computed_mapping/2` once, under a grouped alias). *Rejected: routing mutants among warm, app-
  restarted and fresh VMs* — Giggly has no process for a mutant to reach.

- **The theme's element tree is a boundary of its own, `Giggly.ElementTree`, beside `Giggly.Theme`
  (2026-10-24, Steve, choosing a peer over an export).** It holds ggplot2's `.element_tree` as far
  as Giggly draws, each element's name, kind, parent and description, and the `kind` type. `Theme`
  works out its kinds and parents from it and `Plot` builds `theme/2`'s schema and documentation
  from it, both in module attributes, and only those two list it. A module attribute's call makes
  its module depend at compile time on the whole file it calls, so while the table was in
  `theme.ex` every edit to `Theme`, and every `Theme` mutant, recompiled `plot.ex`; now only an edit
  to the table does. *Rejected: leaving the table in `Theme`* — that recompile on every theme step.
  *Rejected: `Giggly.Theme.Tree`, exported by `Theme`* — a boundary exports to every dependent, so
  `Assembly`, `Guide` and `Render` could read it too. *Rejected: `top_level?: true` to keep that
  name* — boundary's docs discourage it, and the namespace would place it inside `Theme` while the
  boundary placed it beside.

- **`Plot`'s options live in `Giggly.Plot.Options`, inside `Plot`'s boundary: every function's
  schema, the checks NimbleOptions calls and the defaults the functions share (2026-10-24,
  Steve).** `plot.ex` had grown to 7,200 lines, 3,000 of them schemas and their checks, the
  checks public on the API module because NimbleOptions calls them by name; every increment added
  more. `Plot` keeps its functions and their documentation, which writes each schema in while
  compiling, and reads a schema through an accessor per schema, so a misspelt name fails to
  compile; the two values guards read are copied into `Plot` attributes. No boundary changes.
  *Rejected: a top-level `Giggly.Options` for every domain* — Plot has 51 of the 55 schemas, and
  its checks read colours, shapes, the element tree and guides, so `Format` would reach the geoms
  through it, against extracting the scales half. *Rejected: an `Options` module in every domain*
  — nothing else needs one. *Rejected: one `schema(name)` lookup* — a misspelt name fails only
  when called.

- **Legends go where the theme puts them, each box placed as grid places a viewport, by a hang on
  its cell (2026-10-24, Steve, agreeing the proposal and including the box's margin and background;
  checked in R).** `legend_position` takes ggplot2's six places: a side's column or row outside the
  axes' titles, spanning the panels or, with `legend_location: :plot`, the plot; inside, every
  panel, whatever the location. A justification is resolved to `{x, y}` as `valid.just()` reads it;
  direction, arrangement and box justification stay `:none` until rendering works them out by
  position, as `Guides$draw()` and `package_box()` do. A box is placed by `hang: {:at, point,
  justification, size}`, which the generic layout lays out, so `{:left, w}` and nested tables'
  centring went. `theme_void()`'s unset `legend.spacing` is half a line, as `Guides$assemble()`
  fills it. The box's background inherits nothing (Steve: "what R draws"), as `package_box()` reads
  `legend.box.background` raw: 0.75 points of grid's black, not `rect`'s 1.07. *Rejected: inheriting
  `rect`*, as ggplot2's tree says and its drawing does not. *Rejected: a new cell field for the
  anchor* — a hang already says where a cell's box sits. *Rejected: null-unit rows round the box*,
  ggplot2's side margins — they cannot put a box's point anywhere but its justification. *Rejected:
  R's loose values* (an unknown position drawing none). *Deferred:* a guide's own position,
  direction, `nrow`, `ncol`, `byrow`; title and label positions; `legend.key.spacing.x`/`.y` as
  settings.

- **Each layer's defaults are filled in from the theme as columns, as ggplot2 4's `use_defaults()`
  fills `default_aes` from `element_geom()` (2026-10-24, Steve, choosing columns and leaving out
  R's refilled `width`; checked in R).** Each geom gives its defaults (`Geom.default_aesthetics/2`)
  from the complete theme's `geom` element, which every complete theme builds from its base sizes
  and paper. The assembly completes the theme once the positions are final, fills each layer's
  missing columns after the non-position scales map and before the set values, and fills each
  legend layer's keys the same way, so `layer_data/2` shows R's columns and no geom holds a look of
  its own. Ink is mixed toward paper by `ColorOperations.mix/3`, scales' `col_mix()`. *Rejected:
  geoms filling them as they draw* — `layer_data/2` would show fewer columns than R's, and every
  drawing function would take the theme. *Rejected: the theme holding the mixed colours* — the
  geoms' shares would sit in `Theme`. *Rejected: the `color` library's sRGB mix* — `#807F80` where
  R gives `#808080`. *Rejected: R's `width` of 0.9, put back once a bar is set up* — not the width
  it is drawn at. *Deferred:* `theme(geom = element_geom())`; text's `fontface` and `lineheight`.

- **A plot chooses a complete theme with `theme_gray/2`, `theme_bw/2` and the rest, each taking
  `base_size:`, `base_line_size:` and `base_rect_size:`, and records it by name with its sizes, or
  `complete: :none` for none (2026-10-23, Steve, agreeing the proposal; checked in R).** R's `+
  theme_bw()` replaces the plot's theme, so the function drops earlier settings. R lays each later
  `theme()` over an added complete theme in turn, but merges a plot's own settings first when none
  was added; the two differ only where an element is set after its removal, which a chosen theme
  records as `{:replace, element}`, what `%+replace%` would record. The widths default to
  `base_size / 22` at the call, so the plot holds what was resolved. Theme colours take an alpha,
  worked out as an opacity beside each `#RRGGBB`. In R the base sizes and `theme_void()`'s paper
  also reach the layers' defaults (`element_geom`), a step of its own (the entry beginning "Each
  layer's defaults are filled in"). *Rejected:
  `complete: :gray` with a flag* — `:none` says it. *Rejected: recording each call to fold when
  drawn* — the marker is the only difference. *Rejected: copying the tree into the plot* — loses
  the name. *Rejected: `theme(complete: :bw)`* — ggplot2's are functions.

- **The panel's border is never filled, though `theme/2` takes its `fill:`, and an axis's line
  comes from the coordinate system with its breaks (2026-10-23, Steve choosing to take the fill;
  checked in R).** ggplot2 draws `panel.border` with `fill = NA` and takes a fill without a
  warning; one also reaches the border from `rect`, so refusing it given directly would give
  `panel_border` a schema of its own. `Coord.axes/2` places each axis's line beside its breaks, as
  ggplot2's guide munches its `decor` through the coordinate system: radially a ray of 30 points
  and a circle of 186, which no guide could place. The theme works a line type into dashes in
  points as it works out a line width, so svglite's rule sits in `Theme` and in `Geom.Mark`, each
  pinned to R's numbers. *Rejected: refusing the border's `fill:`* — a special case for what R
  takes. *Rejected: a protocol function for axis lines* — a line belongs to its axis. *Rejected:
  one home for the dash rule* — `Theme` lists nothing, and would list a boundary for five lines.
  *Deferred:* `linejoin`, `arrow`, `guide_axis(cap =)`, a line colour of `:none`.

- **The theme is Phase 3's eleventh increment, in seven steps: `theme/2` with inheritance,
  removal with `:none`, the panel border and axis lines, the complete themes, the layers' defaults
  from the theme, where the legends go, text's face, angle and alignment (2026-10-23, Steve,
  agreeing the proposal, and adding the layers' defaults when step 4 found the base sizes reach
  them; checked against ggplot2 4.0.3's source and R).** 25 waiting examples need nothing but the
  theme, and 20 draw once it lands. The complete themes are `theme_gray()`, `bw`, `linedraw`,
  `light`, `dark`, `minimal`, `classic` and `void`, each with `base_size`, `base_line_size` and
  `base_rect_size`, one spelling (`theme_gray`, as `scale_color_gray/2`). An inside legend's
  placement is written as data on the scene's cell, laid out by the generic table code, never in the
  SVG writer, so the layout split a second backend needs moves it with the rest. *Rejected:
  `theme_set()`* — global state, which the pure core forbids; a shared look is the user's own
  function piped before the plot's settings. *Deferred:* `theme_test()`;
  `base_family`/`header_family` (one font); `ink`/`paper`/`accent`, which in ggplot2 4 colour the
  layers too; `%+replace%`; `theme_sub_*()`; `palette.*`; `aspect.ratio`; a draw-time theme
  (`to_svg(plot, theme: ...)`), with colours as CSS variables.

- **A theme is set element by element, by ggplot2's flat names, each element a keyword list
  checked against its kind (2026-10-23, Steve).** `theme(axis_text: [color: "red", size: {:rel,
  1.5}], plot_margin: {2, :cm})`: the key says the kind, so no `element_text()` constructor is
  needed (R's give a value its class, for dispatch and extension classes; a struct in a slot stays
  possible later). A length is a number of ggplot2's points, `{amount, unit}` or `{:rel, share}`; a
  margin one length or a keyword list of sides, a side left out 0. R's rules hold exactly: an
  element or property left out inherits, `theme/2` merges into what the plot has (R's `+`), and a
  later complete theme replaces earlier settings. The plot records the complete theme's name and
  sizes and the merged settings; `Giggly.ElementTree` holds the tree, from which `Plot` builds its
  schema, and `Giggly.Theme` resolves it when drawn (`calc_element()`), converting units in grid's
  order. *Rejected: element constructors (ggity's)* — they check nothing the key does not.
  *Rejected: nesting by family (`axis: [text: ...]`)* — splits R's flat names at an arbitrary dot.
  *Rejected: order-independent settings* — the same code would draw unlike R's.

- **An element set to `:none` is removed, as ggplot2's `element_blank()`, and under a removed
  root a property nothing above gives falls to grid's default (2026-10-23, Steve, choosing grid's
  defaults; checked in R).** A removal draws nothing and takes no room, and `calc_element()`'s
  rule holds: a complete theme's elements take a removed parent's removal, one a setting gives
  skips every removed element above it, a later setting replaces a removal. Under a removed
  `line`, `rect` or `text` R draws what such an element leaves unset at grid's defaults: black,
  white, 0.75-point lines with round ends, 12-point text 1.2 apart, no margin, a share with no
  parent the share itself. So a line's end joined the theme ahead of step 3. Only lines,
  rectangles and texts are removed: R refuses a blank length or margin, and a share at the roots
  `spacing` and `margins`, which `theme/2` now refuses too. `text: :none` leaves the legends'
  titles and labels, as ggplot2's legend replaces the root with its own text. *Rejected: the
  complete theme's root for such a property* — draws unlike R where `theme_void()`'s users add
  lines back. *Rejected: NimbleOptions' `{:or, ...}` for `:none`* — it reports a mistake inside an
  element at the element. *Deferred:* `inherit_blank:` as a property.

- **Ordering, viridis and `log10` by name are Phase 3's tenth increment, in seven steps: levels
  from the mapping, levels from the table, `diamonds`' levels, viridis, `log10`, `reorder()`, the
  notebooks (2026-10-22, Steve, agreeing the proposal; checked against R, ggplot2 4.0.3, scales
  1.4.0 and Explorer 0.13).** 44 waiting verdicts name the order of a column's values, most of
  them `diamonds`' ordered factors, and 22 examples draw once it lands. A factor's levels order
  its scale, legend, groups (so stacking and dodging) and facet panels, as R's do, and the frame's
  category carries them and `ordered`. `{:reorder, [x, y]}` is R's `reorder()`, the whole of a
  mapping value as a factor is: the frame's mean of `y` for each value of `x` (a `mean`
  aggregate, as R's `mean()` adds), ties in `x`'s own order, a missing mean last, titled
  `reorder(manufacturer, cty)`. *Deferred:* `drop:` (no caller; unused levels are dropped, as
  R's default), `factor()`'s `labels`, `reorder()`'s `FUN` and `decreasing` (r4ds writes
  `fct_reorder(class, hwy, median)`), a factor as `reorder()`'s value, forcats, `cut_*()` and
  `interaction()`, faceting by an expression, binned viridis. *Found:* Explorer 0.13 has no level order to bring; its categories
  are its string cache's first-seen order, sorted and grouped by text.

- **`{:factor, [value], levels: [...]}` gives a factor its levels, in the frame grammar's
  options form (2026-10-22, Steve, agreeing the proposal; checked in R).** As R's `factor(x,
  levels = ...)`: the levels name values as the column holds them, as `limits:` does (`[8, 4, 6]`
  for numbers), a value not among them is missing and placed last, one the data lacks is dropped
  by the scale, and `ordered: true` marks the factor ordered; a level named twice (`4` and `4.0`
  are one), `nil` or no levels is refused at the call, as R refuses a repeated level. Without
  `levels:` the levels are the sorted values, as R's. The title is R's, `factor(cyl, levels =
  c(8, 4, 6))`, each level as `Giggly.AsCharacter` writes it (`TRUE`, `1e+05`), a string quoted,
  `Giggly.Mapping` listing it (Steve; *rejected:* Elixir's `inspect` text, no widening, but
  `c(true, false)` inside R's call). *Rejected: `{:factor, [:cyl, [8, 4, 6]]}`* — an argument list
  holds what is evaluated, and a bare list is refused, kept for an inline column. *Rejected:
  `{:factor, [:cyl], [8, 4, 6]}`* — a positional third element nothing else in the grammar has.

- **A mapping names a function only as a shortcut for a common one Elixir lacks, `log10` first;
  an operator stays a capture (2026-10-22, Steve, scoping Phase 3's tenth increment: "If there is
  an elixir function already I don't think we need to rename it").** `{:log10, [:carat]}` is
  titled `log10(carat)`, as R titles it, and computed by the frame's `mutate/2` as R computes it
  (0 gives minus infinity, a negative number NaN, a missing value passes through); each frame
  implementation says which names it runs, Lists all of them, which a test pins, and the call
  refuses a name the table's engine cannot run, and one given a column or a constant that is not
  numbers, as R fails ("non-numeric argument to mathematical function"), a boolean too, which R
  reads as 1 or 0, since the frame, as Explorer's, reads none as a number. `{&Kernel.//2, [:hwy,
  :cty]}` and Kernel's other
  operators stay captures, titled as Elixir writes them and computed on lists, as any function
  is; an engine could later run them by recognising the capture, as titles already do. `sqrt`,
  `log`, `exp` and the rest arrive with their callers. *Rejected: the operators by name*
  (`{:/, [:hwy, :cty]}`, proposed, all their families or only those the notebooks write) — a
  second spelling of a function Elixir already has.

- **A function by name's value is a column, a constant or another function by name, never a
  capture or a closure (2026-10-22, Steve, building step 5: "A").** The engine computes a
  function by name whole, so it runs every value it reads and the call can check every type.
  `log10(price + 1)` stays a capture throughout, `{&:math.log10/1, [{&Kernel.+/2, [:price,
  1]}]}`, titled `:math.log10(price + 1)`, as it drew before; no caller writes one, the
  notebooks, r4ds and the ggplot2 book applying `log10()` to a bare column only. A function by
  name inside a capture (`log10(price) * 2`) is computed by the frame and handed to the capture.
  *Rejected: accepting a capture inside* (the capture computed on lists and handed to the frame
  as a column, titled as R's) — a temporary column, a type known only when run, and no caller;
  it can arrive later without breaking anything. A reordering's values follow the same rule, so
  `reorder(class, -hwy)` is refused.

- **The frame's sums are R's, added in the emulated long double, and its arithmetic gives an
  infinity past the largest double (2026-10-23, Steve: "A").** Elixir raises where IEEE rounds a
  result past the largest double to an infinity, so the frame's add, subtract, multiply, divide
  and sums raised where R gives `Inf`; each now gives the infinity, the plain sum (`rowsum()`)
  too. R's `sum()` and `cumsum()` add in its long double, which passes the largest double and
  comes back (`sum(c(xmax, xmax, -xmax))` is `xmax`), `sum()` reading anything past it as `Inf`
  and `cumsum()` rounding each running sum; both now add in `LongDouble`, matching R on 2,000
  random groups and every edge, and the summation is named `:extended` for what it now is.
  *Rejected: Neumaier's compensated sum with its overflow caught* — an infinity where R's sum
  comes back, and an approximation of the long double where the emulation is R's by construction.

- **The frame's mean is R's `mean()`, worked out in an emulated long double (2026-10-23, Steve:
  "A", building step 6 of the tenth increment; checked against R 4.6.1 and Explorer 0.13).** R
  adds a mean's doubles in the x87's long double (64 significant bits), divides by the count,
  adds the values' summed distances from that mean over the count, and rounds to a double last;
  integers it sums and divides once. `Giggly.DataFrame.LongDouble` holds each value exactly and
  rounds every step to 64 bits, so `summarise/3`'s `mean` matched R on 2,000 random groups of
  doubles and 2,000 of integers, overflow (1e308 twice gives 1e308) and 1e16, 1, -1e16
  (0.33365885416666669, not a third) included; `NA` wins wherever it is, where R's `sum()` keeps
  the first met. `operations/1` now names the aggregates, so a reordering is refused where the
  engine has no `mean`. *Rejected: the compensated sum over the count* — missed R's last digit in
  441 groups of 2,000, and overflows. *Rejected: the exact mean rounded once* — missed in 83,
  wherever R's correction pass loses bits. *Rejected: Explorer's mean* — missed in 523, and skips
  `nil`.

- **Viridis joins the tenth increment: `scale_color_viridis_d/2`, `scale_fill_viridis_d/2`, their
  `_c` forms, an ordered factor's default colour and fill scale, and `Giggly.Datasets.txhousing/0`
  (2026-10-22, Steve; checked against viridisLite 0.4.3 and grDevices).** R's `viridis(n)` takes a
  palette's 256 colours into CIE Lab through grDevices' `convertColor()` (D65 at (0.3137,
  0.3291) and the sRGB matrix made from it, not farver's), fits an fmm spline per channel, samples
  `n` places from `begin` to `end` and converts back, rounded to 5 decimals and clipped. The
  `color` library's Lindbloom conversions take grDevices' constants; the splines are R's
  coefficients from `splinefun()`, copied into `priv/` and read at compile time behind a waiver of
  their own, so Giggly only evaluates the cubic; R's `viridis(n)` for every palette and `n` to 256
  pins it. The options are R's: `option:` (the eight palettes by name), `begin:`, `end:`,
  `direction:`, and on `_d` `alpha:`; `_c` is the gradient over six. *Left out:* `_b` (no binned
  scales), `scale_*_ordinal()`'s `type`. *Rejected: viridis as its own increment* (the plan) —
  Steve. *Rejected: OpenBLAS's arithmetic* (found in step 4's mutation pass) — R's colour where a
  channel lands exactly on a rounding tie depends on its BLAS and processor, so no one R answer
  exists there to copy; Giggly sums as R's code reads.

- **`scale_*_viridis_c/2` takes no `alpha:` (2026-10-22, Steve, building step 4; checked in
  R).** R's `scale_colour_viridis_c(alpha = 0.3)` runs its gradient through six colours each
  ending `4D`, and `colour_ramp()` blends their alpha with their L*a*b*, so every value and the
  colour bar are drawn at that opacity. Giggly's gradient refuses a colour with an alpha of its
  own, a gradient through such colours deferred with the colour scales, and `_c` records a
  gradient, so `alpha:` waits for that gradient as its first caller; no notebook example gives
  `_c` an alpha. `_d` takes it, each colour carrying `rgb()`'s byte. *Rejected: a gradient
  through colours with an alpha now* — farver's alpha byte, the blend and the colour bar's
  opacity each to check against R, for no example.

- **A factor carries R's `ordered` flag from the increment that brings levels (2026-10-22, Steve,
  scoping Phase 3's tenth increment; checked in R).** `ordered: true` on `Giggly.Factor.new/2` and
  on `{:factor, ...}` marks a factor ordered, the frame's category carries it beside its levels,
  `reorder()` keeps it, as R's does, and `diamonds`' `cut`, `color` and `clarity` are ordered, as
  R's are, so the dataset is R's whole once. In a plot it changes only the default colour and
  fill scale, to viridis (`scale_colour_ordinal()`); alpha's and size's ordinal palettes are their
  discrete ones, and shape only warns. *Rejected: the flag with viridis, its only reader*
  (proposed, as an option that changes nothing can be tested only as carried) — Steve's call,
  asking for viridis in this increment too.

- **A discrete scale fed levelled and plain values trains as R's `discrete_range()`, remembering
  whether its first values had levels (2026-10-22, Steve, scoping Phase 3's tenth increment;
  checked in R).** Each training (one layer's column, on the panels the scale serves) brings the
  levels its rows hold, as R's `drop = TRUE`, or its plain values sorted, and adds those the scale
  lacks, matched by `Discrete.key/1`: a factor's levels lead whichever layer brings them, so
  factor (b, a) and text (c, a) train to b, a, c in either order. A scale whose first values had
  levels then adds each new value after the rest; one whose first were plain sorts everything at
  each plain training, so text, factor, text (d, 0) gives 0, a, b, c, d where factor first gives
  b, a, c, 0, d. `Scale.Discrete` gains a documented field saying which, `factor`, R's name for
  it; Giggly already trains in ggplot2's order, a layer and a column at a time. *Rejected: levels
  first, plain values sorted after, whatever the order* — no field, but a departure from R from
  the third training on.

- **A table's column carries its levels as a `Giggly.Factor`, its values and levels in one
  struct, read with the table (2026-10-22, Steve, scoping Phase 3's tenth increment; checked
  against R, Explorer 0.13 and `table`).** R orders a scale, its groups and a facet's panels by a
  factor column's levels, as `diamonds`' `cut`, `color` and `clarity` carry them, and a facet
  splits the raw table, so only the table can order its panels. `Table.Reader` hands over values
  alone and Explorer 0.13's categories are its string cache's first-seen order, so no source
  brings levels. `Giggly.Factor.new(values, levels: [...])` enumerates as its values, so Explorer,
  Kino and `table` read it as a list (`Table.to_columns/1` passes it through), and `from_table/1`
  stores a `:category` column with its levels, a value not among them `nil`, as R's NA. Its
  boundary lists NimbleOptions; the frame and `Giggly.Datasets` list it. *Rejected: levels only
  in a mapping* — every `diamonds` example would write a factor where R names a column, and
  panels could not be ordered. *Rejected: `Table.Reader` metadata under a namespaced key* — a user
  wraps a whole table to order one column. *Rejected: `Giggly.Category`* — `Factor` is the
  mapping's `{:factor, ...}` word. Its `Enumerable` implementation is left unclassified, since
  Elixir's protocol has no boundary, and the declarations test checks only Giggly's own
  protocols' implementations (Steve, building step 2). *Rejected: classifying it into
  `Giggly.Factor`'s boundary* — its calls would be checked, but it is a move the gate asks for.

- **Size, shape and line type are Phase 3's eighth increment, in seven steps: a point's look
  (its fixed look and a mapped fill), a line's fixed look, mapped size, `geom_count()`, mapped
  shape, mapped line type and width, the notebooks (2026-10-19, Steve, agreeing the proposal;
  checked against ggplot2 4.0.3's source and vdiffr).** A point took only colour and alpha, so
  `geom_point(size = 3)` could not be written, and the scales and legends built for colour, fill
  and alpha reached no other aesthetic; 86 waiting examples name a piece of it, more than any other
  candidate. The scale functions are kind-named as step 5's (`scale_size_continuous/2`, not R's
  alias `scale_size`), beside R's own `scale_radius/2` and `scale_size_area/2`. `geom_count()`
  comes in (Steve), the size scale's natural subject, so `Giggly.Stat` exports `Sum`. A mapped
  point fill moved from the fifth step to the first (Steve, building it): once points draw a fill,
  a plot's `fill` reaches them and fills shapes 21 to 25, so waiting would draw R's points without
  R's legend. `stroke: :none` is R's `stroke = NA`, as `:none` removes (Steve), rather than
  leaving it to `stroke: 0`, which looks alike in SVG but writes the lines R leaves out.
  *Rejected, as the
  next increment:* the theme (14 examples alone, and its legend-placement examples map shape),
  histograms and box plots (18; their outliers want shapes), `facet_grid()` (13), ordering and
  jitter (21). *Deferred:* identity scales, as one family of seven, likely with tiles (Steve); a
  character as a shape; binned size and line width; a mapped `stroke`, which ggplot2 does not
  scale; a mapped text size; `scale_size_manual()` and `scale_linewidth_manual()`, with alpha's;
  `override.aes`.

- **A shape is ggplot2's name for it as an atom, or R's number, turned into the name at the call
  (2026-10-19, Steve).** `shape: 21` and `shape: :circle_filled` draw the same point. The 26
  names are ggplot2's `translate_shape_string()` table with underscores for spaces, shape 14
  keeping only `:square_triangle`; a number becomes its name where `colour:` becomes `color:`,
  so nothing past the call sees two spellings. `:none` draws no point. The default palette hands
  out `:circle_small`, `:triangle`, `:square`, `:plus`, `:square_cross` and `:asterisk` (R's 16,
  17, 15, 3, 7, 8), or with `solid: false` the open ones. *Rejected: names only* (proposed: one
  spelling, the Elixir form) — every ggplot2 user writes `shape = 21`. *Rejected: numbers only*
  — `21` says nothing of what it draws.

- **A line type is a name, R's number 0 to 6, or a dash pattern as a tuple of lengths
  (2026-10-19, Steve; the tuple and annotations' lists building step 2).** The names are R's as
  atoms (`:blank`, `:solid`, `:dashed`, `:dotted`, `:dotdash`, `:longdash`, `:twodash`). A
  pattern is 2, 4, 6 or 8 lengths from 1 to 15, on and off in turn: `{3, 3, 1, 3}` for R's
  `"3313"`. Each is held as its pattern from the call (`:dashed` as `{4, 4}`, `:solid` as `{}`,
  `:blank` as `:none`), as a colour as its hex: a column holds one type, and R's palette mixes
  `solid` with patterns. A bar's or a rectangle's annotation takes a list of line types and of
  widths, as R draws them row by row; a path's one line type, as R refuses a type varying along a
  line, and a list of widths, drawn a segment at a time. *Rejected: a list* (agreed first) — `annotate/3` and a layer's set values read a list as
  one value per row, so `linetype: [2, 3]`, R's `c(2, 3)`, dashed then dotted, would be a pattern.
  *Rejected: R's hex string* — a little language (`"F"` for 15) checked only whole, its
  familiarity buying little for something rare. *Rejected: both* — two spellings of a rare thing.

- **A discrete palette with fewer shapes or line types than the scale has values raises when the
  plot is run (2026-10-19, Steve).** R gives the seventh shape on, or the fourteenth line type,
  no value, warns, and leaves those points or lines out. Giggly cannot warn, so it raises,
  naming the aesthetic, the number of values and the palette's, and the manual scale that takes
  more: as a colour bar for a discrete scale raises where R warns, and as R's own manual scale
  fails on the same shortage. *Rejected: drawing as R draws* — whole categories would vanish
  without a word.

- **A point's shape is worked out in the geom from R's graphics engine and drawn with the scene's
  primitives (2026-10-19, in the scope Steve agreed).** R's `GESymbol()` turns each of the 26 shapes
  into the rectangles, circles, polygons and lines svglite writes (0 a `<rect>`, 15 a `<polygon>`, 3
  two `<line>`s, 21 a circle with a fill of its own); the port works them out in points round each
  point's place, so circles carry a radius and fill per mark and rectangles, polygons and segments
  offsets in points, as polylines do. Points are drawn in row order, so overlapping ones stack as
  R's, each run of one kind and outline width one primitive. *Rejected: a symbol primitive the
  backend draws* — every backend would hold R's geometry, and the scene would know R.

- **A scale's `rescaler` says how it places a value, and a legend key is as big as its glyphs
  (2026-10-20, Steve, the size step).** `scale_size_area()` places a value at its share of the
  limits' high end, R's `rescale_max()`, which no palette can work out from a place alone, so
  `Scale.Continuous`'s `midpoint` became `rescaler` (`:rescale`, `{:mid, midpoint}`, `:max`), the
  field ggplot2's scale holds: one field for one question (Steve). Keys size themselves as
  `measure_legend_keys()` sizes them: each geom reports its glyph's room (`Geom.key_size/2`) and
  draws by fractions of the key and offsets in points (`draw_key/2`), as grid mixes `npc` and
  absolute units, so the legend lays out its rows and column before any glyph is placed; text keys
  too (Steve), measured as `draw_key_text()` measures them. A size scale takes R's options,
  `na_value:` on `_area` and `_discrete` alone. *Rejected: `rescaler` beside `midpoint`*, two
  fields a scale uses one of. *Rejected: drawing each key at its final size*, rendering asking the
  guide for its layout between measuring and drawing. *Deferred:* `transform:` on size scales (so
  `lims(size: {20, 0})` is refused, where R reverses), `aesthetics:`, and `scale_size_ordinal()`,
  with ordered factors.

- **A count layer counts over ggplot2's list of aesthetics, and `stat_sum/3` comes with
  `geom_count/3` (2026-10-20, Steve, the size step's fourth; checked against ggplot2 4.0.3 in R).**
  `Stat.Sum` is R's `StatSum`: per panel, a row for each combination of the columns
  `.all_aesthetics` names but `weight`, `group` included, its `n` the rows or their weights' sum,
  its `prop` that share of its group's total, size taking `n` by default. A column the plot's
  mapping carries in under a name the list lacks (`linewidth`, `stroke`, a nudge) is dropped, as R
  drops it. A missing weight makes its count missing, as R's `sum()` does, where counting skips
  one, as `rowsum()` does. A stat's default for an aesthetic other than position gets a scale and
  draws in the legend, as ggplot2 reads `defaults(computed_mapping, stat$default_aes)`; a set size
  draws none. A weight given after the stat is refused, as counting refuses it, where R ignores it.
  *Rejected: every column but `weight`* — simpler, but a plot-mapped `linewidth` splits counts R
  keeps whole. *Rejected: `stat_sum()` left out until a layer chooses its geom* (proposed) —
  Steve: the same layer under R's name, now.

- **The frame's first group-by aggregate is `DataFrame.summarise/3`, and stats sum through it,
  extended as R's `sum()` adds or plain as `rowsum()` does (2026-10-20, Steve).** R's `sum()`
  adds in extended precision, so plain doubles missed R's `layer_data()` in 901 of 3,000 random
  weight groups (mpg's `displ`: 55.500000000000014 for R's 55.5). Steve asked that stats compute
  through the frame rather than on pulled lists: `summarise(frame, by, name: {:sum, [column],
  options})` groups and sums, rows sorted by `by`, a missing value last, each `by` column keeping
  its type, with `summation: :extended` (the default; how it adds is the entry beginning "The
  frame's sums are R's") or `:plain` and `missing: :propagate` (the default) or `:skip`. Counting
  moved onto it, its counts plain and its proportions' totals extended, which fixed a departure:
  6 of mpg's 7 class shares weighted by `displ` were a bit off.
  *Rejected: a compensated sum private to the stat* (proposed) — an engine running the frame would
  never see it. *Rejected: plain doubles* — R's values missed in 30% of groups. *Rejected: one
  summation* — counting's counts would leave `rowsum()`'s.

- **A stat computes only through frame operations and pulls only what it has already summarised
  (2026-10-20, Steve, scoping Phase 3's ninth increment).** The work that scales with a layer's
  rows — binning, counting, quantiles, filtering outliers — is written as `mutate`, `filter`,
  `join` and `summarise` with aggregates, so an engine holding the table does it and nothing of
  the layer's table crosses into Elixir; what a stat pulls is its own output, small by
  construction, so `density` from a bin's counts or a box's fences from its hinges may be worked
  out on lists. Three stats pull their rows instead (the entry beginning "Smoothing and densities
  compute"). Each operation arrives with the stat that first needs it, and the expression form
  `mutate` takes is the one a mapping's named expressions will reuse (§7, "Engine backends").
  Counting and counting at each place, which pull their input to choose rows, weigh them and
  carry a group's constant columns, come under the rule in the same increment, first, the panel's
  limits arriving with binning, their first reader (Steve, 2026-10-21): R's bin and boxplot drop rows and carry constant
  columns as counting does, so counting is those operations' first caller, proven by its tests
  pinned to R before binning relies on them. *Rejected: counting last, or in a follow-up* —
  binning would prove the operations alone, and a follow-up leaves two carries, one on lists.
  Nothing checks the rule but review (Steve, 2026-10-21). *Rejected: a credo check* — it sees
  a pull of the input and of a summarised table alike, so it could only pin a code shape (pull
  beside its summarise). *Rejected: a strict frame for tests* (proposed), refusing a pull of
  anything not yet summarised.
  *Rejected: building bin and boxplot on pulled lists and moving them
  later* — nothing toward the goal, and a rewrite of the first two summarising stats. *Rejected:
  a vocabulary designed ahead of its callers* — the rules' "an operation arrives with its first
  caller", and bin and boxplot are the proving ground.

- **A stat is handed each panel's axes: their limits, whether each is discrete, and a function
  through its transformation (2026-10-21, Steve, scoping distributions' step 2).** ggplot2's stats
  read four things from a scale: `dimension()`, `is_discrete()`, and the transformation forward
  (binning's user breaks, `stat_function()`'s y) and back (`stat_function()`'s x). The assembly,
  which holds the scales, hands `compute_layer` a map from panel to its x and y, each its
  unexpanded limits, a discrete flag and a function that transforms values, built around the
  panel's scale; the inverse joins with its first reader. Stat keeps its boundary and can do only
  what it is handed. *Rejected: the transformation's name, Stat listing Scale* — plain data and
  closer to R, but one widening opens every function Scale exports to every stat. *Rejected:
  refusing user breaks on a transformed axis* — it leaves out what R does.

- **A missing value in a sum is R's, `NA` or NaN, and an infinity adds (2026-10-21, Steve).** R's
  `sum()` and `rowsum(na.rm = TRUE)` treat only `NA` and `NaN` as missing, so an infinite weight
  made R's counts infinite and their shares NaN or 0 where Giggly's sum skipped it or went
  missing. The frame's sum now keeps the first missing value met and adds an infinity as IEEE
  does, and R's arithmetic on the frame's values has one home, `Giggly.DataFrame.Arithmetic`
  (exported), through which counting, counting at each place and binning divide and stacking
  adds; the bar geom takes an infinite y to the panel's edge, which `geom_col()` crashed on, and
  the position scale maps NaN to missing, as R's does. *Rejected: an infinity as a missing
  value* — it departed from R in every stat that sums. *Rejected: the arithmetic in each family*
  — three homes for one rule, Stat, Geom and Position.

- **The frame's operations share one expression grammar, and a row finds its bin by `cut` per
  panel (2026-10-21, Steve).** `mutate/2`, `filter/2` and `summarise/3`'s aggregates take the
  mapping's grammar with an operation named by an atom: a column by its frame name (never `true`,
  `false`, `nil`), a constant alone or `{:constant, term}`, `{name, [argument]}`, or `{name,
  [argument], options}` for parameters that are not row values, so `{:sum, :weight, options}`
  becomes `{:sum, [:weight], options}`. Values follow Explorer's semantics: a missing value passes
  through, a filter keeps the rows whose value is true, floats divide as IEEE does. Counting brings
  `filter`, `mutate`, `is_finite`, `and`, `n_distinct` (a missing value counting as one) and
  `first`; binning `cut`, R's `.bincode` against its fuzzy breaks, per panel by `split/2`; box
  plots (2026-10-22, scoping step 4) a left `join/3` on equal keys, a missing key matching none,
  `or`, `not`, `<` and `>`, NaN above every number as in Explorer 0.13, and `count`, `min`, `max`,
  `quantile` (R's type 7 in R's order, `(1 − h)·lo + h·hi`) and `list`, all but `list` skipping a
  missing value (`nil` or NaN), as ggplot2 calls them; `is_nil` and `is_nan` lost their caller,
  R's stat dropping non-finite rows, which `is_finite` does. Densities, shares and fences are worked
  out on summarised tables, so arithmetic waits for the mapping's names; no boundary changes.
  *Rejected: floor arithmetic* (Mosaic's) — equal widths only, a value within rounding error of a
  break can land in another bin than R's, and binning would need a join and arithmetic. *Rejected:
  R's `NA` for a comparison with NaN* — the grammar's rule is Explorer's, and no row reaching a
  comparison holds NaN.

- **A box's outliers are a list column on its row, a type of its own (2026-10-21, Steve, scoping
  Phase 3's ninth increment).** As R's `stat_boxplot()` returns them: each box's row holds its
  outliers, found by a frame filter against its fences and collected into a list by a `summarise`
  aggregate, so the geom reads their extent into `ymin_final` and `ymax_final` and draws them at
  the box's x in its look, after dodging moves the box. A list entering a frame is typed `{:list,
  type}` by Explorer 0.13's rule (2026-10-22, scoping step 4), its values typed as a column's and
  lists mixing two types refused, so the outliers are of y's type, as the frame gives a `:term` that
  gets plotted a named type. Engines build such a column (Explorer 0.13's grouped `summarise` of a
  plain column gives a `list[…]`), and diamonds' price by cut brings 3,588 outliers out of 53,940
  rows in either shape, since each is drawn. *Rejected: outliers as rows of a second frame* — every
  stage after the stat would carry two tables, the extents and the drawing each a join, and
  `layer_data/2` would lose them or differ from R; its premise, that an engine cannot build a list
  column, was wrong.

- **A box plot takes R's options but `quantile.type` and a `stat:` (2026-10-21, Steve, scoping
  Phase 3's ninth increment).** `geom_boxplot/3` takes `outliers:`, the outliers' look
  (`outlier_color:`, `_fill:`, `_shape:`, `_size:`, `_stroke:`, `_alpha:`), `varwidth:` (which
  dodges each box at its own width, as R switches `position_dodge2()` to `preserve = "single"`),
  `notch:` and `notchwidth:`, `width:` and `staplewidth:`, and ggplot2 4.0's look of each part
  (`whisker_`, `staple_`, `median_` and `box_` `color:`, `linetype:`, `linewidth:`), R's dotted
  names underscored as `na.value` is `na_value:`, `outlier_colour:` beside `outlier_color:` as
  `colour:` is. Usage was thin (reference examples: the outlier look 5, `varwidth` 2, `notch` 1;
  r4ds and the ggplot2 book's 42 box plots: `varwidth` and `width` once each), but Steve kept the
  part looks, cheap to draw. A mapped `width` is taken too (2026-10-22, Steve: "follow ggplot2's
  lead in terms of what is supported"): a box is as wide as its group's first `width`, else 0.9 of
  the group's x range where it spans several, else `width:`, as R's stat reads them; a set `width:`
  drops a mapped one, as R's set aesthetics drop a mapping (R draws mapped widths 0.2 and 0.6 beside
  `width = 0.3` at 0.3), and still yields to a group's range (checked 2026-10-22, scoping step 6).
  The set aesthetics are R's, `shape:` and `size:` setting the outliers' look as R's do (Steve,
  2026-10-22, step 6). *Left out: `stat_boxplot/3`* (step 6) — without `geom:` it draws what
  `geom_boxplot()` draws but ignores the outlier and part looks; its use, `geom = "errorbar"`,
  waits on `geom:`, and neither r4ds nor the ggplot2 book calls it. *Rejected: refusing it as
  `geom_bar/3` and `geom_col/3` do* (proposed) — R documents and draws it; the bars' refusal was
  never decided. *Left out: `quantile.type`* — no use, and each of R's other eight types would be an
  aggregate every engine must carry. *Left out: weighted boxes* (2026-10-22, Steve) — R weighs them
  with `quantreg::rq()`, which ggplot2 only suggests, so a plain install fails ("there is no package
  called 'quantreg'") and draws no layer, and matching `rq()`'s linear-programming answer would be
  research. *Left out: the identity-stat box* — it needs a `stat:` option, which no geom has; that
  is a decision for every geom.

- **A weight in the plot's mapping is refused by a box layer at the call (2026-10-22, Steve,
  scoping distributions' step 6).** `Plot.new(mpg, %{x: :class, y: :hwy, weight: :displ}) |>
  Plot.geom_boxplot()` raises from `geom_boxplot/3`, saying the plot maps `:weight`, that a box's
  quartiles are of its rows unweighted, and to map the weight on the layers that count with it.
  R weighs the boxes with `quantreg::rq()`, or, on a plain install, warns "Computation failed in
  `stat_boxplot()`" and draws none; Giggly leaves weighted boxes out (the entry beginning "A box
  plot takes R's options"), so riding along, the rule for a plot aesthetic a layer cannot use (the
  entry beginning "An aesthetic a layer takes from the plot"), would draw unweighted boxes, a
  third result R never draws, silently. The first exception to that rule: an aesthetic R's layer
  uses and Giggly's cannot. *Rejected: riding along unused* — a mapping silently doing nothing.
  The cost, accepted: a plot weighting a bar layer through its own mapping holds no boxes until
  the weight moves to that layer, where R would have weighed the boxes too.

- **A box layer dodges by clusters unless told otherwise, and `varwidth:` switches its dodging to
  `preserve: :single` silently (2026-10-22, Steve, scoping distributions' step 6).**
  `geom_boxplot/3` takes `position:` `:dodge2`, its default, `:dodge`, or `position_dodge2/1`'s
  struct; `:stack` is refused, as R fails stacking boxes ("replacement has 0 rows"), and
  `:identity` waits, as it does for bars. With `varwidth: true`, either atom records
  `position_dodge2(preserve: :single)`, as R replaces any position string, `"identity"` included,
  and a struct records `preserve: :single` with its `padding` and `reverse` kept, where R warns
  "Can't preserve total widths when `varwidth = TRUE`" and switches, so every call draws what R
  draws. *Rejected: raising for a struct* — `position_dodge2/1` records `:total` unless told
  otherwise, as R's does, so it would refuse the default struct, a setting nobody wrote, where R
  only warns.

- **A box plot's orientation is R's, an ambiguous one chosen silently, and a contrary
  `orientation:` raises where one axis is mapped (2026-10-22, Steve, scoping distributions' step
  6).** Where both axes are continuous and no group holds one value, R warns "Orientation is not
  uniquely specified" and runs along y, even on its own reference example, `geom_boxplot(aes(group
  = cut_width(carat, 0.25)))`, and its no-group example draws one wide box after "did you forget
  `aes(group = ...)`?"; both draw, so Giggly draws them, unwarned, as a pure pipeline must. Where
  one of x and y is mapped, the box summarises it and stands along the other (R's
  `main_is_orthogonal`), so `orientation:` names the axis not mapped, `:x` for y alone, the
  reverse of binning's sense, and a contrary one raises at the call, where R draws a box of `NA`s;
  where both are mapped, it chooses. *Rejected: refusing the ambiguous case* — it refuses R's
  reference examples, whose drawing is well defined.

- **A frequency polygon takes no `pad:`, since R pads one whatever it is given (2026-10-22, Steve,
  scoping distributions' step 3).** ggplot2's `geom_freqpoly()` sets `params$pad <- TRUE` after
  reading its arguments, so `geom_freqpoly(pad = FALSE)` still draws a bin of no rows at each end,
  and says nothing. `geom_freqpoly/3` records `%Stat.Bin{pad: true}` and leaves `pad:` out of its
  options, so `pad: false` raises naming it, as an option that would do nothing raises elsewhere
  (`fill:` on `geom_path/3`), and every call it takes draws what R draws. *Rejected: honouring
  `pad: false`* — the unpadded polygon a reader might expect, but R draws one only through
  `stat_bin(geom = "line")`, so the same call would draw differently. *Rejected: taking `pad:` and
  ignoring it, as R does* — an option that changes nothing.

- **Binning takes `orientation:`, which must name the aesthetic it bins, and a contrary one raises
  a friendly error at the call (2026-10-22, Steve, scoping distributions' step 3).** R's
  `geom_histogram()`, `geom_freqpoly()` and `stat_bin()` take `orientation`: one agreeing with the
  mapped `x` or `y` changes nothing, and a contrary one only warns "Computation failed in
  `stat_bin()`", with a cause that never says why, and draws the plot without the layer; any
  string but `"y"` reads as `"x"`. Giggly's three take `:x` or `:y`, checked at the call against
  the one of `x` and `y` mapped and recorded nowhere, since one accepted says what the mapping
  says; a contrary one raises in plain words: what the layer bins along, why, and how to bin the
  other way. Unlike a polygon's `pad:`, which R ignores, it is a claim the call checks, so R code
  with a correct orientation runs unchanged. `geom_bar/3`'s counting, as unambiguous, takes it
  alike, with options of its own (Steve); `geom_col/3`'s, the ambiguous case `orientation` exists
  for (horizontal bars from two numeric columns), is a feature waiting for the bar geom to read
  it. *Rejected: leaving it out* (proposed) — code ported from R meets "unknown options".
  *Rejected: a field of `%Stat.Bin{}`* — nothing would read it. *Rejected: `geom_bar/3`'s waiting
  for `geom_col/3`'s* — one bar feature, but the check is binning's, ready now.

- **Bars take R's `width:` and `just:`, and `geom_col/3` a mapped `:width` (2026-10-22, Steve:
  "follow ggplot2's lead in terms of what is supported").** `geom_bar/3` and `geom_col/3` take
  `width:`, any number, as R does, a set aesthetic like `alpha:`, so it beats a mapped `:width` as
  R's `aes_params` do, put into every row before the bar's setup where the table has no width, as
  a set corner is, so stacking, dodging and the axes see the edges; on `geom_bar/3` counting takes
  it as its width, as `stat_count()` takes it (2026-10-22, step 6: so a box plot's summary keeps
  0.9 of a group's range over a set width, as R's `compute_data_size()` reads a row's width
  first). `geom_col/3` and `annotate/3`'s bars take `:width` row by row. `just:`, 0 to 1 (R takes
  any number), is a field of `%Geom.Bar{}`, as R's is a parameter. A mapped
  `:width` on `geom_bar/3` and `width:` on the histogram functions stay refused: R ignores both.
  *Rejected: the bars' refusal* — never decided, and R's own pages use both. *Rejected: `width:` as
  a field of the geom* — a mapped width would beat the set one, the reverse of R.

- **Dodging by clusters computes on lists, as every position does, since a position's rows are
  its marks (2026-10-22, Steve, scoping distributions' step 5).** `Position.Dodge2`, R's
  `position_dodge2()`, pulls the columns it moves, works out R's clusters, widths, running sums and
  padding on lists, in R's order through `Giggly.DataFrame.Arithmetic` so its doubles are R's, and
  puts them back, as dodging and stacking do. The stat rule (the entry beginning "A stat computes
  only through frame operations") covers the work that scales with a layer's input; a position
  runs on the stat's output, one row per mark, which the geom reads straight after to draw, and
  §7's engine plan materialises that output, so `layer_data/2` stays a frame of lists. *Rejected:
  frame operations* — dodge2's per-bar steps need arithmetic in expressions, a sort and an ordered
  running sum within groups, three new kinds of operation whose first caller would be a table
  drawn at once; the running sum arrives with a stat that needs it (`stat_ecdf()`), arithmetic
  with an engine that runs the operators' captures (the entry beginning "A mapping names a
  function only as a shortcut").

- **`Plot.position_dodge2/1` arrives with dodging by clusters, taking `preserve:`, `padding:` and
  `reverse:` (2026-10-22, Steve, scoping distributions' step 5).** It returns `%Position.Dodge2{}`,
  which `position:` takes beside the `:dodge2` atom on `geom_bar/3`, `geom_col/3`,
  `geom_histogram/3` and `stat_bin/3`, as the entry beginning "A layer chooses its position by an
  atom now" foresaw: `preserve:` `:total` or `:single`, R's strings as atoms; `padding:` 0 to 1, as
  `just:` is, where R takes any number and its code widens bars into their neighbours below 0 and
  turns them inside out above 1; `reverse:` a boolean. Step 6's `varwidth` sets the same
  `preserve`. `width:` is left out: R reads it only for a geom without edges, none of which takes a
  position, and on bars it changes nothing, so it raises as an unknown option, as a frequency
  polygon's `pad:` does. *Rejected: the atom alone, `preserve` set only by `varwidth`* — R's
  `position_dodge` page draws bars with `preserve` twice. *Rejected: `preserve:` alone* —
  `padding:` and `reverse:` are R's, a line each, already checked against R.

- **Dodging by clusters places each cluster from its own centre and widths, where R misplaces
  those after a bar with no edges (2026-10-22, Steve, scoping distributions' step 5).** R's
  `pos_dodge2()` totals each cluster's new widths by its centre, sorts the centres, and gives the
  k-th one's start to the k-th cluster found; a bar with no edges, from a missing mapped width, is
  a cluster with no centre, so each cluster after it takes the next one's start and the last keeps
  its own edges. Over x a, a, b, c, c with widths 0.5, 0.5, NA, 0.5, 0.5, R draws c's two bars one
  on the other at 2.8875–3.1125; Giggly sets them at 2.7625–2.9875 and 3.0125–3.2375, as a's are,
  and the bar with no edges loses its x, as R's does. The two agree wherever every bar has edges
  and a positive width and none reaches back past an earlier cluster; negative widths, each its
  own cluster by R's rule, stay where they are. A panel where no bar has edges, where R fails
  summing no clusters ("non-numeric argument to binary operator"), keeps its bars without them
  (found in the step's mutation pass). *Rejected: R's placement* — a slip in its indexing, which
  stacks the bars dodging exists to separate.

- **A shape scale is discrete alone, and its functions take R's options but those their families
  wait for (2026-10-20, Steve, the shape step; checked against ggplot2 4.0.3 in R).**
  `scale_shape_discrete/2` takes `solid:` (`{:shape, :solid}` or `{:shape, :open}`, R's
  `pal_shape()`), `scale_shape_manual/2` `values:`, shapes or a map from value to shape, through
  the colour scale's manual palette, and both `name:`, `limits:`, `breaks:`, `labels:`, `guide:`
  and `na_value:`, a shape, none when not given, as R's `NA`. Shapes have no order, so a
  continuous or a date column on shape is refused when run (`Scale.discrete_only?/1`) and
  `lims(shape: {1, 5})` at the call, where R aborts for each. *Rejected: `Scale.kind/2` giving
  `:none` for it* — the refusal would say "no scale can place yet", where R never will.
  *Deferred* (Steve): `aesthetics:`, with the size scales'; `na.translate` and `drop`, with every
  discrete scale's; `scale_shape_binned()`, with binned scales; `scale_shape_ordinal()`, with
  ordered factors; `scale_shape_identity()`, with identity scales.

- **A line type or width scale takes R's options but those its family waits for, and
  `economics_long` comes with it (2026-10-20, Steve, the line type and width step; checked against
  ggplot2 4.0.3 in R).** Line type is discrete alone, as R's `scale_linetype_continuous()` aborts
  for a number, a date and `lims(linetype = c(1, 5))`; its palette is `pal_linetype()`'s 13
  patterns as tuples, a fourteenth level raising. `na_value:` goes on `scale_linetype_discrete/2`,
  which R takes though its docs hide it, and on `scale_linewidth_discrete/2`, never
  `_continuous`, which R refuses. `economics_long` came forward from the notebook step, its
  waiver asked, so the golden is `scale_linetype()`'s own example, written to 17 digits where
  `write.csv()`'s 15 lose `value01`. *Deferred* (Steve), each with its family:
  `scale_linetype_binned()`, `scale_linewidth_binned()`, `scale_linetype_identity()`,
  `scale_linewidth_manual()`, `scale_linewidth_ordinal()`, `scale_linewidth_date()` and
  `_datetime()` (R draws dates 1 to 6 mm; every aesthetic but position refuses a date),
  `transform:` (`lims(linewidth: {10, 0})` refused where R reverses), `aesthetics:`,
  `na.translate`, `drop`.

- **A manual list named by breaks leaves the scale its levels, as R's does (2026-10-20, Steve,
  found checking the line type step against R).** `manual_scale()` names a list by its breaks after
  choosing its limits, so two values with `breaks = c("c", "a")` over three levels fail
  ("Insufficient values"), where Giggly had made the list a map, which narrowed the scale to `c`
  and `a` and drew `b` missing. The palette is `{:manual, values, breaks}`, for every manual scale;
  a map the user writes still narrows. *Rejected: leaving it*, a recorded departure — a plot R
  refuses for a missing value would draw without a word.

- **A stroke's width, a radius, an opacity and a gradient offset are written as svglite writes
  any number, a position with two decimals (2026-10-20, the line type and width step).** svglite
  writes every number below 1 with as many decimals as reach its first significant digit and one
  more, so `scale_linewidth(range = c(0, 4))` draws 0.040-point segments that two decimals wrote
  `0.04`. Sizes are worked out in R's order, so they match R's to the digit. *Rejected: every
  number so* — positions near 0 are layout's rounding error, which grid and Giggly leave apart
  (5.7e-14 where grid has 0 at a radial panel's top), and two decimals hide it.

- **A guide is chosen by a scale's `guide:` and by `guides/2`, which wins, as in R (2026-10-19,
  Steve, agreeing the proposal; checked against ggplot2 4.0.3 in R).** Every colour, fill and
  alpha scale function takes `guide:`, a name (`:none`, `:legend`, `:colorbar`) or the struct
  `guide_legend/1` builds (`reverse:`), as a position's parameters will come by constructor (the
  entry beginning "A layer chooses its position"). `guides/2` takes `color:`, `fill:` and
  `alpha:` the same way; it beats the scale's whatever the pipe order, and a later call replaces
  only what it names, R's `guides() > scale > default`. A colour bar for alpha or a discrete
  scale is refused, at the call where the call can tell and otherwise when run, where R warns and
  draws none. `reverse` flips every key, the missing-value key included, before legends merge,
  so a reversed colour beside an unreversed fill on one column draws two legends, as R does.
  *Rejected: `{:legend, reverse: true}`*, no new function, but a second way of writing a kind
  with options. *Rejected: the axes in `guides/2` now* (`x: :none` keeps the title alone, as R):
  no waiting example draws from it; axes join with `guide_axis()`'s options. *Rejected: the
  last call wins.* *Deferred:* every guide option but `reverse`, the colour bar's included.

- **`Plot` lists `Giggly.Guide` to build a legend's struct, and `PlotRunsNothing` refuses
  `Guide`'s modules that hold no struct (2026-10-19, Steve).** `guide_legend/1` returns
  `%Guide.Legend{}`, as a plot records each kind as a struct. Listing `Guide` lets `Plot` call
  every module `Guide` exports, `Axis`, `Box`, `Grid`, `Strip` and `Title` among them, which
  draw; the check's roots, derived from the build in `.credo.exs`, gain every `Giggly.Guide.*`
  module defining no struct, beside the protocols and `Giggly.Scale`, so `Plot` may write a
  kind's struct and call nothing that draws. *Rejected: plain data the assembly turns into the
  struct*, no widening, but a kind that is not a struct in the plot.

- **Colour, fill and alpha scales are the scale functions' step 5, each option checked against
  ggplot2 4.0.3 in R (2026-10-19, Steve, agreeing the proposal).** `scale_color_manual/2`
  (`values:`, a list, or a map from value to colour as R's named vector, whose keys narrow the
  default limits to the values the data holds; a list takes its names from `breaks:`, as R's
  does), `scale_color_hue/2`, `scale_color_gray/2` (`start:`, `end:`; American, as the theme's
  `:gray`, though R spells it only grey), `scale_color_discrete/2`, `scale_color_gradient/2`,
  `scale_color_gradient2/2`, `scale_color_gradientn/2` (`colors:`), `scale_color_continuous/2`,
  each with its `scale_fill_` twin, and `scale_alpha_continuous/2` and `scale_alpha_discrete/2`
  (`range:`), each with `name:`, `limits:`, `breaks:`, `labels:` and `na_value:`, R's function
  defaults (gray's missing value is red). `lims/2` takes `color:`, `fill:` and `alpha:`. A
  legend shows the scale's breaks among its limits, labelled as given; a continuous scale maps
  over its limits, censoring outside them. *Rejected: `guide:` in this step* (Steve: step 6,
  beside `guides/2`, so which guide fits which scale is decided once). *Rejected:
  `scale_alpha/2`*, R's alias. *Deferred:* `h.start`, gradientn's `values` and `rescaler`,
  `aesthetics`, a transformation on these scales (so `lims/2` refuses numbers high to low for
  them, which R reverses), `scale_alpha_manual()`, a gradient through colours with an alpha.

- **`palette:` takes a list of colours (2026-10-19, Steve).** On `scale_color_continuous/2` it
  is a gradient through them, the palette `scale_color_gradientn/2` records, as R's vector of
  colours draws exactly gradientn's; on `scale_color_discrete/2` it gives the levels their
  colours in order, the palette a manual scale's list records, and too few raise when the plot is
  run, as R's manual scale fails (its discrete palette warns and leaves the points undrawn). A
  palette stays a value naming its function (the entry beginning "A scale's palette is a
  field"). *Rejected: a function as well* (`fn count -> colors end`), as R takes one: the scale
  would hold a closure, and it draws nothing more, its one example needing brewer's colours.
  *Deferred: a palette by name* (R's registry of 138, `"viridis"`), with the brewer and viridis
  palettes most of its names point to.

- **A colour of `:none` beside others in a column is held as `nil`, and a geom reads a missing
  colour as `:none` (2026-10-19, Steve: "Fix"; found by step 7's notebook sweep).** Step 5's
  `na_value: :none` raised whenever a value was missing, and an annotation's list such as `fill:
  [:none, "red"]` was refused at the call: each made a column of colours beside `:none`, and a
  column holds one type. R's column holds `NA`, so `nil`, the table's missing value, is the same
  value, and the two `layer_data()`s agree: the assembly puts a value a scale maps to `:none` in
  as `nil`, and `annotate/3` holds a list's `:none` so. `Geom.Mark.colors/2` reads it as
  `:none`, which every geom already draws as R draws `NA`: no point, line or label, a rectangle
  unfilled or unbordered. A scale still maps to `:none`, so a legend's key keeps it, and a set
  `colour: :none` still fills its column. *Rejected: the frame taking `:none` beside a string*:
  the frame knows nothing about plots, and `nil` already means missing. *Rejected: a transparent
  colour*: R draws no mark for `NA`, where a transparent colour is a mark.

- **The hue scale's options are spelled out: `hue:`, `chroma:`, `luminance:` and `direction:`
  (2026-10-19, Steve).** `scale_color_hue(hue: {0, 90}, luminance: 40)`, as the hue palette
  records them and as Giggly names things, no abbreviation or single letter: `hue:` the range of
  hues in degrees, spread end to end unless it spans the circle, `direction: -1` handing the
  colours out in reverse, R's own name and values. *Rejected: R's `h:`, `c:` and `l:`*, what a
  ggplot2 user types, from R's `hcl()`: three single-letter names in the API.

- **A gradient is one palette of any number of colours, and gradient2's midpoint is the scale's
  (2026-10-19, part of the agreed step 5).** R's three gradients are one palette,
  `pal_gradient_n()`: each colour in L*a*b*, a straight line between neighbours as `approxfun()`
  draws it, exact at each colour. So `{:gradient, colors}` replaces `{:gradient, {low, high}}`;
  generalised from two colours, Giggly's blend matches R on all 30,054 colours sampled from six
  colour sets, through the `color` library with farver's constants, no new library. gradient2
  centres its colours on the midpoint by R's `rescale_mid()`, which R keeps on the scale as its
  rescaler, so `Scale.Continuous` holds it as its `rescaler`, `{:mid, midpoint}`; its colour bar's
  ticks are placed over the limits, as R places them, ignoring it. *Rejected: a palette per
  function*, three copies of one blend. *Rejected: the midpoint in the palette*: a palette takes a
  place from 0 to 1, and the ticks never go through the midpoint.

- **`date_breaks:` and `date_minor_breaks:` are a step as `Date.shift/2` takes one, `[week: 1]`,
  and `date_labels:` is a `Calendar.strftime/3` format (2026-10-19, Steve).** A step is one of
  `day`, `week`, `month` and `year`, R's units, with a positive whole count; its breaks run from
  the extent's start rounded down to the unit to its end rounded up, as R's `breaks_width()` runs
  them. A format is written by `Calendar.strftime/3` as it is, and checked at the call by writing
  a date with it, so one it cannot write raises there; the default labels still follow R's
  `format()`, a year unpadded. *Rejected: R's `"1 week"`*: a small grammar parsed inside an Elixir
  API. *Rejected: `{1, :week}`*: no Elixir API writes a date step so. *Rejected: R's `format()`,
  every conversion and flag the C library writes for a date ported*: it would draw scale_date's
  `"%W"` plot, which waits on it; where the two differ (`%x`, `%z`, a year under 1000), a
  format's labels differ from R's.

- **A discrete axis names its values as the column holds them (2026-10-19, Steve).** `limits:`,
  `breaks:`, a labels map's keys and a discrete `xlim/2` name each value as it is: `factor(cyl)`'s
  levels as `[8, 4]`, a boolean as `true`, the missing value as `nil`; a column of strings, the
  common case, reads alike either way. The entry beginning "`factor()` reads a value as discrete"
  kept a factor's numbers as values because text sorts `10` before `9`; naming them by value keeps
  one identity for a level from the column to the axis, its text only how the axis writes it.
  *Rejected: by text, as R matches `as.character()` of each value* (`limits = c("8", "4")`): a
  level would have two names, and `"NA"` would collide with the missing value.

- **Discrete and date position scales are the scale functions' step 4, each option checked
  against ggplot2 4.0.3 in R (2026-10-19, Steve, agreeing the proposal).** `scale_x_discrete/2`
  and `scale_y_discrete/2` take `name:`, `limits:` (the values shown, in order; one left out is
  missing, `nil` places the missing value), `breaks:`, `labels:` (a list, a map from value to
  label as R's named vector, a function, or `:none`; a list of the wrong length raises, where R
  pads it with `NA`) and `expand:`. `scale_x_date/2` and `scale_y_date/2` take `name:`,
  `limits:` (sorted, never reversed: R's `limits()` reverses numbers only), `breaks:`,
  `date_breaks:`, `labels:`, `date_labels:`, `minor_breaks:`, `date_minor_breaks:` and
  `expand:`; an option given with its `date_` twin is refused at the call, where R takes the
  twin. `Giggly.Scale` exports `Discrete`, which `Plot` writes (Steve). A list in `xlim/2`,
  `ylim/2` or `lims/2` gives a discrete scale's limits and two dates a date scale's. A date under
  `scale_x_continuous/2` is placed at its days, labelled as numbers, as R draws it; under another
  transformation it is refused, where R fails. *Rejected: `Discrete` unexported, the assembly
  building it from options in another shape*: every option in two shapes. *Rejected:
  `xlim(plot, "I1", "IF")`*: a second form of the list, for R's loose arguments. *Deferred:*
  `na.translate`, `drop`, a discrete `palette`, `continuous.limits`, discrete minor breaks, `oob`,
  `position`, `sec.axis`, and numbers on a discrete axis, which R places and Giggly refuses, an
  axis being one kind.

- **Transformations are log10, sqrt, reverse and reciprocal, R's transformation objects ported
  whole (2026-10-19, Steve).** `scale_x_continuous/2`'s `transform:` takes `:identity`, `:log10`,
  `:sqrt`, `:reverse` or `:reciprocal`, and `scale_x_log10/2`, `scale_x_sqrt/2`,
  `scale_x_reverse/2` and their y twins set it: the scale_continuous page draws each, reciprocal
  its own example. Breaks are found in data units on the extent turned back, labels written from
  breaks turned back, a labels function handed those; limits, given breaks and minor breaks are
  given in data units and transformed, limits then sorted, as ggplot2 sorts them, so a scale
  function takes either order, and `xlim/3`, `ylim/3` and `lims/2` reverse an axis given high to
  low, as ggplot2's `limits()` does. A value outside the domain is R's: `log10(0)` is minus
  infinity, at the panel's edge, a NaN missing. *Rejected: R's other transformations* (log, log2,
  exp, pseudo_log): no example draws one. *Rejected: transformations a user defines*: `Transform`
  made API, built from closures. *Rejected: refusing high-to-low limits on a scale function*: the
  order means nothing once transformed (`scale_x_reverse` takes both).

- **`Giggly.Format`'s `comma/2`, `percent/2` and `currency/2` take every option of scales
  1.4.0's `label_comma()`, `label_percent()` and `label_currency()` (2026-10-18, Steve).**
  `currency`, since scales 1.4.0 supersedes `label_dollar()` with it, the output the same (the
  entry beginning "Giggly exposes no function" holds for scales too); the notebook draws
  `label_dollar()` with it. Each takes `accuracy:`, `scale:`, `prefix:`, `suffix:`, `big_mark:`,
  `decimal_mark:`, `trim:`, `style_negative:`, `style_positive:` and `scale_cut:`, and currency
  `largest_with_fractional:` (Steve: "do the options you were going to defer"). `scale_cut:` is a
  list of `{suffix, threshold}` pairs, which R's `cut_short_scale/1`, `cut_long_scale/1`,
  `cut_si/1` and `cut_time_scale/1` return; it must hold a threshold of 0, since without one R
  misaligns the step below (`c(m = 60, h = 3600)` writes 5400 as `5 400NA`). Its options are
  NimbleOptions schemas, as every public option in Giggly is, so its boundary lists NimbleOptions
  (Steve). *Rejected: `dollar/2`*, the name ggplot2's example calls: superseded. *Rejected: the
  first four options alone*: separators, padding, sign styles and cuts are R's too. *Rejected:
  `scale_cut: :short_scale`*: two shapes in one option. *Rejected: any list, each value taking
  its own lower step*: a label R never writes. *Rejected: options checked by hand, so the
  boundary lists nothing*: a second error for a bad option, and docs kept beside the checks.

- **Scale functions are Phase 3's seventh increment, in seven steps: continuous position scales,
  formatters, transformations, discrete and date position scales, colour, fill and alpha
  scales, guides, the notebooks (2026-10-18, Steve, agreeing the proposal; checked against
  ggplot2 4.0.3 in R).** Scales were Giggly's thinnest part: no user-facing option, and the spec
  the entry beginning "Scales are three values" names had never existed. 30 of the 571 waiting
  notebook examples wait on scale functions alone and 125 name one. The functions are `Plot`'s,
  in `plot.ex` (Steve), and American only, `scale_color_*` (Steve: "America"), as the theme is
  `:gray`; options still take `colour:`. *Rejected:* histograms and box plots (18 alone; next in
  line), the theme (about 16 drawable), size, shape and linetype (15), `facet_grid()` (11); two
  increments, position then colour (they share no example, so a split moved only a notebook
  sweep); British aliases (R exports 22 of each, the notebooks write `scale_colour_` 154 times to
  once): every alias is API surface. *Deferred:* binned scales, viridis and brewer, ordered
  factors, `sec_axis()`, datetimes, `oob`, identity scales, guide options but `reverse`, legend
  position, `coord_cartesian()` zoom, size, shape and linetype scales, and extracting R's
  `scales` half into a package (Steve: later).

- **A scale function records the untrained scale as its spec: a `%Scale.Continuous{}` carrying
  its options, its range `:none` (2026-10-18, Steve).** The entry beginning "Scales are three
  values" has the trained scale as the spec plus a range, as ggplot2 copies the scale a user adds
  and trains the copy; so the assembly starts from the plot's scale for an aesthetic, or
  `Scale.new/1` from the column's type, and `Giggly.panel_scales/2` shows the options. `Plot`
  lists `Giggly.Scale`, which exports its kinds, and `PlotRunsNothing` keeps `Scale`'s root out
  of `Plot`'s files, so the plot writes a struct and never trains or maps one, as with coordinate
  systems and facets: that answers why `Plot` was kept from listing `Scale` on 2026-10-12 (the
  entry beginning "Position scales are chosen by column type"). *Rejected: the options as plain
  data the assembly builds a scale from*: no grant, but every option in two shapes.

- **`labels:` takes a list, a function handed every break drawn, or `:none`; Giggly's formatters
  are list functions in `Giggly.Format` (2026-10-18, Steve).** A function sees every break at
  once, as R's do, so a formatter can give them shared decimals (R's `precision()`:
  `label_comma()` writes 0.5, 1 and 1.25 as `0.50`, `1.00`, `1.25`) and `currency` can drop
  cents only when every break is whole; it returns one label per break, or the run raises.
  `comma/2`, `percent/2` and `currency/2` are plain functions shipped for convenience (Steve),
  matching R's `label_*()` output. A label list needs a breaks list of its length, checked at the call.
  *Rejected: a function called per break*: shorter to write, but no formatter could share
  decimals. *Rejected: formatters named by value* (`labels: :comma`, ggity's): a second
  contract. *Rejected: `Giggly.Labels`*: it shares its last segment with `Giggly.Scale.Labels`,
  and it owns no table.

- **"Absent" in a public option: `:none` removes, an option left out is the default, and a limit
  the data supplies is `nil` (2026-10-18, Steve).** `breaks: :none` draws no breaks, as R's
  `NULL` does, beside `colour: :none` and `labs(x: :none)`; nothing stands for R's `waiver()`,
  since leaving the option out is the default. `limits: {nil, 4}` and `xlim(plot, nil, 4)` take
  the low end from the data, as R's `NA` does, since `nil` is already Giggly's missing value.
  *Rejected: `:none` for the open limit*: it would mean "remove" in one option and "the data
  decides" in another. *Rejected: `nil` for "remove"*: it already means a missing value.

- **API docs describe Giggly on its own terms; comparing with ggplot2 is the notebooks' job
  (2026-10-18, Steve).** A public moduledoc, `@doc`, `@typedoc` or option doc says what Giggly
  does: what a function draws, its aesthetics and options, an example or two. It names no ggplot2
  counterpart, R function it ports or difference from R; the notebooks show each ggplot2 example
  beside Giggly's and note where the drawing differs. How a port follows R stays where its
  maintainers read it, an internal module's comment block and its rules file. A dataset still
  says whose table it copies. *Rejected: the docs as written until then*, each function tied to
  its ggplot2 counterpart with R's mechanics spelled out (72 "as ggplot2" in `plot.ex`'s 1,990
  lines, a sentence repeated in seven functions): they read as a specification and restated what
  the notebooks already show.

- **A verdict names a missing expression by what it needs, never as "an expression in a mapping"
  (2026-10-18, Steve).** Once columns, per-row expressions, constants, `factor()` and `after_stat()`
  landed, the phrase named something Giggly has, so step 4's sweep took it out of every verdict:
  where nothing else waited the example is drawn, a capture wherever one function computes it and
  its title noted where it differs from R's; elsewhere the piece is dropped, an `after_stat()`
  waiting only on its stat included. What is still missing is named by the feature that would
  unlock it: `after_scale()`, `stage()`, "a whole-column function in a mapping, such as
  `reorder(manufacturer, cty)`" (one head that sees a column), "a vector outside the data in a
  mapping, such as `miss`", and "`after_stat()` reading `group`". *Rejected: keeping "an
  expression in a mapping, such as …" for these*: one familiar term, but a search for it would
  find landed and waiting examples alike, and the next sweep would read every one to tell them
  apart.

- **A verdict names a date format `Calendar.strftime/3` cannot write by its code in `date_labels`
  (2026-10-19, Steve: "A").** scale_date's second plot labels weekly breaks `"%W"`, the week of
  the year, which `date_labels:` refuses at the call, since a format is written by
  `Calendar.strftime/3` (the entry beginning "`date_breaks:` and `date_minor_breaks:` are a
  step"). Its verdict reads "`"%W"` in `date_labels`, the week of the year, which
  `Calendar.strftime/3` cannot write", so a search for the code or the option finds it.
  *Rejected: "R's `format()` for dates, here `"%W"`"*: it names the port that entry rejected, and
  a search would find it only if that port were made.

- **An after_stat reads its stat's computed variables as ggplot2 documents them, checked at the
  call (2026-10-18, Steve's choice; checked in R).** `{:after_stat, [value]}` is left out of
  evaluation and grouping, evaluated against the stat's output, and put through its aesthetic's
  scale, as `map_statistic()` does. Its names are the stat's documented variables (counting's
  `count` and `prop`), so a misspelt one is refused by the layer function, and a layer whose stat
  computes nothing refuses every after_stat. Neither name is a position, so R's read-back into
  data units arrives with the first stat documenting one (`stat_boxplot()`). An axis's scale is
  still chosen before the stat: a value on it must be numbers (dates on a date axis), else refused
  when run, where R adds a scale or warns. An aesthetic only an after_stat maps gets its scale
  after the stat; `weight`, which counting consumes, is refused. *Rejected: every column counting
  writes* (`x` or `y`, `width`, `flipped_aes`): the list turns with the bars, and none is of use.
  *Rejected: R's whole reading* (carried columns, `group`): not checkable at the call. *Rejected:
  an after_stat inside an expression*, which R allows: one way to write it, the value inside.

- **`factor()` reads a value as discrete through a declared `:category` column type (2026-10-18,
  Steve, agreeing the step-2 proposal; checked in R).** `{:factor, [value]}` evaluates its value
  and the assembly declares the column `:category`, a type the frame never reads from values, so
  grouping and the scales take it as discrete, its levels in order of value with `nil` last and
  each written as R's `as.character()` writes it, as `factor()` labels them; every discrete level
  is so written, so a boolean column reads `FALSE`/`TRUE`, as R's does. It is refused as an
  expression's argument, where R hands a function a factor's level codes. A discrete scale is told
  levels from positions by the stage that trains it (`train/2`, `train_positions/2`), and a legend
  key's drawing by the scale's kind, never by a value's type. *Rejected: the level text as the
  column's values* — strings sort `10` before `9`, and R sorts by value. *Rejected: telling levels
  from positions by `is_number/1`* — a factor's numbers are levels.

- **R's `as.character()` is a boundary of its own, `Giggly.AsCharacter` (2026-10-18, Steve).** The
  text geom wrote its labels by it and a factor's levels need it in the scales, and neither
  boundary lists the other; it depends on nothing, and both list it, as `Giggly.Resolution` is R's
  `resolution()`, and so does the facet, whose strips are ggplot2's `label_value()`, so `mtcars`'
  doubles read `4` there too. *Rejected: `Scale.Labels`, with `Geom` listing `Scale`* — a geom would reach
  scales, which its rules keep it from. *Rejected: a copy in each* — two homes for one rule.

- **The mutation pass mirrors `.credo/` into muex's sandboxes, and checks one first with no mutant
  (2026-10-18, Steve).** A plain project's sandbox links only the entries muex names, `.credo/` not
  among them, so `test/credo_checks_test.exs`, which loads its checks from there, failed in every
  sandbox; where coverage has no data for a line muex can run every test file, the credo test
  failed first, and the mutant was "killed" with no test of `lib/` tried. Every pass since
  2026-10-15 had such kills; `bb57487`'s had 541 of 1,441, and of `6dc3658`'s 99, 64 survived once
  rerun. muex's baseline, the suite once in a sandbox with no mutant, would have refused those runs
  but runs for an umbrella only, so the skill runs it itself, in a sandbox muex builds with Giggly's
  build copied in: seconds, and 19 failures without `--mirror .credo`. *Rejected: leaving the
  credo test out with `--test-paths`* — a list of test paths that drifts. *Rejected: the test
  finding `.credo/` another way* — only muex's symlinks lead back. *Rejected: scanning the kills
  for one test failing on its own* — muex clips each error before its stack trace, and real kills
  share errors too, so it flagged a dozen real groups beside the false.

- **A mapping value is a column, an expression or a constant, as plain data, and
  `Giggly.Mapping` holds the grammar (2026-10-18, Steve; the `{function, [values]}` shape his).**
  An atom or a string is a column; `{function, [values]}` applies a capture or a closure per row;
  `{:factor, [value]}` and `{:after_stat, [value]}` are heads; `{:constant, term}` wraps a string
  or atom constant, and a number, boolean or date is one alone. Data keeps a plot a value that
  prints, and a wrapper goes only where the type is ambiguous: ergonomics over regularity. A guide
  is titled by a value's text (`hwy / cty`, `:math.log10(carat)`), a closure's by nothing until
  `labs()`, and a constant's by its aesthetic's name as a fallback, as R's `make_labels()` does
  (checked in R; the constant's own text was assumed first). *Rejected:* builder functions on
  `Plot` (names without brevity, in the biggest file); an `aes` macro (sugar over the same data
  later, perhaps); MFA tuples (a capture is the MFA as a value); `{columns, closure}` alone
  (nothing prints or titles); `{:constant, [term]}` (a list holds what is evaluated); a protocol
  for the heads (`:factor` acts on the column, not per row).

- **Expressions in a mapping are Phase 3's sixth increment, in four steps: the grammar with
  constants, computed columns and titles; `factor()`; `after_stat()`; the notebooks (2026-10-18,
  Steve).** 119 of the 591 waiting notebook examples name an expression, the most-named piece; the
  scope covers about 95 of the 109 forms named, and about a dozen examples wait on nothing else.
  Checked in R first: `map_statistic()` puts an `after_stat()` value through the scale, reading the
  stat's output back in data units, and `factor()` prints a double's level as R prints the number
  (`4`, `1e+05`). A computed weight's type is known only when run, so counting refuses a non-number
  then, where R warns and draws nothing. *Out:* whole-column work (`cut_width()`, `reorder()`,
  `interaction()`, `max(count)` in `after_stat()`; it needs a head that sees the column), a list as
  an inline column, `stage()`, `after_scale()`, ordering a factor's levels, `aes(colour = NULL)`,
  plotmath; `..count..` never (superseded).

- **Mutation testing runs after each commit, over the lines it changed, and the commit gate holds
  the next commit until it has run (2026-10-18, Steve).** The `mutation-testing` skill runs muex's
  mutants with `--since HEAD~1` over the commit's changed `lib/` files, then triages, fixes and
  reports what it found; the fixes are committed when Steve says so. `commit-gate.sh` denies any
  commit while the last one changed code and has no mutation mark, and an after-commit hook names
  the pass as due. *Rejected: running it in code review, before the commit, over whole files* — a
  run took 30–60 minutes, and a comparison on 2026-10-17 found the commit's lines ran about 5% of
  the mutants at almost no loss. *Rejected: the after-commit hook alone* — the gate exists because a
  skill step slips under wrap-up pressure, and just after a commit is that moment. *Rejected: whole
  modules for a commit that changes only tests* — the same cost for the same rare case.

- **A title may run over several lines, drawn a line at a time as R's graphics engine draws them
  (2026-10-17, Steve: "Build multi-line now").** Every title, an axis's, a legend's and the plot's
  own, splits where it breaks and draws each line as a label of its own, its `lineheight` (0.9
  unless set) x 1.2 font sizes below the one before, stacked by `vjust` as the engine stacks
  lines; it is as deep as its lines spaced out and a line of text, ggplot2's `titleGrob` measure,
  and as wide as its widest line. The scene and the backend learn nothing: a text's per-label
  offsets place each line. Tick labels, strips and `geom_text()` labels stay one line. *Rejected:
  refusing a label that breaks at the call* until multi-line text arrived, recommended because no
  waiting example needs one; a title breaking over lines is common in ggplot2 practice.

- **`labs/2` takes the titles of the aesthetics a guide shows and the plot's title, subtitle,
  caption and tag, as text or `:none`, and the plot's labels are drawn in `Giggly.Guide`
  (2026-10-17, Steve, agreeing the proposal and the widening).** A key Giggly shows nothing for, a
  misspelling or an aesthetic it maps no guide for, raises at the call, as every option does, and a
  number is refused where R writes it; a label for an aesthetic no layer maps titles nothing, as R
  ignores it. Calls merge, the latest winning per key, and a label wins over the mapped column and
  a stat's, so a label decides which legends merge. `Guide.Title`, which the guide boundary
  exports, measures and draws them as `Guide.Axis` draws the axes' titles; rendering lays out its
  cells. *Rejected: accepting any key, as ggplot2 does,* which lets a misspelt `titel:` draw
  nothing; *the plot's labels in `Guide.Axis`*, which they are not part of; *measured in
  rendering*, which computes no sizes.

- **A position declares the aesthetics it reads, with their defaults, and the assembly writes them
  into every row just before the position runs, as ggplot2 4.0's `Position$use_defaults()`
  (2026-10-17, Steve).** Nudging reads `nudge_x` and `nudge_y`, which `geom_text/3` sets; the
  stage writes the layer's value or else the default, 0, so every text layer's table carries both,
  as R's `layer_data()` does, though no geom's defaults are written yet. No layer maps a nudge yet,
  so a nudge the plot maps, carried into a text layer, is replaced and moves nothing. *Rejected:
  writing only a set nudge*, the position reading 0 where the column is absent, which keeps tables
  free of defaults but differs from R's and gives the position a missing-column case; *writing only
  where no column exists*, as R does, which lets a plot's nudge mapping move each label while a
  layer's own is refused: half of a deferred feature, with no check of the column's type.

- **An aesthetic a layer takes from the plot and cannot use rides along unused, as ggplot2 carries
  one (2026-10-17, Steve, settling §7's question as the second geom drawn beside points arrived).**
  A layer's own mapping is checked against what it accepts; the plot's reaches every layer, so a
  plot can map `label` for its text and still draw points, as ggplot2's `geom_text` example does.
  The carried aesthetic is evaluated into the layer's table and drawn by nothing; a discrete one
  still splits the layer's groups (never `label`, which grouping leaves out), and the layer draws in
  a legend only for aesthetics it accepts, a legend no layer can draw dropped, as ggplot2's
  `matched_aes()` and its guides do. Its geom is handed the rows without it, so none reads it as a
  value the layer sets (2026-10-19, Steve: a carried `linewidth` broke a path). *Rejected:
  dropping it for that layer*, the same drawing for
  `label` but not for a plot-level `fill`, which splits a line's groups in ggplot2; *refusing it*,
  the first geom's rule, which cannot write that example.

- **Text and titles is Phase 3's fifth increment, in six steps: `geom_text()`, nudging, `labs()`,
  a layer's own table, `annotate()` with `geom_rect()`, the notebooks (2026-10-17, Steve, agreeing
  the proposal; checked against ggplot2 4.0.3 in R).** It draws 21 of the 591 waiting notebook
  examples. Titles are the second most-named piece (35 examples) after an expression in a mapping
  (137), and afterwards 19 examples wait on the theme alone. `geom_rect()` comes because the bar
  geom already draws its rectangles, and it gives `annotate()` its shaded rectangles. *Rejected:*
  histograms, box plots and jitter (17 examples, but three stats matched to R's numbers, and a
  jitter R draws differently on every build); expressions in a mapping (10, two of them printed
  mappings, and the largest API question left); themes (about 19 of 27: five need a global default
  theme the pure core rules out, and all need the whole element tree); `geom_label()` now (one
  example, for a rounded box traced as grid traces it). *Deferred:* `parse = TRUE`, dodging text,
  `inherit.aes`, mapped text `size`, `key_glyph`, `fontface`, `size.unit`, `labs()`'s `alt`,
  `alt_insight` and `dictionary`, a function as a label (formatting the default title, `labs(x =
  toupper)`) and `waiver()` (the default title, asked for), `get_labs()`; multi-line tick labels,
  strips and text labels.

- **A layer's own table is public: `data:`, an option of every layer function, as ggplot2's
  `data =` (2026-10-17, Steve).** `annotate()` needs a layer with a table of its own, drawn in
  every panel, so the machinery is built either way. Making it public adds the facet layout read
  from every layer's table (a value only a layer has adds a panel, as in R), a table lacking some
  facet columns repeated across them, and a check at the call that the layer's table holds the
  columns the plot maps (R fails with "object not found"). It draws facet_wrap's "The same data in
  every panel" now, and 14 more waiting examples need it. `inherit.aes` waits for an example that
  needs it. *Rejected: a table internal to `annotate()`*, recommended first for a reason that did
  not hold: §7's inherited-mapping question is about aesthetics a geom cannot use, which a layer's
  own table leaves alone.

- **A column the plot names is checked against the tables that use it, as ggplot2 checks it
  (2026-10-18, Steve, asking "Why not follow R here?").** `new/2` checks only that each value of its
  mapping is one the mapping grammar takes; each layer function checks every column it draws with,
  its own mapping's and those it takes from the plot's, against the table it draws, raising at its
  call. `facet_wrap/3` checks the form of its columns at the call, and whether the plot's data or
  some layer's own table holds them all is the facet's question, raised when the plot is run, as
  ggplot2's "At least one layer must contain all faceting variables". So both may name a column only
  a layer's table holds, as R 4.6.1 with ggplot2 4.0.3 draws them; the cost is a misspelt facet
  column reported at run time. *Rejected: checking both against the plot's data at the call*,
  recommended first: stricter than R, it would have to move once a plot may have no data, and its
  reason, that a mistake raises from the line that wrote it, is a rule of Giggly's own, which the
  mapping's check still keeps at the layer's call.

- **`annotate()` draws with every geom Giggly has, from values recycled as R recycles them
  (2026-10-18, Steve).** Its positions become a table of its own, a row per annotation, mapped as
  ggplot2's `aes_all()`, so they train the scales and repeat in every panel; it takes nothing from
  the plot's mapping (`inherit.aes = FALSE`), titles no axis (an unlabelled mapping) and is in no
  legend. Each option takes one value or a list, every list as long as the others. An option its
  geom cannot use raises, where ggplot2 warns, its position still widening the axis. Steve chose
  point, col and bar, path, line, text and rect; *rejected:* text and rect alone, recommended, as
  the waiting examples use no other. A list only for what a geom draws row by row (`label`,
  `colour`, `alpha`, `fill`); *rejected:* every aesthetic, as R, which needs text drawn at its own
  size, angle and font per label. A list under a facet of several panels raises when run, as
  ggplot2's "Aesthetics must be either length 1 or the same as the data"; *rejected:* drawing it
  in every panel, which carries set values past the colour scales.

- **Giggly exposes no function ggplot2 has superseded or deprecated (2026-10-17, Steve: "generally
  speaking we aren't going to expose superseded things").** ggplot2 4.0.3 marks `xlab()`, `ylab()`
  and `ggtitle()` superseded by `labs()` (`lifecycle::signal_stage()`), so Giggly has `labs()`
  alone. The same holds for `coord_flip()`, `coord_polar()`, `coord_map()`, `expand_limits()` and
  `annotation_logticks()`, superseded, and for `qplot()`, `coord_trans()`, `borders()`,
  `geom_errorbarh()` and `aes_string()`, deprecated. A superseded function stays in ggplot2
  without a warning, but ggplot2 recommends its replacement, and one way to say a thing keeps the
  API small. *Rejected: the shortcuts for parity* with ggplot2 and with ggity, which had `xlab/2`
  and `ylab/2`: three more public functions that only rename a key of `labs()`.

- **A discrete scale carries its missing value as a field, `na_value`, as ggplot2's scale carries
  `na.value` (2026-10-16, Steve).** A missing level takes no share of the palette and maps to it:
  grey50, `#7F7F7F`, for colour and fill, `nil`, R's `NA`, for alpha and a position, which places
  `nil` as its last level instead. Both scale kinds are API, so the field is too, on
  `Scale.Discrete` and `Scale.Continuous`, whose missing or non-finite value maps to it as well.
  *Rejected: the palette
  carrying it* (`{:hue, ..., na: ...}`), which keeps the struct as it was, but R's palettes know
  nothing of `NA`, and a scale function's `na.value` would have to rewrite the palette.

- **A library's owner nests under the umbrella, and the root lists the library (2026-10-16,
  Steve).** boundary lets a sub-boundary list an outside library only when its parent does, so
  `Giggly.DataFrame` lists `Table` and `Giggly.ColorOperations` lists `Color`, and the root lists
  both libraries in place of their owners. The only module the root's list opens a library to is
  `Giggly`, the run functions; every domain is strict and calls only what it lists, so a domain
  reaching a library needs a widening the waiver gate brings to the user. Nesting drops two
  `top_level?:` exemptions and keeps the namespace and the boundary tree one shape, as boundary's
  docs prefer. *Rejected: top-level owners*, which close one silent path, `Giggly` calling a
  library, at the cost of an exemption per library.

- **Colour and fill is Phase 3's fourth increment, in four steps: fixed colours, mapped discrete
  colour and fill, mapped continuous colour and fill with the colour bar, the notebooks
  (2026-10-16, Steve, agreeing the proposal; checked against ggplot2 4.0.3 in R).** Colour is the
  most-waited-for aesthetic: 283 of the 619 waiting notebook examples need colour or fill, though
  only six need nothing else, most also waiting on jitter, smoothing, `labs()` or a scale
  function. A discrete colour takes the hue palette and a legend; a continuous one the default
  gradient and a colour bar, the second guide kind. *Rejected: folding in `factor()`* (Steve), which
  colour does not need, since discrete scales already have levels; an expression in a mapping is
  an increment and an API decision of its own. *Deferred:* scale functions and their options,
  `guides()` and legend positions, ordered factors and viridis, binned and date colour scales,
  point shapes with a fill, base R's `col` and `fg`, numeric colours, `geom_raster()` and
  `faithfuld`.

- **Colours are CSS's names and hex forms, carried as uppercase hex strings (2026-10-16, Steve).**
  A colour is `#RRGGBB`, or `#RRGGBBAA` when it carries its own alpha, and `:none` is R's `NA`:
  the form R, CSS and the scene already use, so it sits in a frame column, a scale's `na_value`
  and a legend key as any string does. A name CSS lacks (`grey50`) raises at the call. A notebook
  keeps ggplot2's name with CSS's meaning and notes where the drawing differs (CSS's `green` is
  `#008000`, R's `#00FF00`), and writes a name CSS lacks as its hex, naming the R colour. A row's
  `alpha` replaces a colour's own alpha, as `scales::alpha()` does, and a missing one keeps it; a
  bar's border is never given the row's, as `GeomRect` draws it. *Rejected: R's 657 names*
  (recommended), whose `gray`, `green`, `maroon` and `purple` are not CSS's; *CSS's plus R's
  extras*, a vocabulary of neither; *a struct*, a public type in every column and scale for what a
  string carries. R's `transparent` is white and CSS's black, which shows under a set alpha.

- **R's exact colours come from the `color` package's conversions, handed farver's constants
  (2026-10-16, Steve: no hand-rolled colour maths).** Both of ggplot2's default palettes go
  through farver (`pal_hue()` too, not `hcl()`). `Color.Conversion.Lindbloom` takes the matrix and
  the white point as arguments: given farver's sRGB matrices, the white point farver's R code
  makes from D65's chromaticity (0.31271, 0.32902) rather than the textbook 95.047 and 108.883, and
  each channel rounded half to even, it matches R on 50,400 HCL values, `pal_hue()` for 1 to 40
  levels, and all but one of 35,007 gradient samples, a colour below L* 8 where farver keeps
  0.008856 and 7.787. `Giggly.ColorOperations` is its only caller; a gradient's interpolation in
  Lab is the scale's, as in R's scales. *Rejected: `color`'s own conversions*, 12 of 820 hue
  colours a byte out; *porting farver*; *`Giggly.Color`* (Steve: `Color.` could not be grepped
  apart from the library's) and *`Giggly.Colors`* (Steve).

- **The colour bar is drawn as ggplot2's gradient form (2026-10-16, Steve).** ggplot2's default
  (`display = "raster"`) is a 1×300 PNG, which svglite writes as a base64 `<image>`; its
  `display = "gradient"` is a `<linearGradient>` of 15 stops filling a `<rect>`, which svglite 2.2
  writes and SVG draws natively, within 0.99/255 of the raster's colours on the default gradient.
  Its ticks take the gradient form's places, and its id comes from its content, not svglite's
  `pat-0`, so two plots on one page cannot share it. The bar's elements are checked against
  svglite's drawing (vdiffr cannot draw a gradient), the rest of the plot against vdiffr's.
  *Rejected: the raster*, checkable only by decoding pixels, and needing a PNG writer and
  `xmlns:xlink` on every root; *rectangles*, 300 of them, with seams.

- **The guide protocol sits at `Giggly.Guide`, a scale names its guide, and legends stack in
  aesthetic order (2026-10-16, Steve, agreeing the proposal).** A protocol module holds nothing but
  its protocol (`defprotocol` allows nothing else), so the axes and their titles move to
  `Guide.Axis`, the strips to `Guide.Strip`, the grid to `Guide.Grid` and the stacking to
  `Guide.Box`, exported for rendering. A scale records its guide by name, as ggplot2's scale
  carries `guide` (`:axis` for a position); the assembly turns the name into the kind's struct, as
  `Plot` turns `position: :dodge` into one, and works out a guide's keys and a colour bar's colours
  from the scale (2026-10-17, Steve), so a guide only draws and never sees a scale. Legends stack
  as `package_box()` stacks them on the right, a column, each left-aligned, `legend.spacing.y`
  apart, centred on the panels; same kind, title and labels merge (a colour bar's colours too).
  ggplot2 orders them by a hash of title, labels and kind (9 of 20 random title pairs came out
  alphabetical), so Giggly orders by aesthetic name and a golden's R script sets `guides(order =)`.
  *Rejected: the protocol in a submodule*, leaving the exports alone; *title order*; *the kinds
  extracting their own keys*, as ggplot2's `extract_key()` does, which has `Guide` list
  `Giggly.Scale` and a guide calling toward the data.

- **The document's root declares svglite's stylesheet for lines as attributes (2026-10-16,
  Steve).** svglite gives every line round ends, round corners and a mitre limit of 10 through an
  embedded stylesheet, and writes a line's own only where it differs. Giggly writes no stylesheet,
  since one inlined in a page styles the whole page, so a browser would draw SVG's defaults, mitre
  corners limited at 4, where ggplot2's lines are round. The `<svg>` element carries
  `stroke-linecap='round' stroke-linejoin='round' stroke-miterlimit='10.00'`, which every element
  inherits, so each writes exactly what svglite writes; presentation attributes sit at the bottom of
  the cascade, so a page's or a future CSS theme's rules outrank them. Every golden's root changed
  once. *Rejected: writing round corners on each line*, three more things to strip from every
  comparison with svglite, and grid lines left mitred; *an inline `style` on the root* (Steve's
  question), which works as well for elements but beats any stylesheet rule aimed at the root.

- **Lines and date axes are Phase 3's third increment, in four steps: paths and lines, lines in
  radial coordinates, dates on an axis, the notebooks (2026-10-16, Steve, agreeing the proposal;
  checked against ggplot2 4.0.3 in R).** A line chart over time is the commonest dashboard chart,
  and Phase 3's roadmap names lines next. `geom_path()` and `geom_line()` take x, y, `group` and
  `alpha`, a set `linewidth`, `lineend`, `linejoin` and `linemitre`, and `geom_line()` its
  `orientation`; a panel is drawn as polylines, or as segments where alpha varies along a line,
  as ggplot2's `GeomPath` decides. `Coord.munch/3` arrives with them, so a radial line curves. A
  `Date` column gets a continuous scale through a date transformation whose breaks are R's
  `prettyDate()`, labelled in the format it chose. **Steve's choices:** the line options above
  ride along. *Rejected: a fixed `linetype` now*, its patterns being the table a mapped `linetype`
  scale needs; *`geom_step()` now*, which arrives with `stat_ecdf()`; *datetimes now*, which
  bring sub-day steps and time zones and draw no notebook example; *refusing lines in radial
  coordinates*, since `coord.md` planned munching for the first path geom. *Deferred:* arrows,
  `key_glyph`, colour on lines, `economics_long`, radial bars.

- **Guides become structs of their kind behind a protocol in the increment that brings a second
  kind, expected to be colour (2026-10-16, Steve, agreeing the proposal).** ggplot2 makes each
  guide an object of its kind (`GuideLegend`, `GuideColourbar`, `GuideNone`, the axes), chosen per
  aesthetic, and runs every guide through one lifecycle: extract the key, merge, take the layers'
  keys, draw, pack the guide box. Giggly already runs a legend through those stages as plain
  functions, its kind fixed (`legends/3` in the assembly, `draw_legend/2` in rendering). Then each
  kind becomes one module holding its struct (its options), key and drawing, behind a protocol at
  `Giggly.Guide`: a build function the assembly calls, a drawing one rendering calls; glyphs stay
  on `Geom.draw_key/2`. Merging groups guides by order, kind, title and labels, each kind merging
  its own way. Axes join when a user can choose one. `Plot` building guide structs widens its
  boundary, raised then. *Rejected: ggity's legend protocol on the scale*, every scale redoing the
  layout and its own glyphs. *Rejected: building it now*, a protocol with one implementation.

- **A legend is a table nested in the plot's, as gtable nests one (2026-10-16, Steve, agreeing
  the proposal).** A legend has rows and columns of its own (margin, title, a row per key, key and
  label columns) and sits centred on the panels' rows, which a facet interleaves with strips and
  axes. So a cell's primitives may include a `%Giggly.Scene{}`, laid out in the cell's box and
  centred when its sizes are all points, as grid centres a fixed gtable in its viewport; the
  legend's cell spans the panel rows right of the panels. Its geometry is read from ggplot2's
  `GuideLegend` (`setup_elements()`'s margins and justifications) and checked against R, not
  fitted. Each geom draws its own key (`Geom.draw_key/2`), as ggplot2's `draw_key` does.
  *Rejected: the legend's rows and columns in the plot's table*, which centring on faceted panels
  breaks. *Rejected: one cell placed by point offsets*, which rectangles and circles lack and which
  would write the key backgrounds unlike svglite.

- **A scale's palette is a field of the two scale kinds, a value naming its function (2026-10-16,
  Steve, agreeing the proposal).** ggplot2 makes every scale a continuous or a discrete scale and
  makes it an aesthetic's by its palette, a function from R's `scales`: `pal_rescale(c(0.1, 1))`
  for continuous alpha, `seq(0.1, 1, length.out = n)` for discrete, the identity for a position.
  So `Scale.Continuous` and `Scale.Discrete`, public through `Giggly.panel_scales/2`, gain
  `palette`, `:identity` for the axes, and colour, size and shape will add palettes, not kinds. A
  palette is a value (`{:rescale, {0.1, 1.0}}`), resolved by `Scale.Palette` as a transformation's
  name is, so a scale stays a value. *Rejected: separate structs for non-position scales*, a second
  pair training the same way. *Rejected: a module per aesthetic and kind*, ggity's
  `Scale.Alpha.Continuous`, whose closures and legends multiplied with each aesthetic.

- **ggplot2's `diamonds` is shipped whole, kept compressed, and drawn whole (2026-10-16, Steve).**
  `geom_point`'s transparency example draws all 53,940 diamonds, which no sample shows, and the
  pages that sample draw from the whole table. Kept as its columns, as `mpg` is, it would be some
  18 MB held wherever `Giggly.Datasets` is loaded, which a release does at boot; compiled into a
  compressed binary it is 0.49 MB, decoded in about 23 ms per call, with no IO. Its read has a
  waiver of its own, as every dataset's does. *Rejected: reading the file when called*, as ggity
  did, since the core does no IO. *Rejected: drawing a sample* (Steve did not mind the departure)
  — the example is about overplotting at scale, and 53,940 points draw in about half a second as
  an 8 MB SVG. *Open:* whether `mpg` and `mtcars` move to the same compressed storage.

- **Alpha is Phase 3's second increment, in four steps: setting it, mapping it through a scale,
  its legend, the notebooks (2026-10-15, Steve, agreeing the proposal; checked against ggplot2
  4.0.3 in R).** Steve chose `alpha` to build a non-position aesthetic, its scale and its legend
  without colour spaces and palettes. A set value is a keyword option of the layer function
  (`Plot.geom_point(alpha: 0.4)`), ggity's idiom of a map mapping and a keyword list setting, and
  is applied last, as ggplot2 applies `aes_params`. A mapped numeric column is rescaled onto 0.1 to
  1; a point is transparent outline and fill, a bar its fill only, as ggplot2's geoms draw them,
  and the scene carries an opacity per mark. **A text column mapped to alpha is drawn as ggplot2
  draws it, its values spread evenly over 0.1 to 1, without ggplot2's warning (Steve).**
  *Rejected: refusing a text column* (recommended, as ggplot2 advises against it) *and leaving it
  out.* *Deferred:* `scale_alpha()`'s options, binned and date alpha, legend positions but the
  right, and combining legends.

- **Bars are Phase 3's first increment, in five steps: columns, counts, dodge, horizontal bars,
  a notebook (2026-10-15, Steve, agreeing the proposal; checked against ggplot2 4.0.3 in R).**
  Steve chose bars before other aesthetics to exercise stats, positions and discrete axes.
  `geom_col` and `geom_bar` with `stat_count` (its group split and constant-column carry,
  `weight`, `y` from `count` titled "count"), `position_stack` and `position_dodge`
  (`preserve = "total"`), and orientation, which the entry beginning "Giggly follows ggplot2's
  current coordinate functions" said arrives with the first geom that has a direction (Steve:
  now). Position scales reset and retrain after the position, a discrete scale keeping its levels
  and retraining the continuous range bars give it. A bar's width follows R's `resolution()`,
  integer columns included (Steve): an integer column's bars are 0.9 wide. *Rejected: width from
  the values alone*, which departs from ggplot2 for R's integer columns. *Deferred:* bars under
  `coord_radial()` (Steve), with `Coord.munch/3` and the radial options every radial bar example
  needs; `position_fill`; `geom_bar`'s options; histograms.

- **A geom says where its marks sit in data space during the build (`Geom.setup_data/2`), and
  the assembly calls only the families' build functions (2026-10-15, Steve).** ggplot2 calls a
  geom's `setup_data` after the stat and before the position, since positions stack and dodge a
  mark's extent and the retrained scales must cover it (a bar's `ymin` of 0). So the assembly lists
  `Giggly.Geom`, as it lists `Giggly.Coord`, and could call `draw_panel/4`; `assembly.md` says it
  calls build functions only, which review holds. *Rejected: a credo allow-list* (proposed) — the
  assembly calls family roots by design, so the list would change with every build stage, against
  a mistake no one has made; *a protocol per family for drawing* — the compiler would hold it, at a
  second protocol name per family, rejected before; *the extent in the stat, the position or
  rendering* — counting tied to bars, each position knowing each geom, or axes that miss the mark.

- **A geom is told whether each axis is discrete, so a bar finds its orientation as ggplot2's does
  (2026-10-15, Steve).** ggplot2's `GeomBar` draws horizontally when y alone is `mapped_discrete`;
  Giggly's discrete positions are plain integers, so the assembly hands `Geom.setup_data/3` each
  axis's scale kind, a kind and never a range. Counting decides from which of x and y is mapped,
  and positions read the `flipped_aes` column. *Rejected: an `orientation:` option instead* — a
  departure for every horizontal `geom_col()`; *`geom_bar` alone this step* — `geom_col` with a
  discrete y drawn wrongly meanwhile.

- **A layer chooses its position by an atom now, a constructor later (2026-10-15, Steve).**
  `geom_bar` and `geom_col` take `position: :stack | :dodge`, ggplot2's string shorthand,
  validated by NimbleOptions, `:stack` by default. When a position's parameters arrive,
  `Plot.position_dodge/1` returns its struct and the same option takes it, as ggplot2's
  `position = position_dodge()` does; a position's parameters never become the geom's options,
  ggity's mistake (`position_vjust:`). *Rejected: constructors from the start* — two public
  functions taking nothing yet, more to write for the common case.

- **ggplot2's `resolution()` is a boundary of its own, `Giggly.Resolution` (2026-10-15,
  Steve).** A mark with a width in data units takes it from the closest spacing of its positions:
  a bar is 0.9 of it. The bar geom needs it (step 1), the count stat with different options (step
  2), positions later (jitter), each in its own boundary, so one pure function sits where each may
  list it. It asks `Giggly.Scale` whether a range is zero wide, the one home of R's
  `zero_range()`. *Rejected: in `Giggly.Scale`* — a geom would list the scales, against the
  coordinate seam; *a copy where used* — one utility in two places, then three.

- **A kind is named after ggplot2's ggproto class without its family prefix; a class ggplot2
  keeps only as an alias is not a kind (2026-10-15, Steve).** `GeomPoint` is `Geom.Point`,
  `CoordRadial` `Coord.Radial`. ggplot2's `GeomCol` is an empty subclass of `GeomBar` marked to
  be deprecated, so `geom_col/3` records `%Geom.Bar{}` with `%Stat.Identity{}`: functions take
  ggplot2's function names and may share a kind, as ggplot2's `geom_histogram()` is `GeomBar` and
  `geom_jitter()` `GeomPoint`. *Rejected: `Geom.Col`* — a second kind drawing exactly as the first.

- **`coord_radial()` is built in four steps, in its simplest form, with ggplot2's defaults
  (2026-10-15, Steve, agreeing the proposal).** Checked against ggplot2 4.0.3 in R: a full circle
  clockwise from 12 o'clock, scales expanded exactly as cartesian ones, and `clip = "off"`, its
  own default. The panel is square (`coord$aspect()` is 1) and its background a munched disc; the
  r axis is a left axis up the panel's upper half, its labels centred between two margins
  (`axis.text.r`); the theta axis is drawn inside the panel over the layers, unmeasured. The
  radial transform places `x` and `y` only, as ggplot2's does, and fails loudly on any other x-
  or y-family column, since a range cannot be placed without its pair; munching is private to
  `Coord.Radial` until a path geom brings `Coord.munch/3`, which is where geoms first bend (Phase
  3: ggplot2's rect and segment geoms ask `is_linear()`).
  *Deferred:* every option, `guide_axis_theta()`'s options, label merging (needs
  `expand = FALSE`), a notebook (its examples need bars, arcs, an inner radius).

- **A primitive's position is a place in its cell plus an offset in points (2026-10-15, Steve).**
  The theta axis's ticks and labels sit 2.75 and 4.95 points out from points on the circle, while
  the panel's size is known only when the backend lays the scene out, so a position is grid's
  `unit(x, "npc") + unit(d, "pt")`: a polyline's points carry offsets, `{across, up}`, and a
  text's anchor one, `{along, up}` in its own frame, which replaced its `baseline_offset`. Text
  takes any `hjust`, which the SVG backend writes as R's graphics engine writes it for svglite,
  the nearest of start, middle and end shifted by the rest of the label's width, a device's limit
  being the backend's. A polyline says `fill: none`, as grid's never fills, so a radial grid's
  circle is not filled black; *rejected: svglite's stylesheet*, which in an inlined SVG styles
  the whole page.
  *Rejected: rendering laying the scene out at the drawing's size*, everything then in points —
  the scene tied to one size, closing off a backend that lays it out again (a resizing LiveView or
  Kino plot).

- **A `:rest` size has a weight, and a scene can keep its proportions, gtable's null units and
  `respect` (2026-10-15, Steve).** Radial panels are square: ggplot2 sets panel heights to the
  aspect ratio in null units, widths to 1, and has the table respected, so both directions take
  one scale, the largest that fits, and the table is centred, the plot's background covering the
  table only. A size is `{:rest, weight}`; the scene's `keep_proportions` is gtable's `respect`,
  named for what it does, as `:rest` is for "null". Rendering gives panel rows the aspect ratio
  the assembly carries as their weight and keeps proportions; without one, weights are 1 and the
  layout is as before. *Rejected: an `aspect_ratio` on the scene* (proposed) — one case of the
  weights, replaced again when `space = "free"` arrives; the general form costs a few lines, its
  unequal weights pinned by the backend's tests until a pipeline gives one. **The plot's
  background is clipped to the table** (Steve, found building the faceted golden), as gtable adds
  it, cutting its border's outer half at the table's edge; *rejected: a stated departure*, a
  hairline on a dark page. *Deferred:* the drawing beside a kept-proportion table stays empty
  (svglite paints its page white).

- **The design log is reference, not reading, and each fact has one home (2026-10-15, Steve).**
  Sessions filled their context before touching code: orientation read a 24,000-word design log
  and a 5,900-word plan, and one change was written into four or five surfaces. Now a session
  orients from its plan's "Where we are", a few hundred words; a §4 entry is about 150 words, read
  by name; §6 is one line per milestone, the commit message carrying the story; a rules file holds
  invariants, and the mechanism lives in the module's documentation. *Rejected: an in-repo status
  file* — a commit every session. *Rejected: dropping §6 for `git log`* — the index ties each
  milestone to its §4 entries. *Rejected: compressing the existing §4 entries* — nuance lost from
  entries now read only by lookup. *Rejected: keeping a trimmed "How it works" in each rules
  file* — a second home for the mechanism.

- **Each dataset's file is read behind a waiver of its own, so every new dataset asks (2026-10-15,
  Steve).** `Giggly.Datasets` reads each dataset's file at compile time with `File.read!/1`, which
  the `CorePurity` check refuses without a waiver. Adding `mpg/0`, the facet_wrap notebook's data,
  I proposed one read for every dataset, the waiver moved onto a comprehension over the files and
  reworded for datasets in general, since every dataset's answer would be the same. Steve chose a
  waiver per file: "I'd rather you have to ask each time as opposed to adding whatever you want to
  the list". A list behind one waiver would let a dataset in without anyone deciding it, while a
  waiver per file makes each one a stop. The parsing is shared; only the reads are separate.
  *Rejected: one read covering every dataset's file* (proposed) — a list that grows with no
  decision.

- **Every plot's cells are drawn in ggplot2's facets' order, a plot without a facet included
  (2026-10-15, Steve).** ggplot2 is not consistent: a plot without a facet draws its y axis before
  its x axis (`FacetNull$draw_panels()` gives the left axis a lower z than the bottom one), while
  `facet_wrap` and `facet_grid` add every bottom axis before every left one at one z, so draw them
  in that order. Axes never overlap, so the order changes nothing visible, only the order of the
  SVG's elements, which the goldens' comparison with ggplot2 diffs. Rendering arranges every
  plot's panels the same way (the entry beginning "`facet_wrap` is built in steps"), so it can
  follow one order: ggplot2's facets', in which the panels go column by column, the strips and
  bottom axes from the last row of panels to the first, and the left axes from the last column to
  the first, as ggplot2's `weave_tables_row()` and `weave_tables_col()` add them. The plain plot's
  golden draws its x axis before its y axis, which `test/golden/point.R` names; the faceted golden
  matches ggplot2's drawing in every element, in order. *Rejected: the facet carrying a drawing
  order as data (ggplot2's z levels)*, which matches every kind of plot exactly but adds a concept
  to the layout only to reproduce a difference no one can see; *and the plain plot's order for
  every plot*, which puts every faceted golden out of ggplot2's order instead.

- **`facet_wrap` is built in steps after the conversion to structs, and the facet says where each
  panel's axes and strips go as data, which rendering arranges and the guide draws (2026-10-14,
  Steve, agreeing the proposal's recommendations).** Step 1 is panels as data:
  `Plot.facet_wrap(plot, facets, options)` with `facets` a column or a list of them, named at the
  call as a mapping names one, and `nrow:` and `ncol:` validated by NimbleOptions, which `Plot` will
  list; panels are the combinations of values present, ordered as a discrete scale orders its
  levels by the key the assembly hands in (`Scale.level_key/1`, as for `Group.add/2`), `nil` its
  own panel labelled `NA`, laid out by ggplot2's `wrap_dims()`. Too few cells for the panels
  raises when the plot is run, since counting the combinations is the facet's computation and the
  plot checks only what it knows. §7's question of how an option says "absent" does not arrive: a
  caller leaves `nrow:` out and never writes "absent". Step 2 draws several panels: strips, one per
  facet variable, stacked, the value as ggplot2's `label_value` gives it; the theme's panel
  spacing; axes at the margins, a panel above an empty cell included; panels sharing what the
  fixed sizes leave equally. Step 3 is free scales. Step 4 is a notebook following ggplot2's
  `facet_wrap` reference page, with `Giggly.Datasets.mpg/0`, in this increment (Steve).
  **The arrangement:** the facet's layout table says, for each panel, which axes it draws and its
  strip labels; rendering arranges the scene's table from those columns, knowing no facet; and
  `Giggly.Guide` draws the strips, text in the theme's look in a cell beside the panel, measured
  as an axis title is, and by the guide's own definition something that helps a reader turn marks
  back into data. No boundary changes, and the facet stays a data domain. *Rejected: ggplot2's
  shape, the facet protocol drawing its panels and strips* (`draw_panels`, `render_strips`) —
  `Facet` would list `Font`, `Scene` and `Theme`, a data domain becoming a drawing one. The cost
  of the choice made: an arrangement the layout's columns cannot express, such as a third party's
  facet, grows a case in rendering. *Deferred:* `labeller`, `strip.position`, `dir`, `as.table`,
  `axes` and `axis.labels`, `space`, `shrink`, `drop` (moot without factors), a layer's own data,
  `facet_grid`, and theme settings for strips.

- **Each facet, coordinate system, geom, stat and position is a struct of its kind, computed or
  drawn through a protocol at its family's root, and a repo-local check keeps `Plot` from
  referencing those roots (decided 2026-10-14, Steve; built the same day as Phase 2's step 0).** A
  plot recorded each of these choices by name (`facet: :null`, `geom: :point`), resolved to a
  module implementing its family's behaviour. Names have no room for parameters, and `facet_wrap`,
  Phase 2's first increment, brings the first (its variables, `ncol`, free scales), with
  `coord_radial()`'s, geoms', stats' and positions' after it. Names also spread each kind's facts
  across the pipeline: `Plot` held `geom_point`'s accepted and required aesthetics while
  `Geom.Point` drew, and default aesthetics (the assembly) and legend keys (the guides) would
  each add another place, the scattering the ggity research found. **The shape:** a family's root
  is a protocol (`Giggly.Geom` with `draw_panel/4`; `Giggly.Stat` with `compute_layer/3` and
  `Giggly.Position` with `compute_layer/2`; `Giggly.Facet` with `layout/1` and `assign_panels/2`; `Giggly.Coord` with
  `panel_params/3`, `transform/3`, `axes/2`, `grid/2` and `clip/1`), each function taking the
  kind first, and each kind is one module holding everything about it, as ggplot2's `GeomPoint`
  does: `Giggly.Geom.Point` has `defstruct` with the kind's parameters, functions giving its facts
  (`accepted_aesthetics/0`, `required_aesthetics/0`), and `defimpl Giggly.Geom, for: __MODULE__`
  with its drawing. The identities are `%Stat.Identity{}` and `%Position.Identity{}`, still values
  a test can assert. `Plot` lists the five family boundaries, builds the kinds' structs, and reads
  their facts to check a mapping at the call, so `plot.md`'s "a mistake raises from the call that
  wrote it" holds. A third party adds a kind with a module of its own and a `defimpl`. **What
  building it settled**, each a consequence of a protocol dispatching on its first argument rather
  than a fresh choice: **the geom is handed the coordinate system** as well as the panel's params
  (`draw_panel(geom, frame, coord, params)`, ggplot2's own signature, where the decision had said
  `draw_panel/3`), since every coordinate function needs the coordinate system's struct to
  dispatch on, so the assembly carries the plot's coordinate system and rendering hands it on
  unread; *rejected: params carrying the coordinate system inside them* — the geom would read a
  field of params meant to be opaque. **Panel params are a plain map** the coordinate system's
  implementation builds and alone reads, as ggplot2's are a list, since `%Coord.Cartesian{}` now
  names the coordinate system. **`clip` moved from the params to the coordinate system's struct**
  (`%Coord.Cartesian{clip: :on}` by default), where ggplot2's `coord$clip` keeps it and where
  `clip = "off"` will be set, so the assembly carries one `clip` rather than one per panel.
  **Boundary checks nothing a protocol implementation calls until the implementation is
  classified** (found by compiling a `defimpl` that called a module its family does not list: it
  compiled clean; boundary's checker skips references from an unclassified implementation), so
  every `defimpl` opens with `use Boundary, classify_to:` its protocol, and the boundary
  declarations test fails on any implementation in the app not classified into its protocol's
  boundary. Such a line only narrows and has one right answer, so Giggly's `waiver-gate.sh` passes
  a `classify_to:` naming the protocol of the `defimpl` it opens, on the line straight after it,
  and still stops any other (Steve: my edit to the hook was refused by Claude Code's auto mode, and
  he applied the tested patch himself). *Rejected: the hook as it was* — a stop for every kind,
  each with one answer; *thin implementations calling functions on the kind's module* — the
  drawing would sit on an exported module `Plot` could call. **The check:** `boundary` cannot let
  `Plot` use `Geom.Point` while forbidding `Giggly.Geom`, since a boundary always exports its root
  module and a boundary may depend only on its siblings, its parent and its ancestors' deps (read
  in its source), so `GigglyCredo.Check.PlotRunsNothing` holds the rule: in `Plot`'s files, no
  module reference resolves to a root — a call, a module passed as a value (which closes a call
  through a variable), an `import` or `require`, a typespec (a protocol's `t()` is any term, so a
  field holding a kind is typed `struct()`) — following aliases, grouped or renamed with `as:`,
  while an `alias` of a root, the `use Boundary` declaration, and a kind's struct and fact
  functions stay allowed. **Its roots are every protocol Giggly defines, derived in `.credo.exs`**
  (Steve), which raises on a build with none; *rejected: the five named in `.credo.exs`* — a
  second list to keep in step, and a later protocol (scale kinds) would go unchecked. It runs in
  `mix credo --strict`, and the waiver gate stops any disabling of it, as `CorePurity` holds what
  boundary cannot see. **The boundary changes were approved one at a time** (Steve): `Plot` lists
  `Coord`, `Facet`, `Geom`, `Position` and `Stat`, and each family exports its kinds
  (`Facet.Null`, `Coord.Cartesian`, `Geom.Point`, `Stat.Identity`, `Position.Identity`), whose
  computing stays in implementations nothing exports. An export applies to every boundary listing
  the family, so a geom or guide could match `%Coord.Cartesian{}`, which the coordinate seam's
  rule forbids and review watches for. **Transformations stay a name and a behaviour**
  (`transform: :identity`) until the first one a user chooses (`scale_x_log10()`), when a struct
  has something to hold (Steve); *rejected: converting them now, for one shape everywhere.*
  Themes stay functions returning a value (the entry beginning "A theme is a function"): a
  protocol on a struct is for kinds that differ in what they do. *Rejected: names with a
  behaviour, as before* — no room for parameters, and facts spread. *Rejected: names with
  parameters and a table of facts in `Plot`* — closed to extension, facts apart from the drawing.
  *Rejected: descriptions taking the family name with a separately named drawing protocol*
  (`Geom.Point` with `Giggly.Draw`) — a second protocol name per family. *Rejected: descriptions
  under `Plot` (`Plot.Geom.Point`)* — `Plot`'s exports grow, and the computing domains would
  depend on `Plot`. *Rejected: a boundary of descriptions (`Spec.Geom.Point`)* (Steve) —
  three-level names, and `Spec` abbreviates. *Rejected: no `Giggly.Geom` module, each kind its own
  boundary beside a `Geom.Draw` protocol* (Steve's, and the one the compiler would hold) — a
  boundary per kind, and two dependency entries per new kind, each a widening; about seventy
  boundaries by Phase 3's end. *Rejected: a check against anything under a family's namespace* —
  it would forbid the facts; the rule is about the roots. *Deferred:* a public function adding a
  layer of any kind (ggplot2's `layer()`), which third-party kinds need, until the first one;
  required aesthetics checked after the stat, as ggplot2's `compute_geom_1()` checks them.

- **The assembly's titles are `guide_titles`, the title each aesthetic's guide draws (2026-10-14,
  Steve).** `%Assembly{}` held the axes' titles as `titles`, keyed by aesthetic, a name chosen
  because "labels" here means a break's text. But ggplot2 titles a legend by the same rule as an
  axis (`setup_plot_labels()` over every aesthetic), so the map will grow by `color:` and the
  rest, while a plot's own title, subtitle and caption belong to no aesthetic; `titles` would have
  read as every title in the plot once a plot title existed. They are the titles guides draw:
  ggplot2's axes and legends are both guides, each titled from the mapping and set with
  `guide_axis(title = …)` or `guide_legend(title = …)`, and `Giggly.Guide` draws them. The field,
  the private `guide_title/3` that finds one, and `Guide.Axis.titles/4`'s argument took the name.
  *Rejected: `aesthetic_titles`* — it says how the map is keyed, not what the titles are for;
  *and waiting for `labs/2`* — the rename was cheapest while nothing depended on the name.

- **A theme is a function that builds the complete theme, not a module implementing a behaviour;
  a behaviour is for kinds that differ in what they do (2026-10-14, Steve).** `Giggly.Theme` had a
  behaviour of one callback, `complete/0`, and one module implementing it, `Theme.Gray`, because
  every name a plot records resolves through its namespace, and facets, coordinate systems, geoms,
  stats, positions and transformations are each a module implementing their namespace's
  behaviour. Those kinds differ in what they do: a coordinate system has five operations that all
  change when it is radial rather than cartesian, and a behaviour groups operations that vary
  together. Themes differ only in their values, every theme one `%Giggly.Theme{}`, so a callback
  returning the struct was a function in disguise. ggplot2's complete themes are functions with
  arguments (`theme_grey(base_size = 11, …)`), and the others are built from one by replacing
  elements (`theme_bw()` is `theme_grey()` `%+replace%` a few), neither of which a callback with
  no arguments can express. The behaviour bought nothing besides: names were resolved by a closed
  match in `complete/1`, so no one could add a theme by implementing it. Each complete theme's
  derivation is a private function of its base sizes in `Giggly.Theme` (`gray/1`, `bw/1` …),
  which a user chooses through `Plot.theme_gray/2` and its kin. *Rejected: keeping the behaviour for
  uniformity* — the rule is that a behaviour serves kinds that differ in behaviour, and plain
  functions serve kinds that differ in data.

- **The scene's circle primitive is `Circles`, not `Points` (2026-10-14, Steve).** The scene names
  its primitives after grid's, and this one holds positions and their radii, grid's
  `circleGrob(x, y, r)`; grid's `pointsGrob()` takes a shape and a size, which it never held. A
  primitive is named for what it draws, a shape, while a geom is named for the grammar's mark:
  `geom_point` and `Geom.Point` keep their names, and which primitives a point is drawn with is the
  geom's business. When shapes become an aesthetic, the likely design follows R's split, where
  `pointsGrob()` meets a graphics engine (`GESymbol` in `engine.c`) that turns each shape into
  circles, rectangles, polygons or line segments and the device draws only those, so shape 19
  stays `Circles` and no scene primitive called `Points` returns. *Rejected: keeping `Points` until
  the shape stage* (proposed) — the name broke the scene's own rule, and the churn feared was
  real only if the scene held shapes itself, which the likely design does not; *and renaming
  everything point-related to circle* — the geom draws the grammar's point, whatever it draws it
  with.

- **Zip and map in one pass, `Enum.zip_with/2,3`, and a repo-local credo check holds the rule
  (2026-10-13, Steve).** Three places piped `Enum.zip` into `Enum.map`, building a list of tuples
  only to walk it again; `Enum.zip_with` calls the function as it zips. CLAUDE.md's Conventions now
  say so, and `GigglyCredo.Check.ZipMap`, the repo's first check in `.credo/checks/`, fails the gate
  on a zip piped or passed straight into a map, as credo's own `MapJoin` does for `map` then
  `join`. The case for a check over fixing the three by hand is the code still to be written: an
  agent writes `zip |> map` by habit, and a credo finding is the feedback that sticks. The module
  is named outside `Giggly`, as the test helpers are (`GigglyTest`), since it is the repo's, not the
  library's (my choice). *Rejected: fixing the three by hand with no check* — the habit returns
  with the next agent. *Rejected for now: `Stream.zip` into `Stream.map`, and zip then reduce
  (`Enum.zip_reduce/4`)* — nothing here writes either; the check grows when something does. What
  it cannot see, by design: a zip bound to a variable and mapped later, and `Enum` reached through
  an alias; it reads the code as written, as `MapJoin` does.

- **The API is what a user calls, and everything else says it is not API: an internal module is
  `@moduledoc false` with its documentation as an opening comment, every public function says
  whether it is API, and only API functions have doctests (2026-10-13, Steve).** Every module had
  a `@moduledoc` and every public function a `@doc`, so ExDoc published the whole pipeline, the
  assembly, rendering, the scene's primitives and `Plot.computed_mapping/2` among it, as if users
  called it; Elixir has only `def` and `defp`, and a function another module calls must be `def`.
  CLAUDE.md's rule meant that the API is documented, not that every `def` is API. The API is now
  `Giggly`'s run functions, `Plot`, `Datasets`, `DataFrame`'s readers (`names/1`, `row_count/1`,
  `dtypes/1`, `pull/2`, since `layer_data/2` returns a frame) and the two scale structs
  `panel_scales/2` returns. Every other module is `@moduledoc false`, its documentation kept word
  for word as a comment block at its top (Steve: nothing stops the documentation being kept
  without being a moduledoc). Every public function says whether it is API, wherever it is: a
  `@doc` string, or `@doc false` with its explanation as a comment, in an internal module too
  (Steve: explicit, not inferred from the module), so Tack's `PublicFunctionDoc` check still holds
  every public function to an answer. A function that is not API is tested by ordinary tests
  (Steve: doctests make no sense for documentation users will not read); its examples moved one
  for one into its module's test file, compared with `===` as a doctest's pinned match compares,
  and an API example shows what a user sees, never an internal struct. API types name no hidden
  type, which ExDoc warns about: `DataFrame.t` is `@opaque`, and `Plot` and `Giggly` gained
  `aesthetic` and `panel_scale`. *Rejected: hiding internal modules with ExDoc's
  `filter_modules` option* (recommended: no source change, every doctest kept) — Steve chose
  `@moduledoc false`, which the module itself says. *Rejected: internal modules left in the docs*
  — users would read the pipeline's joints as API. *Rejected: an internal module's functions
  keeping their `@doc` and doctests under `@moduledoc false`* (this decision's first wording) —
  examples no user reads are tests written in doc syntax. *Rejected: narrowing
  `PublicFunctionDoc` to the API modules' files* (recommended) — a second record of what is API,
  and an API module left off it goes unchecked; *and a Giggly copy of the check skipping
  `@moduledoc false` modules* — a second check to maintain and test. *Rejected: the frame
  implementing `Table.Reader` so that `DataFrame` stays internal* (recommended: a user would read
  `layer_data/2` with Explorer, Kino's data table or `Table`, the protocol data comes in by) —
  Steve chose `DataFrame`'s readers as API.

- **Data a plot cannot read is refused by raising, at the call; what to do about bad data is
  decided upstream (2026-10-13, Steve).** Reviewing `DataFrame.from_table/1`, Steve asked whether
  loading data is a process boundary that should return `{:ok, frame}` or `{:error, reason}`
  through `with`. It is not: `from_table/1` is handed a value already in memory, any IO happened
  where the caller read the data, with that tool's tuples, a pipe cannot carry a tuple, and
  Explorer draws the same line (`from_csv/2` returns a tuple, `DataFrame.new/2` raises). Giggly's
  part is to detect bad data and refuse it loudly, since a plausible wrong plot is worse than a
  crash; the caller decides what to do about it. A precondition checked as a statement, by a
  helper that returns `:ok` or raises (`Plot`'s `check_accepted/1`), is idiomatic: Elixir's
  standard library writes its checks the same way, with and without a bang (`Module`'s
  `validate_doc_meta/2`, `Supervisor.Spec.supervise/2`'s `assert_unique_ids/1`). *Rejected:
  tuples or `with` at data loading.* What the review found and left unscheduled is in §7.

- **Giggly follows ggplot2's current coordinate functions: no `coord_flip()` and no
  `coord_polar()`; Phase 2 proves the coordinate seam with `coord_radial()` (2026-10-13,
  Steve).** ggplot2 marked `coord_flip()` superseded in 3.5.0: a horizontal plot is made by
  swapping the x and y aesthetics, and since 3.3.0 geoms and stats detect their orientation from
  the mapping or take `orientation = "y"`; `coord_flip()` remains only for a geom or stat without
  that support. Giggly gives the feature without the function. For points it already works, since
  a point has no direction; for bars, boxplots and histograms it is orientation in the geom and the
  stat (ggplot2's `flipped_aes` and `flip_data()`), which arrives in Phase 3 with the first geom
  that has a direction, and `Aesthetics.counterpart/1` already gives its renaming. ggplot2 4.0.3
  signals that `coord_polar()` is superseded in favour of `coord_radial()` (checked by running it),
  which 3.5.0 added as its successor: partial circles by start and end angles, an inner radius, the
  radius axis inside the panel, an axis around the circle (`guide_axis_theta()`), `reverse`, and
  scales expanded by default as cartesian ones are, where `coord_polar()` expands none. Giggly
  follows `coord_radial()`, its arguments and its defaults, and offers no `coord_polar()`. Phase 2
  is now `facet_wrap` with free scales, then `coord_radial()` in its simplest form, a full circle
  with no inner radius, as the test that a coordinate system which places positions differently
  changes no geom; its other features follow it. *Rejected: `coord_flip` as Phase 2's coordinate
  test*
  (Phase 0's plan) — superseded, and the cheaper test it offered (axes and titles keyed by the
  aesthetic each side shows) is exercised by `coord_radial()`'s axes as well; *and
  `coord_polar()`* — superseded, with defaults that differ from its successor's.

- **A plot is drawn at the size it is given, in pixels, 700 by 433 by default, ggplot2's online
  reference size; `to_svg/2`'s options are the first NimbleOptions validates, from the root
  boundary (2026-10-13, Steve).** In Livebook the notebook's drawings looked tiny: `to_svg/1`
  drew every plot at vdiffr's 10 by 8 inches (960 by 768 pixels), chosen in increment 7 to match
  ggplot2's snapshots, while ggplot2's reference pages draw at pkgdown's default, 700 pixels wide
  at 96 dots per inch with the golden ratio's height (`pkgdown/R/figure.R`); text, points and
  lines keep their sizes in points, so on the larger canvas they take less of it, and Livebook
  then scales the image down to its column. Scaling the image could not help, since it keeps the
  proportions. `Giggly.to_svg/2` now takes `width:` and `height:`, **in pixels**, the unit
  Livebook, VegaLite and the web size things in, written in the document in points at 96 pixels to
  the inch; *rejected: inches*, ggsave's unit, which ggplot2's users know. **The default is 700 by
  433 pixels**, what the notebooks mirror; the golden passes vdiffr's 960 by 768 explicitly, so it
  still sits beside ggplot2's snapshots; *rejected: keeping vdiffr's size as the default*, which
  every notebook would override, *and R's 7 by 7 inch device*. **Options are validated with
  NimbleOptions at the call**, as ratified on 2026-10-11, and this is its first use: `nimble_options`
  1.1.1 (Apache 2.0, no runtime dependencies, its source read in increment 3) is a new dependency,
  and **the root boundary lists `NimbleOptions`**, since `to_svg/2` lives there, so a sub-boundary
  may list it in turn when its options arrive (`Plot`'s, by the same ownership rule); that settles
  where NimbleOptions sits, which the Phase 1 audit left for Phase 2. A misspelt option
  raises `NimbleOptions.ValidationError` naming it. The widening was agreed with the three
  choices and recorded with `waiver-gate.sh approve-widening`.

- **The notebooks follow ggplot2's reference pages, every example, as documentation; their data
  is a public datasets module read from R's own files (2026-10-13, Steve).** Steve's aim is a set
  of Livebook notebooks matching ggplot2's online reference, which ExDoc points at rather than
  drawing graphics itself, as ggity's docs did. The first, `notebooks/geom_point.livemd`, follows
  the `geom_point()` page: **every example, in the page's order** (Steve), each with ggplot2's
  code first; the two Giggly can draw are drawn, and the rest keep their code and name what they
  wait for, so the notebook is also the page's list of what remains. *Rejected: only the
  examples Giggly can draw.* **No ggplot2 drawings beside Giggly's** (Steve: "this is a
  documentation tool first"); checking a drawing against ggplot2 stays review's job. *Rejected:
  each example drawn by ggplot2 in Docker and shown beside Giggly's* (proposed). **The data is a
  module, `Giggly.Datasets`, so users have it for their own plots** (Steve); *rejected: JSON files
  beside the notebooks* (proposed) *and the data inline in each notebook*. `mtcars/0` is the
  first, a keyword list of columns in R's order with the row names as a first `model` column,
  whole numbers as integers as plotnine's copy has them. **Its values are R's file, read at
  compile time** (as recommended): `priv/datasets/mtcars.csv` is R 4.6.1's `write.csv(mtcars)`
  with a provenance header, read behind a second `CorePurity` waiver worded as `Giggly.Font`'s,
  and the file's header gives the column order. *Rejected: the values as literals in the module*
  — R's data could not be regenerated and diffed apart from the code, and its hundreds of literal
  mutants would survive every review, the reason the glyph table is a file. A notebook installs
  Giggly by path and Kino, and shows a plot with `Kino.Image` until the Kino side quest lets a
  plot show itself. Both drawn examples were checked against ggplot2's drawings of the same code
  and match in every element. The missing-values example draws R's `set.seed(1)` rows, named.

- **Every page of ggplot2's function reference has a notebook, and `notebooks/index.livemd`
  follows the reference index (2026-10-15, Steve).** The index keeps ggplot2's sections, their
  descriptions and its order, each entry a relative link to its notebook, which Livebook opens as
  a notebook of its own; it was written from ggplot2's rendered index for 4.0.3, the release
  the notebooks follow. Each notebook shows its page's examples verbatim, every line in
  order, and draws only those whose plot Giggly builds with its own functions, each checked
  against ggplot2's drawing in R; the rest name what they wait for in the same words everywhere,
  so a feature that lands finds its examples by search. *Rejected: an index of the built pages
  only* (recommended, as short and easy to keep true; Steve chose every page). *Rejected for now:
  ExDoc pages made from the notebooks*: they would show code without drawings, and "Run in
  Livebook" cannot install a path dependency until Giggly is published.

- **A notebook leaves out an argument ggplot2 does not recognise, and draws what R draws
  (2026-10-18, Steve).** geom_segment's example labels its segments with `hjust = 'outside'`, a
  word ggplot2 does not define: `compute_just()` reads it as `NA`, and R centres the labels exactly
  as `hjust = 0.5` does. Giggly's cell leaves `hjust` out, its default centring them the same, and
  the prose says what R does with the word. *Rejected: adding `:outside` to Giggly's
  justifications*, a word ggplot2 lacks, given a meaning only R's fallback gives it; *naming it as
  missing*, which would leave the example waiting on something Giggly will never build.

- **A verdict names a text's mapped size "mapping a text's `size`" (2026-10-20, Steve, in the
  size, shape and line type sweep).** Once a point maps `size`, "mapping `size`" names something
  Giggly has, so geom_text's example, which waits for a text to map it, and the About sentences
  that say what Giggly maps, name it "a text's `size`", as "a point's `fill`" names a point's.
  Giggly refuses it today: `geom_text/3` accepts no `:size` in its mapping. *Rejected: keeping
  "mapping `size`"* — after the sweep no point example names it, so a search still finds only
  text, but the verdict reads as if Giggly mapped no size at all.

- **An example R refuses on purpose, which Giggly refuses too, is shown by a cell returning
  Giggly's message (2026-10-20, Steve).** geom_path's `should_stop(p + geom_line(aes(colour = x),
  linetype = 2))` checks that R stops: a dashed line cannot change colour along it. Giggly raises
  an `ArgumentError` for the same line, so nothing waits and no verdict is written; the cell runs
  Giggly's line in `try`/`rescue` and returns the message, as `should_stop()` checks the failure,
  so the refusal is shown running and every cell still runs. *Rejected: prose only* — the refusal
  is taken on trust. *Rejected: a cell that raises* — closest to R's code, but the notebook keeps a
  cell that fails on purpose.

- **A value an example computes in base R before plotting is written out as R gives it
  (2026-10-22, Steve, in the distributions sweep).** geom_histogram's equal-count bins take their
  edges from `quantile(diamonds$price, probs = seq(0, 1, length = 11))`, base R's default
  quantiles; Giggly offers no quantile a user can call (the frame's is internal), so the cell
  writes R's eleven edges as a list and the prose says they are what `quantile()` gives, as a
  notebook takes the rows R's random numbers produced. The plot is still Giggly's own: `breaks:`
  takes the list, and both drawings match R's. *Rejected: computing them in the cell* — R's
  interpolation ported by hand, statistics in a page about plotting. *Rejected: leaving the
  example waiting on `quantile()`* — base R, not ggplot2, and nothing Giggly's plotting lacks.

- **A random sample of a table's rows is written out as R's row numbers, however many
  (2026-10-23, Steve: "A", in the ordering sweep).** scale_hue, scale_viridis and scale_brewer
  draw `diamonds[sample(nrow(diamonds), 1000), ]` after `set.seed(596)`, scale_shape 100 rows of
  the same draw. Each cell writes the numbers R's `sample()` picks as a `~w()` word list and takes
  those rows of every column; a `Giggly.Factor` enumerates as its values alone, so the cell
  rebuilds each factor with `Giggly.Factor.new/2` and its levels, or the cuts would sort
  alphabetically. Every such drawing matches R's. facet_wrap's `reorder(mpg$class, mpg$displ)`, a
  base-R step before plotting, is written out too, as the levels R gives, since faceting by an
  expression waits. *Rejected: leaving the 1,000-row examples waiting on R's `sample()`* —
  shorter notebooks, but base R, not plotting, as the entry above found. *Rejected: a list
  literal* — Elixir's formatter puts each of 1,000 numbers on a line of its own.

- **An example that sets ggplot2's active theme is drawn with the plot's own theme (2026-10-24,
  Steve: "go", in the theme sweep).** get_theme's `set_theme(theme_bw())` and `update_theme()`
  change a global theme Giggly rejects (the entry beginning "The theme is Phase 3's eleventh
  increment"); the plot drawn after each is the plot choosing `Plot.theme_bw/2` or setting
  `Plot.theme/2`, the counterpart Giggly offers, and the prose says Giggly has no active theme.
  `replace_theme()`'s example waits on `%+replace%`, deferred: removing an element and setting
  it again under a chosen theme draws the same, but only imitates it. This answers §7's "How a
  notebook treats an example of a function Giggly will not offer" for the active theme alone.
  *Rejected: a verdict waiting on the active theme* — one that never comes true. *Rejected:
  drawing `replace_theme()`'s example by removal* — the imitation `notebooks.md` forbids.

- **A verdict names a theme element Giggly lacks "the theme's `X` setting", by ggplot2's dotted
  name (2026-10-24, Steve: "go", in the theme sweep).** Once `theme/2` landed, "changing the
  theme" named something Giggly has, so the sweep took it out of every verdict and named what
  still waits: "the theme's `strip.placement` setting", `legend.byrow`,
  `palette.colour.continuous`; `element_geom()` by its function, and an element set in a guide's
  own theme by that guide's `theme` option. *Rejected: keeping "changing the theme, here its `X`
  setting"* — it says Giggly cannot change a theme, which `theme/2` does.

- **The panel is clipped to its edges; the coordinate system records it and the assembly carries
  it to rendering (2026-10-13, Steve).** What is drawn in the panel is cut off at its edges, as
  every ggplot2 coordinate system does by default (`coord_cartesian(clip = "on")`, applied in
  `Coord$draw_panel` with the background and the border): a point at an infinite position, on
  the panel's edge, shows only its inner half. `clip` is a parameter of the coordinate system's
  struct, read by `Coord.clip/1`; the assembly asks once and keeps it in `%Assembly{}` as `clip`;
  rendering marks the panel's cell, every `Scene.Cell` now saying `:on` or `:off`
  as gtable's `clip` does; and SVG writes a clipped cell as svglite writes a clipping viewport,
  a `<clipPath>` of the cell's box in `<defs>` and the cell's primitives in a `<g>` that uses
  it, with svglite's id, `cp` and the base64 of the box's `left|right|top|bottom`. The golden's
  clip markup is svglite's for ggplot2's drawing of the same plot, byte for byte. That id is kept
  because it is named by the box: two drawings inlined on one page share an id only when they
  share the box, while a counter would let one drawing's clip path cut off another's. svglite's
  group clipped to the whole drawing around everything else does nothing visible and is left out.
  Steve first chose the coordinate system's saying so over rendering clipping every panel itself,
  since a deliberate default is recorded as a value a test can assert; asked how I felt about the
  `Render` + `Coord` dependency that shape needed, I said it granted rendering the whole
  coordinate system, `transform/3` included, against its rule of computing no positions, to read
  one value with one answer, and proposed the assembly carry it, as it carries the axes' titles;
  Steve agreed. *Rejected: rendering clipping every panel as a rule of its own* (proposed first)
  — the coordinate system's default would be nowhere a test can see it, and `clip = "off"` would
  move it later. *Rejected: `Render` listing `Coord` to ask* (Steve's first choice) — the reasons
  above. No boundary changed. *Deferred to first reader:* `clip = "off"`, with the coordinate
  options.

- **An axis whose extent is zero wide once widened is drawn at the panel's middle, and the scale
  says so by giving the extent equal ends (2026-10-13, Steve).** A single value is widened by
  0.05 either side; from about 4.5e11 up that is rounding error beside the value, R's
  `zero_range()` calls the extent zero wide, and `scales::rescale()` puts every value on it,
  infinities included, at the middle of the panel; from about 1e15 up the widening is lost
  altogether and the extent's ends are equal. Giggly divided by zero there, and between the two
  put the point at the middle by arithmetic but the axis's one tick, at the extent's low end, at
  the panel's left edge. `Scale.dimension/1` now returns such an extent as its middle, both ends
  equal, and `Coord.Cartesian` puts every value on an axis of equal ends at the middle, before it
  squishes infinities, as ggplot2 rescales before it squishes; the single break, at that middle,
  is labelled with the value itself. Drawn with ggplot2 in Docker, single values of 1e12 and 1e16
  now match in every element but the label, which ggplot2 writes in scientific form (`1e+12`) and
  Giggly as plain digits, as decided for labels. *Rejected: mapping to the middle only when the
  ends are exactly equal* — it ends the crash but leaves the tick at the left edge for single
  values from about 4.5e11 to 1e15; *and a copy of `zero_range()` in the coordinate system* — one
  rule stored twice, while equal ends carry the scale's verdict to it. The check against ggplot2
  also found that cartesian coordinates' `grid/2` rescaled each line's ends on its own axis's extent
  rather than the other axis's, which agree whenever an extent's ends differ; across an axis of
  equal ends ggplot2's lines shrink to a point at the middle, and now so do Giggly's.

- **The panel's grid lines are placed by the coordinate system and drawn by the guide, at R's
  regular minor breaks; clipping waits for a step of its own (2026-10-12, Steve).** The panel
  is drawn as ggplot2's `theme_gray()` draws it: a light grey background (ink mixed 92% toward
  paper, no border) and white grid lines, major ones at each axis's breaks as wide as a line and
  minor ones between them half as wide, under the layers. **`Coord.grid/2` places the lines**: it
  returns, for the major and the minor breaks of each aesthetic, lines of points in the unit panel,
  which for cartesian coordinates cross the panel from edge to edge, as ggplot2's `guide_grid()`
  runs each line from minus to plus infinity through the coordinate system. A new
  `Giggly.Guide.Grid` gives them the theme's look and ggplot2's order (the background, the minor
  lines of y and then of x, the major lines of y and then of x) and draws the panel's background
  with them, as `guide_grid()` does; rendering puts them first in the panel's cell. A group with no
  lines is drawn as an empty primitive, which draws nothing, rather than left out by a filter
  whose effect nothing could see. *Rejected: the axes carrying minor breaks, and the guide
  drawing a straight line across the panel at each* — the guide would decide that a grid line is
  straight and crosses the panel, which is the coordinate system's call (ggplot2's polar
  `render_bg` draws circles and spokes), the grid would be keyed by an axis's side where ggplot2
  keys it by aesthetic, and the axis would carry minor breaks it never draws. The minor breaks
  come from the scale: `Scale.Transform` gained `minor_breaks`, as R's transformation object
  carries it, and the identity's is a port of `scales::regular_minor_breaks()` asking for two
  intervals per gap (`Scale.MinorBreaks`): one more step past an outermost break the extent
  reaches beyond, then each gap's middle, found as R's `seq()` finds it, the gap's start plus half
  its width, which differs from the two ends' mean in the last bit. `Scale.minor_breaks/3` takes
  the breaks `breaks/2` gave on the same extent, as ggplot2's view scale hands its breaks to
  `get_breaks_minor()`, keeps the minor breaks inside the extent, its ends included, as R's
  `discard()` does, and leaves out the breaks themselves; a discrete scale has none. The
  assembly hands each axis's minor breaks to the coordinate system with its extent and breaks.
  *Rejected: the breaks left among the minor breaks, for the guide to take out* (ggplot2's
  `guide_grid()` does so with `setdiff()`) — nothing here reads them together. Every example of
  the minor breaks was checked against R (ggplot2 4.0.3, scales 1.4.0): ggplot2's own minor grid
  breaks for the golden's axes, mtcars's `wt`, a single value of 1e16 and a discrete axis, and
  `regular_minor_breaks()` on inputs chosen so each clause decides one. With them the golden matches ggplot2's drawing of the same
  plot in every element. No boundary changed. **Clipping is a step of its own, after this
  increment** (Steve, as proposed): ggplot2 clips a panel's contents to it in the same function
  that draws its background (`Coord$draw_panel`, from `coord_cartesian(clip = "on")`), and a point
  at an infinite position is drawn today half over the axis, where ggplot2 shows half a circle; but
  clipping is the coordinate system's `clip` option, touches the scene and svglite's clip-path
  markup, and nothing here needs it. *Rejected: a third step of this increment.* It was flagged as
  a separate task. *Deferred to first reader:* a grid that is not rectangular, munched with its
  background (polar coordinates); grid lines styled apart for x and y, or drawn over the layers
  (`panel.ontop`); minor ticks on an axis; the panel's border (`render_fg`, blank in
  `theme_gray()`).

- **The theme is a resolved value that every drawing function takes; the plot's background is
  the first element added to it (2026-10-12, Steve).** A plot records its theme, as it records its
  facet and coordinate system, and `Giggly.Theme` resolves it into the complete theme (ggplot2's
  `complete_theme()`): every element it draws, worked out from `theme_gray()`'s arguments (base
  size 11, black ink on white paper, lines and borders 11/22 mm) as ggplot2's `theme-defaults.R`
  works them out, each length and line width in points and each colour a hex string, so the
  TeX-point and millimetre conversions happen once, in the theme. The assembly carries the theme
  unread; rendering resolves it and hands the complete theme to the guide. The axis look moved
  out of the guide's module attributes into it, and the plot margin out of rendering's. The
  plot's background, a
  white fill with a white 0.5 mm border, is drawn first, in a cell spanning the whole table,
  margin included, as ggplot2's `table_add_background()` adds it: without it the drawing is
  transparent outside the panel, and on a dark page its grey labels vanish. The scene gained
  `Rect` (grid's `rectGrob()` at its default place and size, filling its cell) and cells that span
  ranges of rows and columns, and SVG writes svglite's rectangle markup. svglite's own page
  rectangle is left out with the rest of its preamble, since the plot's background covers it.
  *Rejected: module attributes
  until a theme can be set* (what the guide's rules said) — the look would sit in three drawing
  modules sharing derived values (paper white is the grid lines' colour and the background's, 0.5
  mm the tick's width and the major grid line's, the margin half a line), each copying the
  derivations and conversions, and every drawing function's signature would change when a theme
  arrived. **The name is `:gray`** (Steve): the American spelling the aesthetics' `color` set,
  plotnine's `theme_gray`, and the spelling ggplot2's own documentation lists and its examples
  use, though ggplot2 defines the function as `theme_grey` and makes `theme_gray` the alias.
  *Rejected: `:grey`.* **A golden is
  checked against ggplot2's drawing of the same plot** (Steve): `test/golden/point.R` draws the
  golden's plot with ggplot2 (4.0.3) and vdiffr (1.0.9), which Docker's `r-base` image installs,
  as ggplot2's snapshots are drawn but with no title row, since vdiffr adds `theme_test()` only to
  a plot that sets no theme; its header gives the command and the element-by-element comparison,
  and the suite never runs it. Before this step the golden already matched ggplot2's
  `theme_test()` drawing of its data in every point, tick and label. *Rejected: committing
  ggplot2's drawing with a test that compares the two* — the comparison needs a normaliser that
  grows with each deliberate difference, such as Elixir-style labels, and two stored files that
  must agree; *and the scratchpad alone*, where increment 8's R checks were lost with the session.
  New boundary: `Theme` lists nothing; `Render` and `Guide` gained `Theme`; `Scene` exports
  `Rect`. *Deferred to first reader:* theme values as CSS classes,
  ggity's way (the LiveView layer; only colours could move, since the layout is measured from the
  sizes); the theme's fonts. The panel's background and grid lines are this increment's second
  step (since built, see the entry beginning "The panel's grid lines are placed").

- **An axis is titled by the first layer to map its aesthetic, and the title is drawn by the
  axis's guide (2026-10-12, Steve).** The assembly titles each axis with the name of the column
  the first layer, in the order added, maps the axis's own aesthetic to through its computed
  mapping (`Plot.computed_mapping/2`): ggplot2's `setup_plot_labels()`, where a later layer
  never replaces an earlier one's label, read as `resolve_label()` reads it, by the scale's first
  aesthetic, so `xmin` alone titles nothing. An axis no layer maps has the title `:none` and
  draws none. The titles are `%Assembly{}`'s `guide_titles`, not `labels`,
  which here means a break's text. `Coord.axes/2` now says which aesthetic each side's axis shows,
  so which title goes on which side is the coordinate system's call. `Guide.Axis.title/3` draws
  each title in a cell of its own beyond its axis, as ggplot2's layout adds its `xlab-b` row and
  `ylab-l` column: 11-point black text, a 2.75-TeX-point gap toward the axis, centred on the
  panel's side, hanging from the cell's far edge, the y title
  turned 90 degrees. `Scene.Text` gained an angle, and SVG writes turned text and leaves out a
  black fill as svglite does. With the titles, the golden matches ggplot2's `expand-range`
  snapshot element for element in every x position and in everything below the panel; the rest
  differs only by the plot title row vdiffr adds above the panel. *Rejected: deferring titles
  past the background, with `labs/2`* (proposed) — Steve chose them now and `labs/2` later.
  *Rejected: the plot's mapping alone* — a layer that remaps x would be titled by the plot's
  column; *and the last layer winning* — ggplot2 has no basis for it, and adding a layer would
  retitle the plot. *Rejected: titles drawn by rendering* — it computes no positions; *or by a
  domain of their own* — ggplot2's `guide_axis(title = …)` sets an axis's title, and legends draw
  their own. *Deferred to first reader:* the search past a layer that leaves the axis unmapped (a
  geom such as `geom_hline()`).

- **Axes are drawn from breaks the scale computes and the coordinate system places, by a guide
  that measures its labels with the glyph table ggplot2's own snapshots were measured with
  (2026-10-12, Steve).** `Scale.breaks(scale, extent)` returns an axis's breaks as `{position,
  label}` pairs on the extent it is handed. A continuous scale's are its transformation's (the
  `Scale.Transform` behaviour gained `breaks` and `format`, as R's transformation object carries
  them), kept inside the extent as ggplot2's view scale censors them; an untrained scale has none,
  and an extent of zero width has its low end alone, as `ScaleContinuous$get_breaks` returns. A
  discrete scale's are its levels at 1..n. The identity's breaks are extended Wilkinson, ported
  from `labeling::extended()` 0.4.3 with five breaks wanted (`scales::breaks_extended()`), its
  degenerate cases included: a range under 100 epsilons wide, or wider than the square root of the
  largest float, spaced evenly from end to end, and a best sequence whose span is rounding error
  beside its size reduced to its first break, as R's `seq()` reduces it. The port reproduces the
  break sets in ggplot2's snapshots (0–10, 0–50, and mtcars's wt and mpg) and agreed with a second,
  independent port on 409 random ranges. The assembly hands each axis's extent and breaks to the
  coordinate system, whose new `axes/2` places them by the rescale the data goes through, keyed
  by the side of the panel each axis is drawn on (cartesian: x at the bottom, y on the left). A new
  `Giggly.Guide`, ggplot2's `guide_axis()`, draws each side's ticks and labels in `theme_grey()`'s
  look, and measures how far the axis reaches;
  a new `Giggly.Font` measures text. The scene gained sizes in points, its weighted size became
  `:rest`, what the fixed sizes leave, and it gained `Text` and `Polylines` primitives; SVG lays the table out and writes svglite's markup; rendering puts
  the axes and ggplot2's plot margin around the panel. Two findings made the layout exact: vdiffr,
  which writes ggplot2's SVG snapshots, measures text from Liberation Sans's glyph table (its
  `glyph_dims.h`: advances summed with no kerning, a line's height the ascent of "M", to which
  ggplot2's `titleGrob` adds the deepest descent of "gjpqyQ"); and ggplot2's theme lengths are TeX
  points (grid's `"pt"`, 1/72.27 inch) while font sizes and svglite's unit are 1/72 inch. With both,
  the axes of `coord-cartesian/expand-range.svg` are reproduced to the hundredth of a point
  measured from the panel's edges. New boundaries: `Font` lists nothing; `Guide` lists `Coord`,
  `Font` and `Scene`; `Render` gained `Guide`; `Scene` exports `Polylines` and `Text`.
  *Rejected: the coordinate system listing `Scale` and building view scales itself* (ggplot2's
  shape, `view_scales_from_scale()` in `coord-cartesian-.R`) — it widens `Coord` to save the
  assembly one call per axis, and the assembly already hands it what it needs; revisit when `xlim`
  makes the extent the coordinate system's to decide. *Rejected: positions and labels as two
  lists* (ggplot2's `get_breaks()` and `get_labels()`) — they must agree element by element, so
  they travel as one; *and a `%Scale.View{}` struct* — matching another domain's struct is a
  dependency, so `Coord` would list `Scale` after all. **Number labels are written the Elixir way:**
  `inspect`'s plain decimals, each break rounded to 15 significant digits first, as many decimals on
  every label of an axis as the most precise needs (`0.0 2.5 5.0`), none when every break is whole
  (`2 3 4`), negative zero as `0`, never scientific, no thousands separators. *Rejected: R's
  `format()`* (proposed: `formatReal()` and `scientific()` in R's `format.c`, seven significant
  digits, scientific when narrower, so `1e+05` and `0e+00`, which is ggplot2's default and what
  its snapshots show) — Steve: people expect numbers written as Elixir writes them. *Rejected:
  Elixir's output as it stands* — `Float.to_string/1` writes 25000.0 as `2.5e4`, both it and
  `inspect` show float noise (`0.30000000000000004`) and `2.0`, and `inspect` switches to
  scientific below 0.0001, which would mix forms on one axis. *Rejected: the scales package's
  `label_number()`* — not ggplot2's default either. **A discrete level is labelled with
  `to_string/1`, and a missing one `NA`** (Steve, over my proposal of `nil`, Elixir's spelling
  and consistent with `true` and `false`, which keep Elixir's spelling); *rejected: an empty
  label*, which reads as a missing label rather than a missing value. **`Giggly.Font` is a plain
  module with no behaviour**, which amends Phase 0's "a text-metrics service behind an interface":
  its functions are the only route to a text's size, and every family is measured alike; a
  behaviour arrives, if at all, with a second measurer (the entry beginning "A font family is a
  name"). It holds the
  whole of vdiffr's Liberation Sans table, 2,242 glyphs, so Greek and Cyrillic are measured right,
  and a character the font lacks takes vdiffr's own fallback width. The table is
  `priv/fonts/liberation_sans.txt`, copied from vdiffr with its provenance in a header and read at
  compile time behind the tree's one `CorePurity` waiver. *Rejected: a flat estimate (0.6 em per
  character)* — it reproduces nothing; *ASCII and Latin-1 only* — with `textLength` a label
  measured at the fallback is drawn visibly stretched; *a map literal in the module* — about
  9,000 literal mutants surviving every mutation run; *a heredoc in the module* (proposed, needing
  no waiver) — Steve chose a file: the table is generated data, regenerated and diffed apart from
  the code; *reading a font file when a plot is drawn* — IO. **Axes are drawn by a domain of their
  own**, which places breaks through the coordinate system as a geom places rows. *Rejected: the
  coordinate system drawing them* (where ggplot2's `render_axis_h/v` sit, though they only
  delegate to the guide) — `Coord` would list `Scene` and `Font` and become a drawing domain;
  *rendering drawing them* — rendering computes no positions; *the name `Axis`* — it would be
  renamed when legends join, and ggplot2, Wilkinson and plotnine call both guides. **Sizes are
  measured when the scene is built** (ggplot2 measures an axis's grobs while building its table;
  only `"null"` sizes wait for the drawing), and text carries one offset in points to its
  baseline; *rejected: lazy measured sizes resolved by the backend* (grid's `"grobwidth"`), which
  would put a font in every backend, *and grid's mixed units for every position*, more general
  than anything that uses them. The scene's docs say column widths and row heights, not "tracks"
  (Steve did not know the term). The panel's column and row are `:rest`, taking what the fixed
  sizes leave, and exactly one of each is allowed; *rejected: increment 7's `{:null, weight}`
  shared by weight* — every scene has one of each, of weight 1, so review's mutation step found
  the sharing arithmetic unpinnable (`left * weight / total_weight` and its mutants agree), and
  weights return with `facet_wrap`'s panels. **A label is drawn at its measured width** (svglite's
  `textLength`), so the layout and the drawing agree whatever font the browser picks, at the cost
  of squeezed letters in a font of other widths; *rejected: natural letters*, which can overrun
  their space. Its `font-family` is `"Liberation Sans", Arial, Helvetica, sans-serif`; *rejected:
  vdiffr's `sans`*, which is not a CSS generic family. **Axis titles come in this increment, as
  its second step** (Steve, over my proposal to defer them past the background), with `labs/2`
  later; the two steps are reviewed and committed apart. The plot margin arrived with the axes,
  since without it the leftmost label touches the drawing's edge. *Deferred to first reader:* the
  transformation's inverse and domain (the first transformation that is not the identity); axes
  above or to the right, and secondary axes; angled, dodged or thinned labels; a scale's `breaks:`, `labels:` and
  `n.breaks:` (§7's "absent" question); more fonts, bold and italic; cell names and z-order beyond
  list order; a polyline's fill (the first with area); and the plot's title.

- **The coordinate system arrives with drawing: a plot is drawn to SVG through a scene
  (2026-10-12, Steve).** `Giggly.to_svg/2` assembles a plot, renders it into a scene
  (`Giggly.Render`, ggplot2's rendering stage) and has `Giggly.SVG` draw the scene. The plot's
  coordinate system is cartesian unless it says otherwise, as ggplot2's `ggplot()` defaults to.
  The assembly builds each
  panel's params last, from `Scale.dimension/1`: the axis's extent widened by ggplot2's default
  expansion (5% of a continuous range at each end, 0.6 around discrete positions 1 to n, a range
  of zero width by R's `zero_range()` widened as if its width were 1, an empty axis 0 to 1 first).
  `Coord.transform/3` rescales every x-family and y-family column into the panel by those extents
  and puts an infinite position at the edge (`squish_infinite()`). `Geom.Point` calls it, as
  ggplot2's `draw_panel()` calls `coord$transform()`, drops a row missing its x or y, and draws
  ggplot2's default point (black, size 1.5 mm, border 0.5 mm) as a circle of radius 1.95 points
  with a 0.71-point outline: the figures in ggplot2's own visual-test snapshots, reproduced from
  `.pt`, `.stroke` and R's 0.375 radius for shape 19. The scene is a table of weighted tracks
  holding one cell, the panel, placed at the layout's new `row` and `column` (ggplot2's `ROW` and
  `COL`); its primitives sit in cell units and are sized in points. SVG follows svglite (the point
  as its unit, two decimals, its circle markup) at vdiffr's 720 by 576 points, so its output can
  be set beside ggplot2's snapshots; the first golden test compares a whole document. New
  boundaries: `Coord`, `Geom`, `Scene`, `SVG` and `Render`, and `Assembly` gained `Coord`
  (`mix boundary.spec` prints the graph). *Rejected: the coordinate system alone, its params
  stored for drawing to read later* (the plan's increment 7) — the params would be read by nothing
  and `transform/3` called
  only by tests. *Rejected: a public panel-params inspector as its reader* — ggplot2 has none (its
  params are opaque by contract, reachable only through `ggplot_build()`'s object), and §4 keeps
  the assembled value internal. *Rejected: `Coord` handed the family rule, or each geom naming
  its x and y columns, rather than listing `Aesthetics`* — handing the rule in moves the listing to
  `Geom`, a peer domain, and naming columns makes every geom repeat the family lists. *Rejected:
  the
  expansion in the coordinate system* — ggplot2 lets a scale's own `expand` override the default,
  and `expand_range()` is R's `scales`; the coordinate system holds the widened extents.
  *Rejected: the assembly writing unit-panel positions into the tables* — whether to munch before
  transforming is the geom's call, and a path in polar coordinates could not curve. *Rejected:
  point defaults in a theme now* — ggplot2 4 takes them from the theme's `element_geom`, but the
  theme's next reader is the panel background; they sit in `Geom.Point`, where ggplot2 kept them
  before 4.0. *Rejected names:* `Display` for the stage (proposed, after Wilkinson's third stage;
  Steve preferred ggplot2's "render"), and `SVG.render/3` for the backend's function (the verb
  would name two steps; `draw/3`, after grid's `grid.draw()`). *Deferred to first reader:* every
  coordinate option (`xlim`, `expand`, `reverse`, `ratio`, `clip`) and a scale's own `expand`;
  cell names; and how a dropped row is reported, since ggplot2 warns and a pure pipeline cannot.

- **A layer records its stat and position, and a continuous scale its transformation, the
  identity included (2026-10-12, Steve).** `geom_point/3` records `%Stat.Identity{}` and
  `%Position.Identity{}` on its layer and `Scale.new(:continuous)` records `transform: :identity`,
  as ggplot2's `geom_point()` defaults `stat = "identity"` and `position = "identity"` and its
  continuous scales `transform = "identity"`. A discrete scale records none: ggplot2's has none.
  The assembly runs the stages where the fixed order puts them: each axis's scale is added after
  grouping, its columns are put through `Scale.transform/2`, trained on and mapped, and then each
  layer's stat (`Giggly.Stat`) and position (`Giggly.Position`) run. A transformation is a module
  implementing `Giggly.Scale.Transform`, resolved from its name; a stat and a position are structs
  of their kinds (the entry beginning "Each facet, coordinate system, geom, stat and position is a
  struct"). Modules whose last segment repeats across namespaces are written through their
  namespace (`alias Giggly.Stat`, then `Stat.Identity`), never aliased to the tail: a second
  `alias` with the same tail replaces the first without a warning (tried). That settles §7's
  module-name question. *Rejected: the identity as the absence of a stat, a position or a
  transformation* (proposed for this increment) — an absent stat cannot be told from a forgotten
  one, while a recorded identity says the choice was made and a test can assert it; the cost is
  stage calls that the mutation step reports as equivalent survivors, since removing an identity
  changes no output. *Rejected: `as:` aliases* — credo's `AliasAs` check is enabled; *and renamed
  modules (`StatIdentity`)* — ggplot2 prefixes because an R package has one flat namespace, and
  module nesting does that job here. *Rejected: `position_jitter` as the stages' first non-identity
  member now* — it would bring keyword options, NimbleOptions' placement, the "absent" sentinel,
  `resolution()` and a default seed (ggplot2's `seed = NA` draws a fresh one per build, which a
  pure pipeline cannot) into a Phase 1 scatter plot; it belongs with stack and dodge. *Deferred to
  first reader:* a stat's or position's further arguments; and a transformation's inverse and
  domain.

- **Position scales are chosen by column type, trained after grouping and mapped to data-space
  positions; what has no reader yet waits (2026-10-12, Steve).** `Giggly.Scale` (boundary lists
  nothing) takes plain values: `kind/1` gives `:continuous` for `:integer`, `:float` and `:null`,
  `:discrete` for `:string`, `:boolean` and `:atom`, and `:none` for dates, times and `:term`;
  training follows R's `scales` (`train_continuous`: the finite numbers' range; `discrete_range`:
  sorted distinct values, missing last — read in its source); mapping leaves a continuous value as
  it is and puts a discrete one at its level's position from 1. The assembly trains one scale per
  axis over every layer's x-family or y-family columns, reading the scale id from the layout table
  (`Facet.layout/0`: `panel`, `scale_x`, `scale_y`), and maps those columns; its output became
  `%Giggly.Assembly{}`. `Giggly.panel_scales(plot, panel)` is ggplot2's `get_panel_scales()`,
  indexed by panel id. The assembly refuses, when the plot is run, an axis column no scale can
  place and one whose kind disagrees with the axis's first column, naming the layer by index, the
  aesthetic, the column and its type — where ggplot2 refuses too. `Group.add/2` numbers values by
  an order key the assembly hands it, `Scale.level_key/1`, so group ids and axis positions come
  from one rule while grouping names nothing about scales. *Rejected: refusing at the geom call,
  with `Plot` asking `Scale.kind/1`* (first built, then reversed by Steve) — the description would
  list `Scale`, and a list grants a whole boundary, so the plot could start running scales; what
  the plot checks is what it knows, names and which aesthetics a geom takes. *Rejected: `Group`
  listing `Scale`* — grouping would depend on scales to borrow one comparison. *Rejected: a shared
  `Ordering` module that both list* — extracting `Scale` would carry a module that non-extracted
  domains depend on. *Rejected: a copy of the level order in `Group`* — two copies of one rule, to
  be kept in step by a test. Handing the order in costs one argument with one value today, and is
  the shape configurable level order needs: ggplot2's stacks follow factor levels, not scale
  limits, and here the assembly can hand grouping the configured order. *Rejected: routing rows
  to several scales now* — with one panel nothing could exercise it; the assembly matches exactly
  one scale id per axis and fails loudly when free scales bring more. *Deferred to first reader or
  need:* user scale functions and their options (so NimbleOptions and the "absent" sentinel).

- **The facet assigns panels first; the layout table arrives with scale training (2026-10-12,
  Steve).** The facet runs first in the assembly and gives every row of each layer's table its
  panel, as ggplot2's `map_data()` does (`panel = 1` without a facet), which evaluation carries
  into every layer frame, ordered as ggplot2 orders them: aesthetics, `panel`, `group`. Checked
  against `R/facet-null.R`, `R/facet-.R` (`layout_null()`) and `R/layout.R`. *Rejected: the
  layout table now* (the Phase 1 plan's draft)
  — its `scale_x`/`scale_y` columns are first read by scale training (increment 5), which routes
  each panel's rows to a scale through them, and its `row`/`col` by the scene (increment 8);
  built now, nothing would read it. *Rejected: a mutable
  go-between like ggplot2's `Layout` object* — it holds the facet, the coord, the panel scales and
  the panel params and is trained by side effect; here the assembly passes values between stages.
  *Rejected: folding this into increment 5* — small verifiable increments, and this one proves
  the stage order's first slot on its own.

- **A plot is a value built by `Giggly.Plot` and run by the functions in `Giggly`; the stages run
  in `Giggly.Assembly` (2026-10-12, Steve).** `Plot` holds the value and the vocabulary that
  builds it, and runs nothing. The root module holds the run functions, each taking a finished
  plot: `layer_data(plot, index)` now (ggplot2's `get_layer_data()`, layers counted from 0, the
  first by default), `to_svg` and further inspection later. This is ggplot2's split — `ggplot()`
  and `+` build a plot; `print`, `ggsave()`, `ggplotGrob()` and `get_layer_data()` take one and run
  it (`R/plot.R`, `R/save.R`, `R/plot-render.R`, `R/plot-build.R`) — and Ecto's (`Ecto.Query`,
  then `Repo.all/1`). `Assembly` is named for the middle of Wilkinson's three stages of making a
  graphic (specification, assembly, display). There is no public intermediate value: the
  assembled value and the scene are internal, and the assembly returns a list of layer frames
  until a second field arrives, when it becomes a struct named for what it holds. Arrows run root
  → `Assembly` → `Plot`. *Rejected: `build/1`, `render/1` and `to_svg/1` on the root, with public
  `%Built{}` and `%Scene{}`* (the 2026-10-11 shape) — `Build` and `Built` name a step and the state
  after it, not a thing, and ggplot2's users inspect through `get_layer_data()`, not the built
  object. *Rejected: a plot that runs itself (`Plot.to_svg/1`)* — `Plot` and the assembly would
  depend on each other unless the value moved into a module of its own (Req's `Req.Request`
  shape), which would exist only to break that cycle. *Rejected: the assembly reading a plot's
  fields without naming its struct* — boundary does not see field access, so the dependency would
  be real and hidden. *Rejected names:* `Pipeline` (says nothing about plots), `Compiler`
  (Vega-Lite's word, but reads as Elixir's compiler in a stack trace), `Evaluator` (one part of
  the job), `Dataflow` (Vega's runtime is a graph; ours is a sequence), `Stages` (plural names are
  contexts here), `Layout` (increment 4's). *Rejected: counting layers from 1* (R's) — Elixir
  counts from 0, and the default keeps `layer_data(plot)` reading as ggplot2's `layer_data(p)`.

- **Every boundary is strict, and each domain's `deps:` is its contract (2026-10-12, Steve).**
  `boundary: [default: [type: :strict]]` in `mix.exs`, pinned by `boundary_declarations_test.exs`
  with a second test refusing any `type: :relaxed`. Each domain is a sub-boundary carved when its
  first module lands, its `deps:` growing with its needs (`mix boundary.spec` prints the graph).
  `Giggly` exports `Plot`. The test helpers
  became `GigglyTest.TestEnv` and `GigglyTest.Eventually`, top-level by name, each listing
  `ExUnit`. The `CorePurity` check now reads all of `lib/`; scoped to a `core/` that did not
  exist, it had checked nothing. Found by compiling a throwaway copy, and recorded in
  `.claude/rules/dependencies.md`: a strict parent does not check an outside-library call from a
  sub-boundary that is not strict itself, a sub-boundary may list an outside library only when
  its parent does, and boundary sees calls and struct use but not typespecs or field access.
  *Rejected: a `Giggly.Core` namespace* (CLAUDE.md's installed shape) — nearly every module here is
  pure, so `Core` would hold the whole library and renaming everything would separate nothing.
  *Rejected: `type: :strict` on each declaration* — a new domain that forgot it would be relaxed
  in silence; the default fails safe. *Rejected: strict on the top-level boundary only* — it does
  not reach a sub-boundary's calls. *Rejected: `ExUnit` listed on
  `Giggly` for the test helpers* — the library could then call it; *or the helpers lifted with
  `top_level?:`* — two exemptions where naming them outside `Giggly` needs none.

- **Column types belong to the frame: `DataFrame.dtypes/1` (2026-10-12, Steve).** Every column has
  one type, worked out when it enters a frame by Explorer's rules for `Series.from_list/2` (read in
  its 0.13.0 source): one kind of value plus `nil`; integers with floats are `:float`, the integers
  stored as floats, as Explorer casts them (2026-10-18, Steve: so `4` and `4.0` make one facet
  panel, group and level, as in R); `:nan`, `:infinity` and `:neg_infinity` are floats; all-`nil` or
  empty is `:null`; binaries are `:string`; `Date`, `Time`, `NaiveDateTime` and `DateTime` have
  their own types. Lists adds `:atom` and `:term` (pandas' and Polars' `object`), and stores each
  column as `{dtype, values}`. A column mixing two types is refused, by `from_table/1` and beneath
  it alike. What a type means to a plot is the plot's: `Giggly.Group` reads `:string`, `:boolean`
  and `:atom` as discrete. *Rejected: deciding discreteness from the values in plotting code* (first
  proposed for this increment) — what a column holds is the frame's to validate and report, and an
  engine has the types natively. *Rejected: R's coercion, where numbers mixed with strings make a
  character column* — Elixir has none, a silently categorical axis hides a messy column, and
  Explorer's `DataFrame.new` refuses the same input. *Rejected: working types out on demand* — each
  reader rescans, and a mixed column surfaces wherever it is first read. *Rejected: refusing values
  with no named type* — an unused JSON or numeric column in a database result would refuse the whole
  table. *Rejected: Explorer's widths (`{:s, 64}`)* — a list holds unbounded integers and has no
  width to report.

- **Group ids follow ggplot2's `add_group()` (2026-10-12, Steve).** Checked against
  `R/grouping.R` and `id()`/`id_var()` in `R/compat-plyr.R`. A mapped `group` is renumbered 1..k
  over its sorted values and nothing else counts; otherwise the combinations of the discrete
  columns that occur are numbered 1..k, sorted column by column; with no discrete column every row
  is `-1`. Values sort with `nil` last (R's `na.last`) and otherwise in Erlang term order. Evaluated
  columns are the layer's own aesthetics, then those it takes from the plot, as ggplot2's
  `defaults(layer$mapping, plot$mapping)` lays them (2026-10-16, Steve), each mapping's `x` and `y`
  first, as `aes()` takes them, then the rest in aesthetic-name order, and the key follows them, so
  a discrete alpha mapped with `x` groups within each `x`, and `geom_bar(aes(fill = drv))` over
  `aes(class)` by drive train first, as in ggplot2. *Rejected: `x` and `y` first whichever mapping
  gives them* — the reference page's bars were then numbered, and drawn, class first. The
  integer `panel` column needs
  no exclusion; ggplot2 excludes `PANEL` only because it is a factor. *Rejected: `:none` for "no
  grouping"* — it is a value in the data, not an absent option, and the column must stay integers:
  ggplot2 stacks in `-group` order. *Rejected: `1` for "no grouping"* — `-1` keeps it
  distinguishable from a grouping that found one group, which `stat_boxplot`'s "did you forget
  `group`?" warning reads. *Rejected: locale collation for strings* (R's) — the pipeline reads no
  config, and bytes are deterministic, so `"B"` sorts before `"a"`. *Rejected: the order `aes()`
  was written* (ggplot2's key order) — a map has none, and the two differ only when two
  non-position discrete aesthetics vary within one stack. *Rejected: numbering as a frame
  operation* (a dense rank) — which columns count, `-1` and `nil` last are plotting policy, and the
  rank alone is what an engine backend would add, which is deferred.

- **The table is read when the plot is created, and each call checks the mapping it is given
  (2026-10-12, Steve).** `Giggly.Plot.new/2` reads the `Table.Reader` into a frame, and a layer
  function its `data:` option's; each geom function resolves its mapping against the table its
  layer draws, raising `ArgumentError` that names the aesthetic, the reference as written and the
  table's columns, and checks there the columns it takes from the plot's mapping, which `new/2`
  leaves to the layers (the entry beginning "A column the plot names"). ggplot2 converts its data
  at construction too (`fortify(data)` in `ggplot.default`, `R/plot.R`, and again in `layer()`);
  only expression evaluation waits for the build.
  *Rejected: reading at build start* — a misspelt column surfaced at
  render, its stack trace pointing at the wrong line, and the build held a `Table.Reader` rather
  than a checked frame. *Rejected: "did you mean"* — the list of columns already puts the right
  spelling beside the wrong one, and a similarity threshold is one more thing to tune and test.

- **The assembly exists from its first stage and gains one stage per increment (2026-10-12,
  Steve).** It began with aesthetic evaluation and `Group.add/1`; each later increment inserts its
  stage where the order puts it, and `%Giggly.Assembly{}` gains a field with the stage that fills
  it.
  *Rejected: wiring the whole build at once, at the end of Phase 1* (the Phase 1 plan's draft) —
  every stage function would have had only test callers until then.

- **Points accept only what Phase 1 can draw (2026-10-12, Steve).** An aesthetic joins a geom
  with the scale that maps it. *Rejected: ggplot2's full list for points now* — a mapped colour
  would be evaluated and grouped and never drawn.

- **CLAUDE.md holds only what applies to a library, and each area's rules file earns one
  status-map line (2026-10-11).** Tack's library profile wrote a CLAUDE.md for an application, and
  its line budget was spent after the first area's line. The rules that did not apply were dropped
  and the gate's per-step reasoning moved to `dependencies.md`, under the same budget. *Rejected:
  raising the budget a line per area* — the cap exists to keep CLAUDE.md small. *Rejected: fewer,
  larger rules files* — each would load whenever any of its areas is read. *Rejected: one
  status-map line per pipeline tier naming several rules files* — workable, but unnecessary once
  the inapplicable text was gone.

- **Removing a boundary declaration is a widening, and the waiver gate denies it (2026-10-11,
  Steve).** The hook counts `use Boundary` declarations outside docstrings and denies an edit that
  lowers the count; the commit check does the same, and flags a declaring file deleted while
  `.ex` files remain under its namespace directory. *Rejected: a test listing the modules that
  must declare a boundary* — it would protect Giggly only, and keep a second list in step with the
  declarations themselves. *Rejected: relying on the permission score* — `exports: []` scores 0,
  the same as no declaration, so deleting `Giggly.DataFrame`'s declaration scored 0 → 0 and passed.
  *Rejected: flagging every deleted declaring file* — deleting an area outright would need an
  approval for a change that opens nothing.

- **Mutation testing runs with muex, over the changed code; survivors are triaged, not scored
  (2026-10-11, Steve).** The `mutation-testing` skill runs the mutants muex builds with the flags
  it gives over the changed `lib/` files, and its report says of each
  survivor whether it is a missing test, unreachable or
  redundant code, an equivalent mutant, or the wording of a message whose datum the tests assert —
  and why. *Rejected: hand-picked mutants* — chosen by
  looking at the tests already written, they never mutated `DataFrame.pull/2`'s guard, the one
  behaviour with no test; and a scripted loop reused a previous mutant's build. *Rejected: a `mix
  quality` step or a `--fail-at` score threshold* — two small files take minutes, and equivalent
  mutants count as survivors, so the score is noise while the survivor list is the signal.
  *Rejected: muex's defaults* — its optimizer reported 100% over five mutants where the full run
  had a real survivor, and its filter skips any module declaring several callbacks.
  *Rejected: muzak and exavier* — no release since 2022 and 2020. *Rejected: dropping the
  `literal` and `function_call` mutators* (2026-10-12, Steve) — replacing a value and removing or
  rearranging a call are basic mutation operators, and their survivors are judged one by one like
  any other. On the data frame most of theirs were error-message wording, set aside only where the
  tests assert the message's datum; a call renamed to one that does not exist is killed whenever a
  test runs its line, so one that survives marks a line no test runs.

- **Callers reach a frame only through `Giggly.DataFrame`, which dispatches on the frame's
  struct (2026-10-11, Steve).** Each operation is a `@callback` plus a function in
  `Giggly.DataFrame` that calls the frame's own module, the backend pattern Explorer and Nx use.
  The frame is the implementation's struct with no wrapper, and `Giggly.DataFrame` is its own
  boundary exporting only its root, so a caller naming `Lists` fails the build. Operations arrive
  with their first caller, so the first set is only what aesthetic evaluation needs; reading one
  column is `pull/2`, after dplyr and Explorer. *Rejected: a protocol* — it cannot construct a
  frame, and building one is half the job. *Rejected: a wrapper struct around the
  implementation's* (Explorer's shape) — nothing outside matches on the frame, so one can come with
  a second backend that needs it. *Rejected: the facade rule as a rules-file sentence only* — the
  boundary makes breaking it a build failure. *Rejected: `fetch!/2`* — vague about one column or
  several; *`column/2`* — returns a column object, not values, in pyarrow and Arquero.
  *Rejected: designing split/recombine and the `panel`/`group` columns with the frame* (the Phase 1
  plan's draft) — nothing splits until scales train by scale id, and that caller decides the
  contract (piece order, whether row order is restored, pieces whose columns differ); the reserved
  columns belong to the facet and `add_group`, and a frame that knew about panels would be the
  facet leaking into the currency.

- **User column names become strings when a table is read; every column the pipeline writes is an
  atom (2026-10-11, Steve).** `from_table/1` converts names with `to_string/1` and refuses two that
  collide (`:wt` and `"wt"`). So a user column called `"panel"`, `"group"` or `"x"` cannot collide
  with the pipeline's `:panel`, `:group` or `:x`; a mapping reference resolves with `to_string/1`
  and never mints an atom; and "after evaluation, user column names do not exist" holds by type
  rather than by a test. Reading is a thin adapter over the pure `new/1` and the only caller of
  `table`, so it can sit outside a strict core. *Rejected: names as the source gives them* — a list
  of maps with a `:panel` key collides with the reserved column, and every reference has to be
  looked up as both an atom and a string. *Rejected: ggplot2's upper-case `PANEL`* — it still
  collides with a user column of that name. *Rejected: converting user names to atoms* — that
  creates atoms from caller input.

- **Options are validated with NimbleOptions at every public function (2026-10-11, Steve).** A
  schema per function, typed errors on an unknown or ill-typed option, option docs generated into
  ExDoc. Validation lives at the API boundary; the pure functions beneath are assertive and take
  validated data. *Rejected: `struct/2` with the options keyword* — ggity's approach; it silently
  drops unknown keys, so `colour:`, a typo, or `scale_x_continuous(limits: …)` did nothing and
  said nothing. *Rejected: hand-rolled guards only* — no new dependency, but option documentation
  and "unknown option" errors then have to be written by hand per function, and the allowlist
  check is the part that gets skipped.

- **The public pipe API lives in `Giggly.Plot`, ggity-style (2026-10-11, Steve).**
  `Plot.new(data, %{x: :wt, y: :mpg}) |> Plot.geom_point(%{color: :cyl}, alpha: 0.4) |>
  Plot.labs(…)`; a map argument is a mapping, a keyword list is fixed options, both may be given.
  The `Giggly` root holds `build/1`, `render/1`, `to_svg/1` and the boundary declaration (since
  amended: the root holds the run functions, and build and render are internal — see the entry
  beginning "A plot is a value built by").
  *Rejected: every function on the `Giggly` root* — reads closest to `ggplot() + geom_point()`,
  but one module then carries every geom, scale and theme function. *Rejected: an importable
  bare-function DSL* — closest to R visually, unusual in Elixir, collides with user names.

- **Three values with one function between each (2026-10-11, Steve):** `%Giggly.Plot{}` → the
  assembly → `%Giggly.Assembly{}` → rendering → `%Giggly.Scene{}` → a backend → iodata; only the
  plot is public. The assembled value carries per-layer frames with resolved params, the layout
  table, trained scales and panel params; nothing in it knows about SVG. *Rejected: a single pass
  from spec to markup* — ggity's `Plot.plot/1`, where aesthetic mapping, pixel arithmetic and SVG
  emission happened in
  one loop per row inside each geom, so there was no point at which a layout could be measured or
  a panel inserted.

- **Scales are three values, never one mutated object (2026-10-11, Steve).** The *spec*
  (`scale_x_log10(…)`), the *trained scale* (spec plus the range folded over the layer frames — a
  provisional one feeds stats and positions, a final one is retrained after positions), and the
  per-panel *view scale* (expanded range, breaks, labels) that the coord freezes. A position scale
  stops at "trained limits in transformed space"; the coord is the only route to the unit panel,
  and nothing under `Giggly.Scale` knows a pixel exists. Expansion happens in transformed space.
  *Rejected: scales that map to pixels* — ggity baked `width: 200` into every scale struct, which
  is the single decision that made facets (panels of different sizes) and coords (swapping which
  scale drives which screen axis) unreachable. *Rejected: one mutable scale with `clone/0` and
  `reset/0`* — ggplot2's shape, which works only because every `+` and every build clones, and
  whose getters with side effects make call order matter.

- **The build order is fixed up front, and each adjacent pair is a semantic we chose
  (2026-10-11, Steve).** The order itself is in `.claude/rules/build.md`, moved there when the build
  got code. Transform-before-stat means a smoother on a log axis fits in log space; train-before-stat
  means bin edges come from the panel range and agree across groups; position-before-retrain means
  stacked totals reach the axis; fixed values last means they bypass scales. *Rejected: ggity's
  order* — positions ran in pixel space after scaling, so the scale could not see stacked totals
  and the stat had to run a second time at `geom_bar` call time to stash a maximum in a side
  channel.

- **The layer-data currency is `Giggly.DataFrame`, a behaviour with a relational, engine-neutral
  operation set, and `Giggly.DataFrame.Lists` is the only implementation in core (2026-10-11,
  Steve).** Columns keyed by aesthetic atom; the operations are select, mutate from a closed
  expression catalog, filter, group-by-aggregate, sort, distinct and a lookup join — the set that
  Polars, DuckDB and SQL all implement. Transforms and built-in stats are named operations so a
  backend could run them in its engine; anything user-defined (a custom transform or stat)
  materializes to lists. Engine backends are deferred (§7). Measured 2026-10-11, pure Elixir on
  one core: the pipeline's dozen column passes run in ~50 ms at 10⁵ rows and ~0.5 s at 10⁶, with
  per-group splitting (0.5 s) and sorting for quantiles (0.7 s) the costly steps at 10⁶ — and SVG
  cannot carry more than ~10⁵ marks anyway, so "large data" means large input into a summarizing
  stat, which is where an engine backend would pay. *Rejected: Explorer as the currency* — ggity's
  choice; a ~42 MB precompiled NIF per target for every user, a Rust toolchain for source builds,
  no list columns (ggity serialized boxplot outliers with `term_to_binary` into a binary column),
  and a single-maintainer upstream. *Rejected: lists with no behaviour behind them* — cheapest
  today, but gives up stats on large inputs permanently. *Rejected: Nx* — vectorized math without
  a group-by shape, and its fast backend is a larger NIF than Explorer's. *Rejected name:
  `Giggly.Frame`* (Phase 0's proposal, amended at ratification).

- **Input is anything implementing `Table.Reader`, read once, by `Plot.new/2` (2026-10-11,
  Steve), and a layer's own by its function's `data:` (2026-10-17).**
  The `table` package is tiny, stable, and implemented by Explorer, Dux, the database drivers and
  plain lists of maps, because Livebook requires it — so it survives whichever dataframe library
  is maintained in three years. Mapping values may be atoms or strings and are resolved against the
  table's column names at the call; after that point user column names do not exist in the
  pipeline. *Rejected: Explorer only* — ggity; couples the library's life to one dependency's.
  *Rejected: per-format adapters* — each one is code the `Table.Reader` implementers already wrote.

- **Two reserved frame columns, `panel` and `group`, integer ids, present from aesthetic
  evaluation onward (2026-10-11, Steve).** `panel` is assigned by the facet against the raw data,
  before aesthetics are evaluated, because facet variables name raw columns that evaluation
  discards. `group` is inferred once, from the discrete-typed aesthetic columns, before any scale
  touches the data — position mapping turns a discrete x into integers, after which it no longer
  looks discrete — and is global across panels so stack and dodge order agree between facets.
  *Rejected: per-geom grouping* — ggity had at least six definitions of "a series" (line by every
  non-positional aesthetic, ribbon by `{alpha, fill}`, bar by x, text alone reading `:group`, and
  the stats a seventh); none could feed a stat or a position. *Rejected: inferring after position
  mapping* — collapses every per-category bar and boxplot into one group.

- **Aesthetics are atoms with ggplot2's names, American spelling canonical, aliases rewritten once
  at the API (2026-10-11, Steve).** `color` is canonical and `colour` is accepted and normalized at
  the boundary so nothing downstream sees both; `linewidth` is line thickness and `size` is point
  size (ggplot2 ≥ 3.4). The x and y position families are ggplot2's lists verbatim (`x xmin xmax
  xend xintercept xmin_final xmax_final xlower xmiddle xupper x0`, and the y mirror with `lower
  middle upper`), kept as data in one module that scales, coords, flip and positions all key off.
  Two keys naming one aesthetic after renaming (`color` and `colour` together) raise.
  *Rejected: British canonical* — ggplot2's internal choice, but ggity's users wrote `color` and the
  Elixir ecosystem does too. *Rejected: `size` for line thickness* — pre-3.4 ggplot2 and ggity;
  conflates point area with stroke width in one scale. *Rejected: no family list* — ggity trained x
  only on `x`, so `xmin`/`xend` annotations never widened the axis. *Rejected: ggplot2's duplicate
  handling* — it warns and keeps one value (`rename_aes`, `R/aes.R`), the silent behavior the
  validation decision exists to prevent. *Rejected: ggplot2's substring rule* (`sub("color",
  "colour", …)` on every name) — in Elixir it means minting atoms from caller input; an explicit
  alias table does the same job for the names that exist. *Rejected: the base-graphics aliases*
  (`col`, `pch`, `cex`, `lty`, `lwd`, `srt`, `adj`, `bg`, `fg`, `min`, `max`) — ggplot2's
  concession to base R, not names ggplot2 users write in `aes()`, and contrary to the
  descriptive-names convention.

## 5. Testing approach

_The tiers (exhaustive at the pure core, thin smoke above it), what runs offline and how, the
fixture builders, and the suite's conventions that `elixir-code-review`'s `test-quality.md`
enforces._

## 6. Milestone log

One line per milestone, newest first: the date, a title (since 2026-10-15, the commit's subject,
so `git log --grep` finds it), the commit, and the §4 entries it settled. The commit message
tells the story (`git show <hash>`). Until 2026-10-15 each milestone also had a full entry here;
`git log -S "<title>" -- notes/design-log.md` finds it in this file's history. The phases are
§1's roadmap.

- 2026-10-25 — Fit loess smooths: method: :loess and span:, each place's quadratic fitted directly
  in plain Elixir, its band at the first trace and the t quantile at fractional degrees of freedom
  (smoothing and densities, step 4); §4: "A loess band takes its first trace", "A loess curve stops
  at its rows", "A loess group whose neighbourhoods cannot hold a quadratic", "A smooth given no
  method", "The t quantile keeps", "Nx is a core dependency"
- 2026-10-25 — Estimate densities: geom_density/3 and stat_density/3, binned through the frame and
  convolved by Nx through Giggly.Tensor (smoothing and densities, step 3); §4: "A density takes
  ggplot2's options"
- 2026-10-25 — Fit linear smooths: geom_smooth/3 and stat_smooth/3 with method: :lm, lm summed
  through the frame and its band's quantile Giggly's own (smoothing and densities, step 2); §4: "A
  linear smooth fits the slope", "A smooth given no method is refused when the plot is run", "The
  t quantile keeps the agreed closed form", "A full-range smooth spans the axis it runs along"
- 2026-10-25 — Draw ribbons and areas: geom_ribbon/3, and geom_area/3 aligning its groups as
  stat_align does and stacking them (smoothing and densities, step 1); §4: "Smoothing and
  densities are Phase 3's twelfth increment", "Nx is a core dependency", "Smoothing and densities
  compute over the rows through the frame", "loess is Giggly's own", "A stat's values reached by
  another route"
- 2026-10-24 — Move Plot's option schemas, NimbleOptions checks and shared defaults into
  Giggly.Plot.Options; §4: "`Plot`'s options live in `Giggly.Plot.Options`"
- 2026-10-24 — Draw the notebook examples the theme and its families unlock, and narrow every
  verdict to what still waits (theme, the notebook sweep); §4: "An example that sets ggplot2's
  active theme", "A verdict names a theme element Giggly lacks"
- 2026-10-24 — Give a theme's texts a font family by name, and every complete theme
  base_family and header_family, each family measured by the built-in table (fonts, the family
  step); §4: "A text's family is the theme's", "A font family is a name"
- 2026-10-24 — Let theme/2 set a text's face, angle, justification and line height, every text
  placed as ggplot2's titleGrob places it (theme, step 7); §4: "Text's face, angle, justification
  and line height are the theme's"
- 2026-10-24 — Run the mutation pass in warm VMs: muex's mutants, each against the whole suite;
  §4: "The mutation pass runs muex's mutants in warm VMs" ("Mutation testing picks each mutant's
  tests by coverage" deleted)
- 2026-10-24 — Move the theme's element tree into Giggly.ElementTree, beside Theme, so an edit to
  Theme no longer recompiles Plot; §4: "The theme's element tree is a boundary of its own", "A
  theme is set element by element" (amended)
- 2026-10-24 — Let theme/2 place the legends on any side or inside the panels, run their keys
  across, and stack them either way (theme, step 6); §4: "Legends go where the theme puts them"
- 2026-10-24 — Fill each layer's defaults from the theme, as ggplot2 4's element_geom gives them
  (theme, step 5); §4: "Each layer's defaults are filled in from the theme", "A plot chooses a
  complete theme" (amended), "The theme is a resolved value" (amended)
- 2026-10-23 — Let a plot choose any of ggplot2's eight complete themes at its base sizes, and
  give theme colours an alpha (theme, step 4); §4: "A plot chooses a complete theme", "The theme
  is Phase 3's eleventh increment" (amended), "A theme is a function" (amended)
- 2026-10-23 — Let theme/2 draw the panel border and axis lines, and set line types, ends,
  panel_ontop and fill: :none (theme, step 3); §4: "The panel's border is never filled"
- 2026-10-23 — Hang an axis's ticks from the panel's edge, so an unlabelled axis of no depth
  draws them (the zero-depth ticks card)
- 2026-10-23 — Let theme/2 remove an element with :none and put the legends nowhere (theme, step
  2); §4: "An element set to `:none` is removed"
- 2026-10-23 — Let theme/2 set the theme's elements, inherited through ggplot2's tree (theme,
  step 1); §4: "The theme is Phase 3's eleventh increment", "A theme is set element by element",
  "The theme is a resolved value" (amended), "A theme is a function" (amended)
- 2026-10-23 — Draw the notebook examples ordering, viridis and log10 by name made drawable
  (ordering, step 7); §4: "A random sample of a table's rows"
- 2026-10-23 — Give the frame's doubles one sort order, Arithmetic.sort_key/1 (seven private
  copies replaced)
- 2026-10-23 — Give the frame's arithmetic R's infinities, and add its sums in the long double;
  §4: "The frame's sums are R's", "The frame's first group-by aggregate" (amended)
- 2026-10-23 — Reorder by name, by R's mean() in an emulated long double (ordering, step 6); §4:
  "The frame's mean is R's `mean()`", "Ordering, viridis and `log10` by name" (amended), "A
  function by name's value" (amended)
- 2026-10-22 — Map log10 by name, computed by the table's frame (ordering, step 5); §4: "A
  mapping names a function only as a shortcut" (amended), "A function by name's value is a
  column, a constant or another function by name"
- 2026-10-22 — Add the viridis scales and txhousing, and colour an ordered factor by viridis
  (ordering, step 4); §4: "Viridis joins the tenth increment" (amended), "`scale_*_viridis_c/2`
  takes no `alpha:`"
- 2026-10-22 — Give diamonds R's levels for cut, color and clarity (ordering, step 3); §4: "A
  table's column carries its levels as a `Giggly.Factor`", "A factor carries R's `ordered` flag"
- 2026-10-22 — Read a table's factor columns, and order facet panels by their levels (ordering,
  step 2); §4: "A table's column carries its levels as a `Giggly.Factor`" (amended)
- 2026-10-22 — Give a factor its levels, and train a discrete scale as R's discrete_range()
  (ordering, step 1); §4: "A discrete scale fed levelled and plain values", "A factor carries R's
  `ordered` flag", "`{:factor, [value], levels: [...]}` gives a factor its levels"
- 2026-10-22 — Sweep the notebooks for histograms, box plots and dodging (distributions, step 7);
  §4: "A value an example computes in base R"
- 2026-10-22 — Draw box plots: Geom.Boxplot and geom_boxplot/3 (distributions, step 6); §4: "A
  weight in the plot's mapping is refused by a box layer", "A box layer dodges by clusters", "A
  box plot's orientation is R's", "A box plot takes R's options" (amended)
- 2026-10-22 — Dodge bars by clusters: position_dodge2 (distributions, step 5); §4: "Dodging by
  clusters computes on lists", "`Plot.position_dodge2/1` arrives", "Dodging by clusters places
  each cluster"
- 2026-10-22 — Give bars R's width and placement: width:, just: and a mapped width; §4: "Bars
  take R's `width:` and `just:`"
- 2026-10-22 — Summarise each group into a box through the frame (distributions, step 4); §4: "A
  box's outliers are a list column", "A box plot takes R's options", "The frame's operations share
  one expression grammar"
- 2026-10-22 — Draw histograms and frequency polygons, and check a layer's orientation
  (distributions, step 3); §4: "A frequency polygon takes no `pad:`", "Binning takes
  `orientation:`"
- 2026-10-21 — Bin a continuous axis into counts, and add infinite weights as R does
  (distributions, step 2); §4: "A stat is handed each panel's axes", "A missing value in a sum is
  R's"
- 2026-10-21 — Choose, weigh and carry counted rows through the frame (distributions, step 1);
  §4: "A stat computes only through frame operations", "The frame's operations share one
  expression grammar"
- 2026-10-20 — Draw the notebook examples sizes, shapes and line types made drawable (size, shape
  and line type, step 7); §4: "A verdict names a text's mapped size", "An example R refuses on
  purpose"
- 2026-10-20 — Dash and widen lines by a mapped column (size, shape and line type, step 6); §4:
  "A line type or width scale takes R's options", "A manual list named by breaks", "A stroke's
  width, a radius, an opacity and a gradient offset"
- 2026-10-20 — Shape points by a mapped column (size, shape and line type, step 5); §4: "A shape
  scale is discrete alone"
- 2026-10-20 — Count the rows at each place, sized by their count (size, shape and line type,
  step 4); §4: "A count layer counts over ggplot2's list", "The frame's first group-by aggregate"
- 2026-10-20 — Size points by a mapped column, and legend keys by their glyphs (size, shape and
  line type, step 3); §4: "A scale's `rescaler` says how it places a value"
- 2026-10-19 — Dash a line and a bar's border in its line type (size, shape and line type, step
  2); §4: "A line type is a name", "An aesthetic a layer takes from the plot"
- 2026-10-19 — Give a point its shape, size, stroke and fill (size, shape and line type, step 1);
  §4: "Size, shape and line type are Phase 3's eighth increment", "A shape is ggplot2's name for
  it", "A line type is a name", "A discrete palette with fewer shapes or line types", "A point's
  shape is worked out in the geom"
- 2026-10-19 — Draw the notebook examples the scale functions made drawable (scale functions,
  step 7b); §4: "A verdict names a date format `Calendar.strftime/3` cannot write"
- 2026-10-19 — Draw a colour of :none beside others as R draws NA (scale functions, step 7a);
  §4: "A colour of `:none` beside others in a column is held as `nil`"
- 2026-10-19 — Let a plot choose its guides (scale functions, step 6); §4: "A guide is chosen by a
  scale's `guide:` and by `guides/2`", "`Plot` lists `Giggly.Guide` to build a legend's struct"
- 2026-10-19 — Give a plot colour, fill and alpha scales (scale functions, step 5); §4: "Colour,
  fill and alpha scales are the scale functions' step 5", "`palette:` takes a list of colours",
  "The hue scale's options are spelled out", "A gradient is one palette of any number of colours"
- 2026-10-19 — Give a plot discrete and date position scales (scale functions, step 4); §4:
  "Discrete and date position scales are the scale functions' step 4", "A discrete axis names its
  values as the column holds them", "`date_breaks:` and `date_minor_breaks:` are a step"
- 2026-10-19 — Give a plot transformed scales: log10, sqrt, reverse and reciprocal (scale
  functions, step 3); §4: "Transformations are log10, sqrt, reverse and reciprocal"
- 2026-10-18 — Write a scale's labels as R's formatters do (scale functions, step 2) (`7486f22`); §4:
  "`Giggly.Format`'s `comma/2`, `percent/2` and `currency/2` take every option", "`labels:`
  takes a list"
- 2026-10-18 — Give a plot continuous position scales (scale functions, step 1) (`1d650df`); §4:
  "Scale functions are Phase 3's seventh increment", "A scale function records the untrained
  scale", "`labels:` takes a list", "\"Absent\" in a public option"
- 2026-10-18 — Describe Giggly on its own terms in the API docs (`d344408`); §4: "API docs
  describe Giggly on its own terms"
- 2026-10-18 — Draw expressions in the notebooks (expressions, step 4) (`a6f8a79`); §4: "A verdict
  names a missing expression by what it needs"
- 2026-10-18 — Map an aesthetic to what its stat computes with after_stat (expressions, step 3)
  (`c6dc492`); §4: "An after_stat reads its stat's computed variables"
- 2026-10-18 — Give mtcars R's column types (expressions, step 2, part 3) (`37e6e07`); §4: "R's
  `as.character()` is a boundary of its own"
- 2026-10-18 — Read a mapping value as discrete with factor() (expressions, step 2, part 2)
  (`aaa63ba`); §4: "`factor()` reads a value as discrete", "R's `as.character()` is a boundary of
  its own"
- 2026-10-18 — Store a column mixing integers and floats as floats (expressions, step 2, part 1)
  (`dead326`); §4: "Column types belong to the frame"
- 2026-10-18 — Check the mutation pass's sandbox before it runs, with .credo mirrored (`74b9275`);
  §4: "The mutation pass mirrors `.credo/`"
- 2026-10-18 — Map aesthetics to expressions and constants (expressions, step 1) (`6dc3658`); §4:
  "A mapping value is a column, an expression or a constant", "Expressions in a mapping are Phase
  3's sixth increment"
- 2026-10-18 — Mutation-test each commit after it lands, over the lines it changed (`8a82a46`);
  §4: "Mutation testing runs after each commit"
- 2026-10-18 — Draw text and titles in the notebooks (text and titles, step 6) (`52aa3a2`); §4:
  "Text and titles is Phase 3's fifth increment", "A notebook leaves out an argument ggplot2 does
  not recognise"
- 2026-10-18 — Annotate plots and draw rectangles (text and titles, step 5) (`bb57487`); §4:
  "`annotate()` draws with every geom Giggly has"
- 2026-10-18 — Give a layer a table of its own with data: (text and titles, step 4) (`4e77ecd`);
  §4: "A layer's own table is public", "A column the plot names is checked against the tables"
- 2026-10-17 — Label plots with labs (text and titles, step 3) (`d1e8217`); §4: "A title may run
  over several lines", "`labs/2` takes the titles"
- 2026-10-17 — Nudge labels with nudge_x and nudge_y (text and titles, step 2) (`dabca48`); §4: "A
  position declares the aesthetics it reads"
- 2026-10-17 — Draw labels with geom_text (text and titles, step 1) (`91fe040`); §4: "Text and
  titles is Phase 3's fifth increment", "An aesthetic a layer takes from the plot"
- 2026-10-17 — Draw colours in the notebooks (colour, step 4) (`5918137`); §4: "Colour and fill is
  Phase 3's fourth increment", "Colours are CSS's names and hex forms"
- 2026-10-17 — Map continuous columns to colours and draw the colour bar (colour, step 3b)
  (`5c1aabb`); §4: "The colour bar is drawn as ggplot2's gradient form", "R's exact colours come
  from the `color` package's conversions", "A discrete scale carries its missing value"
- 2026-10-17 — Draw guides through a protocol at Giggly.Guide (colour, step 3a) (`47df626`); §4:
  "The guide protocol sits at `Giggly.Guide`"
- 2026-10-16 — Draw a layer only in the legend keys its data holds (colour, step 2's follow-up)
  (`8e21e24`); §4: none, ggplot2's `keep_key_data()` followed as `assembly.md` says
- 2026-10-16 — Map discrete columns to colours and fills (colour, step 2) (`5dbd380`); §4: "A
  discrete scale carries its missing value", "Group ids follow ggplot2's `add_group()`", "The
  guide protocol sits at `Giggly.Guide`"
- 2026-10-16 — Set colours and fills on a layer (colour, step 1) (`2841c12`); §4: "Colour and fill
  is Phase 3's fourth increment", "Colours are CSS's names and hex forms", "R's exact colours come
  from the `color` package's conversions"
- 2026-10-16 — Draw lines and dates in the notebooks (lines, step 4) (`04e9957`); §4: "Lines and
  date axes are Phase 3's third increment"
- 2026-10-16 — Put dates on an axis (lines, step 3) (`223c9f1`); §4: "Lines and date axes are Phase
  3's third increment"
- 2026-10-16 — Curve lines in radial coordinates (lines, step 2) (`10dce7f`); §4: "Lines and date
  axes are Phase 3's third increment"
- 2026-10-16 — Draw paths and lines (lines, step 1) (`6db4135`); §4: "Lines and date axes are Phase
  3's third increment", "The document's root declares svglite's stylesheet for lines"
- 2026-10-16 — Draw mapped alpha in the notebooks (alpha, step 4) (`af5d981`); §4: "Alpha is Phase
  3's second increment", "Guides become structs of their kind"
- 2026-10-16 — Draw alpha's legend (alpha, step 3) (`c64b1e5`); §4: "A legend is a table nested in
  the plot's", "Alpha is Phase 3's second increment"
- 2026-10-16 — Map alpha through a scale (alpha, step 2) (`c8140fd`); §4: "A scale's palette is a
  field", "Alpha is Phase 3's second increment", "Group ids follow ggplot2's `add_group()`"
- 2026-10-16 — Set alpha on a layer, and add the diamonds dataset (alpha, step 1) (`4f34ce2`); §4:
  "Alpha is Phase 3's second increment", "ggplot2's `diamonds` is shipped whole"
- 2026-10-15 — Add a notebook for every page of ggplot2's reference (`adf9236`); §4: "Every page
  of ggplot2's function reference has a notebook"
- 2026-10-15 — Add the geom_bar notebook (bars, step 5) (`6f6b680`); §4: "Bars are Phase 3's
  first increment", "The notebooks follow ggplot2's reference pages"
- 2026-10-15 — Draw horizontal bars (bars, step 4) (`b5c2d10`); §4: "A geom says where its marks
  sit", "Bars are Phase 3's first increment"
- 2026-10-15 — Dodge bars side by side (bars, step 3) (`5d24693`); §4: "A layer chooses its
  position by an atom"
- 2026-10-15 — Count bars with geom_bar (bars, step 2) (`fe658e8`); §4: "Bars are Phase 3's first
  increment"
- 2026-10-15 — Draw columns with geom_col (bars, step 1) (`eb2c178`); §4: "Bars are Phase 3's first
  increment", "A geom says where its marks sit", "A kind is named after ggplot2's ggproto class",
  "ggplot2's `resolution()` is a boundary of its own"
- 2026-10-15 — Draw faceted radial panels, and clip the plot's background (`coord_radial()`,
  step 4) (`cbd42bb`), which completes Phase 2; §4: "A `:rest` size has a weight"
- 2026-10-15 — Draw a plot in radial coordinates (`coord_radial()`, step 3) (`8989249`); §4:
  "`coord_radial()` is built in four steps"
- 2026-10-15 — Give the scene offsets, polygons and kept proportions (`coord_radial()`, step 2)
  (`93fb858`); §4: "A primitive's position is a place in its cell plus an offset in points", "A
  `:rest` size has a weight"
- 2026-10-15 — Place positions in radial coordinates (`coord_radial()`, step 1) (`f4440ce`); §4:
  "`coord_radial()` is built in four steps"
- 2026-10-15 — Cut the internal documents to one home per fact; §4: "The design log is reference,
  not reading"
- 2026-10-15 — The `facet_wrap` notebook and `Datasets.mpg/0` (`09421b0`); §4: "Each dataset's
  file is read behind a waiver of its own"
- 2026-10-15 — `facet_wrap`'s free scales (`3276a48`)
- 2026-10-15 — `facet_wrap`'s panels drawn (`129c30f`); §4: "Every plot's cells are drawn in
  ggplot2's facets' order"
- 2026-10-14 — `facet_wrap`'s panels, as data (`21a9507`)
- 2026-10-14 — Facets, coordinate systems, geoms, stats and positions are structs of their kinds
  (`64e899b`, `74ce98b`); §4: "Each facet, coordinate system, geom, stat and position is a
  struct", "`facet_wrap` is built in steps"
- 2026-10-14 — The assembly's axis titles are `guide_titles` (`b29f225`); §4: "The assembly's
  titles are"
- 2026-10-14 — A theme is a function, not a module implementing a behaviour (`6ca507e`); §4: "A
  theme is a function"
- 2026-10-14 — The scene's circle primitive is `Circles`, not `Points` (`2cdfefa`); §4: "The
  scene's circle primitive is"
- 2026-10-13 — Zip and map in one pass, held by the first repo-local credo check (`ba323d6`); §4:
  "Zip and map in one pass"
- 2026-10-13 — Phase 2 planned around `coord_radial()`; no `coord_flip()` or `coord_polar()`
  (`7703f52`); §4: "Giggly follows ggplot2's current coordinate functions"
- 2026-10-13 — Only the API is documented; everything else says it is not API (`308ae52`); §4:
  "The API is what a user calls", "Data a plot cannot read is refused by raising"
- 2026-10-13 — `to_svg/2` draws at a size in pixels, 700 by 433 by default (`a8b02ce`); §4: "A
  plot is drawn at the size it is given"
- 2026-10-13 — The first notebook: `geom_point` (`e05d891`); §4: "The notebooks follow ggplot2's
  reference pages"
- 2026-10-13 — Phase 1 audited: the scatter plot is architecturally complete (`22de0a3`)
- 2026-10-13 — The panel is clipped to its edges (`c32529b`); §4: "The panel is clipped to its
  edges"
- 2026-10-13 — An axis of one huge value is drawn at the panel's middle (`b38cf68`); §4: "An axis
  whose extent is zero wide"
- 2026-10-13 — The panel's background and grid lines (Phase 1, increment 9, step 2) (`596f08b`);
  §4: "The panel's grid lines are placed"
- 2026-10-12 — The theme and the plot's background (Phase 1, increment 9, step 1) (`596f08b`); §4:
  "The theme is a resolved value"
- 2026-10-12 — Axis titles (Phase 1, increment 8, step 2) (`721bfc1`); §4: "An axis is titled"
- 2026-10-12 — Axes (Phase 1, increment 8, step 1) (`714436c`); §4: "Axes are drawn"
- 2026-10-12 — The coordinate system, drawn: `Giggly.to_svg/1` (`e049a0e`); §4: "The coordinate
  system arrives with drawing"
- 2026-10-12 — The stat, position and transform stages (`1d9c2f4`); §4: "A layer records its
  stat and position"
- 2026-10-12 — Code review's mutation step picks tests by coverage (`72890c5`); §4: "Mutation
  testing picks each mutant's tests by coverage"
- 2026-10-12 — Position scales (Phase 1, increment 5) (`72890c5`); §4: "Position scales are chosen
  by column type"
- 2026-10-12 — Staging no longer invalidates a recorded boundary approval (`a2624ca`)
- 2026-10-12 — Panels (Phase 1, increment 4) (`a2624ca`); §4: "The facet assigns panels first"
- 2026-10-12 — A plot is run from `Giggly`; the stages run in `Giggly.Assembly`; every boundary is
  strict (`e01519e`); §4: "A plot is a value built by", "Every boundary is strict"
- 2026-10-12 — The plot spec, the first build stages and column types (`e01519e`); §4: "Column
  types belong to the frame", "Group ids follow ggplot2's", "The table is read when the plot is
  created", "The assembly exists from its first stage", "Points accept only what Phase 1 can
  draw"
- 2026-10-11 — The waiver gate treats a removed boundary declaration as a widening (`e4aaade`);
  §4: "Removing a boundary declaration is a widening"
- 2026-10-11 — The mutation step mutated only the last file named (`e4aaade`)
- 2026-10-11 — The review's scope command works without a remote (`8850615`)
- 2026-10-11 — Mutation testing added to code review (`8850615`); §4: "Mutation testing runs in
  code review"
- 2026-10-11 — The data frame (Phase 1, increment 2) (`cdb9ee0`); §4: "Callers reach a frame",
  "User column names become strings"
- 2026-10-11 — CLAUDE.md trimmed to what applies to a library (`ca7d7e7`); §4: "CLAUDE.md holds
  only what applies to a library"
- 2026-10-11 — The aesthetic vocabulary (Phase 1, increment 1) (`de4e8ec`); §4: "Aesthetics are
  atoms with ggplot2's names"
- 2026-10-11 — Phase 0 ratified: the vocabulary and the value types (`de4e8ec`); §4: the entries
  dated 2026-10-11
- 2026-10-11 — The coding harness installed (`85b24cd`)

## 7. Deferred / open questions

- **Rows taken from a table by hand lose its factors' levels (found 2026-10-23, the ordering
  sweep).** A `Giggly.Factor` enumerates as its values, so a user who filters or samples
  `diamonds` with `Enum`, or reads it into Explorer, gets plain text, and `cut` sorts
  alphabetically, where R's `subset()` and `diamonds[rows, ]` keep the factor. The notebooks
  rebuild each factor by hand (§4, the entry beginning "A random sample of a table's rows").
  Options: a public function that takes rows of a table and keeps its factors, or leaving the
  rebuilding to the user, as the notebooks do. Settled when `geom_jitter()` arrives, whose
  examples draw `subset(diamonds, carat > 1)`.
- **How a notebook treats an example of a function Giggly will not offer (found 2026-10-17).**
  Giggly exposes no superseded or deprecated function (§4, the entry beginning "Giggly exposes no
  function"), yet 33 waiting examples call one, most of them `coord_map()`,
  `annotation_logticks()`, `expand_limits()`, `qplot()` and `coord_flip()`, and their verdicts
  say "Not in Giggly yet", which will never become true. Options: draw them with the replacement,
  as `labs(x:)` for `xlab()`, which `notebooks.md` allows as a counterpart, though `ggplot()` for
  `qplot()` is the imitation it forbids; or say in the verdict that Giggly will not offer it.
  Settled when the first such example could otherwise be drawn. The active theme's functions,
  which Giggly rejects as global state, are answered (§4, the entry beginning "An example that
  sets ggplot2's active theme").
- **Livebooks that match ggplot2's online reference (Steve's aim, 2026-10-12).** A set of
  Livebooks reproducing the examples in ggplot2's documentation, which ExDoc points at rather than
  building graphics, as ggity's docs did. `geom_point` and `facet_wrap` are built, and how notebooks are
  made is settled (the §4 entry beginning "The notebooks follow ggplot2's reference pages"). Still
  open: which pages follow, and a side quest, a Kino library so a plot value draws itself in a
  cell (Livebook shows the SVG with `Kino.Image` until then), as an optional dependency or a
  package of its own like `kino_vega_lite`, settled when it is built.
- **How structs order in a mapped `group`.** Group ids sort values in Erlang term order, which
  orders `Date`s by their fields rather than chronologically. Nothing shows group order until a
  position stacks or dodges by it (Phase 3), which settles it.
- **Engine backends for `Giggly.DataFrame` (Explorer, Dux, SQL) are deferred.** The behaviour's
  operation set is kept relational so one can be added as a separate optional package without
  touching stats or scales. One gets built only against a measured case the list implementation
  cannot serve (the §4 numbers: ~0.5 s per 10⁶-row pass for splitting or sorting) **and** an
  upstream healthy enough at that moment to carry it — checked then, not assumed now. As of
  2026-10-11 Explorer has a new de facto maintainer and a release cadence again after an
  eleven-month gap; Dux has been quiet since May and calls itself not production ready.
  **The long-term goal (Steve, 2026-10-20): the engine does the work that scales with the rows,
  so a plot over a very large table is drawn from its small render data without the table
  crossing into Elixir.** The approach, in the order it is taken: (1) stats compute only through
  frame operations (§4, the entry beginning "A stat computes only through frame operations"),
  with a vocabulary every engine has — `mutate` from an expression as data, `filter`, `join`,
  `summarise` with count, sum, min, max, mean, quantile, and window functions for cumulative
  sums; (2) a mapping's expressions by name (`{:log10, [:carat]}`), the engine validating each
  name at the call and refusing what it cannot run, an Elixir function kept as the Lists-only
  escape (built for `log10` 2026-10-22, a capture inside one refused); (3) with the first engine, the stages before the stat as columns and aggregates — the
  facet writing `panel` by a join rather than `split/2`, `group` as a window rank, training as
  one batched aggregate per layer, discrete mapping as a join against the level table — and
  `Plot.new/2` taking an engine's handle as itself, `Table.Reader` for Lists alone; a lazy
  engine then scans the table about twice per layer (train, stat) and materialises only the
  stat's output, so `layer_data/2` stays a frame of lists. Known limits: the identity stat
  materialises the rows it draws (Mosaic's M4 — four aggregates per pixel column — is the way
  past it for lines, outside ggplot2's vocabulary); `stat_density()` is relational in its binning
  (R's `density()` linear-bins onto 512 points before its FFT convolution; Mosaic's `binLinear1d`
  does the same binning in SQL and smooths the small result in the client) but not in its
  convolution, which runs on the 512; loess and gam smooths are not relational, `lm` with one
  predictor is (sufficient statistics, SQL's `regr_*`); R's doubles to the last digit hold for Lists and become a
  conformance suite with tolerances for engines whose summation, quantile or logarithm differs
  (Polars sums pairwise, DuckDB compensated, Postgres plain; `percentile_cont` exists in Postgres
  alone; Explorer 0.13's `quantile` in a query is hard-coded to nearest-rank interpolation, not
  R's type 7, so an Explorer engine refuses a box's hinges or computes them otherwise, checked
  2026-10-21 in its `expressions.rs`; it has no `log10`, only `log(x, 10)`, which divides natural
  logarithms and misses R's `log10()` in the last bit on 7,144 of 12,064 values tried, where
  Erlang's `:math.log10`, the list frame's, matched R on all, checked 2026-10-22 by running it).
  **The precedent is Mosaic** (uwdata/mosaic, read from its source 2026-10-20: `packages/mosaic/
  sql/src/transforms/`, `packages/mosaic/core/src/`, `packages/vgplot/plot/src/marks/`), a
  JavaScript grammar whose marks are clients of a coordinator and compute in DuckDB; no Elixir
  library does this, and VegaLite/Tucan describe transforms for the browser's Vega runtime alone.
  What carries over: a mark's `prepare()` asks for every channel's statistics (min, max, distinct)
  in one query, then `query()` builds the main one from those numbers — train once per layer, in
  one batched aggregate, then one stat scan; bin breaks are chosen in the client from the two
  extent numbers and the engine runs `floor((col - min) / step)` in transformed space
  (`binHistogram`), though Mosaic drops empty bins where ggplot2 keeps them; queries are an AST in
  a package of their own (`mosaic-sql`) walked by visitors (`collectColumns`, `rewrite`), an
  aggregate becoming a window function when given a partition and order — the shape for
  `mutate`'s expression form and the engine's validation walk; density's linear binning is two
  weighted rows per point, `UNION ALL`, group by, sum (`binLinear1d`), smoothed in the client;
  `regressionY` is one query of SQL's `regr_*`; M4 is four aggregates per pixel column; only
  decomposable aggregates are cached or merged (`sufficient-statistics.ts`: count, sum, avg,
  variance, covariance, correlation, `regr_*`, min, max, product; never `DISTINCT`, median or
  quantile), and the consolidator merges queries on one table, filter and group-by into one
  `SELECT` split per client, its cache keyed by SQL text. Not to copy: DuckDB-only SQL
  (`argmin`, `regr_*` are not in SQLite; Polars spells them differently) where the vocabulary
  wants the portable intersection, and "perceptually faithful" as the correctness bar where
  Giggly's is R's output.
- **Rows that `table` reads loosely (found 2026-10-13, unscheduled).** Reviewing
  `DataFrame.from_table/1`: rows whose keys disagree (a later map row missing a key, keyword rows
  in another order, a row that is not a record) raise `table`'s own `RuntimeError`, not an
  `ArgumentError` in Giggly's words, and `from_table/1`'s explanation does not list them; a later
  map row's **extra key is dropped without a word**, since `table` takes the columns from the first
  row, which is the silent loss `from_table/1`'s length check exists to prevent; and `[]` is a
  table of no rows while `%{}` is refused as not a table.
- **`tack` is a git dependency with no `ref`/`tag`.** `mix.lock` pins the commit, so builds are
  reproducible, but `mix deps.update tack` floats to the branch head. Settled by pinning a `tag:`
  once Tack publishes releases.
