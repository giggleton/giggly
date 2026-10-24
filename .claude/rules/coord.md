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
the root, and why a geom is handed it: the entry beginning "Each facet, coordinate system, geom,
stat and position is a struct"; what radial coordinates are and why: the entry beginning
"`coord_radial()` is built in four steps".

## Rules

- **The coordinate system is the only route from positions to the unit panel.** A geom hands the
  coordinate system, its rows and its panel's params to `transform/3` and never reads a scale's
  range; no scale knows the panel exists.
- **Panel params are opaque outside the coordinate system that built them.** The assembly has them
  built, rendering passes them on with the plot's coordinate system, and a geom or a guide hands
  both back; only that coordinate system's implementation reads them, a map it builds in its own
  shape, so a coordinate system that places positions differently changes no geom, and a guide
  draws only what `axes/2` and `grid/2` hand it.
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
- **`axes/2` places each axis's breaks by the same rescale as the data, keyed by where the axis
  is drawn, with the aesthetic it shows and the look it is drawn in** (ggplot2's theme suffix),
  so a guide never reads the params and takes the title of that aesthetic. Cartesian: x at the
  bottom and y on the left, each in its own look. Radial: the radius axis on the left in the
  `:r` look, the angle axis `:theta`, around the circle inside the panel, and a bottom axis with
  no breaks, which keeps the x title where ggplot2 draws it. **Each axis comes with its line**,
  run from minus to plus infinity along its aesthetic and munched as ggplot2 munches an axis
  guide's: on a side the places along it the line passes through, a cartesian side's whole length;
  radially the radius axis's a ray up from the centre at the angle's end, the angle axis's the
  circle at the edge as points in the panel, and none below the panel.
- **`grid/2` places the panel's grid lines, so where a grid line runs is the coordinate
  system's call**, as ggplot2's `render_bg` differs by coordinate system (straight lines here,
  circles and spokes in polar). It returns lines of points in the unit panel, major and minor, by
  the aesthetic whose breaks they mark; the guide gives them the theme's look and the drawing
  order. A line runs from minus to plus infinity along the other aesthetic, as ggplot2 runs it,
  through the same placing as the data: a cartesian one from edge to edge, or shrunk to a point
  at the middle across an axis whose extent has equal ends; a radial one a spoke or a whole
  circle. `grid/2` also gives the background's shape: `:panel`, filling it, or the outline of the
  shape it fills, radially a disc. A grid that is not rectangular is munched as ggplot2's
  `coord_munch()` munches it, inside the coordinate system that draws it.
- **Cartesian `transform/3` places every x-family and y-family column**, by
  `Aesthetics.family/1`, never by comparing a name with `:x`; other columns pass through.
  **Radial `transform/3` places `x` and `y` only**, as ggplot2's does, **and fails on any other
  x-family or y-family column**: a range cannot be placed without its pair, so a geom drawing
  one turns it into a path first, as ggplot2's geoms do under coordinates that are not linear.
- **An infinite position goes to its extent's end and a missing one stays missing**, as ggplot2's
  `squish_infinite()` and `rescale()` leave them: the panel's edge, or radially the angle's start
  or the circle's centre or edge, a row missing either radial position missing both; dropping a
  missing row is the geom's.
- **On an axis whose extent has equal ends, every position goes to the middle, infinite ones
  too**: the panel's middle, or radially half a turn round or halfway out, as `scales::rescale()`
  puts every value on a zero-wide range before ggplot2 squishes anything. The scale gives equal
  ends exactly when R's `zero_range()` calls the widened extent zero wide; this namespace tests
  only that the ends are equal and never copies the rule.
- **A coordinate system records whether its panels are clipped as one of its parameters, and
  `clip/1` reads it**, as ggplot2's `coord$clip` holds it. Cartesian coordinates default to `:on`,
  `coord_cartesian(clip = "on")`'s default, and radial ones to `:off`, `coord_radial()`'s, values
  a test can assert on the plot. The assembly asks once and carries the answer to rendering,
  which marks each panel's cell, so rendering never lists this namespace.
- **`aspect/2` gives the shape a panel keeps, its height over its width**, from the first
  panel's params, as ggplot2 asks `coord$aspect()`: `:none` for cartesian coordinates, 1 for a
  full circle. The assembly asks once and carries it to rendering, as it carries `clip`.
- **`munch/3` places a layer's lines, cut first to follow the panel's curves**, as ggplot2's
  `coord_munch()`: cartesian coordinates place the rows as `transform/3` does; radial ones put an
  infinite position at its extent's end, cut each piece between two rows of one group as a grid
  line is cut, leave a piece across a change of group or from a missing position whole, copy every
  column of a piece's first row into its steps, keep the last row, and then place them. **A piece
  is measured as `dist_polar()` measures it**, on radii boosted to the power 0.75 and angles a full
  turn round: the arc of Archimedes' spiral through its ends, a circle's arc where its radius stays
  the same, a ray where its angle does, classified by the rescaled values as R compares them, and
  not measured where neither changes.
- **What waits for its first reader:** axes above or to the right, and every coordinate option (cartesian `xlim`, `expand`, `ratio`, `clip = "off"`;
  radial `theta`, `start` and `end`, `inner.radius`, `thetalim` and `rlim`, `expand`,
  `clip = "on"`, `r.axis.inside`, `rotate.angle`, `reverse`).
