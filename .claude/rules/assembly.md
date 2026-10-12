---
paths:
  - "lib/giggly.ex"
  - "lib/giggly/assembly.ex"
  - "lib/giggly/group.ex"
  - "test/giggly_test.exs"
  - "test/giggly/group_test.exs"
---

# The assembly, and the functions that run a plot

`Giggly.Assembly` turns a `%Giggly.Plot{}` into what is drawn; the functions in `Giggly` take a
finished plot and run it there. Why a plot is run by functions outside `Plot`, and why the module
is called `Assembly`: design-log §4, the entry beginning "A plot is a value built by". Why the
stages run in this order: the entry beginning "The build order is fixed up front"; why `group` is
inferred where it is: the entry beginning "Two reserved frame columns"; how group ids are
numbered: the entry beginning "Group ids follow ggplot2's".

## Rules

- **A plot is run only from `Giggly`.** The root module holds the run functions (`layer_data/2`
  now; `to_svg` and the rest as they arrive), each taking a finished plot; `Plot` describes and
  never runs, and nothing outside Giggly calls `Assembly`. Arrows run root → `Assembly` → `Plot`,
  and nothing calls back up.
- **The stages run in one fixed order**, each pair a semantic chosen in §4: the facet assigns
  `panel` to the raw data → each layer's mapping is evaluated → `Group.add/1` writes `group` →
  transform scales → train position scales → map positions to numeric (not to the unit panel) →
  stat → `after_stat` → geom reparameterize (a bar to `xmin`/`xmax`/`ymin`/`ymax`) → position →
  reset and retrain position scales → freeze view scales → map positions again → train
  non-position scales → build guides → map non-position scales → `after_scale` → fixed values
  last. A stage arrives with its increment and goes where this order puts it.
- **Each stage is its own domain, and `Assembly`'s `deps:` names them.** A stage is handed what it
  needs; it never reaches back into the assembly or the plot.
- **The assembly's output is named for what it holds, when it holds more than one thing.** Today
  it is a list of layer frames; a struct arrives with the second field (the layout table), not
  ahead of it.
- **After evaluation a layer's frame speaks only the aesthetic vocabulary:** one column per
  mapped aesthetic, plus the columns the pipeline writes. The data's own names never appear.
- **`group` is written once, by `Group.add/1`, straight after evaluation** — before any scale maps
  a discrete position to numbers, after which it no longer looks discrete.
- **Discreteness is read from `DataFrame.dtypes/1`** (`:string`, `:boolean`, `:atom`), never by
  scanning values.
- **A group id depends only on the values,** never on the panel or the row's position, so stacking
  and dodging order agree across facets. The integer `panel` column is never discrete, so it needs
  no exclusion from the key.
- **Evaluated columns are in aesthetic-name order, and the group key follows column order.**
  Reordering the columns renumbers groups.

## How it works

`Giggly` lists `Giggly.DataFrame` only so its sub-boundaries may: a sub-boundary may list a
top-level boundary only when its parent does. It exports `Plot`; `Assembly` and `Group` are
internal.

`Assembly.run/1` reverses the plot's `reversed_layers` into drawing order and, for each layer,
lays its mapping over the plot's (the layer's column wins), sorts the pairs by aesthetic and
passes them to `DataFrame.select/2`, then `Group.add/1`. `layer_data/2` checks the index against
the plot's layer count before assembling, so a missing layer raises an `ArgumentError` naming it.

`Group.add/1` takes its key from the frame's types: a mapped `group` alone, or else every discrete
column. It zips the key columns into one tuple per row, sorts the distinct tuples with each
`nil` tagged to sort after every present value, numbers them from 1, and looks each row up. An
empty key gives every row `-1`. Values otherwise compare in Erlang term order, so strings sort by
bytes and structs such as dates by their fields rather than chronologically.
