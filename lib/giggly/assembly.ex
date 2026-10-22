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
  #   1. lays the panels out from the plot's data and every layer's table, and assigns each row of
  #      each layer's table its panel, repeating the rows of a table that lacks a column the facet
  #      splits on in each panel they fit (`Giggly.Facet`);
  #   2. evaluates each layer's mapping against its table (`Giggly.Mapping`): a column, an
  #      expression computed in each row, or a constant in every row, an after_stat left until its
  #      stat has run;
  #   3. adds each layer's `:group` column (`Giggly.Group`), numbering values in the order a
  #      discrete scale gives its levels, so group ids follow axis and legend order;
  #   4. adds one x scale and one y scale per scale id in the layout (`Giggly.Scale`), of the kind
  #      the axis's columns need, first refusing an axis column no scale can place yet, or one whose
  #      kind disagrees with the axis's first column: an axis has one scale;
  #   5. puts every layer's x-family and y-family columns through their scale's transformation;
  #   6. trains each scale over those columns, in the rows of the panels that use it;
  #   7. maps them to their positions, each row on its panel's scale;
  #   8. computes each layer's stat (`Giggly.Stat`) on its table;
  #   9. puts into each aesthetic the layer maps to an after_stat its value, evaluated against the
  #      stat's output, and into each it leaves unmapped the computed column its stat names for it,
  #      as a count into y, each on an axis checked against the axis's scale and put through it;
  #  10. puts into every row each position a layer sets, as a rectangle's corners, then has each
  #      layer's geom (`Giggly.Geom`) give each row the extent it is drawn over, such as a bar's
  #      edges, told whether each axis is discrete, which decides a bar's orientation;
  #  11. puts into every row each aesthetic a layer's position reads, such as nudging's `nudge_x`,
  #      the value the layer sets or else the position's default, as ggplot2's `use_defaults()`
  #      for a position does, then moves the layer's marks by its position (`Giggly.Position`);
  #  12. resets each scale and trains it again on every layer's columns on its axis, where the
  #      marks now stand, a discrete scale keeping its levels and widening its continuous range;
  #  13. adds a scale for each aesthetic other than position that a layer maps (`alpha`, `color`,
  #      `fill`), of the kind its columns need, those evaluated before the stats and then those
  #      computed after, trains it on every layer's column of that
  #      aesthetic, and maps each column through it, as ggplot2 trains and maps its non-position
  #      scales once the positions are final;
  #      it then builds the legends: each such scale's, drawn by the guide `guides/2` sets for its
  #      aesthetic or else the one the scale names, none for `:none`, a key for each break,
  #      labelled, with the value it maps to, last first for a legend reversed, in the order of
  #      the aesthetics' names, one with the title and labels of an earlier merged into it, as
  #      ggplot2 merges guides that would read alike; each legend
  #      is drawn by the geom of each layer that maps one of its aesthetics and can use it, with
  #      what that layer sets, in the keys whose values the layer's table holds, and a legend no
  #      layer can draw is dropped;
  #  14. puts each aesthetic a layer sets, such as `alpha`, into every row of its table, last, as
  #      ggplot2's geoms apply a layer's `aes_params` once every scale has run: one value in every
  #      row, or an annotation's list, one value per row, refused where a facet has repeated the
  #      annotation's rows across its panels, as ggplot2 refuses it;
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
  # columns are named by aesthetic plus `:panel` and `:group`, with each layer's geom and the rows
  # it draws, the frame without the aesthetics other than position the layer carries unused; the
  # layout table; the trained scales, by scale id; the trained scale of each aesthetic other than position
  # that a layer maps, by aesthetic, and the legend each gives; the plot's coordinate system, which rendering hands each
  # geom and guide unread, each panel's params, by panel id, whether panels are clipped, and the
  # aspect ratio every panel keeps, `:none` when they take the shape the drawing leaves; each
  # axis's title, the text of what the first layer to map the axis's aesthetic maps it to
  # (ggplot2's `setup_plot_labels()`); and the name of the plot's theme, passed on for rendering,
  # the only stage that reads a theme so far. The data's own column names appear only as titles.
  #
  # Nothing outside Giggly calls this module: the functions in `Giggly` take a plot and run it here.

  # The assembly reads a plot and hands each stage its input; what it may call is the plot, the
  # data frame, the aesthetic vocabulary (which columns are x and which y), the mapping grammar,
  # which evaluates and titles each mapping value, and the stages, each named as it arrives; the
  # guides it lists only to build the kind of guide a scale names.
  use Boundary,
    deps: [
      Giggly.Aesthetics,
      Giggly.Coord,
      Giggly.DataFrame,
      Giggly.Facet,
      Giggly.Geom,
      Giggly.Group,
      Giggly.Guide,
      Giggly.Mapping,
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
    Mapping,
    Plot,
    Position,
    Scale,
    Stat
  }

  @enforce_keys [
    :layer_data,
    :drawn_data,
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
    :plot_labels,
    :theme
  ]
  defstruct @enforce_keys

  @typedoc """
  An assembled plot: each layer's table, the rows its geom draws, the table without the aesthetics
  the layer carries unused, and the geom that draws them, in the order the layers were added; the
  layout table; the trained x and y scales keyed by the scale ids the layout gives each panel; the
  trained scale of each aesthetic other than position that a layer maps, by aesthetic;
  each legend those scales give, its title, its keys and the geoms that draw them; the plot's
  coordinate system, each panel's params keyed by panel id, whether panels
  are clipped to their edges, and the aspect ratio, height over width, every panel keeps, `:none`
  for none; the title of each aesthetic's guide, the x and y axes' so far,
  `:none` for an axis no layer maps; the plot's own labels, its title, subtitle, caption and tag,
  `:none` for each it has not; and the name of the plot's theme, which rendering resolves.
  """
  @type t :: %__MODULE__{
          layer_data: [DataFrame.t()],
          drawn_data: [DataFrame.t()],
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
          plot_labels: %{
            title: String.t() | :none,
            subtitle: String.t() | :none,
            caption: String.t() | :none,
            tag: String.t() | :none
          },
          theme: Plot.theme()
        }

  @typedoc """
  A legend for one or more aesthetics other than position, those whose scales give the same kind of
  guide, title and labels, in name order: the guide that draws it, a struct of its kind, as the
  first aesthetic's scale names it (`Giggly.Guide`); its title, the label `Plot.labs/2` sets for
  the first aesthetic, or else the title an axis would take from the layers' mappings (a column's
  name, an expression's text, a constant's aesthetic name as a fallback), `:none` for none;
  a key for each of its scales' breaks, the break's label, the break
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
          required(:title) => String.t() | :none,
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
  # The facet first lays the panels out from the plot's data and each layer's table, the layer's own
  # or else the plot's, and gives each row of a layer's table its panel. Then each layer's mapping
  # is laid over the plot's (the layer's column wins), chooses and renames its table's columns, the
  # panel column is carried across, and `Giggly.Group.add/2` adds the `:group` column. The
  # aesthetics come out in the order ggplot2 evaluates them, the layer's own before those it takes
  # from the plot, each mapping's `:x` and `:y` first, as ggplot2's `aes()` takes them, then the
  # rest in name order, since a mapping is a map and has no written order to keep, followed by
  # `:panel` and `:group`, as ggplot2 orders them. Each axis then gets its scale, and every layer's
  # columns in that axis's family are put through the scale's transformation, trained on, and mapped
  # to their positions. Each layer's stat then computes on its table, and its position moves the
  # marks, once every row holds the aesthetics the position reads, and each aesthetic a layer sets
  # is put into every row of its table. Last, the plot's coordinate system builds each panel's
  # params from the extents of the scales the layout gives that panel and the breaks and minor
  # breaks each axis draws on its extent. Each axis is titled by the label `Plot.labs/2` sets for
  # it, or else by the first layer, in the order added, an annotation never, whose mapping laid over
  # the plot's maps `:x` (or `:y`); a later layer never retitles it, and an axis no layer maps has
  # no title. The plot's own labels are carried for drawing.
  #
  # Raises `ArgumentError` when a layer maps an axis to a column no scale can place yet, such as a
  # time, to a column whose kind (continuous, discrete or date) disagrees with the first column on
  # that axis, or to one the plot's scale for the axis does not take. The message names the layer
  # by its index, counting from 0, the aesthetic, the column as the data names it, and its type.
  # Raises it too for an annotation given a list of values for an aesthetic under a facet that
  # repeats its rows across several panels, naming the layer and the aesthetic.
  # No expansion, as ggplot2's stats read an axis's `dimension()`.
  @unexpanded [mult: {0.0, 0.0}, add: {0.0, 0.0}]

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
    layers = Enum.reverse(reversed_layers)
    tables = Enum.map(layers, fn layer -> Plot.layer_table(plot, layer) end)
    layout = Facet.layout(facet, [data | tables], &Scale.level_key/1)

    grouped_data =
      Enum.zip_with(layers, tables, fn layer, table ->
        facet
        |> Facet.assign_panels(table, layout)
        |> evaluate(plot, layer)
        |> Group.add(&Scale.level_key/1)
      end)

    x_routes = routes(layout, :x)
    y_routes = routes(layout, :y)
    x_scale = position_scale(plot, grouped_data, :x)
    y_scale = position_scale(plot, grouped_data, :y)
    scale_kinds = %{x: Scale.kind_of(x_scale), y: Scale.kind_of(y_scale)}
    axis_kinds = Map.new(scale_kinds, fn {axis, kind} -> {axis, discreteness(kind)} end)

    untrained_x_scales = add_scales(x_scale, x_routes)
    untrained_y_scales = add_scales(y_scale, y_routes)

    transformed_data =
      Enum.map(grouped_data, fn frame ->
        through_scales(
          frame,
          {untrained_x_scales, x_routes},
          {untrained_y_scales, y_routes},
          &Scale.transform/2
        )
      end)

    x_scales = train(untrained_x_scales, x_routes, :x, transformed_data, &Scale.train/2)
    y_scales = train(untrained_y_scales, y_routes, :y, transformed_data, &Scale.train/2)

    axes = %{x: {x_scales, x_routes}, y: {y_scales, y_routes}}
    panel_axes = stat_axes(axes)

    statistic_data =
      layers
      |> Enum.with_index()
      |> Enum.zip_with(transformed_data, fn {layer, index}, frame ->
        stat = Plot.layer_stat(layer)
        mapped = through_scales(frame, axes.x, axes.y, &Scale.map/2)
        computed = Stat.compute_layer(stat, mapped, panel_axes)
        map_statistic(computed, {plot, layer, index}, scale_kinds, axes)
      end)

    non_position_columns = non_position_columns(plot, grouped_data, statistic_data)

    layer_data =
      Enum.zip_with(layers, statistic_data, fn layer, statistic ->
        fixed = Plot.layer_fixed(layer)

        set_up =
          Geom.setup_data(Plot.layer_geom(layer), set_positions(statistic, fixed), axis_kinds)

        position = Plot.layer_position(layer)
        defaulted = set_position_aesthetics(set_up, position, fixed)
        Position.compute_layer(position, defaulted)
      end)

    # ggplot2 resets the position scales and trains them again on the marks where they now stand,
    # so an axis covers every bar's edges, then maps the positions again, which leaves out a mark
    # the scale's limits cut, as a bar taller than the y axis's.
    final_x_scales = retrain(x_scales, x_routes, :x, layer_data)
    final_y_scales = retrain(y_scales, y_routes, :y, layer_data)

    positioned_data =
      Enum.map(layer_data, fn frame ->
        through_scales(
          frame,
          {final_x_scales, x_routes},
          {final_y_scales, y_routes},
          &Scale.censor/2
        )
      end)

    non_position_scales =
      Map.new(non_position_columns, fn {aesthetic, first_column} ->
        untrained = non_position_scale(plot, aesthetic, first_column)
        {aesthetic, train_non_position(untrained, aesthetic, positioned_data)}
      end)

    fixed_data =
      layers
      |> Enum.with_index()
      |> Enum.zip_with(positioned_data, fn {layer, index}, frame ->
        frame
        |> map_non_position(non_position_scales)
        |> set_fixed_last(Plot.layer_fixed(layer), index)
      end)

    panel_params = panel_params(coord, layout, final_x_scales, final_y_scales)

    %__MODULE__{
      layer_data: fixed_data,
      drawn_data:
        Enum.zip_with(layers, fixed_data, fn layer, frame -> drawn(frame, plot, layer) end),
      layer_geoms: Enum.map(layers, &Plot.layer_geom/1),
      layout: layout,
      x_scales: final_x_scales,
      y_scales: final_y_scales,
      non_position_scales: non_position_scales,
      legends: legends(non_position_scales, plot, Enum.zip(layers, positioned_data)),
      coord: coord,
      panel_params: panel_params,
      clip: Coord.clip(coord),
      # ggplot2 asks the coordinate system for the first panel's.
      aspect_ratio: Coord.aspect(coord, Map.fetch!(panel_params, 1)),
      guide_titles:
        Map.new([:x, :y], fn aesthetic -> {aesthetic, guide_title(plot, layers, aesthetic)} end),
      plot_labels:
        Map.new([:title, :subtitle, :caption, :tag], fn name ->
          {name, Map.get(plot.labels, name, :none)}
        end),
      theme: theme
    }
  end

  # The rows a layer's geom draws: its table without the aesthetics other than position it takes
  # from the plot's mapping and cannot use, which ride along in its table, and split its groups,
  # but are drawn by nothing, so a geom never reads one as a value the layer sets. A carried
  # position stays, as a geom reads only the positions it uses or works out itself, as a bar its
  # edges.
  defp drawn(frame, plot, layer) do
    accepted = Plot.layer_accepted(layer)

    carried =
      plot
      |> Plot.computed_mapping(layer)
      |> Map.keys()
      |> Enum.reject(fn aesthetic ->
        aesthetic in accepted or Aesthetics.family(aesthetic) != :none
      end)

    kept = for name <- DataFrame.names(frame), name not in carried, do: {name, name}
    DataFrame.select(frame, kept)
  end

  # The title of an aesthetic's guide, an axis's or a legend's: the name of the plot's scale for it,
  # `:none` among them, as ggplot2's scale name wins over every label; else the label `Plot.labs/2`
  # sets for it, `:none` among them, as a plot's labels win in ggplot2's
  # `setup_plot_labels()`; else the title of what the first layer to map the aesthetic to a column
  # or an expression maps it to (`Giggly.Mapping.title/2`), through the layer's computed mapping,
  # `:none` for a closure's, an annotation never, as ggplot2's `annotate()` mapping is unlabelled;
  # failing that, the last layer's fallback: the aesthetic's own name where the layer maps it to a
  # constant, or else the computed column its stat puts into it by default, as `count`; or `:none`.
  # A layer's own title is never replaced by a later layer's and replaces every fallback, which
  # ggplot2 marks as one, read as `resolve_label()` reads it, by the scale's first aesthetic.
  defp guide_title(%Plot{scales: scales, labels: labels} = plot, layers, aesthetic) do
    case Map.fetch(scales, aesthetic) do
      {:ok, %{name: name}} when name != :default -> name
      _no_name -> Map.get_lazy(labels, aesthetic, fn -> data_title(plot, layers, aesthetic) end)
    end
  end

  defp data_title(plot, layers, aesthetic) do
    titles =
      layers
      |> Enum.reject(&Plot.layer_annotation?/1)
      |> Enum.flat_map(fn layer -> layer_title(plot, layer, aesthetic) end)

    case Keyword.fetch(titles, :title) do
      {:ok, title} ->
        title

      :error ->
        titles
        |> Keyword.get_values(:fallback)
        |> List.last(:none)
    end
  end

  # The title `layer` gives `aesthetic`'s guide, as ggplot2's `make_labels()` gives it, its
  # mapping's before its stat's default, which is a fallback; none where it gives neither.
  defp layer_title(plot, layer, aesthetic) do
    mapped =
      plot
      |> Plot.computed_mapping(layer)
      |> Map.fetch(aesthetic)

    defaulted =
      layer
      |> default_mapping()
      |> Map.fetch(aesthetic)

    case {mapped, defaulted} do
      {{:ok, value}, _default} -> [Mapping.title(value, aesthetic)]
      {:error, {:ok, column}} -> [fallback: Atom.to_string(column)]
      {:error, :error} -> []
    end
  end

  defp default_mapping(layer) do
    layer
    |> Plot.layer_stat()
    |> Stat.default_mapping()
  end

  # What `layer` maps (`Plot.computed_mapping/2`) with, in each aesthetic it neither maps nor sets,
  # the after_stat its stat puts there by default, written as a layer would map it, as
  # `size: {:after_stat, [:n]}`: ggplot2 reads `defaults(computed_mapping, stat$default_aes)` to add
  # the scales a stat's output needs and to match a layer with a legend (`matched_aes()`, which
  # leaves out what the layer sets), so a size its stat gives it by default is scaled and drawn in
  # the size legend.
  defp mapping_with_defaults(plot, layer) do
    mapping = Plot.computed_mapping(plot, layer)

    set =
      layer
      |> Plot.layer_fixed()
      |> Map.keys()

    layer
    |> default_mapping()
    |> Map.drop(set)
    |> Map.new(fn {aesthetic, column} ->
      {:ok, value} = Mapping.resolve({:after_stat, [column]})
      {aesthetic, value}
    end)
    |> Map.merge(mapping)
  end

  # The legends the scales of aesthetics other than position give, as ggplot2's guides build them
  # from the trained scales: each scale's, drawn by its guide (`guide/3`), none for `:none`, in the
  # order of the aesthetics' names, a key for each break the scale shows, labelled, with the value
  # it maps to, last first where the guide reverses them, merged into an earlier one with the same
  # kind of guide, title and labels, as ggplot2 merges
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
          guide = guide(Map.get(plot.guides, aesthetic, scale.guide), scale, aesthetic),
          guide != :none,
          breaks = Scale.legend_breaks(scale),
          breaks != [] do
        {values, labels} = Enum.unzip(breaks)
        mapped = Scale.map(scale, values)

        legend = %{
          guide: guide,
          aesthetics: [aesthetic],
          title: guide_title(plot, layers, aesthetic),
          keys:
            Enum.zip_with([labels, values, mapped], fn [label, value, mapped_value] ->
              %{label: label, value: value, values: %{aesthetic => mapped_value}}
            end)
        }

        legend
        |> with_guide_data(scale)
        |> in_key_order()
      end

    scale_legends
    |> Enum.reduce([], &merged/2)
    |> Enum.reverse()
    |> Enum.filter(fn legend ->
      Enum.any?(layers, fn layer -> draws_in?(legend, plot, layer) end)
    end)
    |> Enum.map(fn legend ->
      Map.put(legend, :layers, key_layers(legend, non_position_scales, plot, layers_and_data))
    end)
  end

  # Whether `layer` draws in `legend`: whether it maps one of the legend's aesthetics and can use
  # it. ggplot2 drops a guide no layer draws in, as when every layer takes the aesthetic from the
  # plot's mapping and none can use it.
  defp draws_in?(legend, plot, layer), do: drawn_aesthetics(legend, plot, layer) != []

  # The legend's aesthetics that `layer` maps, from its own mapping or the plot's, or its stat by
  # default, and can use, as ggplot2's `matched_aes()` keeps those the layer's geom knows.
  defp drawn_aesthetics(legend, plot, layer) do
    mapping = mapping_with_defaults(plot, layer)
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

  # The guide that reads `aesthetic`'s scale back, `guide` the one `guides/2` set for it or else
  # the one the scale names, as ggplot2 takes `guides()` over a scale's `guide`: `:none`, or a
  # struct of its kind, as `Plot` turns a position's name into one, a colour bar sampling its
  # colours at 15 values, as ggplot2's gradient form does (`nbin`). A colour bar for a discrete
  # scale, which only `guides/2` can give, the scale functions refusing one, raises, where ggplot2
  # warns and draws none.
  defp guide(:none, _scale, _aesthetic), do: :none
  defp guide(:legend, _scale, _aesthetic), do: %Guide.Legend{}
  defp guide(%Guide.Legend{} = legend, _scale, _aesthetic), do: legend
  defp guide(:colorbar, %Scale.Continuous{}, _aesthetic), do: %Guide.Colorbar{bins: 15}

  defp guide(:colorbar, %Scale.Discrete{}, aesthetic) do
    raise ArgumentError,
          "Plot.guides/2 gives #{aesthetic} a colour bar, which shows a continuous scale, and " <>
            "#{aesthetic}'s scale is discrete; give it :legend"
  end

  # The legend's keys in the order its guide reads them: last break first for a legend reversed,
  # the missing value's key among them, as ggplot2's `extract_params()` turns its key table upside
  # down, before legends merge, so two read alike only in the same order.
  defp in_key_order(%{guide: %Guide.Legend{reverse: true}, keys: keys} = legend),
    do: %{legend | keys: Enum.reverse(keys)}

  defp in_key_order(legend), do: legend

  # The legend with what its kind of guide draws beyond its keys, worked out from the scale: for a
  # colour bar, each key's place up the bar, 0 at the low end of the scale's limits to 1 at their
  # high (ggplot2's `extract_params()` in the gradient form), and its colours (`decor`), sampled at
  # the bar's `bins` values spread evenly over the limits, each its place and colour, as
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
  defp key_layers(%{guide: %Guide.Colorbar{}}, _scales, _plot, _layers_and_data), do: []

  defp key_layers(legend, scales, plot, layers_and_data) do
    discrete =
      scales
      |> Map.fetch!(hd(legend.aesthetics))
      |> Scale.discrete?()

    for {layer, frame} <- layers_and_data,
        mapped = drawn_aesthetics(legend, plot, layer),
        mapped != [] do
      %{
        geom: Plot.layer_geom(layer),
        aesthetics: mapped,
        fixed: Plot.layer_fixed(layer),
        draws: draws(legend.keys, frame, mapped, discrete)
      }
    end
  end

  # Whether a layer draws in each key, as ggplot2's `keep_key_data()` decides: in a continuous
  # scale's key always, whatever its break; in a discrete key, a factor's number among them, only
  # where one of the layer's columns of the aesthetics it maps holds the break, a value matched as
  # the scale matches it (`Scale.Discrete.key/1`, so a limit of `4` is a column's `4.0`, as R
  # matches the two as text), `nil` among them, so a layer whose column lacks a level a second
  # layer's column gave the scale leaves that key to the second; in the `NA` key, also where one
  # of those columns holds a value no key shows, one outside the scale's limits or breaks, which
  # the scale maps to its missing value; and in every key where the layer's stat dropped those
  # columns.
  defp draws(keys, _frame, _aesthetics, false), do: Enum.map(keys, fn _key -> true end)

  defp draws(keys, frame, aesthetics, true) do
    case Enum.filter(aesthetics, fn aesthetic -> aesthetic in DataFrame.names(frame) end) do
      [] ->
        Enum.map(keys, fn _key -> true end)

      present ->
        held =
          present
          |> Enum.flat_map(fn aesthetic -> DataFrame.pull(frame, aesthetic) end)
          |> MapSet.new(&Scale.Discrete.key/1)

        shown = MapSet.new(keys, fn key -> Scale.Discrete.key(key.value) end)
        unshown? = not MapSet.subset?(held, shown)

        Enum.map(keys, fn key ->
          MapSet.member?(held, Scale.Discrete.key(key.value)) or
            (is_nil(key.value) and unshown?)
        end)
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
  # scale, as ggplot2's `map_df()` maps them, in name order. A value mapped to `:none`, a scale's
  # `na_value: :none`, is put in as `nil`, the table's missing value, as R's mapped column holds
  # `NA`: a column holds one type, so `:none` beside a colour would be refused, and a geom reads a
  # missing colour as none (`Giggly.Geom.Mark.colors/3`).
  defp map_non_position(frame, scales) do
    scales
    |> Enum.sort()
    |> Enum.reduce(frame, fn {aesthetic, scale}, mapped ->
      if aesthetic in DataFrame.names(mapped),
        do:
          DataFrame.put(
            mapped,
            aesthetic,
            mapped_values(scale, DataFrame.pull(mapped, aesthetic))
          ),
        else: mapped
    end)
  end

  defp mapped_values(scale, values) do
    scale
    |> Scale.map(values)
    |> Enum.map(&missing_for_none/1)
  end

  defp missing_for_none(:none), do: nil
  defp missing_for_none(value), do: value

  # The layer's table with each aesthetic its position reads given, in every row, the value the
  # layer sets for it, or else the position's default, as ggplot2's `use_defaults()` for a position
  # puts them in before the position runs. No layer maps one yet, so a column the plot's mapping
  # carried in under its name is replaced, and moves nothing.
  defp set_position_aesthetics(frame, position, fixed) do
    defaults = Position.default_aesthetics(position)
    set_fixed(frame, Map.merge(defaults, Map.take(fixed, Map.keys(defaults))))
  end

  # The layer's table with each position the layer sets, an x- or y-family aesthetic, given its
  # value in every row just before its geom's setup, as ggplot2's `GeomRect$setup_data()` fills a
  # rectangle's missing corners from the layer's parameters: so the position moves it and the
  # scales, trained again after the position, cover it, as a rectangle's set corners need.
  defp set_positions(frame, fixed) do
    positions =
      Map.filter(fixed, fn {aesthetic, _value} -> Aesthetics.family(aesthetic) != :none end)

    set_fixed(frame, positions)
  end

  # The layer's table with each aesthetic the layer sets given its value, last, as ggplot2's
  # `use_defaults()` applies a layer's `aes_params` after every scale has mapped its aesthetics.
  # An annotation's list holds one value per annotation, so it must hold one per row; under a facet
  # of more than one panel its rows are repeated in each, so it holds too few, and the layer, at
  # `index`, is refused, as ggplot2 fails with "Aesthetics must be either length 1 or the same as
  # the data".
  defp set_fixed_last(frame, fixed, index) do
    rows = DataFrame.row_count(frame)

    Enum.each(fixed, fn {aesthetic, value} -> check_per_row(value, rows, aesthetic, index) end)
    set_fixed(frame, fixed)
  end

  defp check_per_row(values, rows, aesthetic, index)
       when is_list(values) and length(values) != rows do
    raise ArgumentError,
          "the layer at index #{index} sets #{inspect(aesthetic)} to #{length(values)} values, " <>
            "one per annotation, but draws #{rows} rows, its annotations repeated in each panel " <>
            "of the facet; give #{inspect(aesthetic)} one value, as ggplot2 requires one or one " <>
            "per row"
  end

  defp check_per_row(_value, _rows, _aesthetic, _index), do: :ok

  # The layer's table with each aesthetic the layer sets given its value in every row, in name
  # order: one value repeated, or a list holding one per row.
  defp set_fixed(frame, fixed) do
    rows = DataFrame.row_count(frame)

    fixed
    |> Enum.sort()
    |> Enum.reduce(frame, fn {aesthetic, value}, set ->
      DataFrame.put(set, aesthetic, row_values(value, rows))
    end)
  end

  defp row_values(values, _rows) when is_list(values), do: values
  defp row_values(value, rows), do: List.duplicate(value, rows)

  # The stat's output, `frame`, with each aesthetic it gives, as ggplot2's `map_statistic()` puts
  # them in once the stat has run: each the layer maps to an after_stat, in the order ggplot2
  # evaluates them (`Plot.mapping_order/2`), then each it leaves unmapped that its stat names a
  # computed column for (`Stat.default_mapping/1`), in name order, as counting puts its count into
  # y; each replaced where the table has it, or else added after its last column, a factor's
  # declared a category. An after_stat is evaluated against the output as it stands: ggplot2 reads
  # the output back in data units first, but an after_stat reads only the variables a stat
  # documents as computed, and no stat's here is a position. Each on an axis is then checked
  # against the axis's scale and put through it, as ggplot2's `transform_df()` puts it; one on
  # another aesthetic waits for its scale, added after the position, whose transformation is the
  # identity. `layer_at` is the plot, the layer and its index, which a refusal names.
  defp map_statistic(frame, {plot, layer, _index} = layer_at, scale_kinds, axes) do
    mapping = Plot.computed_mapping(plot, layer)

    after_stat =
      plot
      |> Plot.mapping_order(layer)
      |> Enum.map(fn aesthetic -> {aesthetic, Map.fetch!(mapping, aesthetic)} end)
      |> Enum.filter(fn {_aesthetic, value} -> Mapping.stage(value) == :after_stat end)
      |> Enum.map(fn {aesthetic, value} ->
        {{:mapped, value}, evaluated_column(aesthetic, value, frame)}
      end)

    defaulted =
      layer
      |> default_mapping()
      |> Enum.reject(fn {aesthetic, _column} -> Map.has_key?(mapping, aesthetic) end)
      |> Enum.sort()
      |> Enum.map(fn {aesthetic, column} ->
        {{:default, column}, {aesthetic, DataFrame.pull(frame, column)}}
      end)

    after_stat
    |> Enum.concat(defaulted)
    |> Enum.reduce(frame, fn {source, column}, statistic ->
      aesthetic = elem(column, 0)

      statistic
      |> put_column(column)
      |> through_axis(aesthetic, source, {layer_at, scale_kinds}, axes)
    end)
  end

  defp put_column(frame, {name, values}), do: DataFrame.put(frame, name, values)

  defp put_column(frame, {name, values, :category}),
    do: DataFrame.put(frame, name, values, :category)

  # The column of `aesthetic`, computed from the stat's output, put through its axis's scale where
  # it is an x- or y-family aesthetic, each row on the scale its panel uses, once it is checked: an
  # axis's scale is chosen before the stat runs, so the column must be one it takes, numbers on a
  # continuous axis and on a discrete one, where a number is a position among the levels, and
  # dates on a date axis, which its scale turns into numbers. ggplot2 adds a discrete or a date
  # scale for an axis nothing mapped before the stat; here such an axis is continuous, as
  # ggplot2's `add_missing()` makes one, so it takes numbers alone. Numbers on a date axis, such as
  # counting's count, ggplot2 reads as days since 1970-01-01 and warns ("A <numeric> value was
  # passed to a Date scale"), which a pure pipeline cannot, so they are refused. A column of no
  # values is any.
  defp through_axis(statistic, aesthetic, source, {layer_at, scale_kinds}, axes) do
    case Aesthetics.family(aesthetic) do
      :none ->
        statistic

      family ->
        dtype =
          statistic
          |> DataFrame.dtypes()
          |> Map.fetch!(aesthetic)

        scale_kind = Map.fetch!(scale_kinds, family)

        if dtype != :null and Scale.kind(dtype) != statistic_kind(scale_kind),
          do:
            raise(
              ArgumentError,
              unplaced_statistic_message(layer_at, aesthetic, source, dtype, scale_kind)
            )

        through_scale(statistic, aesthetic, Map.fetch!(axes, family), &Scale.transform/2)
    end
  end

  # The kind of column a value computed after the stat must be on an axis of `scale_kind`.
  defp statistic_kind(:date), do: :date
  defp statistic_kind(_continuous_or_discrete), do: :continuous

  defp unplaced_statistic_message({_plot, _layer, index}, aesthetic, source, dtype, scale_kind) do
    family = Aesthetics.family(aesthetic)

    "the layer at index #{index} #{statistic_source(aesthetic, source)}, a #{inspect(dtype)} " <>
      "column, but the #{family} axis's scale, chosen before the stat, " <>
      takes_message(scale_kind)
  end

  defp statistic_source(aesthetic, {:default, column}),
    do: "puts its stat's #{inspect(column)} into #{inspect(aesthetic)}"

  defp statistic_source(aesthetic, {:mapped, value}),
    do: "maps #{inspect(aesthetic)} to #{inspect(value)}"

  defp takes_message(:continuous), do: "is continuous, so it takes numbers"
  defp takes_message(:date), do: "is a date scale, so it takes dates"

  defp takes_message(:discrete),
    do: "is discrete, and takes a value computed after the stat as a number, a position"

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

  # Evaluation keeps only the mapped aesthetics, each the column its value makes from the table
  # (`Giggly.Mapping.evaluate/2`), so the panel the facet assigned is carried across by name: it is
  # the one raw column every layer keeps. The table is the layer's, its own or the plot's, with its
  # panels assigned. The columns come out in the order ggplot2 evaluates them
  # (`Plot.mapping_order/2`): the layer's own aesthetics, then those it takes from the plot's
  # mapping, each mapping's `x` and `y` first and its others in name order; grouping keys on the
  # discrete ones in that order, so a discrete alpha mapped with `x` groups within each `x`, and a
  # fill a layer maps over the plot's `x` groups by fill first, as ggplot2 numbers its groups. Each
  # column is typed as it enters the frame, so an expression whose results mix two kinds is refused
  # there, naming its aesthetic, and a factor's is declared a category. An after_stat is left out,
  # evaluated once the stat has run (`map_statistic/4`), so it takes no part in grouping or in the
  # stat, as ggplot2's `compute_aesthetics()` leaves out calculated aesthetics.
  defp evaluate(paneled_data, plot, layer) do
    mapping = Plot.computed_mapping(plot, layer)

    columns =
      plot
      |> Plot.mapping_order(layer)
      |> Enum.map(fn aesthetic -> {aesthetic, Map.fetch!(mapping, aesthetic)} end)
      |> Enum.filter(fn {_aesthetic, value} -> Mapping.stage(value) == :start end)
      |> Enum.map(fn {aesthetic, value} -> evaluated_column(aesthetic, value, paneled_data) end)

    columns
    |> Enum.concat([{:panel, DataFrame.pull(paneled_data, :panel)}])
    |> DataFrame.new()
  end

  # The column `value` makes from the table it is evaluated against, the layer's or, for an
  # after_stat, the stat's output, under `aesthetic`'s name, declared a category where it is a
  # factor, whose type the frame cannot read from its values.
  defp evaluated_column(aesthetic, value, paneled_data) do
    values = Mapping.evaluate(value, paneled_data)

    case Mapping.dtype(value, paneled_data) do
      :category -> {aesthetic, values, :category}
      _read_from_values -> {aesthetic, values}
    end
  end

  # Which of the axis's scales each panel uses, by panel: the layout's `:scale_x` or `:scale_y`,
  # ggplot2's `SCALE_X` and `SCALE_Y`. A fixed axis routes every panel to one scale, a free one each
  # panel to its own.
  # Each panel's x and y as a stat reads them (`Giggly.Stat.axes/0`), ggplot2's panel scales
  # handed to `compute_layer()`: each axis's extent unwidened, whether it is discrete, and a
  # function through its transformation, built round the panel's scale, so a stat never sees one.
  defp stat_axes(%{x: {x_scales, x_routes}, y: {y_scales, y_routes}}) do
    Map.new(x_routes, fn {panel, x_scale_id} ->
      y_scale_id = Map.fetch!(y_routes, panel)

      {panel,
       %{
         x: stat_axis(Map.fetch!(x_scales, x_scale_id)),
         y: stat_axis(Map.fetch!(y_scales, y_scale_id))
       }}
    end)
  end

  defp stat_axis(scale) do
    %{
      limits: Scale.dimension(scale, @unexpanded),
      discrete: Scale.discrete?(scale),
      transform: fn values -> Scale.transform(scale, values) end
    }
  end

  defp routes(layout, family) do
    panels = DataFrame.pull(layout, :panel)
    scale_ids = DataFrame.pull(layout, scale_column(family))

    panels
    |> Enum.zip(scale_ids)
    |> Map.new()
  end

  # One copy of the axis's untrained scale per scale id the layout gives the axis, as ggplot2 clones
  # the axis's scale for each scale id.
  defp add_scales(untrained, routes) do
    routes
    |> Map.values()
    |> Map.new(fn scale_id -> {scale_id, untrained} end)
  end

  # Each scale folds in, from every layer's columns on its axis, the values in the rows of the
  # panels that use it, as ggplot2's `train_position()` trains each panel scale on its panels.
  # `training` is `Scale.train/2` for the layers' own values, a discrete axis's levels, and
  # `Scale.train_positions/2` once they are positions.
  defp train(scales, routes, family, layer_data, training) do
    Map.new(scales, fn {scale_id, untrained} ->
      trained =
        layer_data
        |> family_columns(family)
        |> Enum.reduce(untrained, fn {frame, name}, scale ->
          training.(scale, values_on(frame, name, routes, scale_id))
        end)

      {scale_id, trained}
    end)
  end

  # Each scale reset and trained again on every layer's columns on its axis: ggplot2's
  # `reset_scales()` and second `train_position()`.
  defp retrain(scales, routes, family, layer_data) do
    scales
    |> Map.new(fn {scale_id, scale} -> {scale_id, Scale.reset(scale)} end)
    |> train(routes, family, layer_data, &Scale.train_positions/2)
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

  # The untrained scale of the axis of `family`: the plot's own scale for the aesthetic, which
  # must take the kind of column the axis's columns need (`Scale.takes?/2`), or else a new scale of
  # that kind, as ggplot2 adds a default scale only for an aesthetic the plot has none for, before
  # transforming anything; on an axis no layer maps, the plot's scale whatever its kind, or a
  # continuous one, as ggplot2's is. A plot's scale that does not take the axis's columns is
  # refused when the plot is run, naming the first column on the axis, as ggplot2 refuses
  # "Discrete value supplied to a continuous scale".
  defp position_scale(%Plot{scales: scales} = plot, layer_frames, family) do
    case {Map.fetch(scales, family), axis_kind(plot, layer_frames, family)} do
      {{:ok, scale}, :unmapped} -> scale
      {{:ok, scale}, kind} -> checked_scale(scale, kind, plot, layer_frames, family)
      {:error, :unmapped} -> Scale.new(:continuous)
      {:error, kind} -> Scale.new(kind)
    end
  end

  defp checked_scale(scale, kind, plot, layer_frames, family) do
    if Scale.takes?(scale, kind) do
      scale
    else
      selected? = fn aesthetic -> Aesthetics.family(aesthetic) == family end
      [first_column | _rest] = mapped_columns(plot, layer_frames, selected?, :start)
      raise ArgumentError, untaken_message(scale, family, first_column)
    end
  end

  # The untrained scale of `aesthetic`, one other than position that a layer maps: the plot's own
  # scale for it, which must take the kind of column its first column needs, or else ggplot2's
  # default for the aesthetic and that kind, as ggplot2 adds a default scale only for an aesthetic
  # the plot has none for. A plot's scale that does not take it is refused when the plot is run,
  # naming that column, as ggplot2 refuses "Continuous value supplied to a discrete scale".
  defp non_position_scale(%Plot{scales: scales}, aesthetic, first_column) do
    {_index, _aesthetic, _column, _dtype, kind} = first_column

    case Map.fetch(scales, aesthetic) do
      {:ok, scale} ->
        if Scale.takes?(scale, kind),
          do: scale,
          else: raise(ArgumentError, untaken_message(scale, aesthetic, first_column))

      :error ->
        Scale.new(kind, aesthetic)
    end
  end

  defp untaken_message(scale, scale_name, {index, aesthetic, column, _dtype, column_kind}) do
    "the plot's #{scale_name} scale is #{scale_description(scale)}, but the layer at index " <>
      "#{index} maps #{inspect(aesthetic)} to #{inspect(column)}, a #{column_kind} column"
  end

  # A scale's kind, and a continuous scale's transformation where it has one, which a refusal names
  # since a continuous scale through the identity takes a date; written into the message as it is.
  defp scale_description(%Scale.Continuous{transform: transform})
       when transform not in [:identity, :date],
       do: "continuous through #{transform}"

  defp scale_description(scale), do: Scale.kind_of(scale)

  # Whether an axis of a scale of `kind` is discrete or continuous, all a geom is told: a date
  # scale is continuous, as ggplot2's geoms see a date axis as not discrete.
  defp discreteness(:discrete), do: :discrete
  defp discreteness(_continuous), do: :continuous

  # The kind of scale the axis's columns need: an axis has one scale, so every column on it must
  # be a type some scale can place, and all of one kind, the first column deciding; `:unmapped`
  # for an axis no layer maps before the stat.
  defp axis_kind(plot, layer_frames, family) do
    selected? = fn aesthetic -> Aesthetics.family(aesthetic) == family end

    case mapped_columns(plot, layer_frames, selected?, :start) do
      [] -> :unmapped
      columns -> checked_kind(columns, "an axis has one scale")
    end
  end

  # The first column of each aesthetic other than position that a layer maps, which decides the
  # kind of scale it needs: as an axis's, every column of it must be a type some scale can map,
  # and all of one kind, the first deciding, as ggplot2 adds a scale for the first layer's and
  # refuses a column it cannot map; and on an aesthetic whose every scale is discrete
  # (`Scale.discrete_only?/1`), none continuous or a date's, as ggplot2's `scale_shape_continuous()`
  # aborts for both.
  # The columns evaluated before the stats come first, read from `layer_frames`, and those computed
  # after, from `statistic_frames`, each in layer order, as ggplot2 adds the scales of every layer's
  # evaluated aesthetics before any stat runs and an after_stat's as its layer's stat is mapped.
  defp non_position_columns(plot, layer_frames, statistic_frames) do
    for aesthetic <- Scale.non_position_aesthetics(),
        selected? = fn mapped -> mapped == aesthetic end,
        evaluated = mapped_columns(plot, layer_frames, selected?, :start),
        computed = mapped_columns(plot, statistic_frames, selected?, :after_stat),
        columns = Enum.concat(evaluated, computed),
        columns != [],
        into: %{} do
      if Scale.discrete_only?(aesthetic), do: Enum.each(columns, &check_discrete/1)
      checked_kind(columns, "an aesthetic has one scale")
      {aesthetic, hd(columns)}
    end
  end

  # A column of an aesthetic whose every scale is discrete, refused unless its type is one a
  # discrete scale takes, or one no scale can place, which `checked_kind/2` refuses.
  defp check_discrete({index, aesthetic, value, dtype, _kind}) do
    if Scale.kind(dtype) in [:continuous, :date] do
      noun = Aesthetics.in_words(aesthetic)

      raise ArgumentError,
            "the layer at index #{index} maps #{inspect(aesthetic)} to #{inspect(value)}, a " <>
              "#{inspect(dtype)} column, but a #{noun} scale is discrete, since #{noun}s have " <>
              "no order; map #{inspect(aesthetic)} to a discrete column or a factor, or " <>
              "#{inspect(value)} to another aesthetic"
    end
  end

  # Each column a layer maps to one of the aesthetics `selected?` chooses, with a value of `stage`
  # (`Mapping.stage/1`), in layer order, with what a refusal names: the layer's index, the
  # aesthetic, the value it is mapped to as the plot holds it, a column by the name its table gives
  # it, its type and the kind of scale that type needs. The type is read from the layer's frame,
  # `layer_frames` in layer order, evaluated or, for an after_stat, the stat's output with it put
  # in, since an expression's is known only once its function has run; the value from the plot's
  # mapping, so a refusal names what the caller mapped rather than the aesthetic's column, or the
  # after_stat its stat maps by default (`mapping_with_defaults/2`).
  defp mapped_columns(plot, layer_frames, selected?, stage) do
    layers_and_frames =
      plot.reversed_layers
      |> Enum.reverse()
      |> Enum.zip(layer_frames)

    for {{layer, frame}, index} <- Enum.with_index(layers_and_frames),
        dtypes = DataFrame.dtypes(frame),
        mapping = mapping_with_defaults(plot, layer),
        {aesthetic, value} <- Enum.sort(mapping),
        selected?.(aesthetic),
        Mapping.stage(value) == stage,
        dtype = Map.fetch!(dtypes, aesthetic),
        do: {index, aesthetic, value, dtype, Scale.kind(dtype, aesthetic)}
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
