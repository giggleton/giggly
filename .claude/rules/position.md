---
paths:
  - "lib/giggly/position.ex"
  - "lib/giggly/position/**"
---

# Positions

`Giggly.Position` moves a layer's marks once its stat has run. Why the identity is a position a
layer names rather than an absence: design-log §4, the entry beginning "A layer names its stat and
position"; why the layer records a struct of its kind, run through a protocol at the root:
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
  alone: stacking splits it by the `panel` column itself and reads no scale. A position's own
  parameters (a dodge's width, stacking's `vjust` and `reverse`) arrive with the option that sets
  them, and the panel's scales with the first position that reads one.
- **Stacking is ggplot2's `position_stack()`, `vjust = 1`**: nothing moves unless two rows of
  the layer share an x, in any panel; then each panel's bars pile by their `xmin`, those below
  zero downward and apart from the rest, ordered by group, highest first, each bar's y moving to
  the top of its stretch. A row missing its x, edges or y loses them all and stacks as nothing.
- **Dodging is ggplot2's `position_dodge()`, `preserve = "total"`**: each panel's bars at one
  `xmin` share the panel's first bar's width, ranked by group, lowest leftmost, each the widest
  bar's width over the number of groups at that x; an x with one group keeps its bar. Dodged
  positions come out doubles, as R's are, so a discrete axis's column stays one type.
- **A position reads a layer's orientation from its `flipped_aes` column**, written by the stat or
  the geom, and moves horizontal bars along y, flipped and flipped back, as ggplot2's positions
  read `flipped_aes`; without the column, bars are vertical.
