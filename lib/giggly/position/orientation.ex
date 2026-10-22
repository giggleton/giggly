defmodule Giggly.Position.Orientation do
  @moduledoc false

  # A layer's orientation as its positions read it: whether its marks are horizontal, as its stat or
  # geom wrote in the `flipped_aes` column, and its table with x and y swapped, so a position moves
  # horizontal bars along y with the code that moves vertical ones along x, swapping back once done,
  # as ggplot2's positions read `has_flipped_aes()` and swap with `flip_data()`. Not a kind: the
  # positions that dodge and stack call it.

  alias Giggly.{Aesthetics, DataFrame}

  # Whether `frame`'s marks are horizontal: the first boolean in its `flipped_aes` column, and false
  # without one, so marks are vertical unless the stat or the geom wrote otherwise.
  @doc false
  @spec flipped?(DataFrame.t()) :: boolean()
  def flipped?(frame) do
    if :flipped_aes in DataFrame.names(frame) do
      frame
      |> DataFrame.pull(:flipped_aes)
      |> Enum.find(false, fn flipped -> is_boolean(flipped) end)
    else
      false
    end
  end

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
