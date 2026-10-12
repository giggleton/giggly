---
paths:
  - "lib/giggly/scale.ex"
  - "lib/giggly/scale/**"
  - "test/giggly/scale_test.exs"
---

# Position scales

`Giggly.Scale` decides what kind of axis a column needs, trains a scale over the values it is
given, and maps values to their positions. Why scales are values rather than one mutated object:
design-log §4, the entry beginning "Scales are three values"; what this increment built and what
waits for its first reader: the entry beginning "Position scales are chosen by column type".

## Rules

- **A scale sees plain values, never a frame or a plot.** Its boundary lists nothing; the
  assembly pulls a column and hands its values here, so the namespace stays extractable, as R's
  `scales` stands beside ggplot2. Anything that needs a frame belongs to the caller.
- **A scale knows no pixel.** It stops at positions in data space: a continuous value as it is, a
  discrete value at its level's position counting from 1. The unit panel is the coordinate
  system's.
- **`kind/1` is the one rule for which column types an axis can place**, read by the assembly to
  refuse a column when the plot is run and to choose the scale. A type with no scale yet returns
  `:none`.
- **Training follows R's `scales`.** A continuous range spans the finite numbers only (`nil` and
  the non-finite floats skipped); discrete levels are the distinct values, `nil` last.
- **Discrete values are ordered by `level_key/1` alone**, and the assembly hands the same key to
  grouping, which orders its combinations by it, so group ids and axis positions agree. The rule
  exists once, and grouping does not depend on scales to use it.
- **An untrained continuous scale's range is `:none`.** Defaults for an empty axis (ggplot2's 0
  to 1) belong to the view of the scale the coordinate system builds, when it arrives.

## How it works

`Giggly.Scale` is the namespace root and the only module callers use; it dispatches on the
trained struct. `Scale.Continuous` folds values into a `{low, high}` range, skipping anything that
is not a number; its `map` returns the values unchanged until limits can censor them.
`Scale.Discrete` merges values into its levels as a sorted, de-duplicated list, and maps each
value through a level-to-position map built once per call.
