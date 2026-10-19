---
paths:
  - "lib/giggly/scale.ex"
  - "lib/giggly/scale/**"
  - "test/giggly/scale_test.exs"
  - "test/giggly/scale/**"
---

# Scales

`Giggly.Scale` decides what kind of scale a column needs, puts values through a scale's
transformation, trains a scale over the values it is given, and maps values to their positions,
or, for an aesthetic other than position, through the scale's palette to the aesthetic's values.
Why a palette is a field of the two scale kinds: design-log §4, the entry beginning "A scale's
palette is a field".
Why scales are values rather than one mutated object: design-log §4, the entry beginning "Scales
are three values"; what increment 5 built and what waits for its first reader: the entry
beginning "Position scales are chosen by column type"; why a continuous scale records the
identity transformation: the entry beginning "A layer records its stat and position"; why breaks
come from extended Wilkinson and labels are written the Elixir way: the entry beginning "Axes are
drawn"; why minor breaks are R's regular ones, less the breaks: the entry beginning "The panel's
grid lines are placed by the coordinate system".

## Rules

- **A scale is a continuous or a discrete scale, whatever the aesthetic; its palette is what makes
  it one aesthetic's.** A palette is a value naming its function (`Scale.Palette`), never a
  closure: `:identity` for a position, `{:rescale, {low, high}}` for a continuous aesthetic, R's
  `pal_rescale()`, `{:gradient, {low, high}}` for a continuous colour or fill, R's
  `pal_seq_gradient()`, `{:sequence, {low, high}}` for a discrete one, R's `seq(low, high,
  length.out = n)` as ggplot2's ordinal alpha takes it, and `{:hue, %{hue:, chroma:, luminance:}}`
  for a discrete colour or fill, R's `pal_hue()`. `new/1` makes a position scale; `new/2` makes an
  aesthetic's with ggplot2's default palette for it (`alpha`: 0.1 to 1; `color` and `fill`: the
  gradient from `#132B43` to `#56B1F7`, or `pal_hue()`'s hues from 15 round to 375, chroma 100,
  luminance 65), one of `non_position_aesthetics/0`.
- **The gradient is exactly R's `pal_seq_gradient()`**: a place from 0 to 1 blended from the low
  colour to the high in CIE L*a*b* (`Giggly.ColorOperations`), each channel interpolated as R's
  `approxfun()` does, the high end exact at 1, as `colour_ramp()` blends; its tests pin R's
  colours.
- **A continuous value's place in the range is R's `rescale()` (`Scale.rescale/3`), in R's order
  of operations**, and a range of zero width puts every value at the middle, so one value maps to
  the middle of its palette (0.55 for alpha); the rescale palette calls the same function. A
  missing value, or one that is not a finite number, maps to the scale's `na_value`, ggplot2's
  `na.value`: `nil` for a position and alpha, grey50 for a colour or fill.
- **A legend's breaks are the scale's on its limits, not an axis's extent** (`legend_breaks/1`): a
  continuous scale's are its transformation's breaks inside its trained range, taken as floats as
  R's limits are doubles, one at the low end of a range of zero width, none untrained; a discrete
  scale's are its levels, `nil` last and labelled `NA`, as ggplot2's legend keeps `NA`.
- **A discrete palette spreads the present levels; `nil` takes no share and maps to the scale's
  `na_value`**, ggplot2's `na.value`, as ggplot2's mapping leaves `NA` out of the levels it counts:
  `nil` for alpha (R's `NA`) and grey50, `#7F7F7F`, for colour and fill. `na_value` is a field of
  both scale kinds, as ggplot2's scale carries it (design-log §4, the entry beginning "A discrete
  scale carries its missing value"); a position scale places `nil` as its last level and reads
  none. The spread is R's `seq()`: its ends exact, each value between found by steps from the
  first (the fourth of seven is 0.54999999999999993).
- **The hue palette is exactly R's `pal_hue()`**: the circle's last `360 / n` degrees left off,
  the hues spread by the same `seq()`, each colour `Giggly.ColorOperations.from_hcl/3`; its test
  pins R's colours for counts whose last hue lands on 360 and past it. R takes each hue modulo
  360 first, which changes no colour, cosine and sine repeating, so it is left out.
- **A scale names its guide (`guide`), as ggplot2's scale carries `guide`**: `:axis` for a position
  (ggplot2's `guide_axis()`, drawn by the coordinate system's sides, not through the guide
  protocol), `:colorbar` for a continuous colour or fill, and `:legend` for alpha and a discrete
  colour or fill. The assembly turns the name into the kind; a scale never sees a guide.
  **`samples/2` and `places/2` give what a colour bar draws from a continuous scale**: values spread
  evenly over the trained range by R's `seq()`, as `extract_decor()` takes them, and each value's
  place in the range, 0 to 1, as the gradient form places its ticks and colours.
- **`Scale.Continuous` and `Scale.Discrete` are API; the rest of the namespace is not.**
  `Giggly.panel_scales/2` returns them, so their fields are documented and changing one changes
  the API; their functions are `@doc false`, used through `Giggly.Scale`, which is
  `@moduledoc false` like `Breaks`, `DateBreaks`, `Labels`, `MinorBreaks`, `Palette` and
  `Transform`.
- **A continuous scale carries the options a plot gives it**, `name`, `limits`, `breaks`,
  `minor_breaks`, `labels` and `expand`, each `:default` until given, `limits` `{nil, nil}` and
  `expand` ggplot2's `[mult: {0.05, 0.05}, add: {0, 0}]`; `Giggly.Plot` writes the struct,
  untrained, and the assembly trains a copy (design-log §4, the entry beginning "A scale function
  records the untrained scale"). Its field defaults are a position scale's, so `%Continuous{}` is
  `new(:continuous)`. `kind_of/1` says which kind a scale is, as `kind/1` says which a column needs.
- **Limits replace the range end by end, and a position outside them is censored.** Given in
  data units, they are transformed and, both given, sorted, as ggplot2 transforms and sorts them
  (`Continuous.limits/1`); a given end outside the domain raises, where R fails. An end of `nil`
  takes the range's (R's `get_limits()`), and with both ends an axis exists before any data.
  `map/2` turns a position outside the limits into `nil` before the stat, and `censor/2` does once
  the positions are final, as ggplot2 maps them twice with `oob = censor` (finite values only):
  `:infinity` and `:neg_infinity` are kept, and a discrete scale's positions are never censored.
- **Given breaks are kept in the order given wherever they fall inside the widened extent**, in
  data units and transformed, one outside the transformation's domain dropped, even beyond the
  limits, as R keeps 1.4 on mtcars' weights from 1.513; given labels go with their
  breaks by index, so a break left out takes its label with it; a labels function is handed every
  break drawn at once, as R's are, and must return a string for each, or the run raises; `:none`
  gives no breaks (so no minor breaks), no minor breaks, or `{position, :none}` for each break,
  which the axis draws as ticks alone.
- **A scale sees plain values, never a frame or a plot.** Its boundary lists
  `Giggly.ColorOperations`, which gives the hue palette its colours, as R's `scales` lists farver,
  and `Giggly.AsCharacter`, which writes a discrete level, and nothing else; the assembly pulls a column and hands its values here, so the namespace stays
  extractable, as R's `scales` stands beside ggplot2. Anything that needs a frame belongs to the
  caller.
- **A scale knows no pixel.** It stops at positions in data space: a continuous value as its
  transformation leaves it, a discrete value at its level's position counting from 1. The unit panel is the coordinate
  system's.
- **`kind/1` is the one rule for which column types an axis can place, and `kind/2` for an
  aesthetic**, read by the assembly to refuse a column when the plot is run and to choose the
  scale. A type with no scale yet returns `:none`. A `Date` column is `:date`, as ggplot2's
  `scale_type()` gives a `Date` `"date"`, and `:category`, a factor's column, is `:discrete`
  whatever its values: a date's is a continuous scale through the date transformation, so
  dates and numbers on one axis are two kinds and refused; on an aesthetic other than position a
  date has no scale yet (`kind/2` gives `:none`), ggplot2's `scale_colour_date()` and
  `scale_alpha_date()`.
- **Training follows R's `scales`.** A continuous range spans the finite numbers only (`nil` and
  the non-finite floats skipped); discrete levels are the distinct values, `nil` last, numbers
  among them, as a factor's are. **Which a discrete scale is handed, levels or positions, the
  caller says** by the function it calls, never by the values' type: `train/2` for a layer's own
  values, its levels, and `train_positions/2` for positions once the levels are mapped, which
  widen its continuous range alone. `discrete?/1` tells the two kinds apart for a caller that
  must, as a legend's key drawing does.
- **Discrete values are ordered by `level_key/1` alone**, and the assembly hands the same key to
  grouping, which orders its combinations by it, so group ids and axis positions agree. The rule
  exists once, and grouping does not depend on scales to use it.
- **A continuous scale records its transformation by name, the identity included.**
  `new(:continuous)` records `:identity`, as ggplot2's continuous scales default to
  `transform = "identity"`, so an untransformed axis says so; `new(:date)` records `:date`; a
  plot's scale may name `:log10`, `:sqrt`, `:reverse` or `:reciprocal`. A
  discrete scale has none, as in ggplot2, and `transform/2` returns its values as given.
- **A scale trains and maps in transformed space.** The assembly puts an axis's columns through
  `transform/2` before training, so the range, and every view of it the coordinate system builds,
  is in transformed space.
- **A transformation is a module implementing `Giggly.Scale.Transform`**, resolved from its name
  there, and carries what R's object carries and a scale reads: the transformation, its inverse,
  its domain, and its axis's default breaks, minor breaks and labels (`breaks`, `minor_breaks`,
  `format`). **A label is made from the break and the extent** (`format/2`), since a date's
  format is the step chosen for the whole axis; a number's ignores the extent and is written once
  the breaks outside it are dropped. **Breaks follow ggplot2's `get_breaks()`**: the extent
  squished into the transformed domain (log10 from -100, sqrt from 0), turned back into data
  units, broken there, and transformed back, **in the order that leaves them**, so reverse's and
  reciprocal's descend, as R draws them; labels are written, and a labels function handed, the
  breaks turned back, as R turns them (`10^x`, `x * x`). **A value outside the domain is R's**:
  log10 places 0 at minus infinity, at the panel's edge, and a negative value, as sqrt does, at
  `nil`, R's NaN; reverse swaps the infinities, reciprocal places 0 at plus infinity.
- **log10's breaks are exactly R's `breaks_log()`, five wanted** (`Transform.Log10`): every power
  of ten, or every second, third and so on, the widest step leaving three inside; else
  `log_sub_breaks()`'s multiples, evenest in log space first, keeping one each side; else
  extended breaks in data units. Its test pins R's own axis for each branch. sqrt, reverse and
  reciprocal take extended breaks on the data range, as R's `extended_breaks()` does.
- **A date scale works in days since 1970-01-01, as R stores a date** (`Transform.Date`, R's
  `transform_date()`): a date is a float of its days, a missing one `nil`; it trains, expands and
  is placed as any continuous scale, a single date 0.05 days either side. **Its breaks are exactly
  R's `pretty()` for dates** (`Scale.DateBreaks`, grDevices' `prettyDate()`): five days or less is
  every day, widened by five less its length, rounded half to even; longer takes the calendar step,
  a day to a thousand years, that cuts the extent closest to five times, from its start truncated
  to the step's unit (a Monday for weeks), or its neighbour where that comes closer, as R does.
  Each is labelled in its step's format, written as R's `format()` writes it, a year unpadded.
  **What R does only for times is left out**, and reaching it fails: steps under a day, and the
  widening, finer step and trimming no date extent needs. Its minor breaks are the identity's
  (`MinorBreaks.regular/2`) on the days. A surviving mutant there is judged against R as an
  extended-breaks one is (below): its test pins R's own breaks for each case and for each random
  extent where a mutant departed.
- **`breaks/2` gives an axis's breaks as `{position, label}` pairs, on the extent it is handed**,
  never one of its own, so a coordinate limit can hand it another. A continuous scale's are its
  transformation's breaks inside the extent (ggplot2 censors the rest), none when untrained, and
  the extent's low end alone when it has zero width; a discrete scale's are its levels at 1..n.
  Positions and labels travel as pairs so they cannot drift apart. A surviving mutant there is
  judged against R: applied to a scratch copy and compared with `labeling::extended()` on many
  random and degenerate ranges, it is equivalent only if it matches R on all of them; otherwise
  the first range where it departs joins the tests, with R's breaks.
- **`minor_breaks/3` gives an axis's minor breaks between the breaks `breaks/2` gave on the same
  extent**, as ggplot2's view scale hands `get_breaks_minor()` its breaks: the transformation's
  minor breaks kept inside the extent, ends included (R's `discard()`), less the breaks
  themselves, which ggplot2's grid takes out of its minor lines and nothing here reads. A discrete
  scale has none, as in ggplot2.
- **Every transformation's minor breaks are R's `scales::regular_minor_breaks()`**
  (`Scale.MinorBreaks`), in transformed space, with two intervals per gap, on the breaks in the
  transformation's order, the first gap's step added before and after them as R adds it, with
  `reverse = TRUE` for reverse alone: one more step past an outermost break the extent reaches beyond,
  then each gap's middle as R's `seq()` finds it, its start plus half its width, which differs
  from the two ends' mean in the last bit (an example pins it), and none for fewer than two breaks.
- **The identity's breaks are exactly R's `labeling::extended()` breaks**, five wanted, its three
  degenerate cases included (`Scale.Breaks`). Its test pins R's own output for a range of every
  winning nice number, skip, count and zero bonus, since a slip in one score shows only where that
  score decides the winner; a row that stops matching is a bug in the port, and the table is
  regenerated only by running R (labeling 0.4.3 in Docker's `r-base` image).
- **Labels are written the Elixir way, not R's** (`Scale.Labels`): `inspect`'s plain decimals,
  rounded to 15 significant digits, as many decimals on every label as the most precise needs,
  none when all are whole, negative zero as `0`, never scientific, no thousands separators, so a
  log axis's `1e+05` is written `100000`. **A
  discrete level is written as R's `as.character()` writes its value** (`Giggly.AsCharacter`),
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
- **`dimension/1` is an axis's extent widened by the scale's expansion**, in transformed
  positions: a continuous scale's limits by its `expand`, at each end `width * mult + add` (R's
  `expand_range4()`; a negative amount narrows it, as R's `expansion()` allows), 5% of the width
  by default, discrete levels (1 to n) by 0.6,
  limits of zero width (R's `zero_range()`, rounding error included) as if their width were 1;
  a discrete scale's extent then reaches as far as its continuous range does, unwidened, as
  ggplot2's `expand_limits_discrete()` takes the range of both. `zero_range?/2` is the one home of
  R's `zero_range()`; `Giggly.Resolution` asks it.
  **An extent still zero wide once widened is returned as its middle, both ends equal** (a single
  value from about 4.5e11 up): ggplot2 keeps such an extent and `scales::rescale()` draws every
  value on it at the panel's middle, and equal ends are how the coordinate system is told, so
  `zero_range()` stays in this namespace alone. The coordinate system maps the extent onto the
  panel and adds nothing; the coordinate system's switch to turn expansion off arrives with its
  options.
