---
paths:
  - "lib/giggly/plot.ex"
  - "lib/giggly/plot/**"
  - "test/giggly/plot_test.exs"
---

# The plot and its API

`Giggly.Plot` is the public pipe API and the plot value it builds; `Giggly.Plot.Layer` is one
layer of that value. Why the API is shaped this way, and what was rejected: design-log §4, the
entries beginning "The public pipe API lives in", "A plot is a value built by", "The table is
read when the plot is created", "Points accept only what Phase 1 can draw", "A layer names its
stat and position" and "Each facet, coordinate system, geom, stat and position is a struct".

## Rules

- **A plot describes and runs nothing.** `Plot` builds the value; running it — assembling,
  inspecting, drawing — is the functions in `Giggly`. Its boundary lists `Giggly.Aesthetics`,
  `Giggly.DataFrame`, `Giggly.ColorOperations`, which reads a colour an option sets,
  `Giggly.Mapping`, whose checks resolve each mapping value at the call, the five
  families whose kinds it builds (`Giggly.Coord`, `Giggly.Facet`, `Giggly.Geom`,
  `Giggly.Position`, `Giggly.Stat`), `Giggly.Guide`, whose legend's struct `guide_legend/1`
  builds, `Giggly.Scale`, whose `Continuous` and `Discrete` structs it writes and whose
  `Discrete.key/1` it reads to refuse a discrete value named twice, and `Giggly.Theme`, whose tree
  `theme/2` builds its schema from and whose `merge/2` it calls, and exports nothing beyond
  `Plot`.
  **`GigglyCredo.Check.PlotRunsNothing` keeps those families' roots, the protocols that compute
  and draw, every `Giggly.Guide` module holding no struct, which draw, and `Giggly.Scale`'s root,
  which trains and maps, out of its files** — no call, no module passed as a value, no `import` —
  which boundary cannot, since a boundary always exports its root and every export to all its
  dependents (design-log §4, the entry beginning "`Plot` lists `Giggly.Guide`"). A plot writes a
  scale and never runs one.
- **The API is `new/2`, the geom functions (`geom_histogram/3`, `geom_freqpoly/3` and
  `geom_boxplot/3` among them), `stat_sum/3`, `stat_bin/3`, `annotate/3`, the facet functions
  (`facet_wrap/3`), the coordinate functions (`coord_radial/1`), the scale functions
  (`scale_x_continuous/2`, `scale_y_continuous/2`, their `_log10`, `_sqrt` and `_reverse` shortcuts,
  `scale_x_discrete/2`, `scale_y_discrete/2`, `scale_x_date/2`, `scale_y_date/2`, the colour scales
  `scale_color_manual/2`, `_hue`, `_gray`, `_discrete`, `_viridis_d`, `_gradient`, `_gradient2`,
  `_gradientn`, `_continuous` and `_viridis_c`, each with its `scale_fill_` twin,
  `scale_alpha_continuous/2`,
  `scale_alpha_discrete/2`, the size scales `scale_size_continuous/2`, `scale_size_area/2`,
  `scale_radius/2` and `scale_size_discrete/2`, the shape scales `scale_shape_discrete/2` and
  `scale_shape_manual/2`, the line type scales `scale_linetype_discrete/2` and
  `scale_linetype_manual/2`, the line width scales `scale_linewidth_continuous/2` and
  `scale_linewidth_discrete/2`, `xlim/3`, `xlim/2`, `ylim/3`, `ylim/2`, `lims/2`),
  the guide functions (`guides/2`, `guide_legend/1`), `position_dodge2/1`, `labs/2` and
  `theme/2`.**
  `computed_mapping/2`, `mapping_order/2` and the `layer_*` accessors (`layer_table/2` the table a
  layer draws, `layer_annotation?/1` whether it is an annotation) exist for the assembly and are
  `@doc false`, and `Layer` is `@moduledoc false`; an API type names no hidden one (`aesthetic`, not
  `Aesthetics.name/0`). An example in the docs shows what a user sees, through `Giggly.layer_data/2`
  or the drawing `Giggly.to_svg/2` makes, never a layer's or a kind's struct.
- **No function ggplot2 has superseded or deprecated becomes API**; Giggly offers its replacement
  alone, `labs()` and never `xlab()` (design-log §4, the entry beginning "Giggly exposes no
  function").
- **A kind is named after ggplot2's ggproto class without its family prefix, and a class ggplot2
  keeps only as an alias is not a kind:** `geom_col/3` records `%Geom.Bar{}` with
  `%Stat.Identity{}` and `%Position.Stack{}`, as ggplot2's `GeomCol` is an empty `GeomBar`, and
  `geom_count/3` and `stat_sum/3` both `%Geom.Point{}` with `%Stat.Sum{}` and
  `%Position.Identity{}`, and `geom_histogram/3` and `stat_bin/3` both `%Geom.Bar{}` with
  `%Stat.Bin{}` and their position, `:stack` unless `position:` says otherwise, and
  `geom_freqpoly/3` `%Geom.Path{}` with `%Stat.Bin{pad: true}` and `%Position.Identity{}`, as
  ggplot2's `geom_freqpoly()` pads whatever it is given, so it takes no `pad:` (design-log §4, the
  entry beginning "A frequency polygon takes no"). **The binning options are fields of
  `%Stat.Bin{}`**, ggplot2's: `bins:` (30), `binwidth:`, above 0, `center:`, `boundary:`,
  `breaks:`, two or more distinct numbers, `closed:` (`:right` or `:left`), `pad:` and `drop:`
  (`:none`, `:all` or `:extremes`), numbers kept as floats as R keeps doubles, an option not given
  `:none`; a centre and a boundary together are refused at the call, as `stat_bin()` refuses
  them. A
  function takes ggplot2's function name, several may share a kind, and a refusal names the
  function that wrote the mapping (design-log §4, the entry beginning "A kind is named after").
  **The binning functions and `geom_bar/3` take `orientation:`, `:x` or `:y`, checked at the call
  against the one of `x` and `y` mapped before the stat and recorded nowhere**, since the stat
  runs along that one; a contrary one raises saying what the layer runs along, why, and how to run
  along the other (design-log §4, the entry beginning "Binning takes `orientation:`").
  `geom_col/3`, whose orientation would choose its bars' direction, takes none.
  **`geom_boxplot/3` records `%Geom.Boxplot{}` with `%Stat.Boxplot{}` and dodging by clusters**
  (design-log §4, the entries beginning "A box plot takes R's options", "A weight in the plot's
  mapping", "A box layer dodges by clusters" and "A box plot's orientation"): `coef:`, `width:`
  and `orientation:` are the stat's fields, `width:` set in `fixed` too, so it drops a mapped
  width; `outliers:`, `notch:`, `notchwidth:`, `staplewidth:` and `varwidth:` the geom's, and each
  part's look (`outlier_`, `whisker_`, `staple_`, `median_` and `box_` options, `outlier_stroke:`
  0.5 unless given) a map in the geom of only the looks given. `position:` takes `:dodge2`, its
  default, `:dodge` or `position_dodge2/1`'s struct; with `varwidth: true` an atom records
  `position_dodge2(preserve: :single)` and a struct `preserve: :single`, its padding and order
  kept. A `:weight` the plot's mapping gives is refused, naming it, since boxes are not weighted;
  where one of x and y is mapped, `orientation:` must name the other, the axis the boxes stand
  along, the reverse of binning's sense, and where both are it chooses.
- **A layer's mapping laid over the plot's is `computed_mapping/2`, and nowhere else.** Every
  reader of a layer's aesthetics — the checks here, the assembly's evaluation — asks for it, so
  the precedence exists once: the layer's column wins over the plot's, and an aesthetic the layer
  sets wins over both, dropped from the mapping as ggplot2's `compute_aesthetics()` drops what
  `aes_params` set. **The order ggplot2 evaluates them in is `mapping_order/2`'s, here alone**:
  the layer's own aesthetics, then those it takes from the plot, each mapping's `x` and `y` first
  and its others in name order, as `defaults(layer$mapping, plot$mapping)` lays them.
- **A plot and its layers record their kinds as structs, the null and identity ones included**: each
  layer's geom, stat and position (`%Geom.Point{}`, `%Stat.Identity{}`, `%Position.Identity{}`), and
  the plot's facet and coordinate system (`%Facet.Null{}` and `%Coord.Cartesian{}` when nothing
  chooses others; `coord_radial/1` records `%Coord.Radial{}`); `geom_text/3` records
  `%Position.Nudge{}`, as ggplot2 4.0's `geom_text()` defaults `position = "nudge"`, and
  `geom_rect/3` `%Geom.Rect{}` with the identity stat and position. `annotate/3` records the kind
  the layer function of its geom's name records (`:col` and `:bar` both `%Geom.Bar{}`), with the
  identity stat and position, as ggplot2's `annotate()` does, so its text is never nudged. `Plot`
  builds them and reads a geom's facts to check a layer, but never computes or draws with one; the
  assembly reads a layer's with `layer_geom/1`, `layer_stat/1`, `layer_position/1` and
  `layer_fixed/1`, so `Layer` stays private.
  A field holding a kind is typed `struct()`: a protocol's `t()` is any term, and the check refuses
  it. **The plot records a scale per aesthetic a scale function gives one** (`scales`, `%{}` until
  then): an untrained `%Scale.Continuous{}` or `%Scale.Discrete{}` with the options given, built
  by `struct!/2` so an option not given keeps the struct's default; a later scale for the
  aesthetic replaces it whole, `xlim/3` and `lims/2` included, as ggplot2's does. **A date scale
  is a `%Scale.Continuous{}` through `:date`**, its `date_breaks:` and `date_minor_breaks:`
  recorded as `{:width, step}` in `breaks` and `minor_breaks` and its `date_labels:` as
  `{:format, format}` in `labels`, each refused beside its plain twin, where R takes the `date_`
  one. **`xlim/2`, `ylim/2` and `lims/2` give a list of values a discrete scale's limits, and
  `xlim/3`, `ylim/3` and `lims/2` two dates a date scale's**, sorted, never reversed, as R's
  `limits()` reverses numbers only; two strings are refused, naming the list form (design-log §4,
  the entry beginning "Discrete and date position scales"). **A colour, fill, alpha, shape, size,
  line type or line width scale function records its palette from its options and every other
  field from its schema's defaults, R's function defaults** (gray's missing value red, gradient2's
  ends `muted()`), since
  `PlotRunsNothing` keeps `Scale.new/2` out of `Plot`: the defaults a scale takes when given no
  palette live here as values, and a test pins the discrete and continuous functions' to
  `Scale.new/2`'s. gradient2 records its midpoint as the scale's rescaler, `{:mid, midpoint}`, and
  `scale_size_area/2` its `rescale_max()`, `:max`. **A viridis scale function takes R's options**:
  `option:`, a palette by name, one of `ColorOperations.viridis_options/0`, never R's letters,
  `begin:` and `end:`, places from 0 to 1 (`validate_palette_place/1`), and `direction:`;
  `scale_color_viridis_d/2` records `{:viridis, ...}` with `alpha:` too, its missing value
  `:none`, R's `NA`, the scale an ordered factor gets by default (`Scale.new(:ordinal, ...)`, a
  test pinning the two equal); `scale_color_viridis_c/2` records the gradient through the
  palette's six colours, as R's scale holds `pal_gradient_n()` of them, and takes no `alpha:`
  (design-log §4, the entry beginning "`scale_*_viridis_c/2` takes no"). **A size scale function
  takes the options R's
  does**: `na_value:` only on `scale_size_area/2` and `scale_size_discrete/2`, as R's
  `scale_size_continuous()` and `scale_radius()` refuse `na.value`, and no `transform:` (design-log
  §4, the entry beginning "A scale's `rescaler`"); a size, a range's ends and `max_size:` 0 or
  more (`validate_size/1`, `validate_size_range/1`). **A shape scale function takes the options
  R's does** but those its family waits for (`aesthetics:`, `na.translate`, `drop`): `solid:`,
  recorded `true` unless given, `na_value:`, a shape (`validate_shape/1`), none, drawing no point,
  when not given, as R's `NA`, and `scale_shape_manual/2`'s `values:`, shapes or a map from value to
  shape (`validate_manual_values/2`, which a colour's takes too). **A line type scale function
  takes the options R's does** but those its family waits for: `na_value:`, a line type
  (`validate_linetype/1`), none, drawing no line, when not given, as R's `NA`, which R's
  `scale_linetype()` takes though its docs leave it out, and `scale_linetype_manual/2`'s `values:`,
  line types or a map from value to line type. **A line width scale function takes R's**:
  `range:`, widths 0 or more (`validate_linewidth_range/1`), and `na_value:` only on
  `scale_linewidth_discrete/2`, as R's `scale_linewidth_continuous()` refuses `na.value`, and no
  `transform:`. **Each records its `guide:`** (`validate_guide/2`): `:legend`, `:none`, or the
  `%Guide.Legend{}` `guide_legend/1` builds, and on a continuous colour or fill scale `:colorbar`,
  its default, the others' `:legend`; a colour bar for a discrete scale, or for any aesthetic but
  colour and fill, is refused at the call, where R warns and draws none (design-log §4, the entry
  beginning "A guide is chosen").
  A manual scale's list beside a list of `breaks:` is recorded with them, `{:manual, values,
  breaks}`, each value the break's at its place, as R's `manual_scale()` names them, which leaves
  the scale's limits its levels, so too few values raise. **`lims/2` takes `color:` (`colour:`,
  canonicalized first), `fill:`, `alpha:`, `shape:`, `size:`, `linetype:` and `linewidth:`**: a
  list records what the aesthetic's `_discrete` function records with those limits, two numbers
  its `_continuous` one's, but a shape's or a line type's, refused at the call
  (`validate_unordered_limits/2`), as R's `lims(shape = c(1, 5))` aborts; numbers high to low are
  refused at the call, where R reverses the
  values through a transformation these scales lack (design-log §4, the entry beginning "Colour,
  fill and alpha scales"), and dates are refused. **Limits, breaks and minor breaks are recorded in
  data units, as given**, for the scale to transform; a shortcut records its transformation in
  `transform`, and takes every other option `scale_x_continuous/2` does; limits in either order are
  recorded so, and `xlim/3`, `ylim/3` and `lims/2` record `:reverse` for a pair given high to low,
  as ggplot2's `limits()` does (design-log §4, the entry beginning "Transformations are").
- **A mistake raises from the call that wrote it, or from the layer that draws it.** Each layer
  function resolves its own mapping against the table it draws, its own or the plot's, and checks
  what the geom can use there, so a misspelt column or an unusable aesthetic is reported by the
  line that has it, never later when the plot is run. A missing column's message names the
  aesthetic, the value as the caller wrote it, the column it lacks, which table lacks it, and that
  table's columns.
  **The plot's mapping is checked by the layers that take it** (design-log §4, the entry beginning
  "A column the plot names"): `new/2` refuses only a value the mapping grammar refuses, and each
  layer function checks every column it takes from the plot's mapping, for an aesthetic it neither
  maps nor sets, against its table, one it cannot use included, as ggplot2 evaluates them all and
  fails with "object not found"; so the plot's mapping may name a column only layers' own tables
  hold. This covers what the plot itself knows — names, and which aesthetics a geom takes and
  needs; whether a column's type suits an axis is the scales' question, answered when the plot is
  run. **Each value a layer draws with, its own or the plot's, is checked against the table it
  draws by `Mapping.check/2`** once its columns are found: a function by name the table's engine
  runs, given numbers where the call can tell its value's type, where R fails when the plot is
  built ("non-numeric argument to mathematical function"), and a reordering by numbers, its mean
  one the engine runs, where R warns and orders nothing. A facet's columns are named at the
  call, and none, one named twice, or a value that is not a
  column reference is refused there; whether some table holds them all, and whether `nrow:` and
  `ncol:` hold the panels, are the facet's questions, answered when the plot is run, since a layer
  added later may bring a column and counting the panels is its computation.
- **A layer is checked against the facts of the kind that reads its aesthetics first**: a point or
  column layer against its geom's (`Geom.Point`, `Geom.Bar`), a counting or binning layer against
  its stat's (`Stat.Count`, `Stat.Bin`: one of `:x` and `:y` needed and not both, ggplot2's
  `"x|y"`, `:weight` taken),
  accepting too what its geom draws (`:alpha`), which counting carries, and a count layer against
  `Stat.Sum`'s (`:x` and `:y` needed, `:weight` and `:size` taken) and its geom's, and a box plot
  layer against `Stat.Boxplot`'s (`:x` or `:y` needed, both allowed, `:width` taken) and
  `Geom.Boxplot`'s. **An after_stat,
  the layer's own or the plot's, is checked at the call against the variables the layer's stat
  documents** (`Stat.Count.computed_variables/0`; none for a layer that computes nothing, which
  refuses every one), never against the table, and refused for an aesthetic its stat consumes
  (`dropped_aesthetics/0`, both counting stats' `:weight`). What a stat requires is met, and what it
  takes only one of is counted, by the aesthetics mapped before it runs: `x` beside an after_stat
  `y` counts along x, and an after_stat alone meets nothing, as ggplot2's stat sees only those. A
  required aesthetic is a name or a list of alternatives, one of which is enough; an exclusive list
  allows at most one. A weight must hold numbers: a column's type, read from the layer's table, and
  a constant's are refused at the call, where R would fail inside the stat and draw nothing; an
  expression's type is known only once it has run, so its stat refuses it then; a column layer's
  mapped `:width` alike, an expression's refused by the bar geom.
- **A geom function takes a mapping, a map, and options, a keyword list, either alone or both**
  (design-log §4, the entry beginning "The public pipe API lives in"): `geom_bar(plot,
  position: :dodge)` and `geom_bar(plot, %{x: :class}, position: :dodge)`. A bar function's
  position is chosen by an atom (`position: :stack | :dodge | :dodge2`, `:dodge2` recorded with
  `position_dodge2/1`'s defaults) or by the struct `position_dodge2/1` builds from its options
  (`preserve:`, `padding:` 0 to 1, `reverse:`, and no `width:`, which no geom taking a position
  reads), and recorded as its kind's struct; its parameters never become the geom's options
  (design-log §4, the entries beginning "A layer chooses its position by an atom" and
  "`Plot.position_dodge2/1` arrives").
- **An option that sets an aesthetic for every mark (`alpha:`, `colour:`, `fill:`, `linewidth:`)
  is recorded in the layer's `fixed`, by canonical name**, as ggplot2's `aes_params`; every geom
  function takes `alpha:` and `colour:`, the bar, rectangle and point functions `fill:`,
  `geom_point/3`, `geom_count/3` and `stat_sum/3` `shape:`, `size:` and `stroke:`, in millimetres,
  the line, bar and rectangle
  functions `linewidth:`, in millimetres, and `linetype:`, a line's or a border's,
  and `geom_text/3` `size:`, in millimetres, `angle:`, in degrees,
  `hjust:` and `vjust:`, a number or one of ggplot2's words as an atom (`:inward`), `family:`,
  and `nudge_x:` and `nudge_y:`, in the units of each axis, which its position reads, and
  `geom_rect/3` its corners, `xmin:`, `xmax:`, `ymin:` and `ymax:`, a number or `:infinity` or
  `:neg_infinity`, in the units of each axis, and `geom_bar/3` and `geom_col/3` `width:`, any
  number, as R takes it, and `geom_boxplot/3` `fill:`, `linewidth:`, `linetype:`, `shape:` and
  `size:`, the last two the outliers', and `width:`. The assembly puts it into every row last, a
  position's aesthetic also just before the position runs, and a set corner, an x- or y-family
  aesthetic, and a set width where the table has none, before the geom's setup, so it widens the
  axes as ggplot2 4.0's `GeomRect` fills its corners in, and a bar's edges are where R's are; a
  stat writing a width takes the set one as its own (counting's `%Stat.Count{width:}`).
  **A colour is resolved at the call** (`Giggly.ColorOperations.parse/1`): the layer
  holds its uppercase hex or `:none`, never the name written, and a colour CSS does not define
  raises naming the value. **A shape is resolved at the call too** (`validate_shape/1`): one of
  the names `Geom.Point.shapes/0` lists, or its number, 0 to 25, held as the name, or `:none`, so
  nothing past the call sees two spellings (design-log §4, the entry beginning "A shape is
  ggplot2's name"); anything else raises listing the names. **So is a line type**
  (`validate_linetype/1`): one of R's seven names, its number, 0 to 6, or a dash pattern, a tuple
  of 2, 4, 6 or 8 whole lengths from 1 to 15, each held as its pattern, `:solid` as `{}` and
  `:blank` as `:none`, since a column holds one type and `fixed` reads a list as one value per row
  (design-log §4, the entry beginning "A line type is a name"); anything else raises listing the
  names. A map maps and a keyword list sets:
  the two never trade places. **An
  option that chooses how a geom draws** (`lineend:`, `linejoin:`, `linemitre:`, `geom_line/3`'s
  `orientation:`, `geom_text/3`'s `check_overlap:`, the bar functions' `just:`) **is a field of the
  geom's struct**, its default recorded as ggplot2's (`:butt`, `:round`, `10.0`, `:x`, `false`,
  `0.5`).
- **A function's keyword options are validated by NimbleOptions at the call** (`facet_wrap/3`'s
  `nrow:`, `ncol:` and `scales:`; the bar functions' `position:`, `fill:`, `width:` and `just:`,
  0 to 1; every geom function's
  `data:`, `alpha:` and `colour:`; `geom_point/3`'s, `geom_count/3`'s and `stat_sum/3`'s `fill:`,
  `shape:`, `size:` and `stroke:`; the line functions' `lineend:`, `linejoin:`, `linemitre:` and
  `linewidth:`, `geom_freqpoly/3`'s among them; the line, bar and rectangle functions' `linetype:`,
  and the bar functions' `linewidth:`; `geom_line/3`'s `orientation:`; the binning functions'
  binning options and `orientation:`, and `geom_bar/3`'s; every option of `geom_boxplot/3`,
  `geom_text/3`,
  `geom_rect/3`, `annotate/3`, the scale functions, the guide functions, `labs/2` and `theme/2`), so
  a misspelt
  option raises naming it, and a repeated one is refused by `Aesthetics.canonicalize/1`, run first.
  A deliberate default is recorded as a value (`scales: :fixed`). An option not given is recorded as
  `:none` in the kind's struct, but a scale's, whose `:none` removes, is `:default`. A continuous or
  date scale's list of labels needs a list of breaks as long, checked at the call, since its default
  breaks are known only when run; a discrete scale's is one for each break given, or else each limit
  given, checked at the call, and otherwise when run. `date_labels:` is checked at the call by
  writing a date in it with `Calendar.strftime/3`, so a format it cannot write (`"%W"`) raises
  there. A caller writes `:none` only to remove something (`colour: :none`, `labs(x: :none)`), and
  `nil` only for a limit the data supplies (design-log §4, the entry beginning "Absent").
- **A plot records its labels (`labels`), each by what it titles, as `labs/2` sets them**: an
  aesthetic a guide shows (`x`, `y`, `color`, `fill`, `alpha`, `shape`, `size`, `linetype`,
  `linewidth`) or the plot's `title`, `subtitle`, `caption` and `tag`, each a string or `:none`,
  `%{}` until a call sets one; a
  call replaces only the labels it gives. Any other key raises, and so does a label that is not text
  or `:none` (`validate_label/1`); a label may break over lines. Which aesthetic a layer maps is not
  checked, since `labs/2` may come before the layers (design-log §4, the entry beginning "`labs/2`
  takes the titles").
- **A plot records its theme (`theme`) as the complete theme's name and the settings `theme/2`
  has merged** (design-log §4, the entry beginning "A theme is set element by element"):
  `%{complete: :gray, settings: %{}}` until a call sets one. **`theme/2` checks its settings
  against a schema built from `Theme.elements/0`**, an option per element of ggplot2's tree, each
  checked as its kind: a line's, a rectangle's or a text's properties a keyword list
  (`color:`, canonicalized first, `colour:` too; `fill:`; `linewidth:`, millimetres; `size:`,
  points; a text's `margin:`), a size or a line width `{:rel, share}` too, both 0 or more; a
  length a number of ggplot2's points, `{amount, unit}` (`:pt`, `:cm`, `:mm`, `:in`, `:lines`) or
  `{:rel, share}`, held as `{amount, unit}`; a margin one length or a keyword list of
  `:top`, `:right`, `:bottom` and `:left`, each given once, a side left out `{0, :pt}`, held as a
  map of all four, a margin element's `{:rel, share}` too, a text's margin never. A colour is
  opaque, a rectangle's border `:none` too (`validate_theme_color/1`, `validate_theme_border/1`),
  until a theme needs transparency. An element or a property given twice raises from
  `Aesthetics.canonicalize/1`, as `labs/2`'s does. The validated settings are handed to
  `Theme.merge/2`, so a later call's properties replace only those it gives, as R's `+` does.
- **A plot records the guides `guides/2` sets (`guides`), each by canonical aesthetic**, `%{}`
  until a call sets one, a call replacing only the guides it gives, as `labs/2` does: `color`,
  `fill`, `alpha`, `shape`, `size`, `linetype` and `linewidth` alone, each as a scale's `guide:`
  takes it, a colour bar for any but colour and fill refused at the call; whether a colour or fill
  scale it gives a colour bar is continuous is known only when the plot is run, so the assembly
  refuses one that is not. Which aesthetic a layer maps is not checked. The axes take no guide yet:
  they wait for `guide_axis()`'s options.
- **Each table is read once, by the call that gives it**: the plot's by `new/2`, a layer's own by
  its function's `data:`, any `Table.Reader`, read after the options are validated, as ggplot2's
  `data =`. The plot holds a `Giggly.DataFrame` and each layer its own or `:none`, which draws the
  plot's (`layer_table/2`), so nothing past this API sees a `Table.Reader`. R also takes a function
  or formula as a layer's data, which waits.
- **The plot holds what was resolved.** Mapping keys are canonical (`Aesthetics.canonicalize/1`
  runs on every mapping as it enters), and each value is held as `Giggly.Mapping.resolve/1` gives
  it, its columns named as strings, never the atoms the caller wrote: a layer's checked against
  the table it draws; the plot's, against each table that takes them. What a value may be is
  `.claude/rules/mapping.md`'s; `Plot` never matches a value's shape itself.
- **A facet's column reference is an atom or a string,** compared with the data's names as a
  string.
- **A layer's own mapping is checked against what it accepts as the layer is added, and its own
  laid over the plot's against what it requires**: an aesthetic the layer maps that it cannot use
  raises, and so does a required one neither mapping gives nor an option sets, as ggplot2 checks a
  layer's columns and its `aes_params` together. **An aesthetic it takes from the plot's
  mapping that it cannot use rides along unused, as ggplot2 carries one** (design-log §4, the entry
  beginning "An aesthetic a layer takes from the plot"): evaluated into its table and drawn by
  nothing. Each layer records what it accepts (`accepted`, its geom's and its stat's facts, read
  with `layer_accepted/1`), which the assembly reads to say which legends it draws in.
- **A geom accepts only what the pipeline can draw.** An aesthetic joins a geom's accepted list
  with the scale that maps it, so a mapping never silently does nothing.
- **When keyword options arrive, `Aesthetics.canonicalize/1` runs before NimbleOptions validates
  them.** NimbleOptions keeps only the first of a repeated key and checks only that one, so
  validating first would let `alpha: 0.4, alpha: "x"` through; `canonicalize/1` refuses the
  repeat, and spells a box part's colour `_color`, `outlier_colour:` beside `outlier_color:`. NimbleOptions has no number type either: an option taking any number is
  `{:or, [:integer, :float]}`, or an integer is refused. `alpha:` takes 0 to 1, `linewidth:` 0 or
  more, `linemitre:` 1 or more, as grid refuses less, a text's or a point's `size:` and a point's
  `stroke:` 0 or more, the stroke `:none` too, `angle:` any
  number, `hjust:` and `vjust:` any number or one of ggplot2's words, and `nudge_x:` and
  `nudge_y:` any number, through custom checks (`validate_alpha/1`, `validate_linewidth/1`,
  `validate_linemitre/1`, `validate_size/1`, `validate_angle/1`, `validate_justification/1`,
  `validate_nudge/1`, `validate_stroke/1`), which take an integer too and keep a float, as R
  keeps a number, and a shape's (`validate_shape/1`) and a line type's (`validate_linetype/1`),
  which take a name or a whole number, a line type a tuple of them too;
  `validate_color/1` hands a colour to `Giggly.ColorOperations`. A gradient's colours must be
  opaque (`validate_opaque_color/1`), since it blends colours alone; a grey's level and an alpha
  range's ends run from 0 to 1.
- **An annotation (`annotate/3`, `annotation: true`) is a layer drawn from values given in the
  call** (design-log §4, the entry beginning "`annotate()` draws with every geom"): its positions
  become a table of its own, a row per annotation, its mapping naming each position's column, as
  ggplot2 maps `aes_all()` of its data, so they train the scales and repeat in every panel; its
  other aesthetics are set, in `fixed`. It takes nothing from the plot's mapping
  (`computed_mapping/2`), titles no guide, and so draws in no legend. Each option takes one value
  or a list, every list as long as the others, as ggplot2's "Unequal parameter lengths", a list of
  one value being one value; only the aesthetics a geom draws row by row (`label`, `colour`,
  `alpha`, `fill`, a point's `shape`, `size` and `stroke`, a bar's or a rectangle's
  `linewidth` and `linetype`, and a path's or a line's `linewidth`, drawn a segment at a time) take
  a list, which `fixed` holds as one value per annotation; a path's or a line's line type is one,
  as ggplot2 refuses a line type varying along a line. A list's values are of one type, checked by
  building its column (`Giggly.DataFrame`) at the call, a colour's, a shape's or a stroke's `:none`,
  or a line type's `:blank`, in a list held as `nil`, the column's missing value, as R's `c(NA,
  "red")` holds `NA`. A position is kept as a float where it is a number, as an option's number is.
  The options are each geom's function's but `data:`, `position:` and nudging, so one its geom
  cannot use raises, where ggplot2 warns and ignores it.
