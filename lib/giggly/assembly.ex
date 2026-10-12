defmodule Giggly.Assembly do
  @moduledoc """
  The assembly of a plot: the fixed sequence of stages that turns a `Giggly.Plot`, a description,
  into what is drawn, and the value those stages produce. The name is the middle of Wilkinson's
  three stages of making a graphic (specification, assembly, display); a plot is the
  specification, and drawing is the display.

  The stages run in one fixed order, each adjacent pair a semantic chosen on purpose, and they
  arrive one at a time. Today the assembly:

    1. lays the panels out and assigns each row of the plot's data its panel (`Giggly.Facet`);
    2. evaluates each layer's mapping against that data;
    3. adds each layer's `:group` column (`Giggly.Group`), numbering values in the order a
       discrete scale gives its levels, so group ids follow axis and legend order;
    4. trains one x scale and one y scale per scale id in the layout, over every layer's x-family
       and y-family columns (`Giggly.Scale`), first refusing an axis column no scale can place
       yet, or one whose kind disagrees with the axis's first column: an axis has one scale;
    5. maps those columns to their positions on the scales.

  The result holds one `Giggly.DataFrame` per layer, in the order the layers were added, whose
  columns are named by aesthetic plus `:panel` and `:group`; the layout table; and the trained
  scales, by scale id. The data's own column names do not appear.

  Nothing outside Giggly calls this module: the functions in `Giggly` take a plot and run it here.
  """

  # The assembly reads a plot and hands each stage its input; what it may call is the plot, the
  # data frame, the aesthetic vocabulary (which columns are x and which y) and the stages, each
  # named as it arrives.
  use Boundary,
    deps: [
      Giggly.Aesthetics,
      Giggly.DataFrame,
      Giggly.Facet,
      Giggly.Group,
      Giggly.Plot,
      Giggly.Scale
    ],
    exports: []

  alias Giggly.{Aesthetics, DataFrame, Facet, Group, Plot, Scale}

  @enforce_keys [:layer_data, :layout, :x_scales, :y_scales]
  defstruct @enforce_keys

  @typedoc """
  An assembled plot: each layer's table in the order the layers were added, the layout table, and
  the trained x and y scales keyed by the scale ids the layout gives each panel.
  """
  @type t :: %__MODULE__{
          layer_data: [DataFrame.t()],
          layout: DataFrame.t(),
          x_scales: %{optional(pos_integer()) => Scale.t()},
          y_scales: %{optional(pos_integer()) => Scale.t()}
        }

  @doc """
  Assembles `plot`, running the stages in order.

  The facet first gives each row of the plot's data its panel. Then each layer's mapping is laid
  over the plot's (the layer's column wins), chooses and renames the data's columns, the panel
  column is carried across, and `Giggly.Group.add/2` adds the `:group` column. The aesthetics come
  out in name order, since a mapping is a map and has no written order to keep, followed by
  `:panel` and `:group`, as ggplot2 orders them. Last, each axis's scale is trained on every
  layer's columns in that axis's family, and those columns are mapped to their positions.

  Raises `ArgumentError` when a layer maps an axis to a column no scale can place yet, such as a
  date, or to a column whose kind (continuous or discrete) disagrees with the first column on
  that axis. The message names the layer by its index, counting from 0, the aesthetic, the column
  as the data names it, and its type.
  """
  @spec run(Plot.t()) :: t()
  def run(%Plot{data: data, reversed_layers: reversed_layers} = plot) do
    layout = Facet.layout()
    paneled_data = Facet.assign_panels(data)

    layer_data =
      reversed_layers
      |> Enum.reverse()
      |> Enum.map(fn layer ->
        paneled_data
        |> evaluate(plot, layer)
        |> Group.add(&Scale.level_key/1)
      end)

    x_scales = train(:x, plot, layer_data, layout)
    y_scales = train(:y, plot, layer_data, layout)

    %__MODULE__{
      layer_data: Enum.map(layer_data, fn frame -> map_positions(frame, x_scales, y_scales) end),
      layout: layout,
      x_scales: x_scales,
      y_scales: y_scales
    }
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

  # One scale per scale id the layout gives this axis. Every panel shares one scale while there is
  # one panel, so the match below holds; routing rows to several scales arrives with free scales,
  # where the match fails loudly until it does.
  defp train(family, plot, layer_data, layout) do
    [scale_id] =
      layout
      |> DataFrame.pull(scale_column(family))
      |> Enum.uniq()

    untrained =
      plot
      |> scale_kind(family)
      |> Scale.new()

    scale =
      layer_data
      |> family_columns(family)
      |> Enum.reduce(untrained, fn {frame, name}, scale ->
        Scale.train(scale, DataFrame.pull(frame, name))
      end)

    %{scale_id => scale}
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

  defp map_positions(frame, x_scales, y_scales) do
    frame
    |> DataFrame.names()
    |> Enum.reduce(frame, fn name, mapped ->
      case Aesthetics.family(name) do
        :x -> map_column(mapped, name, x_scales)
        :y -> map_column(mapped, name, y_scales)
        :none -> mapped
      end
    end)
  end

  defp map_column(frame, name, scales) do
    [scale] = Map.values(scales)
    positions = Scale.map(scale, DataFrame.pull(frame, name))
    DataFrame.put(frame, name, positions)
  end
end
