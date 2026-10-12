---
paths:
  - "lib/giggly/position.ex"
  - "lib/giggly/position/**"
---

# Positions

`Giggly.Position` moves a layer's marks once its stat has run. Why the identity is a position a
layer names rather than an absence, and why the layer records a name rather than a module:
design-log §4, the entry beginning "A layer names its stat and position".

## Rules

- **A layer always names its position, the identity included.** An absent position cannot be
  told from a forgotten one; `:identity` says the marks stay where the stat put them on purpose.
- **A layer records the position's name, and this namespace resolves it.** `Plot` names no module
  here, so its boundary does not list `Position`.
- **A position runs after the stat**, on positions: a discrete value is its level's position, so
  a width is a fraction of the spacing between levels.
- **A position's arguments arrive with their first reader.** The identity is handed the table
  alone; its own parameters (a dodge's width, a jitter's seed), the panel's scales and the split by
  panel arrive with the first position that moves a mark.

## How it works

`Giggly.Position` is the behaviour (`compute_layer/1`) and the root its callers use:
`compute(frame, name)` resolves the name to its module and calls it. `Position.Identity` returns
the table as given, as ggplot2's `PositionIdentity` overrides `compute_layer` to return its data.
The boundary lists nothing, since nothing here calls the data frame yet; the specs name the
frame's type, which boundary does not check.
