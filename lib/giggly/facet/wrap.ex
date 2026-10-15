defmodule Giggly.Facet.Wrap do
  @moduledoc false

  # Wrapped panels, ggplot2's `facet_wrap()`: a panel for each combination of the values of the
  # facet's columns that occurs in the data, laid out in rows. Its struct holds its parameters: the
  # columns it splits on, by the names the data gives them, and the number of rows and of columns
  # to lay the panels out in, each `:none` when not given. Run it through `Giggly.Facet`.
  #
  # The panels are ordered by the first column's values, then the next's, each as a discrete scale
  # orders its levels, by the key the assembly hands over, so a missing value (`nil`) gets a panel
  # of its own, last. They fill the layout a row at a time, left to right. With neither a number
  # of rows nor of columns, the layout is ggplot2's (R's `n2mfrow()`, rows and columns swapped):
  # one row for up to three panels, two for up to six, three for up to twelve, and beyond that as
  # many columns as the square root of the count, rounded up, and as many rows as those columns
  # need. Given one, the other is as many as the panels need; given both, they must hold every
  # panel. Every panel uses scale 1 of each axis: its scales are fixed.
  #
  # The layout carries each facet column, by its name in the data, as ggplot2's does, and each
  # row's panel is found from its values there.

  @enforce_keys [:facets, :nrow, :ncol]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          facets: [String.t()],
          nrow: pos_integer() | :none,
          ncol: pos_integer() | :none
        }

  defimpl Giggly.Facet, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Facet

    alias Giggly.DataFrame

    # Fixed scales: every panel uses scale 1 of each axis.
    @only_scale 1

    @impl Giggly.Facet
    def layout(%{facets: facets} = wrap, frame, order_key) do
      combinations = combinations(frame, facets, order_key)
      count = length(combinations)
      {_rows, columns} = dimensions(wrap, count)
      places = Enum.map(1..count//1, fn panel -> place(panel, columns) end)

      DataFrame.new(
        [
          panel: Enum.to_list(1..count//1),
          row: Enum.map(places, fn {row, _column} -> row end),
          column: Enum.map(places, fn {_row, column} -> column end)
        ] ++
          facet_columns(facets, combinations) ++
          [
            scale_x: List.duplicate(@only_scale, count),
            scale_y: List.duplicate(@only_scale, count)
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

      panels =
        facets
        |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
        |> Enum.zip_with(fn values -> Map.fetch!(panel_by_values, values) end)

      DataFrame.put(frame, :panel, panels)
    end

    # The combinations of the facet columns' values that occur, each a list in the columns' order,
    # sorted by the first column's values, then the next's.
    defp combinations(frame, facets, order_key) do
      combinations =
        facets
        |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
        |> Enum.zip_with(fn values -> values end)
        |> Enum.uniq()
        |> Enum.sort_by(fn values -> Enum.map(values, order_key) end)

      case combinations do
        [] -> raise ArgumentError, no_panels_message(facets)
        combinations -> combinations
      end
    end

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

    defp no_panels_message(facets) do
      "facet_wrap by #{inspect_all(facets)} has no panels to make: the data has no rows"
    end

    defp inspect_all(terms), do: Enum.map_join(terms, ", ", &inspect/1)
  end
end
