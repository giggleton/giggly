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
  #   * `{:hue, %{hue: {low, high}, chroma: chroma, luminance: luminance}}`, a discrete colour
  #     scale's: given the number of levels, that many colours of one chroma and luminance, their
  #     hues spaced evenly round the circle from `low`, as R's `pal_hue()` gives them. ggplot2's
  #     default is `pal_hue()`'s, hues from 15 round to 375, chroma 100 and luminance 65; `high` is
  #     a full circle on from `low`, the one range a plot can give until a scale function can set
  #     another.
  #
  # Use it through `Giggly.Scale`.

  # A palette's colours come from the colour operations.
  alias Giggly.ColorOperations

  @typedoc "A scale's palette."
  @type t ::
          :identity
          | {:rescale, {number(), number()}}
          | {:sequence, {number(), number()}}
          | {:hue, %{hue: {number(), number()}, chroma: number(), luminance: number()}}

  # A continuous palette's value for a place from 0 to 1 in the trained range: R's
  # `rescale(x, to = range, from = c(0, 1))`, as `pal_rescale()` computes it.
  @doc false
  @spec continuous({:rescale, {number(), number()}}, number()) :: float()
  def continuous({:rescale, to}, place), do: Giggly.Scale.rescale(place, {0, 1}, to)

  # A discrete palette's values for `count` levels, in level order.
  #
  # A sequence's are R's `seq(low, high, length.out = count)`, none for no levels, the first `low`
  # and the last `high` exactly, and each one between `low` plus its index times the step, in that
  # order of operations, as R's `seq.default()` computes it, so the fourth of seven is
  # 0.54999999999999993, not 0.55.
  #
  # A hue palette's are `pal_hue()`'s: the circle's last `360 / count` degrees left off, since its
  # end is its start, the hues spread over the rest by the same `seq()`, and each colour made by
  # `ColorOperations.from_hcl/3`, as `pal_hue()` has farver encode it. R takes each hue modulo 360
  # first; a hue is turned through its cosine and sine, which repeat every 360 degrees, so the
  # colours are the same without it, as they are for every count from 1 to 400. A scale whose every
  # value is missing has no levels to ask for, and ggplot2 then maps every value to its NA value
  # without asking its palette, so no levels give none.
  @doc false
  @spec discrete({:sequence, {number(), number()}}, non_neg_integer()) :: [number()]
  @spec discrete({:hue, map()}, non_neg_integer()) :: [String.t()]
  def discrete({:sequence, {_low, _high}}, 0), do: []
  def discrete({:sequence, {low, _high}}, 1), do: [low]
  def discrete({:sequence, {low, high}}, 2), do: [low, high]

  def discrete({:sequence, {low, high}}, count) when count > 2 do
    step = (high - low) / (count - 1)
    between = Enum.map(1..(count - 2), fn index -> low + index * step end)
    Enum.concat([[low], between, [high]])
  end

  def discrete({:hue, _parameters}, 0), do: []

  def discrete(
        {:hue, %{hue: {low, high}, chroma: chroma, luminance: luminance}},
        count
      )
      when high - low == 360 and count > 0 do
    {:sequence, {low, high - 360 / count}}
    |> discrete(count)
    |> Enum.map(fn hue -> ColorOperations.from_hcl(hue, chroma, luminance) end)
  end
end
