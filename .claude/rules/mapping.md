---
paths:
  - "lib/giggly/mapping.ex"
  - "test/giggly/mapping_test.exs"
---

# The mapping grammar

`Giggly.Mapping` is what a mapping maps each aesthetic to: a column, an expression computed in
each row, or a constant, and the title each gives its guide. Why the grammar is plain data, where
its wrappers go, and what was rejected: design-log §4, the entry beginning "A mapping value is a
column, an expression or a constant"; why an after_stat reads only documented variables: the
entry beginning "An after_stat reads its stat's computed variables".

## Rules

- **A value's shape is matched here and nowhere else.** `Plot` and the assembly ask this module
  (`resolve/1`, `columns/1`, `stage/1`, `dtype/2`, `category/2`, `check/2`, `evaluate/2`,
  `title/2`) and
  never match a tuple or a string themselves. Its boundary lists `Giggly.DataFrame` and
  `Giggly.AsCharacter`, which writes a factor's levels in its title; `Plot` lists it for the checks
  at the call and the assembly for evaluation and titles. **`Plot` calls
  only the checks**, never `evaluate/2` or `title/2`, which holds by review, as the assembly's calls
  into `Coord` and `Geom` do.
- **A plot holds each value resolved, and the mapping stays a map** (`Mapping.t()`, no struct): a
  column by its name as a string, a constant as `{:constant, term}`, an expression as its function
  and its resolved arguments, a function by name as its name and its resolved value, a reordering
  as `{:reorder, [value, by]}`, each resolved. A string in a held mapping is always a column.
- **An atom or a string is a column; nothing else is read as a name.** `true`, `false` and `nil`
  are atoms and name none, and `2.5` is a constant, never the column `"2.5"`.
- **A wrapper only where the type is ambiguous.** A number, a boolean, a date or a time is a
  constant written alone; a string or an atom constant needs `{:constant, term}`. A list holds only
  things to evaluate, so a constant's term is never one.
- **Refused at the call, each with a reason worded to follow "maps :x to …, but"**, which the
  caller raises with its function's name: `nil`, a list (kept free for an inline column), a
  function alone, a constant the frame would type `:term`, a tuple of an unknown head, an
  expression whose arguments are not a list, a function whose arity is not its arguments' count,
  a factor or an after_stat of other than one value, a factor's options other than a keyword list
  of `levels:` and `ordered:`, each once (levels a list of one or more values a column can hold,
  of one type, integers and floats being one, none `nil` and none twice by `==`; `ordered:` a
  boolean), an after_stat inside another value, an atom naming none of `:after_stat`,
  `:constant`, `:factor`, `:reorder` and the functions by name, the refusal listing them, a
  function by name given other than as many values as it takes, or a capture or a closure among
  them, and a reordering of other than two values, of a constant (R: "arguments must have same
  length"), a capture or a closure, a factor, an after_stat or another reordering, or as an
  expression's argument. A refused argument refuses its expression.
- **Kinds of value are function clauses, not a protocol**: they differ in what they are, not in
  how they run. A head that acts on a whole column is a clause that sees the column, never a
  function applied per row.
- **`{:factor, [value]}` reads its value as discrete: its column is declared `:category`**, which
  the frame cannot read from values, so `dtype/2` says so and `category/2` gives the declaration
  the assembly makes when the column enters the evaluated frame. **A column of the table that is
  a category keeps its declaration**, levels and all, and a factor of one keeps its levels and
  ordered flag but those it gives itself, as R's `factor()` of a factor does. **`{:factor,
  [value], levels: [...], ordered: true}` gives its levels and marks it ordered**, R's `factor(x,
  levels = ..., ordered = TRUE)` (design-log §4, the entry beginning "`{:factor, [value], levels:
  [...]}`"), held with its options as written; the frame types the levels with the values, so levels
  of another type are refused when the plot is run. It is the whole of a mapping value, a factor's
  own or an after_stat's, never an expression's argument, refused at the call, since R hands a
  function a factor's level codes. Its title is `factor()` around its value's text and its
  options as R writes the arguments, in the order given (`levels = c(8, 4, 6)`, `ordered =
  TRUE`).
- **`{:after_stat, [value]}` is evaluated against its stat's output, once the stat has run**:
  `stage/1` says `:after_stat`, and the assembly leaves it out of evaluation and grouping. Its
  names are the stat's computed variables, held as strings like a column's and compared with the
  output's atom names as strings (`dtype/2` and `evaluate/2` handed that output); which names a
  stat offers is `Plot`'s check at the call, `columns/1` naming them. It is the whole of a mapping
  value, never inside another, so it is refused in an expression, a factor or an after_stat;
  inside it, any value but another after_stat, a factor included.
- **A function by name, `{:log10, [value]}`, is computed by the frame** (design-log §4, the
  entries beginning "A mapping names a function only as a shortcut" and "A function by name's
  value"): the names and how many values each takes are `@functions`, `functions/0`, each one
  the list frame runs, which a test pins; `evaluate/2` hands the value to `DataFrame.mutate/2` as
  it is, the frame's expression, since its value is a column, a constant or another function by
  name. **`check/2` is the call's check against the table a layer draws**, which `Plot` runs on
  each value once its columns are found: a function by name the table's engine runs
  (`DataFrame.operations/1`), and given numbers where its value is a column of the table or a
  constant, an after_stat's columns being the stat's output, unknown at the call.
- **`{:reorder, [value, by]}` is R's `reorder()`: `value` read as discrete, as a factor reads it,
  its levels ordered by the mean of `by`** (design-log §4, the entries beginning "Ordering,
  viridis and `log10` by name" and "The frame's mean is R's"). `dtype/2` says `:category`,
  `evaluate/2` gives `value`'s values, and `category/2` computes the declaration through the
  frame: `by` mutated into the table, `value` put beside it as the category its factor would be
  (a table's category keeping its levels and ordered flag, so the reordering is ordered where it
  is), `summarise/3`'s `mean` of `by` for each, and only that summary read, its levels sorted by
  mean, minus infinity first, ties keeping their order and a missing mean (`nil`, NaN, or a level
  no row holds) last, as R's `order()` sorts its scores. Each value is a column or a function by
  name, so the engine computes all of it; it goes where a factor goes, a factor's own or an
  after_stat's value. **`check/2` refuses it where the engine has no `mean` and where `by` is a
  column that is not numbers**, booleans and dates among them, where R warns and orders nothing
  or averages them; R's `FUN` and `decreasing`, and a factor as `value`, wait for a caller.
- **An expression's type is the frame's**, decided when its column enters the evaluated frame, so
  it is known only when the plot is run; a check that needs it runs then (the axis's kind, a
  computed weight). `dtype/2` answers at the call for a column and a constant and says `:computed`
  for an expression.
- **A value's title is ggplot2's `make_labels()` read for Elixir**: a column's name; an
  expression's text, a capture of a `Kernel` operator written as the operator whether or not the
  compiler inlined it, an operand that is itself an operator's call in parentheses, any other
  capture as `inspect/1` names its function; a function by name as a call to it,
  `log10(carat)`; a reordering as R's call, `reorder(class, hwy)`; an after_stat's its value's,
  as ggplot2 strips `after_stat()`, never a fallback; `:none` for an expression with a closure
  anywhere in it; and
  for a constant its aesthetic's canonical name, as a fallback (`{:fallback, name}`), which the
  assembly ranks below any layer's title.
