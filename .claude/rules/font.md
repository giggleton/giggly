---
paths:
  - "lib/giggly/font.ex"
  - "priv/fonts/**"
  - "test/fonts/**"
  - "test/giggly/font_test.exs"
---

# Text measurement

`Giggly.Font` measures text as ggplot2's own SVG snapshots measure it, or in a font registered
with Pica as svglite measures one. Why vdiffr's Liberation Sans table, why a plain module rather
than a behaviour, and why the table is a file: design-log §4, the entry beginning "Axes are
drawn"; why Pica measures a family: the entry beginning "A font family is a name"; how: the
entry beginning "A registered font is measured".

## Rules

- **Text is measured here and nowhere else, when the scene is built.** A backend never measures:
  it draws each label at the width measured here (`svg.md`). Every measure takes the text's size,
  family and face.
- **A family and face a font is registered under with Pica is measured from that font**, in a
  project that lists Pica, by svglite's rules, as the module's comment gives them; a test is
  pinned only where svglite's measurement and Giggly's agree. **Only registered fonts are
  searched** (`installed: false`) until labels are drawn as outlines (design-log §4, the entry
  beginning "A label measured with a font Pica"). **A face no font is registered for is measured
  from the table, never another face's font.**
- **The table is vdiffr's Liberation Sans table, copied as written, never recomputed.**
  `priv/fonts/liberation_sans.txt` is regenerated from vdiffr's `glyph_dims.h` as its header
  says. The ascent of "M", the descent of "gjpqyQ" and the missing-glyph width are read from it,
  never restated as constants.
- **The table is read at compile time and only then**, behind a `CorePurity` waiver of its own;
  measuring reads nothing but the fonts registered with Pica. `@external_resource` recompiles the
  module when the file changes, and the path comes from `Application.app_dir/2`.
- **vdiffr's and R's rules for the table, which make ggplot2's snapshot layouts reproducible:** a
  string's width is the sum of its characters' advances, with no kerning; a character the font
  lacks takes codepoint 1's width; a line's height above its baseline is the ascent of "M"; the
  room below it is the deepest descent among "gjpqyQ", whatever the text.
- **Sizes are points (1/72 inch), as font sizes are.** ggplot2's theme lengths are TeX points
  (1/72.27 inch) and are converted where they are declared, not here.
- **Every other family is measured with the one table**: `""` and R's generic names unless a font
  is registered under that exact name, any family Pica lacks, and every family in a project
  without Pica, as vdiffr measures every family with Liberation Sans, so such a family changes how
  a label is drawn, never its width.
- **Pica is optional, and the switch is made when Giggly compiles**: behind
  `Code.ensure_loaded?(Pica)` the module measures through Pica, and without it by the table
  alone, naming none of Pica's functions; `Giggly.Font` and the root list `Pica` in their
  boundaries only when it is loaded. The gate builds and tests Giggly without Pica too
  (`dependencies.md`), leaving out the tests tagged `:pica` and running the `:without_pica` ones.
- **The tests measure only the fonts `test/test_helper.exs` registers**, from `test/fonts/`, never
  the machine's, and never under a family an existing golden names, so those goldens stay
  vdiffr's; each value they expect is svglite's measurement of the same file.
