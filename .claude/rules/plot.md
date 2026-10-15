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
read when the plot is created", "Points accept only what Phase 1 can draw", "A layer names its
stat and position" and "Each facet, coordinate system, geom, stat and position is a struct".

## Rules

- **A plot describes and runs nothing.** `Plot` builds the value; running it — assembling,
  inspecting, drawing — is the functions in `Giggly`. Its boundary lists `Giggly.Aesthetics`,
  `Giggly.DataFrame` and the five families whose kinds it builds (`Giggly.Coord`, `Giggly.Facet`,
  `Giggly.Geom`, `Giggly.Position`, `Giggly.Stat`), and exports nothing beyond `Plot`.
  **`GigglyCredo.Check.PlotRunsNothing` keeps those families' roots, the protocols that compute
  and draw, out of its files** — no call, no module passed as a value, no `import` — which
  boundary cannot, since a boundary always exports its root. It knows nothing about scales.
- **The API is `new/2`, the geom functions, the facet functions (`facet_wrap/3`) and the coordinate
  functions (`coord_radial/1`).** `computed_mapping/2` and the `layer_*` accessors exist for the
  assembly and are `@doc false`, and `Layer` is `@moduledoc false`; an API type names no hidden one
  (`aesthetic`, not `Aesthetics.name/0`). An example in the docs shows what a user sees, through
  `Giggly.layer_data/2` or the drawing `Giggly.to_svg/2` makes, never a layer's or a kind's struct.
- **A kind is named after ggplot2's ggproto class without its family prefix, and a class ggplot2
  keeps only as an alias is not a kind:** `geom_col/3` records `%Geom.Bar{}` with
  `%Stat.Identity{}` and `%Position.Stack{}`, as ggplot2's `GeomCol` is an empty `GeomBar`. A
  function takes ggplot2's function name, several may share a kind, and a refusal names the
  function that wrote the mapping (design-log §4, the entry beginning "A kind is named after").
- **A layer's mapping laid over the plot's is `computed_mapping/2`, and nowhere else.** Every
  reader of a layer's aesthetics — the checks here, the assembly's evaluation — asks for it, so
  the precedence (the layer's column wins) exists once.
- **A plot and its layers record their kinds as structs, the null and identity ones included**: each
  layer's geom, stat and position (`%Geom.Point{}`, `%Stat.Identity{}`, `%Position.Identity{}`), and
  the plot's facet and coordinate system (`%Facet.Null{}` and `%Coord.Cartesian{}` when nothing
  chooses others; `coord_radial/1` records `%Coord.Radial{}`). `Plot` builds them and reads a geom's
  facts to check a layer, but never computes or draws with one; the assembly reads a layer's with
  `layer_geom/1`, `layer_stat/1` and `layer_position/1`, so `Layer` stays private. A field holding a
  kind is typed `struct()`: a protocol's `t()` is any term, and the check refuses it. The theme is
  still a name, `theme: :gray`, until a user can set one; what a misspelt name does arrives with
  that option, and it must raise at the call.
- **A mistake raises from the call that wrote it.** Each function resolves the mapping it is
  given against the data and checks what the geom can use there, so a misspelt column or an
  unusable aesthetic is reported by the line that has it, never later when the plot is run. A
  missing column's message names the aesthetic, the reference as the caller wrote it, and the
  data's columns. This covers what the plot itself knows — names, and which aesthetics a geom
  takes and needs; whether a column's type suits an axis is the scales' question, answered when
  the plot is run. A facet's columns are resolved the same way, at the call, and none, or one named
  twice, is refused there; whether `nrow:` and `ncol:` hold the panels is the facet's question,
  since counting the panels is its computation, answered when the plot is run.
- **A layer is checked against the facts of the kind that reads its aesthetics first**: a point or
  column layer against its geom's (`Geom.Point`, `Geom.Bar`), a counting layer against its stat's
  (`Stat.Count`: `:x` needed, `:weight` taken, `:y` refused, since the count gives it). A weight's
  column must hold numbers, refused at the call, where R would fail inside the stat and draw
  nothing.
- **A geom function takes a mapping, a map, and options, a keyword list, either alone or both**
  (design-log §4, the entry beginning "The public pipe API lives in"): `geom_bar(plot,
  position: :dodge)` and `geom_bar(plot, %{x: :class}, position: :dodge)`. A position is chosen by
  an atom (`position: :stack | :dodge`) and recorded as its kind's struct; its parameters never
  become the geom's options (the entry beginning "A layer chooses its position by an atom").
- **A function's keyword options are validated by NimbleOptions at the call** (`facet_wrap/3`'s
  `nrow:`, `ncol:` and `scales:`; the bar functions' `position:`), so a misspelt option raises
  naming it, and a repeated one is refused by `Aesthetics.canonicalize/1`, run first. A deliberate default is
  recorded as a value (`scales: :fixed`). An option not given is recorded as
  `:none` in the kind's struct; a caller never writes "absent", so §7's question waits.
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
  repeat. NimbleOptions has no number type either: an option taking any number, such as `alpha:`,
  is `{:or, [:integer, :float]}`, or an integer is refused.
