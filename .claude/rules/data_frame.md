---
paths:
  - "lib/giggly/data_frame.ex"
  - "lib/giggly/data_frame/**"
  - "test/giggly/data_frame_test.exs"
---

# The data frame

`Giggly.DataFrame` is the table every pipeline stage reads and writes. Why it is a behaviour with
one list implementation, why user column names are strings, and what was rejected: design-log §4,
the entries beginning "The layer-data currency", "Callers reach a frame only through" and "User
column names become strings".

## Rules

- **Callers use `Giggly.DataFrame`, never an implementation.** It is its own boundary exporting
  only its root, so a call to `Giggly.DataFrame.Lists` or a `%Lists{}` outside it fails the build.
  A new operation is a `@callback` plus a function here that dispatches on the frame's struct.
- **User column names are strings; every column the pipeline writes is an atom.** `from_table/1`
  converts them and refuses two that become the same string. Never turn a string name into an
  atom: that creates atoms from caller input, and it would let a user column pass for an aesthetic.
- **No operation takes an Elixir function.** The set stays relational so an engine could run it.
  Code that needs arbitrary Elixir pulls a column with `pull/2` and puts the result back with
  `put/3`.
- **An operation arrives with its first caller**, shaped by what that caller needs — split and
  recombine, column types, the relational operations. Not designed ahead.
- **The frame knows nothing about plots.** The `panel` and `group` columns belong to the code that
  writes them (the facet, `add_group`), not to the frame.
- **A frame that exists is well formed**: no name twice, every column `row_count` long. Data from
  outside is checked by `from_table/1`, which raises an `ArgumentError` naming the problem; beneath
  it the implementation's guards refuse a malformed call with a `FunctionClauseError`.
- **`nil` in a column is a missing value.** Values are stored as given and interpreted by whoever
  reads them. This is data, not the `:none` option sentinel.

## How it works

`from_table/1` is the only caller of the `table` package, a thin adapter over `new/1`, so it can
sit outside a strict core when one is carved. It takes the column order from
`Table.Reader.init/1`'s metadata, because `Table.to_columns/1` returns a map; reads every column
into a list, lazy sources included, so input is read once; and checks the lengths itself, because
`table` checks none and its row reader stops at the shortest column.

`Lists` keeps a map from name to values, the names newest first (reversed by `names/1`, so gaining
a column never walks the list), and the row count, so a `select/2` that keeps no column keeps the
rows. Every column a frame gains — through `new/1`,
`select/2`, or `put/3` adding a name — passes one guarded private clause, which refuses a name
already present or a length other than the row count; `put/3` replacing a column has its own length
guard.
