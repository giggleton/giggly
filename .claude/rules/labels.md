---
paths:
  - "lib/scales/labels.ex"
  - "lib/scales/labels/**"
  - "test/scales/labels_test.exs"
  - "test/scales/labels_format_test.exs"
---

# Labels

`Scales.Labels` writes a scale's labels as scales 1.4.0's `label_number()`, `label_comma()`,
`label_percent()` and `label_currency()` do, `Scales.Labels.Format` writing their numbers as R's
`format()` does; and plainly, the Elixir way (`plain/1`, `scales.md`), the default labels of a
number's transformations.
Why list functions: design-log §4, the entry beginning "`labels:` takes a list"; why these
names and options: the entry beginning "`Scales.Labels`'s"; why `format()` is ported whole: the
entry beginning "R's `format()` for numbers"; why a missing break's label is `nil`: the entry
beginning "A missing break's label".

## Rules

- **Every label of `number/2`, `comma/2`, `percent/2` and `currency/2` is R's to the character,
  and the tests pin R's own output**, each beside the R
  call that gave it (`giggly-r:ggplot2-4.0.3`). A label that differs from R's is a bug, except
  where the module comments say this differs, and say why.
- **`Labels.Format` is R's `format()` for numbers, `formatReal()` rule for rule** (digits 1 to
  22, `nsmall`, trim, either notation, marks, `NA` and the non-finite values), its tests pinning
  R's output; all of 6,000 random vectors matched R. **R's `scientific = FALSE` is plain unless
  more than 310 characters wider**, a margin bisected from R's output, which its documentation
  never gives; a row of R's that stops matching is a bug, and the margin moves only by measuring
  R again.
- **A missing break, `nil`, has no label, `nil`, where R gives `NA`**, and widens the others'
  untrimmed padding to `NA`'s two characters, as R's `format()` does; the other labels' accuracy
  and cents are worked out without it, and under `scale_cut:` it takes no step.
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
