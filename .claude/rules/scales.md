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
  `Scales.Labels.Format` and the `Scales.Transform.*` modules stay internal, reached through
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
  `pal_brewer()`. A `nil` place gives `nil`, an infinite or NaN one R's answer. Each matched R to
  the last digit; its tests pin R's
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
- **A double is R's: `nil` its `NA`, `:nan` its NaN, `:infinity` and `:neg_infinity` its
  infinities** (`t:Scales.double/0`; design-log §4, the entry beginning "A NaN is `:nan`"), and
  **`Scales.Double` is the one home of R's IEEE arithmetic on them**, an infinity past the largest
  double, NaN for 0/0, Inf − Inf and Inf × 0, a zero's sign read from its bit; its operators take
  no `nil`, which their callers set aside first. **It is the one home too of the elementary
  functions transformations are built from**, a logarithm in a base, a power (R's `^` for any
  base and exponent, its grid of infinities, zeros and negative bases R's), log1p, expm1, the
  hyperbolic sine, cosine and tangent, asinh, atanh, the sine and arcsine, and the standard
  normal's distribution, quantile and density, each R's at the infinities, NaN and zero; `Breaks`
  and `Labels` take their logarithms from it. What Erlang lacks, log1p, expm1 and the normal's
  three, is measured methods, never ported (design-log §4, the entries beginning "The scales
  package carries every transformation" and "A distribution's spread"). Its tests pin R's answers
  and, in `test/scales/fixtures/r_elementary_4.6.1.csv`, each function's measured ulps from R's.
- **The rescaling functions are R's `rescale()`, `rescale_mid()` and `rescale_max()` to the last
  digit** (`Scales.Bounds`), on lists as R's are on vectors, a `nil` in giving `nil` out, as R's
  `NA`, and NaN `:nan`, given or worked out; a value, an end or a midpoint may be an infinity,
  through `Scales.Double`: either range zero wide by `zero_range()` (both ends one infinity too)
  puts every value at the middle of `to`, R's long-double mean, which R checks and the formula
  alone would not, but `nil` for `nil` and NaN, as R gives `NA`; over a high end of 0,
  `rescale_max()` gives an infinity of the signs' product, a negative zero's sign counting, or
  `:nan`. `rescale_none/1` gives the values back. Its tests pin R's figures; Giggly's rescalers
  call these, and Giggly raises at an infinity.
- **A range is widened by R's `expand_range()` to the last digit** (`Bounds.expand_range/2`;
  design-log §4, the entry beginning "A range is widened"): each end by `width * mult + add`,
  `mult:` and `add:` a number or a pair, one for each end, a zero-wide range taking
  `zero_width:` as its width, a range high to low widened outward and a negative amount
  narrowing it, as R's; an infinite end R's IEEE answer, `:nan` where no multiple meets an
  infinite width; a `nil` or NaN end refused by guard, as R fails, and an infinite amount by
  NimbleOptions, where R takes one. Its tests pin R's figures; `Giggly.Scale` widens every extent
  through it.
- **Values outside a range are R's `oob_*` family** (`Scales.Bounds`; design-log §4, the entries
  beginning "A squished value is R's" and "A NaN is `:nan`"): `censor/2` and `squish/2` move
  finite numbers alone, `censor_any/2` and `squish_any/2` the infinities too, to `nil` or onto
  the ends in R's order, low first, so a range high to low squishes every number to its high end;
  `squish_infinite/2` replaces `:neg_infinity` by the low end, then `:infinity` by the high, a
  finite number kept; `discard/2` drops what is outside, `nil` kept and NaN made `nil`;
  `keep/2` changes nothing. `nil`, NaN and what is not a number are kept by the rest. An end is a
  number, an infinity, compared as R compares it, or `nil`, which bounds nothing on its side, in
  `discard/2` too, where R gives `NA` for every value (a departure). Their tests pin R's figures.
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
  there (a user's own from the `%Scales.Transform{}` that `Transform.new/2` makes, a composition
  from `{:compose, parts}`) and handed to each of its callbacks, so the date-time one reads its
  zone; `resolved/1` (`@doc false`) says whether a name resolves, `:unknown` or a composition's
  refusal, for a caller checking one where it is given, as Giggly's `transform:` does; it carries what R's object carries and a scale reads: the transformation, its inverse,
  its domain, and its axis's default breaks, minor breaks and labels (`breaks`, `minor_breaks`,
  `format`). **A label is made from the break and the extent** (`format/2`), since a date's
  format is the step chosen for the whole axis; a number's ignores the extent and is written once
  the breaks outside it are dropped. Breaks the transformation did not choose, given or laid by a
  width, are handed `:given` instead of the extent, and a date writes them in full, `2026-09-21`,
  as R's `format()` writes a date its pretty breaks did not name. **Breaks follow ggplot2's `get_breaks()`**: the extent
  squished into the domain transformed, its ends sorted, at both
  ends (log10 from -100, sqrt from 0, exp from 0, yj(-1) at 1, the bound its values never pass),
  a transformed domain of no width or one end squishing nothing, a date's, date-time's or time's
  never squished, turned back into data
  units, broken there, and transformed back, **in the order that leaves them**, so reverse's and
  reciprocal's descend, as R draws them; labels are written, and a labels function handed, the
  breaks turned back, as R turns them (`10^x`, `x * x`). **A domain is held in data units, as
  R's `domain`** (log10's from 1e-100). **A value outside the domain is R's**: log10 places 0 at
  minus infinity, at the panel's edge, and a negative value, as sqrt does, at `:nan`; reverse
  swaps the infinities, reciprocal places 0 and `-0.0` at the infinities of their signs, each
  through `Scales.Double` where R's IEEE arithmetic decides. **A transformation of numbers has
  R's derivatives both ways and `trim_to_domain/2`** (R's `d_transform`, `d_inverse` and
  `trim_to_domain()`), every double R's, its tests R's golden over the infinities, both zeros,
  `nil` and NaN; a date's, date-time's or time's has neither and raises, as R's has no
  derivatives and takes numbers. `trim_to_domain/2` gives `:none` with nothing to range over,
  where R warns at an empty `range()` (design-log §4, the entry beginning "A transformation gives R's doubles").
- **A logarithm in a base's breaks are `Breaks.log/2`'s, five wanted unless `n:` says, in its
  base** (`Transform.Log`: `:log` in base e, `:log2`, `:log10`, `{:log, base}`), on the extent
  turned back into data units, put back into log space, so `:log`'s are powers of e; its test
  pins R's own axis, labels and minor breaks, for each of `breaks_log()`'s branches, and compares
  its breaks with `Breaks.log/2`'s, whose test pins R's figures. log1p, exp, asinh, the
  pseudo-logarithm, sqrt, reverse, reciprocal, asn, atanh, the probabilities, Box-Cox, modulus
  and Yeo-Johnson take extended breaks on the data range, as R's `extended_breaks()` does; an
  exponential's extent reaching zero or below is broken on its high end alone, as R's breaks drop
  its NaN, and **a Box-Cox's, modulus's or Yeo-Johnson's end that turns back to an infinity** past
  the bound its values never reach is set aside, R's five copies of the other end found, none
  where both do (design-log §4, the entry beginning "An axis past a bound"). **A break at an end
  of a domain the transformation takes to an infinity is that infinity**, logit's 0 and 1, as
  R's, outside every extent; a caller keeps numbers alone.
- **Every transformation of scales 1.4.0 is a name** (design-log §4, the entries beginning "The
  scales package carries every transformation", "A logarithm's or exponential's base" and "A
  distribution's spread"): a base
  is a number above 1, a pseudo-logarithm's sigma and a distribution's `sd:` or `scale:` above 0,
  its `mean:` or `location:` a number, each checked by guard where the name is resolved, so
  `FunctionClauseError` wherever it is handed, where R also takes a falling base below 1 and a
  spread of 0; `{:pseudo_log, ...}` takes `sigma:`, `base:` or both, once each, and
  `{:probability, :normal, ...}` and `{:probability, :logistic, ...}` their own two likewise,
  `:probit` and `:logit` their standard forms; an exponent is any number, a Box-Cox offset one
  from 0 up and a modulus offset one from 1 up, below which R's modulus no longer rises, a span
  of time's unit `:second` to `:week` (design-log §4, the entry beginning "Box-Cox, modulus,
  Yeo-Johnson and a span of time"). `{:log, 10}` and
  `{:log, 2}` place every value where `:log10` and `:log2` do, as R's `log(x, base)` takes those
  bases by their own functions; R's `exp(1)^x`, not `exp(x)`, is `:log`'s inverse and `:exp`.
  Every value, derivative, domain and break is R's but where the platform's asinh, atanh and sine
  are not correctly rounded (asinh and atanh within 1 ulp of R's, the pseudo-logarithm and asn's
  inverse 2), log1p's and expm1's measured methods (within 2 and 1), and the normal's, through the
  platform's erf and erfc, which R's does not use (its quantile within 5, distribution 3, density
  7, nearer the truth than R's where they part under glibc 2.39; a mean
  or the forward derivative carries the quantile's last bit, the derivative's at the far tail
  multiplied by about its square, 5.2e-13 relatively); R's `+0` for a negative zero from log1p,
  expm1, asinh, sinh, the pseudo-logarithm, asin, sin, tanh and atanh on a vector. The
  derivatives are in the order that gave R's doubles, the pseudo-logarithm's `1 / (sqrt(1 + x *
  x / (4 * sigma * sigma)) * 2 * sigma * log(base))` alone of twelve; a probability's forward
  derivative is 1 over its inverse's at the value transformed, as R's. Their tests pin R's
  figures over the nine doubles, ggplot2's axes and `test/scales/fixtures/r_elementary_4.6.1.csv`'s
  bounds. **A figure resting on the platform's asinh, atanh, erf or erfc is pinned as R's within
  these bounds, never as one C library's double**: glibc 2.43 rounds them otherwise than 2.39,
  moving R's own asinh and atanh with them, and the normal's drift is accepted rather than an
  error function of the package's own (design-log §4, the entry beginning "The platform's").
- **The Box-Cox, modulus and Yeo-Johnson transformations are scales' documented formulas**
  (`Transform.BoxCox`, `Transform.Modulus`, `Transform.YeoJohnson`, on `Transform.Power`'s
  `(base^exponent - 1) / exponent`; design-log §4, the entry beginning "The Box-Cox, modulus and
  Yeo-Johnson transformations"): an exponent within 1e-7 of 0, and yj's `2 - exponent`, counts
  as 0, as R's; every double R's but the platform's last bit, R's `^` being x86's `powl` (Box-Cox
  in 3 parts from it on 65 of 3,000, the subtraction then amplifying a bit near 1) and log1p's and
  expm1's methods a double off (`fixtures/r_power_4.6.1.csv`, six rows); the cancellation near 0
  is R's too. A missing value's derivative is 1 where its power is 0, R's `NA^0`; yj's NaN is
  missing and either zero `0.0`, as R's; yj's inverse derivative below 0 at an exponent of 2 is
  `exp(-x)`, where R's fails. **A Box-Cox value below minus its offset is NaN**, where R refuses
  the whole vector, and **its domain is R's, from 0 whatever the offset**, so an axis finds no
  break below 0 (design-log §4, the entry beginning "Box-Cox's domain"). **Their labels are each
  default break's value in data units**, found again from the extent, a given break turned back
  at 14 digits, where the round trip keeps as few as three (design-log §4, the entry beginning
  "Box-Cox, modulus and Yeo-Johnson labels"). Their tests pin the fixture, ggplot2's axes, both
  kinds past a bound, and the refusals.
- **A span of time is its seconds** (`Transform.Timespan`, R's `transform_timespan()`): a value
  times its unit's seconds, turned back times one over them, as R converts a `difftime`'s units,
  numbers where R gives one; `Breaks.timespan/2` on the extent turned back into its unit, its
  labels `Labels.timespan/2`'s in the unit, minor breaks regular, no `n:` and no derivatives, as
  R's take none, `trim_to_domain/2` R's.
- **A composition is `{:compose, [part, ...]}`** (`Transform.Composition`, R's
  `transform_compose()`; design-log §4, the entries beginning "A composition is", "A
  composition's breaks", "A composition's labels", "A composition's domain" and "A date,
  date-time or time transformation comes first"): values through each part and back through each
  inverse, a `nil` passed back uncalled, since built-in inverses take positions; derivatives R's
  running chain-rule product, only where every part has one; breaks and labels the first part's,
  on the extent turned back into its space, `n:` handed on; minor breaks R's regular ones
  unreversed; its domain R's rule but the range's ends ordered as a pair, none left `ArgumentError`; a date, date-time
  or time part first only, the composition then never squished, its steps laid through
  `width/3`. Its tests pin R's doubles at the nine doubles and the edges, the domains and trims,
  ggplot2's axes, and its reversed date, date-time and time axes.
- **A transformation of your own is a `%Scales.Transform{}` made by `Transform.new/2`**
  (`Transform.Custom`, R's `new_transform()`; the entries beginning "`Transform.new/2` takes"
  and "A transformation of your own"): its functions, of one value, are handed every value in
  its domain, its ends and their infinities among them, an integer as a float, `nil` and `:nan`
  kept and a value outside the domain `:nan` uncalled, an answer but a double, an infinity,
  `:nan` or `nil` refused with `ArgumentError`; its breaks its function's on the extent turned
  back, an end turning back to anything but a number set aside as Box-Cox's are; its labels its
  function's of the breaks turned back, by default `Labels.plain_round_tripped/1`'s, 14
  significant digits first, as R's `format()` hides a cube root's `9999.99999999999`. Its tests pin ggplot2's axes of user transformations, alone
  and as a composition's part.
- **A date scale works in days since 1970-01-01, as R stores a date** (`Transform.Date`, R's
  `transform_date()`): a date is a float of its days, a missing one `nil`, and a position turned
  back the day it falls on, rounded down, as R's `format()` writes it; it trains, expands and
  is placed as any continuous scale, a single date 0.05 days either side. **Its breaks are exactly
  R's `pretty()` for dates** (`Scales.DateBreaks`, grDevices' `prettyDate()`), `n` intervals
  wanted, five unless `n:` says: `n` days or less is every day, widened by `n` less its length,
  rounded half to even; longer takes the calendar step, a day to a thousand years, that cuts the
  extent closest to `n` times, from its start truncated to the step's unit (a Monday for weeks);
  where that step cuts it more than `n` times, as many of its breaks beyond the extent as the
  excess are dropped, shared between its ends as R shares them, and where they still do, the next
  coarser step is taken where that comes closer, as R does; R's searches for a finer step never
  come closer and are left out (design-log §4, the entries beginning "A date-time's breaks under a
  day" and "`n:` reaches"). Each is labelled in its step's format, written as R's `format()` writes
  it, a year unpadded, the labels of breaks found with `n:` given the same `n:`.
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
  refused. **Its breaks are exactly R's `pretty()` for date-times** (`DateBreaks.pretty_datetime/3`,
  the date steps' table extended below a day: seconds, minutes and hours, each with R's format and
  unit to truncate to, one and three hours labelled with the day beyond a day), an extent under a
  second widened to whole seconds `n / 2` either side, at least one for an instant and at most 30;
  where a second cuts the extent fewer than `n %/% 2` times, a second added on the right, then the
  left, until it does, as R adds them (design-log §4, the entry beginning "A date-time's breaks
  under a day"). All of 2,910 date and 9,000 date-time extents in three zones, with `n` from 0 to
  20, matched R, every break and label. Its test pins R's breaks for every step and format, R's
  breaks inside each short extent, and R's on the first extent where each mutant of the step table
  departed; a nudge of a step's length that departs on none of R's tables is judged against the code
  on a dense sweep round its step's boundaries, and is equivalent only if it never departs there
  either. **A width's breaks are exactly R's `breaks_width()` for
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
  `reverse = TRUE` for reverse alone, a composition's unreversed whichever way it runs, as R's:
  one more step past an outermost break the extent reaches beyond,
  then each gap's middle as R's `seq()` finds it, its start plus half its width, which differs
  from the two ends' mean in the last bit (an example pins it), and none for fewer than two breaks.
- **A number or a width of minor breaks to each gap is exactly R's `minor_breaks_n()` and
  `minor_breaks_width()`** (`MinorBreaks.n/3`, `width/4`; design-log §4, the entry beginning
  "Minor breaks a number or a width"): R's `loop_breaks()`, the low limit to the first break, each
  pair of neighbours in the order given, the last break to the high limit, a value kept the first
  time it is laid, 0 and -0 one; a number's gaps spread as `Palette.spread/2`, on numbers alone; a
  width's laid by `Breaks.width/3`, on whatever it takes, `offset:` 0 unless given. No breaks are
  refused, where R fails. **A logarithmic axis's are exactly R's `minor_breaks_log()`**
  (`MinorBreaks.log/2`): R's values in R's order, the multiples 2 to 9 but 5 standing for R's
  `setdiff()`, which removes only the powers and their fives; limits both 0 refused, where R
  fails; the `detail` attribute left out. Their tests pin R's figures; all of 4,000 numeric, 2,000
  date, 1,712 date-time and 4,014 log cases matched R, and 1,495 times but where R's `hms` runs
  past midnight.
- **A number of breaks wanted, `n:`, reaches every transformation's own breaks but time's and a
  span of time's**
  (`Transform.breaks/3`, `format/4`; design-log §4, the entry beginning "`n:` reaches"), as R's
  `transformation$breaks(limits, n)`: extended breaks' under the identity, sqrt, reverse and
  reciprocal, log1p, exp, asinh and the pseudo-logarithm, a whole number from 2, as R's search
  finds nothing for one and never ends for none; `Breaks.log/2`'s under a logarithm in a base,
  from 1; R's `pretty()` under the date and date-time
  transformations, from 0, as R takes it, and their labels found with the same `n:`, as R's
  breaks carry theirs as names. Time and a span of time refuse it, as R's `transform_hms()` and
  `transform_timespan()` take no number. A composition hands it to its first part, where ggplot2
  ignores it with a warning; a user's breaks function of two arguments is handed it, and one of
  one refuses it.
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
  first found wins, as in R. A score is summed as R sums it, legibility's weight included, though
  it adds alike to every sequence: two sequences a rounding apart turn on it (the default 0.05
  decides one). A search that finds no sequence above labeling's starting score of
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
- **Round steps' breaks are R's `breaks_pretty()`** (`Breaks.pretty/2`; design-log §4, the entry
  beginning "`n:` reaches"): on numbers, the width over the number wanted, one for none, rounded
  to 1, 2, 5 or 10 times its power of ten, up from just above R's switches, 1.4, 2.8 and 7,
  measured from R's output since R documents every step but that one; every multiple from the
  low limit's down to the high one's up, by the quotient, a step in where that multiple itself
  reaches the limit and never one out, spread as R's `seq()` spreads them, the multiple zero
  exactly 0. Dates and date-times are their transformation's, typed, each a `{break, label}` pair,
  the label R's name for it, `Transform.format/4`'s with the same `n:`, a zero-wide range's
  written in full as R writes a break it has not named (design-log §4, the entry beginning "A
  breaks function"); times numbers' on their
  seconds, wrapped past midnight; a zero-wide range its first limit. Refused: limits past 1e307 and a width per interval under the smallest
  normal float, where R answers or warns. All of 1,500 whole-number ranges, 2,946 of 2,992 round
  and 2,567 of 2,699 random ones matched R, the rest at an end, where R counts a limit within a
  ten-billionth of a step of a multiple as on it, as only its C says. Its tests pin R's figures
  at each switch and each rounding.
- **Labels are written the Elixir way, not R's** (`Scales.Labels.plain/1`): `inspect`'s plain
  decimals, rounded to 15 significant digits, as many decimals on every label as the most precise
  needs, none when all are whole, negative zero as `0`, never scientific, no thousands separators,
  so a log axis's `1e+05` is written `100000` and a natural one's powers of e to 15 digits. **A
  break turned back through an inverse that does not give it back exactly is rounded to 14
  significant digits first** (`Labels.plain_round_tripped/1`: log1p's, exp's, asinh's, the
  pseudo-logarithm's, a probability's), so `10000` under sigma 2, base 10 is not
  `9999.99999999999`, nor `0.0009` under logit `0.000900000000000001`; asn's and atanh's showed
  none and stay plain; its test and the axes' pin it.
