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
  them on, and a geom or a guide hands them back; only `Giggly.Coord` reads them, so a coordinate
  system that places positions differently changes no geom and no guide.
- **A plot always names its coordinate system, `:cartesian` included**, and this namespace
  resolves the name; each coordinate system is a module implementing the behaviour, whose struct
  is its panel params.
- **Params are built from what the assembly hands over: each axis's extent, already widened**
  (`Scale.dimension/1`), **and its breaks on that extent** (`Scale.breaks/2`). The coordinate
  system adds no expansion of its own and never lists `Scale` until a coordinate option
  (`expand = FALSE`, `xlim`) arrives; then the extent is the coordinate system's to decide.
- **`axes/1` places each axis's breaks by the same rescale as the data, keyed by the side the
  axis is drawn on, with the aesthetic the axis shows** (cartesian: x at the bottom, y on the
  left), so a guide never reads the params, takes the title of that aesthetic, and a flipped or
  polar system moves axes and their titles without touching a guide.
- **`transform/2` places every x-family and y-family column**, by `Aesthetics.family/1`, never by
  comparing a name with `:x`; other columns pass through.
- **An infinite position goes to the panel's edge and a missing one stays missing**, as ggplot2's
  `squish_infinite()` and `rescale()` leave them; dropping a missing row is the geom's.
- **What waits for its first reader:** `munch` (the first path geom), minor breaks (grid lines),
  axes above or to the right, and every coordinate option (`xlim`, `expand`, `reverse`, `ratio`,
  `clip`).

## How it works

`panel_params(name, x_axis, y_axis)` resolves the name and returns the coordinate system's
struct, each axis given as `{extent, breaks}`; `transform(frame, params)` and `axes(params)`
dispatch on that struct. `Coord.Cartesian` holds the x and y extents and breaks and rescales each
value by its axis's extent, `(value - low) / (high - low)`, putting `:infinity` at 1 and
`:neg_infinity` at 0 and returning `nil` and `:nan` as they are; `axes/1` rescales each break's
position the same way, keeps its label, and returns `%{bottom: {:x, breaks}, left: {:y, breaks}}`.
The boundary lists `Giggly.Aesthetics`, for which columns are x and which y, and
`Giggly.DataFrame`.
