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
  names are strings, so a source that cannot be read, or a column holding two types, is refused by
  the call that gave it.

  ## Mappings

  A mapping is a map from aesthetic to column, `%{x: :wt, y: :mpg}`. A column is named by an atom
  or a string and compared with the data's column names as a string, so `:wt` and `"wt"` name the
  same column. `:colour` is accepted for `:color`.

  Each function checks the mapping it is given against the data when it is called, and raises
  `ArgumentError` naming the aesthetic, the column as written and the data's columns, so a
  misspelt column is reported by the call that has it.

  The plot's mapping applies to every layer, and a layer's mapping is laid over it: an aesthetic
  both map takes the layer's column. Which aesthetics a layer can use is checked, on the two
  mappings together, when the layer is added.

  ## Errors

  Every function raises on an argument it cannot use, since a pipe cannot carry an error tuple.
  """

  # A plot is a description: it may use the aesthetic vocabulary and the data frame, and nothing
  # that runs it. `Layer` is exported because the assembly reads a plot's layers.
  use Boundary, deps: [Giggly.Aesthetics, Giggly.DataFrame], exports: [Layer]

  alias Giggly.{Aesthetics, DataFrame}
  alias Giggly.Plot.Layer

  @enforce_keys [:data, :mapping, :reversed_layers]
  defstruct @enforce_keys

  @typedoc """
  A mapping as stored: aesthetic to the name of a column in the plot's data.
  """
  @type mapping :: %{optional(Aesthetics.name()) => String.t()}

  @typedoc """
  A plot: its data, its mapping, and its layers newest first (each function adds one at the
  front; they are assembled in the order they were added).
  """
  @type t :: %__MODULE__{
          data: DataFrame.t(),
          mapping: mapping(),
          reversed_layers: [Layer.t()]
        }

  @typedoc "A mapping as written: aesthetic to column, the column named by an atom or a string."
  @type mapping_argument :: %{optional(Aesthetics.name()) => atom() | String.t()}

  @point_aesthetics [:group, :x, :y]
  @point_required [:x, :y]

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
      reversed_layers: []
    }
  end

  @doc """
  Adds a layer of points, one per row, at `x` and `y`.

  `mapping` is laid over the plot's. Points use `:x`, `:y` and `:group`, and need `:x` and `:y`
  from one mapping or the other.

      iex> plot =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point(%{group: :cyl})
      iex> plot.reversed_layers
      [%Giggly.Plot.Layer{geom: :point, mapping: %{group: "cyl"}}]
  """
  @spec geom_point(t(), mapping_argument()) :: t()
  def geom_point(%__MODULE__{} = plot, mapping \\ %{}) when is_map(mapping) do
    layer_mapping = resolve(mapping, plot.data, "Plot.geom_point/2")
    combined_mapping = Map.merge(plot.mapping, layer_mapping)
    check_accepted(combined_mapping)
    check_required(combined_mapping)

    layer = %Layer{geom: :point, mapping: layer_mapping}
    %{plot | reversed_layers: [layer | plot.reversed_layers]}
  end

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
  defp check_accepted(mapping) do
    unaccepted =
      mapping
      |> Map.keys()
      |> Enum.reject(fn aesthetic -> aesthetic in @point_aesthetics end)

    case unaccepted do
      [] ->
        :ok

      unaccepted ->
        raise ArgumentError,
              "Plot.geom_point/2 cannot use #{inspect_all(unaccepted)}, mapped by the layer " <>
                "or by the plot; geom_point accepts #{inspect_all(@point_aesthetics)}"
    end
  end

  defp check_required(mapping) do
    case Enum.reject(@point_required, fn aesthetic -> Map.has_key?(mapping, aesthetic) end) do
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
