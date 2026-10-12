defmodule Giggly.Group do
  @moduledoc """
  The `group` column: which rows of a layer belong to one series.

  A stat computes per group, a position stacks and dodges by group, and a path joins the rows of
  one group, so every layer frame gets a `:group` column of integer ids. `add/1` writes it once,
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
  panel, and stacking and dodging order agree between facets. Values sort with `nil` last and
  otherwise in Erlang term order: strings by their bytes, so `"B"` sorts before `"a"`, with no
  locale. Structs sort in term order too, so dates in a mapped `group` are not numbered in
  chronological order.
  """

  # Grouping reads and writes a frame and nothing else.
  use Boundary, deps: [Giggly.DataFrame], exports: []

  alias Giggly.DataFrame

  @discrete_dtypes [:string, :boolean, :atom]
  @no_group -1

  @doc """
  The frame with a `:group` column, replacing a mapped one.

  Without a mapped `group`, the discrete columns' combinations are numbered. Here `"a"` comes
  first, `nil` last, and the float column `y` does not count:

      iex> frame = Giggly.DataFrame.new(x: ["b", "a", "b", nil], y: [21.0, 22.8, 21.4, 18.7])
      iex> frame |> Giggly.Group.add() |> Giggly.DataFrame.pull(:group)
      [2, 1, 2, 3]

  Two discrete columns are compared one at a time in column order, so every `false` in `manual`
  sorts before every `true`:

      iex> frame =
      ...>   Giggly.DataFrame.new(
      ...>     manual: [true, false, true, false],
      ...>     shape: [:circle, :square, :square, :circle]
      ...>   )
      iex> frame |> Giggly.Group.add() |> Giggly.DataFrame.pull(:group)
      [3, 2, 4, 1]

  A mapped `group` is renumbered on its own values, in sorted order, and the discrete `x` is
  ignored:

      iex> frame = Giggly.DataFrame.new(group: [10, 2, 10], x: ["a", "b", "c"])
      iex> frame |> Giggly.Group.add() |> Giggly.DataFrame.pull(:group)
      [2, 1, 2]

  With no discrete column there is no grouping:

      iex> frame = Giggly.DataFrame.new(x: [2.62, 2.875], y: [21.0, 22.8])
      iex> frame |> Giggly.Group.add() |> Giggly.DataFrame.pull(:group)
      [-1, -1]
  """
  @spec add(DataFrame.t()) :: DataFrame.t()
  def add(frame), do: DataFrame.put(frame, :group, ids(frame, key_names(frame)))

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

  defp ids(frame, []), do: List.duplicate(@no_group, DataFrame.row_count(frame))

  defp ids(frame, names) do
    rows =
      names
      |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
      |> Enum.zip()

    id_by_row =
      rows
      |> Enum.uniq()
      |> Enum.sort_by(&sort_key/1)
      |> Enum.with_index(1)
      |> Map.new()

    Enum.map(rows, fn row -> Map.fetch!(id_by_row, row) end)
  end

  # Tuples of equal size compare element by element, so a tagged value sorts every present value
  # before every `nil`, and present values by term order among themselves.
  defp sort_key(row) do
    row
    |> Tuple.to_list()
    |> Enum.map(fn
      nil -> {1, nil}
      value -> {0, value}
    end)
  end
end
