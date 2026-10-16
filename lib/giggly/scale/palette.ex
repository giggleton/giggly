defmodule Giggly.Scale.Palette do
  @moduledoc false

  # Palettes: the last step of a scale, which turns where a value sits among the data into the
  # value of its aesthetic, as R's `scales` palettes do. A palette is a value naming the function,
  # never a closure, so a scale stays a value that compares and prints.
  #
  #   * `:identity`, a position's: the value is left where the scale puts it, as ggplot2's position
  #     scales' palette is the identity, and the coordinate system places it.
  #   * `{:rescale, {low, high}}`, a continuous scale's: a value's place in the trained range, from
  #     0 to 1, rescaled onto `low` to `high`, as R's `pal_rescale()` does with `rescale()`.
  #   * `{:sequence, {low, high}}`, a discrete scale's: given the number of levels, that many
  #     values from `low` to `high`, evenly spaced, as ggplot2's ordinal alpha scale takes R's
  #     `seq(low, high, length.out = n)`.
  #
  # Use it through `Giggly.Scale`.

  @typedoc "A scale's palette."
  @type t :: :identity | {:rescale, {number(), number()}} | {:sequence, {number(), number()}}

  # A continuous palette's value for a place from 0 to 1 in the trained range: R's
  # `rescale(x, to = range, from = c(0, 1))`, as `pal_rescale()` computes it.
  @doc false
  @spec continuous({:rescale, {number(), number()}}, number()) :: float()
  def continuous({:rescale, to}, place), do: Giggly.Scale.rescale(place, {0, 1}, to)

  # A discrete palette's values for `count` levels, in level order: R's
  # `seq(low, high, length.out = count)`, none for no levels, the first `low` and the last `high`
  # exactly, and each one between `low` plus its index times the step, in that order of operations,
  # as R's `seq.default()` computes it, so the fourth of seven is 0.54999999999999993, not 0.55.
  @doc false
  @spec discrete({:sequence, {number(), number()}}, non_neg_integer()) :: [number()]
  def discrete({:sequence, {_low, _high}}, 0), do: []
  def discrete({:sequence, {low, _high}}, 1), do: [low]
  def discrete({:sequence, {low, high}}, 2), do: [low, high]

  def discrete({:sequence, {low, high}}, count) when count > 2 do
    step = (high - low) / (count - 1)
    between = Enum.map(1..(count - 2), fn index -> low + index * step end)
    Enum.concat([[low], between, [high]])
  end
end
