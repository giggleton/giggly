---
paths:
  - "lib/giggly/data_frame.ex"
  - "lib/giggly/data_frame/**"
  - "lib/giggly/factor.ex"
  - "test/giggly/data_frame_test.exs"
  - "test/giggly/factor_test.exs"
---

# The data frame

`Giggly.DataFrame` is the table every pipeline stage reads and writes. Why it is a behaviour with
one list implementation, why user column names are strings, and what was rejected: design-log §4,
the entries beginning "The layer-data currency", "Callers reach a frame only through", "User
column names become strings", "Column types belong to the frame" and "Every boundary is strict".

## Rules

- **Callers use `Giggly.DataFrame`, never an implementation.** It is its own boundary exporting
  its root and `Arithmetic` alone, so a call to `Giggly.DataFrame.Lists` or a `%Lists{}` outside
  it fails the build. A new operation is a `@callback` plus a function here that dispatches on the
  frame's struct.
- **R's arithmetic on the frame's doubles is `Giggly.DataFrame.Arithmetic`** (design-log §4, the
  entry beginning "A missing value in a sum is R's"): the frame owns `nil` (R's `NA`), `:nan`,
  `:infinity` and `:neg_infinity`, so it owns how they add, subtract, multiply, divide, compare
  and take a magnitude, a maximum, a sum, running sums or a mean, as IEEE arithmetic and R's
  `pmin()`, `pmax()`, `max()`, `sum()`, `cumsum()`, `mean()` and `<` do, a missing value and NaN
  where both meet resolved as R resolves them, and **a result past the largest double an
  infinity of its sign**, as IEEE rounds it, where Erlang raises. **The order of the frame's
  doubles has one home, `sort_key/1`**, R's `order()`: minus infinity, the numbers, infinity, a
  missing value last; every family that sorts or compares them reads it, never a key of its own. **A sum, running sums and a mean
  are R's digit for digit** (`sum/2`, which `summarise/3`'s sum calls, `cumulative_sum/1` and
  `mean/1`; design-log §4, the entries beginning "The frame's sums are R's" and "The frame's mean
  is R's"): every step R takes in its long double, a mean's correction pass and its division of
  each value where the sum is past the largest double included, taken in
  `Giggly.DataFrame.LongDouble`, which holds a value exactly and rounds each result to 64 bits, as
  the x87 does, and only `Arithmetic` calls; so a running sum may pass the largest double and come
  back, and a sum left past it is an infinity, as R's `sum()` reads it, a running sum one where
  it rounds to one, as `cumsum()` rounds it. A stat's shares, densities
  and bins, stacking's heights, dodging's widths and a bar's sides go through it, never Elixir's
  arithmetic, which has no infinity.
- **Its readers are API, and the rest is not.** `Giggly.layer_data/2` returns a frame, so
  `names/1`, `row_count/1`, `dtypes/1` and `pull/2` are documented with doctests, and `t` is
  `@opaque`: a user reads a frame through them. `from_table/1`, `new/1`, `select/2`, `put/3`,
  `put/4`, `category/2`, `operations/1`, `split/2`, `slice/2`, `filter/2`, `mutate/2`,
  `summarise/3`, `join/3` and the callbacks are the pipeline's, `@doc false`, and `Lists` is
  `@moduledoc false`; offering a
  user another operation is a decision (CLAUDE.md, Conventions).
- **The frame owns the `table` library.** Its `deps:` is `Table` and `Giggly.Factor`, `Table`
  listed by the root too, as boundary lets a sub-boundary list only what its parent does, and by
  no other domain (`.claude/rules/dependencies.md`). A domain that uses the frame lists
  `Giggly.DataFrame`, its sibling under the umbrella.
- **User column names are strings; every column the pipeline writes is an atom.** `from_table/1`
  converts them and refuses two that become the same string. Never turn a string name into an
  atom: that creates atoms from caller input, and it would let a user column pass for an aesthetic.
- **No operation takes an Elixir function.** The set stays relational so an engine could run it.
  Code that needs arbitrary Elixir pulls a column with `pull/2` and puts the result back with
  `put/3`, which a stat does only to a table it has summarised (`stat.md`).
- **What `filter/2` and `mutate/2` compute, and what an aggregate reads, is an expression: plain
  data in the mapping's grammar with an operation named by an atom** (design-log §4, the entry
  beginning "The frame's operations share one expression grammar"): a column by its name, a
  constant alone or as `{:constant, term}`, an operation `{name, [expression]}`, or `{name,
  [expression], options}` for parameters that are not row values (`cut`'s `breaks:` and
  `closed:`, R's `cut(include.lowest = TRUE)`, numbering each value's interval from 1). Values
  follow Explorer's semantics, as types do: a missing value passes through an operation, a filter
  keeps only the rows whose value is true, `and` and `or` are SQL's three-valued and and or, and
  `<` and `>` put NaN above every number, both infinities included; `log10` is R's `log10()`,
  zero's minus infinity and a negative number's NaN, a float, by `:math.log10`, which matches
  R's to the last bit where a division of natural logarithms does not. A column named alone
  keeps its type, a constant's is worked out from its value, an operation's is what it computes. An
  expression outside the vocabulary, or an operation given a column of the wrong type, rows or
  none, raises `FunctionClauseError`. **An implementation names the operations it runs**
  (`operations/1`), `summarise/3`'s aggregates among them, the list frame every one, a test
  pinning the list, so a caller can refuse what an engine cannot run before running it; a
  mapping's function by name is an expression in this grammar, and its reordering needs `mean`.
- **An operation arrives with its first caller**, shaped by what that caller needs — split and
  recombine, the relational operations; `slice/2`, vctrs' `vec_slice()`, takes rows by index, in
  any order, repeated or left out, as a line's geom reorders and drops rows, munching repeats
  them, and the facet repeats a table across the panels; `summarise/3`, the first group-by
  aggregate, with the stats that count; `filter/2`, `mutate/2`, the `is_finite` and `and`
  operations and the `n_distinct` and `first` aggregates, with counting's rows, weights and carried
  columns; `cut`, with binning's bins; `log10` and `operations/1`, with a mapping's functions by
  name; `join/3`, the `or`, `not`, `<` and `>` operations and the
  `quantile`, `count`, `min`, `max` and `list` aggregates, with the box plot's fences, outliers
  and whiskers; the `mean` aggregate, with a mapping's reordering. Not designed ahead.
- **`join/3` is a left join on equal keys, as Explorer joins**: a missing key matches nothing,
  the key columns must be of one type in both frames, and a column besides them in both is
  refused, never suffixed.
- **`summarise/3`'s aggregates are operations over one column, `{name, [column]}`**:
  `n_distinct`, a missing value counting as one, as R's `vec_unique_count()` counts; `first`, in
  row order, of the column's type; `list`, the group's values in row order, missing ones kept, of
  the type `{:list, type}`; `count`, `min`, `max` and `quantile` (`probability:`, R's type 7,
  worked in R's order, `(1 - h) * lower + h * higher`, which a test pins where the textbook order
  differs), each leaving a missing value (`nil` or NaN) out, as R's statistics call them, and
  missing, or 0, for a group of none; `mean`, R's `mean()`, a float, missing wherever a `nil`
  is, else NaN where a NaN is or both infinities meet; and a sum. **A sum's spec says how it
  adds** (design-log §4, the entry beginning "The frame's first group-by aggregate"):
  `summation: :extended`, the default, as R's `sum()` adds in extended precision, or `:plain`,
  in row order, as `rowsum()`;
  `missing: :propagate`, the default, or `:skip`, a missing value being `nil` or NaN, as R's
  `is.na()` reads one, the first met kept where it propagates, and an infinity no missing value but
  added as IEEE adds one, so a sum meeting both infinities is NaN. Its rows are sorted by the
  `by` columns, a missing value last, each keeping its type. An engine implementing the frame
  implements both summations, or refuses the one it cannot.
- **The frame knows nothing about plots.** The `panel` and `group` columns belong to the code that
  writes them (the facet, `add_group`), not to the frame.
- **A frame that exists is well formed**: no name twice, every column `row_count` long, every
  column one type. Data from outside is checked by `from_table/1`, which raises an `ArgumentError`
  naming the problem; beneath it the implementation's guards refuse a malformed call with a
  `FunctionClauseError`. A column mixing two types raises `ArgumentError` on either path, since
  finding the mix means reading the values, which a guard cannot do.
- **The frame owns its columns' types; callers ask `dtypes/1`.** A type is worked out once, when a
  column enters (`new/1`, `put/3`, `put/4`; `select/2` carries it), by Explorer's rules for a
  series built from a list, written out in the moduledoc; `mutate/2` types a column by its
  expression. What a type *means* to a plot (discrete
  or not, which scale) is the caller's, never the frame's.
- **`:category` is the one type never worked out from values: `new/1` and `put/4` are told it**,
  a column given as `{name, values, :category}` or `{name, values, {:category, levels: levels,
  ordered: ordered}}`, or put with either, its values typed and cast as any column's first, a
  `:term`'s refused. It is Explorer's name for a categorical column; what it means (discrete) is
  the plot's. **A category has levels and may be ordered** (design-log §4, the entries beginning
  "A table's column carries its levels" and "A factor carries R's `ordered` flag"): levels given
  are typed and cast with the values, refused if they hold `nil`, repeat a value (`4` and `4.0`)
  or are of another type; else they are its distinct values in order, as R's `factor()` orders
  them (numbers by value, minus infinity first and NaN last, dates and times by time, the rest in
  term order); a value not among them is `nil`, and each value is its level's own term, `-0.0`
  held as `0.0`. The type holds them, so `select/2`, `split/2`, `slice/2`, `filter/2`, a column
  `mutate/2` names alone, `join/3`, `summarise/3`'s `by` columns and its `first` carry them;
  `dtypes/1` reports `:category`, `category/2` the declaration `put/4` would make again, and
  `put/3` works a type out afresh. **A table's column given as a `Giggly.Factor` is read as a
  category with its levels and ordered flag** (`from_table/1`), refused as one declared so is.
- **`Giggly.Factor` is a column type of its own boundary, API**: `new/2` holds a column's values,
  its levels or `:default` and its ordered flag, its options checked by NimbleOptions, which its
  boundary lists alone; it checks nothing of the values, which the frame types when it reads the
  table. It enumerates as its values, so `Table.Reader`, Explorer and Kino read the column as
  they are; the frame and `Giggly.Datasets` list it.
- **`:term` is the one type whose values are not checked against each other.** It holds whatever
  has no type of its own (maps, tuples, `Decimal`…), so a column the plot never uses cannot refuse
  the table. When something needs one of those checked or plotted, it gets a named type of its own,
  as lists got `{:list, type}` (design-log §4, the entry beginning "A box's outliers are a list
  column"): typed by Explorer's rule, the values of all of a column's lists together, so lists
  whose values mix two types are refused, and a category holds none.
- **`nil` in a column is a missing value.** Values are stored as given, but for an integer in a
  `:float` column, which becomes a float, as Explorer casts a mix of the two: `4` and `4.0` are then
  one value to every reader that compares them (a facet's panels, the groups, a scale's levels), as
  R's numbers are; the frame converts nothing else. `nil` is data, not the `:none` option sentinel.
