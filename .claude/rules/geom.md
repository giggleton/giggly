---
paths:
  - "lib/giggly/geom.ex"
  - "lib/giggly/geom/**"
  - "test/giggly/geom_test.exs"
---

# Geoms

`Giggly.Geom` draws a layer's rows in a panel as scene primitives. Why a geom calls the coordinate
system itself and how a point's look was derived: design-log §4, the entry beginning "The
coordinate system arrives with drawing"; why a geom is a struct of its kind whose module also
holds the facts a plot checks: the entry beginning "Each facet, coordinate system, geom, stat and position is a struct".

## Rules

- **A geom never sees a panel's size, a pixel, a scale's range or a facet.** It is handed one
  panel's rows, the plot's coordinate system and that panel's params, as ggplot2's `draw_panel()`
  is, places the rows with `Coord.transform/3`, and emits primitives in the cell's units, 0 to 1.
- **A geom calls the coordinate system itself**, as ggplot2's `draw_panel()` calls
  `coord$transform()`: a path will choose `munch` over `transform`, which only the geom knows to
  do. The params stay opaque to it.
- **A layer records its geom as a struct of its kind, and each geom is one module holding
  everything about it**: its struct, whose fields are its parameters; the facts a plot checks a
  layer's mapping against (`accepted_aesthetics/0`, `required_aesthetics/0`), which `Plot` reads;
  and its drawing, in a `defimpl Giggly.Geom` that opens by classifying itself into this boundary.
  The boundary exports the kinds; their drawing stays in their implementations.
- **A row missing a required position is not drawn.** ggplot2 also warns; a pure pipeline cannot,
  so how a dropped row is reported is open until something can report it.
- **A point looks like ggplot2's default point until aesthetics can change it:** black, size 1.5
  mm, border 0.5 mm, which grid draws as a circle of radius 1.95 points with a 0.71-point outline.
  The defaults move to the theme with its second reader.
