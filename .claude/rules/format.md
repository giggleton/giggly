---
paths:
  - "lib/scales/format.ex"
  - "lib/scales/format/**"
  - "test/scales/format_test.exs"
---

# Formatters

`Scales.Format` writes a scale's labels as scales 1.4.0's `label_comma()`, `label_percent()` and
`label_currency()` do, `Scales.Format.Fixed` writing their numbers as R's `format()` does; and
plainly, the Elixir way (`plain/1`, `scales.md`), the default labels of a number's
transformations.
Why list functions: design-log §4, the entry beginning "`labels:` takes a list"; why these
names and options: the entry beginning "`Scales.Format`'s".

## Rules

- **Every label of `comma/2`, `percent/2` and `currency/2` is R's to the character, and the tests
  pin R's own output**, each beside the R
  call that gave it (`giggly-r:ggplot2-4.0.3`). A label that differs from R's is a bug, except
  where the module comments say this differs, and say why.
- **R's order of floating-point operations is kept**: rounding is `round(x / (accuracy /
  scale)) * (accuracy / scale)` and a step's scale `scale * (1 / threshold)`, since reordering
  moves labels (two and a half billion is `3B` under the short scale).
- **A float is printed from its exact value, a half to even, never with `float_to_binary/2`'s
  `decimals:`**, which rounds a tie away from zero where R's `sprintf()` does not; `plain/1`
  rounds to 15 significant digits first, so `decimals:` only pads its labels.
- **Its options are NimbleOptions schemas, as every public option in Giggly is**, so a bad one
  raises `NimbleOptions.ValidationError` and each formatter's option docs are generated from its
  schema; its boundary lists NimbleOptions and nothing else. The package's transformations call
  `plain/1` for their default labels; a user hands the others to a scale's labels.
- **Only what R offers, and only where R's answer is sound**: no superseded name (`currency`,
  not `dollar`), and a `scale_cut:` list without a zero threshold is refused, the one shape where
  R misaligns its steps.
