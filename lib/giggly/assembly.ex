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
  #   9. has each layer's geom (`Giggly.Geom`) give each row the extent it is drawn over, such as a
  #      bar's edges;
  #  10. moves each layer's marks by its position (`Giggly.Position`);
  #  11. resets each scale and trains it again on every layer's columns on its axis, where the
  #      marks now stand, a discrete scale keeping its levels and widening its continuous range;
  #  12. has the plot's coordinate system (`Giggly.Coord`) build each panel's params from the
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
  # table; the trained scales, by scale id; the plot's coordinate system, which rendering hands each
  # geom and guide unread, each panel's params, by panel id, whether panels are clipped, and the
  # aspect ratio every panel keeps, `:none` when they take the shape the drawing leaves; each
  # axis's title, the name of the column the first layer to map the axis's aesthetic maps it to
  # (ggplot2's `setup_plot_labels()`); and the name of the plot's theme, passed on for rendering,
  # the only stage that reads a theme so far. The data's own column names appear only as titles.
  #
  # Nothing outside Giggly calls this module: the functions in `Giggly` take a plot and run it here.

  # The assembly reads a plot and hands each stage its input; what it may call is the plot, the
  # data frame, the aesthetic vocabulary (which columns are x and which y) and the stages, each
  # named as it arrives.
  use Boundary,
    deps: [
      Giggly.Aesthetics,
      Giggly.Coord,
      Giggly.DataFrame,
      Giggly.Facet,
      Giggly.Geom,
      Giggly.Group,
      Giggly.Plot,
      Giggly.Position,
      Giggly.Scale,
      Giggly.Stat
    ],
    exports: []

  alias Giggly.{Aesthetics, Coord, DataFrame, Facet, Geom, Group, Plot, Position, Scale, Stat}

  @enforce_keys [
    :layer_data,
    :layer_geoms,
    :layout,
    :x_scales,
    :y_scales,
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
  panel; the plot's coordinate system, each panel's params keyed by panel id, whether panels
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
          coord: struct(),
          panel_params: %{optional(pos_integer()) => Coord.panel_params()},
          clip: Coord.clip(),
          aspect_ratio: Coord.aspect(),
          guide_titles: %{x: String.t() | :none, y: String.t() | :none},
          theme: Plot.theme()
        }

  # Assembles `plot`, running the stages in order.
  #
  # The facet first gives each row of the plot's data its panel. Then each layer's mapping is laid
  # over the plot's (the layer's column wins), chooses and renames the data's columns, the panel
  # column is carried across, and `Giggly.Group.add/2` adds the `:group` column. The aesthetics come
  # out in name order, since a mapping is a map and has no written order to keep, followed by
  # `:panel` and `:group`, as ggplot2 orders them. Each axis then gets its scale, and every layer's
  # columns in that axis's family are put through the scale's transformation, trained on, and mapped
  # to their positions. Each layer's stat then computes on its table, and its position moves the
  # marks. Last, the plot's coordinate system builds each panel's params from the extents of the
  # scales the layout gives that panel and the breaks and minor breaks each axis draws on its
  # extent. Each axis is
  # titled by the first layer, in the order added, whose mapping laid over the plot's maps `:x` (or
  # `:y`); a later layer never retitles it, and an axis no layer maps has no title.
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
    untrained_x_scales = add_scales(:x, plot, x_routes)
    untrained_y_scales = add_scales(:y, plot, y_routes)

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
        set_up = Geom.setup_data(Plot.layer_geom(layer), computed)
        Position.compute_layer(Plot.layer_position(layer), set_up)
      end)

    # ggplot2 resets the position scales and trains them again on the marks where they now stand,
    # so an axis covers every bar's edges; it maps the positions again after, which changes nothing
    # here, since a scale maps a position to itself.
    final_x_scales = retrain(x_scales, x_routes, :x, layer_data)
    final_y_scales = retrain(y_scales, y_routes, :y, layer_data)

    panel_params = panel_params(coord, layout, final_x_scales, final_y_scales)

    %__MODULE__{
      layer_data: layer_data,
      layer_geoms: Enum.map(layers, &Plot.layer_geom/1),
      layout: layout,
      x_scales: final_x_scales,
      y_scales: final_y_scales,
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
  # aesthetic maps it to, through the layer's computed mapping, or `:none` when no layer maps it. It
  # is ggplot2's `setup_plot_labels()`, where a later layer never replaces an earlier one's label,
  # read as `resolve_label()` reads it, by the scale's first aesthetic. Every point layer maps x and
  # y, so today the first layer maps it whenever there is one; the search past a layer that does not
  # arrives with the first geom that can leave an axis unmapped, and `Map.fetch!/2` fails loudly
  # until it does.
  defp guide_title(_plot, [], _aesthetic), do: :none

  # The plot holds each mapping's column by the name the data gives it, which is the title.
  defp guide_title(plot, [first_layer | _later_layers], aesthetic) do
    plot
    |> Plot.computed_mapping(first_layer)
    |> Map.fetch!(aesthetic)
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
  # by name: it is the one raw column every layer keeps.
  defp evaluate(paneled_data, plot, layer) do
    renames =
      plot
      |> Plot.computed_mapping(layer)
      |> Enum.sort()

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
  defp add_scales(family, plot, routes) do
    untrained =
      plot
      |> scale_kind(family)
      |> Scale.new()

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
  # The plot's mappings are read rather than the evaluated frames, so a refusal can name each
  # column as the data names it.
  defp scale_kind(plot, family) do
    dtypes = DataFrame.dtypes(plot.data)
    layers = Enum.reverse(plot.reversed_layers)

    positions =
      for {layer, index} <- Enum.with_index(layers),
          mapping = Plot.computed_mapping(plot, layer),
          {aesthetic, column} <- Enum.sort(mapping),
          Aesthetics.family(aesthetic) == family,
          dtype = Map.fetch!(dtypes, column),
          do: {index, aesthetic, column, dtype, Scale.kind(dtype)}

    case positions do
      [] ->
        :continuous

      [{_index, _aesthetic, _column, _dtype, first_kind} = first | _rest] ->
        Enum.each(positions, fn position -> check_position(position, first) end)
        first_kind
    end
  end

  defp check_position({_index, _aesthetic, _column, _dtype, :none} = position, _first),
    do: raise(ArgumentError, unplaceable_message(position))

  defp check_position(
         {_index, _aesthetic, _column, _dtype, kind},
         {_first_index, _first_aesthetic, _first_column, _first_dtype, kind}
       ),
       do: :ok

  defp check_position(position, first),
    do: raise(ArgumentError, kind_conflict_message(position, first))

  defp unplaceable_message({index, aesthetic, column, dtype, _kind}) do
    "the layer at index #{index} maps #{inspect(aesthetic)} to #{inspect(column)}, a " <>
      "#{inspect(dtype)} column, which no scale can place yet"
  end

  defp kind_conflict_message({index, aesthetic, column, _dtype, kind}, first) do
    {first_index, first_aesthetic, first_column, _first_dtype, first_kind} = first

    "the layer at index #{index} maps #{inspect(aesthetic)} to #{inspect(column)}, a #{kind} " <>
      "column, but the layer at index #{first_index} maps #{inspect(first_aesthetic)} to " <>
      "#{inspect(first_column)}, a #{first_kind} one; an axis has one scale"
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
