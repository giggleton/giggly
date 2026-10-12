defmodule Giggly.DataFrame do
  @moduledoc """
  The table every stage of the pipeline reads and writes: named columns of equal length.

  ## Column names

  The data a plot is given is read once, by `from_table/1`, and its column names become strings
  whatever the source used. Every column the pipeline writes is named by an atom, such as the
  aesthetic `:x`, so a user column called `"x"` can never be mistaken for one.

  ## Values

  A column is a list of values in row order, stored as given and never converted. `nil` is a
  missing value, which is how every `Table.Reader` source returns a null.

  ## Types

  Every column has one type, which `dtypes/1` reports. It is worked out from the values when the
  column enters a frame, by Explorer's rules for building a series from a list:

    * the non-missing values are all of one kind, and a column mixing two kinds is refused with an
      `ArgumentError` naming the column and two values that disagree;
    * integers and floats together are `:float`, and `:nan`, `:infinity` and `:neg_infinity` are
      floats, as Explorer gives a non-finite float;
    * a column of only `nil`, or of no rows, is `:null`;
    * binaries are `:string`;
    * `Date`, `Time`, `NaiveDateTime` and `DateTime` are `:date`, `:time`, `:naive_datetime` and
      `:datetime`.

  Two types exist here and not in Explorer, since a list holds Elixir values an engine cannot:
  `:atom`, for any other atom, and `:term`, for anything else (maps, lists, tuples, `Decimal` and
  other structs). A `:term` column's values are not checked against each other; it is the frame's
  equivalent of pandas' and Polars' `object` type, so a column the plot never uses cannot refuse the
  table.

  ## Implementations

  This module is both the behaviour an implementation follows and the only module callers use:
  each operation dispatches on the frame's struct. `Giggly.DataFrame.Lists` is the one
  implementation. The operations are relational (choosing, renaming and adding columns), so an
  engine such as a database could run them, and none takes an Elixir function, since an engine
  cannot run one. Code that needs one pulls a column into a list and puts the result back.
  """

  # Its own boundary, exporting only this module: callers reach a frame through the functions
  # below, so an implementation's struct and functions are private to it and a second
  # implementation changes no caller. It is a top-level boundary because it owns the `table`
  # library: nested under `Giggly`, it could list `Table` only if `Giggly` did too, and then every
  # module directly in `Giggly` could call it. Here `from_table/1` is the one caller.
  use Boundary, top_level?: true, deps: [Table], exports: []

  alias Giggly.DataFrame.Lists

  @typedoc "A frame: the struct of the implementation holding it."
  @type t :: Lists.t()

  @typedoc "A column name: a string for a column read from the input, an atom for every other."
  @type name :: atom() | String.t()

  @typedoc "A column's type, as the moduledoc's Types section describes."
  @type dtype ::
          :integer
          | :float
          | :string
          | :boolean
          | :atom
          | :date
          | :time
          | :naive_datetime
          | :datetime
          | :null
          | :term

  @doc "Builds a frame from `{name, values}` pairs, as `new/1` describes."
  @callback new([{name(), list()}]) :: t()

  @doc "The column names, as `names/1` describes."
  @callback names(t()) :: [name()]

  @doc "The number of rows, as `row_count/1` describes."
  @callback row_count(t()) :: non_neg_integer()

  @doc "Each column's type, as `dtypes/1` describes."
  @callback dtypes(t()) :: %{optional(name()) => dtype()}

  @doc "Chooses and renames columns, as `select/2` describes."
  @callback select(t(), [{name(), name()}]) :: t()

  @doc "One column's values, as `pull/2` describes."
  @callback pull(t(), name()) :: list()

  @doc "Adds or replaces a column, as `put/3` describes."
  @callback put(t(), name(), list()) :: t()

  @doc """
  Reads any `Table.Reader` (a list of maps, a map of columns, an Explorer data frame, a database
  result) into a frame.

  Every column is read into a list, so a lazy source is read here and nowhere else, and column
  names become strings. Raises `ArgumentError` when the input is a list or map that is not a
  table, when two of its names become the same string (`:wt` and `"wt"`), when its columns
  differ in length, or when a column mixes two types; a value with no `Table.Reader`
  implementation raises `Protocol.UndefinedError`.

      iex> frame = Giggly.DataFrame.from_table(%{wt: [2.62, 2.875, 2.32], id: 1..3})
      iex> Giggly.DataFrame.names(frame)
      ["id", "wt"]
      iex> Giggly.DataFrame.pull(frame, "id")
      [1, 2, 3]

      iex> Giggly.DataFrame.from_table([1, 2, 3])
      ** (ArgumentError) expected a table (any Table.Reader), got: [1, 2, 3]
  """
  @spec from_table(Table.Reader.t()) :: t()
  def from_table(table) do
    table
    |> Table.Reader.init()
    |> read_columns(table)
    |> new()
  end

  defp read_columns(:none, table) do
    raise ArgumentError, "expected a table (any Table.Reader), got: #{inspect(table)}"
  end

  # The metadata carries the column order; `Table.to_columns/1` returns a map, which loses it.
  defp read_columns({_traversal, %{columns: source_names}, _values} = reader, _table) do
    values_by_source_name = Table.to_columns(reader)

    columns =
      for {name, source_name} <- string_names(source_names) do
        %{^source_name => values} = values_by_source_name
        {name, Enum.to_list(values)}
      end

    check_lengths(columns)
  end

  # Pairs each source name with its string form, remembering which source name first claimed each
  # string so a second claim can say which two names collided.
  defp string_names(source_names) do
    {pairs, _claimed} =
      Enum.map_reduce(source_names, %{}, fn source_name, claimed ->
        name = to_string(source_name)

        case claimed do
          %{^name => earlier_source_name} ->
            raise ArgumentError,
                  "the table has two columns named #{inspect(name)} " <>
                    "(#{inspect(earlier_source_name)} and #{inspect(source_name)}); rename one"

          %{} ->
            {{name, source_name}, Map.put(claimed, name, source_name)}
        end
      end)

    pairs
  end

  # `table` checks no lengths, and reading rows from columns stops at the shortest, so a short
  # column would silently misalign every row after it ends.
  defp check_lengths(columns) do
    lengths = Enum.map(columns, fn {name, values} -> {name, length(values)} end)

    case Enum.uniq_by(lengths, fn {_name, length} -> length end) do
      [_first, _second | _rest] ->
        described =
          Enum.map_join(lengths, ", ", fn {name, length} -> "#{inspect(name)} has #{length}" end)

        raise ArgumentError,
              "the table's columns differ in length (#{described}); give every column one value per row"

      _one_length ->
        columns
    end
  end

  @doc """
  Builds a frame from `{name, values}` pairs, keeping their order.

  This is how the pipeline builds a frame; data from outside it enters through `from_table/1`.
  Every `values` is a list of the same length and no name appears twice; a call that breaks either
  raises `FunctionClauseError`. A column mixing two types raises `ArgumentError`.

      iex> frame = Giggly.DataFrame.new(x: [1.5, 2.0], color: ["a", "b"])
      iex> Giggly.DataFrame.names(frame)
      [:x, :color]

      iex> Giggly.DataFrame.new([]) |> Giggly.DataFrame.row_count()
      0

      iex> Giggly.DataFrame.new(mpg: [21.0, nil, "n/a"])
      ** (ArgumentError) the column :mpg holds values of more than one type (21.0 and "n/a"); give each column one type
  """
  @spec new([{name(), list()}]) :: t()
  def new(columns) when is_list(columns), do: Lists.new(columns)

  @doc "The column names, in column order."
  @spec names(t()) :: [name()]
  def names(%implementation{} = frame), do: implementation.names(frame)

  @doc "The number of rows."
  @spec row_count(t()) :: non_neg_integer()
  def row_count(%implementation{} = frame), do: implementation.row_count(frame)

  @doc """
  Each column's type, by column name, as the moduledoc's Types section describes.

      iex> frame =
      ...>   Giggly.DataFrame.new(
      ...>     count: [1, nil],
      ...>     mpg: [21, 22.8],
      ...>     ratio: [:nan, 2],
      ...>     limit: [:infinity, :neg_infinity],
      ...>     model: ["Mazda RX4", "Datsun 710"],
      ...>     manual: [true, false],
      ...>     species: [:setosa, :virginica],
      ...>     day: [~D[2026-10-12], nil],
      ...>     clock: [~T[09:30:00], ~T[17:00:00]],
      ...>     logged: [~N[2026-10-12 09:30:00], ~N[2026-10-12 17:00:00]],
      ...>     stamped: [~U[2026-10-12 09:30:00Z], ~U[2026-10-12 17:00:00Z]],
      ...>     missing: [nil, nil],
      ...>     payload: [%{id: 1}, [2]]
      ...>   )
      iex> Giggly.DataFrame.dtypes(frame)
      %{
        count: :integer,
        mpg: :float,
        ratio: :float,
        limit: :float,
        model: :string,
        manual: :boolean,
        species: :atom,
        day: :date,
        clock: :time,
        logged: :naive_datetime,
        stamped: :datetime,
        missing: :null,
        payload: :term
      }
  """
  @spec dtypes(t()) :: %{optional(name()) => dtype()}
  def dtypes(%implementation{} = frame), do: implementation.dtypes(frame)

  @doc """
  A frame of the columns named in `renames`, each `{new_name, existing_name}`, in that order.

  It is dplyr's `select(x = wt)`: an existing column may be chosen under several new names, and
  any column not named is dropped. The rows are kept even when no column is.

      iex> frame = Giggly.DataFrame.from_table(%{"wt" => [2.62, 2.875], "cyl" => ["6", "4"]})
      iex> selected = Giggly.DataFrame.select(frame, x: "wt", color: "cyl", label: "wt")
      iex> Giggly.DataFrame.names(selected)
      [:x, :color, :label]
      iex> Giggly.DataFrame.dtypes(selected)
      %{x: :float, color: :string, label: :float}
      iex> Giggly.DataFrame.pull(selected, :label)
      [2.62, 2.875]
      iex> frame |> Giggly.DataFrame.select([]) |> Giggly.DataFrame.row_count()
      2
  """
  @spec select(t(), [{name(), name()}]) :: t()
  def select(%implementation{} = frame, renames) when is_list(renames),
    do: implementation.select(frame, renames)

  @doc """
  One column's values, as a list in row order. Raises `FunctionClauseError` when the frame has no
  column of that name.
  """
  @spec pull(t(), name()) :: list()
  def pull(%implementation{} = frame, name), do: implementation.pull(frame, name)

  @doc """
  The frame with the column `name` holding `values`: replaced where it is, or added after the
  last column. The column's type is worked out from `values`, so a replacement may change it.
  Raises `FunctionClauseError` unless `values` has one value per row, and `ArgumentError` when
  they mix two types.

      iex> frame =
      ...>   Giggly.DataFrame.new(x: ["a", "b"])
      ...>   |> Giggly.DataFrame.put(:group, [1, 1])
      ...>   |> Giggly.DataFrame.put(:x, [1.0, 2.0])
      iex> Giggly.DataFrame.names(frame)
      [:x, :group]
      iex> Giggly.DataFrame.dtypes(frame)
      %{x: :float, group: :integer}
      iex> Giggly.DataFrame.pull(frame, :x)
      [1.0, 2.0]
  """
  @spec put(t(), name(), list()) :: t()
  def put(%implementation{} = frame, name, values), do: implementation.put(frame, name, values)
end
