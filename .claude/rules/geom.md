---
paths:
  - "lib/giggly/geom.ex"
  - "lib/giggly/geom/**"
  - "test/giggly/geom_test.exs"
---

# Geoms

`Giggly.Geom` draws a layer's rows in a panel as scene primitives. Why a geom calls the coordinate
system itself and how a point's look was derived: design-log §4, the entry beginning "The
coordinate system arrives with drawing".

## Rules

- **A geom never sees a panel's size, a pixel, a scale's range or a facet.** It is handed one
  panel's rows and that panel's params, places the rows with `Coord.transform/2`, and emits
  primitives in the cell's units, 0 to 1.
- **A geom calls the coordinate system itself**, as ggplot2's `draw_panel()` calls
  `coord$transform()`: a path will choose `munch` over `transform`, which only the geom knows to
  do. The params stay opaque to it.
- **A layer names its geom, and this namespace resolves the name**; each geom is a module
  implementing the behaviour.
- **A row missing a required position is not drawn.** ggplot2 also warns; a pure pipeline cannot,
  so how a dropped row is reported is open until something can report it.
- **A point looks like ggplot2's default point until aesthetics can change it:** black, size 1.5
  mm, border 0.5 mm, which grid draws as a circle of radius 1.95 points with a 0.71-point outline.
  The defaults move to the theme with its second reader.

## How it works

`draw_panel(frame, name, panel_params)` resolves the name and calls the module's
`draw_panel/2`. `Geom.Point` transforms the frame, keeps the rows whose `x` and `y` are both
numbers after placing, and returns one `Scene.Circles` holding them. Its radius and outline are
computed at compile time from ggplot2's constants: a font size of `size * .pt + stroke * .stroke /
2` (`.pt` = 72.27/25.4 font points per millimetre, `.stroke` = 96/25.4 line-width units per
millimetre), a radius of 0.375 times that font size (R's graphics engine for shape 19), and an
outline of `stroke * .stroke / 2` line-width units of 1/96 inch, written in points.
