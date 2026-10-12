---
paths:
  - "lib/giggly/coord.ex"
  - "lib/giggly/coord/**"
  - "test/giggly/coord_test.exs"
---

# The coordinate system

`Giggly.Coord` builds each panel's params and places positions in the unit panel. Why it arrived
with drawing, and why it lists the aesthetic vocabulary: design-log §4, the entry beginning "The
coordinate system arrives with drawing"; why it is the only route to the panel: the entry
beginning "Scales are three values".

## Rules

- **The coordinate system is the only route from positions to the unit panel.** A geom hands its
  rows and its panel's params to `transform/2` and never reads a scale's range; no scale knows the
  panel exists.
- **Panel params are opaque outside this namespace.** The assembly builds them, rendering passes
  them on, and a geom hands them back; only `Giggly.Coord` reads them, so a coordinate system that
  places positions differently changes no geom.
- **A plot always names its coordinate system, `:cartesian` included**, and this namespace
  resolves the name; each coordinate system is a module implementing the behaviour, whose struct
  is its panel params.
- **Params are built from the scales' extents, already widened** (`Scale.dimension/1`): the
  coordinate system adds no expansion of its own until a coordinate option (`expand = FALSE`,
  `xlim`) arrives.
- **`transform/2` places every x-family and y-family column**, by `Aesthetics.family/1`, never by
  comparing a name with `:x`; other columns pass through.
- **An infinite position goes to the panel's edge and a missing one stays missing**, as ggplot2's
  `squish_infinite()` and `rescale()` leave them; dropping a missing row is the geom's.
- **What waits for its first reader:** `munch` (the first path geom), breaks and labels on the
  params (the axes), and every coordinate option (`xlim`, `expand`, `reverse`, `ratio`, `clip`).

## How it works

`panel_params(name, x_dimension, y_dimension)` resolves the name and returns the coordinate
system's struct; `transform(frame, params)` dispatches on that struct. `Coord.Cartesian` holds
the x and y extents and rescales each value by its axis's extent, `(value - low) / (high - low)`,
putting `:infinity` at 1 and `:neg_infinity` at 0 and returning `nil` and `:nan` as they are.
The boundary lists `Giggly.Aesthetics`, for which columns are x and which y, and
`Giggly.DataFrame`.
