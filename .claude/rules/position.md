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
- **A position's arguments arrive with their first reader.** The identity is handed the table
  alone; its own parameters (a dodge's width, a jitter's seed), the panel's scales and the split by
  panel arrive with the first position that moves a mark.

## How it works

`Giggly.Position` is a protocol: `compute_layer(position, frame)` dispatches on the position's
struct. `Position.Identity`, which has no parameters, returns the table as given, as ggplot2's
`PositionIdentity` overrides `compute_layer` to return its data. The boundary lists nothing, since
nothing here calls the data frame yet, and exports `Identity`; the specs name the frame's type,
which boundary does not check.
