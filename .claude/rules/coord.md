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
beginning "Scales are three values"; why it places the grid lines: the entry beginning "The panel's
grid lines are placed by the coordinate system"; why it is a struct of its kind with a protocol at
the root, and why a geom is handed it: the entry beginning "Each facet, coordinate system, geom, stat and position is a struct".

## Rules

- **The coordinate system is the only route from positions to the unit panel.** A geom hands the
  coordinate system, its rows and its panel's params to `transform/3` and never reads a scale's
  range; no scale knows the panel exists.
- **Panel params are opaque outside the coordinate system that built them.** The assembly has them
  built, rendering passes them on with the plot's coordinate system, and a geom or a guide hands
  both back; only that coordinate system's implementation reads them, a map it builds in its own
  shape, so a coordinate system that places positions differently changes no geom and no guide.
- **A plot always records its coordinate system as a struct of its kind, `%Coord.Cartesian{}`
  included**, whose fields are its parameters. `Giggly.Coord` is a protocol, every function taking
  the coordinate system first; each coordinate system is one module holding its struct and its
  computing, in a `defimpl` that opens by classifying itself into this boundary. The boundary
  exports the kinds, whose structs a plot records; a geom or guide that matched one would be
  special-casing a coordinate system, which this seam exists to prevent.
- **Params are built from what the assembly hands over: each axis's extent, already widened**
  (`Scale.dimension/1`), **and its breaks and minor breaks on that extent** (`Scale.breaks/2`,
  `Scale.minor_breaks/3`). The coordinate
  system adds no expansion of its own and never lists `Scale` until a coordinate option
  (`expand = FALSE`, `xlim`) arrives; then the extent is the coordinate system's to decide.
- **`axes/2` places each axis's breaks by the same rescale as the data, keyed by the side the
  axis is drawn on, with the aesthetic the axis shows** (cartesian: x at the bottom, y on the
  left), so a guide never reads the params, takes the title of that aesthetic, and a radial
  system moves axes and their titles without touching a guide.
- **`grid/2` places the panel's grid lines, so where a grid line runs is the coordinate
  system's call**, as ggplot2's `render_bg` differs by coordinate system (straight lines here,
  circles and spokes in polar). It returns lines of points in the unit panel, major and minor, by
  the aesthetic whose breaks they mark; the guide gives them the theme's look and the drawing
  order. A cartesian line runs from minus to plus infinity along the other axis, as ggplot2 runs
  it, through the same rescale as the data: from edge to edge, or shrunk to a point at the middle
  across an axis whose extent has equal ends, as ggplot2's does.
- **`transform/3` places every x-family and y-family column**, by `Aesthetics.family/1`, never by
  comparing a name with `:x`; other columns pass through.
- **An infinite position goes to the panel's edge and a missing one stays missing**, as ggplot2's
  `squish_infinite()` and `rescale()` leave them; dropping a missing row is the geom's.
- **On an axis whose extent has equal ends, every position goes to the panel's middle, infinite
  ones too**, as `scales::rescale()` puts every value on a zero-wide range before ggplot2 squishes
  anything. The scale gives equal ends exactly when R's `zero_range()` calls the widened extent
  zero wide; this namespace tests only that the ends are equal and never copies the rule.
- **A coordinate system records whether its panels are clipped as one of its parameters, and
  `clip/1` reads it**, as ggplot2's `coord$clip` holds it. Cartesian coordinates default to `:on`,
  `coord_cartesian(clip = "on")`'s default, a value a test can assert on the plot. The assembly
  asks once and carries the answer to rendering, which marks each panel's cell, so rendering never
  lists this namespace.
- **What waits for its first reader:** `munch` (the first path geom; a grid that is not
  rectangular munches its lines and background, as ggplot2's does), axes above or to the right,
  and every coordinate option (`xlim`, `expand`, `reverse`, `ratio`, and `clip = "off"`).

## How it works

Every function dispatches on the coordinate system's struct: `panel_params(coord, x_axis,
y_axis)`, each axis given as `{extent, breaks, minor_breaks}`, returns the panel's params, and
`transform(coord, frame, params)`, `axes(coord, params)`, `grid(coord, params)` and `clip(coord)`
read them or the struct. `%Coord.Cartesian{clip: :on}`'s params are a map of the x and y extents,
breaks and minor breaks; it rescales each value by its axis's extent, `(value - low) / (high -
low)`, putting `:infinity` at 1 and `:neg_infinity` at 0 and returning `nil` and `:nan` as they
are; `axes/2` rescales each break's position the same way, keeps its label, and returns
`%{bottom: {:x, breaks}, left: {:y, breaks}}`; `grid/2` rescales each break's and minor break's
position the same way and runs an x line from `{place, bottom}` to `{place, top}`, the y extent's
rescaled minus and plus infinity, and a y line from `{left, place}` to `{right, place}` on the x
extent. The boundary lists `Giggly.Aesthetics`, for which columns are x and which y, and
`Giggly.DataFrame`, and exports `Cartesian`.
