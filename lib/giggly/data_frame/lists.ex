defmodule Giggly.DataFrame.Lists do
  @moduledoc """
  The pure-Elixir data frame: each column is a list. Callers use `Giggly.DataFrame`, which
  dispatches here.

  A frame keeps a map from column name to values, the names newest first (reversed when `names/1`
  asks, so gaining a column never walks the list), and its row count, so a `select/2` that keeps
  no column keeps the rows. Every column has exactly `row_count` values and no name appears twice:
  every column a frame gains passes one guarded clause that checks both, so a frame that exists is
  well formed.
  """

  @behaviour Giggly.DataFrame

  alias Giggly.DataFrame

  @enforce_keys [:reversed_names, :columns, :row_count]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          reversed_names: [DataFrame.name()],
          columns: %{optional(DataFrame.name()) => list()},
          row_count: non_neg_integer()
        }

  @impl DataFrame
  def new([]), do: empty(0)

  def new([{_name, values} | _rest] = columns) when is_list(values) do
    Enum.reduce(columns, empty(length(values)), &add_column/2)
  end

  @impl DataFrame
  def names(%__MODULE__{reversed_names: reversed_names}), do: Enum.reverse(reversed_names)

  @impl DataFrame
  def row_count(%__MODULE__{row_count: row_count}), do: row_count

  @impl DataFrame
  def select(%__MODULE__{row_count: row_count} = frame, renames) do
    Enum.reduce(renames, empty(row_count), fn {new_name, existing_name}, selected ->
      add_column({new_name, pull(frame, existing_name)}, selected)
    end)
  end

  @impl DataFrame
  def pull(%__MODULE__{columns: columns}, name) when is_map_key(columns, name),
    do: Map.fetch!(columns, name)

  @impl DataFrame
  def put(%__MODULE__{columns: columns, row_count: row_count} = frame, name, values)
      when is_map_key(columns, name) and length(values) == row_count do
    %{frame | columns: Map.put(columns, name, values)}
  end

  def put(%__MODULE__{} = frame, name, values), do: add_column({name, values}, frame)

  defp empty(row_count), do: %__MODULE__{reversed_names: [], columns: %{}, row_count: row_count}

  # The one way a frame gains a column, so the shape is checked in one place.
  defp add_column({name, values}, %__MODULE__{columns: columns, row_count: row_count} = frame)
       when not is_map_key(columns, name) and length(values) == row_count do
    %{
      frame
      | reversed_names: [name | frame.reversed_names],
        columns: Map.put(columns, name, values)
    }
  end
end
