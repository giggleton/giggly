defmodule Giggly.Scale.Discrete do
  @moduledoc """
  A discrete scale. `Giggly.Plot.scale_x_discrete/2` records one with the options it is given and
  no levels, and `Giggly.panel_scales/2` returns an axis's trained. Its fields:

    * `levels`: the distinct values it has seen, in level order.
    * `continuous_range`: the range of the positions it has been handed since its levels were
      placed, such as a bar's edges, which can widen the axis past its levels; `:none` before any.
    * `palette`: what turns a value into its aesthetic's value: `:identity` for a position, each
      value at its place counting from 1; `{:sequence, {low, high}}` for an aesthetic such as
      alpha, the values spread evenly from `low` to `high` in order; and, for colour and fill,
      `{:hue, %{hue: {low, high}, chroma: chroma, luminance: luminance, direction: direction}}`,
      a colour for each value, their hues spaced evenly from `low` to `high` round the circle,
      handed out in reverse for a `direction` of -1; `{:gray, {start, finish}}`, greys from the
      level `start` to `finish`, 0 black and 1 white; or `{:manual, colors}`, the colours of a
      list in order, or those of a map from value to colour by value; and for size,
      `{:area_sequence, {low, high}}`, sizes from `low` to `high` whose squares, and so areas, are
      spread evenly.
    * `na_value`: what a missing value, or one not among the limits, maps to: `nil` for alpha and
      size, grey, `"#7F7F7F"`, for colour and fill, or `:none`, no colour. A missing value takes
      no share of the palette; a position scale puts it at its last level, and its `na_value` is
      `nil`.
    * `guide`: the guide that draws it: `:axis` for a position and `:legend` for an aesthetic such
      as alpha or colour, `:none` for none, or a legend `Giggly.Plot.guide_legend/1` makes.
    * `name`: its guide's title, `:none` for none, or `:default` for the title its mapping
      gives.
    * `limits`: the values it shows, in the order shown, whatever the data, or `:default` for its
      levels, those a manual palette's map has a colour for where it is one. A value not among
      them is missing, so its mark is not drawn on an axis and takes the `na_value` elsewhere;
      `nil` among them places the missing value. A number names the value equal to it, so `2`
      names a level of `2.0`.
    * `breaks`: the values an axis marks, in the order given, those not among its limits left out;
      `:none` for none, or `:default` for every one of its limits.
    * `labels`: the breaks' labels: a list, one for each break; a map from a value to its label,
      a value it does not hold keeping its own; a function handed every break drawn, which
      returns their labels; `:none` for none; or `:default`, each value written as text.
    * `expand`: how far an axis reaches beyond its first and last values,
      `[mult: {low, high}, add: {low, high}]`: at each end, that multiple of the distance between
      them plus that constant.
  """

  # Use it through `Giggly.Scale`.

  alias Giggly.Scale.{Continuous, Palette}

  # Every field's default is a position scale's before it has seen any data: no levels, the
  # identity palette, an axis, and every option the default, ggplot2's 0.6 of a level's room at
  # each end among them.
  defstruct levels: [],
            continuous_range: :none,
            palette: :identity,
            na_value: nil,
            guide: :axis,
            name: :default,
            limits: :default,
            breaks: :default,
            labels: :default,
            expand: [mult: {0, 0}, add: {0.6, 0.6}]

  @type t :: %__MODULE__{
          levels: list(),
          continuous_range: :none | {number(), number()},
          palette:
            :identity
            | {:sequence, {number(), number()}}
            | {:hue,
               %{
                 hue: {number(), number()},
                 chroma: number(),
                 luminance: number(),
                 direction: 1 | -1
               }}
            | {:gray, {number(), number()}}
            | {:manual, [String.t() | :none] | %{term() => String.t() | :none}}
            | {:area_sequence, {number(), number()}},
          na_value: nil | number() | String.t() | :none,
          guide: :axis | :legend | :none | struct(),
          name: :default | :none | String.t(),
          limits: :default | [term()],
          breaks: :default | :none | [term()],
          labels: :default | :none | [String.t()] | %{term() => String.t()} | (list() -> list()),
          expand: [mult: {number(), number()}, add: {number(), number()}]
        }

  # The scale with the distinct `values` merged into its levels, as `Giggly.Scale.train/2`
  # describes.
  @doc false
  @spec train(t(), list()) :: t()
  def train(%__MODULE__{levels: levels} = scale, values) do
    merged =
      levels
      |> Enum.concat(values)
      |> Enum.uniq()
      |> Enum.sort_by(&Giggly.Scale.level_key/1)

    %{scale | levels: merged}
  end

  # The scale with its continuous range widened to cover the positions `values`, its levels left
  # alone, as `Giggly.Scale.train_positions/2` describes.
  @doc false
  @spec train_positions(t(), list()) :: t()
  def train_positions(%__MODULE__{continuous_range: range} = scale, values),
    do: %{scale | continuous_range: Continuous.train_range(range, values)}

  # The values the scale shows, in order, as ggplot2's `get_limits()` gives them: its limits where
  # given, else its levels, or, for a manual palette's map, those of its levels the map has a
  # colour for, and the missing value where it is one, as ggplot2's manual scale limits itself to
  # the names of its values.
  @doc false
  @spec limits(t()) :: list()
  def limits(%__MODULE__{limits: :default, levels: levels, palette: {:manual, colors}})
      when is_map(colors) do
    named = MapSet.new(colors, fn {value, _color} -> key(value) end)
    Enum.filter(levels, fn level -> is_nil(level) or MapSet.member?(named, key(level)) end)
  end

  def limits(%__MODULE__{limits: :default, levels: levels}), do: levels
  def limits(%__MODULE__{limits: limits}), do: limits

  # Each value as `Giggly.Scale.map/2` describes: a position at its place among the limits counting
  # from 1, `nil` for a value not among them; for any other palette, its value from the palette,
  # which spreads the present limits, `nil` taking none of them, or, for a manual palette's map,
  # the colour it gives the value; and the scale's `na_value` for `nil`, a value not among the
  # limits, or one the map has no colour for, as ggplot2's mapping gives each its `na.value`.
  @doc false
  @spec map(t(), list()) :: list()
  def map(%__MODULE__{palette: :identity} = scale, values) do
    position_by_key =
      scale
      |> limits()
      |> Enum.with_index(1)
      |> Map.new(fn {limit, position} -> {key(limit), position} end)

    Enum.map(values, fn value -> Map.get(position_by_key, key(value)) end)
  end

  def map(%__MODULE__{palette: palette, na_value: na_value} = scale, values) do
    present =
      scale
      |> limits()
      |> Enum.reject(&is_nil/1)

    value_by_key =
      present
      |> Enum.zip_with(palette_values(palette, present, na_value), fn limit, mapped ->
        {key(limit), mapped}
      end)
      |> Map.new()

    Enum.map(values, fn value -> Map.get(value_by_key, key(value), na_value) end)
  end

  # The palette's value for each of the present limits: a manual palette's map gives each the
  # colour it holds for it, by value, or `na_value`; any other palette spreads them in order.
  defp palette_values({:manual, colors}, present, na_value) when is_map(colors) do
    color_by_key = Map.new(colors, fn {value, color} -> {key(value), color} end)
    Palette.named(color_by_key, Enum.map(present, &key/1), na_value)
  end

  defp palette_values(palette, present, _na_value),
    do: Palette.discrete(palette, length(present))

  # The key a value is looked up by: a number as a float, so an integer and the float equal to it
  # share one, and adding a zero turns a negative zero into the zero it equals; any other value as
  # it is.
  @doc false
  @spec key(term()) :: term()
  def key(value) when is_number(value), do: value + 0.0
  def key(value), do: value
end
