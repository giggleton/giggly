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

- **A geom never sees a panel's size, a pixel, a scale's range or a facet.** Its boundary lists
  `Giggly.AsCharacter` for the text it writes, never a scale. It is handed one panel's rows, the
  plot's coordinate system and that panel's params, as ggplot2's `draw_panel()` is, places the rows
  with `Coord.transform/3`, and emits primitives in the cell's units, 0 to 1.
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
- **A geom is handed its layer's rows without the aesthetics other than position that the layer
  takes from the plot's mapping and cannot use** (the assembly's `drawn_data`), which ride along in
  `layer_data/2` and are drawn by nothing, so a geom never reads such a column as a value the layer
  sets: a path's carried `stroke`, a point's carried `linewidth`.
- **A row missing a required position is not drawn.** ggplot2 also warns; a pure pipeline cannot,
  so how a dropped row is reported is open until something can report it.
- **A point looks like ggplot2's default point unless its row says otherwise:** the solid circle
  (`:circle`, R's 19), black, no fill, size 1.5 mm, border 0.5 mm, which grid draws as a circle of
  radius 1.95 points with a 0.71-point outline. **A bar looks like ggplot2's default bar, and a
  rectangle like its default rectangle:** filled `#595959`, ink mixed 35% toward paper, with no
  border, its border's width 0.5 mm all the same. The defaults move to the theme with the
  default-aesthetics stage. **A row's colour, mapped or set, replaces the default**: a point's
  colour and fill, a bar's fill and border, a line's colour, read from each row
  (`Giggly.Geom.Mark.colors/3`), where the assembly put it, so the scene carries one per mark. A
  point takes `color` and `fill`, which fills only shapes 21 to 25; a bar takes both; a line takes
  `color`.
- **A point is drawn in its row's shape as R's graphics engine draws it** (`Giggly.Geom.Shape`,
  ported from `GESymbol()` in R's `engine.c`): each of the 26 shapes the circles, squares,
  polygons and line segments R draws it with, in R's order, worked out in points round the point
  from its font size, `size * .pt + stroke * .stroke / 2` (ggplot2's `gg_par()`), its outline
  `stroke * .stroke / 2` line-width units wide; a stroke of `:none`, R's `NA`, or a missing one,
  adds nothing to the size, outlines nothing and draws no segment, as R's engine draws a border of
  no width transparent and a line of no width not at all (`test/golden/point_no_stroke.svg`,
  written `0.00` wide where svglite writes `nan`). The open shapes are outlined in the colour alone;
  15 to 18 filled with it and not outlined; 19 and 20 outlined and filled with it; 21 to 25
  outlined with it and filled with the fill. A circle of no radius is not drawn, as `GECircle()`
  draws none; a square, polygon or segment of no size is. A shape of `:none`, or a missing one, as
  a colour's, draws no point, and so does a missing size, as `GeomPoint` drops a row whose size a
  size scale left missing. **Points are drawn in row order, each whole before the next**, so
  overlapping points stack as R's do; each run of elements of one kind and one outline width is one
  primitive. Every shape is checked against vdiffr's drawing (`test/golden/point_shapes.svg`).
- **A row's `alpha` replaces its colour's own alpha: a point's colour and fill alike, a bar's fill
  alone, a line's stroke**, as ggplot2's `GeomPoint` applies `alpha()` to the colour and
  `fill_alpha()` to the fill, `GeomRect` `fill_alpha()` to the fill and `GeomPath` `alpha()` to the
  line; a row without one, or a table without the column, keeps the colour's own, opaque for a
  colour with none, as ggplot2's default alpha, `NA`, leaves a colour. **A bar's border is never
  given the row's alpha**, only its own. `Giggly.Geom.Mark` is the one home of the rule, and a
  colour reaches the scene as its `#RRGGBB` and an opacity.
- **A colour of `:none`, R's `NA`, draws nothing**: no point and no line, as ggplot2's `GeomPoint`
  and `GeomPath` drop the rows whose colour is missing (`handle_na()`, a path's at a group's ends),
  and a bar left unfilled or unbordered, whatever the alpha, as `alpha(NA, a)` is `NA`; so a point's
  or a line's key draws nothing, and a bar's is left unfilled or unbordered. **A missing colour
  draws as `:none` does** (`Mark.colors/3`): a frame's column holds one type, so a set `colour:
  :none` fills its whole column, and a value a scale maps to `:none` (`na_value: :none`), or an
  annotation's list's `:none`, is held as `nil`, as R's column holds `NA`.
- **A geom draws its own legend key (`draw_key/2`) and says how much room it needs
  (`key_size/2`)**, as ggplot2's `draw_key` belongs to the geom: handed the key's aesthetic
  values, the layer's set values among them as ggplot2's key data holds its `aes_params`, it draws
  in the key's cell **by fractions of the cell and offsets in points**, as grid places a glyph by
  `npc` and absolute units, so it is right in a key of any size, and reports `{width, height}` in
  points, which the legend sizes its rows and column by (design-log §4, the entry beginning "A
  scale's `rescaler`"). A point's key is the point at the middle in the key's shape, size,
  stroke, colour and fill, as `draw_key_point()` draws it, and needs its size in millimetres
  either way, its stroke left out, as `set_key_size()` reads it; a bar's is its fill short of the
  key by its border's width, the key's `linewidth` or 0.5 mm, its corners offset half that
  in, as `draw_key_polygon()` takes `linewidth` millimetres off the key, its fill at the key's
  alpha and its border in its own, as wide and in the line type the key says, a blank or missing
  one not drawn, and needs twice its border's width, `draw_key_polygon()`'s `linewidth / 5` cm; a
  path's is a segment across the middle from a tenth of the key's width to nine tenths, as
  `draw_key_path()` draws it, as wide as the key's `linewidth` or 0.5 mm and in its line type, a
  blank or missing one drawing nothing, its ends the layer's and its corners round, and needs its
  width. **A key of a missing width, R's `NA`, draws nothing and needs no room**, a bar's because
  `draw_key_polygon()`'s rectangle then has no size. Each was checked against vdiffr's drawing of a
  key too big for the theme's, and of a missing width, a path's of a missing line type too.
- **A path is drawn as ggplot2's `GeomPath` draws one.** Rows missing `x` or `y`, a width or a
  line type at a group's ends are dropped (`keep_mid_true()`), and one missing a position in the
  middle breaks the line; the rows are put in group order, each group's in its own, and munched; a
  group of fewer than two rows is not drawn. **Where every group keeps one colour, alpha, width and
  line type all along it, each group is one polyline in its first row's look; where any group's
  vary, the whole panel is segments**, one from each row to the next of its group, in its start's
  colour, alpha and width, a segment touching a missing position, or starting from a missing width,
  left out, as `GeomPath` tests its groups' `colour`, `alpha`, `linewidth` and `linetype` for
  constancy and R's engine draws no line of no width. A discrete colour, line type or width groups
  the rows, so it varies along a group only where `group` is mapped apart from it. A line is black,
  or its row's colour, as wide as its row's `linewidth` in millimetres or 0.5 (1.07 points, worked
  out as ggplot2's `linewidth * .pt` line-width units and svglite's points), with the geom's ends,
  corners and mitre limit (ggplot2's defaults: butt, round, 10); the lines run in group order, each
  run alike in width and line type one primitive, and segments in row order, each run of one width
  one. **It is solid, or in its row's line type, dashed as svglite writes R's**
  (`Mark.dashes/2`): each length of its pattern times the line's width in line-width units, or 1
  where the line is narrower, in points; a blank line is not drawn, as R's engine draws none.
  **While any group's line type is other than solid, blank included, a panel where any group's
  look varies along it is refused when the plot is drawn**, as `GeomPath` aborts, so segments are
  always solid.
- **Text (`Geom.Text`) is drawn as ggplot2's `GeomText` draws it**: a label per row at its `x` and
  `y`, its row's value as R's `as.character()` writes it (`Giggly.AsCharacter`, which the scales'
  discrete levels share: a whole number with no point, a float in up to 15 significant digits,
  scientific notation where it is shorter, `TRUE`, a date); black, or its row's colour at its row's
  alpha as a point; 11 points, the theme's base size, or the layer's `size` in millimetres times
  `.pt`; turned the layer's `angle`; justified by the layer's `hjust` along its baseline and `vjust`
  up the ascent of "M", a number or one of ggplot2's words, and `:inward` and `:outward` by where
  each label falls in the panel, as `compute_just()` decides. A row missing its place or label, or
  whose colour is `:none`, is not drawn. **A geom measures the text it draws** (`Giggly.Font`),
  since the scene draws a label at its measured width; **whether labels overlap is the backend's to
  decide** (`Scene.Text`'s `check_overlap`), since it turns on the panel's size in points, which no
  geom sees. Its key is the letter "a" at the layer's justification, turned as `rotate_just()` turns
  it, a tenth of a line of its own text in from the key's edges, an offset turned into the text's
  frame, as `draw_key_text()` draws it, and needs the box round the letter turned with it, the
  font's descent added by the angle's sine and cosine and a margin each side of a tenth of a line
  of grid's default 12-point font, not its own, as `draw_key_text()` measures it, outside the
  text's font.
- **A line (`Geom.Line`) is a path whose rows `setup_data/3` puts in order** of panel, group and
  `x`, or `y` for `orientation: :y`, as `GeomLine$setup_data()` orders them: ties keep their order,
  infinities sort at their ends, a missing position last, as R's `order()` sorts; it then draws
  and keys as a `Geom.Path` with its parameters, as ggplot2's `GeomLine` is a `GeomPath`. Its
  orientation is the layer's; one a stat names arrives with the first such stat.
- **A rectangle (`Geom.Rect`) is drawn as ggplot2's `GeomRect` draws one, and a bar is drawn as a
  rectangle**, its key too, as ggplot2's `GeomBar` draws with its parent `GeomRect`: so the
  rectangle owns the drawing and `Geom.Bar` only works out a bar's edges (`setup_data/3`). **Each
  rectangle's border is as wide as its row's `linewidth`, 0.5 mm by default, and in its row's line
  type**, dashed as a line is, a blank one leaving it unbordered, as R's engine draws a blank
  border transparent, and so a missing width, written 0 wide where svglite writes `nan`, and the
  dashes written whether or not the border has a colour; the
  rectangles are drawn in row order, each run of borders alike in width and line type one
  primitive, as a point's elements run by outline width. A
  rectangle's corners are left as they are by the build and drawn between, an `xmin` past its
  `xmax` included, as grid draws one; a row missing a corner is not drawn, and an infinite one is
  at the panel's edge, where the coordinate system puts it. Its corners are `xmin`, `xmax`,
  `ymin` and `ymax`; ggplot2 4.0 also places one by `x` and `width`, `y` and `height`, which
  waits, and so does a rectangle in radial coordinates, drawn square as a bar is.
