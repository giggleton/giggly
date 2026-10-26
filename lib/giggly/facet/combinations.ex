defmodule Giggly.Facet.Combinations do
  @moduledoc false

  # The combinations of the values of some of a facet's columns that the plot's data and every
  # layer's table make, and the panel each row of a table is drawn in by its combination: what
  # ggplot2's facets share in `combine_vars()` and `map_facet_data()`, which `Giggly.Facet.Wrap`
  # and `Giggly.Facet.Grid` call, a grid once for its rows' columns and once for its columns'.
  #
  # The combinations are those the tables make together, as `combine_vars()` makes them: each
  # combination of the columns' values in a table holding them all, and then, for each table
  # holding only some of them, in turn, each of its combinations of those with each combination of
  # the others' values made so far, so a value only such a table holds makes a combination with
  # each. A table holding none of them, or no rows, makes none, and unless some table holds them
  # all they are refused, naming what each lacks. They are ordered by the first column's values,
  # then the next's, each as R's vctrs combines the tables' columns: by their levels where every
  # table holding the column holds it as a category, the first's and then the levels each later
  # one adds; else as a discrete scale orders its levels, by the key the assembly hands over, so a
  # factor beside a column of text sorts as text. A missing value (`nil`) is a value of its own,
  # last.
  #
  # The layout carries each facet column, by its name in the data, as ggplot2's does, and each
  # row's panel is found from its values there. A table lacking some of the columns has each of
  # its rows repeated once for each combination of the missing columns' values in the layout, in
  # panel order, as ggplot2's `map_facet_data()` repeats them: all its rows for the first, then
  # all for the next, so one lacking them all is drawn in every panel.
  #
  # A strip writes a value as ggplot2's `label_value()` writes it, R's `as.character()`
  # (`Giggly.AsCharacter`: `4` for a whole float, `TRUE`), with a missing value written `NA`.

  alias Giggly.{AsCharacter, DataFrame}

  # The combinations of `columns`' values that `frames` make, the plot's data and then each
  # layer's table, each a list of values in the columns' order, sorted; `order_key` orders values
  # as a discrete scale orders its levels. `subject` names the facet and its columns in a refusal.
  @doc false
  @spec combine([DataFrame.t(), ...], [String.t(), ...], (term() -> term()), String.t()) ::
          [[term()], ...]
  def combine(frames, columns, order_key, subject) do
    column_keys = Enum.map(columns, fn name -> column_key(frames, name, order_key) end)

    {complete, partial} =
      Enum.split_with(frames, fn frame -> held(frame, columns) == columns end)

    check_complete(complete, frames, columns, subject)

    made =
      complete
      |> Enum.flat_map(fn frame -> rows_of(frame, columns) end)
      |> Enum.uniq()

    combinations =
      partial
      |> Enum.reduce(made, fn frame, so_far -> crossed(frame, so_far, columns) end)
      |> Enum.map(fn values -> Enum.map(columns, fn name -> Map.fetch!(values, name) end) end)
      |> Enum.sort_by(fn values -> sort_key(values, column_keys) end)

    case combinations do
      [] -> raise ArgumentError, no_panels_message(subject)
      combinations -> combinations
    end
  end

  # The table `frame` with a `:panel` column giving each row's panel in `layout`, whose `columns`
  # hold each panel's values of the facet's columns; a table lacking some of them repeated in
  # each panel of the values it has.
  @doc false
  @spec assign_panels(DataFrame.t(), DataFrame.t(), [String.t(), ...]) :: DataFrame.t()
  def assign_panels(frame, layout, columns) do
    panel_by_values =
      [:panel | columns]
      |> Enum.map(fn name -> DataFrame.pull(layout, name) end)
      |> Enum.zip_with(fn [panel | values] -> {values, panel} end)
      |> Map.new()

    missing = columns -- held(frame, columns)
    fills = fills(layout, missing)
    rows = Enum.to_list(0..(DataFrame.row_count(frame) - 1)//1)
    repeated = DataFrame.slice(frame, Enum.flat_map(fills, fn _fill -> rows end))
    fill_by_row = Enum.flat_map(fills, fn fill -> Enum.map(rows, fn _row -> fill end) end)

    panels =
      columns
      |> Enum.map(fn name -> facet_values(name, missing, repeated, fill_by_row) end)
      |> Enum.zip_with(fn values -> Map.fetch!(panel_by_values, values) end)

    DataFrame.put(repeated, :panel, panels)
  end

  # A value as its strip writes it, ggplot2's `label_value()`.
  @doc false
  @spec label(term()) :: String.t()
  def label(nil), do: "NA"
  def label(value), do: AsCharacter.text(value)

  # How a facet column's values are ordered: by the places of the levels of the tables holding it,
  # in table order, where every one holds it as a category, a missing value after them, as vctrs
  # combines factors; else by the caller's key, as vctrs makes a factor beside text text.
  defp column_key(frames, name, order_key) do
    holding = Enum.filter(frames, fn frame -> name in DataFrame.names(frame) end)

    if Enum.all?(holding, fn frame -> Map.fetch!(DataFrame.dtypes(frame), name) == :category end),
      do: level_place(holding, name),
      else: order_key
  end

  defp level_place(holding, name) do
    place_by_level =
      holding
      |> Enum.flat_map(fn frame -> levels(frame, name) end)
      |> Enum.uniq()
      |> Enum.with_index()
      |> Map.new()

    fn
      nil -> {1, nil}
      level -> {0, Map.fetch!(place_by_level, level)}
    end
  end

  defp levels(frame, name) do
    {:category, declaration} = DataFrame.category(frame, name)
    Keyword.fetch!(declaration, :levels)
  end

  # A combination's values in column order, each turned into its column's sort key.
  defp sort_key(values, column_keys),
    do: Enum.zip_with(values, column_keys, fn value, column_key -> column_key.(value) end)

  # The combinations made so far, with each combination of the columns `frame` holds crossed with
  # each of the others' values made so far. A table holding none of them, or no rows, adds none.
  defp crossed(frame, made, columns) do
    held = held(frame, columns)
    others = columns -- held

    own =
      frame
      |> rows_of(held)
      |> Enum.uniq()

    crossings =
      for other <- Enum.map(made, fn values -> Map.take(values, others) end),
          values <- own,
          do: Map.merge(other, values)

    Enum.uniq(made ++ crossings)
  end

  # The facet columns `frame` holds, in the facet's order.
  defp held(frame, columns) do
    names = DataFrame.names(frame)
    Enum.filter(columns, fn name -> name in names end)
  end

  # Each row's values of `columns`, by column name.
  defp rows_of(frame, columns) do
    columns
    |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
    |> Enum.zip_with(fn values -> by_name(columns, values) end)
  end

  defp by_name(columns, values) do
    columns
    |> Enum.zip(values)
    |> Map.new()
  end

  # Each combination of the `missing` columns' values in the layout, by column name, in panel
  # order, a table's rows repeated once for each: one with none, when the table misses none.
  defp fills(_layout, []), do: [%{}]

  defp fills(layout, missing) do
    layout
    |> rows_of(missing)
    |> Enum.uniq()
  end

  # A facet column's value in each row of the repeated table: its own, or the fill it was repeated
  # for.
  defp facet_values(name, missing, repeated, fill_by_row) do
    if name in missing,
      do: Enum.map(fill_by_row, fn fill -> Map.fetch!(fill, name) end),
      else: DataFrame.pull(repeated, name)
  end

  defp check_complete([], frames, columns, subject) do
    lacking =
      frames
      |> Enum.with_index()
      |> Enum.map_join("; ", fn {frame, index} ->
        "#{table_name(index)} lacks #{inspect_all(columns -- held(frame, columns))}"
      end)

    raise ArgumentError,
          "#{subject} needs a table holding every column named, but none holds them all: " <>
            lacking
  end

  defp check_complete(_complete, _frames, _columns, _subject), do: :ok

  defp no_panels_message(subject),
    do: "#{subject} has no panels to make: the tables holding its columns have no rows"

  # The first table is the plot's data, and each after it a layer's, in the order added.
  defp table_name(0), do: "the plot's data"
  defp table_name(index), do: "the layer at index #{index - 1}'s table"

  defp inspect_all(terms), do: Enum.map_join(terms, ", ", &inspect/1)
end
