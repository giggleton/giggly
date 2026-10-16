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

  ## Setting aesthetics

  A layer function's options can set an aesthetic to one value for every mark the layer draws, as
  ggplot2's `geom_point(alpha = 0.4)` does: `Giggly.Plot.geom_point(plot, alpha: 0.4)`. A map
  maps and a keyword list sets.
  """

  # A plot is a description: it may use the aesthetic vocabulary, the data frame, the kinds of
  # facet, coordinate system, geom, stat and position, whose structs it builds and whose facts it
  # checks a layer against, and NimbleOptions, which validates its functions' options at the call,
  # and nothing that runs it. The five families' roots are protocols that
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
      Giggly.Stat,
      NimbleOptions
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

  @typedoc "A column of the plot's data as written: its name as an atom or a string."
  @type column_reference :: atom() | String.t()

  @typedoc "A mapping as written: aesthetic to column."
  @type mapping_argument :: %{optional(aesthetic()) => column_reference()}

  # `facet_wrap/3`'s options, validated at the call as every public function's are.
  @facet_wrap_options NimbleOptions.new!(
                        nrow: [
                          type: :pos_integer,
                          doc: "How many rows to lay the panels out in."
                        ],
                        ncol: [
                          type: :pos_integer,
                          doc: "How many columns to lay the panels out in."
                        ],
                        scales: [
                          type: {:in, [:fixed, :free_x, :free_y, :free]},
                          default: :fixed,
                          doc:
                            "Whether the panels share each axis's scale (`:fixed`), or each " <>
                              "panel has its own x scale (`:free_x`), y scale (`:free_y`) or both " <>
                              "(`:free`), and draws its own axis for each."
                        ]
                      )

  # An aesthetic set to one value for every mark of a layer, an option of the function that adds
  # the layer, as ggplot2's `geom_point(alpha = 0.4)` sets it. A number from 0 to 1 is kept as a
  # float, as R keeps it.
  @alpha_option [
    type: {:custom, __MODULE__, :validate_alpha, []},
    doc:
      "How opaque every mark is, from 0, invisible, to 1, opaque, as ggplot2's " <>
        "`alpha = 0.4` sets it."
  ]

  # The options that set an aesthetic rather than choose how a layer is drawn.
  @fixed_aesthetics [:alpha]

  # `geom_point/3`'s options, validated at the call.
  @point_options NimbleOptions.new!(alpha: @alpha_option)

  # `geom_bar/3`'s and `geom_col/3`'s options, validated at the call.
  @bar_options NimbleOptions.new!(
                 position: [
                   type: {:in, [:stack, :dodge]},
                   default: :stack,
                   doc:
                     "How bars that share an `x` are placed: piled on one another (`:stack`), " <>
                       "or set side by side within the width one bar takes (`:dodge`), " <>
                       "ggplot2's `position = \"dodge\"`."
                 ],
                 alpha: @alpha_option
               )

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

  Points use `:x`, `:y` and `:group`, and need `:x` and `:y` from one mapping or the other. A point
  set to be transparent is so in its outline and its fill alike, as ggplot2 draws one. A mapping,
  a map, and options, a keyword list, may each be given alone or both together.

  ## Options

  #{NimbleOptions.docs(@point_options)}

      iex> plot =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]}
      ...>   |> Giggly.Plot.new()
      ...>   |> Giggly.Plot.geom_point(%{x: :wt, y: :mpg, group: :cyl})
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :x)
      [2.62, 2.875]
      iex> Giggly.DataFrame.pull(frame, :group)
      [2, 1]

  A value set for every point is in every row of the layer's table:

      iex> plot =
      ...>   %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point(alpha: 0.4)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:alpha)
      [0.4, 0.4]
  """
  @spec geom_point(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_point(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_point(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_point(plot, %{}, options)

  def geom_point(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    validated = layer_options(options, @point_options)

    layer = %Layer{
      geom: %Geom.Point{},
      stat: %Stat.Identity{},
      position: %Position.Identity{},
      mapping: resolve(mapping, plot.data, "Plot.geom_point/3"),
      fixed: fixed(validated)
    }

    add_layer(plot, layer, "Plot.geom_point/3",
      accepted: Geom.Point.accepted_aesthetics(),
      required: Geom.Point.required_aesthetics()
    )
  end

  @doc """
  Adds a layer of bars counting the rows at each `x`: ggplot2's `geom_bar()`. Each bar runs from 0
  to the number of rows at its `x`, or, where `:weight` is mapped, to the sum of their weights, and
  the y axis is titled `count`. A row missing its `x` is not counted.

  Bars are drawn as `geom_col/3` draws them: 0.9 as wide as the closest spacing of the `x`
  positions, counting from zero, and stacked where groups share an `x`, the highest group at the
  bottom, or set side by side with `position: :dodge`.

  Counting uses `:x` or `:y`, `:weight` and `:group`, and needs exactly one of `:x` and `:y`: it
  counts along the one mapped, and the count is the other, so mapping `:y` alone draws horizontal
  bars, as ggplot2's `geom_bar(aes(y = class))` does, the x axis titled `count`. A `:weight` column
  must hold numbers. A mapping, a map, and options, a keyword list, may each be given alone or
  both together.

  ## Options

  #{NimbleOptions.docs(@bar_options)}

      iex> plot =
      ...>   %{"class" => ["suv", "compact", "suv"]}
      ...>   |> Giggly.Plot.new(%{x: :class})
      ...>   |> Giggly.Plot.geom_bar()
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :count)
      [1.0, 2.0]
  """
  @spec geom_bar(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_bar(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_bar(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_bar(plot, %{}, options)

  def geom_bar(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    validated = layer_options(options, @bar_options)

    layer = %Layer{
      geom: %Geom.Bar{},
      stat: %Stat.Count{},
      position: position(Keyword.fetch!(validated, :position)),
      mapping: resolve(mapping, plot.data, "Plot.geom_bar/3"),
      fixed: fixed(validated)
    }

    plot
    |> add_layer(layer, "Plot.geom_bar/3",
      accepted: Stat.Count.accepted_aesthetics(),
      required: Stat.Count.required_aesthetics(),
      exclusive: Stat.Count.exclusive_aesthetics()
    )
    |> check_weight(layer)
  end

  @doc """
  Adds a layer of bars, one per row, each from 0 to its `y` and centred on its `x`: ggplot2's
  `geom_col()`, for bars whose heights are in the data. Bars at the same `x` are stacked, those
  above zero upward and those below it downward, ordered by group so the highest group is at the
  bottom of each stack, as ggplot2 orders them to match the legend; with `position: :dodge` they
  are set side by side within the width one bar takes, ordered by group from the left, an `x` with
  one group keeping its whole width.

  Each bar is 0.9 as wide as the closest spacing of the `x` positions: 0.9 on a discrete axis,
  whose values sit 1 apart, and on a continuous one the closest pair's gap times 0.9 for every bar,
  as ggplot2's `resolution()` gives it, a column of integers counting as 1 apart. The `y` axis
  reaches to 0, since every bar starts there.

  Bars use `:x`, `:y` and `:group`, and need `:x` and `:y` from one mapping or the other. When `y`
  is the discrete axis and `x` the continuous one, the bars are horizontal, each from 0 to its `x`,
  as ggplot2 decides. A mapping, a map, and options, a keyword list, may each be given alone or both
  together.

  ## Options

  #{NimbleOptions.docs(@bar_options)}

      iex> plot =
      ...>   %{"trt" => ["a", "b", "c"], "outcome" => [2.3, 1.9, 3.2]}
      ...>   |> Giggly.Plot.new(%{x: :trt, y: :outcome})
      ...>   |> Giggly.Plot.geom_col()
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :ymin)
      [0.0, 0.0, 0.0]
      iex> Giggly.DataFrame.pull(frame, :ymax)
      [2.3, 1.9, 3.2]

  Dodged, the two groups at `a` share its width, and `b`'s one group keeps all of it:

      iex> plot =
      ...>   %{"x" => ["a", "a", "b"], "y" => [1.0, 2.0, 3.0], "g" => ["p", "q", "p"]}
      ...>   |> Giggly.Plot.new(%{x: :x, y: :y, group: :g})
      ...>   |> Giggly.Plot.geom_col(position: :dodge)
      iex> frame = Giggly.layer_data(plot)
      iex> Giggly.DataFrame.pull(frame, :xmin)
      [0.55, 1.0, 1.55]
  """
  @spec geom_col(t(), mapping_argument() | keyword(), keyword()) :: t()
  def geom_col(plot, mapping_or_options \\ %{}, options \\ [])

  def geom_col(%__MODULE__{} = plot, options, []) when is_list(options),
    do: geom_col(plot, %{}, options)

  def geom_col(%__MODULE__{} = plot, mapping, options)
      when is_map(mapping) and is_list(options) do
    validated = layer_options(options, @bar_options)

    layer = %Layer{
      geom: %Geom.Bar{},
      stat: %Stat.Identity{},
      position: position(Keyword.fetch!(validated, :position)),
      mapping: resolve(mapping, plot.data, "Plot.geom_col/3"),
      fixed: fixed(validated)
    }

    add_layer(plot, layer, "Plot.geom_col/3",
      accepted: Geom.Bar.accepted_aesthetics(),
      required: Geom.Bar.required_aesthetics()
    )
  end

  @doc """
  Splits the plot into panels, one for each combination of values of the `facets` columns that
  occurs in the data, laid out in rows: ggplot2's `facet_wrap()`. `facets` is a column, or a list
  of columns, each named as a mapping names one, so `facet_wrap(plot, :class)` is ggplot2's
  `facet_wrap(vars(class))` and `facet_wrap(plot, [:cyl, :drv])` its `facet_wrap(vars(cyl, drv))`.
  It replaces the plot's facet, which is one panel until a plot is faceted.

  Each layer's rows are drawn in the panel of their values. The panels are ordered by the first
  column's values, then the next's, as an axis orders its levels, with a missing value (`nil`)
  given a panel of its own, last. They fill the rows left to right. With neither `nrow:` nor
  `ncol:`, the panels are laid out as ggplot2 lays them out: in one row up to three panels, two
  rows up to six, three up to twelve, and beyond that in a square or nearly one. Given one of the
  two, the other is as many as the panels need.

  The panels share each axis's scale, so the same position means the same value in every panel,
  and an axis is drawn only at the edges of the panels. Free scales give each panel a scale of its
  own, trained on its rows alone, which makes patterns within a panel easier to see and comparisons
  between panels harder; each panel then draws its own axis.

  ## Options

  #{NimbleOptions.docs(@facet_wrap_options)}

  Raises `ArgumentError` for a column the data does not have, a column named twice or none at all,
  and `NimbleOptions.ValidationError` for an option it does not take or a count that is not a
  positive whole number. When the plot is run, `nrow:` and `ncol:` that together hold fewer
  panels than there are raise `ArgumentError`, as does data with no rows to make a panel from.

      iex> plot =
      ...>   %{"wt" => [2.32, 2.62, 3.44, 2.2], "mpg" => [22.8, 21.0, 18.7, 32.4], "cyl" => [4, 6, 8, 4]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.facet_wrap(:cyl)
      iex> plot |> Giggly.layer_data() |> Giggly.DataFrame.pull(:panel)
      [1, 2, 3, 1]
  """
  @spec facet_wrap(t(), column_reference() | [column_reference()], keyword()) :: t()
  def facet_wrap(%__MODULE__{data: data} = plot, facets, options \\ []) when is_list(options) do
    options = NimbleOptions.validate!(options, @facet_wrap_options)

    facet = %Facet.Wrap{
      facets: facet_columns(facets, data),
      nrow: Keyword.get(options, :nrow, :none),
      ncol: Keyword.get(options, :ncol, :none),
      scales: Keyword.fetch!(options, :scales)
    }

    %{plot | facet: facet}
  end

  @doc """
  Draws the plot in radial coordinates, ggplot2's `coord_radial()`: x is the angle, running
  clockwise round a full circle from 12 o'clock, and y the radius, out from the centre. It
  replaces the plot's coordinate system, which is cartesian until a plot says otherwise.

  The scales are expanded as cartesian ones are, so the marks keep clear of the circle's edge and
  centre, and the first and last positions on x are a gap apart at 12 o'clock rather than meeting.
  Each panel is square. Its grid is a circle at each of y's breaks and a spoke at each of x's, on
  a disc; x's axis is drawn round the circle inside the panel, and y's to the panel's left, up the
  radius at 12 o'clock. Nothing is clipped at the panel's edges, ggplot2's default for radial
  coordinates. `coord_radial()`'s options (its start and end angles, an inner radius, which of x
  and y is the angle) are not taken yet.

      iex> svg =
      ...>   %{"wt" => [2.32, 2.62, 3.44], "mpg" => [22.8, 21.0, 18.7]}
      ...>   |> Giggly.Plot.new(%{x: :wt, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.Plot.coord_radial()
      ...>   |> Giggly.to_svg()
      ...>   |> IO.iodata_to_binary()
      iex> svg =~ "<polygon"
      true
  """
  @spec coord_radial(t()) :: t()
  def coord_radial(%__MODULE__{} = plot), do: %{plot | coord: %Coord.Radial{}}

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

  # The aesthetics `layer` sets to one value for every mark, as ggplot2's `aes_params`.
  @doc false
  @spec layer_fixed(Layer.t()) :: Layer.fixed()
  def layer_fixed(%Layer{fixed: fixed}), do: fixed

  # NimbleOptions' check of an `alpha:` option: a number from 0, invisible, to 1, opaque, kept as a
  # float.
  @doc false
  @spec validate_alpha(term()) :: {:ok, float()} | {:error, String.t()}
  def validate_alpha(alpha) when is_number(alpha) and alpha >= 0 and alpha <= 1,
    do: {:ok, alpha / 1}

  def validate_alpha(alpha),
    do: {:error, "expected a number from 0 to 1, got: #{inspect(alpha)}"}

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

  # The plot with `layer` added, once the mapping it draws with is checked against what the function
  # that adds it, `function`, accepts and requires. At the front, so adding a layer never walks the
  # list.
  defp add_layer(plot, layer, function, facts) do
    combined_mapping = computed_mapping(plot, layer)
    check_accepted(combined_mapping, Keyword.fetch!(facts, :accepted), function)
    check_required(combined_mapping, Keyword.fetch!(facts, :required), function)
    check_exclusive(combined_mapping, Keyword.get(facts, :exclusive, []), function)

    %{plot | reversed_layers: [layer | plot.reversed_layers]}
  end

  # A layer function's options, validated against `schema`, their names put in their canonical
  # spelling first, so a repeated option is refused rather than one silently winning.
  defp layer_options(options, schema) do
    options
    |> Aesthetics.canonicalize()
    |> NimbleOptions.validate!(schema)
  end

  # The aesthetics a layer's validated options set for every mark.
  defp fixed(validated) do
    validated
    |> Keyword.take(@fixed_aesthetics)
    |> Map.new()
  end

  defp position(:stack), do: %Position.Stack{}
  defp position(:dodge), do: %Position.Dodge{}

  # A weight is summed, so the column a layer's weight comes from must hold numbers, missing ones
  # included.
  defp check_weight(plot, layer) do
    mapping = computed_mapping(plot, layer)
    dtypes = DataFrame.dtypes(plot.data)

    with {:ok, column} <- Map.fetch(mapping, :weight),
         dtype when dtype not in [:integer, :float, :null] <- Map.fetch!(dtypes, column) do
      raise ArgumentError,
            "Plot.geom_bar/3 maps :weight to #{inspect(column)}, a #{inspect(dtype)} column, " <>
              "but a weight is summed, so it must be a number"
    end

    plot
  end

  # The plot's mapping reaches every layer, so an aesthetic it maps that the geom cannot use is as
  # wrong as one the layer maps itself.
  defp check_accepted(mapping, accepted, function) do
    unaccepted =
      mapping
      |> Map.keys()
      |> Enum.reject(fn aesthetic -> aesthetic in accepted end)

    case unaccepted do
      [] ->
        :ok

      unaccepted ->
        raise ArgumentError,
              "#{function} cannot use #{inspect_all(unaccepted)}, mapped by the layer " <>
                "or by the plot; it accepts #{inspect_all(accepted)}"
    end
  end

  # A required aesthetic is a name, or a list of names of which one is enough, as ggplot2 writes
  # `"x|y"`.
  defp check_required(mapping, required, function) do
    case Enum.reject(required, fn needed -> mapped?(mapping, needed) end) do
      [] ->
        :ok

      missing ->
        raise ArgumentError,
              "#{function} needs #{Enum.map_join(missing, ", ", &needed_message/1)}, " <>
                "but neither its mapping nor the plot's maps it"
    end
  end

  defp mapped?(mapping, alternatives) when is_list(alternatives),
    do: Enum.any?(alternatives, fn aesthetic -> Map.has_key?(mapping, aesthetic) end)

  defp mapped?(mapping, aesthetic), do: Map.has_key?(mapping, aesthetic)

  defp needed_message(alternatives) when is_list(alternatives),
    do: "one of #{inspect_all(alternatives)}"

  defp needed_message(aesthetic), do: inspect(aesthetic)

  # Aesthetics of which a layer maps at most one, as counting maps x or y but not both.
  defp check_exclusive(mapping, exclusive, function) do
    Enum.each(exclusive, fn alternatives -> check_one_of(mapping, alternatives, function) end)
  end

  defp check_one_of(mapping, alternatives, function) do
    case Enum.filter(alternatives, fn aesthetic -> Map.has_key?(mapping, aesthetic) end) do
      [_first, _second | _rest] = both ->
        raise ArgumentError,
              "#{function} maps #{inspect_all(both)}, but takes only one of them, " <>
                "since it counts along one and the count is the other"

      _one_or_none ->
        :ok
    end
  end

  # The columns a facet splits on, by the names the data gives them, in the order written.
  defp facet_columns(facets, frame) do
    names = DataFrame.names(frame)
    references = List.wrap(facets)

    columns =
      Enum.map(references, fn reference -> facet_column(reference, names) end)

    check_facet_columns(columns, references)
    columns
  end

  defp facet_column(reference, names) when is_column_reference(reference) do
    name = to_string(reference)

    if name in names do
      name
    else
      raise ArgumentError,
            "Plot.facet_wrap/3 facets by #{inspect(reference)}, but the data has no column " <>
              "#{inspect(name)}; its columns are #{inspect_all(names)}"
    end
  end

  defp facet_column(reference, _names) do
    raise ArgumentError,
          "Plot.facet_wrap/3 facets by #{inspect(reference)}, " <>
            "but a facet names a column, as an atom or a string"
  end

  defp check_facet_columns([], _references) do
    raise ArgumentError, "Plot.facet_wrap/3 needs a column to facet by, and was given none"
  end

  defp check_facet_columns(columns, references) do
    case columns -- Enum.uniq(columns) do
      [] ->
        :ok

      [repeated | _others] ->
        raise ArgumentError,
              "Plot.facet_wrap/3 facets by #{inspect_all(references)}, which names the column " <>
                "#{inspect(repeated)} more than once"
    end
  end

  defp inspect_all(terms), do: Enum.map_join(terms, ", ", &inspect/1)
end
