# giggly — Design Notes

The canonical design overview, decision log and milestone log. CLAUDE.md says what applies to
every session; the area files under `.claude/rules/` say how each area works; this file says
**why** — what was decided, what was rejected, and what shipped when. The `docs-sync` skill routes
changes here; `.claude/rules/docs.md` is the shape.

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
module lands with its `deps:` as its contract, a domain that owns an outside library is a
top-level boundary, and the `CorePurity` check reads all of `lib/`.

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
names — the status map is the index, and the moduledocs are the contracts.

## 4. Key design decisions (the "why", so we don't relitigate)

Each entry: **the decision (date, whose call)**, then *Rejected: the alternative* — and why. Newest
first. A decision belongs here when someone could plausibly propose undoing it; the entry is what
stops the question being reopened from scratch.

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
  first module lands: `Aesthetics` lists nothing, `Group` lists `DataFrame`, `Plot` lists
  `Aesthetics` and `DataFrame` and exports `Layer`, `Assembly` lists `Plot`, `DataFrame` and
  `Group`; to come, `Scale` lists nothing (so it stays extractable) and the SVG backend lists only
  the scene. A domain that owns an outside library is a top-level boundary, so the library is
  listed only where it is used: `DataFrame` with `Table`, a sanctioned `top_level?:` exemption;
  `Giggly` lists `DataFrame` only so its sub-boundaries may, and exports `Plot`. The test helpers
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
  not reach a sub-boundary's calls. *Rejected: `DataFrame` nested, with `Table` listed on `Giggly`*
  — every module directly in `Giggly` could then call `table`. *Rejected: `ExUnit` listed on
  `Giggly` for the test helpers* — the library could then call it; *or the helpers lifted with
  `top_level?:`* — two exemptions where naming them outside `Giggly` needs none.

- **Column types belong to the frame: `DataFrame.dtypes/1` (2026-10-12, Steve).** Every column
  has one type, worked out when it enters a frame by Explorer's rules for `Series.from_list/2`
  (read in its 0.13.0 source): one kind of value plus `nil`; integers with floats are `:float`;
  `:nan`, `:infinity` and `:neg_infinity` are floats; all-`nil` or empty is `:null`; binaries are
  `:string`; `Date`, `Time`, `NaiveDateTime` and `DateTime` have their own types. Lists adds `:atom`
  and `:term` (pandas' and Polars' `object`), and stores each column as `{dtype, values}`. A column
  mixing two types is refused, by `from_table/1` and beneath it alike. What a type means to a plot
  is the plot's: `Giggly.Group` reads `:string`, `:boolean` and `:atom` as discrete. *Rejected:
  deciding discreteness from the values in plotting code* (first proposed for this increment) —
  what a column holds is the frame's to validate and report, and an engine has the types natively.
  *Rejected: R's coercion, where numbers mixed with strings make a character column* — Elixir has
  none, a silently categorical axis hides a messy column, and Explorer's `DataFrame.new` refuses
  the same input. *Rejected: working types out on demand* — each reader rescans, and a mixed
  column surfaces wherever it is first read. *Rejected: refusing values with no named type* — an
  unused JSON or numeric column in a database result would refuse the whole table. *Rejected:
  Explorer's widths (`{:s, 64}`)* — a list holds unbounded integers and has no width to report.

- **Group ids follow ggplot2's `add_group()` (2026-10-12, Steve).** Checked against
  `R/grouping.R` and `id()`/`id_var()` in `R/compat-plyr.R`. A mapped `group` is renumbered 1..k
  over its sorted values and nothing else counts; otherwise the combinations of the discrete
  columns that occur are numbered 1..k, sorted column by column; with no discrete column every row
  is `-1`. Values sort with `nil` last (R's `na.last`) and otherwise in Erlang term order. Evaluated
  columns are in aesthetic-name order, and the key follows them. The integer `panel` column needs
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
  (2026-10-12, Steve).** `Giggly.Plot.new/2` reads the `Table.Reader` into a frame; `new/2` and
  each geom function resolve their mapping against it, raising `ArgumentError` that names the
  aesthetic, the reference as written and the data's columns; a layer's mapping is checked with
  the plot's as the layer is added. ggplot2 converts its data at construction too (`fortify(data)`
  in `ggplot.default`, `R/plot.R`, and again in `layer()`); only expression evaluation waits for
  the build. This amends the entry beginning "Input is anything implementing `Table.Reader`".
  *Rejected: reading at build start* (that entry's first wording) — a misspelt column surfaced at
  render, its stack trace pointing at the wrong line, and the build held a `Table.Reader` rather
  than a checked frame. *Rejected: "did you mean"* — the list of columns already puts the right
  spelling beside the wrong one, and a similarity threshold is one more thing to tune and test.

- **`Giggly.build/1` exists from its first stage and gains one stage per increment (2026-10-12,
  Steve; since amended — the stages run in `Giggly.Assembly` and a plot is inspected with
  `Giggly.layer_data/2`, see the entry beginning "A plot is a value built by").** It began with aesthetic evaluation and `Group.add/1`; each later increment inserts its
  stage where the order puts it, and `%Giggly.Built{}` gains a field with the stage that fills it.
  *Rejected: wiring the whole build at once, at the end of Phase 1* (the Phase 1 plan's draft) —
  every stage function would have had only test callers until then.

- **Points accept only what Phase 1 can draw, and fixed aesthetics wait for drawing (2026-10-12,
  Steve).** `geom_point/2` accepts `:x`, `:y` and `:group`; an aesthetic joins a geom with the
  scale that maps it. *Rejected: ggplot2's full list for points now* — a mapped colour would be
  evaluated and grouped and never drawn. *Rejected: fixed aesthetics (`alpha: 0.4`) now* — nothing
  reads one before the scene, what counts as a valid value is a rendering decision, and "a fixed
  value overrides an inherited mapping" cannot be exercised until something can be both. So
  NimbleOptions waits for the first keyword option; what its source showed about duplicates is in
  `.claude/rules/plot.md`.

- **Removing a boundary declaration is a widening, and the waiver gate denies it (2026-10-11,
  Steve).** The hook counts `use Boundary` declarations outside docstrings and denies an edit that
  lowers the count; the commit check does the same, and flags a declaring file deleted while
  `.ex` files remain under its namespace directory. *Rejected: a test listing the modules that
  must declare a boundary* — it would protect Giggly only, and keep a second list in step with the
  declarations themselves. *Rejected: relying on the permission score* — `exports: []` scores 0,
  the same as no declaration, so deleting `Giggly.DataFrame`'s declaration scored 0 → 0 and passed.
  *Rejected: flagging every deleted declaring file* — deleting an area outright would need an
  approval for a change that opens nothing.

- **Mutation testing runs in code review, with muex, over the changed files; survivors are
  triaged, not scored (2026-10-11, Steve).** `elixir-code-review` runs `mix muex --no-optimize
  --no-filter --verbose` with the changed `lib/` files as one comma-separated `--files`, and its
  report says of each survivor whether it is a missing test, unreachable or redundant code, an
  equivalent mutant, or the wording of a message whose datum the tests assert — and why.
  An experiment; how it goes decides whether it stays. *Rejected: hand-picked mutants* — chosen by
  looking at the tests already written, they never mutated `DataFrame.pull/2`'s guard, the one
  behaviour with no test; and a scripted loop reused a previous mutant's build. *Rejected: a `mix
  quality` step or a `--fail-at` score threshold* — two small files take minutes, and equivalent
  mutants count as survivors, so the score is noise while the survivor list is the signal.
  *Rejected: muex's defaults* — its optimizer reported 100% over five mutants where the full run
  had a real survivor, and its filter skips any module declaring several callbacks. *Rejected:
  `--since <ref>`* — it diffs committed history, and review here runs before commit.
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

- **Three top-level values with one function between each (2026-10-11, Steve; since amended —
  the assembled value and the scene are internal, see the entry beginning "A plot is a value
  built by"):** `%Giggly.Plot{}`
  → `build/1` → `%Giggly.Built{}` → `render/1` → `%Giggly.Scene{}` → a backend → iodata. The
  build product carries per-layer frames with resolved params, the layout table, trained scales
  and panel params; nothing in it knows about SVG. *Rejected: a single pass from spec to markup* —
  ggity's `Plot.plot/1`, where aesthetic mapping, pixel arithmetic and SVG emission happened in
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
  a group-by shape, and its fast backend is a larger NIF than Explorer's.

- **Input is anything implementing `Table.Reader`, read once at build start (2026-10-11, Steve;
  since amended — it is read in `Plot.new/2`, see the entry beginning "The table is read when the
  plot is created").**
  The `table` package is tiny, stable, and implemented by Explorer, Dux, the database drivers and
  plain lists of maps, because Livebook requires it — so it survives whichever dataframe library
  is maintained in three years. Mapping values may be atoms or strings and are resolved against the
  table's column names at evaluation; after that point user column names do not exist in the
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

## 6. Milestone log & roadmap

Entries older than about two weeks are compacted into the one-line index below; newer ones are kept
in full and compact on the same schedule as they age. Before an entry is compacted its durable
content is verified to live in the evergreen surfaces — decisions and rejected alternatives in §4,
current behaviour in CLAUDE.md / the rules files / the skills / moduledocs — so the index is a
finding aid, not the record. The full text is one `git log -S "<its title>"` away.

**Compacted index:**

_(none yet)_

**Full entries (newest first):**

- **2026-10-12 — A plot is run from `Giggly`; the stages run in `Giggly.Assembly`; every boundary
  is strict.** Settling where the strict boundary went turned into a walk through the whole
  architecture, prompted by Steve asking why the top-level `Giggly` should list `Table` when
  nothing in it calls `table`. The two §4 entries dated today beginning "A plot is a value built
  by" and "Every boundary is strict" give the result. In code: `Giggly.build/1` and
  `Giggly.Built` gave way to `Giggly.Assembly.run/1` (returning the list of layer frames) and
  `Giggly.layer_data/2`, whose tests replaced the build's; `Giggly.Layer` became
  `Giggly.Plot.Layer`; every domain got its declaration; the test helpers moved out of the
  `Giggly` name. Experiments in a throwaway copy decided the shape: the purity check, pointed at
  all of `lib/`, passed and flagged a planted clock read; a strict top-level boundary refused
  `Table` from `Plot` but not from `DataFrame`, which was not strict itself; `Table` listed on
  `DataFrame` alone was rejected until its parent listed it; and a `Plot.t()` named in a `@spec`
  crossed a boundary unseen while a `%Plot{}` match did not. In the real tree a planted module
  inside `Plot` calling `Table` and `Group` was refused on both counts, and each strictness test
  failed when its default was removed or a declaration relaxed. Each widened declaration was
  shown to Steve in plain language before it was written, and his approval recorded with
  `waiver-gate.sh approve-widening`. The build area's rules file became `assembly.md`. Review's
  mutation step found `layer_data/2`'s `index >= 0` guard unpinned: without it a negative index
  reached `Enum.at/2`, which counts from the end, so `layer_data(plot, -1)` returned the last
  layer; a negative index now raises the documented `ArgumentError`, and a test pins it. It also
  ran over `Giggly.Aesthetics` for the first time, since the declaration brought the file into
  scope; its survivors are in increment 1's code and are reported, not acted on.

- **2026-10-12 — The plot spec, the first build stages and column types (Phase 1, third
  increment).** `Giggly.Plot` (`new/2`, `geom_point/2`) builds a `%Plot{}` of a data frame, a
  mapping and layers (`Giggly.Layer`); `Giggly.build/1` evaluates each layer's mapping and adds the
  `group` column (`Giggly.Group.add/1`), returning `%Giggly.Built{data: [frame per layer]}`; and
  `Giggly.DataFrame.dtypes/1` reports each column's type. The §4 entries dated today give the
  shape. The scope changed in discussion before any code: the plan's draft wired the build at
  increment 7 and added fixed aesthetics and NimbleOptions now; the build instead starts here, and
  the other two wait for drawing. Discreteness was first proposed as a rule over values in the
  grouping code; Steve moved column types into the frame, since what a column holds is the frame's
  to report. NimbleOptions 1.1.1's source was read ahead of the increment that will add it: it
  keeps the first of a repeated key and type-checks only that one, and it has no number type —
  recorded in `.claude/rules/plot.md`. ggplot2's grouping was checked against `R/grouping.R` and
  `R/compat-plyr.R`, and Explorer's inference against its 0.13.0 `Series.from_list/2`. Review's
  mutation step (all seven changed files) found two doc promises no example kept — the two
  infinities, and a float before an integer — and `:group` unpinned among the aesthetics points
  accept; refusal tests that asserted no datum of their message; and two branches that only
  chose between wordings (a separate message for an inherited aesthetic, and refusing `nil`,
  `true` and `false` as column references), which were removed rather than tested. The areas got
  `.claude/rules/plot.md` and `build.md`, and `data_frame.md` gained the type rules; covering the
  root module left no `lib/` file outside a rules glob.

- **2026-10-11 — The waiver gate treats a removed boundary declaration as a widening.** The
  corrected mutation run left a survivor deleting `use Boundary, exports: []` from
  `Giggly.DataFrame`: no test failed, the build stayed clean, and `.claude/hooks/waiver-gate.sh`
  allowed the edit, since its permission score reads that declaration and no declaration alike as
  0. Simulated edits confirmed it: exporting `Lists` was denied, deleting the declaration was not.
  The hook now counts declarations (`boundary_count`, docstrings excluded) at edit time and at
  commit time, flags a declaring file deleted while modules remain under its namespace, and hashes
  the count into a recorded approval so an earlier approval cannot cover a later removal. Proved
  against the real tree for edits (removal and widening denied; a doc edit, an identical rewrite
  and a docstring example's removal allowed) and in a throwaway clone for the commit check
  (removal flagged, then passed once approved and flagged again after a further change; a lone
  deleted root flagged; a whole deleted namespace and a `git mv` passed; a plain `mv` flagged). The
  hook came from the Tack harness, so this copy now differs from Tack's.

- **2026-10-11 — The mutation step mutated only the last file named.** The procedure said to pass
  each changed file in a `--files` of its own; muex declares `--files` as a single string, so a
  repeated flag keeps only the last value, and it splits that value on commas. Every run before
  this one mutated `Lists` alone — the trial's finding stands, since `pull/2`'s guard is in
  `Lists` — and `Giggly.DataFrame` had never been mutated; the summary line gives no per-file
  count, so nothing showed it. Found during the first review to use the step, by looking for a
  mutant of `DataFrame.select/2`'s guard and finding none. The procedure now passes one
  comma-separated `--files` and `--verbose`, whose `Found <n> file(s)` line counts what loaded; a
  capped run showed the comma form loading both files and the repeated form loading one.
  The corrected run's survivors were mostly the wording of error messages, whose datum the tests
  assert and whose sentence they deliberately do not — a kind the reference had no name for, and
  now names as not a finding — plus equivalent mutants and two deletions muex's sandbox lets
  compile: an `alias`, whose warnings the gate's `--warnings-as-errors` fails, and
  `Giggly.DataFrame`'s `use Boundary` declaration, which nothing caught (the entry above). The
  entry below reported the `alias` deletion as a deleted `@moduledoc`; muex never mutates docs,
  and the report's module listing had been misread. The review's own change removed `Lists.select/2`'s
  `is_list(renames)` guard, which repeated `DataFrame.select/2`'s, its only caller, so the facade's
  guard is the one check.

- **2026-10-11 — The review's scope command works without a remote.** `elixir-code-review` found
  its files with `git diff --name-only $(git merge-base HEAD origin/main)...HEAD`. With no `origin`
  the merge base failed inside `$(…)`, the pipeline still exited 0, and the review was scoped to
  nothing and reported clean; and even with a remote, `...HEAD` sees committed work only, while
  review here runs before the commit. The command now takes the merge base with the local `main`
  and lists `git diff --name-only <base>` (the branch's commits and the uncommitted changes)
  together with the untracked files. It was proved in a throwaway repo: on `main` it lists the
  working tree, on a branch it adds the branch's commits, and with no `main` it prints git's error
  and exits non-zero. The mutation step takes its files from the same list instead of keeping a
  command of its own. Like the mutation step, this makes Giggly's copy of the skill differ from
  Tack's.

- **2026-10-11 — Mutation testing added to code review.** `muex` 0.11.3 (dev/test only, pinned
  exactly; its one runtime dependency, `jason`, was already locked through credo) and a new step in
  `elixir-code-review` that runs it over the changed `lib/` files and triages every survivor (§4),
  its procedure in the skill's `references/mutation-testing.md` like the other checks' rules.
  It was tried first on a copy of the tree with `DataFrame.pull/2`'s test removed: the full run
  found that guard among its survivors, the gap the hand-picked mutants had missed. Its source was
  read for what it writes: each mutant is built from source in a sandbox under the temp directory
  that symlinks the project, and runs `mix test` in a fresh VM after the mutated module's `.beam` is
  deleted, so it cannot reuse a stale build; the in-place mutate-and-restore code still in the
  package has no callers. (These runs mutated `lists.ex` only, and the "deleted `@moduledoc`" below
  was a misread `alias` deletion — see "The mutation step mutated only the last file named" above.) On the committed data frame it leaves survivors that are equivalent
  (a deleted `@moduledoc`, reordered map keys, `Map.put_new` under a guard that excludes the key, a
  type guard that only changes the exception) and one that is not: `Lists.select/2`'s
  `is_list(renames)` guard repeats `DataFrame.select/2`'s, its only caller. The skill came from the
  Tack harness, so this copy of it now differs from Tack's.

- **2026-10-11 — The data frame (Phase 1, second increment).** `Giggly.DataFrame`, the behaviour
  and the module callers use, with `Giggly.DataFrame.Lists` its one implementation: reading any
  `Table.Reader` into a frame, building one from columns, column names and row count, choosing and
  renaming columns, pulling one column and putting one back. The §4 entries beginning "Callers
  reach a frame" and "User column names become strings" give the shape. `table` 0.1.2 was added after reading its whole source rather than its docs, which
  turned up what the adapter has to do itself: `Table.to_columns/1` returns a map, so the column
  order comes from `Table.Reader.init/1`'s metadata; nothing in the package checks that columns
  have equal lengths, and its row reader zips columns to the shortest, so a short column would
  silently misalign the rows; and a list of maps yields its columns sorted by key. It has no
  runtime dependencies, and the lock gained only its own line. The boundary was proved with a
  throwaway module outside it: a call to `Lists` and a `%Lists{}` each failed the build, and a
  call through `Giggly.DataFrame` did not. `nil` in a column is a missing value, as every
  `Table.Reader` source returns a null; the `:none` sentinel is for options, not data. Moved out of
  this increment to their first callers: split and recombine (scale training by scale id), column
  types and dense group ids (`add_group`), the `panel` and `group` columns (the facet and
  `add_group`), and the remaining relational operations (the first stat, `facet_wrap`). The area
  got `.claude/rules/data_frame.md` and a status-map line.

- **2026-10-11 — CLAUDE.md trimmed to what applies to a library.** Tack's library profile installed
  a CLAUDE.md written with an application in mind. Dropped: the external-services rule, the
  `Settings` configuration module, the `Clock` half of the determinism rule (now one line: the
  pipeline reads no config, clock or unseeded randomness), the deployment section (now one line
  about publishing keys), and the "follow mix format" bullet the gate already enforces. Moved
  without rewording: the per-step reasoning of the quality gate, into
  `.claude/rules/dependencies.md`, which loads with `mix.exs`. Dropped as already housed
  elsewhere: the credo-allowlist and rules-check paragraphs (`dependencies.md`, `docs.md`), the §6
  compaction policy (§6's own header, the docs-sync skill) and the type-erasing helper note (the
  review skill's `test-quality.md`). Rewritten: "pipes in the core, `with`s at the boundary" said
  the boundary returns `{:ok, t} | {:error, reason}`, which a pipe API cannot do; it now says the
  public API raises, per §4. Two harness rules that may not fit Giggly are flagged in §7 rather
  than changed. This was prompted by the line budget: each area's rules file earns a status-map
  line, and CLAUDE.md was at its budget after the first. The trim leaves room for Phase 1's lines,
  so the budget is not tightened until they are in. *Rejected: raising the budget a line per area*
  — the cap exists to keep CLAUDE.md small, and much of what filled it did not apply.
  *Rejected: fewer, larger rules files* — each would load whenever any of its areas is read.
  *Rejected: one status-map line per pipeline tier listing several rules files* — workable, but
  unnecessary once the inapplicable text was gone.

- **2026-10-11 — The aesthetic vocabulary (Phase 1, first increment).** `Giggly.Aesthetics`:
  canonical spelling with `colour` as the one alias, `canonicalize/1` for mappings and fixed
  options (raising on a collision), and ggplot2's x/y position families with `family/1` and
  `counterpart/1`. The families were taken from `ggplot_global$x_aes`/`y_aes` in the ggplot2
  source, whose own comment says the lists "must match in length and position of symmetrical
  aesthetics"; here they are held as one list of x/y pairs, so they cannot drift apart. The reserved `panel`/`group` columns are
  left for the data frame increment, where they are first used. The area got
  `.claude/rules/aesthetics.md`; its status-map line replaced CLAUDE.md's "Open items" line, which
  named no rules file and repeated the documentation section's pointer to §7, so the CLAUDE.md
  budget did not move.

- **2026-10-11 — Phase 0 ratified: the vocabulary and the value types.** The decisions in §4
  dated today were proposed from the pre-design research (§1) and ratified in conversation, with
  one amendment (the currency is named `Giggly.DataFrame`, not `Frame`) and one deferral (engine
  backends, §7). The phases that follow, from the research synthesis: **1** — a scatter plot that
  is architecturally complete: the null facet, the cartesian coord, `add_group`, identity stat and
  position, one point geom, one continuous and one discrete position scale with no pixel knowledge,
  the scene graph with its table layout, an SVG backend, and a text-metrics service behind an
  interface; **2** — prove the seams before widening: `facet_wrap` with free scales, `coord_flip`,
  polar; **3** — breadth: stats, stack/dodge, bar/line/boxplot, non-position scales and guides,
  the theme tree; **4** — the LiveView layer: HEEx output, per-mark attributes applied once at the
  scene, stable ids, optional PNG.

- **2026-10-11 — The coding harness installed.** `mix tack.install --profile library` wrote
  CLAUDE.md, the `.claude/` rules, skills and hooks, `.credo.exs` and the `boundary`
  declarations, the `mix quality` gate and CI. It ran directly rather than through
  `mix igniter.install tack@git:…` because igniter's `git:` form splits on `@` to read a ref, so
  an SSH URL (`git@github.com:…`) is unusable there and the HTTPS form has no credentials on this
  machine; igniter was added to `mix.exs` for the run and removed after. The `mix new` placeholder
  (`Giggly.hello/0` and its test) was deleted rather than given a `@spec`, which is what brought the
  first `mix quality` run to green. Nothing about the product has been decided yet; the pre-design
  research is in `~/.claude/plans/giggly-research/` (§1).

## 7. Deferred / open questions

- **How a public option says "absent".** CLAUDE.md's sentinel rule (`:none`, never `nil`) came with
  the harness. ggplot2 separates "remove this" (`breaks = NULL`, `guide = "none"`) from "use the
  default" (`waiver()`), and ggity spelled them `nil` and `:waivers`. Unresolved: the atoms Giggly's
  options use for each, and whether `nil` is acceptable at the public API while `:none` stays the
  internal sentinel. Settled by the first scale options that need both (`breaks:`, `labels:`).
- **Module names whose last segments collide.** CLAUDE.md forbids two modules in a family sharing a
  last segment, since a second `alias` with the same tail shadows the first. ggplot2's naming gives
  `Stat.Identity`, `Position.Identity` and `Scale.Identity`, and the build stage will use several at
  once. Options: keep ggplot2's names and call them through their namespace (`alias Giggly.Stat`,
  then `Stat.Identity`); keep them and alias with `as:`, which credo's `AliasAs` check (enabled)
  flags; or rename (`StatIdentity`). Settled when the first stat and position land.

- **What a second geom makes legal in an inherited mapping.** Each geom call checks the plot's
  mapping with its own, so today an inherited aesthetic the geom cannot use raises. ggplot2
  evaluates every inherited aesthetic and carries the ones a layer ignores: a plot-level `label`
  rides along in a point layer, and a discrete one the geom ignores still splits its groups, which
  is why `add_group()` excludes `label`. Options: drop an inherited aesthetic the layer cannot use
  before evaluation, or carry it as ggplot2 does. Settled when the second geom arrives; the `label`
  exclusion from the group key arrives with `geom_text` either way.
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
- **`tack` is a git dependency with no `ref`/`tag`.** `mix.lock` pins the commit, so builds are
  reproducible, but `mix deps.update tack` floats to the branch head. Settled by pinning a `tag:`
  once Tack publishes releases.
