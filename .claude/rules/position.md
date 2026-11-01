---
paths:
  - "lib/giggly/position.ex"
  - "lib/giggly/position/**"
  - "test/giggly/position_test.exs"
---

# Positions

`Giggly.Position` moves a layer's marks once its stat has run. Why the identity is a position a
layer records rather than an absence: design-log §4, the entry beginning "A layer records its stat
and position"; why the layer records a struct of its kind, run through a protocol at the root:
the entry beginning "Each facet, coordinate system, geom, stat and position is a struct".

## Rules

- **A layer always records its position, the identity included.** An absent position cannot be
  told from a forgotten one; `%Position.Identity{}` says the marks stay where the stat put them on
  purpose.
- **A layer records its position as a struct of its kind, which `Plot` builds and never runs.**
  `Plot` lists this boundary to build the struct; `GigglyCredo.Check.PlotRunsNothing` keeps the
  protocol out of its files. Each position is one module holding its struct, whose fields are its
  parameters, and its computing, in a `defimpl` that opens by classifying itself into this
  boundary; the boundary exports the kinds.
- **A position runs after the stat**, on positions: a discrete value is its level's position, so
  a width is a fraction of the spacing between levels.
- **A position's arguments arrive with their first reader.** Every position is handed the table
  and each axis's kind (`axis_kinds`, as a geom's `setup_data/3` is), which jittering first read,
  as R's `compute_jitter()` reads a mapped discrete position: stacking splits the table by the
  `panel` column itself and reads no scale. A position's own
  parameters arrive with the option that sets them, as dodging by clusters' `preserve`, `padding`
  and `reverse` arrived with `{:dodge2, options}`, dodging's `width` with `{:dodge, width: width}`,
  the first reader a line range, which has no edges, and stacking's `vjust`, `reverse` and `fill`
  with `{:stack, options}` and `:fill`; dodging by clusters' `width` waits, and the panel's scales
  with the first position that reads one.
- **Stacking is ggplot2's `position_stack()`, and filling its `position_fill()`, one kind with
  `fill: true`** (design-log §4, the entry beginning "Filling is stacking"): nothing moves unless
  two rows of the layer share an x, in any panel, or it fills or its `vjust` is not 1; then a layer
  with no `ymax`, a point's, is stacked by its y, given a `ymax` and then a `ymin` in R's order, as
  `setup_data()` and `pos_stack()` write them, and a layer with no `xmin`, an area's, has its
  `xmin` and `xmax` set to its x, as ggplot2's `collide()` sets them, and each panel's bars or
  bands pile by their `xmin`, those below zero downward and apart from the rest, ordered by group,
  highest first, lowest first when reversed, each bar's y moving `vjust` of the way up its
  stretch, `(1 - vjust) * low + vjust * high`. Filled, each pile's heights are divided by its
  total's magnitude, as R's `pos_stack()` divides them, where that is above R's
  `sqrt(.Machine$double.eps)`. A row missing its x, edges or y loses them all and stacks as nothing.
  The heights add, divide and compare in R's arithmetic (`Giggly.DataFrame.Arithmetic`), so an
  infinite bar takes its pile to its infinity and a bar above it runs from infinity to infinity,
  its y R's `0 * Inf`, NaN, which the scale's second mapping makes missing; filled, the bars below
  an infinity reach 0 and it NaN. **It departs from R where R fails**: a filled pile whose total is
  NaN, holding both infinities, is divided by it, so its marks are missing, where R fails.
- **Dodging is ggplot2's `position_dodge()`, `preserve = "total"`**: a mark with sides and no x, a
  rectangle, is first given their middle as its x, which it keeps, as `setup_data()` gives it; a
  mark with no `xmin` and `xmax`, a line range's or a point range's, is given them, its x ∓ half the
  `width` given, else its x, as `collide_setup()` gives them, so given none it does not move (R
  warns, and `Plot` refuses `:dodge` alone for such marks); a mark with no `ymax`, a point, is given
  its y as one, as `collide()` gives it; each panel's marks at one `xmin` then share the `width`
  given, else the panel's first mark's, ranked by group, lowest leftmost, each the widest mark's
  width over the number of groups at that x; an x with one group keeps its mark. Dodged positions
  come out doubles, as R's are, so a discrete axis's column stays one type.
- **Dodging by clusters is ggplot2's `position_dodge2()`, on lists, in R's order and R's
  arithmetic** (design-log §4, the entries beginning "Dodging by clusters"): its widths' sum and its
  edges are R's `sum()` and `cumsum()` in extended precision (`Arithmetic.sum/2`,
  `cumulative_sum/1`), so its doubles are R's; each panel's rows come out sorted by x, then group,
  as R's do; a bar with no group is dodged; padding applies to every bar of a panel where a cluster
  holds two, and nowhere else; `:single` divides by the most bars at one present x in any panel; a
  rectangle is first given the middle of its sides as its x, as dodging gives it. **It departs from
  R where R slips**: each cluster is placed from its own middle and widths, where R misplaces those
  after a bar missing an edge, which is placed nowhere and loses its x; and a panel where no bar has
  edges, where R fails, keeps them missing. It writes none of R's scratch columns (`xid`, `newx`,
  `new_width`), nor `order`.
- **A position declares the aesthetics it reads, each with its default
  (`default_aesthetics/1`)**, as ggplot2's position declares its `default_aes`, and reads them
  from columns the assembly has put into every row before it runs (design-log §4, the entry
  beginning "A position declares the aesthetics it reads"); a position reading none declares an
  empty map.
- **Nudging is ggplot2's `position_nudge()`, `x = NULL`, `y = NULL`**, the text geom's default
  position, as in ggplot2 4.0, and a position every layer but a diagonal line's takes, its nudges
  set or mapped (design-log §4, the entry beginning "A nudge is an aesthetic only"): every column
  in the x family moves by its row's `nudge_x` and every one in the y family by its `nudge_y`, both
  0 by default, through the frame's `+` (`Giggly.DataFrame.Arithmetic`), so a position comes out a
  double, as R's do, an infinite nudge sends its mark to that infinity, and a row missing its
  position or its nudge is missing that position. **It departs from R where R fails**: a missing
  nudge in a layer whose other nudges along that axis are all 0, where R fails.
- **Jittering is ggplot2's `position_jitter()`, its seed fixed** (design-log §4, the entries
  beginning "`geom_jitter` is Phase 3's fourteenth" and "A jitter's distances are Erlang's"):
  every column of the x family moves by its row's distance across and every one of the y family
  by its distance up, each drawn from minus to plus its amount, one not given 0.4 of the closest
  spacing of each panel's positions along that axis (`Giggly.Resolution`, not counting from zero,
  the one position listing it), 0.4 on a discrete axis whatever levels a panel holds. Each panel draws afresh from the seed, as R sets its seed per
  panel, two numbers a row, across then up, whatever the amounts, by `:rand`'s `exsss` named,
  never OTP's default, a draw `u` becoming `-amount + 2 * amount * u`, as R's `runif()` scales
  one; the moves are the frame's `+` (`DataFrame.mutate/2`), so a position comes out a double, a
  missing one stays missing and an infinite one where it is. **It departs from R where R's
  numbers cannot be had**: R's random numbers are never reproduced, so a golden is checked by R
  drawing Giggly's distances through `position_nudge()`; and positions whose only gap is to an
  infinity are 1 apart, where R's `resolution()` is infinite and sends them to infinity.
- **A position reads a layer's orientation from its `flipped_aes` column**, written by the stat or
  the geom, and moves horizontal bars along y, flipped and flipped back, as ggplot2's positions
  read `flipped_aes`; without the column, bars are vertical. The positions that move bars share
  this through `Giggly.Position.Orientation`, a module of the boundary that is no kind and no
  export.
- **What stacking and dodging give a mark before they move it is `Giggly.Position.Collide`**,
  ggplot2's `collide_setup()`, `collide()` and `PositionDodge$setup_data()`: an x from a
  rectangle's sides, sides from an x, a `ymax` from a y, each kept, as R's `layer_data()` keeps
  them. Like `Orientation`, it is no kind and no export.
