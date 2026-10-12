---
paths:
  - "lib/giggly/scale.ex"
  - "lib/giggly/scale/**"
  - "test/giggly/scale_test.exs"
---

# Position scales

`Giggly.Scale` decides what kind of axis a column needs, puts values through a scale's
transformation, trains a scale over the values it is given, and maps values to their positions.
Why scales are values rather than one mutated object: design-log §4, the entry beginning "Scales
are three values"; what increment 5 built and what waits for its first reader: the entry
beginning "Position scales are chosen by column type"; why a continuous scale records the
identity transformation: the entry beginning "A layer names its stat and position".

## Rules

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
  there. What R's transformation object carries beside the transform itself (the inverse, the
  axis's default breaks and labels, the domain) joins the behaviour with its first reader.
- **An untrained continuous scale's range is `:none`.** The empty axis's 0 to 1 is
  `dimension/1`'s, as it is ggplot2's `get_limits()`'s.
- **`dimension/1` is an axis's extent widened by ggplot2's default expansion**, in transformed
  positions: a continuous range by 5% of its width at each end, discrete levels (1 to n) by 0.6,
  a range of zero width (R's `zero_range()`, rounding error included) as if its width were 1.
  The coordinate system maps it onto the panel and adds nothing; a scale's own `expand`, and the
  coordinate system's switch to turn expansion off, arrive with options.

## How it works

`Giggly.Scale` is the namespace root and the only module callers use; it dispatches on the
trained struct. `Scale.Continuous` puts values through its transformation by handing its name to
`Scale.Transform`, whose `Transform.Identity` returns them as given; it folds values into a
`{low, high}` range, skipping anything that is not a number; its `map` returns the values
unchanged until limits can censor them.
`Scale.Discrete` merges values into its levels as a sorted, de-duplicated list, and maps each
value through a level-to-position map built once per call.
