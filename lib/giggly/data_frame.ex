defmodule Giggly.DataFrame do
  @moduledoc """
  A table of named columns of equal length, as Giggly holds one: the data a plot was given, and
  each table `Giggly.layer_data/2` returns. `names/1`, `row_count/1`, `dtypes/1` and `pull/2` read
  it.

  ## Column names

  The data a plot is given is read once, when the plot is created (`Giggly.Plot.new/2`), and so is
  a layer's own table, by its function's `data:` option; their column names become strings
  whatever the source used. Every column Giggly computes is named by
  an atom, such as the aesthetic `:x`, so a user column called `"x"` can never be mistaken for one.

  ## Values

  A column is a list of values in row order, stored as given, but for one conversion its type
  makes: an integer in a column of floats becomes a float, as Explorer casts one, so `4` and `4.0`
  are the same value. `nil` is a missing value, which is how every `Table.Reader` source returns a
  null.

  ## Types

  Every column has one type, which `dtypes/1` reports. It is worked out from the values when the
  column enters a frame, by Explorer's rules for building a series from a list:

    * the non-missing values are all of one kind, and a column mixing two kinds is refused with an
      `ArgumentError` naming the column and two values that disagree;
    * integers and floats together are `:float`, the integers stored as floats, and `:nan`,
      `:infinity` and `:neg_infinity` are floats, as Explorer gives a non-finite float;
    * a column of only `nil`, or of no rows, is `:null`;
    * binaries are `:string`;
    * `Date`, `Time`, `NaiveDateTime` and `DateTime` are `:date`, `:time`, `:naive_datetime` and
      `:datetime`.

  Two types exist here and not in Explorer, since a list holds Elixir values an engine cannot:
  `:atom`, for any other atom, and `:term`, for anything else (maps, lists, tuples, `Decimal` and
  other structs). A `:term` column's values are not checked against each other; it is the frame's
  equivalent of pandas' and Polars' `object` type, so a column the plot never uses cannot refuse the
  table.

  One more is never worked out from values, only declared when a column is built: `:category`,
  Explorer's name for a categorical column, which a plot reads as discrete whatever its values
  are. Its values are typed, and an integer among floats becomes a float, as any column's; it may
  hold anything but a `:term`'s values.
  """

  # ## Implementations
  #
  # This module is both the behaviour an implementation follows and the only module callers use:
  # each operation dispatches on the frame's struct. `Giggly.DataFrame.Lists` is the one
  # implementation. The operations are relational (choosing, renaming and adding columns, splitting
  # and taking rows), so an engine such as a database could run them, and none takes an Elixir
  # function, since an engine cannot run one. Code that needs one pulls a column into a list and
  # puts the result back.

  # ## Expressions
  #
  # What `filter/2` and `mutate/2` compute in each row is an expression, plain data in the grammar
  # a mapping writes, with an operation named by an atom where a mapping takes a function, so an
  # engine can run it and a stat never pulls a table to choose its rows:
  #
  #   * a column, by its name, an atom or a string: `:x`, `"cyl"`; `true`, `false` and `nil` name
  #     none;
  #   * a constant, the value in every row: a number, a boolean, a date or a time written alone, or
  #     any value as `{:constant, term}`, typed as a column holding it would be;
  #   * an operation, `{name, [expression, ...]}`, or `{name, [expression, ...], options}` for
  #     parameters that are not row values: `{:is_finite, [x]}`, whether each number is finite,
  #     and `{:and, [left, right]}`, whether both are true, each a boolean; `{:cut, [x], breaks:
  #     breaks, closed: :right}`, the interval of `breaks`, ascending, each number falls in,
  #     numbered from 1, an integer, as R's `cut(include.lowest = TRUE)` numbers it: closed on the
  #     right, or on the left with `closed: :left`, and the outermost interval at its outer end
  #     too, a number outside them all missing.
  #
  # Values follow Explorer's semantics, as types do: a missing value passes through an operation
  # as missing, so `is_finite` is missing where its number is, and `and` is false where either side
  # is false, true where both are true and missing otherwise (SQL's three-valued logic). An
  # expression outside this vocabulary, or an operation given a column of the wrong type, whether
  # or not it has rows, raises `FunctionClauseError`. Operations arrive with their first caller.

  # Its own boundary, exporting this module and `Giggly.DataFrame.Arithmetic`, R's arithmetic on
  # the doubles a frame holds: callers reach a frame through the functions below, so an
  # implementation's struct and functions are private to it and a second implementation changes
  # no caller. It owns the `table` library, which `Giggly` lists too, as
  # boundary lets a sub-boundary list only what its parent does; no other domain lists it, and
  # here `from_table/1` is the one caller.
  use Boundary, deps: [Table], exports: [Arithmetic]

  alias Giggly.DataFrame.Lists

  @typedoc "A frame, read through the functions here."
  @opaque t :: Lists.t()

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
          | :category

  @typedoc "A column as built: its name and values, and `:category` where it is declared one."
  @type column :: {name(), list()} | {name(), list(), :category}

  @typedoc """
  What a frame computes in each row: a column by its name, a constant, or an operation on
  expressions by its name.
  """
  @type expression ::
          name()
          | number()
          | boolean()
          | Date.t()
          | Time.t()
          | NaiveDateTime.t()
          | DateTime.t()
          | {:constant, term()}
          | {:is_finite, [expression()]}
          | {:and, [expression()]}
          | {:cut, [expression()], [breaks: [number()], closed: :right | :left]}

  @typedoc "What `summarise/3` computes over each group's values of a column."
  @type aggregate ::
          {:sum, [name()]}
          | {:sum, [name()], [summation: :compensated | :plain, missing: :propagate | :skip]}
          | {:n_distinct, [name()]}
          | {:first, [name()]}

  # Builds a frame from columns, as `new/1` describes.
  @doc false
  @callback new([column()]) :: t()

  # The column names, as `names/1` describes.
  @doc false
  @callback names(t()) :: [name()]

  # The number of rows, as `row_count/1` describes.
  @doc false
  @callback row_count(t()) :: non_neg_integer()

  # Each column's type, as `dtypes/1` describes.
  @doc false
  @callback dtypes(t()) :: %{optional(name()) => dtype()}

  # Chooses and renames columns, as `select/2` describes.
  @doc false
  @callback select(t(), [{name(), name()}]) :: t()

  # One column's values, as `pull/2` describes.
  @doc false
  @callback pull(t(), name()) :: list()

  # Adds or replaces a column, as `put/3` describes.
  @doc false
  @callback put(t(), name(), list()) :: t()

  # Adds or replaces a column declared a category, as `put/4` describes.
  @doc false
  @callback put(t(), name(), list(), :category) :: t()

  # The rows split by the values of one column, as `split/2` describes.
  @doc false
  @callback split(t(), name()) :: %{optional(term()) => t()}

  # The rows at the given indices, as `slice/2` describes.
  @doc false
  @callback slice(t(), [non_neg_integer()]) :: t()

  # The rows an expression is true in, as `filter/2` describes.
  @doc false
  @callback filter(t(), expression()) :: t()

  # Adds or replaces columns computed from expressions, as `mutate/2` describes.
  @doc false
  @callback mutate(t(), [{name(), expression()}]) :: t()

  # One row per group of rows, as `summarise/3` describes.
  @doc false
  @callback summarise(t(), [name(), ...], [{name(), aggregate()}]) :: t()

  # Reads any `Table.Reader` (a list of maps, a map of columns, an Explorer data frame, a database
  # result) into a frame.
  #
  # Every column is read into a list, so a lazy source is read here and nowhere else, and column
  # names become strings. A list of maps gives its columns in sorted key order, since `table` sorts
  # the first row's keys; a list of keyword lists keeps its written order. Raises `ArgumentError`
  # when the input is a list or map that is not a table, when two of its names become the same
  # string (`:wt` and `"wt"`), when its columns differ in length, or when a column mixes two types;
  # a value with no `Table.Reader` implementation raises `Protocol.UndefinedError`.
  @doc false
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

  # Builds a frame from `{name, values}` pairs, keeping their order, a column declared a category
  # given as `{name, values, :category}`.
  #
  # This is how the pipeline builds a frame; data from outside it enters through `from_table/1`.
  # Every `values` is a list of the same length and no name appears twice; a call that breaks either
  # raises `FunctionClauseError`. A column mixing two types raises `ArgumentError`, and so does a
  # category of values with no type of their own.
  @doc false
  @spec new([column()]) :: t()
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
      ...>   %{"cyl" => ["6", "4"], "mpg" => [21.0, 22.8]}
      ...>   |> Giggly.Plot.new(%{x: :cyl, y: :mpg})
      ...>   |> Giggly.Plot.geom_point()
      ...>   |> Giggly.layer_data()
      iex> Giggly.DataFrame.dtypes(frame)
      %{x: :integer, y: :float, panel: :integer, group: :integer}
  """
  @spec dtypes(t()) :: %{optional(name()) => dtype()}
  def dtypes(%implementation{} = frame), do: implementation.dtypes(frame)

  # A frame of the columns named in `renames`, each `{new_name, existing_name}`, in that order.
  #
  # It is dplyr's `select(x = wt)`: an existing column may be chosen under several new names, and
  # any column not named is dropped. The rows are kept even when no column is.
  @doc false
  @spec select(t(), [{name(), name()}]) :: t()
  def select(%implementation{} = frame, renames) when is_list(renames),
    do: implementation.select(frame, renames)

  @doc """
  One column's values, as a list in row order. Raises `FunctionClauseError` when the frame has no
  column of that name.
  """
  @spec pull(t(), name()) :: list()
  def pull(%implementation{} = frame, name), do: implementation.pull(frame, name)

  # The frame with the column `name` holding `values`: replaced where it is, or added after the
  # last column. The column's type is worked out from `values`, so a replacement may change it.
  # Raises `FunctionClauseError` unless `values` has one value per row, and `ArgumentError` when
  # they mix two types.
  @doc false
  @spec put(t(), name(), list()) :: t()
  def put(%implementation{} = frame, name, values), do: implementation.put(frame, name, values)

  # The frame with the column `name` holding `values`, declared a category, as `new/1` declares a
  # column given as `{name, values, :category}`: replaced where it is, or added after the last
  # column. Raises as `put/3` does, and `ArgumentError` for values with no type of their own.
  @doc false
  @spec put(t(), name(), list(), :category) :: t()
  def put(%implementation{} = frame, name, values, :category),
    do: implementation.put(frame, name, values, :category)

  # The frame's rows split by the values of the column `name`, as R's `split()` splits ggplot2's
  # layer data by panel: for each value the column holds, a frame of the rows holding it, in their
  # order, with every column and each column's type. A value the column does not hold has no frame.
  @doc false
  @spec split(t(), name()) :: %{optional(term()) => t()}
  def split(%implementation{} = frame, name), do: implementation.split(frame, name)

  # The frame's rows at `indices`, counting from 0, in the order given, as vctrs' `vec_slice()`
  # takes them: a row may be taken more than once or not at all, as ggplot2's geoms reorder,
  # drop and repeat the rows they draw. Every column and each column's type are kept. Raises
  # `ArgumentError` for an index past the last row.
  @doc false
  @spec slice(t(), [non_neg_integer()]) :: t()
  def slice(%implementation{} = frame, indices) when is_list(indices),
    do: implementation.slice(frame, indices)

  # The frame's rows in which `expression` is true, in their order, every column keeping its type,
  # as dplyr's `filter()` and SQL's `WHERE` keep them: a row where it is false or missing is left
  # out. The expression is a boolean one, as the Expressions comment above describes.
  @doc false
  @spec filter(t(), expression()) :: t()
  def filter(%implementation{} = frame, expression),
    do: implementation.filter(frame, expression)

  # The frame with each of `columns`, a `{name, expression}`, computed in every row: replaced where
  # it is, or added after the last column, in the order given, as dplyr's `mutate()` adds them.
  # Every expression reads the frame as given, never a column the same call computes, as Polars'
  # `with_columns()` reads. A column named alone keeps its type, a category's included; a
  # constant's type is worked out from its value, and an operation's is what it computes.
  @doc false
  @spec mutate(t(), [{name(), expression()}]) :: t()
  def mutate(%implementation{} = frame, columns) when is_list(columns),
    do: implementation.mutate(frame, columns)

  # One row for each combination of the values of the columns `by` that the frame's rows hold, as
  # dplyr's `summarise(.by = )` and SQL's `GROUP BY` give one, with each of `aggregates`, a
  # `{name, aggregate}` in order, computed over that group's rows. The `by` columns come first, in
  # the order given, each keeping its type, a category's included; each aggregate follows as a
  # column of its own. The rows are sorted by the `by` columns, the first deciding first, each by
  # its values in Erlang's term order with a missing one last, as R's `id()` orders the
  # combinations it finds and SQL's `NULLS LAST` does.
  #
  # An aggregate is an operation, `{name, [column]}` or `{name, [column], options}`, over each
  # group's values of one column, in row order:
  #
  #   * `{:n_distinct, [column]}`, how many distinct values the group holds, an integer, a missing
  #     value counting as one, as R's `vec_unique_count()` and Polars' `n_unique()` count it;
  #   * `{:first, [column]}`, the group's first value, of the column's type, a category's included;
  #   * `{:sum, [column]}`, the sum of a column of numbers, a float, which takes two options.
  #
  # A sum's `summation:` says how it adds: `:compensated`, the default, carries the rounding error
  # each addition makes and adds it back at the end, as R's `sum()` adds in extended precision, so
  # the sum is the one R's gives; `:plain` adds the values in row order in floats, as R's
  # `rowsum()` does. `missing:` says what a missing value does, one that is `nil` (R's `NA`) or
  # NaN: `:propagate`, the default, makes the group's sum missing, `nil` where one is, else NaN,
  # as R's `sum()` gives `NA` or `NaN`; `:skip` leaves it out, as `rowsum(na.rm = TRUE)` does, a
  # group of only missing values summing to 0. An infinity is no missing value: it adds as IEEE
  # adds one, so the sum is that infinity, or NaN where both meet, as R's is. A sum of a column of
  # another type and an option not listed are refused with an `ArgumentError`; an empty `by`, an
  # option's value not listed, an aggregate not listed and an aggregate's name shared with a `by`
  # column raise `FunctionClauseError`.
  @doc false
  @spec summarise(t(), [name(), ...], [{name(), aggregate()}]) :: t()
  def summarise(%implementation{} = frame, [_first | _rest] = by, aggregates)
      when is_list(aggregates),
      do: implementation.summarise(frame, by, aggregates)
end
