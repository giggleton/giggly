---
paths:
  - "lib/giggly/scale.ex"
  - "lib/giggly/scale/**"
  - "test/giggly/scale_test.exs"
---

# Scales

`Giggly.Scale` decides what kind of scale a column needs, puts values through a scale's
transformation, trains a scale over the values it is given, and maps values to their positions,
or, for an aesthetic other than position, through the scale's palette to the aesthetic's values.
It is ggplot2's half of a scale; R's scales half, the breaks, transformations, palettes, bounds and
data ranges it works with, is the `Scales` package (giggleton/scales, its `scales.md`).
Why a palette is a field of the two scale kinds: design-log §4, the entry beginning "A scale's
palette is a field".
Why scales are values rather than one mutated object: design-log §4, the entry beginning "Scales
are three values"; what increment 5 built and what waits for its first reader: the entry
beginning "Position scales are chosen by column type"; why a continuous scale records the
identity transformation: the entry beginning "A layer records its stat and position".

## Rules

- **A scale is a continuous or a discrete scale, whatever the aesthetic, or for colour and fill a
  binned one (below); its palette is what makes it one aesthetic's.** Its palette is any value
  of `Scales.Palette`'s (the package's `scales.md`), one of the other kind converted when
  mapped, or one of ggplot2's own a discrete scale holds (below).
  `new/1` makes a position scale; `new/2` makes an aesthetic's with ggplot2's default palette for
  it (`alpha`: 0.1 to 1; `color` and `fill`: the gradient from `#132B43` to `#56B1F7`, or
  `pal_hue()`'s hues from 15 round to 375, chroma 100, luminance 65; `size`: 1 to 6 by area, or 2
  to 6 discrete; `shape`: the solid shapes, discrete alone; `linetype`: R's 13, discrete alone;
  `linewidth`: 1 to 6 rescaled, or 2 to 6 discrete by `seq()`; as floats, as `Plot`'s scale
  functions record them), one of `non_position_aesthetics/0`. **`new(:ordinal, aesthetic)` is an
  ordered factor's, ggplot2's ordinal scale**, `scale_type()`'s word for it: viridis for colour
  and fill, its missing value `:none`, R's `NA`, as `scale_colour_ordinal()` takes
  `scale_colour_viridis_d()`, and the discrete scale for the rest, which ggplot2's ordinal ones
  match.
- **A shape or line type scale is discrete alone** (`discrete_only?/1`), as R's
  `scale_shape_continuous()` and `scale_linetype_continuous()` abort, neither having an order:
  `new/2` makes none continuous, and the assembly refuses a continuous or a date column of the
  aesthetic.
- **A continuous value's place is R's `rescale()` (`Scales.Bounds.rescale/3`) over the scale's limits**
  (`limits/1`, R's `get_limits()`: each given end, else the trained range's), **in R's order of
  operations**, and limits of zero width put every value at the middle, so one value maps to the
  middle of its palette (0.55 for alpha); the rescale palette calls the same function. **A scale's
  `rescaler` says how a value is placed, as ggplot2's scale holds its rescaler** (design-log §4,
  the entry beginning "A scale's `rescaler`"): `:rescale`, by `rescale()`; `{:mid, midpoint}`, by
  R's `rescale_mid()` (`Scales.Bounds.rescale_mid/4`), as gradient2's does, its midpoint in
  transformed space, given in data units and transformed by the scale function, as ggplot2's
  `mid_rescaler()` transforms it (design-log §4, the entry beginning "gradient2's midpoint"); or `:max`, by R's
  `rescale_max()` (`Scales.Bounds.rescale_max/3`), the value over the
  limits' high end, as `scale_size_area()`'s does, so 0 is at 0 and one value at 1, a high end of
  0 placing 0 at `nil`, R's NaN, and raising for any other finite value, which R makes an
  infinity it cannot draw. The rescaler is the scale's, not the palette's, since a palette takes a place and
  the colour bar's ticks never go through a midpoint. A value is placed once its `oob` has run
  (below), and placed beyond 0 to 1 where it leaves one outside; a value the palette gives
  nothing for, `nil` or NaN, maps to the scale's `na_value`, ggplot2's `na.value`: `nil` for a
  position, alpha, line width and size, grey50 for a colour or fill, or what a plot's scale gives,
  `:none` among them. A colour's palette gives nothing off its ends or at an infinity; alpha's,
  size's and line width's run on past their range and give an infinity for an infinite value, as
  R's palettes do (design-log §4, the entry beginning "A non-position scale keeps"), and
  `:max`'s infinite place is an infinity whatever the high end.
- **A continuous or binned scale's `oob` is R's, run in transformed space before a value is
  placed** (`Giggly.Scale.OutOfBounds`; design-log §4, the entries beginning "`oob:` takes a
  name" and "A function `oob`"): a name runs `Scales.Bounds`'s function of that name on the
  limits `limits/1` gives, ends filled from the range; a function is handed one column's values
  and those limits, sorted, and returns a value for each, a number read as a float, an infinity,
  `nil` or `:nan`, another count or kind raising when run. NaN comes back `nil`, from either. A
  position's runs at both maps, `map/2` before the stat and `map_positions/2` once the positions
  are final, each column alone; with no limits and no finite value it is handed the range of
  nothing, `{:infinity, :neg_infinity}`, as R's; a non-position scale with no limits maps every
  value to `na_value` without it. Guides map through `map/2`, so a legend's keys and a colour
  bar's colours go through it too. Its tests pin R's table of every name and two functions over
  each kind of scale (`test/giggly/fixtures/r_oob_ggplot2_4.0.3.txt`).
- **A legend's breaks are the scale's on its limits, not an axis's extent** (`legend_breaks/1`),
  from its options as an axis's are: a continuous scale's are its breaks, given or its
  transformation's, inside its limits, taken as floats as R's limits are doubles, one at the low
  end of limits of zero width, none before it has limits; a discrete scale's are its breaks among
  its limits (`Discrete.limits/1`), in the order given, `nil` labelled `NA`, as ggplot2's legend
  keeps `NA`; each labelled by the scale's `labels`, `:none` among them; `breaks: :none` gives no
  legend, as R's `breaks = NULL` draws no guide.
- **A discrete palette spreads the present levels; `nil` takes no share and maps to the scale's
  `na_value`**, ggplot2's `na.value`, as ggplot2's mapping leaves `NA` out of the levels it counts:
  `nil` for alpha, line type, line width and shape (R's `NA`) and grey50, `#7F7F7F`, for colour and
  fill. `na_value` is a field of both scale kinds, as ggplot2's scale carries it (design-log §4, the
  entry beginning "A discrete scale carries its missing value"); a position scale places `nil` as
  its last level and reads none.
- **A manual palette gives a list's colours, shapes or line types to the levels in order, and a
  map's by value** (`Scales.DataRange.key/1`), a level the map lacks taking the `na_value`; a map
  with no given limits narrows the scale's limits to the levels it names, the missing value kept,
  as ggplot2's manual scale limits itself to its values' names. **A list named by breaks
  (`{:manual, values, breaks}`) gives each break's level the value at its place and leaves the
  limits the levels**, as `manual_scale()` names values by breaks after choosing its limits. Any
  kind with fewer values than limits raises when the plot is run, named or not, as R fails
  ("Insufficient values in manual scale"). This matching and refusing is ggplot2's, so it is
  `Giggly.Scale.Discrete`'s, as are ggplot2's ordinal palettes: `{:sequence, {low, high}}`,
  `scale_alpha_ordinal()`'s `seq(low, high, length.out = n)`, and `{:area_sequence, {low, high}}`,
  `scale_size_ordinal()`'s `sqrt(seq(low^2, high^2, length.out = n))`, `low^2` as `low * low`, as
  R's `^` squares, both on `Scales.Palette.spread/2`; every other palette is R's (the package's
  `scales.md`). **A shape scale's seventh level, a line type scale's fourteenth, or a level past a
  brewer palette's largest set, raises when the plot is run**, naming the palette's count, the
  levels' and `Giggly.Plot.scale_shape_manual/2`, `scale_linetype_manual/2` or the colour manual
  scales, where R's palette gives `NA` with a warning and leaves it undrawn (design-log §4, the
  entry beginning "A discrete palette with fewer shapes"); the package's palette gives `nil`
  there, which the scale refuses.
- **A scale names its guide (`guide`), as ggplot2's scale carries `guide`**: `:axis` for a position
  (ggplot2's `guide_axis()`, drawn by the coordinate system's sides, not through the guide
  protocol), `:colorbar` for a continuous colour or fill, `:colorsteps` for a binned one, and
  `:legend` for alpha, line type, line width, shape, size and a discrete colour or fill, by
  default; a plot's scale may name `:none`, a legend or colour steps for a continuous colour or
  fill, or carry the legend's struct `Plot.guide_legend/1` builds,
  typed `struct()`. The assembly turns a name into the kind; a scale never reads its guide, so the
  boundary lists no guide. **`samples/2` and `places/2` give what a colour bar draws from a
  continuous scale**: values spread evenly over its limits by R's `seq()`, as `extract_decor()`
  takes them, and each value's place in the limits, 0 to 1, whatever the rescaler, as the gradient
  form places its ticks and colours. **`steps/2` gives what colour steps draw from a continuous or
  binned scale**, as `GuideColoursteps` works it out with even steps: bins of equal length between
  the limits and breaks sorted, each coloured as the scale maps its middle, and each break's place
  by R's count of the breaks in the order given, one lower where the scale's first break is on a
  limit, `nil` past the bar's end; a continuous scale's default breaks on a limit `nil` too, as R
  leaves them out. Its tests pin R's places and colours, out-of-order breaks among them.
- **`Scale.Continuous`, `Scale.Discrete` and `Scale.Binned` are API, and the boundary exports
  the three; the rest of the namespace is not.** `Giggly.panel_scales/2` returns the first two
  and `Giggly.Plot` writes them, so their fields are documented and changing one changes the
  API; their functions are `@doc false`,
  used through `Giggly.Scale`, which is `@moduledoc false`. The rule for which values a discrete
  scale counts as one (a number as a float, so `2` and `2.0` are one) is
  `Scales.DataRange.key/1`, which `Plot` reads to refuse a value named twice, and the assembly to
  match a legend's key against a layer's column, so the rule has one home.
- **A binned scale is ggplot2's third kind, `ScaleBinned`, which no column's type chooses**
  (`Scale.Binned`; design-log §4, the entry beginning "A binned scale's breaks and limits"): it
  trains as a continuous scale and takes numbers alone (`takes?/2`); **its breaks and widened
  limits are worked out from its range and options each time they are read, never stored**, and
  it maps on the widened limits whatever the guide, where R's limits depend on whether a guide
  read them first. Each value goes through its `oob`, `:squish` by default, as R's, is placed by
  its rescaler and cut at the breaks' places, R's `cut(include.lowest = TRUE, right)`, a place
  left outside the limits in no bin, as `cut()` gives `NA`; a bin is
  coloured by `{:binned, palette}`'s colours for the bins' count, too few raising, or by a
  continuous palette at its middle. Given breaks outside the limits are left out with their
  labels, a function's breaks, handed the limits and `[n: n_breaks]` for two arguments, read as
  given ones once called (`Binned.called/1`), the limits not widened, as R's `get_breaks()`
  writes them back; a labels list is one for each given or default break or the run raises, and
  a missing value is never coloured. **Default breaks are `n_breaks` wanted (5)**: nice ones, the
  identity's extended breaks with `n:`, or, with `nice_breaks: false`, `n_breaks` spaced evenly
  by R's `seq()` less its ends; with no limits given, two or more inside the range widen it so
  the end bins match their neighbours, one widens it to that break less and plus its distance to
  the further end, and none leave it, its ends its breaks, a zero-wide range first widened 0.05
  either side, R's `get_breaks()` branch by branch, its arithmetic included.
  **`shown_limits/1` gives the limits a scale with `show_limits` labels the bar's ends with**,
  written by its labels as its breaks are, `[]` when not shown, raising beside a list of labels,
  which R ignores with a warning. Its tests pin R's breaks, limits, colours and labels.
- **A continuous scale carries the options a plot gives it**, `name`, `limits`, `oob`, `breaks`,
  `minor_breaks`, `n_breaks`, `labels`, `expand` and `rescaler`, each `:default` until given but
  `rescaler`,
  `:rescale`, `oob` `:censor` (a binned scale's `:squish`), `limits` `{nil, nil}` and
  `expand` ggplot2's `[mult: {0.05, 0.05}, add: {0, 0}]`; `Giggly.Plot` writes the struct,
  untrained, and the assembly trains a copy (design-log §4, the entry beginning "A scale function
  records the untrained scale"). Its field defaults are a position scale's, so `%Continuous{}` is
  `new(:continuous)`. `kind_of/1` says which kind a scale is, as `kind/1` says which a column needs.
  **A date scale's breaks and minor breaks may be a width, `{:width, [week: 1]}`, and its labels
  a format, `{:format, "%b %d"}`**, as `Plot.scale_x_date/2` records `date_breaks:`,
  `date_minor_breaks:` and `date_labels:` (design-log §4, the entry beginning "`date_breaks:` and
  `date_minor_breaks:` are a step"): a width's breaks are `DateBreaks.width/2` on the extent,
  those inside it kept, and a format's labels each date written by `Calendar.strftime/3` as it is.
  **Its breaks and minor breaks may be a function** (`Giggly.Scale.BreaksFunction`; design-log §4,
  the entry beginning "A breaks function"), called as ggplot2's `get_breaks()` calls one: handed
  the extent squished into the domain, turned back into data units, a date's rounded out to whole
  days and a time's held inside the day, and for breaks of two arguments `[n: n_breaks]`, `[]`
  while `n_breaks` is `:default`; for minor breaks of two the breaks drawn; an extent of zero width
  its end, the function not called. It returns breaks of the scale's kind or `{break, label}`
  pairs, R's named breaks, a pair's label its default label; what it returns is kept and
  labelled as given breaks are, a list of labels one for each break it returns or the run raises,
  and colour steps leave out its breaks on a limit as they do default ones, as R's scale holds no
  numbers there. `n_breaks` asks the transformation's own breaks for that many.
  A date-time scale's are the same, `Plot.scale_x_datetime/2` recording them, its steps taking
  `:second`, `:minute` and `:hour` too, its width's breaks `DateBreaks.datetime_width/3`'s and its
  format writing each break as a `DateTime` or a `NaiveDateTime`; a time scale's too,
  `Plot.scale_x_time/2` recording them, its steps `:second`, `:minute` and `:hour` alone, its
  format writing each break as a `Time` wrapped past midnight; the transformation lays a width
  (`Transform.width/3`), only a date's, a date-time's and a time's having one.
- **A discrete scale carries the options a plot gives it**, `name`, `limits`, `breaks`,
  `minor_breaks`, `labels` and `expand`, each `:default` until given but `expand`, ggplot2's
  `[mult: {0, 0}, add: {0.6, 0.6}]`; its field defaults are a position scale's, so `%Discrete{}` is `new(:discrete)`.
  **Its limits are the values it shows** (`Discrete.limits/1`, R's `get_limits()`): given, they
  replace its levels, in their order, every reader (`map/2`, `breaks/2`, `dimension/1`,
  `legend_breaks/1`) going through them; a value not among them maps to `nil`, so its row is not
  drawn, `nil` among them places the missing value, and one the data lacks keeps its place. A
  value is matched by `Scales.DataRange.key/1`, as the column holds it (design-log §4, the entry beginning
  "A discrete axis names its values"). **Its breaks are the given values among its limits, in the
  order given, at their limits' places**, each the limit as the scale holds it, so a break of `4`
  is a level of `4.0`, or every limit, or those a function handed the limits returns, a pair's
  label its default label; **its labels** go with given breaks by
  place, a break left out taking its label with it, a list one for each candidate break or the run
  raises (R pads it with `NA`); a map labels the values it holds, the rest written as a level is;
  a function is handed the breaks' values, `nil` among them.
- **Limits replace the range end by end, and a position outside them goes through the scale's
  `oob`.** Given in data units, they are transformed and, both given, sorted, as ggplot2
  transforms and sorts them (`Continuous.limits/1`); a given end outside the domain is refused
  by the scale function at the call, and by `limits/1` for a scale built by hand, where R warns
  and takes the data's end for one turned into NaN and fails for one turned into an infinity
  (design-log §4, the entry beginning "A given limit outside"). An end of `nil` takes the range's (R's `get_limits()`), and with both ends an axis
  exists before any data. By default, `:censor`, a finite position outside becomes `nil` at both
  maps, `:infinity` and `:neg_infinity` kept, so a bar whose base the limits leave out is missing;
  NaN becomes `nil`, as ggplot2's position map gives `NA` for it, and a discrete scale's positions
  are returned as given.
- **Given breaks are kept in the order given wherever they fall inside the widened extent**, in
  data units and transformed, one outside the transformation's domain dropped, even beyond the
  limits, as R keeps 1.4 on mtcars' weights from 1.513; given labels go with their
  breaks by index, so a break left out takes its label with it; a labels function is handed every
  break drawn at once, as R's are, and must return a label for each, a string, a power
  (`{:power, base, exponent}`, signed or not, `Scales.Labels.log/2`'s) or `nil`, or the run
  raises; `:none` gives no breaks (so no minor breaks), no minor breaks, or `{position, :none}`
  for each break, which the axis draws as ticks alone.
- **A missing label is written where a scale's labels are made, but among powers** (`written/1`,
  over a continuous, a discrete and a binned scale's labels alike, a list's, a map's and a
  function's): `NA`, as R draws a missing label, so a guide sees `nil` only where any label is a
  power, and writes it as R draws its guide's (the scales design log's entry beginning "A missing
  break's label"; design-log §4, the entry beginning "A missing label among powers").
- **A scale sees plain values, never a frame or a plot.** Its boundary lists `Scales`, R's scales
  half, which gives it its breaks, transformations, palettes, bounds and data ranges, and
  `Giggly.AsCharacter`, which writes a discrete level, and nothing else; the assembly pulls a
  column and hands its values here. Anything that needs a frame belongs to the caller.
- **A scale knows no pixel.** It stops at positions in data space: a continuous value as its
  transformation leaves it, a discrete value at its level's position counting from 1. The unit panel is the coordinate
  system's.
- **`kind/1` is the one rule for which column types an axis can place, and `kind/2` for an
  aesthetic**, read by the assembly to refuse a column when the plot is run and to choose the
  scale. A type with no scale yet returns `:none`. A `Date` column is `:date`, as ggplot2's
  `scale_type()` gives a `Date` `"date"`, and `:category`, a factor's column, is `:discrete`
  whatever its values: a date's is a continuous scale through the date transformation, which
  takes no numbers, as R's warns at them; on an aesthetic other than position a
  date has no scale yet (`kind/2` gives `:none`), ggplot2's `scale_colour_date()`,
  `scale_alpha_date()`, `scale_size_date()` and `scale_linewidth_date()`. **A date-time is
  `:datetime` and a naive one `:naive_datetime`**, as `scale_type()` gives a `POSIXct`
  `"datetime"`, two kinds since a naive date-time names no instant, both a continuous scale through
  the date-time transformation (`new/1`), and on an aesthetic other than position none yet, as a
  date's. **A time of day is `:time`**, as `scale_type()` gives an `hms` `"time"`, a continuous
  scale through the time-of-day transformation, and on an aesthetic other than position none yet.
  **`takes?/2` is the one rule for which kind of column a scale takes**: its own kind, a
  date-time scale no column has settled either date-time kind, and a continuous scale through the
  identity a date's, a date-time's or a time's, which the identity places at its days, its seconds
  since 1970-01-01 or its seconds since midnight, as R's untransformed continuous scale draws
  each; under any other transformation each is refused, where R fails. **`places?/2` is the one
  rule for which an axis's scale places**, a plot's or a default one: `takes?/2`'s, and numbers
  on a discrete scale, each a position counting from its first level, as ggplot2's discrete
  position scale trains its continuous range on a value that is not discrete; a date there is
  refused, where R fails.
- **Which a discrete scale is handed, levels or positions, the caller says** by the function it
  calls, never by the values' type: `train/3` for a layer's own values, its levels, and
  `train_positions/2` for positions, a layer's numbers or marks once the levels are mapped, which
  widen its continuous range alone; `map/2` is never handed positions, which stay as they are. `discrete?/1` tells a discrete scale from the
  others for a caller that must, as a legend's key drawing does.
- **A continuous scale records its transformation by name, the identity included.**
  `new(:continuous)` records `:identity`, as ggplot2's continuous scales default to
  `transform = "identity"`, so an untransformed axis says so; `new(:date)` records `:date`;
  `new(:datetime)` records `{:datetime, :default, Calendar.UTCOnlyTimeZoneDatabase}`, the name
  with its zone and the time zone database that reads it, as R's `transform_time(tz)` holds its
  zone (design-log §4, the entry beginning "A time zone's database is passed on the scale"), a
  plot's naming its zone and database; `new(:time)` records `:time`; a plot's scale may name
  any transformation of numbers `Scales.Transform` names, a composition or a user's own among
  them, on an axis and on a continuous scale of colour, fill, alpha, size or line width alike
  (design-log §4, the entries beginning "`transform:` takes every" and "`transform:` reaches"),
  the scale training, breaking, placing and sampling its colour bar in transformed space and
  labelling in data units; a binned scale takes none. A discrete scale has none, as in ggplot2, and
  `transform/2` returns its values as given.
- **A date-time scale's zone is the one a plot gave it, else its first column's**
  (`settle_zone/2`), as ggplot2's takes the first column's `tzone` when given none: `:default`
  until the assembly settles it from that column's type, a zone's name, or `:naive` for naive
  date-times; a zone its database does not know is `{:error, {zone, database}}`, which the
  assembly refuses; a plot's is checked when given. A scale on an axis no
  column maps keeps `:default`, written as UTC.
- **A time zone's database is always passed, never read from config.** Every `DateTime` function
  that works in a zone takes one, defaulting to `Calendar.get_time_zone_database/0`, which reads
  the application's config even for UTC; `GigglyCredo.Check.PassTimeZoneDatabase` fails the gate
  on any such call in `lib/` that leaves it out, where `CorePurity` cannot see the read.
- **A scale trains and maps in transformed space.** The assembly puts an axis's columns through
  `transform/2` before training, so the range, and every view of it the coordinate system builds,
  is in transformed space.
- **`breaks/2` gives an axis's breaks as `{position, label}` pairs, on the extent it is handed**,
  never one of its own, so a coordinate limit can hand it another. A continuous scale's are its
  transformation's breaks inside the extent (ggplot2 censors the rest), none when untrained, and
  the extent's low end alone when it has zero width; a discrete scale's are its breaks among its
  limits, at their places 1..n.
  Positions and labels travel as pairs so they cannot drift apart. A surviving mutant there is
  judged against R: applied to a scratch copy and compared with `labeling::extended()` on many
  random and degenerate ranges, it is equivalent only if it matches R on all of them; otherwise
  the first range where it departs joins the tests, with R's breaks.
- **`minor_breaks/3` gives an axis's minor breaks between the breaks `breaks/2` gave on the same
  extent**, as ggplot2's view scale hands `get_breaks_minor()` its breaks: the transformation's
  minor breaks kept inside the extent, ends included (R's `discard()`), less the breaks
  themselves, matched by value as R's `setdiff()` matches them, which ggplot2's grid takes out of
  its minor lines and nothing here reads. **A discrete axis's are its `minor_breaks`**, as ggplot2
  3.5.0's are, positions at its values' places, or a function's on the extent and the breaks'
  places, none by default.
- **A discrete level is written as R's `as.character()` writes its value** (`level_labels/1`,
  `Giggly.AsCharacter`),
  as `factor()` labels its levels: `4`, `0.5`, `1e+05`, `TRUE`; a missing level is `NA`. The
  scale lists `Giggly.AsCharacter` for it, and the text geom lists it too, so the rule has one
  home.
- **A discrete scale keeps a continuous range beside its levels**, ggplot2's `range_c`: handed
  positions, such as a bar's edges once its levels are mapped, it widens that range and leaves
  its levels alone. `reset/1` empties a continuous scale's range and a discrete one's continuous
  range, keeping its levels, as ggplot2 resets its scales before training them again on the
  positioned marks.
- **An untrained continuous scale's range is `:none`.** The empty axis's 0 to 1 is
  `dimension/1`'s, as it is ggplot2's `get_limits()`'s.
- **`dimension/1` is an axis's extent widened by the scale's expansion, and `dimension/2` the
  same widened by the expansion it is handed**, as ggplot2's `dimension(expand)` takes one, which a
  stat reads unwidened, in transformed
  positions: a continuous scale's limits by its `expand`, at each end `width * mult + add` (R's
  `expand_range4()`, through `Scales.Bounds.expand_range/2`; a negative amount narrows it, as
  R's `expansion()` allows), 5% of the width
  by default, a discrete scale's limits (1 to n) by its `expand`, 0.6 by default,
  limits of zero width (R's `zero_range()`, rounding error included) as if their width were 1;
  a discrete scale's extent then reaches as far as its continuous range does, unwidened, as
  ggplot2's `expand_limits_discrete()` takes the range of both, and **a discrete scale with no
  limits widens its continuous range alone by its `expand`, or else 0 to 1**, as
  `expand_limits_discrete_trans()` does for counts a stat puts on an axis no layer mapped.
  `Scales.Bounds.zero_range?/1` is the one home of R's `zero_range()`; `Giggly.Resolution` asks
  it.
  **An extent still zero wide once widened is returned as its middle, both ends equal** (a single
  value from about 4.5e11 up): ggplot2 keeps such an extent and `scales::rescale()` draws every
  value on it at the panel's middle, and equal ends are how the coordinate system is told, so
  the coordinate system never asks `zero_range()`. The coordinate system maps the extent onto the
  panel and adds nothing; the coordinate system's switch to turn expansion off arrives with its
  options.
