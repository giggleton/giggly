defmodule Giggly.Scale do
  @moduledoc false

  # Scales: what kind of scale a column's values need, the range or levels those values span once
  # trained, and where each value sits on an axis, or what it becomes as another aesthetic, such
  # as alpha, through the scale's palette (`Giggly.Scale.Palette`).
  #
  # A scale works on plain values, never on frames or plots: the assembly pulls a column and hands
  # its values here, so this namespace depends on nothing else in Giggly and could stand alone, as
  # R's `scales` package does beside ggplot2.
  #
  # ## Kinds
  #
  # A column's type decides its scale's kind, as ggplot2's `scale_type()` does:
  #
  #   * `:integer` and `:float` get a continuous scale (`Giggly.Scale.Continuous`), and so does an
  #     all-`nil` (`:null`) column, matching ggplot2's continuous fallback;
  #   * `:string`, `:boolean`, `:atom` and `:category`, a factor's column, get a discrete scale
  #     (`Giggly.Scale.Discrete`);
  #   * `:date` gets a date scale, a continuous scale of the days since 1970-01-01 through the
  #     date transformation, as ggplot2's `scale_type()` gives a `Date` `"date"`; on an aesthetic
  #     other than position it gets none yet;
  #   * times, datetimes and `:term` get none yet.
  #
  # ## Transformation
  #
  # A continuous scale records, by name, the transformation its values are put through before it
  # trains on them (`Giggly.Scale.Transform`), so it trains, and maps, in transformed space. A
  # continuous scale of numbers records the identity, as ggplot2's continuous scales default to
  # `transform = "identity"`: an untransformed axis says so rather than leaving it out. A date
  # scale records the date transformation, and a plot's scale may name log10, square root,
  # reverse or reciprocal. Its limits, breaks and minor breaks are given in data units and put
  # through the transformation here; its labels are written from the breaks turned back. A
  # discrete scale has no transformation, as in ggplot2.
  #
  # ## Training and mapping
  #
  # Training follows R's `scales` package. A continuous scale's range spans the finite numbers it
  # sees; `nil` and the non-finite floats are skipped. A discrete scale's levels are the distinct
  # values it sees, sorted with `nil` last and otherwise in Erlang term order, so strings sort by
  # their bytes. A position scale's palette is the identity: mapping leaves a continuous value as
  # it is, or `nil` outside the scale's limits, and puts a discrete value at its level's position,
  # counting from 1, as ggplot2 does before the coordinate system rescales anything. Any other
  # aesthetic's scale maps through its palette: a continuous value's place in the range, from 0 to
  # 1 (R's `rescale()`), onto the palette's range, and a discrete value to its level's share of the
  # palette's spread.
  #
  # ## Options
  #
  # A continuous scale carries the options a plot gives it (`Giggly.Scale.Continuous`): its
  # limits replace its trained range end by end, its expansion widens them, and its breaks, minor
  # breaks and labels replace its transformation's, or `:none` leaves them out.
  #
  # ## Aesthetics other than position
  #
  # `alpha`, `color` and `fill` so far (`non_position_aesthetics/0`), each scale ggplot2's default
  # for its aesthetic. Alpha's maps a continuous column onto 0.1 to 1, `scale_alpha_continuous()`,
  # and spreads a discrete one from 0.1 to 1, `scale_alpha_ordinal()`, which ggplot2's
  # `scale_alpha_discrete()` uses with a warning that Giggly, building a plot without side effects,
  # does not give. Colour's and fill's give a discrete column `pal_hue()`'s colours, as
  # `scale_colour_discrete()` falls back to it, and a continuous one the gradient from `#132B43` to
  # `#56B1F7`, `scale_colour_continuous()`'s, blended in L*a*b* (`Giggly.Scale.Palette`); a missing
  # value maps to the scale's `na_value`, grey50 for a colour, `nil`, R's `NA`, for alpha. Each
  # names the guide that draws it, as ggplot2's scales do: a colour bar for a continuous colour or
  # fill, a legend for the rest.

  # Values in, values out: a scale depends on nothing but the colour operations, which give the hue
  # palette its colours, as R's `scales` depends on farver, and R's `as.character()`, which writes
  # a discrete level, so it stays extractable. It exports the continuous scale's struct, which
  # `Giggly.Plot` writes with a user's options and `Giggly.panel_scales/2` returns.
  use Boundary, deps: [Giggly.AsCharacter, Giggly.ColorOperations], exports: [Continuous]

  alias Giggly.Scale.{Continuous, Discrete, Labels, Palette, Transform}

  @typedoc "A trained position scale."
  @type t :: Continuous.t() | Discrete.t()

  @typedoc "A break on an axis: its position and its label, `:none` where the axis has no labels."
  @type break :: {number(), String.t() | :none}

  @typedoc "Which kind of scale a column needs, or `:none` when no scale can place it yet."
  @type kind :: :continuous | :discrete | :date | :none

  # The aesthetics other than position that a scale maps, and those of them that are colours.
  @non_position_aesthetics [:alpha, :color, :fill]
  @color_aesthetics [:color, :fill]

  @continuous_dtypes [:integer, :float, :null]
  @discrete_dtypes [:string, :boolean, :atom, :category]

  # ggplot2's default expansion for a discrete scale, `expansion(add = 0.6)`: at each end, a
  # multiple of the width and a constant. A continuous scale's, `expansion(mult = 0.05)`, is its
  # struct's default `expand`.
  @discrete_expansion [mult: {0, 0}, add: {0.6, 0.6}]

  # R's `zero_range()` tolerance: 1000 times the double-precision machine epsilon.
  @zero_range_tolerance 1000 * 2.220446049250313e-16

  # The kind of scale a column of type `dtype` (a `Giggly.DataFrame` type) needs.
  @doc false
  @spec kind(atom()) :: kind()
  def kind(dtype) when dtype in @continuous_dtypes, do: :continuous
  def kind(dtype) when dtype in @discrete_dtypes, do: :discrete
  def kind(:date), do: :date
  def kind(dtype) when is_atom(dtype), do: :none

  # The kind of scale a column of type `dtype` needs on `aesthetic`: on a position aesthetic, its
  # `kind/1`; on another, the same but for a date, whose scale on any aesthetic but position
  # (ggplot2's `scale_alpha_date()` and `scale_colour_date()`) has not arrived.
  @doc false
  @spec kind(atom(), atom()) :: kind()
  def kind(:date, aesthetic) when aesthetic in @non_position_aesthetics, do: :none
  def kind(dtype, _aesthetic), do: kind(dtype)

  # ggplot2's default range for alpha, 0.1 to 1, which leaves every value visible.
  @alpha_range {0.1, 1.0}

  # ggplot2's default discrete colour palette, `pal_hue()`'s: hues from 15 degrees round the
  # circle, chroma 100 and luminance 65.
  @hue_palette {:hue, %{hue: {15, 375}, chroma: 100, luminance: 65}}

  # ggplot2's default continuous colour palette, `pal_seq_gradient("#132B43", "#56B1F7")`.
  @gradient_palette {:gradient, {"#132B43", "#56B1F7"}}

  # ggplot2's colour for a missing value, grey50.
  @color_na_value "#7F7F7F"

  # An untrained position scale of the given kind, its palette the identity and its guide an axis,
  # as ggplot2's position scales are drawn by `guide_axis()`; a continuous one records the identity
  # transformation, and a date scale, a continuous one, the date transformation.
  @doc false
  @spec new(:continuous | :discrete | :date) :: t()
  def new(:continuous), do: %Continuous{}
  def new(:date), do: %Continuous{transform: :date}

  def new(:discrete) do
    %Discrete{
      levels: [],
      continuous_range: :none,
      palette: :identity,
      na_value: nil,
      guide: :axis
    }
  end

  # An untrained scale of the given kind for `aesthetic`, one of `non_position_aesthetics/0`, with
  # ggplot2's default palette, value for a missing value and guide for it: a colour bar for a
  # continuous colour or fill, and a legend for the rest.
  @doc false
  @spec new(:continuous | :discrete, atom()) :: t()
  def new(:continuous, :alpha),
    do: %Continuous{palette: {:rescale, @alpha_range}, guide: :legend}

  def new(:continuous, aesthetic) when aesthetic in @color_aesthetics,
    do: %Continuous{palette: @gradient_palette, na_value: @color_na_value, guide: :colorbar}

  def new(:discrete, :alpha) do
    %Discrete{
      levels: [],
      continuous_range: :none,
      palette: {:sequence, @alpha_range},
      na_value: nil,
      guide: :legend
    }
  end

  def new(:discrete, aesthetic) when aesthetic in @color_aesthetics do
    %Discrete{
      levels: [],
      continuous_range: :none,
      palette: @hue_palette,
      na_value: @color_na_value,
      guide: :legend
    }
  end

  # The kind a scale is, as `kind/1` names the kind a column needs: a discrete scale, a date scale,
  # or another continuous scale.
  @doc false
  @spec kind_of(t()) :: :continuous | :discrete | :date
  def kind_of(%Discrete{}), do: :discrete
  def kind_of(%Continuous{transform: :date}), do: :date
  def kind_of(%Continuous{}), do: :continuous

  # The aesthetics other than position that a scale maps, as ggplot2 adds a default scale for each
  # one a layer maps.
  @doc false
  @spec non_position_aesthetics() :: [atom()]
  def non_position_aesthetics, do: @non_position_aesthetics

  # The values in the space the scale trains and maps in: put through a continuous scale's
  # transformation, and as given to a discrete scale, which has none.
  @doc false
  @spec transform(t(), list()) :: list()
  def transform(%Continuous{} = scale, values), do: Continuous.transform(scale, values)
  def transform(%Discrete{}, values), do: values

  # The scale widened to cover `values` as a layer's table gives them: a continuous scale's range,
  # and a discrete scale's levels, numbers among them, as ggplot2 trains a factor's levels.
  @doc false
  @spec train(t(), list()) :: t()
  def train(%Continuous{} = scale, values), do: Continuous.train(scale, values)
  def train(%Discrete{} = scale, values), do: Discrete.train(scale, values)

  # Whether `scale` is discrete, its legend's keys its levels, rather than continuous.
  @doc false
  @spec discrete?(t()) :: boolean()
  def discrete?(%Discrete{}), do: true
  def discrete?(%Continuous{}), do: false

  # The scale widened to cover positions, such as a bar's edges once its levels are mapped: a
  # continuous scale's range, as `train/2` widens it, and a discrete scale's continuous range, its
  # levels left alone, as ggplot2's discrete position scale trains `range_c`.
  @doc false
  @spec train_positions(t(), list()) :: t()
  def train_positions(%Continuous{} = scale, values), do: Continuous.train(scale, values)
  def train_positions(%Discrete{} = scale, values), do: Discrete.train_positions(scale, values)

  # The scale as ggplot2 resets it before training it again on the positioned marks: a continuous
  # scale forgets its range, and a discrete one its continuous range, keeping its levels, since
  # their values can no longer be recovered from positions.
  @doc false
  @spec reset(t()) :: t()
  def reset(%Continuous{} = scale), do: %{scale | range: :none}
  def reset(%Discrete{} = scale), do: %{scale | continuous_range: :none}

  # Each value's position on the scale's axis: a continuous value unchanged, or `nil` outside the
  # scale's limits, a discrete one at its level's position counting from 1.
  @doc false
  @spec map(t(), list()) :: list()
  def map(%Continuous{} = scale, values), do: Continuous.map(scale, values)
  def map(%Discrete{} = scale, values), do: Discrete.map(scale, values)

  # Each position, `nil` where a continuous scale's limits leave it out, `:infinity` and
  # `:neg_infinity` kept: ggplot2's second mapping of the positions, once they are final, which
  # removes a bar the limits cut. A discrete scale's positions are returned as given.
  @doc false
  @spec censor(t(), list()) :: list()
  def censor(%Continuous{} = scale, values), do: Continuous.censor(scale, values)
  def censor(%Discrete{}, values), do: values

  # The extent of the axis in positions, widened as ggplot2 widens it before drawing: a continuous
  # scale's limits, each end its `limits`' or else its range's, by its `expand`, 5% of their width
  # at each end unless it says otherwise; and discrete levels, at positions 1 to n, by 0.6, then
  # reaching further where its continuous range does, which is not widened: a bar wider than its
  # level's slot widens the axis, as ggplot2's `expand_limits_discrete()` takes the range of both.
  # Limits of zero width are widened as though their width were 1, as R's `expand_range()` does, so
  # one value, zero included, spans 0.05 either side of it; a continuous scale that has seen no data
  # spans 0 to 1 before it is widened, ggplot2's default for an empty axis, unless its limits give
  # both ends. It is ggplot2's `dimension()`, and the coordinate system maps it onto the panel.
  #
  # Ends that differ only by rounding error, relative to their size, count as one value.
  #
  # An extent still zero wide once widened, by R's `zero_range()`, is its middle, both ends equal:
  # a single value from about 4.5e11 up, where 0.05 either side is rounding error beside its size.
  # ggplot2 keeps such an extent's ends and `scales::rescale()` draws every value on it at the
  # middle of the panel; ends that are equal are how the coordinate system is told to.
  @doc false
  @spec dimension(t()) :: {number(), number()}
  def dimension(%Continuous{expand: expansion} = scale) do
    case limits(scale) do
      :none ->
        expand({0, 1}, expansion)

      limits ->
        limits
        |> expand(expansion)
        |> collapse_zero_width()
    end
  end

  def dimension(%Discrete{levels: levels, continuous_range: :none}),
    do: expand({1, length(levels)}, @discrete_expansion)

  def dimension(%Discrete{levels: levels, continuous_range: {range_low, range_high}}) do
    {low, high} = expand({1, length(levels)}, @discrete_expansion)
    {min(low, range_low), max(high, range_high)}
  end

  # The breaks an axis showing `extent` of the scale draws, each its position and its label:
  # ggplot2's `get_breaks()` and `get_labels()` as its view scale calls them.
  #
  # A continuous scale's breaks are those its `breaks` gives, in data units and in the order
  # given, put through its transformation, or by default its transformation's
  # (`Giggly.Scale.Transform`), found on the extent squished into the transformation's domain and
  # ascending in data units, so a reversing transformation's descend; either way those inside
  # `extent` are kept (ggplot2 computes breaks on the widened extent and drops the rest), a break
  # exactly at an end included, so a given break beyond the limits but inside the widened axis is
  # drawn, and one outside the domain is not. A scale with no limits yet has none by default, and
  # an extent of zero width one, at its end, as in ggplot2. `breaks: :none` gives none. Each is
  # labelled by `labels/4`.
  #
  # A discrete scale has a break at each level, whatever the extent, labelled as
  # `Giggly.Scale.Labels` writes a level.
  @doc false
  @spec breaks(t(), {float(), float()}) :: [break()]
  def breaks(%Continuous{breaks: :none}, _extent), do: []

  def breaks(%Continuous{breaks: given, transform: transform} = scale, extent)
      when is_list(given) do
    {positions, indexes} =
      transform
      |> Transform.transform(given)
      |> Enum.with_index()
      |> Enum.filter(fn {position, _index} -> placed_inside?(position, extent) end)
      |> Enum.unzip()

    Enum.zip(positions, labels(scale, positions, indexes, extent))
  end

  def breaks(%Continuous{breaks: :default} = scale, extent) do
    positions = default_breaks(scale, limits(scale), extent)
    Enum.zip(positions, labels(scale, positions, :default, extent))
  end

  def breaks(%Discrete{levels: levels}, _extent) do
    levels
    |> Labels.levels()
    |> Enum.with_index(1)
    |> Enum.map(fn {label, position} -> {position, label} end)
  end

  # The breaks a legend of the scale shows, in its transformation's order, each the value in the
  # data and its label: ggplot2's `get_breaks()` and `get_labels()` on the scale's limits, its
  # trained range or levels, not an axis's widened extent. A continuous scale's are its
  # transformation's breaks inside the range, taken as floats as R's limits are doubles, one at
  # its low end when it has zero width, and none when untrained; a discrete scale's are its
  # levels, `nil` last and labelled `NA`, as ggplot2's legend keeps `NA`.
  @doc false
  @spec legend_breaks(t()) :: [{term(), String.t()}]
  def legend_breaks(%Continuous{range: :none}), do: []

  def legend_breaks(%Continuous{range: {low, high}} = scale),
    do: breaks(scale, {low / 1, high / 1})

  def legend_breaks(%Discrete{levels: levels}),
    do: Enum.zip(levels, Labels.levels(levels))

  # `count` values spread evenly over the trained range of a continuous scale, from its low end to
  # its high, as R's `seq(low, high, length.out = count)` spreads them (`Giggly.Scale.Palette`):
  # the values ggplot2's colour bar takes its colours at (`extract_decor()`).
  @doc false
  @spec samples(Continuous.t(), pos_integer()) :: [number()]
  def samples(%Continuous{range: {low, high}}, count),
    do: Palette.discrete({:sequence, {low, high}}, count)

  # Each of `values`' place in the trained range of a continuous scale, from 0 at its low end to 1
  # at its high (`rescale/3`), as ggplot2's colour bar places its ticks and its colours.
  @doc false
  @spec places(Continuous.t(), [number()]) :: [float()]
  def places(%Continuous{range: {_low, _high} = range}, values),
    do: Enum.map(values, fn value -> rescale(value, range, {0, 1}) end)

  # The minor breaks an axis showing `extent` of the scale draws between `breaks`, the breaks
  # `breaks/2` gives on that extent: ggplot2's `get_breaks_minor()` as its view scale calls it,
  # less the breaks themselves, which ggplot2's grid leaves out of its minor lines.
  #
  # A continuous scale takes those its `minor_breaks` gives, in data units, put through its
  # transformation, or by default its transformation's (`Giggly.Scale.Transform`), and keeps
  # those inside `extent`, its ends included; `:none` gives none. By default they fall midway
  # between breaks in transformed space, and between the outermost breaks and the extent's ends,
  # and an axis with fewer than two breaks has none.
  #
  # A discrete scale has none, as in ggplot2.
  @doc false
  @spec minor_breaks(t(), [break()], {float(), float()}) :: [float()]
  def minor_breaks(%Continuous{minor_breaks: :none}, _breaks, _extent), do: []

  def minor_breaks(%Continuous{} = scale, breaks, extent) do
    positions = Enum.map(breaks, fn {position, _label} -> position end)

    scale
    |> candidate_minor_breaks(positions, extent)
    |> Enum.filter(fn position -> placed_inside?(position, extent) end)
    |> Enum.reject(fn position -> position in positions end)
  end

  def minor_breaks(%Discrete{}, _breaks, _extent), do: []

  defp candidate_minor_breaks(
         %Continuous{minor_breaks: given, transform: transform},
         _positions,
         _extent
       )
       when is_list(given),
       do: Transform.transform(transform, given)

  defp candidate_minor_breaks(%Continuous{transform: transform}, positions, extent),
    do: Transform.minor_breaks(transform, positions, extent)

  # A continuous scale's limits as ggplot2's `get_limits()` gives them, in transformed space: each
  # end its `limits`', or, where that is `nil`, its trained range's; `:none` where an end has
  # neither, before the scale has seen any data.
  defp limits(%Continuous{range: range} = scale) do
    case {Continuous.limits(scale), range} do
      {{low, high}, _range} when is_number(low) and is_number(high) -> {low, high}
      {_limits, :none} -> :none
      {{low, high}, {range_low, range_high}} -> {low || range_low, high || range_high}
    end
  end

  # A continuous scale's default breaks on `extent`: none before its limits are known; otherwise,
  # the extent squished into its transformation's domain, one at its low end where it has zero
  # width, and the transformation's breaks on it, those inside the extent itself kept.
  defp default_breaks(%Continuous{}, :none, _extent), do: []

  defp default_breaks(%Continuous{transform: transform}, _limits, extent) do
    {low, high} = squished = Transform.squish(transform, extent)

    if zero_range?(low, high) do
      [low]
    else
      transform
      |> Transform.breaks(squished)
      |> Enum.filter(fn position -> placed_inside?(position, extent) end)
    end
  end

  # The labels of the breaks at `positions`, which are the given breaks at `indexes` in the order
  # given, or else the default breaks (`:default`): the scale's `labels` at those indexes, what its
  # function returns for the positions, `:none` for each where it has none, or its
  # transformation's (`Transform.format/3`). A function must return a string for each break, or
  # the plot cannot be drawn. A function is handed the breaks in data units, turned back from
  # their positions, as ggplot2 hands them.
  defp labels(%Continuous{labels: :none}, positions, _indexes, _extent),
    do: List.duplicate(:none, length(positions))

  defp labels(%Continuous{labels: given}, _positions, indexes, _extent)
       when is_list(given) and is_list(indexes),
       do: Enum.map(indexes, fn index -> Enum.at(given, index) end)

  defp labels(%Continuous{labels: labeller, transform: transform}, positions, _indexes, _extent)
       when is_function(labeller, 1) do
    breaks = Transform.inverse(transform, positions)
    labelled = labeller.(breaks)

    if is_list(labelled) and length(labelled) == length(positions) and
         Enum.all?(labelled, &is_binary/1) do
      labelled
    else
      raise ArgumentError,
            "a scale's labels function must return a string for each of the breaks " <>
              "#{inspect(breaks)}, got: #{inspect(labelled)}"
    end
  end

  defp labels(%Continuous{labels: :default, transform: transform}, positions, _indexes, extent),
    do: Transform.format(transform, positions, extent)

  defp inside?(position, {low, high}), do: position >= low and position <= high

  # Whether a position is a number inside `extent`: a value a transformation could not place, or
  # placed at an infinity, is not.
  defp placed_inside?(position, extent), do: is_number(position) and inside?(position, extent)

  # Widens each end by a multiple of the width plus a constant, `expansion` giving each end's: R's
  # `expand_range4()`, which widens limits of zero width as though their width were 1.
  defp expand({low, high}, mult: {mult_low, mult_high}, add: {add_low, add_high}) do
    width = if zero_range?(low, high), do: 1, else: high - low
    {low - (width * mult_low + add_low), high + (width * mult_high + add_high)}
  end

  # An extent R's `zero_range()` still calls zero wide, as its middle with both ends equal.
  defp collapse_zero_width({low, high} = extent) do
    if zero_range?(low, high) do
      middle = (low + high) / 2
      {middle, middle}
    else
      extent
    end
  end

  # `value` moved from the range `from` to the range `to`, linearly: R's `scales::rescale()`,
  # `(value - from_low) / (from_high - from_low) * (to_high - to_low) + to_low`, in that order of
  # operations. A `from` of zero width, by R's `zero_range()`, puts every value at the middle of
  # `to`, as R does, so a column of one value maps to the middle of its palette.
  @doc false
  @spec rescale(number(), {number(), number()}, {number(), number()}) :: float()
  def rescale(value, {from_low, from_high}, {to_low, to_high}) do
    if zero_range?(from_low, from_high) do
      (to_low + to_high) / 2
    else
      (value - from_low) / (from_high - from_low) * (to_high - to_low) + to_low
    end
  end

  # R's `zero_range()`: equal ends, or ends so close, relative to the smaller, that their
  # difference is rounding error. `dimension/1` and `breaks/2` both ask it, which is why
  # `breaks/2` lives here in the root, and so does `Giggly.Resolution`, so the rule has one home.
  @doc false
  @spec zero_range?(number(), number()) :: boolean()
  def zero_range?(low, high) when low == high, do: true

  def zero_range?(low, high) do
    smaller = min(abs(low), abs(high))
    smaller != 0 and abs((low - high) / smaller) < @zero_range_tolerance
  end

  # The key that orders discrete values: `nil` after every present value, which compare in Erlang
  # term order, so strings sort by their bytes and structs such as dates by their fields, not
  # chronologically. Grouping orders its combinations by the same key, so group ids and axis
  # positions agree.
  @doc false
  @spec level_key(term()) :: {0, term()} | {1, nil}
  def level_key(nil), do: {1, nil}
  def level_key(value), do: {0, value}
end
