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
`00-synthesis.md` is the proposed build order), as CLAUDE.md asks of plans. Nothing from it has
been ratified yet; decisions and their rejected alternatives move into §4 as they are made.

## 2. Architecture & principles

Giggly is a pipeline over immutable values. `%Giggly.Plot{}` is the spec the public pipe builds:
data, a mapping from aesthetics to columns, layers (each a geom, a stat and a position), scale
specs, a facet, a coord, labels and a theme. `Giggly.build/1` turns it into `%Giggly.Built{}`: one
data frame per layer in the aesthetic vocabulary with `panel` and `group` columns, the layout table,
the trained scales and the per-panel view scales (panel params). `Giggly.render/1` turns that into
`%Giggly.Scene{}`, a tree of drawing primitives sized in units inside a table layout; a backend
(`Giggly.SVG` first) serializes the scene. Each value is inspectable on its own, which is how the
facet and coord seams are tested without rendering anything.

The whole pipeline is pure. Its only inputs are the plot spec and a `Table.Reader`; it reads no
config, no clock and no randomness (jitter will take a seed). The impure edges are adapters at the
rim: reading the input table, and whatever a host does with the emitted iodata. `boundary` holds
the shape (`mix boundary.spec` prints the graph); the sub-boundaries get carved as the first
modules of each area land, starting from the umbrella `Giggly` with `exports: :all`.

Two cross-cutting rules come straight from the ggplot2 study and ggity post-mortem (§1 points at
the research): **a geom never sees a panel, a pixel or a facet variable** — facets are a column
and a lookup table, the coord is the only route from data space to the unit panel, and layout is
resolved by the scene's table of tracks, not by arithmetic in geoms; and **cross-cutting concerns
get a seam before the second user of them exists** — grouping, panels, coordinate transforms and
per-mark attributes are each applied in one place the pipeline threads through, never
re-implemented per geom.

## 3. Module map

`lib/giggly.ex` is the umbrella root, and will hold the top-level entry points (`build/1`,
`render/1`, `to_svg/1`). Each area of the pipeline is a module or namespace directly under
`lib/giggly/`, with its invariants in a `.claude/rules/<area>.md` that CLAUDE.md's status map
names — the status map is the index, and the moduledocs are the contracts.

## 4. Key design decisions (the "why", so we don't relitigate)

Each entry: **the decision (date, whose call)**, then *Rejected: the alternative* — and why. Newest
first. A decision belongs here when someone could plausibly propose undoing it; the entry is what
stops the question being reopened from scratch.

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
  The `Giggly` root holds `build/1`, `render/1`, `to_svg/1` and the boundary declaration.
  *Rejected: every function on the `Giggly` root* — reads closest to `ggplot() + geom_point()`,
  but one module then carries every geom, scale and theme function. *Rejected: an importable
  bare-function DSL* — closest to R visually, unusual in Elixir, collides with user names.

- **Three top-level values with one function between each (2026-10-11, Steve):** `%Giggly.Plot{}`
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
  (2026-10-11, Steve).** Transform scales → train position scales → map positions to numeric (not
  to the unit panel) → stat → `after_stat` → geom reparameterize (bar to `xmin/xmax/ymin/ymax`) →
  position → reset and retrain position scales → freeze view scales → map positions again → train
  non-position scales → build guides → map non-position scales → `after_scale` → fixed values
  last. Transform-before-stat means a smoother on a log axis fits in log space; train-before-stat
  means bin edges come from the panel range and agree across groups; position-before-retrain means
  stacked totals reach the axis; fixed values last means they bypass scales. This list moves into
  `.claude/rules/build.md` when the build area has code. *Rejected: ggity's order* — positions ran
  in pixel space after scaling, so the scale could not see stacked totals and the stat had to run a
  second time at `geom_bar` call time to stash a maximum in a side channel.

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

- **Input is anything implementing `Table.Reader`, read once at build start (2026-10-11, Steve).**
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
