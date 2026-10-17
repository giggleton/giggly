defmodule Giggly.Assembly do
  @moduledoc false

  # The assembly of a plot: the fixed sequence of stages that turns a `Giggly.Plot`, a description,
  # into what is drawn, and the value those stages produce. The name is the middle of Wilkinson's
  # three stages of making a graphic (specification, assembly, display); a plot is the
  # specification, and rendering and drawing it are the display.
  #
  # The stages run in one fixed order, each adjacent pair a semantic chosen on purpose, and they
  # arrive one at a time. Today the assembly:
  #
  #   1. lays the panels out and assigns each row of the plot's data its panel (`Giggly.Facet`);
  #   2. evaluates each layer's mapping against that data;
  #   3. adds each layer's `:group` column (`Giggly.Group`), numbering values in the order a
  #      discrete scale gives its levels, so group ids follow axis and legend order;
  #   4. adds one x scale and one y scale per scale id in the layout (`Giggly.Scale`), of the kind
  #      the axis's columns need, first refusing an axis column no scale can place yet, or one whose
  #      kind disagrees with the axis's first column: an axis has one scale;
  #   5. puts every layer's x-family and y-family columns through their scale's transformation;
  #   6. trains each scale over those columns, in the rows of the panels that use it;
  #   7. maps them to their positions, each row on its panel's scale;
  #   8. computes each layer's stat (`Giggly.Stat`) on its table;
  #   9. puts into each aesthetic the layer leaves unmapped the computed column its stat names for
  #      it, as a count into y;
  #  10. has each layer's geom (`Giggly.Geom`) give each row the extent it is drawn over, such as a
  #      bar's edges, told whether each axis is discrete, which decides a bar's orientation;
  #  11. moves each layer's marks by its position (`Giggly.Position`);
  #  12. resets each scale and trains it again on every layer's columns on its axis, where the
  #      marks now stand, a discrete scale keeping its levels and widening its continuous range;
  #  13. adds a scale for each aesthetic other than position that a layer maps (`alpha`, `color`,
  #      `fill`), of the kind its columns need, trains it on every layer's column of that
  #      aesthetic, and maps each column through it, as ggplot2 trains and maps its non-position
  #      scales once the positions are final;
  #      it then builds the legends: each such scale's, a key for each break, labelled, with the
  #      value it maps to, in the order of the aesthetics' names, one with the title and labels of
  #      an earlier merged into it, as ggplot2 merges guides that would read alike; each legend
  #      is drawn by the geom of each layer that maps one of its aesthetics and can use it, with
  #      what that layer sets, in the keys whose values the layer's table holds, and a legend no
  #      layer can draw is dropped;
  #  14. puts each aesthetic a layer sets to one value, such as `alpha`, into every row of its
  #      table, last, as ggplot2's geoms apply a layer's `aes_params` once every scale has run;
  #  15. has the plot's coordinate system (`Giggly.Coord`) build each panel's params from the
  #      extents of the panel's scales and each axis's breaks and minor breaks on its extent, and
  #      say whether panels are clipped to their edges and what shape they keep, from the first
  #      panel's params, as ggplot2 asks it.
  #
  # Each stage is run by the struct the plot records for it, its facet, its coordinate system and
  # each layer's geom, stat and position, through the protocol at its family's root; the assembly
  # calls only the families' build functions, never their drawing ones, which are rendering's.
  #
  # The result holds one `Giggly.DataFrame` per layer, in the order the layers were added, whose
  # columns are named by aesthetic plus `:panel` and `:group`, with each layer's geom; the layout
  # table; the trained scales, by scale id; the trained scale of each aesthetic other than position
  # that a layer maps, by aesthetic, and the legend each gives; the plot's coordinate system, which rendering hands each
  # geom and guide unread, each panel's params, by panel id, whether panels are clipped, and the
  # aspect ratio every panel keeps, `:none` when they take the shape the drawing leaves; each
  # axis's title, the name of the column the first layer to map the axis's aesthetic maps it to
  # (ggplot2's `setup_plot_labels()`); and the name of the plot's theme, passed on for rendering,
  # the only stage that reads a theme so far. The data's own column names appear only as titles.
  #
  # Nothing outside Giggly calls this module: the functions in `Giggly` take a plot and run it here.

  # The assembly reads a plot and hands each stage its input; what it may call is the plot, the
  # data frame, the aesthetic vocabulary (which columns are x and which y) and the stages, each
  # named as it arrives; the guides it lists only to build the kind of guide a scale names.
  use Boundary,
    deps: [
      Giggly.Aesthetics,
      Giggly.Coord,
      Giggly.DataFrame,
      Giggly.Facet,
      Giggly.Geom,
      Giggly.Group,
      Giggly.Guide,
      Giggly.Plot,
      Giggly.Position,
      Giggly.Scale,
      Giggly.Stat
    ],
    exports: []

  alias Giggly.{
    Aesthetics,
    Coord,
    DataFrame,
    Facet,
    Geom,
    Group,
    Guide,
    Plot,
    Position,
    Scale,
    Stat
  }

  @enforce_keys [
    :layer_data,
    :layer_geoms,
    :layout,
    :x_scales,
    :y_scales,
    :non_position_scales,
    :legends,
    :coord,
    :panel_params,
    :clip,
    :aspect_ratio,
    :guide_titles,
    :theme
  ]
  defstruct @enforce_keys

  @typedoc """
  An assembled plot: each layer's table and the geom that draws it, in the order the layers were
  added; the layout table; the trained x and y scales keyed by the scale ids the layout gives each
  panel; the trained scale of each aesthetic other than position that a layer maps, by aesthetic;
  each legend those scales give, its title, its keys and the geoms that draw them; the plot's
  coordinate system, each panel's params keyed by panel id, whether panels
  are clipped to their edges, and the aspect ratio, height over width, every panel keeps, `:none`
  for none; the title of each aesthetic's guide, the x and y axes' so far,
  `:none` for an axis no layer maps; and the name of the plot's theme, which rendering resolves.
  """
  @type t :: %__MODULE__{
          layer_data: [DataFrame.t()],
          layer_geoms: [struct()],
          layout: DataFrame.t(),
          x_scales: %{optional(pos_integer()) => Scale.t()},
          y_scales: %{optional(pos_integer()) => Scale.t()},
          non_position_scales: %{optional(Plot.aesthetic()) => Scale.t()},
          legends: [legend()],
          coord: struct(),
          panel_params: %{optional(pos_integer()) => Coord.panel_params()},
          clip: Coord.clip(),
          aspect_ratio: Coord.aspect(),
          guide_titles: %{x: String.t() | :none, y: String.t() | :none},
          theme: Plot.theme()
        }

  @typedoc """
  A legend for one or more aesthetics other than position, those whose scales give the same kind of
  guide, title and labels, in name order: the guide that draws it, a struct of its kind, as the
  first aesthetic's scale names it (`Giggly.Guide`); its title, the column the first layer to map
  the aesthetic maps it to; a key for each of its scales' breaks, the break's label, the break
  itself, as the first aesthetic's data holds it (ggplot2's `.value`), the value each aesthetic
  maps it to, and, for a colour bar, its place up the bar, 0 to 1; a colour bar's colours, each
  its place up the bar and its colour (`decor`); and each layer that maps one of its aesthetics,
  in the order the layers were added, with those it maps, its geom drawing its glyph with the
  key's values of those aesthetics and the aesthetics the layer sets, as ggplot2's legend draws a
  key for each such layer, its `aes_params` among the key's data, and whether it draws in each
  key, in key order; a colour bar has none.
  """
  @type legend :: %{
          required(:guide) => struct(),
          required(:aesthetics) => [Plot.aesthetic()],
          required(:title) => String.t(),
          required(:keys) => [
            %{
              required(:label) => String.t(),
              required(:value) => term(),
              required(:values) => %{optional(Plot.aesthetic()) => term()},
              optional(:place) => float()
            }
          ],
          required(:layers) => [
            %{
              geom: struct(),
              aesthetics: [Plot.aesthetic()],
              fixed: %{optional(Plot.aesthetic()) => term()},
              draws: [boolean()]
            }
          ],
          optional(:decor) => [{float(), String.t()}]
        }

  # Assembles `plot`, running the stages in order.
  #
  # The facet first gives each row of the plot's data its panel. Then each layer's mapping is laid
  # over the plot's (the layer's column wins), chooses and renames the data's columns, the panel
  # column is carried across, and `Giggly.Group.add/2` adds the `:group` column. The aesthetics come
  # out in the order ggplot2 evaluates them, the layer's own before those it takes from the plot,
  # each mapping's `:x` and `:y` first, as ggplot2's `aes()` takes them, then the rest in name
  # order, since a mapping is a map and has no written order to keep, followed by `:panel` and
  # `:group`, as ggplot2 orders them. Each axis then gets its scale, and every layer's
  # columns in that axis's family are put through the scale's transformation, trained on, and mapped
  # to their positions. Each layer's stat then computes on its table, and its position moves the
  # marks, and each aesthetic a layer sets to one value is put into every row of its table. Last,
  # the plot's coordinate system builds each panel's params from the extents of the scales the
  # layout gives that panel and the breaks and minor breaks each axis draws on its extent. Each axis
  # is titled by the first layer, in the order added, whose mapping laid over the plot's maps `:x`
  # (or `:y`); a later layer never retitles it, and an axis no layer maps has no title.
  #
  # Raises `ArgumentError` when a layer maps an axis to a column no scale can place yet, such as a
  # date, or to a column whose kind (continuous or discrete) disagrees with the first column on
  # that axis. The message names the layer by its index, counting from 0, the aesthetic, the column
  # as the data names it, and its type.
  @doc false
  @spec run(Plot.t()) :: t()
  def run(
        %Plot{
          data: data,
          facet: facet,
          coord: coord,
          theme: theme,
          reversed_layers: reversed_layers
        } = plot
      ) do
    layout = Facet.layout(facet, data, &Scale.level_key/1)
    paneled_data = Facet.assign_panels(facet, data, layout)
    layers = Enum.reverse(reversed_layers)

    grouped_data =
      Enum.map(layers, fn layer ->
        paneled_data
        |> evaluate(plot, layer)
        |> Group.add(&Scale.level_key/1)
      end)

    x_routes = routes(layout, :x)
    y_routes = routes(layout, :y)
    scale_kinds = %{x: axis_kind(plot, :x), y: axis_kind(plot, :y)}
    axis_kinds = Map.new(scale_kinds, fn {axis, kind} -> {axis, discreteness(kind)} end)
    non_position_kinds = non_position_kinds(plot)
    untrained_x_scales = add_scales(scale_kinds.x, x_routes)
    untrained_y_scales = add_scales(scale_kinds.y, y_routes)

    transformed_data =
      Enum.map(grouped_data, fn frame ->
        through_scales(
          frame,
          {untrained_x_scales, x_routes},
          {untrained_y_scales, y_routes},
          &Scale.transform/2
        )
      end)

    x_scales = train(untrained_x_scales, x_routes, :x, transformed_data)
    y_scales = train(untrained_y_scales, y_routes, :y, transformed_data)

    layer_data =
      Enum.zip_with(layers, transformed_data, fn layer, frame ->
        mapped = through_scales(frame, {x_scales, x_routes}, {y_scales, y_routes}, &Scale.map/2)
        computed = Stat.compute_layer(Plot.layer_stat(layer), mapped)
        statistic = map_statistic(computed, plot, layer)
        set_up = Geom.setup_data(Plot.layer_geom(layer), statistic, axis_kinds)
        Position.compute_layer(Plot.layer_position(layer), set_up)
      end)

    # ggplot2 resets the position scales and trains them again on the marks where they now stand,
    # so an axis covers every bar's edges; it maps the positions again after, which changes nothing
    # here, since a scale maps a position to itself.
    final_x_scales = retrain(x_scales, x_routes, :x, layer_data)
    final_y_scales = retrain(y_scales, y_routes, :y, layer_data)

    non_position_scales =
      Map.new(non_position_kinds, fn {aesthetic, kind} ->
        {aesthetic, train_non_position(Scale.new(kind, aesthetic), aesthetic, layer_data)}
      end)

    fixed_data =
      Enum.zip_with(layers, layer_data, fn layer, frame ->
        frame
        |> map_non_position(non_position_scales)
        |> set_fixed(Plot.layer_fixed(layer))
      end)

    panel_params = panel_params(coord, layout, final_x_scales, final_y_scales)

    %__MODULE__{
      layer_data: fixed_data,
      layer_geoms: Enum.map(layers, &Plot.layer_geom/1),
      layout: layout,
      x_scales: final_x_scales,
      y_scales: final_y_scales,
      non_position_scales: non_position_scales,
      legends: legends(non_position_scales, plot, Enum.zip(layers, layer_data)),
      coord: coord,
      panel_params: panel_params,
      clip: Coord.clip(coord),
      # ggplot2 asks the coordinate system for the first panel's.
      aspect_ratio: Coord.aspect(coord, Map.fetch!(panel_params, 1)),
      guide_titles:
        Map.new([:x, :y], fn aesthetic -> {aesthetic, guide_title(plot, layers, aesthetic)} end),
      theme: theme
    }
  end

  # The title of an aesthetic's guide, an axis's so far: the column the first layer to map the
  # aesthetic maps it to, through the layer's computed mapping; failing that, the computed column a
  # stat puts into it by default, the last layer's to do so, as `count`; or `:none`. It is ggplot2's
  # `setup_plot_labels()`, where a layer's own label is never replaced by a later layer's and
  # replaces a stat's default, which ggplot2 marks as a fallback, read as `resolve_label()` reads it,
  # by the scale's first aesthetic. The plot holds each mapping's column by the name the data gives
  # it, which is the title.
  defp guide_title(plot, layers, aesthetic) do
    mapped =
      Enum.find_value(layers, fn layer ->
        plot
        |> Plot.computed_mapping(layer)
        |> Map.get(aesthetic)
      end)

    computed =
      layers
      |> Enum.reverse()
      |> Enum.find_value(fn layer ->
        layer
        |> default_mapping()
        |> Map.get(aesthetic)
      end)

    title(mapped, computed)
  end

  defp title(nil, nil), do: :none
  defp title(nil, computed), do: Atom.to_string(computed)
  defp title(mapped, _computed), do: mapped

  defp default_mapping(layer) do
    layer
    |> Plot.layer_stat()
    |> Stat.default_mapping()
  end

  # The legends the scales of aesthetics other than position give, as ggplot2's guides build them
  # from the trained scales: each scale's, drawn by the guide the scale names, in the order of the
  # aesthetics' names, a key for each break the scale shows, labelled, with the value it maps to,
  # merged into an earlier one with the same kind of guide, title and labels, as ggplot2 merges
  # guides whose kind, title and labels hash alike, which keeps
  # each key's labels and the first's breaks and gathers its values; then each drawn by the geom of
  # every layer that maps one of its aesthetics, with those it maps, as a layer shows in a legend
  # whose aesthetic it maps, in the keys its data holds. A scale with no breaks, one trained on
  # nothing, gives none. ggplot2 orders legends by their hash, which no reader can predict; Giggly
  # orders them by name, and a legend merged from several stands where its first would. Each layer
  # comes with its table, its positions final and its other aesthetics not yet mapped, as ggplot2's
  # guides read each layer's data before the scales map it.
  defp legends(non_position_scales, plot, layers_and_data) do
    layers = Enum.map(layers_and_data, fn {layer, _frame} -> layer end)

    scale_legends =
      for {aesthetic, scale} <- Enum.sort(non_position_scales),
          breaks = Scale.legend_breaks(scale),
          breaks != [] do
        {values, labels} = Enum.unzip(breaks)
        mapped = Scale.map(scale, values)

        legend = %{
          guide: guide(scale),
          aesthetics: [aesthetic],
          title: guide_title(plot, layers, aesthetic),
          keys:
            Enum.zip_with([labels, values, mapped], fn [label, value, mapped_value] ->
              %{label: label, value: value, values: %{aesthetic => mapped_value}}
            end)
        }

        with_guide_data(legend, scale)
      end

    scale_legends
    |> Enum.reduce([], &merged/2)
    |> Enum.reverse()
    |> Enum.filter(fn legend ->
      Enum.any?(layers, fn layer -> draws_in?(legend, plot, layer) end)
    end)
    |> Enum.map(fn legend ->
      Map.put(legend, :layers, key_layers(legend, plot, layers_and_data))
    end)
  end

  # Whether `layer` draws in `legend`: whether it maps one of the legend's aesthetics and can use
  # it. ggplot2 drops a guide no layer draws in, as when every layer takes the aesthetic from the
  # plot's mapping and none can use it.
  defp draws_in?(legend, plot, layer), do: drawn_aesthetics(legend, plot, layer) != []

  # The legend's aesthetics that `layer` maps, from its own mapping or the plot's, and can use, as
  # ggplot2's `matched_aes()` keeps those the layer's geom knows.
  defp drawn_aesthetics(legend, plot, layer) do
    mapping = Plot.computed_mapping(plot, layer)
    accepted = Plot.layer_accepted(layer)

    Enum.filter(legend.aesthetics, fn aesthetic ->
      Map.has_key?(mapping, aesthetic) and aesthetic in accepted
    end)
  end

  # The legends so far, latest first, with `legend` merged into the one with its title and labels,
  # or else added.
  defp merged(legend, legends) do
    if Enum.any?(legends, fn earlier -> reads_alike?(earlier, legend) end),
      do: Enum.map(legends, fn earlier -> merged_into(earlier, legend) end),
      else: [legend | legends]
  end

  defp merged_into(earlier, legend) do
    if reads_alike?(earlier, legend), do: merge(earlier, legend), else: earlier
  end

  defp reads_alike?(legend, other) do
    legend.guide.__struct__ == other.guide.__struct__ and legend.title == other.title and
      labels(legend) == labels(other)
  end

  # The guide a scale names, as a struct of its kind, as `Plot` turns a position's name into one: a
  # colour bar sampling its colours at 15 values, as ggplot2's gradient form does (`nbin`).
  defp guide(%{guide: :legend}), do: %Guide.Legend{}
  defp guide(%{guide: :colorbar}), do: %Guide.Colorbar{bins: 15}

  # The legend with what its kind of guide draws beyond its keys, worked out from the scale: for a
  # colour bar, each key's place up the bar, 0 at the low end of the scale's range to 1 at its high
  # (ggplot2's `extract_params()` in the gradient form), and its colours (`decor`), sampled at the
  # bar's `bins` values spread evenly over the range, each its place and colour, as
  # `extract_decor()` takes them. A legend needs nothing more.
  defp with_guide_data(%{guide: %Guide.Colorbar{bins: bins}, keys: keys} = legend, scale) do
    places = Scale.places(scale, Enum.map(keys, fn key -> key.value end))
    samples = Scale.samples(scale, bins)
    sample_places = Scale.places(scale, samples)
    placed_keys = Enum.zip_with(keys, places, fn key, place -> Map.put(key, :place, place) end)

    legend
    |> Map.put(:keys, placed_keys)
    |> Map.put(:decor, Enum.zip(sample_places, Scale.map(scale, samples)))
  end

  defp with_guide_data(legend, _scale), do: legend

  defp labels(legend), do: Enum.map(legend.keys, fn key -> key.label end)

  # The legend with `other`'s aesthetics after its own, and each key's values with `other`'s.
  defp merge(legend, other) do
    %{
      legend
      | aesthetics: Enum.concat(legend.aesthetics, other.aesthetics),
        keys:
          Enum.zip_with(legend.keys, other.keys, fn key, other_key ->
            %{key | values: Map.merge(key.values, other_key.values)}
          end)
    }
  end

  # Each layer that maps one of the legend's aesthetics and can use it, in the order the layers were
  # added, with those it maps, its geom, what it sets, and whether it draws in each key; none for a
  # colour bar, which draws no layer's glyph, as ggplot2's colour bar keeps none.
  defp key_layers(%{guide: %Guide.Colorbar{}}, _plot, _layers_and_data), do: []

  defp key_layers(legend, plot, layers_and_data) do
    for {layer, frame} <- layers_and_data,
        mapped = drawn_aesthetics(legend, plot, layer),
        mapped != [] do
      %{
        geom: Plot.layer_geom(layer),
        aesthetics: mapped,
        fixed: Plot.layer_fixed(layer),
        draws: draws(legend.keys, frame, mapped)
      }
    end
  end

  # Whether a layer draws in each key, as ggplot2's `keep_key_data()` decides: in a key whose break
  # is a number, a continuous scale's, always; in a discrete key only where one of the layer's
  # columns of the aesthetics it maps holds the break, `nil` among them, so a layer whose column
  # lacks a level a second layer's column gave the scale leaves that key to the second; and in
  # every key where the layer's stat dropped those columns. ggplot2 also keeps the `NA` key for a
  # layer holding values outside the scale's limits, which the scale maps to `NA`; with no limits
  # but the trained levels, every value is a key.
  defp draws(keys, frame, aesthetics) do
    case Enum.filter(aesthetics, fn aesthetic -> aesthetic in DataFrame.names(frame) end) do
      [] ->
        Enum.map(keys, fn _key -> true end)

      present ->
        held =
          present
          |> Enum.flat_map(fn aesthetic -> DataFrame.pull(frame, aesthetic) end)
          |> MapSet.new()

        Enum.map(keys, fn key -> is_number(key.value) or MapSet.member?(held, key.value) end)
    end
  end

  # A scale for an aesthetic other than position trained on every layer's column of it, in all its
  # rows, where the positions are final, as ggplot2's `train_df()` trains its non-position scales:
  # one scale for the whole plot, whatever the facet. A layer whose stat dropped the column, as
  # counting drops one that varies within a bar, trains nothing. The scale's transformation is the
  # identity, so its values are trained as they are.
  defp train_non_position(untrained, aesthetic, layer_data) do
    Enum.reduce(layer_data, untrained, fn frame, scale ->
      if aesthetic in DataFrame.names(frame),
        do: Scale.train(scale, DataFrame.pull(frame, aesthetic)),
        else: scale
    end)
  end

  # The layer's table with each column of an aesthetic other than position mapped through its
  # scale, as ggplot2's `map_df()` maps them, in name order.
  defp map_non_position(frame, scales) do
    scales
    |> Enum.sort()
    |> Enum.reduce(frame, fn {aesthetic, scale}, mapped ->
      if aesthetic in DataFrame.names(mapped),
        do: DataFrame.put(mapped, aesthetic, Scale.map(scale, DataFrame.pull(mapped, aesthetic))),
        else: mapped
    end)
  end

  # The layer's table with each aesthetic the layer sets to one value given that value in every
  # row, in name order, as ggplot2's `use_defaults()` applies a layer's `aes_params` after every
  # scale has mapped its aesthetics.
  defp set_fixed(frame, fixed) do
    rows = DataFrame.row_count(frame)

    fixed
    |> Enum.sort()
    |> Enum.reduce(frame, fn {aesthetic, value}, set ->
      DataFrame.put(set, aesthetic, List.duplicate(value, rows))
    end)
  end

  # The layer's table with each aesthetic its own and the plot's mappings leave unmapped given the
  # computed column its stat puts into it by default, as ggplot2's `map_statistic()` evaluates a
  # stat's `after_stat()` defaults: counting puts its count into y when no mapping gives y.
  defp map_statistic(frame, plot, layer) do
    mapped = Plot.computed_mapping(plot, layer)

    layer
    |> default_mapping()
    |> Enum.reject(fn {aesthetic, _column} -> Map.has_key?(mapped, aesthetic) end)
    |> Enum.sort()
    |> Enum.reduce(frame, fn {aesthetic, column}, statistic ->
      DataFrame.put(statistic, aesthetic, DataFrame.pull(statistic, column))
    end)
  end

  # Each panel's params, from the scales its layout row names: ggplot2's `setup_panel_params()`,
  # after the positions have run.
  defp panel_params(coord, layout, x_scales, y_scales) do
    [:panel, :scale_x, :scale_y]
    |> Enum.map(fn name -> DataFrame.pull(layout, name) end)
    |> Enum.zip()
    |> Map.new(fn {panel, scale_x_id, scale_y_id} ->
      x_axis = axis(Map.fetch!(x_scales, scale_x_id))
      y_axis = axis(Map.fetch!(y_scales, scale_y_id))
      {panel, Coord.panel_params(coord, x_axis, y_axis)}
    end)
  end

  # An axis as the coordinate system takes it: the scale's extent, widened, and the breaks and
  # minor breaks an axis showing that extent draws, which ggplot2's view scale computes on the
  # same extent.
  defp axis(scale) do
    extent = Scale.dimension(scale)
    breaks = Scale.breaks(scale, extent)
    {extent, breaks, Scale.minor_breaks(scale, breaks, extent)}
  end

  # Evaluation keeps only the mapped aesthetics, so the panel the facet assigned is carried across
  # by name: it is the one raw column every layer keeps. The columns come out in the order ggplot2
  # evaluates them (`Plot.mapping_order/2`): the layer's own aesthetics, then those it takes from
  # the plot's mapping, each mapping's `x` and `y` first and its others in name order; grouping
  # keys on the discrete ones in that order, so a discrete alpha mapped with `x` groups within each
  # `x`, and a fill a layer maps over the plot's `x` groups by fill first, as ggplot2 numbers its
  # groups.
  defp evaluate(paneled_data, plot, layer) do
    mapping = Plot.computed_mapping(plot, layer)

    renames =
      plot
      |> Plot.mapping_order(layer)
      |> Enum.map(fn aesthetic -> {aesthetic, Map.fetch!(mapping, aesthetic)} end)

    panels = DataFrame.pull(paneled_data, :panel)

    paneled_data
    |> DataFrame.select(renames)
    |> DataFrame.put(:panel, panels)
  end

  # Which of the axis's scales each panel uses, by panel: the layout's `:scale_x` or `:scale_y`,
  # ggplot2's `SCALE_X` and `SCALE_Y`. A fixed axis routes every panel to one scale, a free one each
  # panel to its own.
  defp routes(layout, family) do
    panels = DataFrame.pull(layout, :panel)
    scale_ids = DataFrame.pull(layout, scale_column(family))

    panels
    |> Enum.zip(scale_ids)
    |> Map.new()
  end

  # One untrained scale per scale id the layout gives this axis, every one of the kind the axis's
  # columns need, as ggplot2 adds its default scales before transforming anything and clones the
  # axis's scale for each scale id.
  defp add_scales(kind, routes) do
    untrained = Scale.new(kind)

    routes
    |> Map.values()
    |> Map.new(fn scale_id -> {scale_id, untrained} end)
  end

  # Each scale folds in, from every layer's columns on its axis, the values in the rows of the
  # panels that use it, as ggplot2's `train_position()` trains each panel scale on its panels.
  defp train(scales, routes, family, layer_data) do
    Map.new(scales, fn {scale_id, untrained} ->
      trained =
        layer_data
        |> family_columns(family)
        |> Enum.reduce(untrained, fn {frame, name}, scale ->
          Scale.train(scale, values_on(frame, name, routes, scale_id))
        end)

      {scale_id, trained}
    end)
  end

  # Each scale reset and trained again on every layer's columns on its axis: ggplot2's
  # `reset_scales()` and second `train_position()`.
  defp retrain(scales, routes, family, layer_data) do
    scales
    |> Map.new(fn {scale_id, scale} -> {scale_id, Scale.reset(scale)} end)
    |> train(routes, family, layer_data)
  end

  # The column's values in the rows whose panel uses the scale `scale_id`.
  defp values_on(frame, name, routes, scale_id) do
    panels = DataFrame.pull(frame, :panel)
    values = DataFrame.pull(frame, name)

    for {panel, value} <- Enum.zip(panels, values),
        Map.fetch!(routes, panel) == scale_id,
        do: value
  end

  defp scale_column(:x), do: :scale_x
  defp scale_column(:y), do: :scale_y

  # Every column of every layer that belongs to the axis, in layer order.
  defp family_columns(layer_data, family) do
    for frame <- layer_data,
        name <- DataFrame.names(frame),
        Aesthetics.family(name) == family,
        do: {frame, name}
  end

  # An axis has one scale, so every column on it must be a type some scale can place, and all of
  # one kind; the first column decides, and an axis no layer maps is continuous, as ggplot2's is.
  # Whether an axis of a scale of `kind` is discrete or continuous, all a geom is told: a date
  # scale is continuous, as ggplot2's geoms see a date axis as not discrete.
  defp discreteness(:discrete), do: :discrete
  defp discreteness(_continuous), do: :continuous

  defp axis_kind(plot, family) do
    case mapped_columns(plot, fn aesthetic -> Aesthetics.family(aesthetic) == family end) do
      [] -> :continuous
      columns -> checked_kind(columns, "an axis has one scale")
    end
  end

  # The kind of scale each aesthetic other than position needs, for those a layer maps: as an
  # axis's, every column of it must be a type some scale can map, and all of one kind, the first
  # deciding, as ggplot2 adds a scale for the first layer's and refuses a column it cannot map.
  defp non_position_kinds(plot) do
    for aesthetic <- Scale.non_position_aesthetics(),
        columns = mapped_columns(plot, fn mapped -> mapped == aesthetic end),
        columns != [],
        into: %{},
        do: {aesthetic, checked_kind(columns, "an aesthetic has one scale")}
  end

  # Each column a layer maps to one of the aesthetics `selected?` chooses, in layer order, with what
  # a refusal names: the layer's index, the aesthetic, the column as the data names it, its type and
  # the kind of scale that type needs. The plot's mappings are read rather than the evaluated
  # frames, so a refusal can name each column as the data names it.
  defp mapped_columns(plot, selected?) do
    dtypes = DataFrame.dtypes(plot.data)
    layers = Enum.reverse(plot.reversed_layers)

    for {layer, index} <- Enum.with_index(layers),
        mapping = Plot.computed_mapping(plot, layer),
        {aesthetic, column} <- Enum.sort(mapping),
        selected?.(aesthetic),
        dtype = Map.fetch!(dtypes, column),
        do: {index, aesthetic, column, dtype, Scale.kind(dtype, aesthetic)}
  end

  defp checked_kind(
         [{_index, _aesthetic, _column, _dtype, first_kind} = first | _rest] = columns,
         one_scale
       ) do
    Enum.each(columns, fn column -> check_column(column, first, one_scale) end)
    first_kind
  end

  defp check_column({_index, _aesthetic, _column, _dtype, :none} = column, _first, _one_scale),
    do: raise(ArgumentError, unplaceable_message(column))

  defp check_column(
         {_index, _aesthetic, _column, _dtype, kind},
         {_first_index, _first_aesthetic, _first_column, _first_dtype, kind},
         _one_scale
       ),
       do: :ok

  defp check_column(column, first, one_scale),
    do: raise(ArgumentError, kind_conflict_message(column, first, one_scale))

  defp unplaceable_message({index, aesthetic, column, dtype, _kind}) do
    "the layer at index #{index} maps #{inspect(aesthetic)} to #{inspect(column)}, a " <>
      "#{inspect(dtype)} column, which no scale can place yet"
  end

  defp kind_conflict_message({index, aesthetic, column, _dtype, kind}, first, one_scale) do
    {first_index, first_aesthetic, first_column, _first_dtype, first_kind} = first

    "the layer at index #{index} maps #{inspect(aesthetic)} to #{inspect(column)}, a #{kind} " <>
      "column, but the layer at index #{first_index} maps #{inspect(first_aesthetic)} to " <>
      "#{inspect(first_column)}, a #{first_kind} one; #{one_scale}"
  end

  # Replaces each x-family and y-family column with what `scale_function` (a transformation or a
  # mapping) makes of its values, each row's on the scale its panel uses: ggplot2's `scale_apply()`.
  defp through_scales(frame, x_axis, y_axis, scale_function) do
    frame
    |> DataFrame.names()
    |> Enum.reduce(frame, fn name, scaled ->
      case Aesthetics.family(name) do
        :x -> through_scale(scaled, name, x_axis, scale_function)
        :y -> through_scale(scaled, name, y_axis, scale_function)
        :none -> scaled
      end
    end)
  end

  # Each scale takes its own rows' values, in their order, and what it makes of them goes back in
  # row order.
  defp through_scale(frame, name, {scales, routes}, scale_function) do
    scale_ids =
      frame
      |> DataFrame.pull(:panel)
      |> Enum.map(fn panel -> Map.fetch!(routes, panel) end)

    values = DataFrame.pull(frame, name)

    results =
      scale_ids
      |> Enum.zip(values)
      |> Enum.group_by(fn {scale_id, _value} -> scale_id end, fn {_scale_id, value} -> value end)
      |> Map.new(fn {scale_id, scale_values} ->
        scale = Map.fetch!(scales, scale_id)
        {scale_id, scale_function.(scale, scale_values)}
      end)

    {placed, _none_left} =
      Enum.map_reduce(scale_ids, results, fn scale_id, remaining ->
        [result | rest] = Map.fetch!(remaining, scale_id)
        {result, Map.put(remaining, scale_id, rest)}
      end)

    DataFrame.put(frame, name, placed)
  end
end
