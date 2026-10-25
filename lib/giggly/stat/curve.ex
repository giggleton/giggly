defmodule Giggly.Stat.Curve do
  @moduledoc false

  # The places a stat works a curve out at, and a curve read between the places it holds, as R
  # spaces and interpolates them: smoothing's curve at evenly spaced places, aligning's groups at
  # each other's places, and a density's curve at its places from the grid it is convolved on
  # (design-log §4, the entry beginning "Smoothing and densities compute over the rows"). Each
  # works on a stat's own small output as lists, never on a layer's rows.

  # `count` evenly spaced values from `low` to `high`, R's `seq(low, high, length.out = count)`
  # and `seq.int()`, which space them alike: its ends exactly, and between them `low` plus each
  # step of the span over one less than the count, so ends that meet repeat `low`.
  @doc false
  @spec places(number(), number(), pos_integer()) :: [number()]
  def places(low, _high, 1), do: [low]
  def places(low, high, 2), do: [low, high]

  def places(low, high, count) when is_integer(count) and count > 2 do
    step = (high - low) / (count - 1)
    inner = Enum.map(1..(count - 2), fn index -> low + index * step end)
    Enum.concat([[low], inner, [high]])
  end

  # The curve through `knots`, `{x, y}` pairs ascending in x, no two at one x, read at each of
  # `places`, ascending too, as R's `approx()` reads it: exactly a knot's y at its x, and between
  # two knots their y joined by a straight line, `low_y + (high_y - low_y) * ((place - low_x) /
  # (high_x - low_x))` in R's order; `nil` outside them, where no two knots stand either side. One
  # walk along both, since each place's knots are at or past the last place's.
  @doc false
  @spec interpolate([{number(), number()}], [number()]) :: [number() | nil]
  def interpolate(knots, places) do
    spans = Enum.chunk_every(knots, 2, 1, :discard)

    {values, _spans} =
      Enum.map_reduce(places, spans, fn place, spans ->
        ahead = Enum.drop_while(spans, fn [_low, {high_x, _high_y}] -> place > high_x end)
        {read(ahead, place), ahead}
      end)

    values
  end

  defp read([[{low_x, low_y}, _high] | _rest], place) when place == low_x, do: low_y
  defp read([[_low, {high_x, high_y}] | _rest], place) when place == high_x, do: high_y

  defp read([[{low_x, low_y}, {high_x, high_y}] | _rest], place) when place > low_x,
    do: low_y + (high_y - low_y) * ((place - low_x) / (high_x - low_x))

  defp read(_spans, _place), do: nil
end
