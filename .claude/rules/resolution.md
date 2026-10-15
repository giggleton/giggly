---
paths:
  - "lib/giggly/resolution.ex"
  - "test/giggly/resolution_test.exs"
---

# Resolution

`Giggly.Resolution` is ggplot2's `resolution()`: how finely positions are spaced, which a mark
with a width in data units takes its width from when given none. Why it is a boundary of its own:
design-log §4, the entry beginning "ggplot2's `resolution()` is a boundary of its own".

## Rules

- **It is R's `resolution()`, rule for rule, each checked against R**: integer positions and a
  range R's `zero_range()` calls zero wide are 1 apart; gaps within R's tolerance are rounding
  error; with none left the positions are 1 apart.
- **It asks `Giggly.Scale.zero_range?/2` and copies no rule of the scales'**, the one dependency
  its boundary lists.
- **Each caller counts from zero or not as its ggplot2 counterpart does**: a geom's own fallback
  does not (`compute_data_size()`), and `stat_count()` does.
- **A missing or infinite position is left out**, as R's `sort()` drops a missing one.
