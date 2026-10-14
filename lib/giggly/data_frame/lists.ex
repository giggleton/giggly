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
  # type and the values are stored together, so a column cannot exist without its type.

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

  def new([{_name, values} | _rest] = columns) when is_list(values) do
    Enum.reduce(columns, empty(length(values)), fn {name, values}, frame ->
      add_column(frame, name, typed(name, values))
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
  def put(%__MODULE__{columns: columns, row_count: row_count} = frame, name, values)
      when is_map_key(columns, name) and length(values) == row_count do
    %{frame | columns: Map.put(columns, name, typed(name, values))}
  end

  def put(%__MODULE__{} = frame, name, values), do: add_column(frame, name, typed(name, values))

  defp empty(row_count), do: %__MODULE__{reversed_names: [], columns: %{}, row_count: row_count}

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

  # Folds the values into the column's type, keeping the first value of that type so a value that
  # disagrees can be reported beside it.
  defp typed(name, values) do
    {dtype, _witness} =
      Enum.reduce(values, {:null, nil}, fn value, typed_so_far ->
        widen(name, typed_so_far, value)
      end)

    {dtype, values}
  end

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
