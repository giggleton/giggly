defmodule Giggly.Scale.Discrete do
  @moduledoc """
  A discrete scale. `Giggly.Plot.scale_x_discrete/2` records one with the options it is given and
  no levels, and `Giggly.panel_scales/2` returns an axis's trained. Its fields:

    * `levels`: the distinct values it has seen, in level order: a factor's in its levels' order,
      those it lacks after them, and values with no levels of their own sorted, a missing value
      last, but where `factor` keeps them in the order they came.
    * `factor`: whether the first values it was trained on were a factor's, whose levels have an
      order of their own: `true` keeps its levels in the order they came, each new value after
      them; `false` sorts them again whenever values with no levels of their own come, a factor's
      levels first until then; `:none` before it has seen any.
    * `continuous_range`: the range of the positions it has been handed since its levels were
      placed, such as a bar's edges, which can widen the axis past its levels; `:none` before any.
    * `palette`: what turns a value into its aesthetic's value: `:identity` for a position, each
      value at its place counting from 1; `{:sequence, {low, high}}` for an aesthetic such as
      alpha or line width, the values spread evenly from `low` to `high` in order; and, for colour
      and fill, `{:hue, %{hue: {low, high}, chroma: chroma, luminance: luminance, direction:
      direction}}`,
      a colour for each value, their hues spaced evenly from `low` to `high` round the circle,
      handed out in reverse for a `direction` of -1; `{:gray, {start, finish}}`, greys from the
      level `start` to `finish`, 0 black and 1 white; or `{:manual, colors}`, the colours of a
      list in order, or those of a map from value to colour by value, or `{:manual, colors,
      breaks}`, the colours of a list each given to the break at its place; for size,
      `{:area_sequence, {low, high}}`, sizes from `low` to `high` whose squares, and so areas, are
      spread evenly; for shape, `{:shape, :solid}` or `{:shape, :open}`, six shapes by name in
      order, solid or open, or `{:manual, shapes}`, a list's or a map's, as a colour's; and for
      line type, `:linetype`, 13 line types in order, each as its dash pattern, `{}` for a solid
      line, or `{:manual, line_types}`, as a colour's; or any other of `Scales.Palette`'s, such as
      `{:brewer, %{palette: "Set1", direction: 1}}`, a ColorBrewer palette's colours in order, a
      continuous one's taken at places spread evenly over it.
    * `na_value`: what a missing value, or one not among the limits, maps to: `nil` for alpha, line
      type, line width, shape and size, grey, `"#7F7F7F"`, for colour and fill, `:none`, no colour,
      shape or line, or the shape, line type or width a plot's scale gives. A missing value takes
      no share of the palette; a position scale puts it at its last level, and its `na_value` is
      `nil`.
    * `guide`: the guide that draws it: `:axis` for a position and `:legend` for an aesthetic such
      as alpha or colour, `:none` for none, or a legend `Giggly.Plot.guide_legend/1` makes.
    * `name`: its guide's title, `:none` for none, or `:default` for the title its mapping
      gives.
    * `limits`: the values it shows, in the order shown, whatever the data, or `:default` for its
      levels, those a manual palette's map has a value for where it is one. A value not among
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

  alias Scales.{DataRange, Palette}

  # Every field's default is a position scale's before it has seen any data: no levels, the
  # identity palette, an axis, and every option the default, ggplot2's 0.6 of a level's room at
  # each end among them.
  defstruct levels: [],
            factor: :none,
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
          factor: :none | boolean(),
          continuous_range: :none | {number(), number()},
          palette:
            Palette.t()
            | {:sequence, {number(), number()}}
            | {:manual, %{term() => String.t() | atom() | tuple()}}
            | {:manual, [String.t() | atom() | tuple()], [term()]}
            | {:area_sequence, {number(), number()}},
          na_value: nil | number() | String.t() | atom() | tuple(),
          guide: :axis | :legend | :none | struct(),
          name: :default | :none | String.t(),
          limits: :default | [term()],
          breaks: :default | :none | [term()],
          labels: :default | :none | [String.t()] | %{term() => String.t()} | (list() -> list()),
          expand: [mult: {number(), number()}, add: {number(), number()}]
        }

  # The scale with `values` merged into its levels, as R's `scales::discrete_range()` merges a
  # range (`Scales.DataRange.train_discrete/3`), `levels` the factor's levels they are values of,
  # or `:none`; as `Giggly.Scale.train/3` describes.
  @doc false
  @spec train(t(), list(), list() | :none) :: t()
  def train(%__MODULE__{levels: held, factor: factor} = scale, values, levels) do
    {merged, factor} = DataRange.train_discrete({held, factor}, values, levels)
    %{scale | levels: merged, factor: factor}
  end

  # The scale with its continuous range widened to cover the positions `values`, its levels left
  # alone, as `Giggly.Scale.train_positions/2` describes.
  @doc false
  @spec train_positions(t(), list()) :: t()
  def train_positions(%__MODULE__{continuous_range: range} = scale, values),
    do: %{scale | continuous_range: DataRange.train_continuous(range, values)}

  # The values the scale shows, in order, as ggplot2's `get_limits()` gives them: its limits where
  # given, else its levels, or, for a manual palette's map, those of its levels the map has a
  # value for, and the missing value where it is one, as ggplot2's manual scale limits itself to
  # the names of its values.
  @doc false
  @spec limits(t()) :: list()
  def limits(%__MODULE__{limits: :default, levels: levels, palette: {:manual, colors}})
      when is_map(colors) do
    named = MapSet.new(colors, fn {value, _color} -> DataRange.key(value) end)

    Enum.filter(levels, fn level ->
      is_nil(level) or MapSet.member?(named, DataRange.key(level))
    end)
  end

  def limits(%__MODULE__{limits: :default, levels: levels}), do: levels
  def limits(%__MODULE__{limits: limits}), do: limits

  # Each value as `Giggly.Scale.map/2` describes: a position at its place among the limits counting
  # from 1, `nil` for a value not among them; for any other palette, its value from the palette,
  # which spreads the present limits, `nil` taking none of them, or, for a manual palette's map,
  # the value it gives the value; and the scale's `na_value` for `nil`, a value not among the
  # limits, or one the map has no value for, as ggplot2's mapping gives each its `na.value`.
  @doc false
  @spec map(t(), list()) :: list()
  def map(%__MODULE__{palette: :identity} = scale, values) do
    position_by_key =
      scale
      |> limits()
      |> Enum.with_index(1)
      |> Map.new(fn {limit, position} -> {DataRange.key(limit), position} end)

    Enum.map(values, fn value -> Map.get(position_by_key, DataRange.key(value)) end)
  end

  def map(%__MODULE__{palette: palette, na_value: na_value} = scale, values) do
    present =
      scale
      |> limits()
      |> Enum.reject(&is_nil/1)

    value_by_key =
      present
      |> Enum.zip_with(palette_values(palette, present, na_value), fn limit, mapped ->
        {DataRange.key(limit), mapped}
      end)
      |> Map.new()

    Enum.map(values, fn value -> Map.get(value_by_key, DataRange.key(value), na_value) end)
  end

  # The palette's value for each of the present limits, which ggplot2's palettes give and refuse
  # where R's scales does neither: a sequence spreads them evenly from `low` to `high`, as
  # `scale_alpha_ordinal()`'s `seq(low, high, length.out = n)`, and an area sequence spreads their
  # squares, as `scale_size_ordinal()`'s `sqrt(seq(low^2, high^2, length.out = n))`, `low^2` as R's
  # `^` squares, `low * low`; a manual palette's map gives each the value it holds for it, by value,
  # or `na_value`, and so does a list named by breaks, each value its break's, a value beyond the
  # last break naming none, as ggplot2's `manual_scale()` names values; any other palette is R's
  # (`Scales.Palette.discrete/2`). Too few values for the limits raise, as ggplot2's manual scale
  # fails whatever its values' names; and a shape, line type or brewer palette with more levels
  # than it holds, which R's palettes give `NA` with a warning and leave undrawn, raises naming the
  # scale that takes more. A scale whose every value is missing has no levels to ask for, and
  # ggplot2 then maps every value to its `na.value` without asking its palette.
  defp palette_values({:sequence, range}, present, _na_value),
    do: Palette.spread(range, length(present))

  defp palette_values({:area_sequence, {low, high}}, present, _na_value) do
    {low * low, high * high}
    |> Palette.spread(length(present))
    |> Enum.map(&:math.sqrt/1)
  end

  defp palette_values({:manual, values}, present, na_value) when is_map(values) do
    enough!(values, present)
    value_by_key = Map.new(values, fn {value, mapped} -> {DataRange.key(value), mapped} end)
    Enum.map(present, fn limit -> Map.get(value_by_key, DataRange.key(limit), na_value) end)
  end

  defp palette_values({:manual, values, breaks}, present, na_value) do
    enough!(values, present)

    value_by_key =
      breaks
      |> Enum.zip_with(values, fn limit, value -> {DataRange.key(limit), value} end)
      |> Map.new()

    Enum.map(present, fn limit -> Map.get(value_by_key, DataRange.key(limit), na_value) end)
  end

  defp palette_values({:manual, values} = palette, present, _na_value) do
    enough!(values, present)
    Palette.discrete(palette, length(present))
  end

  defp palette_values({:shape, _fill} = palette, present, _na_value),
    do: drawable!(palette, present, {"shape", "shapes"}, "Giggly.Plot.scale_shape_manual/2")

  defp palette_values({:brewer, _parameters} = palette, present, _na_value) do
    drawable!(
      palette,
      present,
      {"colour", "colours"},
      "Giggly.Plot.scale_color_manual/2 or scale_fill_manual/2"
    )
  end

  defp palette_values(:linetype, present, _na_value) do
    drawable!(
      :linetype,
      present,
      {"line type", "line types"},
      "Giggly.Plot.scale_linetype_manual/2"
    )
  end

  defp palette_values(palette, present, _na_value),
    do: Palette.discrete(palette, length(present))

  defp enough!(values, present) when is_map(values) and length(present) <= map_size(values),
    do: :ok

  defp enough!(values, present) when is_list(values) and length(present) <= length(values),
    do: :ok

  defp enough!(values, present) do
    raise ArgumentError,
          "a manual scale needs a value for each of its #{length(present)} levels, " <>
            "but has #{Enum.count(values)}: #{inspect(values)}"
  end

  # The palette's values for the present limits, refused where it holds fewer than they need, as
  # R's palette gives `nil` past its end.
  defp drawable!(palette, present, {kind, kinds}, manual_scale) do
    count = length(present)
    values = Palette.discrete(palette, count)
    held = Enum.count(values, fn value -> not is_nil(value) end)

    if held < count do
      raise ArgumentError,
            "a #{kind} scale's palette has #{held} #{kinds}, too few for its #{count} values, " <>
              "since more are hard to tell apart; #{manual_scale} gives a #{kind} for each"
    end

    values
  end
end
