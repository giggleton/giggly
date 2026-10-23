---
paths:
  - "lib/giggly/font.ex"
  - "priv/fonts/**"
  - "test/giggly/font_test.exs"
---

# Text measurement

`Giggly.Font` measures text as ggplot2's own SVG snapshots measure it. Why vdiffr's Liberation
Sans table, why a plain module rather than a behaviour, and why the table is a file: design-log
§4, the entry beginning "Axes are drawn".

## Rules

- **Text is measured here and nowhere else, when the scene is built.** A backend never measures:
  it draws each label at the width measured here (`svg.md`).
- **The metrics are vdiffr's Liberation Sans table, copied as written, never recomputed.**
  `priv/fonts/liberation_sans.txt` is regenerated from vdiffr's `glyph_dims.h` as its header
  says. The ascent of "M", the descent of "gjpqyQ" and the missing-glyph width are read from it,
  never restated as constants.
- **The table is read at compile time and only then**, behind a `CorePurity` waiver of its own;
  measuring reads nothing. `@external_resource` recompiles the module when the file changes, and
  the path comes from `Application.app_dir/2`.
- **vdiffr's and R's rules, which make ggplot2's snapshot layouts reproducible:** a string's width
  is the sum of its characters' advances, with no kerning; a character the font lacks takes
  codepoint 1's width; a line's height above its baseline is the ascent of "M"; the room below it
  is the deepest descent among "gjpqyQ", whatever the text.
- **Sizes are points (1/72 inch), as font sizes are.** ggplot2's theme lengths are TeX points
  (1/72.27 inch) and are converted where they are declared, not here.
- **No behaviour until a second font**: the theme's text family, or a backend that can measure.
