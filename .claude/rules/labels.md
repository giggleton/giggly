---
paths:
  - "lib/scales/labels.ex"
  - "lib/scales/labels/**"
  - "test/scales/labels_test.exs"
  - "test/scales/labels_date_test.exs"
  - "test/scales/labels_format_test.exs"
  - "test/scales/labels_arithmetic_test.exs"
  - "test/scales/labels_text_test.exs"
  - "test/scales/labels_width_test.exs"
  - "test/scales/fixtures/r_widths_4.6.1.csv"
---

# Labels

`Scales.Labels` writes a scale's labels as scales 1.4.0's `label_number()`, `label_comma()`,
`label_percent()`, `label_currency()`, `label_scientific()`, `label_number_auto()`,
`label_log()`, `format_log()`, `label_bytes()`, `label_ordinal()`, `label_pvalue()`,
`label_timespan()`, `label_date()`, `label_date_short()`, `label_time()`, `label_wrap()` and
`label_dictionary()` do,
`Scales.Labels.Format` writing their numbers as R's `format()` does,
`Scales.Labels.Arithmetic` rounding them as R does, `Scales.Labels.DateFormat` writing dates
as R's `format()` does in a zone, `Scales.Labels.Wrap` breaking text as R's `strwrap()` does and
`Scales.Labels.Width` counting its characters as R does; and plainly, the
Elixir way (`plain/1`, `scales.md`), the default labels of a number's transformations.
Why list functions: design-log §4, the entry beginning "`labels:` takes a list"; why these
names and options: the entry beginning "`Scales.Labels`'s"; why `format()` is ported whole: the
entry beginning "R's `format()` for numbers"; why a missing break's label is `nil`: the entry
beginning "A missing break's label"; why a power is a value: the entries beginning "`log/2`
returns powers" and "A signed power"; why the new labellers take the options they do and
refuse what they refuse: the entries beginning "`scientific/2` takes", "`digits:` is an
integer", "`log/2` refuses", "`format_log/2` takes", "`bytes/2`'s `units:`", "`ordinal/2`
takes", "`pvalue/2`'s accuracy" and "`timespan/2` takes"; why the departures from R's text:
"Plain bytes under binary units" and "`ordinal/2`'s rules are matched"; why the date
labellers write and take what they do: "The date labellers take", "The date labellers write",
"`date/2`'s and `time/2`'s `format:`" and "`date_short/2` takes its parts"; why `wrap/2`
breaks, counts and takes what it does: "Wrapping a strip's label", "`wrap/2` counts a character"
and "`wrap/2` takes"; why `dictionary/2` matches and takes what it does: "`dictionary/2` matches".

## Rules

- **Every label of `number/2`, `comma/2`, `percent/2`, `currency/2`, `scientific/2`,
  `number_auto/1`, `log/2`, `format_log/2`, `bytes/2`, `ordinal/2`, `pvalue/2` and `timespan/2`
  is R's to the character, and the tests pin R's own output**, each beside the R call that gave
  it (`giggly-r:ggplot2-4.0.3`). A label that differs from R's is a bug, except where the module
  comments say this differs, and say why: plain bytes `B` under binary units, and an ordinal's
  rules matched against its digits, the tests pinning R's rows with those changed. All of 11,941
  random cases of `scientific/2` to `format_log/2` matched R, 1,728 of the first four near the
  largest double, and 24,000 of the last four, every option against missing, infinite and
  overflowing breaks.
- **Every label of `date/2`, `date_short/2` and `time/2` is R's to the character**, the tests
  pinning R's rows beside their calls (`giggly-r:ggplot2-4.0.3-hms`), but where the module
  comments say this differs: a `NaiveDateTime` and a `Time` are never shifted into `tz:`;
  `date_short/2`'s `leading:` and `sep:` are text, applied to each part on its own; and `%s`
  outside UTC is the instant's Unix time, where R's counts the wall clock. A `Date` is written at
  midnight UTC, a year unpadded, `%%Y` a literal `%Y`; what changed is read on each break's own
  clock and written in `tz:`. All of 12,000 random cases matched R, every kind, seven zones and
  their changes of offset, missing and repeated breaks, and every option, the departures checked
  against R's own rule.
- **Every label of `wrap/2` and `dictionary/2` is R's to the character**, the tests pinning R's
  rows beside their calls, but where the module comments say this differs: `wrap/2` takes strings
  and `nil` alone, which R writes with `as.character()` first; `dictionary/2` matches a value by
  `Scales.DataRange.key/1`, where R matches its text, takes `""` as a key, which R refuses, and
  raises on an unmatched value that is not a string, which R hands back as text. **A character is
  as wide as R 4.6.1 counts it under `en_US.UTF-8`**, `nchar(type = "w")` measured for every
  code point and held in `Labels.Width`, which matched R on all of them; its test pins both
  ends of every run, and either side, against R's runs as R wrote them
  (`test/scales/fixtures/r_widths_4.6.1.csv`), so a row that stops matching is a bug, and the
  table and the fixture move only by measuring R again. `wrap/2` is modelled from
  `strwrap()`'s documentation and R's output, never ported from R's source; all of 16,000 random
  labels, of every width, whitespace, sentence end, wide, combining and zero-width character,
  matched R.
- **A break `scale:` takes past the largest double is R's `Inf`**, never a raise: Erlang refuses
  the arithmetic R takes to an infinity, so each `*`, `/` and `-` on a break that can pass it is
  `Labels.Arithmetic`'s, the infinity an atom. Rounded past it, the label is `Inf`, its sign
  styled, its prefix and suffix dropped, as R's `number()` writes it; scaled past it only,
  `Inf` inside them; it takes no step and no cents, and no part in the others' accuracy, nor
  does a break whose quotient by the accuracy tried passes it, where R fails beside multiples
  alone (design-log §4, the entry beginning "A break whose quotient").
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
  an unsigned break at or below zero raises, where R writes `1^NaN` or `10^-Inf`; `ordinal/2`
  takes no `scale:`, whose suffix R reads from the unscaled break, and raises on a break no rule
  matches, which R gives another break's suffix; `pvalue/2`'s accuracy is at most 0.5, past which
  R's labels say what is false, and `add_p: true` beside `prefix:` raises, where R ignores it;
  `wrap/2`'s `width:` is a positive integer, where R's fractions, zero and below and `Inf` say
  nothing a whole width does not; `dictionary/2` refuses a key `nil`, which never matches, two
  keys naming one value, which R settles silently, and a `nomatch:` but a string or `nil`, which
  R coerces or recycles.
- **An option R's labeller fixes or refuses is not taken**: `bytes/2` has no `suffix:` or
  `scale_cut:`, `ordinal/2` no `accuracy:` or `decimal_mark:`, `timespan/2` no `scale_cut:`, as
  R's `...` collides with its own argument there or shows nothing. The date labellers take no
  `locale:`, which R needs stringi for, and refuse a format R recycles or reads as its default
  (a list, `""`), a zone their database cannot read, and a break of a kind they do not write.
