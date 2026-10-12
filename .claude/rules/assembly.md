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
  `panel` to the raw data → each layer's mapping is evaluated → `Group.add/2` writes `group` →
  transform scales → train position scales → map positions to numeric (not to the unit panel) →
  stat → `after_stat` → geom reparameterize (a bar to `xmin`/`xmax`/`ymin`/`ymax`) → position →
  reset and retrain position scales → freeze view scales → map positions again → train
  non-position scales → build guides → map non-position scales → `after_scale` → fixed values
  last. A stage arrives with its increment and goes where this order puts it.
- **Each stage is its own domain, and `Assembly`'s `deps:` names them.** A stage is handed what it
  needs; it never reaches back into the assembly or the plot.
- **The assembly's output is `%Giggly.Assembly{}`, and gains a field with the stage that fills
  it:** the layer frames, the layout table, and the trained x and y scales keyed by scale id.
- **Scales are trained after grouping, on every layer's columns in an axis's family, and those
  columns are then mapped to positions.** Which columns belong to an axis is `Aesthetics.family/1`'s
  answer, never a name compared with `:x`.
- **One scale per axis until free scales.** Each axis's scale id is read from the layout, and the
  assembly matches exactly one; routing rows to several arrives with `facet_wrap`'s free scales,
  where that match fails loudly until it does.
- **After evaluation a layer's frame speaks only the aesthetic vocabulary:** one column per
  mapped aesthetic, plus the columns the pipeline writes. The data's own names never appear.
- **`group` is written once, by `Group.add/2`, straight after evaluation** — before any scale maps
  a discrete position to numbers, after which it no longer looks discrete.
- **The assembly gives grouping its order.** `Group.add/2` numbers values by the key it is handed;
  the assembly hands it `Scale.level_key/1`, the order a discrete scale gives its levels, so group
  ids follow axis and legend order while grouping names nothing about scales. When level order
  can be configured, the assembly hands over the configured order.
- **Whether a column suits an axis is checked here, when the plot is run.** Before training, every
  column on an axis must be a type `Scale.kind/1` can place and all of one kind; a refusal names
  the layer by index, the aesthetic, the column as the data names it, and its type. The plot
  checks only what it knows (names and which aesthetics a geom takes).
- **Discreteness is read from `DataFrame.dtypes/1`** (`:string`, `:boolean`, `:atom`), never by
  scanning values.
- **A group id depends only on the values,** never on the panel or the row's position, so stacking
  and dodging order agree across facets. The integer `panel` column is never discrete, so it needs
  no exclusion from the key.
- **Evaluated columns are the aesthetics in name order, then `panel`, then `group`** (ggplot2's
  order), and the group key follows column order: reordering the aesthetics renumbers groups.

## How it works

`Giggly` lists `Giggly.DataFrame` so its sub-boundaries may — a sub-boundary may list a
top-level boundary only when its parent does — and because `panel_scales/2` reads the layout
table. It exports `Plot`; `Assembly`, `Facet`, `Group`
and `Scale` are internal.

`Assembly.run/1` first has `Facet.assign_panels/1` put the `:panel` column on the plot's data,
once for every layer. It then reverses the plot's `reversed_layers` into drawing order and, for
each layer, lays its mapping over the plot's (the layer's column wins), sorts the pairs by
aesthetic, passes them to `DataFrame.select/2`, carries `:panel` across with `DataFrame.put/3`,
and calls `Group.add/2` with `Scale.level_key/1`. It then trains each axis's scale: it reads each
layer's computed mapping for the axis's family, refuses an unplaceable or disagreeing column, takes
the kind from the first column (an axis no layer maps is continuous), and `Scale.train/2` folds in every such column of every layer. Last, each frame's
x-family and y-family columns are replaced by `Scale.map/2`'s positions. `layer_data/2` checks the
index against the plot's layer count before assembling, so a missing layer raises an
`ArgumentError` naming it; `panel_scales/2` finds the panel's scale ids in the layout and raises
the same way for a panel the plot does not have.

`Group.add/2` takes its key columns from the frame's types: a mapped `group` alone, or else every
discrete column. It zips the key columns into one tuple per row, sorts the distinct tuples by the
order key applied to each value, numbers them from 1, and looks each row up. An empty key gives
every row `-1`. With `Scale.level_key/1` as the key, `nil` sorts last and values otherwise compare
in Erlang term order, so strings sort by bytes and structs such as dates by their fields rather than
chronologically.
