defmodule Giggly.Position.Collide do
  @moduledoc false

  # What the positions that pile and dodge marks give a mark before they move it, as ggplot2's
  # `collide_setup()`, `collide()` and its positions' `setup_data()` give it: an x where it has
  # only sides, sides where it has only an x, and a top where it has only a y. Each column it
  # writes the mark keeps, as in R's `layer_data()`. Not a kind: stacking and both dodges call it.

  alias Giggly.DataFrame
  alias Giggly.DataFrame.Arithmetic

  # `frame` with each mark's x the middle of its sides where it has no x, a rectangle, as ggplot2's
  # `PositionDodge$setup_data()` gives one, and as it is otherwise. Every mark a layer stacks or
  # dodges has an x or both sides.
  @doc false
  @spec with_middle(DataFrame.t()) :: DataFrame.t()
  def with_middle(frame) do
    if :x in DataFrame.names(frame),
      do: frame,
      else: DataFrame.put(frame, :x, middles(frame))
  end

  defp middles(frame) do
    [:xmin, :xmax]
    |> Enum.map(fn side -> DataFrame.pull(frame, side) end)
    |> Enum.zip_with(fn [xmin, xmax] ->
      xmin
      |> Arithmetic.add(xmax)
      |> Arithmetic.divide(2)
    end)
  end

  # `frame` with each mark's sides its x less and plus half `width` where it has none, a line range
  # or a point, or its x on both where `width` is `:none`, as ggplot2's `collide_setup()` gives
  # them, and as it is otherwise. A mark has both sides or neither.
  @doc false
  @spec with_sides(DataFrame.t(), :none | float()) :: DataFrame.t()
  def with_sides(frame, width) do
    if :xmin in DataFrame.names(frame) do
      frame
    else
      x_positions = DataFrame.pull(frame, :x)
      half = if width == :none, do: 0.0, else: width / 2

      frame
      |> DataFrame.put(:xmin, Enum.map(x_positions, fn x -> Arithmetic.subtract(x, half) end))
      |> DataFrame.put(:xmax, Enum.map(x_positions, fn x -> Arithmetic.add(x, half) end))
    end
  end

  # `frame` with each mark's `ymax` its y where it has none, a point, as ggplot2's `collide()`
  # gives one before dodging and `PositionStack$setup_data()` before stacking, and as it is
  # otherwise.
  @doc false
  @spec with_top(DataFrame.t()) :: DataFrame.t()
  def with_top(frame) do
    if :ymax in DataFrame.names(frame),
      do: frame,
      else: DataFrame.put(frame, :ymax, DataFrame.pull(frame, :y))
  end
end
