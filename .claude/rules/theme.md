---
paths:
  - "lib/giggly/theme.ex"
  - "lib/giggly/theme/**"
---

# The theme

`Giggly.Theme` gives everything a plot draws other than its marks its look: colours, sizes, line
widths and spacing, ggplot2's complete theme. Why the theme is a resolved value nobody can set
yet, why the point keeps its own look, and why it is called `:gray`: design-log §4, the entry
beginning "The theme is a resolved value".

## Rules

- **A plot always names its theme, `:gray` included**, and this namespace resolves the name with
  `complete/1` into a `%Giggly.Theme{}`; each theme is a module implementing the behaviour, as each
  facet and coordinate system is.
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
  assembly, arrive with the first mapped or set colour or size.

## How it works

`Theme.complete(:gray)` calls `Theme.Gray.complete/0`, which works each element out from
`theme_gray()`'s arguments (base size 11, black ink on white paper, lines and borders 11/22 mm) as
ggplot2's `theme-defaults.R` does: `half_line` is half the base size, and colours are ink mixed
toward paper by `col_mix()`, written as the hex values it rounds to. The plot records the name,
the assembly passes it on in `%Assembly{theme: …}`, and `Giggly.Render` resolves it once and hands
the complete theme to `Giggly.Guide`.
