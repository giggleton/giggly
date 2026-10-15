defmodule Giggly.Position.Stack do
  @moduledoc false

  # Stacking, ggplot2's `position_stack()`: the bars at one x piled on one another, as `geom_col()`
  # and `geom_bar()` default `position = "stack"`. It takes no parameters yet; ggplot2's
  # `vjust = 1`, `reverse = FALSE` and `fill = FALSE` are how it stacks. Run it through
  # `Giggly.Position`.
  #
  # Nothing moves unless two rows of the layer share an x, in any panel, as ggplot2 skips stacking
  # when every x differs. Otherwise each panel's bars are stacked by their `xmin`, those reaching
  # below zero separately from the rest, each pile in the order of its x and then of its group,
  # highest group first, so the pile matches the legend's order, as ggplot2's `collide()` orders
  # them. Each bar takes the next stretch of its pile, `ymin` to `ymax`, as long as its y, and its
  # y moves to the stretch's top. A bar reaching below zero piles downward from zero: its `ymax`,
  # which is 0, is first taken as its `ymin`, as ggplot2 stacks by `ymax`.
  #
  # A row missing its x, its edges or its y loses its x, its edges and its y, as ggplot2's
  # `detect_missing()` blanks them; it stacks as nothing, its y 0, and its `ymin` and `ymax` are
  # missing, so it is not drawn.

  defstruct []

  @type t :: %__MODULE__{}

  defimpl Giggly.Position, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Position

    alias Giggly.DataFrame

    # ggplot2's default: each bar's y at the top of its stretch.
    @vjust 1

    @columns [:panel, :group, :x, :xmin, :xmax, :y, :ymin, :ymax]
    @placed [:x, :xmin, :xmax, :y, :ymin, :ymax]

    @impl Giggly.Position
    def compute_layer(_position, frame) do
      x_positions = DataFrame.pull(frame, :x)

      if length(Enum.uniq(x_positions)) == length(x_positions),
        do: frame,
        else: stacked(frame)
    end

    defp stacked(frame) do
      stacked_rows =
        @columns
        |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
        |> Enum.zip_with(fn values -> row(values) end)
        |> Enum.with_index(fn row, index -> set_up(row, index) end)
        |> Enum.group_by(fn row -> {row.panel, below_zero?(row)} end)
        |> Enum.flat_map(fn {_pile, rows} -> collide(rows) end)
        |> Enum.sort_by(fn row -> row.index end)

      Enum.reduce(@placed, frame, fn name, placed ->
        DataFrame.put(placed, name, Enum.map(stacked_rows, fn row -> Map.fetch!(row, name) end))
      end)
    end

    defp row(values) do
      @columns
      |> Enum.zip(values)
      |> Map.new()
    end

    # ggplot2's `setup_data()`: a bar is stacked by its `ymax`, a zero `ymax` standing for its
    # `ymin`, and a row missing any of its x, edges or y loses them all. Each row keeps its index,
    # so the rows go back in their order once stacked.
    defp set_up(row, index) do
      ymax = stacked_end(row.ymax, row.ymin)
      row = Map.merge(row, %{ymax: ymax, index: index})

      if Enum.any?([row.x, row.xmin, row.xmax, row.y], &missing?/1),
        do: %{row | x: nil, xmin: nil, xmax: nil, y: nil},
        else: row
    end

    defp stacked_end(ymax, ymin) when ymax == 0, do: ymin
    defp stacked_end(ymax, _ymin), do: ymax

    defp below_zero?(%{ymax: ymax}) when is_number(ymax), do: ymax < 0
    defp below_zero?(_row), do: false

    # ggplot2's `collide()`: the pile's rows by their `xmin`, a missing one last, then by group,
    # highest first, each run of one `xmin` stacked on its own.
    defp collide(rows) do
      rows
      |> Enum.sort_by(fn row -> {xmin_key(row.xmin), -row.group} end)
      |> Enum.chunk_by(fn row -> row.xmin end)
      |> Enum.flat_map(&pile/1)
    end

    defp xmin_key(xmin) when is_number(xmin), do: {0, xmin}
    defp xmin_key(_missing), do: {1, nil}

    # ggplot2's `pos_stack()`: each bar takes the stretch from the pile's height so far to that
    # height plus its y, a missing y adding nothing, in order. A bar whose `ymax` was below its
    # `ymin` keeps them that way round, and one missing either has neither.
    defp pile(rows) do
      {stacked, _height} =
        Enum.map_reduce(rows, 0.0, fn row, height ->
          next = height + y_value(row.y)
          low = min(height, next)
          high = max(height, next)
          y = (1 - @vjust) * low + @vjust * high

          {edges(row, y, low, high), next}
        end)

      stacked
    end

    defp y_value(y) when is_number(y), do: y
    defp y_value(_missing), do: 0.0

    defp edges(%{ymin: ymin, ymax: ymax} = row, y, low, high)
         when is_number(ymin) and is_number(ymax) and ymax < ymin,
         do: %{row | y: y, ymin: high, ymax: low}

    defp edges(%{ymin: ymin, ymax: ymax} = row, y, low, high)
         when is_number(ymin) and is_number(ymax),
         do: %{row | y: y, ymin: low, ymax: high}

    defp edges(row, y, _low, _high), do: %{row | y: y, ymin: nil, ymax: nil}

    defp missing?(value), do: value in [nil, :nan]
  end
end
