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
- **The stages run in one fixed order**, each pair a semantic chosen in §4: the facet lays the
  panels out from the plot's data and every layer's table and assigns `panel` to each layer's
  table, raw → each layer's mapping is evaluated (`Giggly.Mapping.evaluate/2`), an after_stat
  left for after the stat (`Mapping.stage/1`) → `Group.add/2` writes `group` →
  transform scales → train position scales → map positions to numeric (not to the unit panel) →
  stat → `after_stat` → the positions a layer sets into every row (a rectangle's set corners, as
  ggplot2's `GeomRect$setup_data()` fills them in), and the width it sets where its table has
  none, as `compute_data_size()` reads a row's width before its parameter (a stat writing a width
  takes the set one as its own, as `stat_count()` and `stat_boxplot()` do) → geom reparameterize
  (a bar to `xmin`/`xmax`/`ymin`/`ymax`) → the position's aesthetics into every row → position →
  reset and retrain position scales → map positions again, censoring what limits cut → freeze
  view scales → train non-position scales → build guides → map non-position scales →
  `after_scale` → fixed values last. A stage arrives with its increment and goes where this order puts it.
- **Each stage is its own domain, and `Assembly`'s `deps:` names them.** A stage is handed what it
  needs; it never reaches back into the assembly or the plot.
- **The assembly calls the families' build functions, never their drawing ones**: the facet's,
  the coordinate system's `panel_params`, `clip` and `aspect`, each layer's stat and position, and
  each geom's `setup_data`; `draw_panel`, `transform`, `axes` and `grid` are rendering's. It lists
  `Coord` and `Geom` for their build functions, so this holds by review: design-log §4, the entry
  beginning "A geom says where its marks sit". It lists `Giggly.Guide` only to build the kind of
  guide a name chooses and to read a legend's struct the plot holds, and never draws one.
- **Each geom is told each axis's scale kind, discrete or continuous**, which the assembly decides
  once per axis, so a bar's orientation is decided as ggplot2's `has_flipped_aes()` decides it from
  `mapped_discrete` positions; a geom never sees a scale itself. A date axis is continuous to a
  geom, as ggplot2's geoms see a date as not discrete; the axis's scale is a date scale.
- **After the stat, each aesthetic the layer maps to an after_stat takes its value evaluated
  against the stat's output, in `Plot.mapping_order/2`'s order, then each it leaves unmapped the
  computed column its stat names for it** (`Stat.default_mapping/1`), in name order, as ggplot2's
  `map_statistic()`: counting's count goes into y, counting at each place's `n` into size. Each
  replaces its column in place or follows the last, a factor's declared `:category`. The output is
  read as it stands; ggplot2 reads it
  back in data units first, which waits for a stat whose documented variables are positions.
  **Each on an axis is checked against the axis's scale, chosen before the stat, and put through
  it** (`Scale.transform/2`, each row on its panel's scale): numbers on a continuous or a discrete
  axis, dates on a date one, and anything else refused when run, naming the layer, the aesthetic,
  the value or the stat's column, and its type, where ggplot2 adds a scale for an axis nothing
  mapped before the stat, or warns at numbers on a date axis.
- **Just before a layer's position runs, each aesthetic the position reads goes into every
  row**: the value the layer sets, or else the position's default
  (`Position.default_aesthetics/1`), as ggplot2's `Position$use_defaults()`, so every text layer's
  table carries `nudge_x` and `nudge_y`, 0 when unset, as R's `layer_data()` does. **No layer maps
  one yet, so a column the plot's mapping carried in under its name is replaced** and moves nothing
  (design-log §4, the entry beginning "A position declares the aesthetics it reads").
- **The position scales are reset and trained again after the position**, on every layer's
  x-family and y-family columns where the marks now stand, as ggplot2's `reset_scales()` and second
  `train_position()`: a bar's `ymin` of 0 reaches the y axis, and a discrete scale keeps its levels
  and widens its continuous range. **The positions are then mapped again** (`Scale.censor/2`), as
  ggplot2 maps them, which leaves out what a scale's limits cut: a bar reaching past the y axis's
  limit is missing its end, so it is not drawn; the non-position scales train on what remains.
- **The assembly's output is `%Giggly.Assembly{}`, and gains a field with the stage that fills it:**
  the layer frames, the rows each layer's geom draws (`drawn_data`: its frame without the
  aesthetics other than position it carries unused), each layer's geom, the layout table, the
  trained x and y scales keyed by
  scale id, the trained scale of each aesthetic other than position that a layer maps, by
  aesthetic (`non_position_scales`), the legends those scales give, merged and ordered
  (`legends`), the plot's coordinate system (carried for rendering to hand each geom and guide),
  each panel's params keyed by panel id, whether panels are clipped (`Coord.clip/1`) and the aspect ratio
  every panel keeps (`Coord.aspect/2`, from the first panel's params, as ggplot2 asks it), each
  asked once here so rendering never lists `Coord`, the title of each aesthetic's guide
  (`guide_titles`, the x and y axes' so far), the plot's own labels (`plot_labels`: its title,
  subtitle, caption and tag, `:none` for each `labs/2` does not set), and the plot's theme, which
  the assembly
  passes on unread for rendering to resolve, the only stage that reads a theme so far; the first
  build stage to read one (default aesthetics, or a palette a theme sets, which `theme_gray()`
  does not) brings the resolution here, where ggplot2's build completes the theme.
- **The facet and the coordinate system run by the structs the plot records**, the null facet and
  cartesian coordinates included, through the protocols `Giggly.Facet` and `Giggly.Coord`; the
  assembly names no kind.
- **A scale's name titles its axis over everything else**, `:none` among them, as ggplot2's
  scale name beats `labs()` whichever came first. **Then a label `Plot.labs/2` sets titles an axis
  or a legend**, `:none` among them, as a plot's labels win in ggplot2's `setup_plot_labels()`,
  whenever the call came; so a label decides which legends merge, as they merge by title.
  Otherwise:
- **Each axis's title is the title of what the first layer to map the axis's aesthetic to a
  column or an expression maps it to** (`Giggly.Mapping.title/2`: a column's name, an
  expression's text, `:none` for a closure's, which no later layer replaces), an annotation never
  (`Plot.layer_annotation?/1`), as ggplot2's `annotate()` mapping is unlabelled, read through
  `Plot.computed_mapping/2` in the order the layers were added, as ggplot2's
  `setup_plot_labels()`, where a later layer never replaces an earlier one's, and `resolve_label()`,
  which reads the scale's first aesthetic, so `:xmin` alone titles nothing. **Failing that, it is
  the last layer's fallback**: the aesthetic's own name where that layer maps it to a constant, or
  else the computed column its stat puts into the aesthetic (`count`), as ggplot2 marks both as
  fallbacks any layer's own title replaces (checked in R: `geom_point(aes(y = 10)) + geom_bar()`
  titles y `count`, the other way round `y`); else `:none`. The titles are the only place the
  data's own column names survive the assembly.
- **A plot with no layers trains no scale, so its axes have no breaks and no titles.** ggplot2
  builds such a plot with a `geom_blank()` layer that inherits the plot's mapping, so its axes
  span the mapped columns and are titled; Giggly follows when a geom that draws nothing arrives.
- **Each panel's params are built once, after the positions, from the scales its layout row
  names, trained again:** each axis's extent (`Scale.dimension/1`) and the breaks an axis showing
  that extent draws (`Scale.breaks/2`), ggplot2's `setup_panel_params()`.
- **Each axis's scale is added after grouping, of the kind its columns need, or is the plot's own
  scale for the aesthetic, refused when run unless it takes their kind (`Scale.takes?/2`: a
  continuous scale through the identity takes a date, at its days, as ggplot2 draws one; "the
  plot's x scale is continuous through log10, but the layer at index 0 maps :x to "day", a date
  column", where ggplot2 fails), and on an axis no layer maps before the stat the plot's scale
  whatever its kind; the axis's kind, which each geom and the after-stat check are told, is its
  scale's (`Scale.kind_of/1`); every layer's columns in the axis's family
  are then put through the scale's transformation, trained on, and mapped to positions**, a
  continuous scale censoring those outside its limits. Which columns belong to an axis is
  `Aesthetics.family/1`'s answer, never a name compared with `:x`.
- **A layer's stat and position run by the structs the layer records**, read with
  `Plot.layer_stat/1` and `Plot.layer_position/1` and run through `Stat.compute_layer/3` and
  `Position.compute_layer/2`; the assembly names no stat or position kind. **A stat is handed
  each panel's axes** (design-log §4, the entry beginning "A stat is handed each panel's axes"),
  built once from the scales trained before the stat: each axis's extent unwidened
  (`Scale.dimension/2` with no expansion, as ggplot2's stats call `dimension()`), whether it is
  discrete, and a function putting values through its transformation, built round the panel's
  scale, so a stat never sees one.
- **Each row is routed to the scale its panel uses.** The layout's `scale_x` and `scale_y` say
  which scale each panel uses, one for a fixed axis and one per panel for a free one; the assembly
  adds an untrained scale per id, all of the axis's one kind, trains each on the rows of the
  panels that use it, and transforms and maps each row on its panel's scale, putting the values
  back in row order, as ggplot2's `scale_apply()` does. One kind per axis holds across every
  panel: free scales are clones of one scale.
- **After evaluation a layer's frame speaks only the aesthetic vocabulary:** one column per
  mapped aesthetic, plus the columns the pipeline writes. The data's own names never appear in a
  frame; only the axes' titles carry them.
- **A text's `label` never groups**: `Group.add/2` leaves it out of the key whatever its type, as
  ggplot2's `add_group()` leaves `label` out, so labels that differ in every row do not make every
  row a group. An aesthetic a layer takes from the plot and cannot use is evaluated like any other,
  and a discrete one splits its groups, as in ggplot2; it stays in the layer's frame, which
  `layer_data/2` shows, but not in the rows its geom draws, which no geom reads as set.
- **`group` is written once, by `Group.add/2`, straight after evaluation** — before any scale maps
  a discrete position to numbers, after which it no longer looks discrete.
- **The assembly gives grouping its order for values with no levels of their own.** `Group.add/2`
  numbers a category by its levels, read from the frame, as R's `id()` numbers a factor, and other
  values by the key it is handed; the assembly hands it `Scale.level_key/1`, the order a discrete
  scale gives such values, so group ids follow axis and legend order while grouping names nothing
  about scales. It hands the facet the same key, so panels made from a column's values follow the
  same order.
- **Whether a column suits an axis is checked here, when the plot is run.** Before training, every
  column on an axis must be a type `Scale.kind/1` can place and all of one kind, each layer's
  types read from its evaluated frame, since an expression's type is known only once it has run;
  a refusal names the layer by index, the aesthetic, the value as the plot holds it (a column by
  the name its table gives it), and its type. The plot checks only what it knows (names and which
  aesthetics a geom takes).
- **Discreteness is read from `DataFrame.dtypes/1`** (`:string`, `:boolean`, `:atom`,
  `:category`), never by scanning values. **A factor's column enters the evaluated frame declared
  a category, with its levels** (`Mapping.category/2` gives the declaration, a table's factor
  column's and a reordering's included), so grouping and the
  scales' kinds read it as discrete, numbers and all; the transformation leaves a category as it
  is, a discrete scale's being the identity, so it reaches training with its levels. **A scale is
  told levels from positions by the stage**: the first training hands it the layers' own values,
  a column at a time, each with its factor's levels or `:none` (`Scale.train/3`), the retraining
  after the position their positions (`Scale.train_positions/2`), so a factor's numbers train
  levels and a bar's edges a discrete axis's continuous range. A non-position scale is trained on
  each column with its levels too.
- **A group id depends only on the values,** never on the panel or the row's position, so stacking
  and dodging order agree across facets. The integer `panel` column is never discrete, so it needs
  no exclusion from the key.
- **Each aesthetic other than position that a layer maps gets one scale for the whole plot**, one
  its stat fills by default counting as mapped where the layer neither maps nor sets it
  (`mapping_with_defaults/2`: size from `n`), as ggplot2 adds scales from
  `defaults(computed_mapping, stat$default_aes)`: the plot's own scale for it, refused when run
  unless it takes the kind of column the first column needs (`Scale.takes?/2`, naming that
  column, where ggplot2 fails with "Continuous value
  supplied to a discrete scale"), or else ggplot2's default for that kind (`Scale.new/2`), its
  ordinal one where that first column is an ordered factor (its frame's `DataFrame.category/2`),
  as ggplot2's `scale_type()` names an ordered factor's `"ordinal"`, the
  columns evaluated before the stats first and those computed after them next, each in layer
  order, as ggplot2 adds the scales of evaluated aesthetics before any stat runs; every column of
  it checked as an axis's are, and on an aesthetic whose every scale is discrete
  (`Scale.discrete_only?/1`: shape, line type) a continuous or a date column refused first, naming
  the layer, the aesthetic in words (`Aesthetics.in_words/1`), the value and its type, as ggplot2's
  `scale_shape_continuous()` and `scale_linetype_continuous()` abort for both,
  trained once the positions are final on every layer's column of it (a column a stat dropped
  trains nothing), and each column mapped through it, a value mapped to `:none` put in as `nil`,
  the table's missing value, as R's mapped column holds `NA`, then the set values on top: a
  value a layer sets wins, its mapping of the aesthetic dropped before evaluation
  (`Plot.computed_mapping/2`).
- **Each non-position scale gives a legend unless its guide is `:none` or it has no breaks**,
  ggplot2's guides built from the trained scales, **its guide the one `Plot.guides/2` sets for its
  aesthetic, else the one its scale names, in whatever order they were given**, as ggplot2 takes
  `guides()` over a scale's `guide` (design-log §4, the entry beginning "A guide is chosen"):
  titled by its label, or else as an axis is (`:none` takes no room), a key for each break the
  scale shows (`Scale.legend_breaks/1`: a continuous scale's breaks inside its limits, a discrete
  one's breaks among its limits, each from the scale's options), labelled as its `labels` give, at
  the value it maps to, drawn by that kind of guide, the struct the plot holds or the one the
  assembly builds from a name (`%Guide.Legend{}` for `:legend`, `%Guide.Colorbar{bins: 15}` for
  `:colorbar`), as `Plot` builds a position's. **A colour bar for a discrete scale raises**, naming
  the aesthetic, where ggplot2 warns and draws none; only `guides/2` can give one, the scale
  functions refusing it. **A reversed legend hands its keys over last first**, the missing value's
  among them, before legends merge, so two read alike only in the same order, as ggplot2's
  `extract_params()` turns its key upside down. **A colour bar's
  keys carry their place up the bar** (`Scale.places/2`, 0 to 1 over the limits, the gradient
  form's), **and the colour bar its colours** (`decor`, `bins` values over the limits from
  `Scale.samples/2`, each its place and colour, `extract_decor()`), worked out here from the scale,
  never by the guide; it draws no layer, so it has none. **Legends come in the order of their aesthetics' names, and one with
  the kind of guide, title and labels of an earlier merges into it**, its aesthetics after the earlier's and each key holding every aesthetic's value, as
  ggplot2 merges guides whose title and labels hash alike (design-log §4, the entry beginning "The
  guide protocol sits at"); ggplot2 orders by that hash, so a golden's R script sets
  `guides(order =)`. A legend is drawn by every layer that maps one of its aesthetics, its stat's
  default for one it neither maps nor sets included, and accepts it (`Plot.layer_accepted/1`),
  with those it maps and accepts, each carrying what it sets (its `fixed`) for its keys, as
  ggplot2's `matched_aes()` gives a layer only the key's aesthetics it
  maps and its geom knows and its key data holds a layer's `aes_params`; a layer that sets the
  legend's own aesthetic draws none. **A legend no layer draws in is dropped**, either kind, as
  ggplot2 drops a guide no layer matches: an aesthetic every layer takes from the plot's mapping
  and none can use has no legend, as text, which knows no `fill`, draws in no fill legend. **Each
  such layer says whether it draws in each key (`draws`), as ggplot2 4's `keep_key_data()` decides**, from its table once the positions are
  final and before the other aesthetics are mapped: a discrete key only where one of the layer's
  columns of the aesthetics it maps holds the key's break (`value`, the first aesthetic's, as
  ggplot2's `.value`), matched as the scale matches values (`Scale.Discrete.key/1`, a limit of `4`
  a column's `4.0`, as R compares them as text), `nil` for the `NA` key, so two layers mapping one
  aesthetic to different columns each draw their own keys; the `NA` key also where one of those
  columns holds a value no key shows, outside the scale's limits or breaks, which the scale maps
  to its missing value, as `keep_key_data()` keeps it; a continuous scale's key always, which the
  scale's kind says (`Scale.discrete?/1`), never the break's type, since a factor's numeric
  levels are discrete keys; and every key where the layer's stat dropped those columns.
- **Evaluated columns are the layer's own aesthetics, then those it takes from the plot's
  mapping, each mapping's `x` and `y` first and its others in name order, then `panel`, then
  `group`** (`Plot.mapping_order/2`), and the group key follows column order: reordering the
  aesthetics renumbers groups. ggplot2 lays a layer's mapping over the plot's as
  `defaults(layer$mapping, plot$mapping)`, so a layer's `fill` over the plot's `x` is evaluated
  first, and `aes()` takes `x` and `y` as its first arguments; a mapping here is a map with no
  written order, so the rest go by name, where ggplot2's follow the writing. A discrete alpha
  mapped with `x` therefore groups within each `x`, and `geom_bar(%{fill: :drv})` over the plot's
  `x` groups by drive train first, as ggplot2's do.
- **The values a layer sets go in last, one value in every row or an annotation's list, one value
  per row**, as ggplot2's `use_defaults()` applies `aes_params`, so a line's set colours land on
  its rows once `setup_data/3` has put them in order, as in R. Under a facet that repeats an
  annotation's rows across several panels a list holds too few, and the run raises naming the
  layer and the aesthetic, as ggplot2 fails with "Aesthetics must be either length 1 or the same
  as the data".
