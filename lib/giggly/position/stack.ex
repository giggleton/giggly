defmodule Giggly.Position.Stack do
  @moduledoc false

  # Stacking, ggplot2's `position_stack()`: the bars at one x piled on one another, as `geom_col()`
  # and `geom_bar()` default `position = "stack"`, and the areas, as `geom_area()` does, and
  # filling, ggplot2's `position_fill()`, which is stacking with each pile scaled to reach 1. Its
  # fields are ggplot2's: `vjust`, where in its stretch each mark's y moves, 0 its bottom and 1 its
  # top, `reverse`, whether the lowest group is at the bottom of the pile, and `fill`, whether each
  # pile is scaled. Run it through `Giggly.Position`.
  #
  # Nothing moves unless two rows of the layer share an x, in any panel, or the marks are filled or
  # their y moves off the top of its stretch, as ggplot2 skips stacking when every x differs and
  # neither is asked. Otherwise a layer whose rows have no `ymax`, as a point's have none, is
  # stacked by its y, its `ymax` and `ymin` written as ggplot2's `setup_data()` and `pos_stack()`
  # write them, and a layer whose rows have no `xmin`, as an area's have none, has
  # each row's `xmin` and `xmax` set to its x, as ggplot2's `collide()` sets them, and each panel's
  # bars, or an area's bands from 0 to its y, are stacked by their `xmin`, those reaching
  # below zero separately from the rest, each pile in the order of its x and then of its group,
  # highest group first, so the pile matches the legend's order, or lowest first when reversed, as
  # ggplot2's `collide()` orders them. Each bar takes the next stretch of its pile, `ymin` to
  # `ymax`, as long as its y, and its y moves to `(1 - vjust) * ymin + vjust * ymax`. A bar
  # reaching below zero piles downward from zero: its `ymax`, which is 0, is first taken as its
  # `ymin`, as ggplot2 stacks by `ymax`.
  #
  # Filled, each pile's heights are divided by the magnitude of its total, as ggplot2's
  # `pos_stack()` divides them, so a pile above zero reaches 1 and one below reaches -1; a pile
  # whose total is no more than R's `sqrt(.Machine$double.eps)` is left as it is. A pile whose
  # total is NaN, one holding both infinities, is divided by it, so its marks are missing and not
  # drawn, where ggplot2 fails.
  #
  # A row missing its x, its edges or its y loses its x, its edges and its y, as ggplot2's
  # `detect_missing()` blanks them; it stacks as nothing, its y 0, and its `ymin` and `ymax` are
  # missing, so it is not drawn.
  #
  # Horizontal marks, those whose `flipped_aes` column says so, or else whose one discrete axis is
  # y, are stacked along x, x and y swapped and swapped back (`Giggly.Position.Orientation`).

  defstruct vjust: 1.0, reverse: false, fill: false

  @type t :: %__MODULE__{vjust: float(), reverse: boolean(), fill: boolean()}

  defimpl Giggly.Position, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Position

    alias Giggly.DataFrame
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Position.{Collide, Orientation}

    # R's `sqrt(.Machine$double.eps)`, the square root of 2^-52: a filled pile whose total is no
    # more than this is left as it is.
    @smallest_total 1.4901161193847656e-8

    @columns [:panel, :group, :x, :xmin, :xmax, :y, :ymin, :ymax]
    @placed [:x, :xmin, :xmax, :y, :ymin, :ymax]

    # Stacking reads no aesthetics of its own.
    @impl Giggly.Position
    def default_aesthetics(_position), do: %{}

    @impl Giggly.Position
    def compute_layer(position, frame, axis_kinds) do
      flipped = Orientation.flipped?(frame, axis_kinds, false)

      frame
      |> Orientation.flip(flipped)
      |> moved(position)
      |> Orientation.flip(flipped)
    end

    # ggplot2 skips stacking only when every x differs and the marks are neither filled nor moved
    # off the top of their stretch.
    defp moved(frame, %{fill: false, vjust: vjust} = position) when vjust == 1 do
      x_positions = DataFrame.pull(frame, :x)

      if length(Enum.uniq(x_positions)) == length(x_positions),
        do: frame,
        else: stacked(frame, position)
    end

    defp moved(frame, position), do: stacked(frame, position)

    defp stacked(frame, position) do
      frame =
        frame
        |> Collide.with_top()
        |> Collide.with_sides(:none)
        |> with_bottom()

      stacked_rows =
        @columns
        |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
        |> Enum.zip_with(fn values -> row(values) end)
        |> Enum.with_index(fn row, index -> set_up(row, index) end)
        |> Enum.group_by(fn row -> {row.panel, below_zero?(row)} end)
        |> Enum.flat_map(fn {_pile, rows} -> collide(rows, position) end)
        |> Enum.sort_by(fn row -> row.index end)

      Enum.reduce(@placed, frame, fn name, placed ->
        DataFrame.put(placed, name, Enum.map(stacked_rows, fn row -> Map.fetch!(row, name) end))
      end)
    end

    # The frame with each mark's `ymin` its y where it has none, which its stretch of the pile
    # replaces, as ggplot2's `pos_stack()` writes a `ymin` for every mark.
    defp with_bottom(frame) do
      if :ymin in DataFrame.names(frame),
        do: frame,
        else: DataFrame.put(frame, :ymin, DataFrame.pull(frame, :y))
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
    # highest first, or lowest first when reversed, each run of one `xmin` stacked on its own.
    defp collide(rows, position) do
      rows
      |> Enum.sort_by(fn row -> {xmin_key(row.xmin), group_key(row.group, position)} end)
      |> Enum.chunk_by(fn row -> row.xmin end)
      |> Enum.flat_map(fn pile -> pile(pile, position) end)
    end

    defp group_key(group, %{reverse: true}), do: group
    defp group_key(group, %{reverse: false}), do: -group

    defp xmin_key(xmin) when is_number(xmin), do: {0, xmin}
    defp xmin_key(_missing), do: {1, nil}

    # ggplot2's `pos_stack()`: the pile's heights, from 0 through each bar's y added in order, a
    # missing y adding nothing, in R's arithmetic (`Giggly.DataFrame.Arithmetic`), so an infinite
    # bar takes the pile to its infinity, and a bar above it stretches from infinity to infinity,
    # its y NaN, as `0 * Inf` is. Filled, each height is divided by the magnitude of the last.
    # Each bar takes the stretch between its two heights and its y moves `vjust` of the way up it.
    # A bar whose `ymax` was below its `ymin` keeps them that way round, and one missing either has
    # neither.
    defp pile(rows, position) do
      {stretches, total} =
        Enum.map_reduce(rows, 0.0, fn row, height ->
          top = Arithmetic.add(height, y_value(row.y))
          {{row, height, top}, top}
        end)

      scale = scaled(total, position)

      Enum.map(stretches, fn {row, bottom, top} ->
        bottom = scale.(bottom)
        top = scale.(top)
        low = Arithmetic.lesser(bottom, top)
        high = Arithmetic.greater(bottom, top)

        y =
          Arithmetic.add(
            Arithmetic.multiply(1 - position.vjust, low),
            Arithmetic.multiply(position.vjust, high)
          )

        edges(row, y, low, high)
      end)
    end

    # How a pile's heights are scaled: divided by the magnitude of `total` when filled and it is
    # more than the smallest total, or NaN, which compares with nothing, and as they are otherwise.
    defp scaled(total, %{fill: true}) do
      magnitude = Arithmetic.magnitude(total)

      if Arithmetic.less?(@smallest_total, magnitude) == false,
        do: fn height -> height end,
        else: fn height -> Arithmetic.divide(height, magnitude) end
    end

    defp scaled(_total, %{fill: false}), do: fn height -> height end

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
