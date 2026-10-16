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
  `split/2`, `slice/2` and the callbacks are the pipeline's, `@doc false`, and `Lists` is
  `@moduledoc false`; offering a user another operation is a decision (CLAUDE.md, Conventions).
- **The frame owns the `table` library.** Its `deps:` is `Table` alone, which the root lists too,
  as boundary lets a sub-boundary list only what its parent does, and no other domain lists it
  (`.claude/rules/dependencies.md`). A domain that uses the frame lists `Giggly.DataFrame`, its
  sibling under the umbrella.
- **User column names are strings; every column the pipeline writes is an atom.** `from_table/1`
  converts them and refuses two that become the same string. Never turn a string name into an
  atom: that creates atoms from caller input, and it would let a user column pass for an aesthetic.
- **No operation takes an Elixir function.** The set stays relational so an engine could run it.
  Code that needs arbitrary Elixir pulls a column with `pull/2` and puts the result back with
  `put/3`.
- **An operation arrives with its first caller**, shaped by what that caller needs — split and
  recombine, the relational operations; `slice/2`, vctrs' `vec_slice()`, takes rows by index, in
  any order, repeated or left out, as a line's geom reorders and drops rows and munching repeats
  them. Not designed ahead.
- **The frame knows nothing about plots.** The `panel` and `group` columns belong to the code that
  writes them (the facet, `add_group`), not to the frame.
- **A frame that exists is well formed**: no name twice, every column `row_count` long, every
  column one type. Data from outside is checked by `from_table/1`, which raises an `ArgumentError`
  naming the problem; beneath it the implementation's guards refuse a malformed call with a
  `FunctionClauseError`. A column mixing two types raises `ArgumentError` on either path, since
  finding the mix means reading the values, which a guard cannot do.
- **The frame owns its columns' types; callers ask `dtypes/1`.** A type is worked out once, when a
  column enters (`new/1`, `put/3`; `select/2` carries it), by Explorer's rules for a series built
  from a list, written out in the moduledoc. What a type *means* to a plot (discrete or not, which
  scale) is the caller's, never the frame's.
- **`:term` is the one type whose values are not checked against each other.** It holds whatever
  has no type of its own (maps, lists, `Decimal`…), so a column the plot never uses cannot refuse
  the table. When something needs one of those checked or plotted, it gets a named type of its own.
- **`nil` in a column is a missing value.** Values are stored as given and never converted; the
  frame classifies them by type and nothing more. `nil` is data, not the `:none` option sentinel.
