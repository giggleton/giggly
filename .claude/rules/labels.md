---
paths:
  - "lib/scales/labels.ex"
  - "lib/scales/labels/**"
  - "test/scales/labels_test.exs"
  - "test/scales/labels_format_test.exs"
  - "test/scales/labels_arithmetic_test.exs"
---

# Labels

`Scales.Labels` writes a scale's labels as scales 1.4.0's `label_number()`, `label_comma()`,
`label_percent()`, `label_currency()`, `label_scientific()`, `label_number_auto()`,
`label_log()` and `format_log()` do, `Scales.Labels.Format` writing their numbers as R's
`format()` does and `Scales.Labels.Arithmetic` rounding them as R does; and plainly, the
Elixir way (`plain/1`, `scales.md`), the default labels of a number's transformations.
Why list functions: design-log §4, the entry beginning "`labels:` takes a list"; why these
names and options: the entry beginning "`Scales.Labels`'s"; why `format()` is ported whole: the
entry beginning "R's `format()` for numbers"; why a missing break's label is `nil`: the entry
beginning "A missing break's label"; why a power is a value: the entries beginning "`log/2`
returns powers" and "A signed power"; why the new labellers take the options they do and
refuse what they refuse: the entries beginning "`scientific/2` takes", "`digits:` is an
integer", "`log/2` refuses" and "`format_log/2` takes".

## Rules

- **Every label of `number/2`, `comma/2`, `percent/2`, `currency/2`, `scientific/2`,
  `number_auto/1`, `log/2` and `format_log/2` is R's to the character, and the tests pin R's own
  output**, each beside the R call that gave it (`giggly-r:ggplot2-4.0.3`). A label that differs
  from R's is a bug, except where the module comments say this differs, and say why. All of
  11,941 random cases of the last four matched R, and 1,728 of the first four near the largest
  double.
- **A break `scale:` takes past the largest double is R's `Inf`**, never a raise: Erlang refuses
  the arithmetic R takes to an infinity, so each `*`, `/` and `-` on a break that can pass it is
  `Labels.Arithmetic`'s, the infinity an atom. Rounded past it, the label is `Inf`, its sign
  styled, its prefix and suffix dropped, as R's `number()` writes it; scaled past it only,
  `Inf` inside them; it takes no step and no cents, and no part in the others' accuracy.
- **`Labels.Format` is R's `format()` for numbers, `formatReal()` rule for rule** (digits 1 to
  22, `nsmall`, trim, either notation, marks, `NA` and the non-finite values, each padded to the
  numbers' marked width), its tests pinning R's output; all of 6,000 random vectors matched R. **R's `scientific = FALSE` is plain unless
  more than 310 characters wider**, a margin bisected from R's output, which its documentation
  never gives; a row of R's that stops matching is a bug, and the margin moves only by measuring
  R again.
- **A missing break, `nil`, has no label, `nil`, where R gives `NA`**, and widens the others'
  untrimmed padding to `NA`'s two characters, as R's `format()` does; the other labels' accuracy
  and cents are worked out without it, and under `scale_cut:` it takes no step. **`number_auto/1`
  writes it `"NA"` in its two `format()` ways**, as R does, and gives `nil` in the others, where
  R gives `NA` or breaks; its years test reads the numbers alone.
- **A label of `log/2` is a power, `{:power, base, exponent}`, a signed one,
  `{:signed, "-" | "+", power}`, a signed zero's `"0"`, or `nil`**, the base and exponent each
  written as R deparses a number (`Format` at 15 digits, the exponent read back from
  `format_log/2`'s text), so `10^ 0` is `"0"` and `6.91e+06` is `"6910000"`.
- **R's order of floating-point operations is kept**: rounding is `round(x / (accuracy /
  scale)) * (accuracy / scale)` and a step's scale `scale * (1 / threshold)`, since reordering
  moves labels (two and a half billion is `3B` under the short scale); `signif()` and `round()`
  are R's C (`Labels.Arithmetic`), a power of ten R's `R_pow_di()`, so `0.15` to one digit is
  `2e-01` where `format()` from the exact value writes `1e-01`.
- **A float is printed from its exact value, a half to even, never with `float_to_binary/2`'s
  `decimals:`**, which rounds a tie away from zero where R's `sprintf()` does not; `plain/1`
  rounds to 15 significant digits first, so `decimals:` only pads its labels.
- **Its options are NimbleOptions schemas, as every public option in Giggly is**, so a bad one
  raises `NimbleOptions.ValidationError` and each formatter's option docs are generated from its
  schema; its boundary lists NimbleOptions and nothing else. The package's transformations call
  `plain/1` for their default labels; a user hands the others to a scale's labels.
- **Only what R offers, and only where R's answer is sound**: no superseded name (`currency`,
  not `dollar`), and a `scale_cut:` list without a zero threshold is refused, the one shape where
  R misaligns its steps; `scientific/2` takes no `trim:`, which `label_scientific()` drops;
  `digits:` is 1 to 22, `format()`'s range; a log's base is a positive number other than 1, and
  an unsigned break at or below zero raises, where R writes `1^NaN` or `10^-Inf`.
