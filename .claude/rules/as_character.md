---
paths:
  - "lib/giggly/as_character.ex"
  - "test/giggly/as_character_test.exs"
---

# Values as R writes them

`Giggly.AsCharacter` writes a value as R's `as.character()` writes it, for a text's label, a
discrete scale's level and a facet's strip. Why it is a boundary of its own: design-log §4, the
entry beginning "R's `as.character()` is a boundary of its own".

## Rules

- **It is R's `as.character()`, rule for rule, each checked against R**: a float in up to 15
  significant digits, plain or scientific whichever is shorter, a tie to plain; a whole number
  with no point; `TRUE`, `FALSE`, `Inf`, `-Inf`, `NaN`; a date as R prints one. Its tests pin R's
  own output.
- **It depends on nothing, and its callers list it**: `Giggly.Geom` for a text's labels,
  `Giggly.Scale` for discrete levels and `Giggly.Facet` for strips, none of which lists another. A
  rule for writing a given value as text lives here, never copied into a caller.
- **A missing value has no text here.** Each caller says what one means: text leaves its row out,
  a scale and a strip label it `NA`.
