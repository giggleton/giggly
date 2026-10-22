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
  #     other than position it gets none yet. A plot's continuous scale through the identity takes
  #     one too, placing each date at its days, as R stores a date (`takes?/2`);
  #   * times, datetimes, lists and `:term` get none yet.
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
  # aesthetic's scale maps through its palette: a continuous value's place in the scale's limits,
  # from 0 to 1 (R's `rescale()`), onto the palette's range, and a discrete value to its level's
  # share of the palette's spread.
  #
  # ## Options
  #
  # A continuous scale carries the options a plot gives it (`Giggly.Scale.Continuous`): its
  # limits replace its trained range end by end, its expansion widens them, and its breaks, minor
  # breaks and labels replace its transformation's, or `:none` leaves them out. A date scale's
  # breaks and minor breaks may be a width, `{:width, [week: 1]}`, a break every week, and its
  # labels a format, `{:format, "%b %d"}`, each date written in it by `Calendar.strftime/3`.
  #
  # A discrete scale carries them too (`Giggly.Scale.Discrete`): its limits replace its levels,
  # choosing the values it shows and their order, its breaks the values an axis marks among them,
  # its labels their text, given as a list, by value in a map, or by a function, and its expansion
  # its room beside the first and last.
  #
  # ## Aesthetics other than position
  #
  # `alpha`, `color`, `fill`, `linetype`, `linewidth`, `shape` and `size` so far
  # (`non_position_aesthetics/0`), each scale, unless the plot gives one, ggplot2's default for its
  # aesthetic. Alpha's maps a continuous
  # column onto 0.1 to 1, `scale_alpha_continuous()`, and spreads a discrete one from 0.1 to 1,
  # `scale_alpha_ordinal()`, which ggplot2's `scale_alpha_discrete()` uses with a warning that
  # Giggly, building a plot without side effects, does not give. Size's maps a continuous column
  # onto sizes from 1 to 6 by area, `scale_size_continuous()`, and spreads a discrete one from 2
  # to 6 by area, `scale_size_ordinal()`, which `scale_size_discrete()` uses with a warning, which
  # it leaves out too. Colour's and fill's give a discrete column `pal_hue()`'s colours, as
  # `scale_colour_discrete()` falls back to it, and a continuous one the gradient from `#132B43`
  # to `#56B1F7`, `scale_colour_continuous()`'s, blended in L*a*b* (`Giggly.Scale.Palette`).
  # Shape's gives a discrete column `pal_shape()`'s six solid shapes, as `scale_shape()` does, and
  # line type's `pal_linetype()`'s 13 line types, as `scale_linetype()` does; a shape or line type
  # scale is always discrete (`discrete_only?/1`): neither has an order, so R has no continuous
  # scale of either and aborts for a continuous column. Line width's maps a continuous column onto
  # widths from 1 to 6, `scale_linewidth_continuous()`, and spreads a discrete one from 2 to 6,
  # `scale_linewidth_ordinal()`, which `scale_linewidth_discrete()` uses with a warning Giggly
  # leaves out. A plot's scale may carry another palette: manual, grey, another hue range or
  # gradient, open shapes. A continuous value's place runs over the scale's limits, or about its
  # midpoint (R's
  # `rescale_mid()`), or at its share of their high end (R's `rescale_max()`), as the scale's
  # `rescaler` says, and one outside them is censored, as ggplot2's `oob = censor`; a missing or
  # censored value maps to the scale's `na_value`, grey50 for a colour, `nil`, R's `NA`, for alpha,
  # line type, line width, shape and size. Each names the guide that draws it, as ggplot2's scales
  # do: a colour bar for a continuous colour or fill, a legend for the rest, whose breaks and labels
  # are the scale's on its limits.

  # Values in, values out: a scale depends on nothing but the colour operations, which give the hue
  # palette its colours, as R's `scales` depends on farver, and R's `as.character()`, which writes
  # a discrete level, so it stays extractable. It exports the two kinds' structs, which
  # `Giggly.Plot` writes with a user's options and `Giggly.panel_scales/2` returns.
  use Boundary,
    deps: [Giggly.AsCharacter, Giggly.ColorOperations],
    exports: [Continuous, Discrete]

  alias Giggly.Scale.{Continuous, DateBreaks, Discrete, Labels, Palette, Transform}

  @typedoc "A trained position scale."
  @type t :: Continuous.t() | Discrete.t()

  @typedoc "A break on an axis: its position and its label, `:none` where the axis has no labels."
  @type break :: {number(), String.t() | :none}

  @typedoc "Which kind of scale a column needs, or `:none` when no scale can place it yet."
  @type kind :: :continuous | :discrete | :date | :none

  # The aesthetics other than position that a scale maps, those of them that are colours, and those
  # whose every scale is discrete.
  @non_position_aesthetics [:alpha, :color, :fill, :linetype, :linewidth, :shape, :size]
  @color_aesthetics [:color, :fill]
  @discrete_aesthetics [:linetype, :shape]

  @continuous_dtypes [:integer, :float, :null]
  @discrete_dtypes [:string, :boolean, :atom, :category]

  # R's `zero_range()` tolerance: 1000 times the double-precision machine epsilon.
  @zero_range_tolerance 1000 * 2.220446049250313e-16

  # The kind of scale a column of type `dtype` (a `Giggly.DataFrame` type) needs.
  @doc false
  @spec kind(atom() | {:list, term()}) :: kind()
  def kind(dtype) when dtype in @continuous_dtypes, do: :continuous
  def kind(dtype) when dtype in @discrete_dtypes, do: :discrete
  def kind(:date), do: :date
  def kind(dtype) when is_atom(dtype), do: :none
  def kind({:list, _values_dtype}), do: :none

  # The kind of scale a column of type `dtype` needs on `aesthetic`: on a position aesthetic, its
  # `kind/1`; on another, the same but for a date, whose scale on any aesthetic but position
  # (ggplot2's `scale_alpha_date()` and `scale_colour_date()`) has not arrived.
  @doc false
  @spec kind(atom() | {:list, term()}, atom()) :: kind()
  def kind(:date, aesthetic) when aesthetic in @non_position_aesthetics, do: :none
  def kind(dtype, _aesthetic), do: kind(dtype)

  # ggplot2's default range for alpha, 0.1 to 1, which leaves every value visible.
  @alpha_range {0.1, 1.0}

  # ggplot2's default sizes, in millimetres: 1 to 6 by area for a continuous scale, `pal_area()`'s,
  # and 2 to 6 by area for a discrete one, its ordinal scale's `sqrt(seq(4, 36))`.
  @continuous_size_range {1.0, 6.0}
  @discrete_size_range {2.0, 6.0}

  # ggplot2's default line widths, in millimetres: 1 to 6 for a continuous scale, `pal_rescale()`'s,
  # and 2 to 6 for a discrete one, its ordinal scale's `seq(2, 6)`.
  @continuous_linewidth_range {1.0, 6.0}
  @discrete_linewidth_range {2.0, 6.0}

  # ggplot2's default discrete colour palette, `pal_hue()`'s: hues from 15 degrees round the
  # circle, chroma 100 and luminance 65, in order.
  @hue_palette {:hue, %{hue: {15.0, 375.0}, chroma: 100.0, luminance: 65.0, direction: 1}}

  # ggplot2's default shape palette, `pal_shape()`'s solid shapes.
  @shape_palette {:shape, :solid}

  # ggplot2's default continuous colour palette, `pal_seq_gradient("#132B43", "#56B1F7")`.
  @gradient_palette {:gradient, ["#132B43", "#56B1F7"]}

  # ggplot2's colour for a missing value, grey50.
  @color_na_value "#7F7F7F"

  # An untrained position scale of the given kind, its palette the identity and its guide an axis,
  # as ggplot2's position scales are drawn by `guide_axis()`; a continuous one records the identity
  # transformation, and a date scale, a continuous one, the date transformation.
  @doc false
  @spec new(:continuous | :discrete | :date) :: t()
  def new(:continuous), do: %Continuous{}
  def new(:date), do: %Continuous{transform: :date}
  def new(:discrete), do: %Discrete{}

  # An untrained scale of the given kind for `aesthetic`, one of `non_position_aesthetics/0`, with
  # ggplot2's default palette, value for a missing value and guide for it: a colour bar for a
  # continuous colour or fill, and a legend for the rest. A shape's and a line type's are discrete
  # alone (`discrete_only?/1`).
  @doc false
  @spec new(:continuous | :discrete, atom()) :: t()
  def new(:continuous, :alpha),
    do: %Continuous{palette: {:rescale, @alpha_range}, guide: :legend}

  def new(:continuous, aesthetic) when aesthetic in @color_aesthetics,
    do: %Continuous{palette: @gradient_palette, na_value: @color_na_value, guide: :colorbar}

  def new(:continuous, :size),
    do: %Continuous{palette: {:area, @continuous_size_range}, guide: :legend}

  def new(:continuous, :linewidth),
    do: %Continuous{palette: {:rescale, @continuous_linewidth_range}, guide: :legend}

  def new(:discrete, :alpha), do: %Discrete{palette: {:sequence, @alpha_range}, guide: :legend}

  def new(:discrete, :size),
    do: %Discrete{palette: {:area_sequence, @discrete_size_range}, guide: :legend}

  def new(:discrete, :linewidth),
    do: %Discrete{palette: {:sequence, @discrete_linewidth_range}, guide: :legend}

  def new(:discrete, aesthetic) when aesthetic in @color_aesthetics,
    do: %Discrete{palette: @hue_palette, na_value: @color_na_value, guide: :legend}

  def new(:discrete, :shape), do: %Discrete{palette: @shape_palette, guide: :legend}
  def new(:discrete, :linetype), do: %Discrete{palette: :linetype, guide: :legend}

  # The kind a scale is, as `kind/1` names the kind a column needs: a discrete scale, a date scale,
  # or another continuous scale.
  @doc false
  @spec kind_of(t()) :: :continuous | :discrete | :date
  def kind_of(%Discrete{}), do: :discrete
  def kind_of(%Continuous{transform: :date}), do: :date
  def kind_of(%Continuous{}), do: :continuous

  # Whether `scale` takes a column that needs a scale of `kind` (`kind/1`): a scale of that kind
  # does, and so does a continuous scale through the identity a date's, placing each date at its
  # days since 1970-01-01, as R stores a date and its continuous scale places one; through another
  # transformation a date is refused, where R fails.
  @doc false
  @spec takes?(t(), kind()) :: boolean()
  def takes?(%Continuous{transform: :identity}, :date), do: true
  def takes?(scale, kind), do: kind_of(scale) == kind

  # The aesthetics other than position that a scale maps, as ggplot2 adds a default scale for each
  # one a layer maps.
  @doc false
  @spec non_position_aesthetics() :: [atom()]
  def non_position_aesthetics, do: @non_position_aesthetics

  # Whether every scale of `aesthetic` is discrete, as a shape's and a line type's are: neither
  # has an order, so ggplot2's `scale_shape_continuous()` and `scale_linetype_continuous()` abort,
  # and a continuous column, or a date's, cannot be mapped to one.
  @doc false
  @spec discrete_only?(atom()) :: boolean()
  def discrete_only?(aesthetic), do: aesthetic in @discrete_aesthetics

  # The values in the space the scale trains and maps in: put through a continuous scale's
  # transformation, and as given to a discrete scale, which has none.
  @doc false
  @spec transform(t(), list()) :: list()
  def transform(%Continuous{} = scale, values), do: Continuous.transform(scale, values)
  def transform(%Discrete{}, values), do: values

  # The scale widened to cover `values` as a layer's table gives them, `levels` the levels of the
  # factor they are values of, or `:none`: a continuous scale's range, and a discrete scale's
  # levels, numbers among them, as R's `scales::discrete_range()` merges a factor's levels and
  # other values into a range (`Giggly.Scale.Discrete`'s `levels` and `factor` say how).
  @doc false
  @spec train(t(), list(), list() | :none) :: t()
  def train(%Continuous{} = scale, values, :none), do: Continuous.train(scale, values)
  def train(%Discrete{} = scale, values, levels), do: Discrete.train(scale, values, levels)

  # Whether `scale` is discrete, its legend's keys its levels, rather than continuous.
  @doc false
  @spec discrete?(t()) :: boolean()
  def discrete?(%Discrete{}), do: true
  def discrete?(%Continuous{}), do: false

  # The scale widened to cover positions, such as a bar's edges once its levels are mapped: a
  # continuous scale's range, as `train/3` widens it, and a discrete scale's continuous range, its
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
  # scale's limits, a discrete one at its level's position counting from 1. For an aesthetic other
  # than position, each value through the scale's palette: a continuous one's place in the scale's
  # limits (`limits/1`), from 0 to 1, by its `rescaler` (`place/3`), put through the palette, and
  # the scale's `na_value` for a missing value, one that is not a finite number, one outside the
  # limits, which ggplot2 censors and maps to its `na.value`, or one whose place R makes NaN; a
  # discrete one as `Giggly.Scale.Discrete` maps it.
  @doc false
  @spec map(t(), list()) :: list()
  def map(%Continuous{palette: :identity} = scale, values), do: Continuous.censor(scale, values)

  # A scale with no limits, every value it was trained on missing, is handed none but missing
  # values, which are not numbers, so `placed_inside?/2` never asks about its bounds.
  def map(%Continuous{palette: palette, na_value: na_value} = scale, values) do
    bounds = limits(scale)

    Enum.map(values, fn value ->
      place = if placed_inside?(value, bounds), do: place(value, bounds, scale.rescaler)
      if is_number(place), do: Palette.continuous(palette, place), else: na_value
    end)
  end

  def map(%Discrete{} = scale, values), do: Discrete.map(scale, values)

  # A value's place in `bounds` by the scale's rescaler: R's `rescale()`, from 0 to 1; about a
  # midpoint, R's `rescale_mid()`, `(value - midpoint) / extent + 0.5`, `extent` twice the further
  # end's distance from it, in that order of operations, so the further end is at 0 or 1 and the
  # midpoint at the middle; bounds of zero width put every value at the middle either way. Or R's
  # `rescale_max()`, the value over the high end, so 0 is at 0 and one value at 1, whatever the
  # low end: over a high end of 0, a value of 0 is R's NaN, `nil`, which maps to the missing value,
  # and any other an infinity, which R cannot draw, so it raises.
  defp place(value, bounds, :rescale), do: rescale(value, bounds, {0, 1})

  defp place(value, {low, high}, {:mid, midpoint}) do
    if zero_range?(low, high) do
      0.5
    else
      extent = 2 * max(abs(low - midpoint), abs(high - midpoint))
      (value - midpoint) / extent + 0.5
    end
  end

  defp place(value, {_low, high}, :max) when high != 0, do: value / high
  defp place(value, _bounds, :max) when value == 0, do: nil

  defp place(value, _bounds, :max) do
    raise ArgumentError,
          "a scale placing each value at its share of its limits' high end cannot place " <>
            "#{inspect(value)} when that end is 0: its place would be infinite, which R cannot " <>
            "draw either; give the scale limits whose high end is above 0"
  end

  # Each position, `nil` where a continuous scale's limits leave it out, `:infinity` and
  # `:neg_infinity` kept: ggplot2's second mapping of the positions, once they are final, which
  # removes a bar the limits cut. A discrete scale's positions are returned as given.
  @doc false
  @spec censor(t(), list()) :: list()
  def censor(%Continuous{} = scale, values), do: Continuous.censor(scale, values)
  def censor(%Discrete{}, values), do: values

  # The extent of the axis in positions, widened as ggplot2 widens it before drawing: a continuous
  # scale's limits, each end its `limits`' or else its range's, by its `expand`, 5% of their width
  # at each end unless it says otherwise; and a discrete scale's limits, its levels unless it
  # gives them, at positions 1 to n, by its `expand`, 0.6 at each end unless it says otherwise, then
  # reaching further where its continuous range does, which is not widened: a bar wider than its
  # level's slot widens the axis, as ggplot2's `expand_limits_discrete()` takes the range of both.
  # A discrete scale with no limits widens its continuous range alone by its `expand`, such as
  # counts a stat puts on the axis, or else 0 to 1, as ggplot2 widens an axis it has no values
  # for.
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
  def dimension(%Continuous{expand: expansion} = scale), do: dimension(scale, expansion)
  def dimension(%Discrete{expand: expansion} = scale), do: dimension(scale, expansion)

  # The extent `dimension/1` gives, widened by `expansion` in place of the scale's `expand`, as
  # ggplot2's `dimension(expand)` takes one: a stat reads an axis unwidened, `[mult: {0, 0}, add:
  # {0, 0}]`, as ggplot2's stats call `dimension()` with its default.
  @doc false
  @spec dimension(t(), mult: {number(), number()}, add: {number(), number()}) ::
          {number(), number()}
  def dimension(%Continuous{} = scale, expansion) do
    case limits(scale) do
      :none ->
        expand({0, 1}, expansion)

      limits ->
        limits
        |> expand(expansion)
        |> collapse_zero_width()
    end
  end

  def dimension(%Discrete{continuous_range: range} = scale, expansion) do
    case {Discrete.limits(scale), range} do
      {[], :none} ->
        expand({0, 1}, expansion)

      {[], range} ->
        expand(range, expansion)

      {limits, :none} ->
        expand({1, length(limits)}, expansion)

      {limits, {range_low, range_high}} ->
        {low, high} = expand({1, length(limits)}, expansion)
        {min(low, range_low), max(high, range_high)}
    end
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
  # an extent of zero width one, at its end, as in ggplot2. A date scale's width, `{:width, step}`,
  # gives a break every step (`Giggly.Scale.DateBreaks.width/2`) on the extent, those inside it
  # kept. `breaks: :none` gives none. Each is labelled by `labels/4`.
  #
  # A discrete scale has a break at each value its `breaks` gives among its limits, in the order
  # given, or else at each of its limits, its levels unless it gives them, whatever the extent;
  # `:none` gives none. Each is at its value's place among the limits and labelled by
  # `discrete_labels/3`.
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

  def breaks(%Continuous{breaks: {:width, step}, transform: transform} = scale, extent) do
    positions =
      transform
      |> Transform.transform(DateBreaks.width(step, extent))
      |> Enum.filter(fn position -> placed_inside?(position, extent) end)

    Enum.zip(positions, labels(scale, positions, :width, extent))
  end

  def breaks(%Discrete{} = scale, _extent) do
    limits = Discrete.limits(scale)

    position_by_key =
      limits
      |> Enum.with_index(1)
      |> Map.new(fn {limit, position} -> {Discrete.key(limit), position} end)

    scale
    |> discrete_breaks(limits)
    |> Enum.map(fn {value, label} ->
      {Map.fetch!(position_by_key, Discrete.key(value)), label}
    end)
  end

  # A discrete scale's breaks among `limits`, each the limit's value and its label: the values its
  # `breaks` gives among the limits, in the order given, or else every limit; none for `:none`.
  # Each is the limit as the scale holds it, which a given break names by value (`Discrete.key/1`),
  # so a break of `4` is a level of `4.0`. Each is labelled by `discrete_labels/3`.
  defp discrete_breaks(%Discrete{breaks: :none}, _limits), do: []

  defp discrete_breaks(%Discrete{} = scale, limits) do
    limit_by_key = Map.new(limits, fn limit -> {Discrete.key(limit), limit} end)
    candidates = discrete_candidates(scale, limits)

    {values, indexes} =
      candidates
      |> Enum.with_index()
      |> Enum.flat_map(fn {value, index} ->
        case Map.fetch(limit_by_key, Discrete.key(value)) do
          {:ok, limit} -> [{limit, index}]
          :error -> []
        end
      end)
      |> Enum.unzip()

    Enum.zip(values, discrete_labels(scale, values, {indexes, length(candidates)}))
  end

  # The values a discrete scale may mark: its breaks where given, else its limits.
  defp discrete_candidates(%Discrete{breaks: :default}, limits), do: limits
  defp discrete_candidates(%Discrete{breaks: given}, _limits), do: given

  # The labels of a discrete scale's breaks `values`, which are the candidates at `indexes` among
  # `count` (its given breaks, or its limits): written as `Giggly.Scale.Labels` writes a level by
  # default; `:none` for each where it has none; its list's labels at those indexes, a list one for
  # each candidate, or the plot cannot be drawn; its map's label for each value it holds, the
  # default for the rest; or what its function returns for the values.
  defp discrete_labels(%Discrete{labels: :default}, values, _indexes), do: Labels.levels(values)

  defp discrete_labels(%Discrete{labels: :none}, values, _indexes),
    do: List.duplicate(:none, length(values))

  defp discrete_labels(%Discrete{labels: given}, _values, {indexes, count})
       when is_list(given) and length(given) == count,
       do: Enum.map(indexes, fn index -> Enum.at(given, index) end)

  defp discrete_labels(%Discrete{labels: given}, _values, {_indexes, count})
       when is_list(given) do
    raise ArgumentError,
          "a discrete scale's #{length(given)} labels must be one for each of its " <>
            "#{count} breaks, got: #{inspect(given)}"
  end

  defp discrete_labels(%Discrete{labels: given}, values, _indexes) when is_map(given) do
    label_by_key = Map.new(given, fn {value, label} -> {Discrete.key(value), label} end)

    Enum.zip_with(values, Labels.levels(values), fn value, own ->
      Map.get(label_by_key, Discrete.key(value), own)
    end)
  end

  defp discrete_labels(%Discrete{labels: labeller}, values, _indexes)
       when is_function(labeller, 1),
       do: labelled(labeller, values)

  # The breaks a legend of the scale shows, in its transformation's order, each the value in the
  # data and its label: ggplot2's `get_breaks()` and `get_labels()` on the scale's limits
  # (`limits/1`), not an axis's widened extent, so given breaks outside them are left out. A
  # continuous scale's are its breaks, given or its transformation's, inside its limits, taken as
  # floats as R's limits are doubles, one at the low end of limits of zero width, and none before
  # the scale has limits; a discrete scale's are its breaks among its limits, `nil` labelled `NA`,
  # as ggplot2's legend keeps `NA`; `:none` gives none.
  @doc false
  @spec legend_breaks(t()) :: [{term(), String.t() | :none}]
  def legend_breaks(%Continuous{} = scale) do
    case limits(scale) do
      :none -> []
      {low, high} -> breaks(scale, {low / 1, high / 1})
    end
  end

  def legend_breaks(%Discrete{} = scale), do: discrete_breaks(scale, Discrete.limits(scale))

  # `count` values spread evenly over a continuous scale's limits (`limits/1`), from their low end
  # to their high, as R's `seq(low, high, length.out = count)` spreads them
  # (`Giggly.Scale.Palette`): the values ggplot2's colour bar takes its colours at
  # (`extract_decor()`).
  @doc false
  @spec samples(Continuous.t(), pos_integer()) :: [number()]
  def samples(%Continuous{} = scale, count) do
    scale
    |> limits()
    |> Palette.spread(count)
  end

  # Each of `values`' place in a continuous scale's limits (`limits/1`), from 0 at their low end
  # to 1 at their high (`rescale/3`), as ggplot2's colour bar places its ticks and its colours,
  # whatever the scale's rescaler.
  @doc false
  @spec places(Continuous.t(), [number()]) :: [float()]
  def places(%Continuous{} = scale, values) do
    bounds = limits(scale)
    Enum.map(values, fn value -> rescale(value, bounds, {0, 1}) end)
  end

  # The minor breaks an axis showing `extent` of the scale draws between `breaks`, the breaks
  # `breaks/2` gives on that extent: ggplot2's `get_breaks_minor()` as its view scale calls it,
  # less the breaks themselves, which ggplot2's grid leaves out of its minor lines.
  #
  # A continuous scale takes those its `minor_breaks` gives, in data units, put through its
  # transformation, or a date scale's every step of its width, or by default its transformation's
  # (`Giggly.Scale.Transform`), and keeps those inside `extent`, its ends included; `:none` gives
  # none. By default they fall midway
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

  defp candidate_minor_breaks(
         %Continuous{minor_breaks: {:width, step}, transform: transform},
         _positions,
         extent
       ),
       do: Transform.transform(transform, DateBreaks.width(step, extent))

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
  # given, the breaks a date scale's width gives (`:width`), or else the default breaks
  # (`:default`): the scale's `labels` at those indexes, what its function returns for the
  # positions, each break written in its format by `Calendar.strftime/3`, `:none` for each where it
  # has none, or its transformation's (`Transform.format/3`), told whether they are the default
  # breaks, since a date's default breaks take the format of the step they were chosen by and any
  # others are written in full. A function must return a string for each break, or the plot cannot
  # be drawn. A function and a format are handed the breaks in data units, turned back from their
  # positions, as ggplot2 hands them.
  defp labels(%Continuous{labels: :none}, positions, _origin, _extent),
    do: List.duplicate(:none, length(positions))

  defp labels(%Continuous{labels: given}, _positions, indexes, _extent)
       when is_list(given) and is_list(indexes),
       do: Enum.map(indexes, fn index -> Enum.at(given, index) end)

  defp labels(%Continuous{labels: labeller, transform: transform}, positions, _origin, _extent)
       when is_function(labeller, 1),
       do: labelled(labeller, Transform.inverse(transform, positions))

  defp labels(
         %Continuous{labels: {:format, format}, transform: transform},
         positions,
         _origin,
         _extent
       ) do
    transform
    |> Transform.inverse(positions)
    |> Enum.map(fn date -> Calendar.strftime(date, format) end)
  end

  defp labels(%Continuous{labels: :default, transform: transform}, positions, :default, extent),
    do: Transform.format(transform, positions, extent)

  defp labels(%Continuous{labels: :default, transform: transform}, positions, _given, _extent),
    do: Transform.format(transform, positions, :given)

  # What a labels function returns for `breaks`, which must be a string for each.
  defp labelled(labeller, breaks) do
    labelled = labeller.(breaks)

    if is_list(labelled) and length(labelled) == length(breaks) and
         Enum.all?(labelled, &is_binary/1) do
      labelled
    else
      raise ArgumentError,
            "a scale's labels function must return a string for each of the breaks " <>
              "#{inspect(breaks)}, got: #{inspect(labelled)}"
    end
  end

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

  # The key that orders discrete values with no levels of their own: `nil` after every present
  # value, which compare in Erlang term order, so strings sort by their bytes and `false` before
  # `true`; a factor's values, dates among them, are ordered by its levels instead. Grouping orders
  # its combinations by the same key, so group ids and axis positions agree.
  @doc false
  @spec level_key(term()) :: {0, term()} | {1, nil}
  def level_key(nil), do: {1, nil}
  def level_key(value), do: {0, value}
end
