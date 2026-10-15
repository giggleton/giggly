---
paths:
  - "lib/giggly/scale.ex"
  - "lib/giggly/scale/**"
  - "test/giggly/scale_test.exs"
  - "test/giggly/scale/**"
---

# Position scales

`Giggly.Scale` decides what kind of axis a column needs, puts values through a scale's
transformation, trains a scale over the values it is given, and maps values to their positions.
Why scales are values rather than one mutated object: design-log §4, the entry beginning "Scales
are three values"; what increment 5 built and what waits for its first reader: the entry
beginning "Position scales are chosen by column type"; why a continuous scale records the
identity transformation: the entry beginning "A layer names its stat and position"; why breaks
come from extended Wilkinson and labels are written the Elixir way: the entry beginning "Axes are
drawn"; why minor breaks are R's regular ones, less the breaks: the entry beginning "The panel's
grid lines are placed by the coordinate system".

## Rules

- **`Scale.Continuous` and `Scale.Discrete` are API; the rest of the namespace is not.**
  `Giggly.panel_scales/2` returns them, so their fields are documented and changing one changes
  the API; their functions are `@doc false`, used through `Giggly.Scale`, which is
  `@moduledoc false` like `Breaks`, `Labels`, `MinorBreaks` and `Transform`.
- **A scale sees plain values, never a frame or a plot.** Its boundary lists nothing; the
  assembly pulls a column and hands its values here, so the namespace stays extractable, as R's
  `scales` stands beside ggplot2. Anything that needs a frame belongs to the caller.
- **A scale knows no pixel.** It stops at positions in data space: a continuous value as its
  transformation leaves it, a discrete value at its level's position counting from 1. The unit panel is the coordinate
  system's.
- **`kind/1` is the one rule for which column types an axis can place**, read by the assembly to
  refuse a column when the plot is run and to choose the scale. A type with no scale yet returns
  `:none`.
- **Training follows R's `scales`.** A continuous range spans the finite numbers only (`nil` and
  the non-finite floats skipped); discrete levels are the distinct values, `nil` last.
- **Discrete values are ordered by `level_key/1` alone**, and the assembly hands the same key to
  grouping, which orders its combinations by it, so group ids and axis positions agree. The rule
  exists once, and grouping does not depend on scales to use it.
- **A continuous scale records its transformation by name, the identity included.**
  `new(:continuous)` records `:identity`, as ggplot2's continuous scales default to
  `transform = "identity"`, so an untransformed axis says so. A discrete scale has none, as in
  ggplot2, and `transform/2` returns its values as given.
- **A scale trains and maps in transformed space.** The assembly puts an axis's columns through
  `transform/2` before training, so the range, and every view of it the coordinate system builds,
  is in transformed space.
- **A transformation is a module implementing `Giggly.Scale.Transform`**, resolved from its name
  there, and carries its axis's default breaks, minor breaks and labels, as R's object carries
  `breaks`, `minor_breaks` and `format`. What else R's object carries (the inverse, the domain) joins the behaviour with its
  first reader: the first transformation that is not the identity, whose breaks must be found in
  data space and mapped back.
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
- **An untrained continuous scale's range is `:none`.** The empty axis's 0 to 1 is
  `dimension/1`'s, as it is ggplot2's `get_limits()`'s.
- **`dimension/1` is an axis's extent widened by ggplot2's default expansion**, in transformed
  positions: a continuous range by 5% of its width at each end, discrete levels (1 to n) by 0.6,
  a range of zero width (R's `zero_range()`, rounding error included) as if its width were 1.
  **An extent still zero wide once widened is returned as its middle, both ends equal** (a single
  value from about 4.5e11 up): ggplot2 keeps such an extent and `scales::rescale()` draws every
  value on it at the panel's middle, and equal ends are how the coordinate system is told, so
  `zero_range()` stays in this namespace alone. The coordinate system maps the extent onto the
  panel and adds nothing; a scale's own `expand`, and the
  coordinate system's switch to turn expansion off, arrive with options.
