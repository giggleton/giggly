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
  `pal_rescale()`, and `{:sequence, {low, high}}` for a discrete one, R's `seq(low, high,
  length.out = n)` as ggplot2's ordinal alpha takes it. `new/1` makes a position scale; `new/2`
  makes an aesthetic's with ggplot2's default palette for it (`alpha`: 0.1 to 1), one of
  `non_position_aesthetics/0`.
- **A continuous value's place in the range is R's `rescale()` (`Scale.rescale/3`), in R's order
  of operations**, and a range of zero width puts every value at the middle, so one value maps to
  the middle of its palette (0.55 for alpha); the rescale palette calls the same function. A
  missing value, or one that is not a finite number, maps to `nil`, ggplot2's `na.value`.
- **A legend's breaks are the scale's on its limits, not an axis's extent** (`legend_breaks/1`): a
  continuous scale's are its transformation's breaks inside its trained range, taken as floats as
  R's limits are doubles, one at the low end of a range of zero width, none untrained; a discrete
  scale's are its levels, `nil` last and labelled `NA`, as ggplot2's legend keeps `NA`.
- **A discrete palette spreads the present levels; `nil` takes no share and maps to `nil`**, as
  ggplot2's mapping leaves `NA` out of the levels it counts. The spread is R's `seq()`: its ends
  exact, each value between found by steps from the first (the fourth of seven is
  0.54999999999999993).
- **`Scale.Continuous` and `Scale.Discrete` are API; the rest of the namespace is not.**
  `Giggly.panel_scales/2` returns them, so their fields are documented and changing one changes
  the API; their functions are `@doc false`, used through `Giggly.Scale`, which is
  `@moduledoc false` like `Breaks`, `DateBreaks`, `Labels`, `MinorBreaks`, `Palette` and
  `Transform`.
- **A scale sees plain values, never a frame or a plot.** Its boundary lists nothing; the
  assembly pulls a column and hands its values here, so the namespace stays extractable, as R's
  `scales` stands beside ggplot2. Anything that needs a frame belongs to the caller.
- **A scale knows no pixel.** It stops at positions in data space: a continuous value as its
  transformation leaves it, a discrete value at its level's position counting from 1. The unit panel is the coordinate
  system's.
- **`kind/1` is the one rule for which column types an axis can place, and `kind/2` for an
  aesthetic**, read by the assembly to refuse a column when the plot is run and to choose the
  scale. A type with no scale yet returns `:none`. A `Date` column is `:date`, as ggplot2's
  `scale_type()` gives a `Date` `"date"`: a continuous scale through the date transformation, so
  dates and numbers on one axis are two kinds and refused; on an aesthetic other than position a
  date has no scale yet (`kind/2` gives `:none`).
- **Training follows R's `scales`.** A continuous range spans the finite numbers only (`nil` and
  the non-finite floats skipped); discrete levels are the distinct values, `nil` last.
- **Discrete values are ordered by `level_key/1` alone**, and the assembly hands the same key to
  grouping, which orders its combinations by it, so group ids and axis positions agree. The rule
  exists once, and grouping does not depend on scales to use it.
- **A continuous scale records its transformation by name, the identity included.**
  `new(:continuous)` records `:identity`, as ggplot2's continuous scales default to
  `transform = "identity"`, so an untransformed axis says so; `new(:date)` records `:date`. A
  discrete scale has none, as in ggplot2, and `transform/2` returns its values as given.
- **A scale trains and maps in transformed space.** The assembly puts an axis's columns through
  `transform/2` before training, so the range, and every view of it the coordinate system builds,
  is in transformed space.
- **A transformation is a module implementing `Giggly.Scale.Transform`**, resolved from its name
  there, and carries its axis's default breaks, minor breaks and labels, as R's object carries
  `breaks`, `minor_breaks` and `format`. **A label is made from the break and the extent**
  (`format/2`), since a date's format is the step chosen for the whole axis; a number's ignores
  the extent and is written once the breaks outside it are dropped. What else R's object carries
  (the inverse, the domain) joins the behaviour with its first reader outside a transformation:
  the date transformation finds its breaks in days and turns them back into dates itself.
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
- **The identity's minor breaks are R's `scales::regular_minor_breaks()`** (`Scale.MinorBreaks`)
  with two intervals per gap: one more step past an outermost break the extent reaches beyond,
  then each gap's middle as R's `seq()` finds it, its start plus half its width, which differs
  from the two ends' mean in the last bit (an example pins it), and none for fewer than two breaks.
- **The identity's breaks are exactly R's `labeling::extended()` breaks**, five wanted, its three
  degenerate cases included (`Scale.Breaks`). Its test pins R's own output for a range of every
  winning nice number, skip, count and zero bonus, since a slip in one score shows only where that
  score decides the winner; a row that stops matching is a bug in the port, and the table is
  regenerated only by running R (labeling 0.4.3 in Docker's `r-base` image).
- **Labels are written the Elixir way, not R's** (`Scale.Labels`): `inspect`'s plain decimals,
  rounded to 15 significant digits, as many decimals on every label as the most precise needs,
  none when all are whole, negative zero as `0`, never scientific, no thousands separators. A
  discrete level is `to_string/1` of its value, and a missing level is `NA`.
- **A discrete scale keeps a continuous range beside its levels**, ggplot2's `range_c`: handed
  positions, such as a bar's edges once its levels are mapped, it widens that range and leaves
  its levels alone. `reset/1` empties a continuous scale's range and a discrete one's continuous
  range, keeping its levels, as ggplot2 resets its scales before training them again on the
  positioned marks.
- **An untrained continuous scale's range is `:none`.** The empty axis's 0 to 1 is
  `dimension/1`'s, as it is ggplot2's `get_limits()`'s.
- **`dimension/1` is an axis's extent widened by ggplot2's default expansion**, in transformed
  positions: a continuous range by 5% of its width at each end, discrete levels (1 to n) by 0.6,
  a range of zero width (R's `zero_range()`, rounding error included) as if its width were 1;
  a discrete scale's extent then reaches as far as its continuous range does, unwidened, as
  ggplot2's `expand_limits_discrete()` takes the range of both. `zero_range?/2` is the one home of
  R's `zero_range()`; `Giggly.Resolution` asks it.
  **An extent still zero wide once widened is returned as its middle, both ends equal** (a single
  value from about 4.5e11 up): ggplot2 keeps such an extent and `scales::rescale()` draws every
  value on it at the panel's middle, and equal ends are how the coordinate system is told, so
  `zero_range()` stays in this namespace alone. The coordinate system maps the extent onto the
  panel and adds nothing; a scale's own `expand`, and the
  coordinate system's switch to turn expansion off, arrive with options.
