defmodule Giggly.Scale.Palette do
  @moduledoc false

  # Palettes: the last step of a scale, which turns where a value sits among the data into the
  # value of its aesthetic, as R's `scales` palettes do. A palette is a value naming the function,
  # never a closure, so a scale stays a value that compares and prints.
  #
  #   * `:identity`, a position's: the value is left where the scale puts it, as ggplot2's position
  #     scales' palette is the identity, and the coordinate system places it.
  #   * `{:rescale, {low, high}}`, a continuous scale's: a value's place in the scale's limits,
  #     from 0 to 1, rescaled onto `low` to `high`, as R's `pal_rescale()` does with `rescale()`.
  #   * `{:gradient, colors}`, a continuous colour scale's: a value's place in the limits, from 0
  #     to 1, along a gradient through `colors`, spaced evenly from 0 to 1, as R's
  #     `pal_gradient_n()` blends them through `colour_ramp()`, which its two- and three-colour
  #     gradients are too: each colour's L*, a* and b* (`Giggly.ColorOperations`), the place's
  #     channels interpolated between the two colours either side as R's `approxfun()` does, a
  #     place at a colour taking that colour's exactly, and the blend turned back into a colour. One
  #     colour is every place's. ggplot2's default runs from `#132B43` to `#56B1F7`.
  #   * `{:area, {low, high}}`, a continuous size scale's: a value's place in the limits, from 0 to
  #     1, its square root rescaled onto `low` to `high`, as R's `pal_area()` does, so a point's
  #     area, not its width, grows with the value. ggplot2's default runs from 1 to 6.
  #   * `{:abs_area, max}`, the size scale's that puts 0 at size 0: the square root of a place's
  #     size rescaled onto 0 to `max`, as R's `abs_area()` does. Its scale places a value at its
  #     share of the limits' high end, which may be below 0, hence the size.
  #   * `{:sequence, {low, high}}`, a discrete scale's: given the number of levels, that many
  #     values from `low` to `high`, evenly spaced, as ggplot2's ordinal alpha scale takes R's
  #     `seq(low, high, length.out = n)`.
  #   * `{:area_sequence, {low, high}}`, a discrete size scale's: given the number of levels, that
  #     many sizes from `low` to `high` whose squares are evenly spaced, so their areas are, as
  #     ggplot2's ordinal size scale takes R's `sqrt(seq(low^2, high^2, length.out = n))`, `low^2`
  #     as R's `^` computes a square, `low * low`. ggplot2's default runs from 2 to 6.
  #   * `{:hue, %{hue: {low, high}, chroma: chroma, luminance: luminance, direction: direction}}`,
  #     a discrete colour scale's: given the number of levels, that many colours of one chroma and
  #     luminance, their hues spaced evenly from `low` to `high`, as R's `pal_hue()` gives them,
  #     handed out in reverse for a `direction` of -1. A range spanning the whole circle, less than
  #     a degree short of it or past it, leaves its last share off, since its end is its start.
  #     ggplot2's default is hues from 15 round to 375, chroma 100 and luminance 65.
  #   * `{:gray, {start, finish}}`, a discrete colour scale's: given the number of levels, that
  #     many greys from the level `start` to `finish`, 0 black and 1 white, as R's `pal_grey()`
  #     takes them from `grey.colors()`: the levels spaced evenly once raised to the power 2.2,
  #     each brought back by the power `1 / 2.2` and written as R's `gray()` writes it, its byte
  #     `255 * level + 0.5` truncated. R spaces them with `seq.int()`, which steps on from the
  #     start as `seq()` does, so they are spaced as `seq()` spaces them.
  #   * `{:viridis, %{option: option, begin: begin, end: end, direction: direction, alpha:
  #     alpha}}`, a discrete colour scale's: given the number of levels, that many colours of the
  #     viridis palette `option`, as R's `pal_viridis()` takes them from `viridisLite::viridis()`
  #     (`Giggly.ColorOperations.viridis/2`), from `begin` to `end`, or `end` to `begin` for a
  #     `direction` of -1, with an alpha of `alpha`. ggplot2's default, an ordered factor's, is
  #     the palette `:viridis` from 0 to 1, opaque.
  #   * `{:shape, :solid | :open}`, a discrete shape scale's: given the number of levels, that many
  #     of six shapes, by name, as R's `pal_shape()` gives them: solid, R's 16, 17, 15, 3, 7 and 8,
  #     or open, its 1, 2, 0, 3, 7 and 8. More than six levels cannot be drawn: R warns and leaves
  #     the seventh on unshaped, so its points vanish, and Giggly, which cannot warn, raises,
  #     naming the manual scale that takes more.
  #   * `:linetype`, a discrete line type scale's: given the number of levels, that many of 13 line
  #     types, each as its dash pattern, as R's `pal_linetype()` gives them: `"solid"`, held as
  #     `{}`, then the patterns R writes in hex digits, `"22"` to `"F1"`, as tuples of their lengths.
  #     More than 13 levels cannot be drawn: R warns and leaves the fourteenth on with no line type,
  #     so its lines vanish, and Giggly, which cannot warn, raises, naming the manual scale that
  #     takes more.
  #   * `{:manual, values}`, a discrete colour, shape or line type scale's, `values` a list: its
  #     first values, one for each level in level order, as R's manual palette gives them. A manual
  #     palette may instead be a map from a value to its colour, shape or line type, each level
  #     taking its own by value (`named/3`), or `{:manual, values, breaks}`, a list each of whose
  #     values is the break's at its place, as R's manual scale names a list by its breaks, a level
  #     no break names taking none (`named_by_breaks/4`). Either way, more levels than values cannot
  #     be drawn, as R's manual scale fails whatever its values' names.
  #
  # Use it through `Giggly.Scale`.

  # A palette's colours come from the colour operations.
  alias Giggly.ColorOperations

  @typedoc "A scale's palette."
  @type t ::
          :identity
          | {:rescale, {number(), number()}}
          | {:gradient, [String.t()]}
          | {:sequence, {number(), number()}}
          | {:hue,
             %{
               hue: {number(), number()},
               chroma: number(),
               luminance: number(),
               direction: 1 | -1
             }}
          | {:gray, {number(), number()}}
          | {:viridis,
             %{
               option: atom(),
               begin: number(),
               end: number(),
               direction: 1 | -1,
               alpha: number()
             }}
          | {:shape, :solid | :open}
          | :linetype
          | {:manual, [manual_value()] | %{term() => manual_value()}}
          | {:manual, [manual_value()], [term()]}
          | {:area, {number(), number()}}
          | {:abs_area, number()}
          | {:area_sequence, {number(), number()}}

  @typedoc "A manual palette's value: a colour, a shape's name, or a line type's dash pattern."
  @type manual_value :: ColorOperations.t() | atom() | tuple()

  # R's gamma for `grey.colors()`.
  @gray_gamma 2.2

  # `pal_shape()`'s shapes, R's 16, 17, 15, 3, 7 and 8, solid, or 1, 2, 0, 3, 7 and 8, open, by the
  # names a point is drawn in.
  @shapes %{
    solid: [:circle_small, :triangle, :square, :plus, :square_cross, :asterisk],
    open: [:circle_open, :triangle_open, :square_open, :plus, :square_cross, :asterisk]
  }

  # `pal_linetype()`'s line types, R's `"solid"`, `"22"`, `"42"`, `"44"`, `"13"`, `"1343"`, `"73"`,
  # `"2262"`, `"12223242"`, `"F282"`, `"F4448444"`, `"224282F2"` and `"F1"`, each as its dash
  # pattern, a hex digit as its length.
  @line_types [
    {},
    {2, 2},
    {4, 2},
    {4, 4},
    {1, 3},
    {1, 3, 4, 3},
    {7, 3},
    {2, 2, 6, 2},
    {1, 2, 2, 2, 3, 2, 4, 2},
    {15, 2, 8, 2},
    {15, 4, 4, 4, 8, 4, 4, 4},
    {2, 2, 4, 2, 8, 2, 15, 2},
    {15, 1}
  ]

  # A continuous palette's value for a place from 0 to 1 in the scale's limits: for a rescale, R's
  # `rescale(x, to = range, from = c(0, 1))`, as `pal_rescale()` computes it; for an area, the
  # place's square root rescaled so, as `pal_area()` computes it; for an absolute area, the square
  # root of the place's size rescaled onto 0 to the maximum, as `abs_area()` computes it, a place
  # being any number its scale's rescaler gives; for a gradient, the colour that far along it, as
  # the opening comment says.
  @doc false
  @spec continuous({:rescale | :area, {number(), number()}}, number()) :: float()
  @spec continuous({:abs_area, number()}, number()) :: float()
  @spec continuous({:gradient, [String.t()]}, number()) :: String.t()
  def continuous({:rescale, to}, place), do: Giggly.Scale.rescale(place, {0, 1}, to)

  def continuous({:area, to}, place) do
    place
    |> :math.sqrt()
    |> Giggly.Scale.rescale({0, 1}, to)
  end

  def continuous({:abs_area, max}, place) do
    place
    |> abs()
    |> :math.sqrt()
    |> Giggly.Scale.rescale({0, 1}, {0, max})
  end

  def continuous({:gradient, [color]}, _place), do: color

  def continuous({:gradient, colors}, place) do
    knots = spread({0.0, 1.0}, length(colors))

    lab =
      case Enum.find_index(knots, fn knot -> knot == place end) do
        nil ->
          blend(Enum.zip(knots, colors), place)

        index ->
          colors
          |> Enum.at(index)
          |> ColorOperations.to_lab()
      end

    ColorOperations.from_lab(lab)
  end

  # The L*a*b* `place` of the way between the two colours either side of it, each a knot and its
  # colour, as R's `approxfun()` interpolates: `low + (high - low) * ((place - low_knot) /
  # (high_knot - low_knot))`, channel by channel, in that order of operations.
  defp blend(knotted, place) do
    [{low_knot, low_color}, {high_knot, high_color}] =
      knotted
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.find(fn [{low_knot, _low}, {high_knot, _high}] ->
        place > low_knot and place < high_knot
      end)

    fraction = (place - low_knot) / (high_knot - low_knot)

    low_color
    |> lab_channels()
    |> Enum.zip_with(lab_channels(high_color), fn low_channel, high_channel ->
      low_channel + (high_channel - low_channel) * fraction
    end)
    |> List.to_tuple()
  end

  # A colour's L*, a* and b*, as a list.
  defp lab_channels(color) do
    color
    |> ColorOperations.to_lab()
    |> Tuple.to_list()
  end

  # A discrete palette's values for `count` levels, in level order.
  #
  # A sequence's are R's `seq(low, high, length.out = count)` (`spread/2`).
  #
  # A hue palette's are `pal_hue()`'s: the circle's last `360 / count` degrees left off where the
  # range, taken modulo 360 as R's `%%` takes it, is less than a degree, since its end is then its
  # start; the hues spread over the range by `spread/2`; each colour made by
  # `ColorOperations.from_hcl/3`, as `pal_hue()` has farver encode it; and the colours reversed for
  # a direction of -1. R takes each hue modulo 360 first; a hue is turned through its cosine and
  # sine, which repeat every 360 degrees, so the colours are the same without it, as they are for
  # every range, chroma, luminance and count its test pins.
  #
  # A grey palette's are `grey.colors()`'s, a viridis palette's `viridisLite::viridis()`'s, a shape
  # or line type palette's its first shapes or line types, and a manual one's its first values, as
  # the opening comment says; a shape or line type palette for more levels than it holds, or a
  # manual palette of too few values, raises.
  #
  # An area sequence's are the square roots of `spread/2` from `low * low` to `high * high`.
  #
  # A scale whose every value is missing has no levels to ask for, and ggplot2 then maps every
  # value to its NA value without asking its palette, so no levels give none.
  @doc false
  @spec discrete({:sequence | :area_sequence, {number(), number()}}, non_neg_integer()) ::
          [number()]
  @spec discrete({:hue | :gray | :viridis, term()}, non_neg_integer()) :: [ColorOperations.t()]
  @spec discrete({:shape, :solid | :open}, non_neg_integer()) :: [atom()]
  @spec discrete(:linetype, non_neg_integer()) :: [tuple()]
  @spec discrete({:manual, list()}, non_neg_integer()) :: [manual_value()]
  def discrete({:sequence, range}, count), do: spread(range, count)

  def discrete({:area_sequence, {low, high}}, count) do
    {low * low, high * high}
    |> spread(count)
    |> Enum.map(&:math.sqrt/1)
  end

  def discrete({:hue, _parameters}, 0), do: []

  def discrete({:hue, %{hue: {low, high}} = parameters}, count) when count > 0 do
    %{chroma: chroma, luminance: luminance, direction: direction} = parameters
    high = if modulo(high - low, 360) < 1, do: high - 360 / count, else: high

    {low, high}
    |> spread(count)
    |> Enum.map(fn hue -> ColorOperations.from_hcl(hue, chroma, luminance) end)
    |> directed(direction)
  end

  def discrete({:gray, _range}, 0), do: []

  def discrete({:gray, {start, finish}}, count) when count > 0 do
    {:math.pow(start, @gray_gamma), :math.pow(finish, @gray_gamma)}
    |> spread(count)
    |> Enum.map(fn level -> gray(:math.pow(level, 1 / @gray_gamma)) end)
  end

  def discrete({:viridis, parameters}, count), do: ColorOperations.viridis(count, parameters)

  def discrete({:shape, fill}, count) do
    shapes = Map.fetch!(@shapes, fill)

    if count > length(shapes) do
      raise ArgumentError,
            "a shape scale's palette has #{length(shapes)} shapes, too few for its #{count} " <>
              "values, since more are hard to tell apart; Giggly.Plot.scale_shape_manual/2 " <>
              "gives a shape for each"
    end

    Enum.take(shapes, count)
  end

  def discrete(:linetype, count) do
    if count > length(@line_types) do
      raise ArgumentError,
            "a line type scale's palette has #{length(@line_types)} line types, too few for its " <>
              "#{count} values, since more are hard to tell apart; " <>
              "Giggly.Plot.scale_linetype_manual/2 gives a line type for each"
    end

    Enum.take(@line_types, count)
  end

  def discrete({:manual, values}, count) when is_list(values) do
    check_enough(values, count)
    Enum.take(values, count)
  end

  # A manual palette's map's value for each of `keys`, the present levels' keys as the scale
  # matches them (`Giggly.Scale.Discrete.key/1`), the map's keys turned so too, or `missing` for
  # a level the map has no value for; a map of fewer values than levels raises, as the opening
  # comment says.
  @doc false
  @spec named(%{term() => term()}, [term()], term()) :: [term()]
  def named(value_by_key, keys, missing) do
    check_enough(value_by_key, length(keys))
    Enum.map(keys, fn key -> Map.get(value_by_key, key, missing) end)
  end

  # A manual palette's list named by breaks: for each of `keys`, the present levels' keys as the
  # scale matches them, the value at the place of the break whose key, in `break_keys`, it is, or
  # `missing` for a level no break names, a value beyond the last break naming none; a list of
  # fewer values than levels raises, as R counts every value of a manual scale, named or not.
  @doc false
  @spec named_by_breaks(list(), [term()], [term()], term()) :: [term()]
  def named_by_breaks(values, break_keys, keys, missing) do
    check_enough(values, length(keys))

    value_by_key =
      break_keys
      |> Enum.zip(values)
      |> Map.new()

    Enum.map(keys, fn key -> Map.get(value_by_key, key, missing) end)
  end

  defp check_enough(values, count) when is_list(values) and count <= length(values), do: :ok
  defp check_enough(values, count) when is_map(values) and count <= map_size(values), do: :ok

  defp check_enough(values, count) do
    raise ArgumentError,
          "a manual scale needs a value for each of its #{count} levels, " <>
            "but has #{Enum.count(values)}: #{inspect(values)}"
  end

  # `count` values from `low` to `high`, evenly spaced, as R's `seq(low, high, length.out =
  # count)` spaces them: none for no levels, the first `low` and the last `high` exactly, and each
  # one between `low` plus its index times the step, in that order of operations, as R's
  # `seq.default()` computes it, so the fourth of seven from 0.1 to 1 is 0.54999999999999993, not
  # 0.55; one for one level, `low`.
  @doc false
  @spec spread({number(), number()}, non_neg_integer()) :: [number()]
  def spread({_low, _high}, 0), do: []
  def spread({low, _high}, 1), do: [low]
  def spread({low, high}, 2), do: [low, high]

  def spread({low, high}, count) when count > 2 do
    step = (high - low) / (count - 1)
    between = Enum.map(1..(count - 2), fn index -> low + index * step end)
    Enum.concat([[low], between, [high]])
  end

  # A grey of `level`, 0 black to 1 white, as R's `gray()` writes it.
  defp gray(level) do
    digits =
      (255 * level + 0.5)
      |> trunc()
      |> Integer.to_string(16)
      |> String.pad_leading(2, "0")

    "#" <> String.duplicate(digits, 3)
  end

  defp directed(colors, 1), do: colors
  defp directed(colors, -1), do: Enum.reverse(colors)

  # `value` modulo `divisor`, its sign the divisor's, as R's `%%` takes it.
  defp modulo(value, divisor), do: value - Float.floor(value / divisor) * divisor
end
