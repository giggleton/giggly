---
paths:
  - "lib/scales.ex"
  - "lib/scales/**"
  - "priv/palettes/brewer.csv"
  - "test/scales/**"
  - "test/scales_test.exs"
---

# The scales package

`Scales` is R's scales half of a plot's scales, the package that leaves this repository once
complete: breaks, labels, transformations, palettes, values against a range's bounds
(`Scales.Bounds`), the range of the data a scale trains on (`Scales.DataRange`), and colour
operations (`color_operations.md`) and labels (`labels.md`), each with a rules file of its own.
Giggly's half, a scale's kind, defaults, training and mapping, is `Giggly.Scale` (`scale.md`).
Why the split falls on R's line and the package is carved here first: design-log §4, the entry
beginning "`scales`, a package of R's scales half"; why its files were moved by name alone: the
entry beginning "The split moves files under `Scales.`". Why breaks come from extended Wilkinson
and labels are written the Elixir way: the entry beginning "Axes are drawn"; why minor breaks are
R's regular ones: the entry beginning "The panel's grid lines are placed by the coordinate system".

## Rules

- **The package depends on nothing in Giggly.** Its boundary lists `Color` and `NimbleOptions`
  alone and exports what Giggly's code calls, so a call back into Giggly fails the build, as it
  would from another repository; Giggly's domains reach it through the root, which lists it.
  **Nor do its tests**: `test/scales` and `test/scales_test.exs` leave with the package, so they
  call only `Scales` and pin R's figures there, alone running every line of `lib/scales`; a test
  of a Giggly scale through the package is Giggly's, in `test/giggly`.
- **A module is API when a user holds its inputs or Giggly calls it** (design-log §4, the entry
  beginning "The scales package's API is what a user holds"): the root and each of R's families,
  their functions R's names less the family's prefix, each `@doc` naming R's function and saying
  where it departs, options keyword lists of R's arguments checked by NimbleOptions; the root
  documents the conventions they share, once. `Scales.DateBreaks` (days or seconds and a clock),
  `Scales.Labels.Fixed` and the `Scales.Transform.*` modules stay internal, reached through
  `Scales.Transform` and `Scales.Labels`.
- **A palette is a value naming its function (`Scales.Palette`), never a closure, and each is
  R's**: continuous, `:identity`, R's `pal_identity()`, `{:rescale, {low, high}}`, R's
  `pal_rescale()`, `{:area, {low, high}}`, R's `pal_area()`, the place's square root rescaled,
  `{:abs_area, max}`, R's `abs_area()`, the square root of the place's size rescaled onto 0 to
  `max`, and `{:gradient, colors}` or `{:gradient, colors, values}`, R's `pal_gradient_n()`;
  discrete, `{:hue, %{hue:, chroma:, luminance:, direction:}}`, R's `pal_hue()`,
  `{:gray, {start, finish}}`, R's `pal_grey()`,
  `{:viridis, %{option:, begin:, end:, direction:, alpha:}}`, R's `pal_viridis()`
  (`ColorOperations.viridis/2`), `{:shape, :solid}` or `{:shape, :open}`, R's `pal_shape()`, six
  shapes by name, `:linetype`, R's `pal_linetype()`, 13 line types as dash patterns,
  `{:manual, values}`, R's `pal_manual()`, a list, and `{:brewer, %{palette:, direction:}}`, R's
  `pal_brewer()`. A `nil` place gives `nil`. Each matched R to the last digit; its tests pin R's
  figures. ggplot2's palettes, the ordinal sequences and a manual
  palette matched by name or by breaks, are Giggly's (`scale.md`).
- **A discrete palette past its end gives `nil`, as R gives `NA`, and raises nothing**: R also
  warns, which a pure library cannot, and refusing is the caller's, so no message of the package
  names one (Giggly's scale raises, `scale.md`). No levels give none, where R's hue palette
  refuses them.
- **The shape palette gives R's 16, 17, 15, 3, 7 and 8, or open, 1, 2, 0, 3, 7 and 8, as their
  names** (`:circle_small`, `:triangle`, `:square`, `:plus`, `:square_cross`, `:asterisk`, the
  first three open `:circle_open`, `:triangle_open`, `:square_open`), Giggly's scale test pinning
  each name to R's number through the table points are drawn from. **The line type palette gives
  R's 13 in order, `"solid"` as `{}` and each hex pattern as a tuple of its lengths**, its test
  pinning `pal_linetype()`'s output.
- **A brewer palette is exactly R's `pal_brewer()`, its colours RColorBrewer's own sets**, copied
  by the R script in `priv/palettes/brewer.csv`'s header and read at compile time behind a
  `CorePurity` waiver of their own, never typed or derived: a set for each count from 3 to the
  palette's largest, fewer than 3 the start of the set of 3, past the largest `nil`, reversed for
  a `direction` of -1 after that padding, so the `nil`s come first, as R's `NA`s do. A palette is
  named as R spells it, and `brewer_palettes/1` gives each type's names in the order R numbers
  them; a name R does not spell so is refused, where R warns and gives Greens. The file carries
  ColorBrewer's copyright and Apache 2.0 notice, and the moduledoc its acknowledgment.
- **A palette's type, levels and name are R's** (`Palette.type/1`, `nlevels/1`, `named/1`; R's
  `palette_type()`, `palette_nlevels()`, `get_palette()`): `nil` where R gives `NA`, a manual
  palette's type guessed as `pal_manual()` guesses it, `nil` where R names a storage type, a
  colour being a string `ColorOperations.parse/1` reads, so never `:none`. **A name is one of
  scales' own, in any case**, each with R's defaults; grDevices' names are refused, the message listing scales'
  (design-log §4, the entry beginning "A palette's name is one of scales' own").
- **A palette of one kind is converted inside the other kind's function** (design-log §4, the
  entry beginning "A palette of one kind is converted"): `continuous/2` takes a discrete palette
  as R's `as_continuous_pal()` does, a gradient through its `nlevels/1` colours or its numbers
  joined by straight lines, `nil` outside them; `discrete/2` samples a continuous one at R's
  `seq()`. What R cannot convert is refused, and so are `:identity` and `{:abs_area, max}`, which
  R hands back unconverted. Its tests pin R's values at places that tell `nlevels/1` apart (hue's
  last colour is its 255th hue).
- **A discrete palette's spread is R's `seq()`** (`Palette.spread/2`): its ends exact, each value between found
  by steps from the first (the fourth of seven is 0.54999999999999993).
- **A gradient is exactly R's `pal_gradient_n()`** (design-log §4, the entry beginning "A gradient
  is one palette"), which R's two- and three-colour gradients are too: its colours spaced evenly
  from 0 to 1 by R's `seq()`, a place between two neighbours blended in CIE L*a*b*
  (`Scales.ColorOperations`), each channel interpolated as R's `approxfun()` does, and a place at
  a colour taking that colour exactly, as `colour_ramp()` blends; one colour is every place's. It
  matched R on every place sampled; its tests pin R's colours. **Its alpha is a fourth channel**
  (design-log §4, the entry beginning "A gradient's values move a place"), interpolated always,
  since an opaque one stays 1 and writes none, its byte rounded half to even; `:none` and
  `"transparent"` are R's white with no alpha. A place outside 0 to 1 gives `nil`, as R's `NA`,
  but one colour's. **`values` move a place first, exactly as R's `approxfun()` takes them**:
  each value at its place by R's `seq()`, a `nil` dropped, sorted, equal ones at their places'
  mean, any count; outside them `nil`; fewer than two left raise. R's warning on equal values is
  not given. All of 3,000 random gradients matched R, alphas, `NA`s and values among them.
- **The hue palette is exactly R's `pal_hue()`**: a range less than a degree short of the whole
  circle, taken modulo 360 as R's `%%` takes it, leaves its last `360 / n` degrees off, any other
  is spread end to end, the hues by the same `seq()`, each colour
  `Scales.ColorOperations.from_hcl/3`, reversed for a `direction` of -1; it matched R on every
  range, chroma, luminance, direction and count sampled, and its tests pin R's colours for counts
  whose last hue lands on 360 and past it and for ranges either side of the degree. Each hue is
  taken modulo 360 first, as R takes it, since `from_hcl/3` caps a hue at 0 and 360 as farver
  does; a chroma below 0 and a luminance outside 0 to 100 are farver's nearer bounds.
- **The grey palette is exactly R's `pal_grey()`, `grey.colors()`**: the levels spaced evenly
  once raised to the power 2.2, brought back by `1 / 2.2` and written as `gray()` writes them, the
  byte `255 * level + 0.5` truncated. R spaces them with `seq.int()`, which in R 4.6.1 steps on
  from the start as `seq()` does, so `seq()` it is.
- **The rescaling functions are R's `rescale()`, `rescale_mid()` and `rescale_max()` to the last
  digit** (`Scales.Bounds`), on lists as R's are on vectors, a `nil` in giving `nil` out, as R's
  `NA`: either range zero wide by `zero_range()` puts every value at the middle of `to`, which R
  checks and the formula alone would not; over a high end of 0, `rescale_max()` gives R's IEEE
  answer, an infinity of the signs' product, a negative zero's sign counting, or NaN as `nil`. Its
  tests pin R's figures; Giggly's rescalers call these, and Giggly raises at an infinity.
- **Censoring and squishing are R's `oob_censor()` and `oob_squish()` on finite numbers**
  (`Scales.Bounds`; design-log §4, the entry beginning "A squished value is R's"): a number outside
  the range `nil`, or moved onto its ends in R's order, low first, so a range high to low squishes
  every number to its high end; the infinities, `nil` and what is not a number kept; `:nan` kept
  by `squish/2`, `nil` from `censor/2`, as ggplot2's position scale maps it. An end is a number
  or `nil`, which moves nothing on its side; an infinite end is refused. Their tests pin R's
  figures.
- **Training follows R's `scales`** (`Scales.DataRange`). A continuous range spans the finite numbers only (`nil` and
  the non-finite floats skipped). **A discrete scale merges each training as R's
  `discrete_range()` does** (design-log §4, the entry beginning "A discrete scale fed levelled and
  plain values"), handed a column at a time, with the levels of the factor its values are of or
  `:none`: a factor brings the levels its values hold, in their order, the missing value after
  them, as `drop = TRUE`; other values their distinct values sorted, `nil` last; values matched by
  `DataRange.key/1`, so `4` and `4.0` are one; a factor's levels lead the rest, and the range's
  factor flag, set by its first training, says whether new values follow the levels held or
  everything is sorted again; no values train nothing.
- **Values with no levels of their own are ordered by `DataRange.level_key/1` alone**, and the assembly
  hands the same key to grouping, which orders their combinations by it, so group ids and axis
  positions agree; a factor's values are ordered by its levels, which grouping reads from the
  frame as the scale is handed them. The rule exists once, and grouping does not depend on scales
  to use it.
- **A transformation is a module implementing `Scales.Transform`**, resolved from its name
  there and handed to each of its callbacks, so the date-time one reads its zone; it carries what
  R's object carries and a scale reads: the transformation, its inverse,
  its domain, and its axis's default breaks, minor breaks and labels (`breaks`, `minor_breaks`,
  `format`). **A label is made from the break and the extent** (`format/2`), since a date's
  format is the step chosen for the whole axis; a number's ignores the extent and is written once
  the breaks outside it are dropped. Breaks the transformation did not choose, given or laid by a
  width, are handed `:given` instead of the extent, and a date writes them in full, `2026-09-21`,
  as R's `format()` writes a date its pretty breaks did not name. **Breaks follow ggplot2's `get_breaks()`**: the extent
  squished into the transformed domain (log10 from -100, sqrt from 0), turned back into data
  units, broken there, and transformed back, **in the order that leaves them**, so reverse's and
  reciprocal's descend, as R draws them; labels are written, and a labels function handed, the
  breaks turned back, as R turns them (`10^x`, `x * x`). **A value outside the domain is R's**:
  log10 places 0 at minus infinity, at the panel's edge, and a negative value, as sqrt does, at
  `nil`, R's NaN; reverse swaps the infinities, reciprocal places 0 at plus infinity.
- **log10's breaks are `Breaks.log/2`'s, five wanted in base 10** (`Transform.Log10`), on the
  extent turned back into data units, put back into log space; its test pins R's own axis, labels
  and minor breaks, for each of `breaks_log()`'s branches, and compares its breaks with
  `Breaks.log/2`'s, whose test pins R's figures. sqrt, reverse and reciprocal take extended
  breaks on the data range, as R's `extended_breaks()` does.
- **A date scale works in days since 1970-01-01, as R stores a date** (`Transform.Date`, R's
  `transform_date()`): a date is a float of its days, a missing one `nil`, and a position turned
  back the day it falls on, rounded down, as R's `format()` writes it; it trains, expands and
  is placed as any continuous scale, a single date 0.05 days either side. **Its breaks are exactly
  R's `pretty()` for dates** (`Scales.DateBreaks`, grDevices' `prettyDate()`): five days or less is
  every day, widened by five less its length, rounded half to even; longer takes the calendar step,
  a day to a thousand years, that cuts the extent closest to five times, from its start truncated
  to the step's unit (a Monday for weeks), or, where that step cuts it more than five times, the
  next coarser one where that comes closer, as R does; R's finer neighbour for too few never comes
  closer and is left out (design-log §4, the entry beginning "A date-time's breaks under a day").
  Each is labelled in its step's format, written as R's `format()` writes it, a year unpadded.
  **A date never reaches a step under a day.** Its minor breaks are the identity's
  (`MinorBreaks.regular/2`) on the days. A surviving mutant there is judged against R as an
  extended-breaks one is (below): its test pins R's own breaks for each case and for each random
  extent where a mutant departed. **A width's breaks are exactly R's `breaks_width()` for dates**
  (`DateBreaks.width/2`, `fullseq()`): from the extent's start rounded down to the step's unit —
  a day count to the nearest multiple of the step's days since 1970-01-01, half to even, a week
  to its Monday, a month to its 1st, a year to 1 January, whatever the count — to its end plus
  the count of a unit's most days (1, 7, 31, 365) rounded down, every step; its test pins R's
  own output for each unit and each rounding.
- **A date-time scale works in seconds since 1970-01-01 00:00 UTC, as R's `POSIXct` stores one**
  (`Transform.Datetime`, R's `transform_time()`): a date-time's whole microseconds divided once by
  a million, the double nearest the instant, a naive one's as though its clock were UTC's, a
  missing one `nil`; a plot's limits or breaks of the other kind raise, as a column's would be
  refused. **Its breaks are exactly R's `pretty()` for date-times** (`DateBreaks.pretty_datetime/2`,
  the date steps' table extended below a day: seconds, minutes and hours, each with R's format and
  unit to truncate to), an extent under a second widened to whole seconds 2.5 either side; three
  branches of R's are left out, none changing a break inside the extent or its label: its added
  ticks where a second cuts the extent once, which keeps its breaks here, its trimming, and its
  finer neighbour (design-log §4, the entry beginning "A date-time's breaks under a day"). Its
  test pins R's breaks for every step and format, R's breaks inside each short extent, and R's on
  the first extent where each mutant of the step table departed; a nudge of a step's length that
  departs on none of R's tables is judged against the code on a dense sweep round its step's
  boundaries, and is equivalent only if it never departs there either. **A width's breaks are
  exactly R's `breaks_width()` for
  date-times** (`DateBreaks.datetime_width/3`): seconds and minutes from the nearest multiple of the
  step since 1970-01-01, half to even, the rest from the start of the unit, rounded up by the
  step's most seconds, stepped by elapsed time but months and years, stepped on the calendar; its
  test pins R's for each unit and rounding. A break it did not choose is written as R's
  `format()` writes it: the date alone where every one is at midnight, else to the second.
  **Breaks are laid, and labels written, on the clock of the scale's zone** (`DateBreaks`'s
  `clock`: UTC's for `:default` and `:naive`, else the zone and its database), as R's are in its
  `tz`: truncated to a minute or an hour, a time keeps its own offset from UTC, as R keeps its
  daylight-saving flag; truncated to a day or longer, its wall-clock time is read again, a time a
  change skips at the offset before it and one a change repeats as the earlier (design-log §4, the
  entry beginning "A local time a change of offset skips or repeats"); a calendar step advances
  the truncated wall-clock time, a width's the start's once read, as R's `seq()` advances each.
  Its test pins R's breaks across the changes of New York, Kolkata, Lord Howe, Havana, Asuncion
  and Apia, from 23,771 random and change-clustered extents in 19 zones and 7,599 widths, all
  matched but where R's answer rests on glibc: a repeated midnight, or an hour repeated with one
  daylight-saving flag, read at the offset R last used, and a skipped midnight of a change of
  standard offset, which glibc reads after it for 17 of the 52 since 1970.
- **A time scale works in seconds since midnight, as R's `hms` stores one** (`Transform.Time`,
  R's `transform_hms()`): a time's whole microseconds divided once by a million, a missing one
  `nil`. **Its breaks are exactly R's `breaks_hms()`**, `Breaks.timespan/2` on the extent's
  seconds, five wanted; **its labels hms's, rounded to the microsecond half to even,
  less two of hms's marks**: six zero decimals where a break is a rounding error off a whole
  second, and spaces padding every label to the widest (design-log §4, the entry beginning "A
  time of day's labels"). A width's breaks are R's `breaks_width()` for times, every multiple of
  the step from the extent's start rounded down. A break turned back, for a labels function or a
  format, is a `Time` wrapped past midnight. Its test pins R's breaks and labels at the hours',
  days' and weeks' switches, past midnight and before it, under a second and on a half microsecond; all of 4,900
  random and switch-clustered extents and 3,000 widths matched R.
- **Every transformation's minor breaks are R's `scales::regular_minor_breaks()`**
  (`Scales.MinorBreaks`), in transformed space, with two intervals per gap, on the breaks in the
  transformation's order, the first gap's step added before and after them as R adds it, with
  `reverse = TRUE` for reverse alone: one more step past an outermost break the extent reaches beyond,
  then each gap's middle as R's `seq()` finds it, its start plus half its width, which differs
  from the two ends' mean in the last bit (an example pins it), and none for fewer than two breaks.
- **A number of breaks wanted, `n:`, reaches extended breaks alone** (`Breaks.extended/2`,
  `Transform.breaks/3`), as R's `transformation$breaks(limits, n)`: the identity, sqrt, reverse
  and reciprocal pass it on; log10, date, date-time and time refuse it, their own counts waiting
  for the breaks increment; it is a whole number from 2, as R's search finds nothing for one and
  never ends for none.
- **A width's breaks are exactly R's `fullseq()` and `breaks_width()`, on numbers, dates,
  date-times and times** (`Breaks.fullseq/3`, `Breaks.width/3`; design-log §4, the entry
  beginning "Breaks a width apart"): numbers from the low limit rounded down to a multiple of the
  size to the high one rounded up, stepped as R's `seq()` steps, the limits in either order, one
  number half a size either side and never padded; dates, date-times and times their
  transformation's width (above), a step of one unit. An offset is a number, or steps moving each
  break in turn, a month past its end carried into the next as R normalises one, a date-time's
  month read again on its zone's clock as a width's start is, the breaks left unsorted as R leaves
  them; a time of day wraps past midnight. Its tests pin R's figures; all of 3,000 numeric, 2,000
  date and 935 New York cases matched R.
- **The identity's breaks are exactly R's `labeling::extended()` breaks**, five wanted unless
  `n:` says, its three
  degenerate cases and the scores R takes to minus infinity included (`Scales.Breaks`), but on
  ranges over about 3e23 wide reaching zero, where R's long-double modulus denies a rounded break
  through zero the bonus for it (`Breaks`' opening comment). **`only_loose:` and `weights:` are
  labeling's `only.loose` and `w`**, a square in a score R's product, `x * x`, never `x ** 2`,
  whose `:math.pow/2` can land a bit away and turn a tie: of two sequences scoring alike the
  first found wins, as in R. A search that finds no sequence above labeling's starting score of
  -2, which only weights other than the defaults bring about, raises, as R fails; the weights'
  first three are positive and the nice numbers two or more, where R's search never ends or
  fails. All of 4,000 random ranges, counts, weights, nice numbers and `only.loose`, and 3,000
  more `only.loose` on the default weights, matched R. Its test
  pins R's own output for a range of every winning nice number, skip, count and zero bonus, and
  for each boundary, since a slip in one score shows only where that
  score decides the winner, and for other counts on ranges where the count decides; a row that
  stops matching is a bug in the port, and the table is regenerated only by running R (labeling
  0.4.3 in Docker's `r-base` image).
- **A logarithmic axis's breaks are exactly R's `breaks_log()` and `log_sub_breaks()`**
  (`Breaks.log/2`; design-log §4, the entry beginning "Breaks for a log, exponential or timespan
  axis"), in any base above 1: R's breaks whole, the extra power or multiple either side of the
  limits included, the multiples evenest on the logarithm first, a base of 2 or less its powers
  alone, else `Breaks.extended/2` on the limits; a logarithm in base 10 and 2 is their own
  function, else the ratio of natural ones, as R takes it. A power is the double nearest it,
  `:math.pow/2`, where R's x86 long-double power lands a bit away on a few (1.2 cubed, 1.1 to the
  fourth: 2 of 7,000); all of 4,000 random limits, counts and twelve bases matched R but 63 in
  base 1.2, each by that bit. Limits of 0 or below are refused, where R fails; a base of 1 or
  below too, where R gives 1, or fails on most limits. **An exponential axis's breaks are R's
  `breaks_exp()`** (`Breaks.exp/2`), in R's order, high to low then 0, its fallback
  `Breaks.extended/2` with every option `extended/2` takes, R's `...`; **a span of time's are R's
  `breaks_timespan()`** (`Breaks.timespan/2`), seconds where R gives a `difftime`, the units
  `:second` to `:week` as the package's steps name them. Their tests pin R's figures, each branch
  and each unit's switch; all of 2,000 exponential and 3,000 timespan cases matched R.
- **Labels are written the Elixir way, not R's** (`Scales.Labels.plain/1`): `inspect`'s plain
  decimals, rounded to 15 significant digits, as many decimals on every label as the most precise
  needs, none when all are whole, negative zero as `0`, never scientific, no thousands separators,
  so a log axis's `1e+05` is written `100000`.
