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
- **The assembly calls the families' build functions, never their drawing ones**: the facet's,
  the coordinate system's `panel_params`, `clip` and `aspect`, each layer's stat and position, and
  each geom's `setup_data`; `draw_panel`, `transform`, `axes` and `grid` are rendering's. It lists
  `Coord` and `Geom` for their build functions, so this holds by review: design-log §4, the entry
  beginning "A geom says where its marks sit".
- **The position scales are reset and trained again after the position**, on every layer's
  x-family and y-family columns where the marks now stand, as ggplot2's `reset_scales()` and second
  `train_position()`: a bar's `ymin` of 0 reaches the y axis, and a discrete scale keeps its levels
  and widens its continuous range. ggplot2 maps the positions again after; a scale maps a position
  to itself, so nothing here does.
- **The assembly's output is `%Giggly.Assembly{}`, and gains a field with the stage that fills it:**
  the layer frames with each layer's geom, the layout table, the trained x and y scales keyed by
  scale id, the plot's coordinate system (carried for rendering to hand each geom and guide), each
  panel's params keyed by panel id, whether panels are clipped (`Coord.clip/1`) and the aspect ratio
  every panel keeps (`Coord.aspect/2`, from the first panel's params, as ggplot2 asks it), each
  asked once here so rendering never lists `Coord`, the title of each aesthetic's guide
  (`guide_titles`, the x and y axes' so far), and the name of the plot's theme, which the assembly
  passes on unread for rendering to resolve, the only stage that reads a theme so far; the first
  build stage to read one (default aesthetics, palettes) brings the resolution here, where ggplot2's
  build completes the theme.
- **The facet and the coordinate system run by the structs the plot records**, the null facet and
  cartesian coordinates included, through the protocols `Giggly.Facet` and `Giggly.Coord`; the
  assembly names no kind.
- **Each axis's title is the column the first layer to map the axis's aesthetic maps it to**,
  read through `Plot.computed_mapping/2` in the order the layers were added, as ggplot2's
  `setup_plot_labels()`, where a later layer never replaces an earlier one's, and `resolve_label()`,
  which reads the scale's first aesthetic, so `:xmin` alone titles nothing. An axis no layer maps
  has the title `:none`. Every point layer maps x and y, so today the first layer is the one; the
  search past a layer that does not map the aesthetic arrives with the first geom that can leave
  an axis unmapped, where `Map.fetch!/2` fails loudly until it does. The titles are the only
  place the data's own column names survive the assembly.
- **A plot with no layers trains no scale, so its axes have no breaks and no titles.** ggplot2
  builds such a plot with a `geom_blank()` layer that inherits the plot's mapping, so its axes
  span the mapped columns and are titled; Giggly follows when a geom that draws nothing arrives.
- **Each panel's params are built once, after the positions, from the scales its layout row
  names, trained again:** each axis's extent (`Scale.dimension/1`) and the breaks an axis showing
  that extent draws (`Scale.breaks/2`), ggplot2's `setup_panel_params()`.
- **Each axis's scale is added after grouping, of the kind its columns need; every layer's
  columns in the axis's family are then put through the scale's transformation, trained on, and
  mapped to positions.** Which columns belong to an axis is `Aesthetics.family/1`'s answer, never
  a name compared with `:x`.
- **A layer's stat and position run by the structs the layer records**, read with
  `Plot.layer_stat/1` and `Plot.layer_position/1` and run through `Stat.compute_layer/2` and
  `Position.compute_layer/2`; the assembly names no stat or position kind.
- **Each row is routed to the scale its panel uses.** The layout's `scale_x` and `scale_y` say
  which scale each panel uses, one for a fixed axis and one per panel for a free one; the assembly
  adds an untrained scale per id, all of the axis's one kind, trains each on the rows of the
  panels that use it, and transforms and maps each row on its panel's scale, putting the values
  back in row order, as ggplot2's `scale_apply()` does. One kind per axis holds across every
  panel: free scales are clones of one scale.
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
