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
  changes no geom; its other features follow it. This amends Phase 0's list of phases (§6, the
  entry beginning "Phase 0 ratified"). *Rejected: `coord_flip` as Phase 2's coordinate test*
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

- **The panel is clipped to its edges; the coordinate system records it and the assembly carries
  it to rendering (2026-10-13, Steve).** What is drawn in the panel is cut off at its edges, as
  every ggplot2 coordinate system does by default (`coord_cartesian(clip = "on")`, applied in
  `Coord$draw_panel` with the background and the border): a point at an infinite position, on
  the panel's edge, shows only its inner half. Cartesian panel params record `clip: :on`, read
  by a new `Coord.clip/1`; the assembly asks for each panel's and keeps it in `%Assembly{}` as
  `panel_clips`; rendering marks the panel's cell, every `Scene.Cell` now saying `:on` or `:off`
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
  coordinate system, `transform/2` included, against its rule of computing no positions, to read
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
  also found that `Coord.Cartesian.grid/1` rescaled each line's ends on its own axis's extent
  rather than the other axis's, which agree whenever an extent's ends differ; across an axis of
  equal ends ggplot2's lines shrink to a point at the middle, and now so do Giggly's.

- **The panel's grid lines are placed by the coordinate system and drawn by the guide, at R's
  regular minor breaks; clipping waits for a step of its own (2026-10-12, Steve).** The panel
  is drawn as ggplot2's `theme_gray()` draws it: a light grey background (ink mixed 92% toward
  paper, no border) and white grid lines, major ones at each axis's breaks as wide as a line and
  minor ones between them half as wide, under the layers. **`Coord.grid/1` places the lines**: it
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
  a separate task (since built, see the entry beginning "The panel is clipped to its edges"). *Deferred to first reader:* a grid that is not rectangular, munched with its
  background (polar coordinates); grid lines styled apart for x and y, or drawn over the layers
  (`panel.ontop`); minor ticks on an axis; the panel's border (`render_fg`, blank in
  `theme_gray()`).

- **The theme is a resolved value that every drawing function takes, recorded by name and set
  by nobody yet; the plot's background is the first element added to it (2026-10-12, Steve).** A
  plot records `theme: :gray`, as it records its facet and coordinate system, and `Giggly.Theme`
  resolves the name into the complete theme (ggplot2's `complete_theme()`): every element it
  draws, worked out from `theme_gray()`'s arguments (base size 11, black ink on white paper,
  lines and borders 11/22 mm) as ggplot2's `theme-defaults.R` works them out, each length and
  line width in points and each colour a hex string, so the TeX-point and millimetre conversions
  happen once, where the theme declares them. The assembly carries the name unread; rendering
  resolves it and hands the complete theme to the guide. The axis look moved out of the guide's
  module attributes into it, and the plot margin out of rendering's. The plot's background, a
  white fill with a white 0.5 mm border, is drawn first, in a cell spanning the whole table,
  margin included, as ggplot2's `table_add_background()` adds it: without it the drawing is
  transparent outside the panel, and on a dark page its grey labels vanish. The scene gained
  `Rect` (grid's `rectGrob()` at its default place and size, filling its cell) and cells that span
  ranges of rows and columns, and SVG writes svglite's rectangle markup. svglite's own page
  rectangle is left out with the rest of its preamble, since the plot's background covers it.
  *Rejected: a theme users can set, now* (`theme/2`, complete themes and their arguments, element
  constructors, ggplot2's inheritance with `rel()` and `element_blank()`) — it brings
  NimbleOptions and §7's "absent" question, which ggplot2's `NULL` (inherit) and `element_blank()`
  (remove) are exactly, and Phase 0 put the theme tree in Phase 3. *Rejected: module attributes
  until a theme can be set* (what the guide's rules said) — the look would sit in three drawing
  modules sharing derived values (paper white is the grid lines' colour and the background's, 0.5
  mm the tick's width and the major grid line's, the margin half a line), each copying the
  derivations and conversions, and every drawing function's signature would change when a theme
  arrived. **The point keeps its own look** (Steve, over the plan's note that the theme's
  `element_geom` would take it now): ggplot2 4 reads `element_geom` when its build fills each
  layer's default aesthetics in as columns (`compute_geom_2`, which is why its `layer_data()`
  shows colour, size, shape and stroke), and that stage, points drawn with a look per row, and the
  theme resolved in the assembly, as ggplot2's `ggplot_build()` completes it, arrive with the
  first mapped or set colour or size. *Rejected: the geom reading the theme as it draws* —
  ggplot2 has no such shape, `Geom` would list `Theme`, and the defaults would move again; *and
  the default-aesthetics stage now* — every row would hold the same values, which nothing can
  vary. **The name is `:gray`** (Steve): the American spelling the aesthetics' `color` set,
  plotnine's `theme_gray`, and the spelling ggplot2's own documentation lists and its examples
  use, though ggplot2 defines the function as `theme_grey` and makes `theme_gray` the alias.
  *Rejected: `:grey`.* Accepting the other spelling waits for the public function. **A golden is
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
  `Rect`. *Deferred to first reader:* a theme a user can set, and accepting `:grey`; default
  aesthetics from `element_geom`; the panel's border (blank in `theme_gray()`); x and y styled
  apart; text alignment and angle in the theme; theme values as CSS classes, ggity's way (the
  LiveView layer; only colours could move, since the layout is measured from the sizes); the
  theme's fonts. The panel's background and grid lines are this increment's second step (since
  built, see the entry beginning "The panel's grid lines are placed").

- **An axis is titled by the first layer to map its aesthetic, and the title is drawn by the
  axis's guide (2026-10-12, Steve).** The assembly titles each axis with the name of the column
  the first layer, in the order added, maps the axis's own aesthetic to through its computed
  mapping (`Plot.computed_mapping/2`): ggplot2's `setup_plot_labels()`, where a later layer
  never replaces an earlier one's label, read as `resolve_label()` reads it, by the scale's first
  aesthetic, so `xmin` alone titles nothing. An axis no layer maps has the title `:none` and
  draws none. Every point layer maps x and y, so today the first layer is always the one; review's
  mutation step showed the search past a layer that does not map the aesthetic could not be
  reached, so it waits for the first geom that can leave an axis unmapped, and `Map.fetch!/2`
  fails loudly until it arrives. The titles are `%Assembly{}`'s `titles`, not `labels`, which
  here means a break's text. `Coord.axes/1` now says which aesthetic each side's axis shows, so
  which title goes on which side is the coordinate system's call, as `coord_flip` will swap titles
  with axes (Giggly since chose not to build `coord_flip`; see the entry beginning "Giggly follows
  ggplot2's current coordinate functions"). `Guide.Axis.title/3` draws each title in a cell of its own beyond its axis, as
  ggplot2's layout adds its `xlab-b` row and `ylab-l` column: 11-point black text, a 2.75-TeX-point
  gap toward the axis, centred on the panel's side, hanging from the cell's far edge, the y title
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
  geom such as `geom_hline()`); `labs/2` and a title set by hand (NimbleOptions and §7's "absent"
  question come with it); the plot's title; and titles of other aesthetics (legends).

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
  coordinate system, whose new `axes/1` places them by the rescale the data goes through, keyed
  by the side of the panel each axis is drawn on (cartesian: x at the bottom, y on the left). A new
  `Giggly.Guide`, ggplot2's `guide_axis()`, draws each side's ticks and labels in `theme_grey()`'s
  look, held as module attributes until a theme can be set (since moved into the theme, see the
  entry beginning "The theme is a resolved value"), and measures how far the axis reaches;
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
  its functions are the only route to a text's size, and nothing chooses a font yet; a behaviour
  arrives with a second font (the theme's family, or a backend that can measure). It holds the
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
  transformation's inverse and domain (the first transformation that is not the identity); minor
  breaks (grid lines); the axis line (blank in `theme_grey()`); axes above or to the right, and
  secondary axes; angled, dodged or thinned labels; a scale's `breaks:`, `labels:` and
  `n.breaks:` (§7's "absent" question); the theme; more fonts, bold and italic; spanning cells
  (the theme and spanning cells since built, see the entry beginning "The theme is a resolved
  value"), names, clipping (since built, see the entry beginning "The panel is clipped"), z-order
  beyond list order and aspect ratio; a size for `to_svg` (since built, see the entry beginning
  "A plot is drawn at the size it is given"); placing
  panels among their axes in the facet, as ggplot2's `draw_panels()` does (the second panel); a
  polyline's fill (the first with area); and the plot's title.

- **The coordinate system arrives with drawing: a plot is drawn to SVG through a scene, and
  records its facet and coordinate system by name (2026-10-12, Steve).** `Giggly.to_svg/2`
  assembles a plot, renders it into a scene (`Giggly.Render`, ggplot2's rendering stage) and has
  `Giggly.SVG` draw the scene at 720 by 576 points (since given a size, see the entry beginning
  "A plot is drawn at the size it is given"); today a plot is drawn as its panel alone, each
  row a point placed by the coordinate system in a panel that fills the drawing. The plot records
  `facet: :null` and `coord: :cartesian`, which ggplot2's `ggplot()` defaults to; each is a name
  its namespace resolves to a module implementing a behaviour (`Facet.Null`, `Coord.Cartesian`),
  and a layer's `geom: :point` resolves to `Geom.Point` the same way. The assembly builds each
  panel's params last, from `Scale.dimension/1`: the axis's extent widened by ggplot2's default
  expansion (5% of a continuous range at each end, 0.6 around discrete positions 1 to n, a range
  of zero width by R's `zero_range()` widened as if its width were 1, an empty axis 0 to 1 first).
  `Coord.transform/2` rescales every x-family and y-family column into the panel by those extents
  and puts an infinite position at the edge (`squish_infinite()`). `Geom.Point` calls it, as
  ggplot2's `draw_panel()` calls `coord$transform()`, drops a row missing its x or y, and draws
  ggplot2's default point (black, size 1.5 mm, border 0.5 mm) as a circle of radius 1.95 points
  with a 0.71-point outline: the figures in ggplot2's own visual-test snapshots, reproduced from
  `.pt`, `.stroke` and R's 0.375 radius for shape 19. The scene is a table of weighted tracks
  holding one cell, the panel, placed at the layout's new `row` and `column` (ggplot2's `ROW` and
  `COL`); its primitives sit in cell units and are sized in points. SVG follows svglite (the point
  as its unit, two decimals, its circle markup) at vdiffr's 720 by 576 points, so its output can
  be set beside ggplot2's snapshots; the first golden test compares a whole document. New
  boundaries: `Coord` lists `Aesthetics` and `DataFrame`; `Geom` lists `Coord`, `DataFrame` and
  `Scene`; `Scene` lists nothing and exports `Cell` and `Points`; `SVG` lists `Scene`; `Render`
  lists `Assembly`, `DataFrame`, `Geom` and `Scene`; `Assembly` gained `Coord`. This amends the
  entry beginning "The facet assigns panels now", which kept the facet plain functions until a
  second kind. *Rejected: the coordinate system alone, its params stored for drawing to read
  later* (the plan's increment 7) — the params would be read by nothing and `transform/2` called
  only by tests. *Rejected: a public panel-params inspector as its reader* — ggplot2 has none (its
  params are opaque by contract, reachable only through `ggplot_build()`'s object), and §4 keeps
  the assembled value internal. *Rejected: `Coord` handed the family rule, or each geom naming
  its x and y columns, rather than listing `Aesthetics`* — handing the rule in moves the listing to
  `Geom`, a peer domain, and naming columns makes every geom repeat the family lists, while
  `coord_flip` needs each column's counterpart from the vocabulary anyway (that reason since gone:
  Giggly builds no `coord_flip`, see the entry beginning "Giggly follows ggplot2's current
  coordinate functions"). *Rejected: the
  expansion in the coordinate system* — ggplot2 lets a scale's own `expand` override the default,
  and `expand_range()` is R's `scales`; the coordinate system holds the widened extents.
  *Rejected: the assembly writing unit-panel positions into the tables* — whether to munch before
  transforming is the geom's call, and a path in polar coordinates could not curve. *Rejected:
  point defaults in a theme now* — ggplot2 4 takes them from the theme's `element_geom`, but the
  theme's next reader is the panel background; they sit in `Geom.Point`, where ggplot2 kept them
  before 4.0. *Rejected names:* `Display` for the stage (proposed, after Wilkinson's third stage;
  Steve preferred ggplot2's "render"), and `SVG.render/3` for the backend's function (the verb
  would name two steps; `draw/3`, after grid's `grid.draw()`). *Deferred to first reader:* axes,
  breaks, labels and extended Wilkinson; text measurement and absolute or measured tracks (each
  since built, see the entry beginning "Axes are drawn"); the
  panel background, grid lines and the theme (the theme since built, see the entry beginning "The
  theme is a resolved value"); `munch` (the first path geom); every coordinate
  option (`xlim`, `expand`, `reverse`, `ratio`, `clip`) and a scale's own `expand`; a size for
  `to_svg` (the first keyword options); splitting a layer's rows by panel (the second panel,
  where rendering's one-panel match fails loudly); clipping, cell names and spans (clipping and
  spans since built, see the entries beginning "The panel is clipped" and "The theme is a resolved
  value"); and how a
  dropped row is reported, since ggplot2 warns and a pure pipeline cannot.

- **A layer names its stat and position, and a continuous scale its transformation, the identity
  included; each is a name its own namespace resolves (2026-10-12, Steve).** `geom_point/2`
  records `stat: :identity` and `position: :identity` on its layer and `Scale.new(:continuous)`
  records `transform: :identity`, as ggplot2's `geom_point()` defaults `stat = "identity"` and
  `position = "identity"` and its continuous scales `transform = "identity"`. A discrete scale
  records none: ggplot2's has none. The assembly runs the stages where the fixed order puts them:
  each axis's scale is added after grouping, its columns are put through `Scale.transform/2`,
  trained on and mapped, and then each layer's stat (`Giggly.Stat`) and position
  (`Giggly.Position`) run. Each is a module implementing its namespace's behaviour
  (`Stat.Identity`, `Position.Identity`, `Scale.Transform.Identity`), resolved from the recorded
  name by the namespace's root; `Stat` and `Position` are boundaries listing nothing, the assembly
  lists both, and `Plot` reads a layer's names out through `layer_stat/1` and `layer_position/1`
  without listing either. Modules whose last segment repeats across namespaces are written through
  their namespace (`alias Giggly.Stat`, then `Stat.Identity`), never aliased to the tail: a second
  `alias` with the same tail replaces the first without a warning (tried). That settles §7's
  module-name question. *Rejected: the identity as the absence of a stat, a position or a
  transformation* (proposed for this increment, and how increment 5 left transforms out, in an
  aside never discussed) — an absent stat cannot be told from a forgotten one, while a recorded
  `:identity` says the choice was made and a test can assert it; the cost is stage calls that the
  mutation step reports as equivalent survivors, since removing an identity changes no output.
  *Rejected: the layer holding the modules* (ggplot2's shape: `layer()` resolves `"identity"` to
  `StatIdentity` as the layer is built) — `Plot` would name `Stat.Identity` as a value, which
  boundary does not count unless `check: [aliases: true]` is on, and listing `Stat` would let a
  plot run stats, the reason `Plot` does not list `Scale`; the question returns when a caller can
  pass `stat:`, whose misspelling must raise at the call. *Rejected: `as:` aliases* — credo's
  `AliasAs` check is enabled; *and renamed modules (`StatIdentity`)* — ggplot2 prefixes because an
  R package has one flat namespace, and module nesting does that job here. *Rejected:
  `position_jitter` as the stages' first non-identity member now* — it would bring keyword options,
  NimbleOptions' placement, the "absent" sentinel, `resolution()` and a default seed (ggplot2's
  `seed = NA` draws a fresh one per build, which a pure pipeline cannot) into a Phase 1 scatter
  plot; it belongs with stack and dodge. *Deferred to first reader:* `after_stat` (no mapping can
  be one, and no stat has defaults); the geom's setup step (the layer already records its geom,
  ggplot2's points have none, and geom modules arrive with drawing); a stat's or position's
  further arguments and its split by panel and group; a transformation's inverse, breaks, labels
  and domain (ggplot2 takes an axis's default breaks and labels from its transformation, and a
  date axis is a continuous scale with a date transformation, which is how the date columns
  refused today will be placed; the breaks and labels since built, see the entry beginning "Axes
  are drawn"); and the reset and retrain of the position scales with the second
  mapping. When the retrain arrives, a discrete scale must take mapped positions into a
  continuous range of its own, never its levels — `Scale.Discrete.train/2` would turn
  `["4", "6"]` into `[1, 2, "4", "6"]` today — and ggplot2 clears only that range on reset,
  keeping the levels (`ScaleDiscretePosition$reset`). Increment 5 deferred that range to "the first
  continuous value on" a discrete axis; the reason was incomplete, since the second training puts
  mapped positions there on every discrete axis. For points it spans 1 to n, inside the expanded
  level range, so it changes nothing the coordinate system builds until a mark lands off the
  integer positions. And when a stat first supplies an aesthetic, a geom's required aesthetics
  must be checked after the stat, as ggplot2's `compute_geom_1` does, not only at the geom call.

- **Mutation testing picks each mutant's tests by coverage, and reports in JSON (2026-10-12,
  Steve).** The review runs `mix muex` with `--coverage-guided --format json --output` added: each
  test file runs once under `:cover`, each mutant then runs exactly the test files that execute its
  line, and a line no test executes is reported as an uncovered mutant, a fourth kind of finding.
  The JSON report gives each mutant its status, location, test files, and the mutated node before
  and after. *Rejected: muex's default selection* — it scans test sources for module names,
  misses a grouped alias and a `doctest` line, and runs only the linked files when there are any,
  so `Plot`'s mutants never ran against `giggly_test.exs` and a mutant of `computed_mapping/2`
  "survived" a test that catches it; trialled on `plot.ex`, coverage selection removed that
  survivor and one other, took about as long (412 s), and found `Plot.new/1` unexecuted.
  *Rejected: writing tests so the scan sees them* (single-module aliases, a call per module) — the
  suite's style would bend to a tool's parser and still miss `doctest`. *Rejected: the terminal
  report* — it gives only a count of uncovered mutants.

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
  need:* user scale functions and their options (so NimbleOptions and the "absent" sentinel),
  transforms (identity is their absence; since amended — a continuous scale records the identity,
  see the entry beginning "A layer names its stat and position"), expansion and the view scale
  with the empty-axis default (the coordinate system; expansion and the empty axis since built,
  in `Scale.dimension/1`, see the entry beginning "The coordinate system arrives with drawing"),
  breaks, labels and extended Wilkinson (the
  axes), a discrete axis's continuous range (the first continuous value on one; that reason since
  corrected in the same entry), the second training (stat and position), and the layout's `row`
  and `col` (the scene; since built as `row` and `column`, read by rendering).

- **The facet assigns panels now; the layout table arrives with scale training; one plain
  function until a second facet (2026-10-12, Steve; since amended — the plot records its facet by
  name and `Facet.Null` implements a behaviour, see the entry beginning "The coordinate system
  arrives with drawing").** `Giggly.Facet.assign_panels/1`
  (ggplot2's `FacetNull$map_data()`) runs first in the assembly and puts `panel = 1` on every row
  of the plot's data, which evaluation carries into every layer frame, ordered as ggplot2 orders
  them: aesthetics, `panel`, `group`. Checked against `R/facet-null.R`, `R/facet-.R`
  (`layout_null()`) and `R/layout.R`. *Rejected: the layout table now* (the Phase 1 plan's draft)
  — its `scale_x`/`scale_y` columns are first read by scale training (increment 5), which routes
  each panel's rows to a scale through them, and its `row`/`col` by the scene (increment 8);
  built now, nothing would read it. *Rejected: a facet behaviour, a `facet` field on the plot and
  dispatch now* — with one kind of facet there is nothing to dispatch on; `facet_wrap` brings
  them, touching only `Plot`, `Facet` and the assembly, never a geom. *Rejected: a mutable
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
  first module lands: `Aesthetics` lists nothing, `Group` lists `DataFrame`, `Plot` lists
  `Aesthetics` and `DataFrame` and exports `Layer`, `Assembly` lists `Plot`, `DataFrame` and
  `Group` (each list has grown since, with its domains' needs, and `Plot` now exports nothing —
  `mix boundary.spec` prints the current graph); to come, `Scale` lists nothing (so it stays extractable) and the SVG backend lists only
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
  triaged, not scored (2026-10-11, Steve; since amended — tests are picked by coverage, see the
  entry above).** `elixir-code-review` runs `mix muex --no-optimize
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

- **2026-10-13 — `to_svg/2` draws at a size in pixels, 700 by 433 by default.** In Livebook the
  first notebook's labels, titles and points looked tiny: every plot was drawn at vdiffr's 10 by 8
  inches, larger than ggplot2's reference pages draw at, and Livebook shrank it to fit. The §4
  entry beginning "A plot is drawn at the size it is given" gives the three choices, each Steve's
  as recommended: pixels, ggplot2's reference size as the default, and NimbleOptions from the root
  boundary, its first use and a new dependency (`nimble_options` 1.1.1; the lock gained only its
  line). The golden passes vdiffr's size and is unchanged; the empty-plot test draws at the
  default and pins it; a new test pins a misspelt option's refusal, which, with the validation
  replaced by merging defaults in a scratch run, failed.

- **2026-10-13 — The first notebook: `geom_point`.** `notebooks/geom_point.livemd` follows
  ggplot2's `geom_point()` reference page example by example, and `Giggly.Datasets.mtcars/0`
  gives its data. The §4 entry beginning "The notebooks follow ggplot2's reference pages" gives
  the decisions, each Steve's: every example, no ggplot2 drawings, a datasets module, and R's file
  read at compile time. Two of the page's examples draw today: the scatter plot of `wt` against
  `mpg`, and the same with four cars' `mpg` blanked, the rows R's `set.seed(1)` blanks, found by
  running R; both match ggplot2's drawings of the same code in every element (76 and 72). The
  others wait for mapped and fixed aesthetics, other shapes, legends, scales set by hand, the
  `diamonds` dataset and `na.rm`. The notebook's cells were run in order, as Livebook runs them.
  The local `livebook` escript was built with Elixir 1.14 and needs reinstalling to run Giggly,
  which requires 1.20.

- **2026-10-13 — Phase 1 audited: the scatter plot is architecturally complete.** Phase 0 asked
  for a scatter plot with every seam in its null form, so that Phase 2 (`facet_wrap` with free
  scales, `coord_flip`, polar coordinates) lands without touching a geom. Built: the null facet
  assigning `panel` to the raw data and laying out panels with scale ids; grouping; the identity
  stat and position; one continuous and one discrete position scale that know no pixel; the
  cartesian coordinate system as the only route to the unit panel (`transform/2`, `axes/1`,
  `grid/1`, `clip/1`); points; the scene's table and SVG; text measurement; and, beyond the
  list, axes, titles, a resolved theme, the panel's background and grid, and clipping. The geom
  test holds: `Geom.Point` reads only `Coord.transform/2` and the placed `:x` and `:y`, so
  `coord_flip` (ggplot2 relabels x and y before its transform, and `Coord.axes/1` already names
  the aesthetic each side shows) and polar coordinates (another transform) change no geom. What
  Phase 2 changes instead, each already marked where it fails loudly or recorded as deferred: the
  facet's callbacks take no parameters and the plot records a bare name, while `facet_wrap` needs
  its variables, free scales and layout; the assembly matches exactly one scale per axis, where
  free scales route each panel's rows to its scale id; rendering matches exactly one panel and
  hands each layer's whole frame to its geom, and `Giggly.DataFrame` has no operation yet to split
  rows by panel; the scene and SVG allow exactly one `:rest` column and row, where panels share
  the rest, and polar's fixed aspect ratio needs the scene to keep a cell's proportions; the
  guide draws straight axes only; and the theme grows strip and spacing elements. The first
  increment of Phase 2 also brings the first public options (`facet_wrap()`'s, `coord_polar()`'s),
  and with them NimbleOptions' placement, §7's "absent" question and a misspelt name raising at
  the call. Two items of the synthesis's Phase 1 remain deferred to Phase 3 readers, as recorded
  in §4: `munch`, which the first path geom calls, and a discrete scale's continuous range, which
  jitter and bars need; and a stat or position is handed no scales or panel until the first one
  that computes.

- **2026-10-13 — The panel is clipped to its edges.** What is drawn in the panel is now cut off
  at its edges, as ggplot2 cuts it, so a point at an infinite position shows only its inner half.
  The §4 entry beginning "The panel is clipped to its edges" gives the shape and how the decision
  moved: Steve chose the coordinate system's recording it, then, asked how I felt about rendering
  listing `Coord` to read it, agreed to the assembly carrying it instead. Flagged as a separate
  task during increment 9 and done here, after the zero-width fix. The golden gained svglite's
  clip markup around the panel, byte for byte what svglite writes for ggplot2's drawing of the
  same plot, and a point at infinity gets ggplot2's clip id with the edge circle inside it.
  Review's mutation step (1,442 mutants over the six changed files) left no line unexecuted and,
  on the changed lines, only reordered keys, one-row ranges' ends swapped and the left title's
  cell widened rightward, which draws the same. No boundary changed.

- **2026-10-13 — An axis of one huge value is drawn at the panel's middle.** A single value from
  about 1e15 up crashed `to_svg/1`, a division by zero in the coordinate system, and one from about
  4.5e11 up drew its tick at the panel's left edge, where ggplot2 draws it in the middle. The §4
  entry beginning "An axis whose extent is zero wide" gives the fix and what was rejected; Steve
  chose it over ending the crash alone. Flagged as a separate task during increment 8 and done
  here. Checking the fix against ggplot2's drawings of single values of 1e12 and 1e16 found a bug
  in the previous commit's grid: each line's ends were rescaled on its own axis's extent, which
  gives the same 0 and 1 for every extent but one of equal ends. Both drawings now match ggplot2's
  in every element but the tick's label. Review's mutation step (610 mutants over `Scale`,
  `Coord` and `Coord.Cartesian`) left no line unexecuted and only equivalent survivors on the
  changed lines.

- **2026-10-13 — The panel's background and grid lines (Phase 1, ninth increment, second of two
  steps).** The panel is drawn grey with white grid lines, major ones at each axis's breaks and
  minor ones between them, under the points. The §4 entry beginning "The panel's grid lines are
  placed" gives the shape, what was rejected and what waits. A continuous scale now gives minor
  breaks (`Scale.minor_breaks/3`, the transformation's new `minor_breaks`, and
  `Scale.MinorBreaks`, a port of R's `regular_minor_breaks()`), the assembly hands them to the
  coordinate system, `Coord.grid/1` places the lines, and the new `Guide.Grid` draws them with the
  panel's background, which the theme gained with the grid's two looks; a rectangle's border can
  now be `:none`. Every expected value in the new examples came from R, run in Docker; one
  example, breaks 0.1, 0.7 and 1.3, was chosen because only R's way of finding a gap's middle
  gives 0.4 there, and swapping in the plain mean failed it. The golden now matches ggplot2's own
  drawing of the same plot in all 49 elements the comparison in `test/golden/point.R` reads. A
  plot with no layers now draws the panel's background inside the margin, and still no axes.
  Review's mutation step (2,112 mutants over the fourteen files this step changed) left no line
  unexecuted, and on this step's lines only equivalent survivors: reordered keys, a one-row
  range's ends swapped, and arguments swapped in clauses that ignore all of them. Credo asked for
  two changes on the way, an alias order and a single-item append rewritten as a final chunk. No
  boundary changed.

- **2026-10-12 — The theme and the plot's background (Phase 1, ninth increment, first of two
  steps).** A plot records `theme: :gray`, `Giggly.Theme` resolves it into the complete theme,
  and everything drawn other than the marks takes its look from it: the axes' ticks, labels and
  titles, the plot margin, and the plot's new white background, drawn first over the whole
  drawing. The §4 entry beginning "The theme is a resolved value" gives the shape, what was
  rejected and what waits. The scope was settled one decision at a time before any code: the
  theme a resolved value nobody can set yet, the point keeping its own look (Steve agreed, over
  the plan's note that it would move now), `Coord.grid/1` for the second step's grid lines,
  `:gray`, clipping as a step of its own after this increment (flagged as a separate task: a point
  at an infinite position is drawn half over the axis today, where ggplot2 clips it), and the R
  script kept beside the golden. Preparing the proposal found that Docker's `r-base` installs
  ggplot2 and vdiffr, so ggplot2 can draw the golden's own plot with no title row, and that
  today's golden already matched ggplot2's `theme_test()` drawing of it in every point, tick and
  label; increment 8's check had used the nearest snapshot, drawn in another theme with a title,
  and carried a caveat for it. The panel's background moved from this step into the second, so
  the grid's drawing module arrives whole. After this step the golden gained one line, the
  plot's background, identical to ggplot2's; what ggplot2 draws and the golden does not is the
  panel's background and its twenty grid lines. Review's mutation step (1,897 mutants over the
  eleven changed files) left no line unexecuted; on this step's lines its survivors were the two
  new `use Boundary` lines, which the waiver gate stops being deleted, reordered keys, a
  one-row range's ends swapped, and the left title's cell widened rightward, which draws the same
  since the turned title hangs from its cell's left edge. The area got `.claude/rules/theme.md`
  and a status-map line; the boundary changes were shown to Steve and approved before they were
  written.

- **2026-10-12 — Axis titles (Phase 1, eighth increment, second of two steps).** Each axis is
  titled by the first layer to map it, and the title is drawn beside its axis: "wt" below the x
  axis, "mpg" turned beside the y axis. The §4 entry beginning "An axis is titled" gives the rule,
  what was rejected and what waits. It was built to the design agreed in the first step's
  discussion, with two choices of mine reported rather than asked: the assembly's field is
  `titles`, since "labels" now means a break's text, and `Coord.axes/1` says which aesthetic each
  side shows. The golden gained the titles and now matches ggplot2's snapshot element for
  element wherever the snapshot's plot title does not move the panel's top. Review's mutation step
  (1,552 mutants over the eight changed files) left no line unexecuted; on this step's lines its
  survivors were reordered struct and map keys, and two real ones. The rule's branch for a layer
  that does not map the aesthetic could not be reached, since every point layer maps both, so the
  rule now takes the first layer and fails loudly otherwise. And the size of an axis with no
  breaks and of a title of `:none` were unpinned: `Guide.axes/1`'s doctest had pinned the first,
  and I deleted it when the function gained the titles, judging a test of a plot with no layers to
  cover it, but such a plot draws nothing, so no size shows. The doctest came back for
  `Guide.axes/2` and pins both. A confirming run over `Assembly` and `Guide` (894 mutants)
  killed both size mutants and left on this step's lines only reordered keys and a `to_string/1`
  that changed nothing, since the plot already holds each mapping's column by its name; it was
  removed.

- **2026-10-12 — Axes (Phase 1, eighth increment, first of two steps).** A plot is drawn with
  its axes: a tick and a label at each break, the x axis below the panel and the y axis to its
  left, inside ggplot2's plot margin. `Scale.breaks/2` gives each axis's breaks (extended
  Wilkinson and Elixir-style labels for a continuous axis, levels for a discrete one), the
  coordinate system places them (`Coord.axes/1`), the new `Giggly.Guide` draws them and the new
  `Giggly.Font` measures their labels; the scene gained sizes in points, `:rest`, `Text` and
  `Polylines`, and SVG lays the table out. The §4 entry beginning "Axes are drawn" gives the
  shape, what was rejected and what waits. The scope was settled one decision at a time, before
  any code. Steve chose labels written as Elixir writes numbers over R's `format()`, `NA` over
  `nil` for a missing level, the glyph table as a file over a heredoc, axis titles in this
  increment rather than after the background, and two steps, axes then titles; he called one
  proposed decision (how the scene holds measured sizes) no decision at all, since its
  alternatives were strawmen. Before proposing, ggplot2's, scales', labeling's and vdiffr's
  sources were read and the snapshot's geometry worked through: the two findings in §4 (vdiffr's
  glyph table, TeX points) account for every number in `coord-cartesian/expand-range.svg`'s axes
  to the hundredth. The golden now draws that snapshot's axes, x 0 to 10 and y 0 to 50, and its
  ticks, labels and label widths match the snapshot measured from the panel's edges. Review's
  mutation step ran three times. The first (3,102 mutants over the seventeen changed files) left
  308 alive and 25 on lines no test ran. 168 of the survivors were in `Scale.Breaks`, 37 of them
  on the one line giving the bonus for a sequence through zero: its examples, the break sets
  ggplot2's snapshots show, were all correct, but no scoring term decided their winners. R was
  run in Docker (`r-base`, R 4.6.1, labeling 0.4.3) and matched the port exactly on 813 ranges,
  random and degenerate, and the port's test became a table of R's output for the shortest range
  found for each of the 46 winning combinations of nice number, skip, count and zero bonus. The
  same run found the censoring's inclusive ends and SVG's escaping of `&`, `<` and `>` unpinned
  (examples and a test added), the reversed-range clause copied from R unreachable (removed),
  `Labels.numbers/1` with no breaks and `Guide.axes/1` with an axis of none unexecuted (examples
  added), conversions and an `abs/1` that changed nothing (removed), and SVG sharing the leftover
  space by weight when every scene has one weighted column and row of weight 1 (the scene's
  `{:null, weight}` became `:rest`, one of each, and any other shape is refused). The second run
  (2,087 mutants over the seven files the fixes touched) left nothing unexecuted and 75
  survivors in `Breaks`; applied one at a time to a scratch copy, 66 matched R on all 813 ranges
  (pruning that only shortens the search, constants shifting every score alike, swapped
  arguments to symmetric functions) and 9 did not, so the seven ranges where those first depart
  joined the table with R's breaks. It also showed that 16 significant digits, not 15, would
  print rounding noise in 131 of R's 813 break sets (an example now pins it), and that the `nil`
  level I had taken out of `Scale.breaks/2`'s example as a duplicate of `Labels.levels/1`'s was
  the only pin on its call to that rule (restored). A third run (1,344 mutants over `Breaks`,
  `Labels` and `Scale`) showed two of the departing variants still alive, since one line held
  three candidate literals each departing on a range of its own (both ranges added), and that
  nothing pinned how many digits a genuine break keeps: Erlang's `float_to_binary/2` reads a
  negative precision as its default, so `1 - 15` survived as seven digits, and 14 survived for 15
  (an example with a break needing all fifteen added). After that, every remaining `Breaks`
  survivor either matches R on all 813 ranges or fails the table, and a last run over `Labels`
  (126 mutants) left only a fallback's unused value and `max/2`'s arguments swapped. The areas got
  `.claude/rules/font.md` and `guide.md` with status-map lines, and CLAUDE.md's scene line no
  longer says "tracks". The boundary changes were shown to Steve and approved before they were
  written; the `CorePurity` waiver carries the reason Steve agreed in conversation.

- **2026-10-12 — The coordinate system, drawn: `Giggly.to_svg/1` (Phase 1, seventh increment).**
  A plot is now drawn to SVG: the assembly builds each panel's params from `Scale.dimension/1`,
  `Giggly.Render` has each layer's geom draw its rows through `Coord.transform/2` into a
  one-cell scene, and `Giggly.SVG` draws the scene at 720 by 576 points. The plot records
  `facet: :null` and `coord: :cartesian`, and the layout gained `row` and `column`. The §4 entry
  beginning "The coordinate system arrives with drawing" gives the shape, what was rejected and
  what waits. The scope changed in discussion before any code. The plan had the coordinate system
  alone, with drawing in increments 8 and 9; since nothing but drawing reads it, Steve chose the
  thinnest slice that draws, folding the scene and SVG in for points only, and recording the
  facet beside the coordinate system by the rule increment 6 set. Steve asked what the
  coordinate system needs that the assembly does not already hold (nothing: the trained scales,
  the layout and the tables carry it all, and what it adds is the expansion and the rescale),
  and why it should list `Aesthetics` (for `transform/2`'s family lookup alone); it lists it.
  He preferred ggplot2's "render" to `Display` for the stage, and the SVG function became
  `draw/3` so one verb does not name two steps. The proposal said a single-valued axis widens by
  ±0.5; R's `expand_range()` treats it as width 1, so 5% gives ±0.05, which is what was built.
  ggplot2's own visual-test snapshots settled the point's look (radius 1.95, outline 0.71, both
  reproduced from its constants) and the canvas (vdiffr's 720 by 576 points). Review's mutation
  step (coverage-guided, over the fifteen changed files) found no line unexecuted and three
  holes, each fixed: a single value of 0 (the `zero_range()` clause for equal ends survived
  deletion, since the example's 2.5 was answered the same by the tolerance clause, and an
  all-zero axis would have had no width); the tolerance's being relative (the example sat where
  relative and absolute agree); and `SVG`'s sharing of the drawing among weighted tracks and its
  cell lookup, which no scene of one cell could exercise and which now accepts the one-cell scene
  alone, failing loudly otherwise, as rendering does with a second panel. A geom test pins a
  point dropped for a missing x, the doctest of `Coord.transform/2` gained `:nan`, and the golden
  carries its label. The areas got `.claude/rules/coord.md`, `geom.md`, `render.md`, `scene.md`
  and `svg.md`, with status-map lines.

- **2026-10-12 — The stat, position and transform stages (Phase 1, sixth increment).** Each
  layer now records `stat: :identity` and `position: :identity`, and each continuous scale
  `transform: :identity`; the assembly adds each axis's scale before putting its columns through
  the scale's transformation, then trains, maps, and runs each layer's stat (`Giggly.Stat`) and
  position (`Giggly.Position`). The §4 entry beginning "A layer names its stat and position" gives
  the shape, what was rejected and what was deferred. The scope changed in discussion before any
  code. The proposal was to build nothing, treating the identity stat and position as absences;
  Steve kept them as recorded values, since an absent stat cannot be told from a forgotten one,
  and extended the rule to transforms, where "identity is their absence" had been an aside in
  increment 5's deferral list, never discussed. The reset and retrain that the plan put in this
  increment was deferred with `after_stat` and the geom's setup step: it is not something a plot
  records, and it gives the same scales for every plot until a stat computes. Checking ggplot2's
  source for it showed that retraining a discrete scale today would put mapped positions among
  its levels, and corrected increment 5's reason for deferring a discrete axis's continuous range;
  both are in §4. §7's module-name question was settled (alias the family, write
  `Stat.Identity`), and CLAUDE.md's naming rule now says so. `Stat` and `Position` are new
  boundaries listing nothing, and `Assembly` lists both; the change was shown to Steve in plain
  language and his approval recorded with `waiver-gate.sh approve-widening`. The areas got
  `.claude/rules/stat.md` and `position.md`, with status-map lines. Review's mutation step
  (coverage-guided, over the twelve changed files) found no line unexecuted, and its only
  survivors in the new code were the expected ones: dropping the stat or the position stage, which
  an identity makes equivalent by design; reordered struct keys; and `Enum.uniq()` on a layout of
  one row. Its other survivors are in code from earlier increments.

- **2026-10-12 — Code review's mutation step picks tests by coverage.** `--coverage-guided` and a
  JSON report were added to the procedure in `elixir-code-review`'s `mutation-testing.md`, which
  now also treats a line no test executes as a finding (§4, the entry beginning "Mutation testing
  picks each mutant's tests by coverage"). Found while triaging increment 5: a survivor
  contradicted a test that existed, and the report's per-survivor "Test files" showed muex had not
  run it. This copy of the skill now differs further from Tack's.

- **2026-10-12 — Position scales (Phase 1, fifth increment).** `Giggly.Scale` with
  `Scale.Continuous` and `Scale.Discrete`; `Facet.layout/0`; two new assembly stages, training and
  mapping; `%Giggly.Assembly{}`; and `Giggly.panel_scales/2`. `layer_data/2` now shows a discrete
  x at its level positions, as ggplot2's `get_layer_data()` does. The §4 entry beginning "Position
  scales are chosen by column type" gives the shape and what was deferred. The proposal named
  `Plot` and `Group` gaining `Scale`; writing it showed the assembly needs `Scale` and
  `Aesthetics` too (which columns are an axis's is `Aesthetics.family/1`'s answer). Reviewing the
  four, Steve took `Scale` out of `Plot` and `Group`: the axis checks moved into the assembly, and
  grouping is handed its order; only the assembly's two widenings remained. The area got `.claude/rules/scale.md` and a
  status-map line. Increment 6 (the coordinate system) would have no reader until drawing, and
  Steve moved the stat and position stages ahead of it, so the stages are built in the order the
  pipeline runs them. (The reason first offered — that they show in `layer_data` — was wrong: the
  identity stat and position leave the layer tables unchanged, so they have no reader before
  drawing either.) Review's mutation step found the type-to-kind
  table pinned only for floats and strings (a mutant dropping `:integer` from it survived), a
  continuous range whose first value had never been `nil` (dropping `widen`'s number guard would
  have made the range `{nil, nil}`), the scale check unexercised for a layer remapping an axis and
  for `group` on a date column, and the fallback for an axis no layer maps unpinned; each got an
  example or a test. It also showed "a layer's mapping laid over the plot's" written in three
  places, a mutant surviving in an untested copy; the rule became `Plot.computed_mapping/2`
  (ggplot2's name), and `Plot` stopped exporting `Layer`, which nothing outside it reads any more.
  ggplot2 gives a plot with no layers a blank layer that inherits the plot's mapping, so its axes
  span the mapped columns; here they are untrained until a geom that draws nothing arrives. A
  later run showed muex choosing each mutant's tests by scanning test files for module names: it
  misses a grouped `alias Giggly.{DataFrame, Plot}` and a `doctest` line, and a module linked to
  some test files runs only those, so `Plot`'s mutants never ran against `giggly_test.exs` and a
  mutant of `computed_mapping/2` "survived" a test that catches it. Run with `--coverage-guided`,
  which picks each mutant's tests by the lines they execute, that survivor and one other went,
  and the run reported the one line no test executes: `Plot.new/1`, the plot with no mapping of
  its own, whose doctest now shows it. Whether the review procedure switches to coverage-guided
  selection is Steve's call.

- **2026-10-12 — Staging no longer invalidates a recorded boundary approval.** The waiver gate
  hashed the changed files' declarations in `git status` order, which lists an untracked file
  after every tracked one and a staged new file in path order; so staging alone reordered the
  list, and the commit of the restructure above was refused under an approval recorded minutes
  before, with no declaration changed. `widening_state` now sorts the paths first, as
  `commit-gate.sh` already sorts its marks'. Proved in a throwaway clone with a new declaring
  file sorting ahead of an edited one: before the fix, approving and then staging failed the
  commit check; after it, approving before or after staging passed, and widening a list after
  approving still failed. Changing the hash meant re-recording the standing approval for this
  increment, whose declarations had not changed. This copy of the hook now differs from Tack's.

- **2026-10-12 — Panels (Phase 1, fourth increment).** `Giggly.Facet.assign_panels/1` puts a
  `:panel` column of 1s on the plot's data, first in the assembly, and every layer frame now
  reads `aesthetics…, :panel, :group`; `layer_data/2`'s doctest shows it. The §4 entry beginning
  "The facet assigns panels now" gives the scope: the layout table was moved to increment 5,
  where scale training is its first reader, and there is no facet behaviour until `facet_wrap`.
  `Facet` lists `DataFrame` and `Assembly` gained `Facet`; both widenings were in the agreed
  proposal. The area got `.claude/rules/facet.md` and a status-map line.

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
- **Livebooks that match ggplot2's online reference (Steve's aim, 2026-10-12).** A set of
  Livebooks reproducing the examples in ggplot2's documentation, which ExDoc points at rather than
  building graphics, as ggity's docs did. The first, `geom_point`, is built, and how notebooks are
  made is settled (the §4 entry beginning "The notebooks follow ggplot2's reference pages"). Still
  open: which pages follow, and a side quest, a Kino library so a plot value draws itself in a
  cell (Livebook shows the SVG with `Kino.Image` until then), as an optional dependency or a
  package of its own like `kino_vega_lite`, settled when it is built.
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
