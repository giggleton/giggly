defmodule Giggly.Assembly do
  @moduledoc """
  The assembly of a plot: the fixed sequence of stages that turns a `Giggly.Plot`, a description,
  into what is drawn, and the value those stages produce. The name is the middle of Wilkinson's
  three stages of making a graphic (specification, assembly, display); a plot is the
  specification, and rendering and drawing it are the display.

  The stages run in one fixed order, each adjacent pair a semantic chosen on purpose, and they
  arrive one at a time. Today the assembly:

    1. lays the panels out and assigns each row of the plot's data its panel (`Giggly.Facet`);
    2. evaluates each layer's mapping against that data;
    3. adds each layer's `:group` column (`Giggly.Group`), numbering values in the order a
       discrete scale gives its levels, so group ids follow axis and legend order;
    4. adds one x scale and one y scale per scale id in the layout (`Giggly.Scale`), of the kind
       the axis's columns need, first refusing an axis column no scale can place yet, or one whose
       kind disagrees with the axis's first column: an axis has one scale;
    5. puts every layer's x-family and y-family columns through their scale's transformation;
    6. trains each scale over those columns;
    7. maps them to their positions on the scales;
    8. computes each layer's stat (`Giggly.Stat`) on its table;
    9. moves each layer's marks by its position (`Giggly.Position`);
   10. has the plot's coordinate system (`Giggly.Coord`) build each panel's params from the
       extents of the panel's scales.

  The result holds one `Giggly.DataFrame` per layer, in the order the layers were added, whose
  columns are named by aesthetic plus `:panel` and `:group`, with each layer's geom; the layout
  table; the trained scales, by scale id; and each panel's params, by panel id. The data's own
  column names do not appear.

  Nothing outside Giggly calls this module: the functions in `Giggly` take a plot and run it here.
  """

  # The assembly reads a plot and hands each stage its input; what it may call is the plot, the
  # data frame, the aesthetic vocabulary (which columns are x and which y) and the stages, each
  # named as it arrives.
  use Boundary,
    deps: [
      Giggly.Aesthetics,
      Giggly.Coord,
      Giggly.DataFrame,
      Giggly.Facet,
      Giggly.Group,
      Giggly.Plot,
      Giggly.Position,
      Giggly.Scale,
      Giggly.Stat
    ],
    exports: []

  alias Giggly.{Aesthetics, Coord, DataFrame, Facet, Group, Plot, Position, Scale, Stat}

  @enforce_keys [:layer_data, :layer_geoms, :layout, :x_scales, :y_scales, :panel_params]
  defstruct @enforce_keys

  @typedoc """
  An assembled plot: each layer's table and the name of the geom that draws it, in the order the
  layers were added; the layout table; the trained x and y scales keyed by the scale ids the layout
  gives each panel; and each panel's params, keyed by panel id.
  """
  @type t :: %__MODULE__{
          layer_data: [DataFrame.t()],
          layer_geoms: [atom()],
          layout: DataFrame.t(),
          x_scales: %{optional(pos_integer()) => Scale.t()},
          y_scales: %{optional(pos_integer()) => Scale.t()},
          panel_params: %{optional(pos_integer()) => Coord.panel_params()}
        }

  @doc """
  Assembles `plot`, running the stages in order.

  The facet first gives each row of the plot's data its panel. Then each layer's mapping is laid
  over the plot's (the layer's column wins), chooses and renames the data's columns, the panel
  column is carried across, and `Giggly.Group.add/2` adds the `:group` column. The aesthetics come
  out in name order, since a mapping is a map and has no written order to keep, followed by
  `:panel` and `:group`, as ggplot2 orders them. Each axis then gets its scale, and every layer's
  columns in that axis's family are put through the scale's transformation, trained on, and mapped
  to their positions. Each layer's stat then computes on its table, and its position moves the
  marks. Last, the plot's coordinate system builds each panel's params from the extents of the
  scales the layout gives that panel.

  Raises `ArgumentError` when a layer maps an axis to a column no scale can place yet, such as a
  date, or to a column whose kind (continuous or discrete) disagrees with the first column on
  that axis. The message names the layer by its index, counting from 0, the aesthetic, the column
  as the data names it, and its type.
  """
  @spec run(Plot.t()) :: t()
  def run(%Plot{data: data, facet: facet, coord: coord, reversed_layers: reversed_layers} = plot) do
    layout = Facet.layout(facet)
    paneled_data = Facet.assign_panels(data, facet)
    layers = Enum.reverse(reversed_layers)

    grouped_data =
      Enum.map(layers, fn layer ->
        paneled_data
        |> evaluate(plot, layer)
        |> Group.add(&Scale.level_key/1)
      end)

    untrained_x_scales = add_scales(:x, plot, layout)
    untrained_y_scales = add_scales(:y, plot, layout)

    transformed_data =
      Enum.map(grouped_data, fn frame ->
        through_scales(frame, untrained_x_scales, untrained_y_scales, &Scale.transform/2)
      end)

    x_scales = train(untrained_x_scales, :x, transformed_data)
    y_scales = train(untrained_y_scales, :y, transformed_data)

    layer_data =
      layers
      |> Enum.zip(transformed_data)
      |> Enum.map(fn {layer, frame} ->
        frame
        |> through_scales(x_scales, y_scales, &Scale.map/2)
        |> Stat.compute(Plot.layer_stat(layer))
        |> Position.compute(Plot.layer_position(layer))
      end)

    %__MODULE__{
      layer_data: layer_data,
      layer_geoms: Enum.map(layers, &Plot.layer_geom/1),
      layout: layout,
      x_scales: x_scales,
      y_scales: y_scales,
      panel_params: panel_params(coord, layout, x_scales, y_scales)
    }
  end

  # Each panel's params, from the extents of the scales its layout row names: ggplot2's
  # `setup_panel_params()`, after the positions have run.
  defp panel_params(coord, layout, x_scales, y_scales) do
    [:panel, :scale_x, :scale_y]
    |> Enum.map(fn name -> DataFrame.pull(layout, name) end)
    |> Enum.zip()
    |> Map.new(fn {panel, scale_x_id, scale_y_id} ->
      x_dimension =
        x_scales
        |> Map.fetch!(scale_x_id)
        |> Scale.dimension()

      y_dimension =
        y_scales
        |> Map.fetch!(scale_y_id)
        |> Scale.dimension()

      {panel, Coord.panel_params(coord, x_dimension, y_dimension)}
    end)
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

  # One untrained scale per scale id the layout gives this axis, of the kind its columns need, as
  # ggplot2 adds its default scales before transforming anything. Every panel shares one scale
  # while there is one panel, so the match below holds; routing rows to several scales arrives
  # with free scales, where the match fails loudly until it does.
  defp add_scales(family, plot, layout) do
    [scale_id] =
      layout
      |> DataFrame.pull(scale_column(family))
      |> Enum.uniq()

    untrained =
      plot
      |> scale_kind(family)
      |> Scale.new()

    %{scale_id => untrained}
  end

  # Each scale folds in every layer's columns on its axis; `add_scales/3` gives an axis one scale.
  defp train(scales, family, layer_data) do
    Map.new(scales, fn {scale_id, untrained} ->
      trained =
        layer_data
        |> family_columns(family)
        |> Enum.reduce(untrained, fn {frame, name}, scale ->
          Scale.train(scale, DataFrame.pull(frame, name))
        end)

      {scale_id, trained}
    end)
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
  # mapping) makes of its values on the axis's scale.
  defp through_scales(frame, x_scales, y_scales, scale_function) do
    frame
    |> DataFrame.names()
    |> Enum.reduce(frame, fn name, scaled ->
      case Aesthetics.family(name) do
        :x -> through_scale(scaled, name, x_scales, scale_function)
        :y -> through_scale(scaled, name, y_scales, scale_function)
        :none -> scaled
      end
    end)
  end

  defp through_scale(frame, name, scales, scale_function) do
    [scale] = Map.values(scales)
    DataFrame.put(frame, name, scale_function.(scale, DataFrame.pull(frame, name)))
  end
end
