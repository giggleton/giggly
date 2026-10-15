defmodule Giggly.Plot do
  @moduledoc """
  The public API for describing a plot. A plot starts from data and a mapping, and layers are
  added with a pipe:

      rows
      |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      |> Giggly.Plot.geom_point()

  A plot describes and runs nothing. The functions in `Giggly` take a finished plot and run it:
  `Giggly.layer_data/2` shows the table a layer computes, as ggplot2's `get_layer_data()` does.

  ## Data

  The data is anything implementing `Table.Reader`: a list of maps, a map of columns, an Explorer
  data frame, a database result. `new/2` reads it once, into a `Giggly.DataFrame` whose column
  names are strings.

  ## Mappings

  A mapping is a map from aesthetic to column, `%{x: :wt, y: :mpg}`. A column is named by an atom
  or a string and compared with the data's column names as a string, so `:wt` and `"wt"` name the
  same column.

  The plot's mapping applies to every layer, and a layer's mapping is laid over it: an aesthetic
  both the plot and layer map takes the layer's column. Which aesthetics a layer can use is checked,
  on the two mappings together, when the layer is added. Whether a column's type suits an axis is
  checked when the plot is run.
  """

  # A plot is a description: it may use the aesthetic vocabulary, the data frame, and the kinds of
  # facet, coordinate system, geom, stat and position, whose structs it builds and whose facts it
  # checks a layer against, and nothing that runs it. The five families' roots are protocols that
  # compute and draw, and `GigglyCredo.Check.PlotRunsNothing` keeps them out of these files, which
  # boundary cannot, since a boundary always exports its root. A layer is read only through
  # `computed_mapping/2`, `layer_geom/1`, `layer_stat/1` and `layer_position/1`, so `Layer` stays
  # private.
  use Boundary,
    deps: [
      Giggly.Aesthetics,
      Giggly.Coord,
      Giggly.DataFrame,
      Giggly.Facet,
      Giggly.Geom,
      Giggly.Position,
      Giggly.Stat
    ],
    exports: []

  alias Giggly.{Aesthetics, Coord, DataFrame, Facet, Geom, Position, Stat}
  alias Giggly.Plot.Layer

  @enforce_keys [:data, :mapping, :facet, :coord, :theme, :reversed_layers]
  defstruct @enforce_keys

  @typedoc "An aesthetic's name, such as `:x`, `:y` or `:color`."
  @type aesthetic :: atom()

  @typedoc """
  A mapping as stored: aesthetic to the name of a column in the plot's data.
  """
  @type mapping :: %{optional(aesthetic()) => String.t()}

  @typedoc "How the plot's rows are split into panels: a facet's struct."
  @type facet :: struct()

  @typedoc "How positions are placed in each panel: a coordinate system's struct."
  @type coord :: struct()

  @typedoc "The look everything but the marks is drawn in."
  @type theme :: :gray

  @typedoc """
  A plot: its data, its mapping, its facet, coordinate system and theme, and its layers newest
  first (each function adds one at the front; they are assembled in the order they were added).
  """
  @type t :: %__MODULE__{
          data: DataFrame.t(),
          mapping: mapping(),
          facet: facet(),
          coord: coord(),
          theme: theme(),
          reversed_layers: [struct()]
        }

  @typedoc "A mapping as written: aesthetic to column, the column named by an atom or a string."
  @type mapping_argument :: %{optional(aesthetic()) => atom() | String.t()}

  defguardp is_column_reference(reference) when is_binary(reference) or is_atom(reference)

  @doc """
  A plot of `data` with the aesthetics in `mapping` applying to every layer.

      iex> plot =
      ...>   Giggly.Plot.new(
      ...>     %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]},
      ...>     %{x: :wt, y: "mpg", colour: :cyl}
      ...>   )
      iex> plot.mapping
      %{x: "wt", y: "mpg", color: "cyl"}
  """
  @spec new(Table.Reader.t(), mapping_argument()) :: t()
  def new(data, mapping \\ %{}) when is_map(mapping) do
    frame = DataFrame.from_table(data)

    %__MODULE__{
      data: frame,
      mapping: resolve(mapping, frame, "Plot.new/2"),
      facet: %Facet.Null{},
      coord: %Coord.Cartesian{},
      theme: :gray,
      reversed_layers: []
    }
  end

  @doc """
  Adds a layer of points, one per row, at `x` and `y`.

  Points use `:x`, `:y` and `:group`, and need `:x` and `:y` from one mapping or the other.

      iex> plot =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]}
      ...>   |> Giggly.Plot.new()
      ...>   |> Giggly.Plot.geom_point(%{x: :wt, y: :mpg, group: :cyl})
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :x)
      [2.62, 2.875]
      iex> Giggly.DataFrame.pull(frame, :group)
      [2, 1]
  """
  @spec geom_point(t(), mapping_argument()) :: t()
  def geom_point(%__MODULE__{} = plot, mapping \\ %{}) when is_map(mapping) do
    layer = %Layer{
      geom: %Geom.Point{},
      stat: %Stat.Identity{},
      position: %Position.Identity{},
      mapping: resolve(mapping, plot.data, "Plot.geom_point/2")
    }

    combined_mapping = computed_mapping(plot, layer)
    check_accepted(combined_mapping, Geom.Point.accepted_aesthetics())
    check_required(combined_mapping, Geom.Point.required_aesthetics())

    %{plot | reversed_layers: [layer | plot.reversed_layers]}
  end

  # The mapping `layer` draws with: its own mapping laid over the plot's, if both map an aesthetic,
  # the layer's column is used.
  @doc false
  @spec computed_mapping(t(), Layer.t()) :: mapping()
  def computed_mapping(%__MODULE__{mapping: plot_mapping}, %Layer{mapping: layer_mapping}),
    do: Map.merge(plot_mapping, layer_mapping)

  # The geom `layer` draws with, a struct of its kind (`Giggly.Geom`).
  @doc false
  @spec layer_geom(Layer.t()) :: Layer.geom()
  def layer_geom(%Layer{geom: geom}), do: geom

  # The stat `layer` computes its table with, a struct of its kind (`Giggly.Stat`).
  @doc false
  @spec layer_stat(Layer.t()) :: Layer.stat()
  def layer_stat(%Layer{stat: stat}), do: stat

  # The position `layer` moves its marks with, a struct of its kind (`Giggly.Position`).
  @doc false
  @spec layer_position(Layer.t()) :: Layer.position()
  def layer_position(%Layer{position: position}), do: position

  defp resolve(mapping, frame, function_name) do
    names = DataFrame.names(frame)

    mapping
    |> Aesthetics.canonicalize()
    |> Map.new(fn {aesthetic, reference} ->
      {aesthetic, column(function_name, aesthetic, reference, names)}
    end)
  end

  defp column(function_name, aesthetic, reference, names) when is_column_reference(reference) do
    name = to_string(reference)

    if name in names do
      name
    else
      raise ArgumentError, missing_column_message(function_name, aesthetic, reference, names)
    end
  end

  defp column(function_name, aesthetic, reference, _names) do
    raise ArgumentError,
          "#{function_name} maps #{inspect(aesthetic)} to #{inspect(reference)}, " <>
            "but a mapping names a column, as an atom or a string"
  end

  defp missing_column_message(function_name, aesthetic, reference, names) do
    "#{function_name} maps #{inspect(aesthetic)} to #{inspect(reference)}, " <>
      "but the data has no column #{inspect(to_string(reference))}; " <>
      "its columns are #{inspect_all(names)}"
  end

  # The plot's mapping reaches every layer, so an aesthetic it maps that the geom cannot use is as
  # wrong as one the layer maps itself.
  defp check_accepted(mapping, accepted) do
    unaccepted =
      mapping
      |> Map.keys()
      |> Enum.reject(fn aesthetic -> aesthetic in accepted end)

    case unaccepted do
      [] ->
        :ok

      unaccepted ->
        raise ArgumentError,
              "Plot.geom_point/2 cannot use #{inspect_all(unaccepted)}, mapped by the layer " <>
                "or by the plot; geom_point accepts #{inspect_all(accepted)}"
    end
  end

  defp check_required(mapping, required) do
    case Enum.reject(required, fn aesthetic -> Map.has_key?(mapping, aesthetic) end) do
      [] ->
        :ok

      missing ->
        raise ArgumentError,
              "Plot.geom_point/2 needs #{inspect_all(missing)}, " <>
                "but neither its mapping nor the plot's maps it"
    end
  end

  defp inspect_all(terms), do: Enum.map_join(terms, ", ", &inspect/1)
end
