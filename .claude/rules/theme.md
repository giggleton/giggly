---
paths:
  - "lib/giggly/theme.ex"
---

# The theme

`Giggly.Theme` gives everything a plot draws other than its marks its look: colours, sizes, line
widths and spacing, ggplot2's complete theme. Why the theme is a resolved value nobody can set
yet, why the point keeps its own look, and why it is called `:gray`: design-log §4, the entry
beginning "The theme is a resolved value"; why a theme is a function and not a module implementing
a behaviour: the entry beginning "A theme is a function".

## Rules

- **A plot always names its theme, `:gray` included**, and this namespace resolves the name with
  `complete/1` into a `%Giggly.Theme{}`.
- **A complete theme is a function in `Giggly.Theme` that builds that value**, as ggplot2's are
  functions (`theme_gray()`), never a module implementing a behaviour: themes differ only in their
  values, where facets and coordinate systems differ in what they do. A theme derived from
  another, as `theme_bw()` is from `theme_grey()`, builds on that function's value by replacing
  elements.
- **The complete theme holds every element already worked out, in the scene's units:** lengths
  and line widths in points (1/72 inch), colours as hex strings. ggplot2's TeX points and
  millimetres are converted where a theme declares them, so nothing that reads the theme converts
  anything.
- **A theme is values and calls nothing.** Its boundary lists nothing; rendering and the guide
  list it and read its fields. It knows no scene primitive: the drawing builds primitives from
  its elements.
- **A theme holds sizes, colours, line widths and spacing; alignment and angle stay with the
  drawing** (the y title turned 90 degrees, labels hung from their ticks) until a theme can set
  them.
- **An element arrives with its first reader.** The struct holds only elements something draws;
  each new drawing adds the element it reads.
- **Nothing can change a theme yet.** `theme/2`, other complete themes and their arguments,
  element constructors and inheritance (`rel()`, `element_blank()`) arrive with the first theme
  setting a user can make; so does accepting `:grey`.
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
  reaching a fifth of the key's width into the bar (`legend.ticks.length`, `rel(0.2)`).
