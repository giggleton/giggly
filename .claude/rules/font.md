---
paths:
  - "guides/fonts.md"
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
  pinned only where svglite's measurement and Giggly's agree. **Installed fonts are searched too
  where `installed_fonts` says** (`to_svg/2`'s option, on by default, since a label in such a font
  is drawn as outlines: design-log §4, the entry beginning "A label measured with a font Pica"),
  handed down as the last argument of every measure, guide and geom drawing function, **never for
  `""` or R's generic names** (`"sans"`, `"serif"`, `"mono"`), whatever the machine has. **A face
  no font is found for is measured from the table, never another face's font.**
- **A registered font also gives each label's glyphs, as the scene carries them** (`Scene.Glyphs`,
  so `Giggly.Font` lists `Giggly.Scene`): placed as shaped at the size it is measured at, each its
  offset from a pen its advance moves on, so a label's glyphs span its measured width; outlines in
  the font's units; a glyph that draws nothing left out. A family measured from the table gives
  `:none`. A test that reads a font's glyphs is compiled only where Pica is
  (`Code.ensure_loaded?(Pica)` round it, beside its `:pica` tag), since the build without Pica
  types it as code that can never run.
- **What a user is told about fonts is `guides/fonts.md`**, which the family options, `theme/2`
  and `to_svg/2`'s `text:` and `installed_fonts:` link rather than restate: a change to which
  fonts a family is measured or drawn in, or to either option, updates it (design-log §4, the
  entry beginning "Fonts are explained by one guide").
- **The tables are vdiffr's, copied as written, never recomputed**: Liberation Sans's for every
  face but the symbol face, `priv/fonts/liberation_sans.txt`, and Symbola's for `:symbol`
  (grid's `fontface = 5`, which plotmath draws a sign in), `priv/fonts/symbola.txt`, each
  regenerated from vdiffr's `glyph_dims.h` as its header says. The ascent of "M", the descent of
  "gjpqyQ" and the missing glyph's metrics are read from them, never restated as constants.
- **The symbol face is measured from a font registered with Pica as `"symbol"`, svglite's alias
  for it, whatever the family, and otherwise from the Symbola table** — never an installed font
  (design-log §4, the entry beginning "A plotmath sign is drawn in the symbol face").
- **`box/5` is plotmath's box of a string**: the highest ascent and the deepest descent among its
  characters, each its own row of the table, a missing one codepoint 1's, or its own glyph box
  from a registered font, rounded outward to a pixel at 10,000 dpi as `ascent/4` and `descent/4`
  round "M" and "gjpqyQ"; none below zero, as plotmath's box starts from none.
- **The tables are read at compile time and only then**, behind one `CorePurity` waiver;
  measuring reads nothing but the fonts Pica holds, registered or installed, the first search of
  the installed ones reading the machine's font files, once for the VM's life, inside Pica. `@external_resource` recompiles the
  module when a file changes, and the paths come from `Application.app_dir/2`.
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
  the machine's: every measure and drawing function a test calls is handed `false`, and a plot
  naming a family no test registers is drawn with `installed_fonts: false`, and never under a family an existing golden names, so those goldens stay
  vdiffr's; each value they expect is svglite's measurement of the same file.
