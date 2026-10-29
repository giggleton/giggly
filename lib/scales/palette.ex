defmodule Scales.Palette do
  @moduledoc """
  Palettes: what turns a value's place among the data into a value of its aesthetic, a colour, a
  size, a shape or a line type. A palette is a value naming its function, so it compares and
  prints. A continuous palette is handed places, 0 to 1 over the data's range (`continuous/2`); a
  discrete one the number of levels it must tell apart (`discrete/2`).

  ## Continuous palettes

    * `:identity`, R's `pal_identity()`: each place as it is.
    * `{:rescale, {low, high}}`, R's `pal_rescale()`: each place moved onto `low` to `high`.
    * `{:area, {low, high}}`, R's `pal_area()`: each place's square root moved onto `low` to
      `high`, so an area drawn at that size grows with the place.
    * `{:abs_area, max}`, R's `abs_area()`: the square root of each place's size moved onto 0 to
      `max`; a place may lie below 0 or past 1.
    * `{:gradient, colors}`, R's `pal_gradient_n()`, which R's two- and three-colour gradients are
      too: the colour that far along a gradient through `colors`, spaced evenly from 0 to 1, each
      place between two blended in CIE L*a*b*; a place at a colour takes it exactly, and one
      colour is every place's.

  ## Discrete palettes

    * `{:hue, %{hue: {low, high}, chroma: chroma, luminance: luminance, direction: direction}}`,
      R's `pal_hue()`: colours of one chroma and luminance, their hues spaced evenly from `low` to
      `high`, handed out in reverse for a `direction` of -1. A range within a degree of the whole
      circle leaves its last share off, since its end is its start.
    * `{:gray, {start, finish}}`, R's `pal_grey()`: greys from the level `start` to `finish`, 0
      black and 1 white, spaced evenly once raised to the power 2.2.
    * `{:viridis, %{option: option, begin: begin, end: end, direction: direction, alpha:
      alpha}}`, R's `pal_viridis()`: colours of a viridis palette, as
      `Scales.ColorOperations.viridis/2` gives them.
    * `{:shape, :solid}` or `{:shape, :open}`, R's `pal_shape()`: six shapes by name, solid
      (`:circle_small`, `:triangle`, `:square`, `:plus`, `:square_cross`, `:asterisk`, R's 16, 17,
      15, 3, 7 and 8) or open (`:circle_open`, `:triangle_open`, `:square_open` and the same last
      three, R's 1, 2, 0, 3, 7 and 8).
    * `:linetype`, R's `pal_linetype()`: 13 line types, each as its dash pattern, a tuple of
      lengths, `{}` for a solid line.
    * `{:manual, values}`, R's `pal_manual()`: `values` in order.
    * `{:brewer, %{palette: palette, direction: direction}}`, R's `pal_brewer()`: the colours of
      one of ColorBrewer's palettes, named as R spells it (`brewer_palettes/1` lists them), which
      has a set of its own for each count from 3 to its largest. Fewer than 3 levels take the
      start of its set of 3, and a `direction` of -1 hands the colours out in reverse once the
      `nil`s past its largest set are added, so those come first, as R's do. A name it does not
      know is refused, where R warns and gives Greens.

  A discrete palette asked for more levels than it holds gives `nil` for each past its end, as R
  gives `NA` (and warns). No levels give none, where R's hue palette refuses them.

  ## A palette of the other kind

  Each function takes a palette of the other kind too, as R's `as_continuous_pal()` and
  `as_discrete_pal()` convert one. `continuous/2` hands a discrete palette of colours on as a
  gradient through its `nlevels/1` colours, and one of numbers as those numbers joined by
  straight lines, spaced evenly from 0 to 1; a place outside them gives `nil`, and a palette of
  shapes, line types or other values is refused. `discrete/2` hands a continuous palette the
  levels' places, spaced evenly from 0 to 1 by `spread/2`. `:identity` and `{:abs_area, max}`,
  which R gives no type, are not converted: R hands them back as they are, so asked for 3 levels
  they give the one number 3, and here they are refused.

  Colours are uppercase `#RRGGBB`, or `#RRGGBBAA` with an alpha of their own, as
  `Scales.ColorOperations` writes them.

  ## ColorBrewer

  This product includes color specifications and designs developed by Cynthia Brewer
  (http://colorbrewer.org/). They are Copyright (c) 2002 Cynthia Brewer, Mark Harrower, and The
  Pennsylvania State University, licensed under the Apache License, Version 2.0, as R's
  RColorBrewer carries them.
  """

  # Each palette matched R to the last digit; the tests pin R's figures. The gradient blends as
  # `colour_ramp()` does: each colour's L*, a* and b* (`Scales.ColorOperations`), a place's
  # channels interpolated between the colours either side as R's `approxfun()` does, and the blend
  # turned back into a colour.

  alias Scales.{Bounds, ColorOperations}

  @typedoc "A continuous palette."
  @type continuous ::
          :identity
          | {:rescale, {number(), number()}}
          | {:area, {number(), number()}}
          | {:abs_area, number()}
          | {:gradient, [String.t(), ...]}

  @typedoc "A discrete palette."
  @type discrete ::
          {:hue,
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
          | {:manual, list()}
          | {:brewer, %{palette: String.t(), direction: 1 | -1}}

  @typedoc "A ColorBrewer palette's type: sequential, diverging or qualitative."
  @type brewer_type :: :seq | :div | :qual

  @typedoc "A palette."
  @type t :: continuous() | discrete()

  @typedoc "What a palette's values are: colours, numbers, shapes or line types."
  @type value_type :: :color | :numeric | :shape | :linetype

  # R's gamma for `grey.colors()`.
  @gray_gamma 2.2

  # The levels R's hue, grey and viridis palettes say they tell apart.
  @many_levels 255

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

  @brewer_path Application.app_dir(:giggly, "priv/palettes/brewer.csv")
  @external_resource @brewer_path

  # why: RColorBrewer's sets are read once, at compile time; no IO happens when a palette is used
  # instead of: the colours as literals in this module — rejected because they are R's output,
  #   kept as the file R writes so they can be regenerated and diffed against their source apart
  #   from the code
  # credo:disable-for-next-line Tack.Credo.Check.CorePurity
  @brewer_text File.read!(@brewer_path)

  # The file's rows, each a palette's name, its type, a count and that count's set of colours, in
  # the file's order: by type, each type's palettes as R's `pal_brewer()` numbers them, each
  # palette's sets from 3 colours up; its comment lines and header skipped.
  @brewer_rows @brewer_text
               |> String.split("\n", trim: true)
               |> Enum.reject(fn line -> String.starts_with?(line, "#") end)
               |> Enum.drop(1)
               |> Enum.map(fn line ->
                 [name, type, count, colors] = String.split(line, ",")
                 types = %{"seq" => :seq, "div" => :div, "qual" => :qual}
                 {name, Map.fetch!(types, type), String.to_integer(count), String.split(colors)}
               end)

  # Each set's colours by its palette's name and count.
  @brewer_sets Map.new(@brewer_rows, fn {name, _type, count, colors} ->
                 {{name, count}, colors}
               end)

  # Each palette's largest count, its last set's.
  @brewer_largest Map.new(@brewer_rows, fn {name, _type, count, _colors} -> {name, count} end)

  # Each type's palettes' names, in the order R numbers them.
  @brewer_palettes @brewer_rows
                   |> Enum.group_by(
                     fn {_name, type, _count, _colors} -> type end,
                     fn {name, _type, _count, _colors} -> name end
                   )
                   |> Map.new(fn {type, names} -> {type, Enum.dedup(names)} end)

  @brewer_names Map.keys(@brewer_largest)

  # scales' own names, each lowercased as R's `get_palette()` lowercases the name it is given, and
  # the palette R registers under it, with R's defaults: each brewer palette, each viridis option,
  # `pal_grey()` and `pal_hue()`.
  @brewer_named Map.new(@brewer_names, fn name ->
                  {String.downcase(name), {:brewer, %{palette: name, direction: 1}}}
                end)

  @viridis_named Map.new(ColorOperations.viridis_options(), fn option ->
                   parameters = %{option: option, begin: 0.0, end: 1.0, direction: 1, alpha: 1.0}
                   {Atom.to_string(option), {:viridis, parameters}}
                 end)

  @named @brewer_named
         |> Map.merge(@viridis_named)
         |> Map.merge(%{
           "grey" => {:gray, {0.2, 0.8}},
           "hue" => {:hue, %{hue: {15.0, 375.0}, chroma: 100.0, luminance: 65.0, direction: 1}}
         })

  # The names as a refusal lists them, brewer's by type in R's order.
  @known_names [:seq, :div, :qual]
               |> Enum.flat_map(fn type -> Map.fetch!(@brewer_palettes, type) end)
               |> Enum.concat(Enum.map(ColorOperations.viridis_options(), &Atom.to_string/1))
               |> Enum.concat(["grey", "hue"])
               |> Enum.map_join(", ", &inspect/1)

  @doc """
  Each place's value under a continuous palette, a place running from 0 to 1 over the data's
  range; a `nil` place gives `nil`. A discrete palette is converted first, as the moduledoc says.

  ## Examples

      iex> Scales.Palette.continuous({:rescale, {2, 5}}, [0, 0.3, 1, nil])
      [2.0, 2.9, 5.0, nil]

      iex> Scales.Palette.continuous({:area, {1.0, 6.0}}, [0.2, 1])
      [3.23606797749979, 6.0]

      iex> Scales.Palette.continuous({:gradient, ["#132B43", "#56B1F7"]}, [0, 0.5, 1])
      ["#132B43", "#336A98", "#56B1F7"]

      iex> Scales.Palette.continuous({:manual, [1.0, 5.0, 9.0]}, [0.25, 1.5])
      [3.0, nil]
  """
  @spec continuous(t(), [number() | nil]) :: [number() | String.t() | nil]
  def continuous(:identity, places), do: places
  def continuous({:rescale, to}, places), do: Bounds.rescale(places, {0, 1}, to)

  def continuous({:area, to}, places) do
    places
    |> each_place(&:math.sqrt/1)
    |> Bounds.rescale({0, 1}, to)
  end

  # R's `rescale(sqrt(abs(x)), c(0, max), c(0, 1))`.
  def continuous({:abs_area, max}, places) do
    places
    |> each_place(fn place ->
      place
      |> abs()
      |> :math.sqrt()
    end)
    |> Bounds.rescale({0, 1}, {0, max})
  end

  def continuous({:gradient, [color]}, places), do: each_place(places, fn _place -> color end)

  def continuous({:gradient, colors}, places) do
    knots = spread({0.0, 1.0}, length(colors))
    each_place(places, fn place -> gradient_color(knots, colors, place) end)
  end

  # A discrete palette is converted as R's `as_continuous_pal()` converts one: its `nlevels/1`
  # values, a gradient through them where they are colours, else joined by straight lines.
  def continuous({kind, _parameters} = palette, places)
      when kind in [:hue, :gray, :viridis, :brewer] do
    colors = discrete(palette, nlevels(palette))
    continuous({:gradient, colors}, places)
  end

  def continuous({:manual, values}, places) when is_list(values),
    do: manual_continuous(guessed_type(values), values, places)

  # A manual palette's colours may be written any way `ColorOperations.parse/1` reads, so each is
  # spelled as the gradient reads it first.
  defp manual_continuous(:color, [_color | _more] = colors, places) do
    spelled =
      Enum.map(colors, fn color ->
        {:ok, spelling} = ColorOperations.parse(color)
        spelling
      end)

    continuous({:gradient, spelled}, places)
  end

  defp manual_continuous(:numeric, [_first, _second | _more] = numbers, places) do
    knotted =
      {0.0, 1.0}
      |> spread(length(numbers))
      |> Enum.zip(numbers)

    each_place(places, fn place -> joined(knotted, place) end)
  end

  # The number at `place` on the straight lines through the knots and their numbers, as R's
  # `approxfun()` interpolates: a knot's own number at a knot, `nil` outside them.
  defp joined(knotted, place) do
    case {List.keyfind(knotted, place, 0), neighbours(knotted, place)} do
      {{_knot, number}, _neighbours} -> number
      {nil, nil} -> nil
      {nil, {{low_knot, low}, {high_knot, high}}} -> along(low, high, low_knot, high_knot, place)
    end
  end

  # The colour at `place` along the gradient, as the opening comment says.
  defp gradient_color(knots, colors, place) do
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
  # colour, channel by channel along the straight line between them.
  defp blend(knotted, place) do
    {{low_knot, low_color}, {high_knot, high_color}} = neighbours(knotted, place)

    low_color
    |> lab_channels()
    |> Enum.zip_with(lab_channels(high_color), fn low_channel, high_channel ->
      along(low_channel, high_channel, low_knot, high_knot, place)
    end)
    |> List.to_tuple()
  end

  # The two knots, each with its value, that `place` falls strictly between, or `nil` where it
  # falls between none.
  defp neighbours(knotted, place) do
    knotted
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find_value(fn [{low_knot, _low} = low, {high_knot, _high} = high] ->
      if place > low_knot and place < high_knot, do: {low, high}
    end)
  end

  # The value `place` of the way from `low` at `low_knot` to `high` at `high_knot`, as R's
  # `approxfun()` interpolates: `low + (high - low) * ((place - low_knot) / (high_knot -
  # low_knot))`, in that order of operations.
  defp along(low, high, low_knot, high_knot, place),
    do: low + (high - low) * ((place - low_knot) / (high_knot - low_knot))

  # A colour's L*, a* and b*, as a list.
  defp lab_channels(color) do
    color
    |> ColorOperations.to_lab()
    |> Tuple.to_list()
  end

  # A hue palette's are `pal_hue()`'s: the circle's last `360 / count` degrees left off where the
  # range, taken modulo 360 as R's `%%` takes it, is less than a degree, since its end is then its
  # start; the hues spread over the range by `spread/2`; each colour made by
  # `ColorOperations.from_hcl/3`, as `pal_hue()` has farver encode it; and the colours reversed for
  # a direction of -1. R takes each hue modulo 360 first; a hue is turned through its cosine and
  # sine, which repeat every 360 degrees, so the colours are the same without it, as they are for
  # every range, chroma, luminance and count its test pins.
  #
  # A grey palette's are `grey.colors()`'s: the levels spaced by `spread/2` once raised to the
  # power 2.2, each brought back by `1 / 2.2` and written as R's `gray()` writes it, the byte `255 *
  # level + 0.5` truncated. R spaces them with `seq.int()`, which steps on from the start as
  # `seq()` does.
  @doc """
  The values of a discrete palette for `count` levels, in level order. A continuous palette is
  converted first, as the moduledoc says.

  ## Examples

      iex> hue = %{hue: {15.0, 375.0}, chroma: 100.0, luminance: 65.0, direction: 1}
      iex> Scales.Palette.discrete({:hue, hue}, 3)
      ["#F8766D", "#00BA38", "#619CFF"]

      iex> Scales.Palette.discrete({:manual, ["#FF0000", "#0000FF"]}, 3)
      ["#FF0000", "#0000FF", nil]

      iex> Scales.Palette.discrete({:rescale, {1, 6}}, 3)
      [1.0, 3.5, 6.0]
  """
  @spec discrete(t(), non_neg_integer()) :: list()
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
  def discrete({:shape, fill}, count), do: padded(Map.fetch!(@shapes, fill), count)
  def discrete(:linetype, count), do: padded(@line_types, count)
  def discrete({:manual, values}, count) when is_list(values), do: padded(values, count)

  # A brewer palette's are `pal_brewer()`'s: the palette's set for `count`, or its set of 3 for
  # fewer, or its largest for more, padded with `nil` past its end and then directed, as R pads
  # before it reverses.
  def discrete({:brewer, %{palette: name, direction: direction}}, count)
      when name in @brewer_names do
    set_count =
      count
      |> max(3)
      |> min(Map.fetch!(@brewer_largest, name))

    @brewer_sets
    |> Map.fetch!({name, set_count})
    |> padded(count)
    |> directed(direction)
  end

  # A continuous palette is converted as R's `as_discrete_pal()` converts one: handed the levels'
  # places, R's `seq(0, 1, length.out = count)`.
  def discrete({kind, _parameters} = palette, count) when kind in [:rescale, :area, :gradient],
    do: continuous(palette, spread({0.0, 1.0}, count))

  @doc """
  What a palette's values are, R's `palette_type()`: `:color`, `:numeric`, `:shape` or
  `:linetype`, or `nil` for `:identity` and `{:abs_area, max}`, which R gives no type.

  A manual palette's is guessed from its values, as R's `pal_manual()` guesses it: `:color` where
  every value is a string `Scales.ColorOperations.parse/1` reads, as no values are, so not
  `:none`, `:numeric` where every one is a number, else `nil`, where R names how its values are
  stored (`"character"`). R reads a colour as hex or one of its own colour names, so `"grey50"` is a
  colour there and `"transparent"` is not; here they are the other way round.

  ## Examples

      iex> Scales.Palette.type({:brewer, %{palette: "Set1", direction: 1}})
      :color

      iex> Scales.Palette.type({:manual, [1, 5, 9]})
      :numeric

      iex> Scales.Palette.type({:manual, [:circle_small, :triangle]})
      nil
  """
  @spec type(t()) :: value_type() | nil
  def type(:identity), do: nil
  def type({:abs_area, _max}), do: nil
  def type({kind, _range}) when kind in [:rescale, :area], do: :numeric

  def type({kind, _parameters}) when kind in [:gradient, :hue, :gray, :viridis, :brewer],
    do: :color

  def type({:shape, fill}) when is_map_key(@shapes, fill), do: :shape
  def type(:linetype), do: :linetype
  def type({:manual, values}) when is_list(values), do: guessed_type(values)

  # R's `guess_pal_type()`, which asks for numbers first; no values are colours here, as R's
  # empty vector of strings is.
  defp guessed_type(values) do
    cond do
      Enum.all?(values, &color?/1) -> :color
      Enum.all?(values, &is_number/1) -> :numeric
      true -> nil
    end
  end

  defp color?(value) when is_binary(value), do: ColorOperations.parse(value) != :error
  defp color?(_value), do: false

  @doc """
  How many levels a discrete palette tells apart, R's `palette_nlevels()`: 6 shapes, 13 line
  types, a manual palette's values, a brewer palette's largest set, and 255 for a hue, grey or
  viridis palette, as R says; `nil` for a continuous palette. A discrete palette converted to a
  continuous one is a gradient through this many of its values.

  ## Examples

      iex> Scales.Palette.nlevels({:brewer, %{palette: "Paired", direction: 1}})
      12

      iex> Scales.Palette.nlevels({:gradient, ["#132B43", "#56B1F7"]})
      nil
  """
  @spec nlevels(t()) :: non_neg_integer() | nil
  def nlevels({:shape, fill}) when is_map_key(@shapes, fill),
    do: length(Map.fetch!(@shapes, fill))

  def nlevels(:linetype), do: length(@line_types)
  def nlevels({:manual, values}) when is_list(values), do: length(values)

  def nlevels({:brewer, %{palette: name}}) when name in @brewer_names,
    do: Map.fetch!(@brewer_largest, name)

  def nlevels({kind, _parameters}) when kind in [:hue, :gray, :viridis], do: @many_levels
  def nlevels(:identity), do: nil
  def nlevels({kind, _parameters}) when kind in [:rescale, :area, :abs_area, :gradient], do: nil

  @doc """
  The palette scales names `name`, R's `get_palette()` for scales' own names, in any case: each
  ColorBrewer palette as `pal_brewer()` gives it (`brewer_palettes/1`), each viridis option as
  `pal_viridis()` does (`Scales.ColorOperations.viridis_options/0`), `"grey"`, `pal_grey()`, and
  `"hue"`, `pal_hue()`, each with R's defaults. Any other name raises `ArgumentError` listing
  these; R also knows grDevices' palettes by name (`"Okabe-Ito"`, `"Blues 3"`), which are left
  out.

  ## Examples

      iex> Scales.Palette.named("set1")
      {:brewer, %{palette: "Set1", direction: 1}}

      iex> Scales.Palette.named("Grey")
      {:gray, {0.2, 0.8}}
  """
  @spec named(String.t()) :: t()
  def named(name) when is_binary(name) do
    case Map.fetch(@named, String.downcase(name)) do
      {:ok, palette} ->
        palette

      :error ->
        raise ArgumentError,
              "scales names no palette #{inspect(name)}; its names, in any case, are " <>
                @known_names
    end
  end

  @doc """
  The names of ColorBrewer's palettes of `type`, sequential (`:seq`), diverging (`:div`) or
  qualitative (`:qual`), as R spells them, in the order R's `pal_brewer()` numbers them, so its
  `pal_brewer("qual", 5)` is `"Pastel2"`.

  ## Examples

      iex> Scales.Palette.brewer_palettes(:qual)
      ["Accent", "Dark2", "Paired", "Pastel1", "Pastel2", "Set1", "Set2", "Set3"]
  """
  @spec brewer_palettes(brewer_type()) :: [String.t(), ...]
  def brewer_palettes(type) when type in [:seq, :div, :qual],
    do: Map.fetch!(@brewer_palettes, type)

  @doc """
  `count` numbers spread evenly from `low` to `high`, R's `seq(low, high, length.out = count)`:
  the ends exact, each number between them `low` plus its index times the step, in R's order of
  operations, so the fourth of seven from 0.1 to 1 is `0.54999999999999993`, not `0.55`.

  ## Examples

      iex> Scales.Palette.spread({0.0, 1.0}, 5)
      [0.0, 0.25, 0.5, 0.75, 1.0]

      iex> Scales.Palette.spread({2, 6}, 1)
      [2]
  """
  @spec spread({number(), number()}, non_neg_integer()) :: [number()]
  def spread({_low, _high}, 0), do: []
  def spread({low, _high}, 1), do: [low]
  def spread({low, high}, 2), do: [low, high]

  def spread({low, high}, count) when count > 2 do
    step = (high - low) / (count - 1)
    between = Enum.map(1..(count - 2), fn index -> low + index * step end)
    Enum.concat([[low], between, [high]])
  end

  # Each place through `function`, a `nil` left `nil`, as R's arithmetic leaves `NA`.
  defp each_place(places, function) do
    Enum.map(places, fn
      nil -> nil
      place when is_number(place) -> function.(place)
    end)
  end

  # The first `count` of `values`, `nil` for each past their end, as R's `values[seq_len(n)]`
  # gives `NA`.
  defp padded(values, count) do
    values
    |> Stream.concat(Stream.repeatedly(fn -> nil end))
    |> Enum.take(count)
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
