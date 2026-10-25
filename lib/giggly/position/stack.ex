defmodule Giggly.Position.Stack do
  @moduledoc false

  # Stacking, ggplot2's `position_stack()`: the bars at one x piled on one another, as `geom_col()`
  # and `geom_bar()` default `position = "stack"`, and the areas, as `geom_area()` does. It takes
  # no parameters yet; ggplot2's `vjust = 1`, `reverse = FALSE` and `fill = FALSE` are how it
  # stacks. Run it through `Giggly.Position`.
  #
  # Nothing moves unless two rows of the layer share an x, in any panel, as ggplot2 skips stacking
  # when every x differs. Otherwise a layer whose rows have no `xmin`, as an area's have none, has
  # each row's `xmin` and `xmax` set to its x, as ggplot2's `collide()` sets them, and each panel's
  # bars, or an area's bands from 0 to its y, are stacked by their `xmin`, those reaching
  # below zero separately from the rest, each pile in the order of its x and then of its group,
  # highest group first, so the pile matches the legend's order, as ggplot2's `collide()` orders
  # them. Each bar takes the next stretch of its pile, `ymin` to `ymax`, as long as its y, and its
  # y moves to the stretch's top. A bar reaching below zero piles downward from zero: its `ymax`,
  # which is 0, is first taken as its `ymin`, as ggplot2 stacks by `ymax`.
  #
  # A row missing its x, its edges or its y loses its x, its edges and its y, as ggplot2's
  # `detect_missing()` blanks them; it stacks as nothing, its y 0, and its `ymin` and `ymax` are
  # missing, so it is not drawn.
  #
  # Horizontal bars, those whose `flipped_aes` column says so, are stacked along x, x and y
  # swapped and swapped back (`Giggly.Position.Orientation`).

  defstruct []

  @type t :: %__MODULE__{}

  defimpl Giggly.Position, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Position

    alias Giggly.DataFrame
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Position.Orientation

    # ggplot2's default: each bar's y at the top of its stretch.
    @vjust 1

    @columns [:panel, :group, :x, :xmin, :xmax, :y, :ymin, :ymax]
    @placed [:x, :xmin, :xmax, :y, :ymin, :ymax]

    # Stacking reads no aesthetics of its own.
    @impl Giggly.Position
    def default_aesthetics(_position), do: %{}

    @impl Giggly.Position
    def compute_layer(_position, frame) do
      flipped = Orientation.flipped?(frame)

      frame
      |> Orientation.flip(flipped)
      |> moved()
      |> Orientation.flip(flipped)
    end

    defp moved(frame) do
      x_positions = DataFrame.pull(frame, :x)

      if length(Enum.uniq(x_positions)) == length(x_positions),
        do: frame,
        else: stacked(frame)
    end

    defp stacked(frame) do
      frame = with_edges(frame)

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

    # The frame with each mark's `xmin` and `xmax` its x where it has none, as an area's rows have
    # none, as ggplot2's `collide()` adds them before it piles the marks by their `xmin`.
    defp with_edges(frame) do
      if :xmin in DataFrame.names(frame) do
        frame
      else
        x_positions = DataFrame.pull(frame, :x)

        frame
        |> DataFrame.put(:xmin, x_positions)
        |> DataFrame.put(:xmax, x_positions)
      end
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

    defp below_zero?(%{ymax: ymax}), do: Arithmetic.less?(ymax, 0) == true

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
    # height plus its y, a missing y adding nothing, in order, in R's arithmetic
    # (`Giggly.DataFrame.Arithmetic`), so an infinite bar takes the pile to its infinity, and a
    # bar above it stretches from infinity to infinity, its y NaN, as `0 * Inf` is. A bar whose
    # `ymax` was below its `ymin` keeps them that way round, and one missing either has neither.
    defp pile(rows) do
      {stacked, _height} =
        Enum.map_reduce(rows, 0.0, fn row, height ->
          next = Arithmetic.add(height, y_value(row.y))
          low = Arithmetic.lesser(height, next)
          high = Arithmetic.greater(height, next)

          y =
            Arithmetic.add(
              Arithmetic.multiply(1 - @vjust, low),
              Arithmetic.multiply(@vjust, high)
            )

          {edges(row, y, low, high), next}
        end)

      stacked
    end

    defp y_value(missing) when missing in [nil, :nan], do: 0.0
    defp y_value(y), do: y

    defp edges(%{ymin: ymin, ymax: ymax} = row, y, low, high) do
      case Arithmetic.less?(ymax, ymin) do
        true -> %{row | y: y, ymin: high, ymax: low}
        false -> %{row | y: y, ymin: low, ymax: high}
        nil -> %{row | y: y, ymin: nil, ymax: nil}
      end
    end

    defp missing?(value), do: value in [nil, :nan]
  end
end
