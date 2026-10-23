---
paths:
  - "lib/giggly/theme.ex"
---

# The theme

`Giggly.Theme` gives everything a plot draws other than its marks its look: colours, sizes, line
widths and spacing, ggplot2's complete theme, and the settings `Plot.theme/2` lays over it. Why the
theme is a resolved value, why the point keeps its own look, and why it is called `:gray`:
design-log §4, the entry beginning "The theme is a resolved value"; why a theme is a function and
not a module implementing a behaviour: the entry beginning "A theme is a function"; why settings
are flat names with keyword-list elements, and R's rules for inheriting and merging: the entry
beginning "A theme is set element by element"; the increment's steps and what waits: the entry
beginning "The theme is Phase 3's eleventh increment".

## Rules

- **A plot records its theme as the complete theme's name and the settings laid over it**
  (`%{complete: :gray, settings: %{}}` until `theme/2` sets one), and this namespace resolves it
  with `complete/1` into a `%Giggly.Theme{}` when the plot is drawn, as ggplot2's `plot_theme()`
  completes a plot's theme at build time.
- **The tree is ggplot2's (`.element_tree`), as far as Giggly draws: `elements/0`** lists each
  element's name (ggplot2's, dots as underscores), its kind (`:line`, `:rect`, `:text`,
  `:length`, `:margin`), the one element it inherits from (`:none` for a root) and what it styles,
  which `Plot` turns into `theme/2`'s schema and documentation, so the vocabulary has one home.
  **An element arrives with its first reader**: the tree holds what something draws and the
  elements those inherit from, and the struct holds only the leaves something draws, by axis and
  side (`axis_text_x_bottom`, `axis_ticks_length_y_left`, a radial panel's `theta` and `r`), the
  grid lines by axis, the panel spacing across and down, a legend key's width and height.
- **Resolution is ggplot2's `calc_element()`**: an element or a property left out is its
  parent's, worked out in turn; a size or a line width given as `{:rel, share}` is that share of
  the parent's resolved one, a length or a margin given so is that share of its parent's in the
  parent's unit; a text's margin is replaced whole, its sides never inherited one by one.
  **`merge/2` is ggplot2's `add_theme()`**: a line's, a rectangle's or a text's properties
  replace only the properties given, a length or a margin replaces the one before.
- **Two drawn elements are worked out as ggplot2's guides work them out**, not by the tree
  alone: a legend's title and labels take their default margins from a `text` laid over the
  theme, the root text's margin widened by `legend_key_spacing` on the side facing the keys (below
  the title, left of the labels), which a margin set on `legend_title`, `legend_text` or `title`
  replaces; and a colour bar's ticks are `guide_colourbar()`'s white 0.5 / .pt mm only where the
  settings leave `legend_ticks` unset (`replace_null()`), so a colour given every line never
  reaches them.
- **A complete theme is a function in `Giggly.Theme` that builds its tree of partial elements**,
  as ggplot2's are functions (`theme_gray()`), never a module implementing a behaviour: themes
  differ only in their values, where facets and coordinate systems differ in what they do. A theme
  derived from another, as `theme_bw()` is from `theme_grey()`, builds on that function's elements
  by replacing some.
- **The complete theme holds every element already worked out, in the scene's units:** lengths,
  margins and line widths in points (1/72 inch), colours as hex strings, every margin a map of its
  four sides. **A length is held as `{amount, unit}` until worked out, and converted in grid's
  order of operations** (TeX's points over 72.27, centimetres over 2.54, millimetres over 10 and
  then 2.54, lines of text as a 12-point font at a line height of 1.2 over 72; then times 72), and
  a line width from millimetres as R's engine hands it to svglite (`linewidth * .pt / 96 * 72`),
  so a resolved value is R's to the last bit; nothing that reads the theme converts anything.
- **A theme is values and calls nothing.** Its boundary lists nothing; `Plot` lists it to build
  `theme/2`'s schema and merge settings, rendering and the guide to read the complete theme. It
  knows no scene primitive: the drawing builds primitives from its elements.
- **A theme holds sizes, colours, line widths, margins and spacing; alignment and angle stay with
  the drawing** (the y title turned 90 degrees, labels hung from their ticks) until a theme can
  set them; so do line types, line ends, text faces and families.
- **What waits, by step** (design-log §4, the entry beginning "The theme is Phase 3's eleventh
  increment"): removing an element (`:none`) and `legend_position`; the panel border, axis lines,
  line types and `panel_ontop`; the other complete themes and accepting their arguments; where
  the legends go; text's face, angle and alignment. A theme colour is opaque, a rectangle's border
  `:none` too, until a theme needs transparency (`theme_void()`'s paper).
- **The point's look is not the theme's yet.** ggplot2 4 reads its `element_geom` when the build
  fills each layer's default aesthetics as columns; that stage, and the theme resolved in the
  assembly, arrive with a default a theme can change, which neither a set nor a mapped colour
  needed. **Nor are the palettes:** ggplot2 4's `set_palettes()` takes a scale's palette from the
  theme, and `theme_gray()` sets none, so the scale's fallback, `pal_hue()`, is its default here.
- **A title's look carries its line spacing** (`Theme.title()`: `line_spacing`, the points from
  one line's baseline to the next's, 0.9 x 1.2 times its size, ggplot2's `lineheight` as R's
  graphics engine reads it), since only titles break over lines: the axes' and the legends'
  titles, and the plot's own, `theme_gray()`'s `plot.title` (1.2 times the base size, `half_line`
  below it), `plot.subtitle` (the base size, `half_line` below), `plot.caption` (0.8 of it,
  `half_line` above) and `plot.tag` (1.2 times it, no margin), all black.
- **A legend's look is `theme_gray()`'s at its defaults**: paper white with no border, `half_line`
  inside its edge (`legend.margin`, from the theme's `margins`), `2 * half_line` above the next
  legend (`legend.spacing.y`, from `legend.spacing`) and `2 * half_line` from the panels
  (`legend.box.spacing`); keys 1.2 lines square as grid works lines out at its own defaults, a
  12-point font at line height 1.2, 17.28 points, not at the base size, on the panel's background
  (`legend.key` inherits it); the title black at the base size with `half_line` below it, the
  labels black at 0.8 of it and `half_line` from the keys (`legend.key.spacing`, from `spacing`);
  a colour bar's ticks white and 0.5 / .pt millimetres wide, `guide_colourbar()`'s default since
  `theme_gray()` sets no `legend.ticks`, worked out in R's order of operations to svglite's 0.38,
  reaching a fifth of the key size into the bar (`legend.ticks.length`, `rel(0.2)` of
  `legend.key.size`).
