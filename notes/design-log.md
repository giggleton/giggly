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

- **A discrete scale carries its missing value as a field, `na_value`, as ggplot2's scale carries
  `na.value` (2026-10-16, Steve).** A missing level takes no share of the palette and maps to it:
  grey50, `#7F7F7F`, for colour and fill, `nil`, R's `NA`, for alpha and a position, which places
  `nil` as its last level instead. `Scale.Discrete` is API, so the field is too; `Scale.Continuous`
  gains it with the continuous colour scale, the first to need grey50. *Rejected: the palette
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
  `key_glyph`, colour on lines, `scale_x_date()`'s options, `economics_long`, radial bars.

- **Guides become structs of their kind behind a protocol in the increment that brings a second
  kind, expected to be colour (2026-10-16, Steve, agreeing the proposal).** ggplot2 makes each
  guide an object of its kind (`GuideLegend`, `GuideColourbar`, `GuideNone`, the axes), chosen per
  aesthetic, and runs every guide through one lifecycle: extract the key, merge, take the layers'
  keys, draw, pack the guide box. Giggly already runs a legend through those stages as plain
  functions, its kind fixed (`legends/3` in the assembly, `draw_legend/2` in rendering). Then each
  kind becomes one module holding its struct (its options), key and drawing, behind a protocol at
  `Giggly.Guide`: a build function the assembly calls, a drawing one rendering calls; glyphs stay
  on `Geom.draw_key/3`. Merging groups guides by order, kind, title and labels, each kind merging
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
  fitted. Each geom draws its own key (`Geom.draw_key/3`), as ggplot2's `draw_key` does.
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
  needs; `position_fill`; user-written `after_stat()`; `geom_bar`'s options; histograms.

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
  `Plot.facet_wrap(plot, facets, options)` with `facets` a column or a list of them, resolved at
  the call as a mapping is, and `nrow:` and `ncol:` validated by NimbleOptions, which `Plot` will
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
  is a protocol (`Giggly.Geom` with `draw_panel/4`; `Giggly.Stat` and `Giggly.Position` with
  `compute_layer/2`; `Giggly.Facet` with `layout/1` and `assign_panels/2`; `Giggly.Coord` with
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
  match in `complete/1`, so no one could add a theme by implementing it. `theme_gray()`'s
  derivation is now the private `gray/0` in `Giggly.Theme`, called by `complete(:gray)`; it
  becomes public with the first theme a user can choose. *Rejected: keeping the behaviour for
  uniformity* — the rule is that a behaviour serves kinds that differ in behaviour, and plain
  functions serve kinds that differ in data. *Deferred to the first theme setting a user can
  make:* the plot holding the theme's value, or the call that builds it, rather than its name,
  once a theme takes arguments.

- **The scene's circle primitive is `Circles`, not `Points` (2026-10-14, Steve).** The scene names
  its primitives after grid's, and this one holds positions and one radius, grid's
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
  transformation's inverse and domain (the first transformation that is not the identity); the
  axis line (blank in `theme_grey()`); axes above or to the right, and
  secondary axes; angled, dodged or thinned labels; a scale's `breaks:`, `labels:` and
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
  first reader:* `after_stat`; a stat's or position's further arguments; and a transformation's
  inverse and domain.

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
  need:* user scale functions and their options (so NimbleOptions and the "absent" sentinel).

- **The facet assigns panels first; the layout table arrives with scale training (2026-10-12,
  Steve).** The facet runs first in the assembly and gives every row of the plot's data its panel,
  as ggplot2's `map_data()` does (`panel = 1` without a facet), which evaluation carries into every
  layer frame, ordered as ggplot2 orders them: aesthetics, `panel`, `group`. Checked against
  `R/facet-null.R`, `R/facet-.R` (`layout_null()`) and `R/layout.R`. *Rejected: the layout table
  now* (the Phase 1 plan's draft)
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
  (2026-10-12, Steve).** `Giggly.Plot.new/2` reads the `Table.Reader` into a frame; `new/2` and
  each geom function resolve their mapping against it, raising `ArgumentError` that names the
  aesthetic, the reference as written and the data's columns; a layer's mapping is checked with
  the plot's as the layer is added. ggplot2 converts its data at construction too (`fortify(data)`
  in `ggplot.default`, `R/plot.R`, and again in `layer()`); only expression evaluation waits for
  the build.
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

- **Mutation testing runs in code review, with muex, over the changed files; survivors are
  triaged, not scored (2026-10-11, Steve).** `elixir-code-review` runs `mix muex` with the flags
  its mutation-testing reference gives over the changed `lib/` files, as one comma-separated
  `--files`, and its report says of each survivor whether it is a missing test, unreachable or
  redundant code, an equivalent mutant, or the wording of a message whose datum the tests assert —
  and why. *Rejected: hand-picked mutants* — chosen by
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
  Steve).**
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

- 2026-10-17 — Draw guides through a protocol at Giggly.Guide (colour, step 3a); §4: "The guide
  protocol sits at `Giggly.Guide`"
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

- **The datasets should carry R's column types (found 2026-10-15).** Bars follow R's
  `resolution()`, which gives an integer column bars 0.9 wide; Giggly's `mtcars` reads `cyl` and
  `gear` as integers where R stores doubles, so its bars are 0.9 wide where ggplot2's are 1.8.
  Reading them as floats would label them `4.0` where R writes `4`, so it waits for labels that
  print whole floats as R does.
- **How a public option says "absent".** CLAUDE.md's sentinel rule (`:none`, never `nil`) came with
  the harness. ggplot2 separates "remove this" (`breaks = NULL`, `guide = "none"`) from "use the
  default" (`waiver()`), and ggity spelled them `nil` and `:waivers`. Unresolved: the atoms Giggly's
  options use for each, and whether `nil` is acceptable at the public API while `:none` stays the
  internal sentinel. Settled by the first scale options that need both (`breaks:`, `labels:`). The
  first public "remove this" is `colour: :none` and `fill: :none`, ggplot2's `NA` (2026-10-16,
  Steve, with the colour increment).
- **Livebooks that match ggplot2's online reference (Steve's aim, 2026-10-12).** A set of
  Livebooks reproducing the examples in ggplot2's documentation, which ExDoc points at rather than
  building graphics, as ggity's docs did. `geom_point` and `facet_wrap` are built, and how notebooks are
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
