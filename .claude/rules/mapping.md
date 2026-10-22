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
  (`resolve/1`, `columns/1`, `stage/1`, `dtype/2`, `category/1`, `evaluate/2`, `title/2`) and
  never match a tuple or a string themselves. Its boundary lists `Giggly.DataFrame` and
  `Giggly.AsCharacter`, which writes a factor's levels in its title; `Plot` lists it for the checks
  at the call and the assembly for evaluation and titles. **`Plot` calls
  only the checks**, never `evaluate/2` or `title/2`, which holds by review, as the assembly's calls
  into `Coord` and `Geom` do.
- **A plot holds each value resolved, and the mapping stays a map** (`Mapping.t()`, no struct): a
  column by its name as a string, a constant as `{:constant, term}`, an expression as its function
  and its resolved arguments. A string in a held mapping is always a column.
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
  boolean), and an after_stat inside another value. A refused argument refuses its expression.
- **Kinds of value are function clauses, not a protocol**: they differ in what they are, not in
  how they run. A head that acts on a whole column is a clause that sees the column, never a
  function applied per row.
- **`{:factor, [value]}` reads its value as discrete: its column is declared `:category`**, which
  the frame cannot read from values, so `dtype/2` says so and `category/1` gives the declaration
  the assembly makes when the column enters the evaluated frame. **`{:factor, [value], levels:
  [...], ordered: true}` gives its levels and marks it ordered**, R's `factor(x, levels = ...,
  ordered = TRUE)` (design-log §4, the entry beginning "`{:factor, [value], levels: [...]}`"),
  held with its options as written; the frame types the levels with the values, so levels of
  another type are refused when the plot is run. It is the whole of a mapping value, a factor's
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
- **An expression's type is the frame's**, decided when its column enters the evaluated frame, so
  it is known only when the plot is run; a check that needs it runs then (the axis's kind, a
  computed weight). `dtype/2` answers at the call for a column and a constant and says `:computed`
  for an expression.
- **A value's title is ggplot2's `make_labels()` read for Elixir**: a column's name; an
  expression's text, a capture of a `Kernel` operator written as the operator whether or not the
  compiler inlined it, an operand that is itself an operator's call in parentheses, any other
  capture as `inspect/1` names its function; an after_stat's its value's, as ggplot2 strips
  `after_stat()`, never a fallback; `:none` for an expression with a closure anywhere in it; and
  for a constant its aesthetic's canonical name, as a fallback (`{:fallback, name}`), which the
  assembly ranks below any layer's title.
