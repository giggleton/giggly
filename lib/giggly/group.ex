defmodule Giggly.Group do
  @moduledoc """
  The `group` column: which rows of a layer belong to one series.

  A stat computes per group, a position stacks and dodges by group, and a path joins the rows of
  one group, so every layer frame gets a `:group` column of integer ids. `add/2` writes it once,
  right after the layer's mapping is evaluated: before any scale maps a discrete position to
  numbers, after which nothing could tell it was discrete.

  The ids are ggplot2's (`add_group()` and `id()`):

    * With a mapped `group`, its values are numbered 1, 2, … in sorted order, and nothing else
      counts.
    * Otherwise each combination of the discrete columns' values is numbered 1, 2, … in sorted
      order, comparing the columns one by one in the frame's column order, and only combinations
      that occur get an id. A column is discrete when its type is `:string`, `:boolean` or
      `:atom`.
    * With no discrete column, every row is `-1`, so "no grouping" stays distinguishable from a
      grouping that found one group.

  A combination's id depends only on its values, so the same combination has the same id in every
  panel, and stacking and dodging order agree between facets. "Sorted" means by the key the caller
  gives for each value. The assembly gives the order a discrete scale gives its levels
  (`Giggly.Scale.level_key/1`), so group ids follow the order the same values take on an axis or a
  legend; when that order can be configured, the assembly will give the configured one. Grouping
  itself knows nothing about scales.
  """

  # Grouping reads and writes a frame; the order it numbers by is handed to it.
  use Boundary, deps: [Giggly.DataFrame], exports: []

  alias Giggly.DataFrame

  @discrete_dtypes [:string, :boolean, :atom]
  @no_group -1

  @doc """
  The frame with a `:group` column, replacing a mapped one, numbering values in the order
  `order_key` gives: it is called on each value and its results compared in Erlang term order.

  Without a mapped `group`, the discrete columns' combinations are numbered. Ordered as a discrete
  scale orders its levels, `"a"` comes first and `nil` last, and the float column `y` does not
  count:

      iex> frame = Giggly.DataFrame.new(x: ["b", "a", "b", nil], y: [21.0, 22.8, 21.4, 18.7])
      iex> frame |> Giggly.Group.add(&Giggly.Scale.level_key/1) |> Giggly.DataFrame.pull(:group)
      [2, 1, 2, 3]

  Two discrete columns are compared one at a time in column order, so every `false` in `manual`
  sorts before every `true`:

      iex> frame =
      ...>   Giggly.DataFrame.new(
      ...>     manual: [true, false, true, false],
      ...>     shape: [:circle, :square, :square, :circle]
      ...>   )
      iex> frame |> Giggly.Group.add(&Giggly.Scale.level_key/1) |> Giggly.DataFrame.pull(:group)
      [3, 2, 4, 1]

  A mapped `group` is renumbered on its own values, in sorted order, and the discrete `x` is
  ignored:

      iex> frame = Giggly.DataFrame.new(group: [10, 2, 10], x: ["a", "b", "c"])
      iex> frame |> Giggly.Group.add(&Giggly.Scale.level_key/1) |> Giggly.DataFrame.pull(:group)
      [2, 1, 2]

  With no discrete column there is no grouping:

      iex> frame = Giggly.DataFrame.new(x: [2.62, 2.875], y: [21.0, 22.8])
      iex> frame |> Giggly.Group.add(&Giggly.Scale.level_key/1) |> Giggly.DataFrame.pull(:group)
      [-1, -1]
  """
  @spec add(DataFrame.t(), (term() -> term())) :: DataFrame.t()
  def add(frame, order_key) when is_function(order_key, 1),
    do: DataFrame.put(frame, :group, ids(frame, key_names(frame), order_key))

  defp key_names(frame) do
    case DataFrame.dtypes(frame) do
      %{group: _dtype} ->
        [:group]

      dtypes ->
        frame
        |> DataFrame.names()
        |> Enum.filter(fn name -> Map.fetch!(dtypes, name) in @discrete_dtypes end)
    end
  end

  defp ids(frame, [], _order_key), do: List.duplicate(@no_group, DataFrame.row_count(frame))

  defp ids(frame, names, order_key) do
    rows =
      names
      |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
      |> Enum.zip()

    id_by_row =
      rows
      |> Enum.uniq()
      |> Enum.sort_by(fn row -> sort_key(row, order_key) end)
      |> Enum.with_index(1)
      |> Map.new()

    Enum.map(rows, fn row -> Map.fetch!(id_by_row, row) end)
  end

  # A row's values in key order, each turned into the caller's sort key; equal-size lists compare
  # element by element, so the first key column decides first.
  defp sort_key(row, order_key) do
    row
    |> Tuple.to_list()
    |> Enum.map(order_key)
  end
end
