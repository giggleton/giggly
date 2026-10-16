---
paths:
  - "lib/giggly/color_operations.ex"
  - "test/giggly/color_operations_test.exs"
---

# Colour operations

`Giggly.ColorOperations` reads a colour as a user writes one, and is the one module that calls the
`color` library. Why colours are CSS's and carried as hex strings: design-log §4, the entry
beginning "Colours are CSS's names and hex forms"; why the library is handed R's constants, and why
the module is not called `Color`: the entry beginning "R's exact colours come from the `color`
package"; why it nests under the umbrella: the entry beginning "A library's owner nests".

## Rules

- **It is the `color` library's only caller.** Its boundary lists `Color` alone, which the root
  lists too, as boundary lets a sub-boundary list only what its parent does, and no other domain
  lists it, as `Giggly.DataFrame` owns `table` (`.claude/rules/dependencies.md`); a boundary that
  needs a colour lists `Giggly.ColorOperations`, its sibling. A test never calls the library
  either: its expected colours come from CSS's table, or from R.
- **A colour has one spelling**: uppercase `#RRGGBB`, or `#RRGGBBAA` when it carries an alpha of its
  own, an alpha of FF dropped as opaque; and `:none`, R's `NA`, which draws nothing. No struct: it
  sits in a frame column, a layer's `fixed` and the scene as any string does.
- **`parse/1` takes what CSS takes, and refuses the rest**: a CSS colour name in any case, from the
  library's table less the chroma-key names it adds; CSS's four hex forms, their digits checked here,
  since the library reads a pair with `Integer.parse/2`, which takes a sign; `transparent`, CSS's
  black with no alpha; and `:none`. A name CSS does not define (R's `grey50`), a spelling the library
  forgives (a name with spaces, hex without its `#`) and CSS's functions (`rgb()`) are `:error`, and
  `Plot` raises naming the value.
