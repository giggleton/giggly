defmodule Giggly.Facet.Grid do
  @moduledoc false

  # A grid of panels, ggplot2's `facet_grid()`: a row of panels for each combination of the values
  # of some columns and a column of panels for each combination of others'. Its struct holds its
  # parameters: the columns its rows split on and those its columns split on, each by the names the
  # data gives them, either list empty for a single row or column of panels; and which axes'
  # scales are free, ggplot2's `scales`: `:fixed`, `:free_x`, `:free_y` or `:free`. Run it through
  # `Giggly.Facet`.
  #
  # The rows' combinations and the columns' are each those the plot's data and every layer's table
  # make together, each ordered by its first column's values, then the next's, a missing value
  # (`nil`) last, as `Giggly.Facet.Combinations` makes them, each refused alone unless some table
  # holds all its columns, as ggplot2's `combine_vars()` checks the rows and the columns apart.
  # Every row's combination is then crossed with every column's, so a pair no table holds is a
  # panel too, drawn empty, as ggplot2's `df.grid()` crosses them; the panels are numbered a row at
  # a time, left to right. Each table's rows are given their panels as `Giggly.Facet.Combinations`
  # gives them, a table lacking some of the columns repeated in each panel of the values it has, so
  # one holding the rows' columns alone is drawn in every panel of its row.
  #
  # On a fixed axis every panel uses that axis's scale 1; on a free one the panels of a column of
  # the grid share an x scale and those of a row a y scale, numbered as the column or the row is,
  # as ggplot2's layout numbers them. A panel draws an axis only at the grid's margins, free scales
  # or not, ggplot2's default: below the last row and left of the first column, so each column's
  # bottom axis is its own x scale's. The panels of the first row have a strip above them for each
  # of the columns' columns, in their order, labelled with its value as ggplot2's `label_value()`
  # writes it.

  @enforce_keys [:rows, :cols, :scales]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          rows: [String.t()],
          cols: [String.t()],
          scales: :fixed | :free_x | :free_y | :free
        }

  defimpl Giggly.Facet, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Facet

    alias Giggly.DataFrame
    alias Giggly.Facet.Combinations

    # A fixed axis's one scale.
    @only_scale 1

    @impl Giggly.Facet
    def layout(%{rows: rows, cols: cols, scales: scales}, frames, order_key) do
      row_values = values(frames, rows, order_key, "rows")
      column_values = values(frames, cols, order_key, "cols")
      last_row = length(row_values)

      cells =
        for {row_value, row} <- Enum.with_index(row_values, 1),
            {column_value, column} <- Enum.with_index(column_values, 1),
            do: %{row: row, column: column, values: row_value ++ column_value, top: column_value}

      free_x = scales in [:free_x, :free]
      free_y = scales in [:free_y, :free]

      DataFrame.new(
        [
          panel: Enum.to_list(1..length(cells)//1),
          row: Enum.map(cells, fn cell -> cell.row end),
          column: Enum.map(cells, fn cell -> cell.column end)
        ] ++
          facet_columns(rows ++ cols, cells) ++
          [
            scale_x: Enum.map(cells, fn cell -> scale_id(cell.column, free_x) end),
            scale_y: Enum.map(cells, fn cell -> scale_id(cell.row, free_y) end),
            axis_bottom: Enum.map(cells, fn cell -> cell.row == last_row end),
            axis_left: Enum.map(cells, fn cell -> cell.column == 1 end),
            strip: Enum.map(cells, &top_strip/1)
          ]
      )
    end

    @impl Giggly.Facet
    def assign_panels(%{rows: rows, cols: cols}, frame, layout),
      do: Combinations.assign_panels(frame, layout, rows ++ cols)

    # The combinations of a side's columns, the rows' or the columns': one with no values when the
    # side splits on none, so the grid is a single row or column of panels.
    defp values(_frames, [], _order_key, _side), do: [[]]

    defp values(frames, columns, order_key, side),
      do:
        Combinations.combine(
          frames,
          columns,
          order_key,
          "facet_grid by #{side} #{inspect_all(columns)}"
        )

    defp facet_columns(columns, cells) do
      Enum.with_index(columns, fn name, index ->
        {name, Enum.map(cells, fn cell -> Enum.at(cell.values, index) end)}
      end)
    end

    # A panel's scale on an axis: its column's or its row's, numbered as that is, on a free axis.
    defp scale_id(place, true), do: place
    defp scale_id(_place, false), do: @only_scale

    # The first row's strips label the columns' values; the panels below have none.
    defp top_strip(%{row: 1, top: values}), do: Enum.map(values, &Combinations.label/1)
    defp top_strip(_cell), do: []

    defp inspect_all(terms), do: Enum.map_join(terms, ", ", &inspect/1)
  end
end
