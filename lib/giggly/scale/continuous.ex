defmodule Giggly.Scale.Continuous do
  @moduledoc """
  A trained continuous scale, as `Giggly.panel_scales/2` returns an axis's: the range of the
  finite numbers it has seen, or `:none` before it has seen any; the name of the transformation
  its values are put through before it sees them, `:identity` for numbers and `:date` for dates,
  which it sees as their days since 1970-01-01, as R stores a date, so a date axis's range is in
  days; and its palette, which turns a value's place in
  that range into the value of its aesthetic: `:identity` for a position, left where it is for
  the coordinate system to place, and `{:rescale, {low, high}}` for an aesthetic such as alpha,
  each value's place, from 0 to 1, rescaled onto `low` to `high`, as R's `pal_rescale()` does, and
  `{:gradient, {low, high}}` for colour and fill, each value's place the colour as far from `low`
  toward `high`, blended in L*a*b*, as R's `pal_seq_gradient()` blends them; the value a missing
  value, or one not a finite number, maps to, its `na_value`, ggplot2's `na.value`: `nil`, R's
  `NA`, for a position and alpha, and grey50, `"#7F7F7F"`, for colour and fill; and the guide that
  draws it, by name, as ggplot2's scale carries `guide`: `:axis` for a position, `:legend` for
  alpha and `:colorbar` for colour and fill.
  """

  # Use it through `Giggly.Scale`; the transformation is resolved by `Giggly.Scale.Transform`.

  alias Giggly.Scale.{Palette, Transform}

  @enforce_keys [:range, :transform, :palette, :na_value, :guide]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          range: :none | {number(), number()},
          transform: atom(),
          palette:
            :identity | {:rescale, {number(), number()}} | {:gradient, {String.t(), String.t()}},
          na_value: nil | String.t(),
          guide: :axis | :legend | :colorbar
        }

  # The values put through the scale's transformation, as `Giggly.Scale.transform/2` describes.
  @doc false
  @spec transform(t(), list()) :: list()
  def transform(%__MODULE__{transform: name}, values), do: Transform.transform(name, values)

  # The scale widened to cover the finite numbers in `values`, as `Giggly.Scale.train/2` describes.
  @doc false
  @spec train(t(), list()) :: t()
  def train(%__MODULE__{range: range} = scale, values) do
    %{scale | range: train_range(range, values)}
  end

  # A range, `:none` for none, widened to cover the finite numbers among `values`: R's
  # `scales::train_continuous()`, which a discrete scale's continuous range trains by too.
  @doc false
  @spec train_range(:none | {number(), number()}, list()) :: :none | {number(), number()}
  def train_range(range, values), do: Enum.reduce(values, range, &widen/2)

  # Each value as `Giggly.Scale.map/2` describes: a position unchanged, until limits can censor
  # it; for any other palette, the value's place in the range, as R's `rescale()` finds it, put
  # through the palette, and the scale's `na_value` for a missing value or one that is not a finite
  # number, as ggplot2 maps such a value to its `na.value`.
  @doc false
  @spec map(t(), list()) :: list()
  def map(%__MODULE__{palette: :identity}, values), do: values

  def map(%__MODULE__{} = scale, values),
    do: Enum.map(values, fn value -> through_palette(value, scale) end)

  defp through_palette(value, %__MODULE__{range: {_low, _high} = range, palette: palette})
       when is_number(value) do
    place = Giggly.Scale.rescale(value, range, {0, 1})
    Palette.continuous(palette, place)
  end

  defp through_palette(_missing, %__MODULE__{na_value: na_value}), do: na_value

  # `nil` and Explorer's non-finite float atoms are not numbers, so only a number widens the range.
  defp widen(value, :none) when is_number(value), do: {value, value}

  defp widen(value, {low, high}) when is_number(value),
    do: {min(low, value), max(high, value)}

  defp widen(_not_a_finite_number, range), do: range
end
