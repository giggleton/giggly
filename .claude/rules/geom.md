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
where its marks sit"; why its defaults are filled in from the theme as columns: the entry
beginning "Each layer's defaults are filled in from the theme".

## Rules

- **A geom never sees a panel's size, a pixel, a scale's range or a facet.** Its boundary lists
  `Giggly.AsCharacter` for the text it writes and `Giggly.ColorOperations` to mix its default
  colours, never a scale. It is handed one panel's rows, the
  plot's coordinate system and that panel's params, as ggplot2's `draw_panel()` is, places the rows
  with `Coord.transform/3`, and emits primitives in the cell's units, 0 to 1.
- **A geom has a say during the build: `setup_data/3`** gives each row the extent it is drawn
  over in data space, after the stat and before the position, as ggplot2's `setup_data()` does, so
  a position stacks or dodges that extent and the scales, trained again after the position, cover
  it. A geom drawn at its x and y alone returns the frame as it is. It is a build function: the
  assembly calls it, and rendering calls `draw_panel/4`. **It is told whether each axis is
  discrete** (`axis_kinds`), which ggplot2's geoms read from a position's `mapped_discrete` class;
  a geom sees an axis's kind, never its range.
- **A geom says what it draws with: `default_aesthetics/2`** gives each aesthetic it draws with
  and its value where the layer neither maps nor sets it, ggplot2's `default_aes` in R's order,
  worked out from the complete theme's `geom` element (`Giggly.Theme`: ink, paper, accent, the
  lines' and borders' widths and types, the text's family and size, the points' size and shape) as
  its `from_theme()` reads `element_geom()`. The assembly fills them into the rows and the keys, so
  every aesthetic a geom draws with is in every row and key it is handed and **a geom holds no
  default look of its own**; a default R gives as `NA` is `nil`. R's defaults Giggly has no
  aesthetic for are left out (text's `fontface` and `lineheight`, a box's `weight`), and so is the
  `width` R puts back into a bar's and a box's table once set up, which is not the width drawn.
- **A bar runs from 0 to its y, as R's `pmin(y, 0)` and `pmax(y, 0)` give its ends, an infinite
  one to the panel's edge**, its ends doubles, a missing y's missing; its sides are its x less and
  plus half its width, in R's arithmetic (`Giggly.DataFrame.Arithmetic`), so an infinite bin's are
  an infinity or NaN.
- **A bar is horizontal when its stat says so in `flipped_aes`, or else when y alone is
  discrete**, as ggplot2's `GeomBar` decides; it writes `flipped_aes` for the position and makes a
  horizontal bar as a vertical one, flipped and flipped back (`Aesthetics.flipped/1`).
- **A mark with a width and none given takes it from the spacing of its positions**
  (`Giggly.Resolution`), as ggplot2's `compute_data_size()` does: a bar takes its `width`, the
  one its stat gave it, as counting does, or the layer maps or sets (design-log §4, the entry
  beginning "Bars take R's `width:`"), or else 0.9 of the closest spacing of its x positions, not
  counting from zero, the smallest found in any panel; the `width` column is then dropped. A
  width that is not a number is refused when the plot is run. **A bar sits against its x as its
  struct's `just` says**, R's parameter, `x - width * just` to `x + width * (1 - just)`.
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
  sets: a path's carried `stroke`, a point's carried `linewidth`. Where one is among its geom's
  defaults, the default takes its place in the rows drawn (a point's carried `stroke`), while
  `layer_data/2` shows the carried column.
- **A row missing a required position is not drawn.** ggplot2 also warns; a pure pipeline cannot,
  so how a dropped row is reported is open until something can report it.
- **A point's defaults are ggplot2's under the theme:** its point shape, the solid circle
  (`:circle`, R's 19), its ink, no fill, its points' size (`base_size / 11 * 1.5` mm) and its
  borders' width (`base_line_size`) as the outline; at the default sizes 1.5 and 0.5 mm, which
  grid draws as a circle of radius 1.95 points with a 0.71-point outline. **A bar's and a
  rectangle's:** no border, a fill of ink mixed 35% toward paper (`ColorOperations.mix/3`:
  `#595959`, `#000000A6` on `theme_void()`'s clear paper), the borders' width and line type.
  **A row's colour, mapped or set, replaces the default**: a point's
  colour and fill, a bar's fill and border, a line's colour, read from each row
  (`Giggly.Geom.Mark.colors/2`), where the assembly put it, so the scene carries one per mark. A
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
  line; a row whose alpha is missing, the default, keeps the colour's own, opaque for a colour
  with none, as ggplot2's default alpha, `NA`, leaves a colour. **A bar's border is never
  given the row's alpha**, only its own. `Giggly.Geom.Mark` is the one home of the rule, and a
  colour reaches the scene as its `#RRGGBB` and an opacity.
- **A colour of `:none`, R's `NA`, draws nothing**: no point and no line, as ggplot2's `GeomPoint`
  and `GeomPath` drop the rows whose colour is missing (`handle_na()`, a path's at a group's ends),
  and a bar left unfilled or unbordered, whatever the alpha, as `alpha(NA, a)` is `NA`; so a point's
  or a line's key draws nothing, and a bar's is left unfilled or unbordered. **A missing colour
  draws as `:none` does** (`Mark.colors/2`, `Mark.key_color/2`): a frame's column holds one
  type, so a set `colour: :none` fills its whole column, and a value a scale maps to `:none`
  (`na_value: :none`), or an
  annotation's list's `:none`, is held as `nil`, as R's column holds `NA`, and so is a default R
  gives as `NA`, a rectangle's border or a point's fill.
- **A geom draws its own legend key (`draw_key/2`) and says how much room it needs
  (`key_size/2`)**, as ggplot2's `draw_key` belongs to the geom: handed the key's aesthetic
  values, the layer's set values among them as ggplot2's key data holds its `aes_params`, laid
  over its geom's defaults under the theme, as ggplot2 fills key data from `default_aes`, it draws
  in the key's cell **by fractions of the cell and offsets in points**, as grid places a glyph by
  `npc` and absolute units, so it is right in a key of any size, and reports `{width, height}` in
  points, which the legend sizes its rows and column by (design-log §4, the entry beginning "A
  scale's `rescaler`"). A point's key is the point at the middle in the key's shape, size,
  stroke, colour and fill, as `draw_key_point()` draws it, and needs its size in millimetres
  either way, its stroke left out, as `set_key_size()` reads it; a bar's is its fill short of the
  key by its border's width, the key's `linewidth`, its corners offset half that
  in, as `draw_key_polygon()` takes `linewidth` millimetres off the key, its fill at the key's
  alpha and its border in its own, as wide and in the line type the key says, a blank or missing
  one not drawn, and needs twice its border's width, `draw_key_polygon()`'s `linewidth / 5` cm; a
  path's is a segment across the middle from a tenth of the key's width to nine tenths, as
  `draw_key_path()` draws it, as wide as the key's `linewidth` and in its line type, a
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
  the rows, so it varies along a group only where `group` is mapped apart from it. A line is its
  row's colour, the theme's ink by default, as wide as its row's `linewidth` in millimetres, the
  theme's `base_line_size` by default (0.5 at the default sizes, 1.07 points, worked
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
  scientific notation where it is shorter, `TRUE`, a date); its row's colour, the theme's ink by
  default, at its row's alpha as a point; its size in millimetres times `.pt`, the layer's or else
  the theme's base size (`base_size / .pt`); turned the layer's `angle`; justified by the layer's
  `hjust` along its baseline and `vjust`
  up the ascent of "M", a number or one of ggplot2's words, and `:inward` and `:outward` by where
  each label falls in the panel, as `compute_just()` decides. A row missing its place or label, or
  whose colour is `:none`, is not drawn. **A geom measures the text it draws** (`Giggly.Font`),
  since the scene draws a label at its measured width; **whether labels overlap is the backend's to
  decide** (`Scene.Text`'s `check_overlap`), since it turns on the panel's size in points, which no
  geom sees. Its key is the letter "a" at the layer's justification (`:inward` and `:outward` read
  against the key's middle, so centred), turned as `rotate_just()` turns it, a tenth of a line of
  its own text in from the key's edges, an offset turned into the text's
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
  rectangle's border is as wide as its row's `linewidth`, the theme's `base_line_size` by default,
  and in its row's line
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
  **Its key is ggplot2's `draw_key_polygon()`, `Rect.polygon_key/3`, which bars, ribbons and areas
  share**, its ends and corners the layer's, as `draw_key_polygon()` reads the layer's `lineend`
  and `linejoin`: a rectangle's and a bar's cut square and mitred, a ribbon's and an area's as
  their struct says, round corners by default.
- **A ribbon (`Geom.Ribbon`) is set up and drawn as ggplot2's `GeomRibbon` does it.** Its setup
  runs along its struct's `orientation`, or, where that is `:none`, along y where it has no `ymin`
  or `ymax`, as `has_flipped_aes(range_is_orthogonal = TRUE)` reads a range (`Plot` makes sure it
  has a range, and refuses an orientation whose range is not given); writes `flipped_aes`; puts
  its rows in order of panel, group and the position it runs along, as `order()` puts them; and
  sets its `y` to its `ymin`, or its `ymax` where it has none. **It is drawn a piece at a time**:
  a row missing (`nil`, `:nan`; an infinity is the panel's edge) a position it needs, a ribbon's
  `x`, `ymin` and `ymax`, an area's `x` and `y`, each turned along y, is dropped, and each run of
  a group's rows left is a piece, as `handle_na()` numbers runs; each piece, in row order, is a
  polygon out along its `ymax` and back along its `ymin`, filled at its alpha and bordered only
  where `outline_type` is `:full`, then its outline, `:both` edges, `:upper` or `:lower`, each a
  line of the piece's colour at its colour's own alpha, never the row's, each edge munched on its
  own. A line of fewer than two points, a blank line type or a missing width draws no line, and a
  colour of `:none`, the default, is written with no stroke, as svglite writes one. A piece whose
  colour, fill, alpha, width or line type varies along it is refused when drawn: ggplot2 refuses a
  colour, width or line type that varies, and draws a varying fill or alpha as a gradient, which
  waits. A row `align_padding` marks is left off the upper edge. Its defaults are ggplot2's under
  the theme: no outline, a fill of ink mixed 20% toward paper (`#333333`), the borders' width
  and line type.
- **An area (`Geom.Area`) is a ribbon from 0 to its y**, as ggplot2's `GeomArea` is a
  `GeomRibbon`: its setup runs along y where its stat's `flipped_aes` says so, as aligning writes
  it, else as its struct's `orientation` says (`:x` unless the layer gives `:y`, as ggplot2 calls
  an area ambiguous), puts its rows in order as a ribbon's, and sets `ymin` to 0 and `ymax` to its
  y; it draws, and takes its defaults and key, as a ribbon does (`Ribbon.draw/5`), dropping a row
  missing its `x` or `y`. It holds no requirements of its own: the stat before it, aligning or a
  density, needs its `x` and `y`, and `Plot` checks a layer against the stat's.
- **A smooth (`Geom.Smooth`) is set up and drawn as ggplot2's `GeomSmooth` does it**: its setup
  writes its stat's orientation into every row's `flipped_aes` and puts its rows in order as a
  line's, along y where flipped; a panel is drawn a group at a time, in group order, each whole
  before the next: where its struct's `se`, its band as a ribbon's (`Ribbon.draw/5` with the
  ribbon's own defaults, both edges outlined, cut square, round corners) in no colour, so a row
  missing an end leaves it off and a curve of no degrees of freedom has none, then its line as a
  path's, in its colour's own alpha, never the row's, which fills the band. Its defaults are
  ggplot2's under the theme: the theme's accent (`#3366FF`), a fill of ink mixed 60% toward paper
  (`#999999`, `#00000066` on clear paper), twice the lines' width, their line type, a weight of 1
  and an alpha of 0.4. **Its key is `draw_key_smooth()`'s**: where `se`, the band's fill at the
  key's alpha over the whole key, unbordered at grid's default width (0.75 points), then a path's
  key at an alpha of 1, so a colour's own alpha leaves the key, needing a path's room; each
  checked against vdiffr's drawing (`test/golden/smooth_lm*.svg`).
- **A box plot (`Geom.Boxplot`) is set up and drawn as ggplot2's `GeomBoxplot` does it**
  (design-log §4, the entry beginning "A box plot takes R's options"). Its setup works along the
  stat's `flipped_aes`, flipped and flipped back; drops `outliers` where the layer keeps none, so
  the axes fit the whiskers; writes `ymin_final` and `ymax_final`, R's `pmin()` and `pmax()` of the
  outliers and the whiskers' ends; and puts its sides at x ∓ width/2, or with `varwidth` times its
  `relvarwidth` over the greatest in the layer, in R's arithmetic, dropping `width` and
  `relvarwidth`. **Each panel's boxes are drawn in the order of their groups, each whole before
  the next**, as ggplot2 splits a panel by group: outliers as points (`Geom.Point`), staples where
  `staplewidth` is not 0, whiskers, the box as a polygon, pinched in at its notches with `notch`,
  and the median. Each part takes its look from the struct's map for it, which holds only what the
  layer gave (a look absent is the box's own, `:none` R's `NA`), else the box's row; lines never
  take the box's alpha and its fill does; the median is twice the box's width unless its look
  gives one; the box is by default the theme's ink mixed 20% toward its paper (`#333333`,
  `#000000CC` on clear paper), filled with its paper, as wide as its borders and solid, its
  outliers its points' size, their stroke the layer's 0.5; staples and whiskers are cut square, the
  box and median cut square and mitred; a line of colour `:none` or missing, blank, or of missing
  width is not drawn, a box's border so left off, and a line missing an end is left out. **A box
  whose corners a scale's limits cut is drawn in the pieces left**, each run of two placed corners
  or more, as grid splits a polygon at a missing point (checked against vdiffr's drawing of
  `xlim()` cutting a plain and a notched box). **Its key is `draw_key_boxplot()`'s**, turned
  for a horizontal layer, which the legend says in the key's `flipped_aes`, its staples drawn
  though they have no length at a `staplewidth` of 0 and its median not doubled, and needs its
  `size` and `linewidth` added, in millimetres. A box in radial coordinates is drawn between its
  placed corners, not curved. Every part and key is checked against vdiffr's drawing
  (`test/golden/boxplot*.svg`).
