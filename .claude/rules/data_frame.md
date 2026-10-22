---
paths:
  - "lib/giggly/data_frame.ex"
  - "lib/giggly/data_frame/**"
  - "test/giggly/data_frame_test.exs"
---

# The data frame

`Giggly.DataFrame` is the table every pipeline stage reads and writes. Why it is a behaviour with
one list implementation, why user column names are strings, and what was rejected: design-log §4,
the entries beginning "The layer-data currency", "Callers reach a frame only through", "User
column names become strings", "Column types belong to the frame" and "Every boundary is strict".

## Rules

- **Callers use `Giggly.DataFrame`, never an implementation.** It is its own boundary exporting
  only its root, so a call to `Giggly.DataFrame.Lists` or a `%Lists{}` outside it fails the build.
  A new operation is a `@callback` plus a function here that dispatches on the frame's struct.
- **Its readers are API, and the rest is not.** `Giggly.layer_data/2` returns a frame, so
  `names/1`, `row_count/1`, `dtypes/1` and `pull/2` are documented with doctests, and `t` is
  `@opaque`: a user reads a frame through them. `from_table/1`, `new/1`, `select/2`, `put/3`,
  `put/4`, `split/2`, `slice/2`, `filter/2`, `mutate/2`, `summarise/3` and the callbacks are the
  pipeline's, `@doc false`, and `Lists` is `@moduledoc false`; offering a user another operation
  is a decision (CLAUDE.md, Conventions).
- **The frame owns the `table` library.** Its `deps:` is `Table` alone, which the root lists too,
  as boundary lets a sub-boundary list only what its parent does, and no other domain lists it
  (`.claude/rules/dependencies.md`). A domain that uses the frame lists `Giggly.DataFrame`, its
  sibling under the umbrella.
- **User column names are strings; every column the pipeline writes is an atom.** `from_table/1`
  converts them and refuses two that become the same string. Never turn a string name into an
  atom: that creates atoms from caller input, and it would let a user column pass for an aesthetic.
- **No operation takes an Elixir function.** The set stays relational so an engine could run it.
  Code that needs arbitrary Elixir pulls a column with `pull/2` and puts the result back with
  `put/3`, which a stat does only to a table it has summarised (`stat.md`).
- **What `filter/2` and `mutate/2` compute, and what an aggregate reads, is an expression: plain
  data in the mapping's grammar with an operation named by an atom** (design-log §4, the entry
  beginning "The frame's operations share one expression grammar"): a column by its name, a
  constant alone or as `{:constant, term}`, an operation `{name, [expression]}`. Values follow
  Explorer's semantics, as types do: a missing value passes through an operation, a filter keeps
  only the rows whose value is true, `and` is SQL's three-valued and. A column named alone keeps
  its type, a constant's is worked out from its value, an operation's is what it computes. An
  expression outside the vocabulary, or an operation given a column of the wrong type, raises
  `FunctionClauseError`; the mapping's expressions by name will reuse the grammar.
- **An operation arrives with its first caller**, shaped by what that caller needs — split and
  recombine, the relational operations; `slice/2`, vctrs' `vec_slice()`, takes rows by index, in
  any order, repeated or left out, as a line's geom reorders and drops rows, munching repeats
  them, and the facet repeats a table across the panels; `summarise/3`, the first group-by
  aggregate, with the stats that count; `filter/2`, `mutate/2`, the `is_finite` and `and`
  operations and the `n_distinct` and `first` aggregates, with counting's rows, weights and carried
  columns. Not designed ahead.
- **`summarise/3`'s aggregates are operations over one column, `{name, [column]}`**:
  `n_distinct`, a missing value counting as one, as R's `vec_unique_count()` counts; `first`, in
  row order, of the column's type; and a sum. **A sum's spec says how it adds** (design-log §4, the
  entry beginning "The frame's first group-by aggregate"): `summation: :compensated`, the
  default, as R's `sum()` adds in extended precision, or `:plain`, in row order, as `rowsum()`;
  `missing: :propagate`, the default, or `:skip`, a missing value being `nil` or a non-finite
  float. Its rows are sorted by the `by` columns, a missing value last, each keeping its type. An
  engine implementing the frame implements both summations, or refuses the one it cannot.
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
  a column given as `{name, values, :category}` or put with `:category`, its values typed and cast
  as any column's first, a `:term`'s refused. It is Explorer's name for a categorical column; what
  it means (discrete) is the plot's. `select/2`, `split/2`, `slice/2`, `filter/2`, a column
  `mutate/2` names alone, `summarise/3`'s `by` columns and its `first` carry it; `put/3` works a
  type out afresh.
- **`:term` is the one type whose values are not checked against each other.** It holds whatever
  has no type of its own (maps, lists, `Decimal`…), so a column the plot never uses cannot refuse
  the table. When something needs one of those checked or plotted, it gets a named type of its own.
- **`nil` in a column is a missing value.** Values are stored as given, but for an integer in a
  `:float` column, which becomes a float, as Explorer casts a mix of the two: `4` and `4.0` are then
  one value to every reader that compares them (a facet's panels, the groups, a scale's levels), as
  R's numbers are; the frame converts nothing else. `nil` is data, not the `:none` option sentinel.
