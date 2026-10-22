defmodule Giggly.DataFrame.Lists do
  @moduledoc false

  # The pure-Elixir data frame: each column is a list. Callers use `Giggly.DataFrame`, which
  # dispatches here.
  #
  # A frame keeps a map from column name to the column's type and values, the names newest first
  # (reversed when `names/1` asks, so gaining a column never walks the list), and its row count, so
  # a `select/2` that keeps no column keeps the rows. Every column has exactly `row_count` values
  # and no name appears twice: every column a frame gains passes one guarded clause that checks
  # both, so a frame that exists is well formed.
  #
  # A column's type is worked out once, when its values enter through `new/1` or `put/3`, by one
  # pass that widens the type as each value arrives; `select/2` carries a column's type with it. The
  # type and the values are stored together, so a column cannot exist without its type. An
  # expression is evaluated into such a pair, its type and its values, so `mutate/2` puts it as it
  # is, `filter/2` reads its booleans, and an aggregate's column keeps its type or takes its own.

  @behaviour Giggly.DataFrame

  alias Giggly.DataFrame

  @enforce_keys [:reversed_names, :columns, :row_count]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          reversed_names: [DataFrame.name()],
          columns: %{optional(DataFrame.name()) => {DataFrame.dtype(), list()}},
          row_count: non_neg_integer()
        }

  # Explorer's representations of the non-finite floats.
  @non_finite_floats [:nan, :infinity, :neg_infinity]

  @impl DataFrame
  def new([]), do: empty(0)

  def new([first | _rest] = columns) when is_list(elem(first, 1)) do
    Enum.reduce(columns, empty(length(elem(first, 1))), fn column, frame ->
      {name, entered} = entered(column)
      add_column(frame, name, entered)
    end)
  end

  @impl DataFrame
  def names(%__MODULE__{reversed_names: reversed_names}), do: Enum.reverse(reversed_names)

  @impl DataFrame
  def row_count(%__MODULE__{row_count: row_count}), do: row_count

  @impl DataFrame
  def dtypes(%__MODULE__{columns: columns}) do
    Map.new(columns, fn {name, {dtype, _values}} -> {name, dtype} end)
  end

  @impl DataFrame
  def select(%__MODULE__{row_count: row_count} = frame, renames) do
    Enum.reduce(renames, empty(row_count), fn {new_name, existing_name}, selected ->
      add_column(selected, new_name, column(frame, existing_name))
    end)
  end

  @impl DataFrame
  def pull(%__MODULE__{} = frame, name) do
    {_dtype, values} = column(frame, name)
    values
  end

  @impl DataFrame
  def put(%__MODULE__{} = frame, name, values), do: put_entered(frame, entered({name, values}))

  @impl DataFrame
  def put(%__MODULE__{} = frame, name, values, :category),
    do: put_entered(frame, entered({name, values, :category}))

  # A column replaced where it is, or else added.
  defp put_entered(
         %__MODULE__{columns: columns, row_count: row_count} = frame,
         {name, {_dtype, values} = column}
       )
       when is_map_key(columns, name) and length(values) == row_count do
    %{frame | columns: Map.put(columns, name, column)}
  end

  defp put_entered(%__MODULE__{} = frame, {name, column}), do: add_column(frame, name, column)

  @impl DataFrame
  def split(%__MODULE__{columns: columns} = frame, name) do
    keys = pull(frame, name)

    # Each column's values grouped by the row's key, in row order, keeping the column's type.
    grouped =
      Map.new(columns, fn {column_name, {dtype, values}} ->
        by_key =
          keys
          |> Enum.zip(values)
          |> Enum.group_by(fn {key, _value} -> key end, fn {_key, value} -> value end)

        {column_name, {dtype, by_key}}
      end)

    keys
    |> Enum.frequencies()
    |> Map.new(fn {key, row_count} -> {key, part(frame, grouped, key, row_count)} end)
  end

  @impl DataFrame
  def slice(%__MODULE__{columns: columns} = frame, indices) do
    sliced =
      Map.new(columns, fn {name, {dtype, values}} ->
        by_index = List.to_tuple(values)
        {name, {dtype, Enum.map(indices, fn index -> elem(by_index, index) end)}}
      end)

    %{frame | columns: sliced, row_count: length(indices)}
  end

  @impl DataFrame
  def filter(%__MODULE__{} = frame, expression) do
    {dtype, kept} = evaluated(frame, expression)
    booleans(dtype)

    indices =
      kept
      |> Enum.with_index()
      |> Enum.flat_map(fn {keep, index} -> if keep == true, do: [index], else: [] end)

    slice(frame, indices)
  end

  @impl DataFrame
  def mutate(%__MODULE__{} = frame, columns) do
    columns
    |> Enum.map(fn {name, expression} -> {name, evaluated(frame, expression)} end)
    |> Enum.reduce(frame, fn computed, mutated -> put_entered(mutated, computed) end)
  end

  # An expression's column over the frame's rows: its type and its values, as the frame's
  # Expressions comment describes.
  defp evaluated(frame, name) when is_binary(name), do: column(frame, name)

  defp evaluated(frame, name) when is_atom(name) and not is_boolean(name) and not is_nil(name),
    do: column(frame, name)

  defp evaluated(frame, {:constant, value}), do: constant(frame, value)

  defp evaluated(frame, value) when is_number(value) or is_boolean(value),
    do: constant(frame, value)

  defp evaluated(frame, %struct{} = value) when struct in [Date, Time, NaiveDateTime, DateTime],
    do: constant(frame, value)

  defp evaluated(frame, {:is_finite, [argument]}) do
    {dtype, values} = evaluated(frame, argument)
    numbers(dtype)
    {:boolean, Enum.map(values, &finite/1)}
  end

  defp evaluated(frame, {:and, [left, right]}) do
    {left_dtype, left_values} = evaluated(frame, left)
    {right_dtype, right_values} = evaluated(frame, right)
    booleans(left_dtype)
    booleans(right_dtype)
    {:boolean, Enum.zip_with(left_values, right_values, &both/2)}
  end

  defp constant(%__MODULE__{row_count: row_count}, value),
    do: typed({:constant, value}, List.duplicate(value, row_count))

  # An operation's argument of the type it takes, or a `FunctionClauseError`, whether or not the
  # column has rows, as an engine checks an expression's types before it runs.
  defp numbers(dtype) when dtype in [:integer, :float, :null], do: :ok
  defp booleans(dtype) when dtype in [:boolean, :null], do: :ok

  # Whether a number is finite, missing where it is.
  defp finite(nil), do: nil
  defp finite(value) when is_number(value), do: true
  defp finite(value) when value in @non_finite_floats, do: false

  # Whether both are true, by SQL's three-valued logic: false beats missing, and missing beats
  # true.
  defp both(false, _right), do: false
  defp both(_left, false), do: false
  defp both(true, true), do: true
  defp both(_left, _right), do: nil

  @impl DataFrame
  def summarise(%__MODULE__{} = frame, by, aggregates) do
    keys =
      by
      |> Enum.map(fn name -> pull(frame, name) end)
      |> Enum.zip_with(fn values -> values end)

    groups =
      keys
      |> Enum.with_index()
      |> Enum.group_by(fn {key, _index} -> key end, fn {_key, index} -> index end)
      |> Enum.sort_by(fn {key, _indices} -> Enum.map(key, &missing_last/1) end)

    by_columns =
      by
      |> Enum.with_index()
      |> Enum.map(fn {name, position} ->
        {dtype, _values} = column(frame, name)
        {name, {dtype, Enum.map(groups, fn {key, _indices} -> Enum.at(key, position) end)}}
      end)

    aggregated =
      Enum.map(aggregates, fn {name, aggregate} ->
        {name, aggregated(frame, aggregate, groups)}
      end)

    Enum.reduce(by_columns ++ aggregated, empty(length(groups)), fn {name, column}, summarised ->
      add_column(summarised, name, column)
    end)
  end

  defp empty(row_count), do: %__MODULE__{reversed_names: [], columns: %{}, row_count: row_count}

  # A value's place in the order `summarise/3` sorts by: by value, a missing one last.
  defp missing_last(nil), do: {1, nil}
  defp missing_last(value), do: {0, value}

  # The aggregate's column, its value for each group in the groups' order, typed.
  defp aggregated(frame, {:sum, [name]}, groups),
    do: aggregated(frame, {:sum, [name], []}, groups)

  defp aggregated(frame, {:sum, [name], options}, groups) when is_list(options) do
    validated = Keyword.validate!(options, summation: :compensated, missing: :propagate)
    summation = Keyword.fetch!(validated, :summation)
    missing = Keyword.fetch!(validated, :missing)

    sums =
      frame
      |> summed_column(name)
      |> by_group(groups, fn values -> sum(values, summation, missing) end)

    typed(name, sums)
  end

  defp aggregated(frame, {:n_distinct, [name]}, groups) do
    counts =
      frame
      |> pull(name)
      |> by_group(groups, &distinct_count/1)

    {:integer, counts}
  end

  defp aggregated(frame, {:first, [name]}, groups) do
    {dtype, values} = column(frame, name)
    {dtype, by_group(values, groups, fn [first | _rest] -> first end)}
  end

  defp distinct_count(values) do
    values
    |> Enum.uniq()
    |> length()
  end

  # Each group's values of a column, in row order, as `reduce` reduces them, in the groups' order.
  defp by_group(values, groups, reduce) do
    by_index = List.to_tuple(values)

    Enum.map(groups, fn {_key, indices} ->
      group_values = Enum.map(indices, fn index -> elem(by_index, index) end)
      reduce.(group_values)
    end)
  end

  defp summed_column(frame, name) do
    case column(frame, name) do
      {dtype, values} when dtype in [:integer, :float, :null] ->
        values

      {dtype, _values} ->
        raise ArgumentError,
              "a sum adds numbers, but the column #{inspect(name)} is a #{inspect(dtype)} column"
    end
  end

  # The sum of `values`, each missing one, `nil` or a non-finite float, making it missing or left
  # out as `missing` says.
  defp sum(values, summation, :propagate) do
    if Enum.all?(values, &is_number/1), do: added(values, summation), else: nil
  end

  defp sum(values, summation, :skip) do
    values
    |> Enum.filter(&is_number/1)
    |> added(summation)
  end

  defp added(values, :plain), do: Enum.reduce(values, 0.0, &+/2)

  # Neumaier's compensated sum: each addition's rounding error, found exactly from the two values
  # and their rounded sum, is kept apart and added back once at the end.
  defp added(values, :compensated) do
    {total, compensation} =
      Enum.reduce(values, {0.0, 0.0}, fn value, {total, compensation} ->
        sum = total + value
        {sum, compensation + rounding_error(total, value, sum)}
      end)

    total + compensation
  end

  defp rounding_error(total, value, sum) when abs(total) >= abs(value), do: total - sum + value
  defp rounding_error(total, value, sum), do: value - sum + total

  # The frame of the `row_count` rows whose key is `key`, from the columns grouped by key.
  defp part(%__MODULE__{reversed_names: reversed_names}, grouped, key, row_count) do
    columns =
      Map.new(grouped, fn {column_name, {dtype, by_key}} ->
        {column_name, {dtype, Map.fetch!(by_key, key)}}
      end)

    %__MODULE__{reversed_names: reversed_names, columns: columns, row_count: row_count}
  end

  defp column(%__MODULE__{columns: columns}, name) when is_map_key(columns, name),
    do: Map.fetch!(columns, name)

  # The one way a frame gains a column, so the shape is checked in one place.
  defp add_column(%__MODULE__{columns: columns, row_count: row_count} = frame, name, column)
       when not is_map_key(columns, name) and length(elem(column, 1)) == row_count do
    %{
      frame
      | reversed_names: [name | frame.reversed_names],
        columns: Map.put(columns, name, column)
    }
  end

  # A column as `new/1` or `put/3` and `put/4` are given it, typed: a category is typed as any
  # column, then declared one.
  defp entered({name, values}), do: {name, typed(name, values)}

  defp entered({name, values, :category}) do
    case typed(name, values) do
      {:term, typed_values} ->
        witness = Enum.find(typed_values, fn value -> value != nil end)

        raise ArgumentError,
              "the column #{inspect(name)} is declared a category, but its values have no type " <>
                "of their own (#{inspect(witness)})"

      {_dtype, typed_values} ->
        {name, {:category, typed_values}}
    end
  end

  # Folds the values into the column's type, keeping the first value of that type so a value that
  # disagrees can be reported beside it.
  defp typed(name, values) do
    {dtype, _witness} =
      Enum.reduce(values, {:null, nil}, fn value, typed_so_far ->
        widen(name, typed_so_far, value)
      end)

    {dtype, cast(dtype, values)}
  end

  # A column of floats holds only floats: an integer among them becomes one, as Explorer casts a
  # mix of integers and floats, so `4` and `4.0` are one value wherever values are compared.
  defp cast(:float, values), do: Enum.map(values, &as_float/1)
  defp cast(_dtype, values), do: values

  defp as_float(value) when is_integer(value), do: value / 1
  defp as_float(value), do: value

  defp widen(_name, typed_so_far, nil), do: typed_so_far
  defp widen(_name, {:null, _witness}, value), do: {kind(value), value}

  defp widen(name, {dtype, witness} = typed_so_far, value) do
    case {dtype, kind(value)} do
      {same, same} -> typed_so_far
      {:float, :integer} -> typed_so_far
      {:integer, :float} -> {:float, value}
      {_dtype, _kind} -> raise ArgumentError, mixed_message(name, witness, value)
    end
  end

  defp kind(value) when is_integer(value), do: :integer
  defp kind(value) when is_float(value) or value in @non_finite_floats, do: :float
  defp kind(value) when is_boolean(value), do: :boolean
  defp kind(value) when is_atom(value), do: :atom
  defp kind(value) when is_binary(value), do: :string
  defp kind(%Date{}), do: :date
  defp kind(%Time{}), do: :time
  defp kind(%NaiveDateTime{}), do: :naive_datetime
  defp kind(%DateTime{}), do: :datetime
  defp kind(_value), do: :term

  defp mixed_message(name, witness, value) do
    "the column #{inspect(name)} holds values of more than one type " <>
      "(#{inspect(witness)} and #{inspect(value)}); give each column one type"
  end
end
