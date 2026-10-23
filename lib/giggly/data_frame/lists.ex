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
  # A category's type holds its levels and whether it is ordered, `{:category, levels, ordered}`,
  # so every operation that carries a type carries them, and `dtypes/1` reports it as `:category`;
  # its values are its levels' own terms, or `nil`, so a value is one of its levels by equality.

  @behaviour Giggly.DataFrame

  alias Giggly.DataFrame
  alias Giggly.DataFrame.Arithmetic

  @enforce_keys [:reversed_names, :columns, :row_count]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          reversed_names: [DataFrame.name()],
          columns: %{optional(DataFrame.name()) => {dtype(), list()}},
          row_count: non_neg_integer()
        }

  # A column's type as the frame holds it: `t:Giggly.DataFrame.dtype/0`, but a category's, which
  # holds its levels and whether it is ordered.
  @typep dtype :: DataFrame.dtype() | {:category, list(), boolean()} | {:list, dtype()}

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
    Map.new(columns, fn {name, {dtype, _values}} -> {name, reported(dtype)} end)
  end

  # A type as `dtypes/1` reports it: a category's as `:category`, a list's by its values'.
  defp reported({:category, _levels, _ordered}), do: :category
  defp reported({:list, dtype}), do: {:list, reported(dtype)}
  defp reported(dtype), do: dtype

  # Every operation an expression or an aggregate names, each run below (`evaluated/2`,
  # `aggregated/3`).
  @impl DataFrame
  def operations(%__MODULE__{}) do
    [
      :<,
      :>,
      :and,
      :count,
      :cut,
      :first,
      :is_finite,
      :list,
      :log10,
      :max,
      :mean,
      :min,
      :n_distinct,
      :not,
      :or,
      :quantile,
      :sum
    ]
  end

  @impl DataFrame
  def category(%__MODULE__{} = frame, name), do: declaration(column(frame, name))

  defp declaration({{:category, levels, ordered}, _values}),
    do: {:category, levels: levels, ordered: ordered}

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
  def put(%__MODULE__{} = frame, name, values, category),
    do: put_entered(frame, entered({name, values, category}))

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

  @impl DataFrame
  def join(%__MODULE__{} = left, %__MODULE__{} = right, on) do
    Enum.each(on, fn name -> same_type(column(left, name), column(right, name)) end)
    matches = matches(left, right, on)
    joined = slice(left, Enum.map(matches, fn {left_index, _right_index} -> left_index end))
    right_indices = Enum.map(matches, fn {_left_index, right_index} -> right_index end)

    right
    |> names()
    |> Enum.reject(fn name -> name in on end)
    |> Enum.reduce(joined, fn name, joined_so_far ->
      {dtype, values} = column(right, name)
      add_column(joined_so_far, name, {dtype, taken(values, right_indices)})
    end)
  end

  # Two key columns are joined only when they are of one type, as Explorer refuses two.
  defp same_type({dtype, _left_values}, {dtype, _right_values}), do: :ok

  # Each left row's index, in order, paired with the index of each right row whose keys equal its
  # own, in right's order, or with `nil` where none does; a missing key equals nothing.
  defp matches(left, right, on) do
    right_indices_by_key =
      right
      |> keys(on)
      |> Enum.with_index()
      |> Enum.reject(fn {key, _index} -> nil in key end)
      |> Enum.group_by(fn {key, _index} -> key end, fn {_key, index} -> index end)

    left
    |> keys(on)
    |> Enum.with_index()
    |> Enum.flat_map(fn {key, left_index} ->
      paired(left_index, Map.get(right_indices_by_key, key, []))
    end)
  end

  defp paired(left_index, []), do: [{left_index, nil}]

  defp paired(left_index, right_indices),
    do: Enum.map(right_indices, fn right_index -> {left_index, right_index} end)

  # Each row's values of the columns `on`, in row order.
  defp keys(frame, on) do
    on
    |> Enum.map(fn name -> pull(frame, name) end)
    |> Enum.zip_with(fn values -> values end)
  end

  # The values at `indices`, missing where an index is.
  defp taken(values, indices) do
    by_index = List.to_tuple(values)
    Enum.map(indices, fn index -> if index, do: elem(by_index, index) end)
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

  defp evaluated(frame, {comparison, [left, right]}) when comparison in [:<, :>] do
    {left_dtype, left_values} = evaluated(frame, left)
    {right_dtype, right_values} = evaluated(frame, right)
    numbers(left_dtype)
    numbers(right_dtype)

    compared =
      Enum.zip_with(left_values, right_values, fn left_value, right_value ->
        compared(comparison, left_value, right_value)
      end)

    {:boolean, compared}
  end

  defp evaluated(frame, {:or, [left, right]}) do
    {left_dtype, left_values} = evaluated(frame, left)
    {right_dtype, right_values} = evaluated(frame, right)
    booleans(left_dtype)
    booleans(right_dtype)
    {:boolean, Enum.zip_with(left_values, right_values, &either/2)}
  end

  defp evaluated(frame, {:not, [argument]}) do
    {dtype, values} = evaluated(frame, argument)
    booleans(dtype)
    {:boolean, Enum.map(values, &negated/1)}
  end

  defp evaluated(frame, {:log10, [argument]}) do
    {dtype, values} = evaluated(frame, argument)
    numbers(dtype)
    {:float, Enum.map(values, &logarithm/1)}
  end

  defp evaluated(frame, {:cut, [argument], options}) do
    {dtype, values} = evaluated(frame, argument)
    numbers(dtype)

    breaks =
      options
      |> Keyword.fetch!(:breaks)
      |> List.to_tuple()

    closed = Keyword.fetch!(options, :closed)
    {:integer, Enum.map(values, fn value -> interval(value, breaks, closed) end)}
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

  # A number's base-10 logarithm, as R's `log10()` gives it: minus infinity for zero, NaN for a
  # negative number, minus infinity included, missing for a missing value, and a positive number's
  # by C's `log10()`, as R's, which a float divided by `ln(10)` misses in the last bit.
  defp logarithm(nil), do: nil
  defp logarithm(value) when is_number(value) and value > 0, do: :math.log10(value)
  defp logarithm(value) when value == 0, do: :neg_infinity
  defp logarithm(:infinity), do: :infinity
  defp logarithm(_negative_or_nan), do: :nan

  # The interval of `breaks` a number falls in, numbered from 1, as R's `.bincode()` finds it with
  # `include.lowest = TRUE`: missing for a missing value, NaN or a number outside the breaks; else
  # a halving search, a number on a break inside them going to the interval it closes.
  defp interval(nil, _breaks, _closed), do: nil
  defp interval(:nan, _breaks, _closed), do: nil

  defp interval(value, breaks, closed) when closed in [:right, :left] do
    last = tuple_size(breaks) - 1
    lowest = elem(breaks, 0)
    highest = elem(breaks, last)

    if Arithmetic.less?(value, lowest) or Arithmetic.less?(highest, value) do
      nil
    else
      search(value, breaks, closed, 0, last)
    end
  end

  defp search(_value, _breaks, _closed, low, high) when high - low < 2, do: low + 1

  defp search(value, breaks, closed, low, high) do
    middle = div(low + high, 2)
    break = elem(breaks, middle)

    if Arithmetic.less?(break, value) or (closed == :left and value == break),
      do: search(value, breaks, closed, middle, high),
      else: search(value, breaks, closed, low, middle)
  end

  # Whether `left` is below (`:<`) or above (`:>`) `right`, missing where either is, NaN above
  # every number and both infinities, as Explorer orders it.
  defp compared(_comparison, nil, _right), do: nil
  defp compared(_comparison, _left, nil), do: nil
  defp compared(:<, left, right), do: Arithmetic.sort_key(left) < Arithmetic.sort_key(right)
  defp compared(:>, left, right), do: Arithmetic.sort_key(left) > Arithmetic.sort_key(right)

  # Whether either is true, by SQL's three-valued logic: true beats missing, and missing beats
  # false.
  defp either(true, _right), do: true
  defp either(_left, true), do: true
  defp either(false, false), do: false
  defp either(_left, _right), do: nil

  # The opposite of a boolean, missing where it is.
  defp negated(nil), do: nil
  defp negated(boolean), do: not boolean

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
    validated = Keyword.validate!(options, summation: :extended, missing: :propagate)
    summation = Keyword.fetch!(validated, :summation)
    missing = Keyword.fetch!(validated, :missing)
    {_dtype, values} = numbers_column(frame, name, "a sum adds numbers")

    typed(
      name,
      by_group(values, groups, fn group_values -> sum(group_values, summation, missing) end)
    )
  end

  defp aggregated(frame, {:quantile, [name], options}, groups) when is_list(options) do
    probability =
      options
      |> Keyword.validate!([:probability])
      |> probability()

    {_dtype, values} = numbers_column(frame, name, "a quantile orders numbers")

    quantiles =
      by_group(values, groups, fn group_values -> quantile(present(group_values), probability) end)

    {:float, quantiles}
  end

  defp aggregated(frame, {:mean, [name]}, groups) do
    {_dtype, values} = numbers_column(frame, name, "a mean averages numbers")
    {:float, by_group(values, groups, &Arithmetic.mean/1)}
  end

  defp aggregated(frame, {:min, [name]}, groups) do
    {dtype, values} = numbers_column(frame, name, "a minimum compares numbers")
    {dtype, by_group(values, groups, fn group_values -> least(present(group_values)) end)}
  end

  defp aggregated(frame, {:max, [name]}, groups) do
    {dtype, values} = numbers_column(frame, name, "a maximum compares numbers")
    {dtype, by_group(values, groups, fn group_values -> greatest(present(group_values)) end)}
  end

  defp aggregated(frame, {:count, [name]}, groups) do
    counts =
      frame
      |> pull(name)
      |> by_group(groups, fn group_values -> length(present(group_values)) end)

    {:integer, counts}
  end

  defp aggregated(frame, {:list, [name]}, groups) do
    {dtype, values} = column(frame, name)
    {{:list, dtype}, by_group(values, groups, fn group_values -> group_values end)}
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

  # A column of numbers, or an `ArgumentError` saying what `purpose` needs, naming the column and
  # its type.
  defp numbers_column(frame, name, purpose) do
    case column(frame, name) do
      {dtype, _values} = numbers when dtype in [:integer, :float, :null] ->
        numbers

      {dtype, _values} ->
        raise ArgumentError,
              "#{purpose}, but the column #{inspect(name)} is a #{inspect(dtype)} column"
    end
  end

  # The values that are not missing, neither `nil` (R's `NA`) nor NaN, as R's `is.na()` reads one.
  defp present(values), do: Enum.reject(values, fn value -> value in [nil, :nan] end)

  # The probability a quantile is taken at, from 0 to 1.
  defp probability(probability: probability)
       when is_number(probability) and probability >= 0 and probability <= 1,
       do: probability

  # The quantile at `probability` of numbers none of which is missing, as R's `quantile()` takes it
  # by its default, type 7: the numbers sorted, an infinity at either end, and the one at the
  # place `1 + (n - 1) * probability` counting from 1, or, where the place falls between two that
  # differ, `(1 - h) * lower + h * higher` for the fraction `h` of the way, in R's arithmetic and in
  # that order, which differs from `lower + h * (higher - lower)` in the last digit about one time
  # in ten. Missing where there are none.
  defp quantile([], _probability), do: nil

  defp quantile(values, probability) do
    sorted =
      values
      |> Enum.sort_by(&Arithmetic.sort_key/1)
      |> List.to_tuple()

    place = 1 + (tuple_size(sorted) - 1) * probability
    low = floor(place)
    lower = elem(sorted, low - 1)
    higher = elem(sorted, ceil(place) - 1)
    fraction = place - low

    if place > low and higher != lower do
      from_lower = Arithmetic.multiply(1 - fraction, lower)
      from_higher = Arithmetic.multiply(fraction, higher)
      Arithmetic.add(from_lower, from_higher)
    else
      as_float(lower)
    end
  end

  # The least and the greatest of numbers none of which is missing, an infinity below or above
  # every number; missing where there are none.
  defp least([]), do: nil
  defp least(values), do: Enum.min_by(values, &Arithmetic.sort_key/1)

  defp greatest([]), do: nil
  defp greatest(values), do: Enum.max_by(values, &Arithmetic.sort_key/1)

  # The sum of `values` as R adds doubles (`Arithmetic.sum/2`), a missing one, `nil` (R's `NA`) or
  # NaN, making it missing or left out, as `missing` says.
  defp sum(values, summation, :propagate), do: Arithmetic.sum(values, summation)

  defp sum(values, summation, :skip) do
    values
    |> Enum.reject(fn value -> value in [nil, :nan] end)
    |> Arithmetic.sum(summation)
  end

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
  # column, then declared one, with its levels.
  defp entered({name, values}), do: {name, typed(name, values)}
  defp entered({name, values, :category}), do: entered({name, values, {:category, []}})

  defp entered({name, values, {:category, options}}) do
    validated = Keyword.validate!(options, levels: :none, ordered: false)
    ordered = ordered(Keyword.fetch!(validated, :ordered))
    {dtype, typed_values} = categorised(name, "values", typed(name, values))
    {levels, category_values} = levelled(name, dtype, typed_values, validated[:levels])
    {name, {{:category, levels, ordered}, category_values}}
  end

  defp ordered(ordered) when is_boolean(ordered), do: ordered

  # The values of a category, or its levels, as typed, unless they have no type of their own or
  # are lists, which a category cannot hold.
  defp categorised(name, what, {:term, typed_values}) do
    raise ArgumentError,
          "the column #{inspect(name)} is declared a category, but its #{what} have no type of " <>
            "their own (#{inspect(witness(typed_values))})"
  end

  defp categorised(name, what, {{:list, _values_dtype}, typed_values}) do
    raise ArgumentError,
          "the column #{inspect(name)} is declared a category, but its #{what} are lists " <>
            "(#{inspect(witness(typed_values))}), which a category cannot hold"
  end

  defp categorised(_name, _what, typed), do: typed

  # A category's levels and its values, each value the level equal to it or `nil`: the levels
  # given, typed with the values, or else the distinct values in order.
  defp levelled(_name, dtype, values, :none) do
    levels =
      values
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&as_level/1)
      |> Enum.uniq()
      |> sorted_levels(dtype)

    {levels, Enum.map(values, &as_level/1)}
  end

  defp levelled(name, dtype, values, levels) when is_list(levels) do
    if nil in levels do
      raise ArgumentError,
            "the column #{inspect(name)} is declared a category with nil among its levels, " <>
              "which is the missing value and never a level"
    end

    {levels_dtype, typed_levels} = categorised(name, "levels", typed(name, levels))

    case wider(dtype, levels_dtype) do
      {:ok, widened} ->
        category_levels =
          widened
          |> cast(typed_levels)
          |> Enum.map(&as_level/1)

        refuse_repeated_level(name, category_levels)
        level_set = MapSet.new(category_levels)

        category_values =
          widened
          |> cast(values)
          |> Enum.map(fn value -> among(as_level(value), level_set) end)

        {category_levels, category_values}

      :error ->
        raise ArgumentError,
              "the column #{inspect(name)} is declared a category whose levels " <>
                "(#{inspect(witness(typed_levels))}) are of another type than its values " <>
                "(#{inspect(witness(values))})"
    end
  end

  defp refuse_repeated_level(name, levels) do
    case levels -- Enum.uniq(levels) do
      [] ->
        :ok

      [repeated | _others] ->
        raise ArgumentError,
              "the column #{inspect(name)} is declared a category with the level " <>
                "#{inspect(repeated)} twice"
    end
  end

  # A value as a level holds it: a float with a zero's sign dropped, so `-0.0` and `0.0` are one
  # level, as R writes both `0`; any other value as it is, a missing one missing.
  defp as_level(value) when is_float(value), do: value + 0.0
  defp as_level(value), do: value

  # The level, if it is among the levels; else missing.
  defp among(level, level_set) do
    if MapSet.member?(level_set, level), do: level
  end

  # A category's levels in order when none are given, as R's `factor()` orders its values: numbers
  # by value, minus infinity first and NaN last; dates and times by time; anything else in term
  # order, so strings by their bytes and `false` before `true`.
  defp sorted_levels(levels, dtype) when dtype in [:integer, :float],
    do: Enum.sort_by(levels, &Arithmetic.sort_key/1)

  defp sorted_levels(levels, :date), do: Enum.sort(levels, Date)
  defp sorted_levels(levels, :time), do: Enum.sort(levels, Time)
  defp sorted_levels(levels, :naive_datetime), do: Enum.sort(levels, NaiveDateTime)
  defp sorted_levels(levels, :datetime), do: Enum.sort(levels, DateTime)
  defp sorted_levels(levels, _dtype), do: Enum.sort(levels)

  # The values typed as a column holding them, and cast to that type.
  defp typed(name, values) do
    dtype = values_type(name, values)
    {dtype, cast(dtype, values)}
  end

  defp witness(values), do: Enum.find(values, fn value -> value != nil end)

  # Folds the values into their type, a column's or a list's, keeping the first value of that type
  # so a value that disagrees can be reported beside it.
  defp values_type(name, values) do
    {dtype, _witness} =
      Enum.reduce(values, {:null, nil}, fn value, typed_so_far ->
        widen(name, typed_so_far, value)
      end)

    dtype
  end

  # A column of floats holds only floats: an integer among them becomes one, as Explorer casts a
  # mix of integers and floats, so `4` and `4.0` are one value wherever values are compared. A
  # list's values are cast as a column's, a missing list left missing.
  defp cast(:float, values), do: Enum.map(values, &as_float/1)

  defp cast({:list, values_dtype}, lists),
    do: Enum.map(lists, fn list -> cast_list(values_dtype, list) end)

  defp cast(_dtype, values), do: values

  defp cast_list(_values_dtype, nil), do: nil
  defp cast_list(values_dtype, list), do: cast(values_dtype, list)

  defp as_float(value) when is_integer(value), do: value / 1
  defp as_float(value), do: value

  defp widen(_name, typed_so_far, nil), do: typed_so_far

  defp widen(name, {dtype, witness} = typed_so_far, value) do
    case wider(dtype, kind(name, value)) do
      {:ok, ^dtype} -> typed_so_far
      {:ok, widened} -> {widened, value}
      :error -> raise ArgumentError, mixed_message(name, witness, value)
    end
  end

  # The type that holds values of both types, as Explorer widens a series: the type of no values
  # widens to any, integers and floats to floats, two lists by their values, and nothing else.
  defp wider(dtype, dtype), do: {:ok, dtype}
  defp wider(:null, dtype), do: {:ok, dtype}
  defp wider(dtype, :null), do: {:ok, dtype}
  defp wider(:integer, :float), do: {:ok, :float}
  defp wider(:float, :integer), do: {:ok, :float}

  defp wider({:list, left}, {:list, right}) do
    case wider(left, right) do
      {:ok, widened} -> {:ok, {:list, widened}}
      :error -> :error
    end
  end

  defp wider(_left, _right), do: :error

  # A list's kind is a list of its values' type, worked out as a column's.
  defp kind(name, values) when is_list(values), do: {:list, values_type(name, values)}
  defp kind(_name, value), do: kind(value)

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
