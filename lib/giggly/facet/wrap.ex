defmodule Giggly.Facet.Wrap do
  @moduledoc false

  # Wrapped panels, ggplot2's `facet_wrap()`: a panel for each combination of the values of the
  # facet's columns that occurs in the data, laid out in rows. Its struct holds its parameters: the
  # columns it splits on, by the names the data gives them; the number of rows and of columns to lay
  # the panels out in, each `:none` when not given; and which axes' scales are free, ggplot2's
  # `scales`: `:fixed`, `:free_x`, `:free_y` or `:free`. Run it through `Giggly.Facet`.
  #
  # The panels are those the plot's data and every layer's table make together, as ggplot2's
  # `combine_vars()` makes them: each combination of the columns' values in a table holding them
  # all, and then, for each table holding only some of them, in turn, each of its combinations of
  # those with each combination of the others' values made so far, so a value only such a table
  # holds makes a panel with each. A table holding none of them, or no rows, makes none, and unless
  # some table holds them all the layout is refused, naming what each lacks. The panels are ordered
  # by the first column's values, then the next's, each as a discrete scale orders its levels, by
  # the key the assembly hands over, so a missing value (`nil`) gets a panel of its own, last. They
  # fill the layout a row at a time, left to right. With neither a number of rows nor of columns,
  # the layout is ggplot2's (R's `n2mfrow()`, rows and columns swapped): one row for up to three
  # panels, two for up to six, three for up to twelve, and beyond that as many columns as the
  # square root of the count, rounded up, and as many rows as those columns need. Given one, the
  # other is as many as the panels need; given both, they must hold every panel. On a fixed axis
  # every panel uses that axis's scale 1; on a free one each panel has a scale of its own, numbered
  # as the panel is, as ggplot2's layout numbers them.
  #
  # The layout carries each facet column, by its name in the data, as ggplot2's does, and each
  # row's panel is found from its values there. A table lacking some of the columns has each of its
  # rows repeated once for each combination of the missing columns' values in the layout, in panel
  # order, as ggplot2's `map_data()` repeats them: all its rows for the first, then all for the
  # next, so one lacking them all is drawn in every panel. It also says where each panel's axes and
  # strip go. A panel draws an axis on each side that has no panel beside it, ggplot2's axes at the
  # margins: below the last row, and below a panel with an empty cell under it, at the end of an
  # unfilled last row; and left of the first column. On a free axis every panel draws its own, since
  # no two share a scale. Each panel has a strip above it for each facet column, in the columns'
  # order, labelled with its value as ggplot2's `label_value()` writes it, here `to_string/1`, with
  # a missing value written `NA`.

  @enforce_keys [:facets, :nrow, :ncol, :scales]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          facets: [String.t()],
          nrow: pos_integer() | :none,
          ncol: pos_integer() | :none,
          scales: :fixed | :free_x | :free_y | :free
        }

  defimpl Giggly.Facet, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Facet

    alias Giggly.DataFrame

    # A fixed axis's one scale.
    @only_scale 1

    @impl Giggly.Facet
    def layout(%{facets: facets, scales: scales} = wrap, frames, order_key) do
      combinations = combinations(frames, facets, order_key)
      count = length(combinations)
      {_rows, columns} = dimensions(wrap, count)
      panels = Enum.to_list(1..count//1)
      places = Enum.map(panels, fn panel -> place(panel, columns) end)
      occupied = MapSet.new(places)
      free_x = scales in [:free_x, :free]
      free_y = scales in [:free_y, :free]

      DataFrame.new(
        [
          panel: panels,
          row: Enum.map(places, fn {row, _column} -> row end),
          column: Enum.map(places, fn {_row, column} -> column end)
        ] ++
          facet_columns(facets, combinations) ++
          [
            scale_x: scale_ids(panels, free_x),
            scale_y: scale_ids(panels, free_y),
            axis_bottom:
              Enum.map(places, fn {row, column} ->
                free_x or {row + 1, column} not in occupied
              end),
            axis_left:
              Enum.map(places, fn {row, column} -> free_y or {row, column - 1} not in occupied end),
            strip: Enum.map(combinations, fn values -> Enum.map(values, &label/1) end)
          ]
      )
    end

    @impl Giggly.Facet
    def assign_panels(%{facets: facets}, frame, layout) do
      panel_by_values =
        [:panel | facets]
        |> Enum.map(fn name -> DataFrame.pull(layout, name) end)
        |> Enum.zip_with(fn [panel | values] -> {values, panel} end)
        |> Map.new()

      missing = facets -- held(frame, facets)
      fills = fills(layout, missing)
      rows = Enum.to_list(0..(DataFrame.row_count(frame) - 1)//1)
      repeated = DataFrame.slice(frame, Enum.flat_map(fills, fn _fill -> rows end))
      fill_by_row = Enum.flat_map(fills, fn fill -> Enum.map(rows, fn _row -> fill end) end)

      panels =
        facets
        |> Enum.map(fn name -> facet_values(name, missing, repeated, fill_by_row) end)
        |> Enum.zip_with(fn values -> Map.fetch!(panel_by_values, values) end)

      DataFrame.put(repeated, :panel, panels)
    end

    # The combinations of the facet columns' values the tables make, as ggplot2's `combine_vars()`
    # makes them: every table holding all the columns gives its own, then each table holding only
    # some crosses its own with those made so far. Each is a list in the columns' order, sorted by
    # the first column's values, then the next's.
    defp combinations(frames, facets, order_key) do
      {complete, partial} =
        Enum.split_with(frames, fn frame -> held(frame, facets) == facets end)

      check_complete(complete, frames, facets)

      made =
        complete
        |> Enum.flat_map(fn frame -> rows_of(frame, facets) end)
        |> Enum.uniq()

      combinations =
        partial
        |> Enum.reduce(made, fn frame, so_far -> crossed(frame, so_far, facets) end)
        |> Enum.map(fn values -> Enum.map(facets, fn name -> Map.fetch!(values, name) end) end)
        |> Enum.sort_by(fn values -> Enum.map(values, order_key) end)

      case combinations do
        [] -> raise ArgumentError, no_panels_message(facets)
        combinations -> combinations
      end
    end

    # The combinations made so far, with each combination of the columns `frame` holds crossed with
    # each of the others' values made so far. A table holding none of them, or no rows, adds none.
    defp crossed(frame, made, facets) do
      held = held(frame, facets)
      others = facets -- held

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
    defp held(frame, facets) do
      names = DataFrame.names(frame)
      Enum.filter(facets, fn name -> name in names end)
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

    defp check_complete([], frames, facets) do
      lacking =
        frames
        |> Enum.with_index()
        |> Enum.map_join("; ", fn {frame, index} ->
          "#{table_name(index)} lacks #{inspect_all(facets -- held(frame, facets))}"
        end)

      raise ArgumentError,
            "facet_wrap by #{inspect_all(facets)} needs a table holding every column it facets " <>
              "by, but none holds them all: " <> lacking
    end

    defp check_complete(_complete, _frames, _facets), do: :ok

    # The first table is the plot's data, and each after it a layer's, in the order added.
    defp table_name(0), do: "the plot's data"
    defp table_name(index), do: "the layer at index #{index - 1}'s table"

    # Each panel's scale on an axis: its own, numbered as the panel is, on a free axis.
    defp scale_ids(panels, true), do: panels
    defp scale_ids(panels, false), do: Enum.map(panels, fn _panel -> @only_scale end)

    defp facet_columns(facets, combinations) do
      Enum.with_index(facets, fn name, index ->
        {name, Enum.map(combinations, fn values -> Enum.at(values, index) end)}
      end)
    end

    # The rows and columns the panels are laid out in.
    defp dimensions(%{nrow: :none, ncol: :none}, count), do: wrapped(count)

    defp dimensions(%{nrow: :none, ncol: columns}, count),
      do: {ceiling_divide(count, columns), columns}

    defp dimensions(%{nrow: rows, ncol: :none}, count), do: {rows, ceiling_divide(count, rows)}

    # Only both given can be too few for the panels.
    defp dimensions(%{nrow: rows, ncol: columns}, count) when rows * columns >= count,
      do: {rows, columns}

    defp dimensions(%{facets: facets, nrow: rows, ncol: columns}, count) do
      raise ArgumentError,
            "facet_wrap by #{inspect_all(facets)} needs #{count} panels, but together nrow " <>
              "#{rows} and ncol #{columns} provide only #{rows * columns}"
    end

    # R's `n2mfrow()`, whose rows ggplot2 takes as columns and whose columns as rows.
    defp wrapped(count) when count <= 3, do: {1, count}
    defp wrapped(count) when count <= 6, do: {2, div(count + 1, 2)}
    defp wrapped(count) when count <= 12, do: {3, div(count + 2, 3)}

    defp wrapped(count) do
      columns = ceil(:math.sqrt(count))
      {ceiling_divide(count, columns), columns}
    end

    # The panel's row and column, counting from 1, filling each row left to right.
    defp place(panel, columns), do: {div(panel - 1, columns) + 1, rem(panel - 1, columns) + 1}

    defp ceiling_divide(numerator, denominator), do: div(numerator + denominator - 1, denominator)

    # A value as its strip writes it, ggplot2's `label_value()`.
    defp label(nil), do: "NA"
    defp label(value), do: to_string(value)

    defp no_panels_message(facets) do
      "facet_wrap by #{inspect_all(facets)} has no panels to make: the tables holding its " <>
        "columns have no rows"
    end

    defp inspect_all(terms), do: Enum.map_join(terms, ", ", &inspect/1)
  end
end
