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

- **A plot is run only from `Giggly`.** The root module holds the run functions (`layer_data/2`,
  `panel_scales/2`, `to_svg/2`), each taking a finished plot; `Plot` describes and never runs, and
  nothing outside Giggly calls `Assembly`. Arrows run root → `Render` → `Assembly` → `Plot` and
  root → `SVG` → `Scene`, and nothing calls back up.
- **The stages run in one fixed order**, each pair a semantic chosen in §4: the facet assigns
  `panel` to the raw data → each layer's mapping is evaluated → `Group.add/2` writes `group` →
  transform scales → train position scales → map positions to numeric (not to the unit panel) →
  stat → `after_stat` → geom reparameterize (a bar to `xmin`/`xmax`/`ymin`/`ymax`) → position →
  reset and retrain position scales → freeze view scales → map positions again → train
  non-position scales → build guides → map non-position scales → `after_scale` → fixed values
  last. A stage arrives with its increment and goes where this order puts it.
- **Each stage is its own domain, and `Assembly`'s `deps:` names them.** A stage is handed what it
  needs; it never reaches back into the assembly or the plot.
- **The assembly's output is `%Giggly.Assembly{}`, and gains a field with the stage that fills it:**
  the layer frames with each layer's geom, the layout table, the trained x and y scales keyed by
  scale id, the plot's coordinate system (carried for rendering to hand each geom and guide), each
  panel's params keyed by panel id, whether panels are clipped (`Coord.clip/1`, asked once here so
  rendering never lists `Coord`), the title of each aesthetic's guide (`guide_titles`, the x
  and y axes' so far), and the name of the plot's theme, which the assembly passes on unread for
  rendering to resolve, the only stage that reads a theme so far; the first build stage to read one
  (default aesthetics, palettes) brings the resolution here, where ggplot2's build completes the
  theme.
- **The facet and the coordinate system run by the structs the plot records**, the null facet and
  cartesian coordinates included, through the protocols `Giggly.Facet` and `Giggly.Coord`; the
  assembly names no kind.
- **Each axis's title is the column the first layer to map the axis's aesthetic maps it to**,
  read through `Plot.computed_mapping/2` in the order the layers were added, as ggplot2's
  `setup_plot_labels()`, where a later layer never replaces an earlier one's, and `resolve_label()`,
  which reads the scale's first aesthetic, so `:xmin` alone titles nothing. An axis no layer maps
  has the title `:none`. Every point layer maps x and y, so today the first layer is the one; the
  search past a layer that does not map the aesthetic arrives with the first geom that can leave
  an axis unmapped, where `Map.fetch!/2` fails loudly until it does. The titles are the only place the data's own column names survive the
  assembly.
- **Each panel's params are built once, after the positions, from the scales its layout row
  names:** each axis's extent (`Scale.dimension/1`) and the breaks an axis showing that extent
  draws (`Scale.breaks/2`), ggplot2's `setup_panel_params()`; until the reset and retrain
  arrives, those are the scales trained before the stat.
- **Each axis's scale is added after grouping, of the kind its columns need; every layer's
  columns in the axis's family are then put through the scale's transformation, trained on, and
  mapped to positions.** Which columns belong to an axis is `Aesthetics.family/1`'s answer, never
  a name compared with `:x`.
- **A layer's stat and position run by the structs the layer records**, read with
  `Plot.layer_stat/1` and `Plot.layer_position/1` and run through `Stat.compute_layer/2` and
  `Position.compute_layer/2`; the assembly names no stat or position kind.
- **One scale per axis until free scales.** Each axis's scale id is read from the layout, and the
  assembly matches exactly one; routing rows to several arrives with `facet_wrap`'s free scales,
  where that match fails loudly until it does.
- **After evaluation a layer's frame speaks only the aesthetic vocabulary:** one column per
  mapped aesthetic, plus the columns the pipeline writes. The data's own names never appear in a
  frame; only the axes' titles carry them.
- **`group` is written once, by `Group.add/2`, straight after evaluation** — before any scale maps
  a discrete position to numbers, after which it no longer looks discrete.
- **The assembly gives grouping its order.** `Group.add/2` numbers values by the key it is handed;
  the assembly hands it `Scale.level_key/1`, the order a discrete scale gives its levels, so group
  ids follow axis and legend order while grouping names nothing about scales. It hands the facet
  the same key, so panels made from a column's values follow the same order. When level order can
  be configured, the assembly hands over the configured order.
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
table. It exports `Plot`. A user calls only the API (CLAUDE.md, Conventions); the domains
beneath are `@moduledoc false`, apart from the parts of `DataFrame` and `Scale` the run functions
hand back.

`Assembly.run/1` first has `Facet.layout/3` build the layout table from the plot's data, handed
`Scale.level_key/1`, and `Facet.assign_panels/3` put the `:panel` column on that data from the
layout, once for every layer. It then reverses the plot's `reversed_layers` into drawing order and, for
each layer, lays its mapping over the plot's (the layer's column wins), sorts the pairs by
aesthetic, passes them to `DataFrame.select/2`, carries `:panel` across with `DataFrame.put/3`,
and calls `Group.add/2` with `Scale.level_key/1`. It then adds each axis's scale: it reads each
layer's computed mapping for the axis's family, refuses an unplaceable or disagreeing column, and
takes the kind from the first column (an axis no layer maps is continuous). Each frame's x-family
and y-family columns are replaced by `Scale.transform/2`'s values, `Scale.train/2` folds in every
such column of every layer, and the columns are replaced again by `Scale.map/2`'s positions. Each
frame then goes through its layer's stat and its position. Last, each layout row's scale ids
pick the panel's x and y scales, and `Coord.panel_params/3` builds the panel's params from each
one's `Scale.dimension/1` and the `Scale.breaks/2` on it; `Coord.clip/1` says whether panels are
clipped. `to_svg/2` validates its options, hands the result to `Render.scene/1` and the scene to
`SVG.draw/3`. `layer_data/2` checks the
index against the plot's layer count before assembling, so a missing layer raises an
`ArgumentError` naming it; `panel_scales/2` finds the panel's scale ids in the layout and raises
the same way for a panel the plot does not have.

`Group.add/2` takes its key columns from the frame's types: a mapped `group` alone, or else every
discrete column. It zips the key columns into one tuple per row, sorts the distinct tuples by the
order key applied to each value, numbers them from 1, and looks each row up. An empty key gives
every row `-1`. With `Scale.level_key/1` as the key, `nil` sorts last and values otherwise compare
in Erlang term order, so strings sort by bytes and structs such as dates by their fields rather than
chronologically.
