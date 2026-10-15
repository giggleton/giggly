---
paths:
  - "lib/giggly/plot.ex"
  - "lib/giggly/plot/**"
  - "test/giggly/plot_test.exs"
---

# The plot and its API

`Giggly.Plot` is the public pipe API and the plot value it builds; `Giggly.Plot.Layer` is one
layer of that value. Why the API is shaped this way, and what was rejected: design-log §4, the
entries beginning "The public pipe API lives in", "A plot is a value built by", "The table is
read when the plot is created", "Points accept only what Phase 1 can draw" and "A layer names its
stat and position".

## Rules

- **A plot describes and runs nothing.** `Plot` builds the value; running it — assembling,
  inspecting, drawing — is the functions in `Giggly`. Its boundary lists `Giggly.Aesthetics` and
  `Giggly.DataFrame`, and exports nothing beyond `Plot`. It knows nothing about scales.
- **The API is `new/2` and the geom functions.** `computed_mapping/2` and the `layer_*`
  accessors exist for the assembly and are `@doc false`, and `Layer` is `@moduledoc false`; an
  API type names no hidden one (`aesthetic`, not `Aesthetics.name/0`). An example in the docs
  shows what a user sees, through `Giggly.layer_data/2`, never a layer struct.
- **A layer's mapping laid over the plot's is `computed_mapping/2`, and nowhere else.** Every
  reader of a layer's aesthetics — the checks here, the assembly's evaluation — asks for it, so
  the precedence (the layer's column wins) exists once.
- **A layer records its geom, stat and position by name, the identity included**, and the
  assembly reads them with `layer_geom/1`, `layer_stat/1` and `layer_position/1`, so `Layer` stays
  private and `Plot` names no module of `Giggly.Geom`, `Giggly.Stat` or `Giggly.Position`. The
  plot records its facet, coordinate system and theme the same way, `facet: :null`,
  `coord: :cartesian` and `theme: :gray` when nothing chooses others. What a misspelt name does arrives with the first
  option that lets a caller choose one: it must raise at the call, which will need the valid names.
  **This changes with `facet_wrap`:** the facet, coordinate system, geom, stat and position become
  structs of their kinds, which `Plot` builds and reads the facts of but never computes or draws
  with (design-log §4, the entry beginning "Each facet, coordinate system, geom, stat and position
  will be a struct"); the theme stays a name until a user can set one.
- **A mistake raises from the call that wrote it.** Each function resolves the mapping it is
  given against the data and checks what the geom can use there, so a misspelt column or an
  unusable aesthetic is reported by the line that has it, never later when the plot is run. A
  missing column's message names the aesthetic, the reference as the caller wrote it, and the
  data's columns. This covers what the plot itself knows — names, and which aesthetics a geom
  takes and needs; whether a column's type suits an axis is the scales' question, answered when
  the plot is run.
- **The table is read once, by `new/2`.** The plot holds a `Giggly.DataFrame`, so nothing past
  this API sees a `Table.Reader`.
- **The plot holds what was resolved.** Mapping keys are canonical (`Aesthetics.canonicalize/1`
  runs on every mapping as it enters), and mapping values are the data's string column names,
  never the atoms the caller wrote.
- **A column reference is an atom or a string,** compared with the data's names as a string.
  Nothing else is read as a name: `2.5` is not the column `"2.5"`.
- **The plot's mapping is checked against each layer as the layer is added,** together with the
  layer's own: an aesthetic either gives that the geom cannot use raises, and so does a required
  one neither gives. With one geom this is exact; what a second geom makes legal is open
  (design-log §7).
- **A geom accepts only what the pipeline can draw.** An aesthetic joins a geom's accepted list
  with the scale that maps it, so a mapping never silently does nothing.
- **When keyword options arrive, `Aesthetics.canonicalize/1` runs before NimbleOptions validates
  them.** NimbleOptions keeps only the first of a repeated key and checks only that one, so
  validating first would let `alpha: 0.4, alpha: "x"` through; `canonicalize/1` refuses the
  repeat.

## How it works

`new/2` reads the data with `DataFrame.from_table/1` and resolves the plot's mapping;
`geom_point/2` resolves the layer's, checks the aesthetics it adds and those it inherits against
what points accept, checks that `:x` and `:y` are mapped by one mapping or the other, and puts a
`%Layer{}` with the identity stat and position at the front of `reversed_layers`, so adding a layer never walks the list and the
assembly reverses them into drawing order. Resolving a mapping canonicalizes its keys and
looks each value up, as a string, in `DataFrame.names/1`; no atom is ever made from a column name.
