---
paths:
  - "lib/giggly/stat.ex"
  - "lib/giggly/stat/**"
---

# Stats

`Giggly.Stat` runs a layer's statistical transformation on its table. Why the identity is a stat a
layer names rather than an absence, and why the layer records a name rather than a module:
design-log §4, the entry beginning "A layer names its stat and position".

## Rules

- **A layer always names its stat, the identity included.** An absent stat cannot be told from a
  forgotten one; `:identity` says the layer computes nothing on purpose, and a test can say so.
- **A layer records the stat's name, and this namespace resolves it.** `Plot` names no module
  here, so a plot describes a stat and never runs one, and `Plot`'s boundary does not list `Stat`.
- **A stat runs after the position scales have mapped the layer's x and y columns**, so it
  computes on positions: a discrete value is its level's position.
- **A stat's arguments arrive with their first reader.** The identity is handed the table alone.
  The panel's scales (ggplot2 hands `compute_layer` the layout, and binning reads the scale's
  range), the split by panel and by group, and ggplot2's rule for carrying a group's constant
  columns through a summary arrive with the first stat that computes.

## How it works

`Giggly.Stat` is the behaviour (`compute_layer/1`) and the root its callers use:
`compute(frame, name)` resolves the name to its module and calls it. `Stat.Identity` returns the
table as given, as ggplot2's `StatIdentity` overrides `compute_layer` to return its data. The
boundary lists nothing, since nothing here calls the data frame yet; the specs name the frame's
type, which boundary does not check.
