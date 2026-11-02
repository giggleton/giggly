defmodule Giggly.Position.Orientation do
  @moduledoc false

  # A layer's orientation as its positions read it: whether its marks are horizontal, and its table
  # with x and y swapped, so a position moves horizontal bars along y with the code that moves
  # vertical ones along x, swapping back once done, as ggplot2's positions read `has_flipped_aes()`
  # and swap with `flip_data()`. Not a kind: the positions that dodge and stack call it.

  alias Giggly.{Aesthetics, DataFrame, Position}

  # Whether `frame`'s marks are horizontal, as ggplot2's `has_flipped_aes()` decides for a
  # position: the first boolean in its `flipped_aes` column, which the stat or the geom wrote;
  # without one, true where y is the one axis of the two the layer has a column for that is
  # discrete, and false where x is; and otherwise `fallback`, dodging's `orientation` being `:y`,
  # false for every other position.
  @doc false
  @spec flipped?(DataFrame.t(), Position.axis_kinds(), boolean()) :: boolean()
  def flipped?(frame, axis_kinds, fallback) do
    names = DataFrame.names(frame)

    case {written(frame, names), discrete?(names, axis_kinds, :x),
          discrete?(names, axis_kinds, :y)} do
      {flipped, _x, _y} when is_boolean(flipped) -> flipped
      {:none, true, false} -> false
      {:none, false, true} -> true
      {:none, _x, _y} -> fallback
    end
  end

  # The first boolean in `frame`'s `flipped_aes` column, and `:none` where it holds none or the
  # layer has no such column.
  defp written(frame, names) do
    if :flipped_aes in names do
      frame
      |> DataFrame.pull(:flipped_aes)
      |> Enum.find(:none, fn flipped -> is_boolean(flipped) end)
    else
      :none
    end
  end

  # Whether the layer has a column for `axis` whose scale is discrete, as R's `is_mapped_discrete()`
  # reads the column.
  defp discrete?(names, axis_kinds, axis),
    do: axis in names and Map.fetch!(axis_kinds, axis) == :discrete

  # `frame` with each column of the x family and its twin in the y family swapped where `flipped`,
  # and as it is otherwise.
  @doc false
  @spec flip(DataFrame.t(), boolean()) :: DataFrame.t()
  def flip(frame, false), do: frame

  def flip(frame, true) do
    renames =
      frame
      |> DataFrame.names()
      |> Aesthetics.flipped()

    DataFrame.select(frame, renames)
  end
end
