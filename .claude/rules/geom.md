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
holds the facts a plot checks: the entry beginning "Each facet, coordinate system, geom, stat and
position is a struct"; why a geom has a say during the build: the entry beginning "A geom says
where its marks sit".

## Rules

- **A geom never sees a panel's size, a pixel, a scale's range or a facet.** It is handed one
  panel's rows, the plot's coordinate system and that panel's params, as ggplot2's `draw_panel()`
  is, places the rows with `Coord.transform/3`, and emits primitives in the cell's units, 0 to 1.
- **A geom has a say during the build: `setup_data/3`** gives each row the extent it is drawn
  over in data space, after the stat and before the position, as ggplot2's `setup_data()` does, so
  a position stacks or dodges that extent and the scales, trained again after the position, cover
  it. A geom drawn at its x and y alone returns the frame as it is. It is a build function: the
  assembly calls it, and rendering calls `draw_panel/4`. **It is told whether each axis is
  discrete** (`axis_kinds`), which ggplot2's geoms read from a position's `mapped_discrete` class;
  a geom sees an axis's kind, never its range.
- **A bar is horizontal when its stat says so in `flipped_aes`, or else when y alone is
  discrete**, as ggplot2's `GeomBar` decides; it writes `flipped_aes` for the position and makes a
  horizontal bar as a vertical one, flipped and flipped back (`Aesthetics.flipped/1`).
- **A mark with a width and none given takes it from the spacing of its positions**
  (`Giggly.Resolution`), as ggplot2's `compute_data_size()` does: a bar takes the `width` its stat
  gave it, as counting does, or else 0.9 of the closest spacing of its x positions, not counting
  from zero, the smallest found in any panel; the `width` column is then dropped.
- **A geom calls the coordinate system itself**, as ggplot2's `draw_panel()` calls
  `coord$transform()`: a geom drawing lines (`Geom.Path`) places its rows with `Coord.munch/3`,
  which cuts them to follow the panel's curves, and every other with `transform/3`, which only
  the geom knows to choose. The params stay opaque to it.
- **A layer records its geom as a struct of its kind, and each geom is one module holding
  everything about it**: its struct, whose fields are its parameters; the facts a plot checks a
  layer's mapping against (`accepted_aesthetics/0`, `required_aesthetics/0`), which `Plot` reads;
  and its drawing, in a `defimpl Giggly.Geom` that opens by classifying itself into this boundary.
  The boundary exports the kinds; their drawing stays in their implementations.
- **A row missing a required position is not drawn.** ggplot2 also warns; a pure pipeline cannot,
  so how a dropped row is reported is open until something can report it.
- **A point looks like ggplot2's default point until aesthetics can change it:** black, size 1.5
  mm, border 0.5 mm, which grid draws as a circle of radius 1.95 points with a 0.71-point outline.
  **A bar looks like ggplot2's default bar, and a rectangle like its default rectangle:** filled
  `#595959`, ink mixed 35% toward paper, with no border, its border's width 0.5 mm all the same.
  The defaults move to the theme with the default-aesthetics stage. **A row's colour, mapped or
  set, replaces the default**: a point's colour, a bar's fill and border, a line's colour, read
  from each row (`Giggly.Geom.Mark.values/3`), where the assembly put it, so the scene carries one
  per mark. A point takes `color` and no `fill`, which colours only the filled shapes not yet
  drawn; a bar takes both; a line takes `color`.
- **A row's `alpha` replaces its colour's own alpha: a point's outline and fill alike, a bar's fill
  alone, a line's stroke**, as ggplot2's `GeomPoint` applies `alpha()` to both colours, `GeomRect`
  `fill_alpha()` to the fill and `GeomPath` `alpha()` to the line; a row without one, or a table
  without the column, keeps the colour's own, opaque for a colour with none, as ggplot2's default
  alpha, `NA`, leaves a colour. **A bar's border is never given the row's alpha**, only its own.
  `Giggly.Geom.Mark` is the one home of the rule, and a colour reaches the scene as its `#RRGGBB`
  and an opacity.
- **A colour of `:none`, R's `NA`, draws nothing**: no point and no line, as ggplot2's `GeomPoint`
  and `GeomPath` drop the rows whose colour is missing (`handle_na()`, a path's at a group's ends),
  and a bar left unfilled or unbordered, whatever the alpha, as `alpha(NA, a)` is `NA`; so a point's
  or a line's key draws nothing, and a bar's is left unfilled or unbordered. A frame's column holds
  one type, so `:none` fills a whole column, as a set `colour: :none` does, and never sits beside a
  mapped colour, which is never `NA` (a missing value maps to grey50).
- **A geom draws its own legend key (`draw_key/3`)**, as ggplot2's `draw_key` belongs to the geom:
  handed the key's aesthetic values, the layer's set values among them as ggplot2's key data holds
  its `aes_params`, and its size in points, it draws in the key's cell. A point's key is the point
  at the middle; a bar's is its fill short of the key by its border's width, 0.5 mm, as
  `draw_key_polygon()` takes `linewidth` millimetres off the key, its fill at the key's alpha and
  its border in its own; a path's is a segment across the middle from a tenth of the key's width
  to nine tenths, as `draw_key_path()` draws it, as wide as the layer's set `linewidth` or 0.5 mm,
  its ends the layer's and its corners round.
- **A path is drawn as ggplot2's `GeomPath` draws one.** Rows missing `x` or `y` at a group's ends
  are dropped (`keep_mid_true()`), and one in the middle breaks the line; the rows are put in
  group order, each group's in its own, and munched; a group of fewer than two rows is not drawn.
  **Where every group keeps one colour and one alpha all along it, each group is one polyline in
  its first row's colour and alpha; where any group's vary, the whole panel is segments**, one from
  each row to the next of its group, in its start's colour and alpha, a segment touching a missing
  position left out, as `GeomPath` tests its groups' `colour` and `alpha` for constancy. A discrete
  colour groups the rows, so it varies along a group only where `group` is mapped apart from it. A
  line is black, or its row's colour, and solid, as wide as the layer's set `linewidth` in
  millimetres or 0.5 (1.07 points, worked out as ggplot2's `linewidth * .pt` line-width units and
  svglite's points), with the geom's ends, corners and mitre limit (ggplot2's defaults: butt,
  round, 10).
- **Text (`Geom.Text`) is drawn as ggplot2's `GeomText` draws it**: a label per row at its `x` and
  `y`, its row's value as R's `as.character()` writes it (a whole number with no point, a float in
  up to 15 significant digits, scientific notation where it is shorter, `TRUE`, a date); black, or
  its row's colour at its row's alpha as a point; 11 points, the theme's base size, or the layer's
  `size` in millimetres times `.pt`; turned the layer's `angle`; justified by the layer's `hjust`
  along its baseline and `vjust` up the ascent of "M", a number or one of ggplot2's words, and
  `:inward` and `:outward` by where each label falls in the panel, as `compute_just()` decides. A
  row missing its place or label, or whose colour is `:none`, is not drawn. **A geom measures the
  text it draws** (`Giggly.Font`), since the scene draws a label at its measured width; **whether
  labels overlap is the backend's to decide** (`Scene.Text`'s `check_overlap`), since it turns on
  the panel's size in points, which no geom sees. Its key is the letter "a" at the layer's
  justification, turned as `rotate_just()` turns it, a tenth of a line in from the key's edges, as
  `draw_key_text()` draws it; ggplot2 widens a key for text too big for it, which waits for keys
  that size themselves.
- **A line (`Geom.Line`) is a path whose rows `setup_data/3` puts in order** of panel, group and
  `x`, or `y` for `orientation: :y`, as `GeomLine$setup_data()` orders them: ties keep their order,
  infinities sort at their ends, a missing position last, as R's `order()` sorts; it then draws
  and keys as a `Geom.Path` with its parameters, as ggplot2's `GeomLine` is a `GeomPath`. Its
  orientation is the layer's; one a stat names arrives with the first such stat.
- **A rectangle (`Geom.Rect`) is drawn as ggplot2's `GeomRect` draws one, and a bar is drawn as a
  rectangle**, its key too, as ggplot2's `GeomBar` draws with its parent `GeomRect`: so the
  rectangle owns the drawing and `Geom.Bar` only works out a bar's edges (`setup_data/3`). A
  rectangle's corners are left as they are by the build and drawn between, an `xmin` past its
  `xmax` included, as grid draws one; a row missing a corner is not drawn, and an infinite one is
  at the panel's edge, where the coordinate system puts it. Its corners are `xmin`, `xmax`,
  `ymin` and `ymax`; ggplot2 4.0 also places one by `x` and `width`, `y` and `height`, which
  waits, and so does a rectangle in radial coordinates, drawn square as a bar is.
