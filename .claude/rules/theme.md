---
paths:
  - "lib/giggly/theme.ex"
  - "lib/giggly/element_tree.ex"
---

# The theme

`Giggly.Theme` gives everything a plot draws other than its marks its look: colours, sizes, line
widths and spacing, ggplot2's complete theme, and the settings `Plot.theme/2` lays over it, and
gives the layers their defaults. Why the theme is a resolved value and why it is called `:gray`:
design-log §4, the entry beginning "The theme is a resolved value"; why the layers' defaults are
filled in from it as columns: the entry beginning "Each layer's defaults are filled in from the
theme"; why a theme is a function and
not a module implementing a behaviour: the entry beginning "A theme is a function"; why settings
are flat names with keyword-list elements, and R's rules for inheriting and merging: the entry
beginning "A theme is set element by element"; the increment's steps and what waits: the entry
beginning "The theme is Phase 3's eleventh increment"; what a removal takes and what it leaves:
the entry beginning "An element set to `:none` is removed"; why the border's fill is taken and
unused, and where the dashes and the axes' lines are worked out: the entry beginning "The panel's
border is never filled"; how a plot chooses a complete theme, what it records, and why settings
are laid over one in turn: the entry beginning "A plot chooses a complete theme"; where the
legends go and why a placement is resolved to `{x, y}`: the entry beginning "Legends go where the
theme puts them"; why the element tree is a boundary of its own beside the theme: the entry
beginning "The theme's element tree is a boundary of its own"; why text's face, angle and
justification are the theme's, and which of R's values are refused: the entry beginning "Text's
face, angle, justification and line height are the theme's"; which texts each of a complete
theme's families reaches: the entry beginning "A text's family is the theme's".

## Rules

- **A plot records its theme as the complete theme it chose and the settings laid over it**:
  `%{complete: :none, settings: %{}}` until a complete theme is chosen, which `choose/2` records
  as `%{name:, base_size:, base_line_size:, base_rect_size:, base_family:, header_family:}`, the
  widths `base_size / 22`, the base family `""` and the header family `:none`, R's `NULL`, unless
  given, with no settings, as ggplot2 drops a plot's earlier settings with the theme it replaces;
  `:none` draws in `theme_gray()` at its default sizes. This namespace resolves it with
  `complete/1` into a `%Giggly.Theme{}` when the plot is assembled, once the positions are final,
  as ggplot2's `plot_theme()` completes a plot's theme at build time.
- **The tree is ggplot2's (`.element_tree`), as far as Giggly draws:
  `Giggly.ElementTree.elements/0`** lists each element's name (ggplot2's, dots as underscores), its
  kind (`:line`, `:rect`, `:text`, `:length`, `:margin`, `:boolean`, `panel_ontop`'s, or a legend's
  placement: `:position`, `:point`, `:justification` by name or share, `:box_justification` by name
  alone, `:direction`, `:location`), the one element it inherits from (`:none` for a root) and what
  it styles, which `Theme` works out each element's kind and parent from and `Plot` turns into
  `theme/2`'s schema (in `Plot.Options`) and documentation, both while compiling, so the vocabulary
  has one home. **The tree is read only in module attributes, and only by `Theme` and `Plot`**, the
  only boundaries that list it: it holds the table and its `kind` type and calls nothing, so `Plot`
  is recompiled when the table changes, through `Plot.Options`, never when `Theme` does.
  **An element arrives with its first reader**: the tree holds what something draws and the
  elements those inherit from, and the struct holds only the leaves something draws, by axis and
  side (`axis_text_x_bottom`, `axis_ticks_length_y_left`, a radial panel's `theta` and `r`), the
  grid lines by axis, the panel spacing across and down, a legend key's width and height.
- **Resolution is ggplot2's `calc_element()`**: an element or a property left out is its
  parent's, worked out in turn; a size or a line width given as `{:rel, share}` is that share of
  the parent's resolved one, a length or a margin given so is that share of its parent's in the
  parent's unit; a text's margin is replaced whole, its sides never inherited one by one.
  **`merge/2` is ggplot2's `add_theme()`**: a line's, a rectangle's or a text's properties
  replace only the properties given, a length or a margin replaces the one before, and so do a
  removal and an element given after one. **Under a chosen complete theme, an element given after
  a removal of it is `{:replace, element}`**, which `complete/1` puts in place of the theme's
  element instead of merging into it, and properties given later merge into it, as ggplot2 lays
  each setting over an added complete theme in turn; a plot that chose none merges its settings
  first and lays them over `theme_gray()` as one, so there the element merges into the theme's.
- **A line, a rectangle or a text set to `:none` is removed and works out as `:none`**, as
  `calc_element()` works a blank out: a complete theme's elements take a removed parent's removal;
  an element a setting gives, which `complete/1` marks `inherit_blank: false`, skips every removed
  element above it. A root's unset property is `theme_gray()`'s at its default sizes whatever the
  complete theme, as ggplot2 fills a root from its default theme, which a root a setting replaces
  whole shows; under a removed root passed over, a property nothing gives is grid's default
  (the `@grid_` attributes), a share of a parent that gives none is nothing, one with no parent
  at all the share itself, and one inherited from a parent still a share is taken of it again;
  a text's justification nothing gives is centred, grid's, where R itself fails.
  A length or a margin is never removed.
- **Two drawn elements are worked out as ggplot2's guides work them out**, not by the tree alone: a
  legend's title and labels take their default margins from a `text` laid over the theme, the root
  text's margin widened by `legend_key_spacing` on the side facing the keys, worked out for each
  side they are drawn on (`legend_title_top`, below it; `legend_title_left`, right of it;
  `legend_text_right`, left of it; `legend_text_bottom`, above it, below a colour bar), and their
  default justification from it too (a title and labels right of keys `{0, 0.5}`, labels below a
  colour bar `{0.5, 1}`), so the root text's justification never reaches them while its face and
  angle do; what `legend_title`, `legend_text` or `title` sets replaces both, and the laid text
  replaces a removed root text, so they are drawn where every other text is removed; and a colour
  bar's ticks are
  `guide_colourbar()`'s white 0.5 / .pt mm only where the settings leave `legend_ticks` unset
  (`replace_null()`), so a colour given every line never reaches them, made as a setting is, so they
  skip a removed `line`.
- **A complete theme is a function in `Giggly.Theme` that builds its tree of partial elements
  from its base sizes**, as ggplot2's are functions (`theme_gray()`), never a module implementing
  a behaviour: themes differ only in their values, where facets and coordinate systems differ in
  what they do. A theme derived from another builds on that function's elements by replacing some
  whole, ggplot2's `%+replace%`, so what it leaves unset is inherited, never the base theme's:
  `bw/1`, `light/1` and `dark/1` from `gray/1`, `linedraw/1`, `minimal/1` and `classic/1` from
  `bw/1`; `void/1` is a tree of its own. Their colours are `col_mix()` of black ink and white
  paper as ggplot2 rounds it, constants named by their share, and `theme_void()`'s paper is ink
  with no alpha.
- **The base sizes reach every element as ggplot2's do**: `base_size` every text's size and,
  through `half_line`, every spacing and margin and so the ticks' length; `base_line_size` every
  line's width, `base_rect_size` every border's; a legend's keys stay 1.2 of grid's lines, and
  `theme_void()` takes neither width, its borders 0 wide; and the layers' defaults: `base_size`
  the text's size and the points' (`base_size / 11 * 1.5`), `base_line_size` the lines' and the
  borders' widths, `theme_void()`'s too, never `base_rect_size`. **So do the families**:
  `base_family` the root text's family and the layers' (`geom`'s); `header_family`, where given,
  `title`'s, so of what Giggly draws only the axes' titles, the legends' titles and the plot's
  title take it, as ggplot2's tree gives no other text `title` for a parent; where it is `:none`,
  `title` sets no family. A family set on `text` never reaches a layer, and under a removed root
  text passed over, a family nothing gives is grid's `""`.
- **The complete theme holds every element already worked out, in the scene's units:** lengths,
  margins and line widths in points (1/72 inch), each colour an `#RRGGBB` beside its opacity (a
  rectangle's `fill_opacity` and `color_opacity`, a line's or a text's `opacity`), its alpha over
  255, 0 for `:none`, every margin a map of its four sides, every text's family as named, its
  face, its angle in degrees and its justification as floats. **A length is held as `{amount, unit}`
  until worked out, and converted in grid's order of operations** (TeX's points over 72.27,
  centimetres over 2.54, millimetres over 10 and then 2.54, lines of text as a 12-point font at a
  line height of 1.2 over 72; then times 72), and a line width from millimetres as R's engine hands
  it to svglite (`linewidth * .pt / 96 * 72`), so a resolved value is R's to the last bit; nothing
  that reads the theme converts anything. **The layers' defaults (`geom`) are the exception, in a
  layer's units**: millimetres and colours in their one spelling, as they become the values of a
  layer's aesthetics, which a layer may set instead.
- **A theme is values and calls nothing.** Its boundary lists only the element tree, which it
  reads while compiling; `Plot` lists it to choose a complete theme and merge settings, the
  assembly to complete it and read the layers' defaults, rendering and the guide to read the
  complete theme. It knows no scene primitive: the drawing builds primitives from its elements.
- **A theme holds sizes, colours, line widths, line types and ends, margins and spacing, text's
  families, faces, angles and justification, and whether the panel is drawn over its layers**:
  the y title turned 90 degrees and the labels hung from their ticks are `theme_gray()`'s and
  `theme_void()`'s settings, the only complete themes that set any (the rest inherit `gray/1`'s,
  as R's do). A line's corners (`linejoin`, round, as `theme_gray()`'s) stay with the drawing.
- **A line type is worked out into `dashes` in points, as svglite writes R's**: each length of
  its pattern times the width in R's line-width units (`linewidth * .pt`), or 1 where narrower,
  `:none` for a solid one. A line of the blank line type works out `dashes: :blank`, which the
  drawing skips while it keeps its room, as R's engine draws no such line; a rectangle's border
  of it works out as no border (`color: :none`). A line's end is its `lineend`, `theme_gray()`'s
  butt, grid's round under a removed `line`; a rectangle's fill may be `:none`, R's `NA`.
- **`theme_gray()` removes the axis lines and the panels' border and draws the panel under its
  layers** (`axis_line` and `panel_border` `:none`, `panel_ontop: false`), so they are drawn only
  where a setting gives them, inheriting from `line` and `rect` past the removal.
- **A legend's placement is resolved as ggplot2's guide box reads it**: each justification to
  `{x, y}` as grid's `valid.just()` reads a name or a share, centred where nothing gives one, as
  `theme_void()` gives none; `legend_position_inside` to its point, or the inside justification's
  where unset; `legend_location` to `:panel` where unset; `legend_direction`, `legend_box` and
  `legend_box_just` to `:none` where unset, which rendering and `Guide.Box` work out from the
  position, as ggplot2's `Guides$draw()` and `package_box()` do, so the theme never holds a
  default that depends on where the legends go. **A theme that leaves `legend_spacing` unset has
  half a line between legends** (`theme_void()`'s 7.2 points), as `Guides$assemble()` fills it in
  before `legend_spacing_x` and `_y` inherit it. **`legend_box_background` is a root and is
  worked out as its setting gives it, inheriting nothing**, its unset properties grid's (white,
  a black border 0.75 points wide), as `package_box()` draws `theme$legend.box.background`
  without `calc_element()`, though ggplot2's tree names `rect` its parent (design-log §4, the
  entry beginning "Legends go where the theme puts them"). Values R takes loosely are refused at
  the call: an unknown position, box or location, a numeric `legend_position`, numbers in
  `legend_box_just`.
- **What waits** (design-log §4, the entry beginning "The theme is Phase 3's eleventh
  increment"): from legend placement, `legend.title.position`,
  `legend.text.position`, `legend.byrow`, `legend.key.spacing.x` and `.y` as settings (a legend
  running across spaces its keys `legend_key_spacing` both ways, as ggplot2 does when neither is
  set), `legend.key.justification`, `legend.frame`. A complete theme's `ink`, `paper` and
  `accent` as options, `theme(geom:)`, and `theme_test()`, wait beyond the increment.
- **The layers' defaults are the complete theme's `geom` element, ggplot2's `element_geom()`**,
  which every complete theme sets in its tree from its base sizes (`gray/1`, inherited by the
  themes built on it, and `void/1`): black ink; white paper, `theme_void()`'s clear; the accent
  `#3366FF`, a smooth's colour, in every theme; the lines'
  and the borders' widths, solid; the text's family, the base family, and size; the points' size
  and shape.
  No setting reaches it, since `theme/2` cannot set `geom` yet. Each geom reads what it draws with
  from it (`Geom.default_aesthetics/2`), mixing its colours from the ink and paper. **The
  palettes are not the theme's:** ggplot2 4's `set_palettes()` takes a scale's palette from the
  theme, and `theme_gray()` sets none, so the scale's fallback, `pal_hue()`, is its default here.
- **A title's look carries its line spacing** (`Theme.title()`: `line_spacing`, the points from
  one line's baseline to the next's, its `lineheight`, 0.9 unless set, x 1.2 times its size, as
  R's graphics engine reads it), since only titles break over lines: the axes' and the legends'
  titles, and the plot's own, `theme_gray()`'s `plot.title` (1.2 times the base size, `half_line`
  below it, left-aligned and hung), `plot.subtitle` (the base size, `half_line` below, the same),
  `plot.caption` (0.8 of it, `half_line` above, right-aligned and hung) and `plot.tag` (1.2 times
  it, no margin, centred), all black. Any other text takes a `lineheight` and holds none.
- **A legend's look is `theme_gray()`'s at its defaults**: right of the panels, centred
  (`legend.justification`), in a box with no margin and no background; paper white with no border,
  `half_line` inside its edge (`legend.margin`, from the theme's `margins`), `2 * half_line` from
  the next legend below or beside it (`legend.spacing.y` and `.x`, from `legend.spacing`) and
  `2 * half_line` from the panels (`legend.box.spacing`); keys 1.2 lines square as grid works lines
  out at its own defaults, a 12-point font at line height 1.2, 17.28 points, not at the base size,
  on the panel's background (`legend.key` inherits it); the title black at the base size with
  `half_line` below it, the labels black at 0.8 of it and `half_line` from the keys
  (`legend.key.spacing`, from `spacing`); a colour bar's ticks white and 0.5 / .pt millimetres wide,
  `guide_colourbar()`'s default since `theme_gray()` sets no `legend.ticks`, worked out in R's order
  of operations to svglite's 0.38, reaching a fifth of the key size into the bar
  (`legend.ticks.length`, `rel(0.2)` of `legend.key.size`).
