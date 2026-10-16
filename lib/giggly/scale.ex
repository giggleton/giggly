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
  #   * `:string`, `:boolean` and `:atom` get a discrete scale (`Giggly.Scale.Discrete`);
  #   * dates, times and `:term` get none yet.
  #
  # ## Transformation
  #
  # A continuous scale records, by name, the transformation its values are put through before it
  # trains on them (`Giggly.Scale.Transform`), so it trains, and maps, in transformed space. Every
  # continuous scale records the identity until a plot can choose another, as ggplot2's continuous
  # scales default to `transform = "identity"`: an untransformed axis says so rather than leaving it
  # out. A discrete scale has no transformation, as in ggplot2.
  #
  # ## Training and mapping
  #
  # Training follows R's `scales` package. A continuous scale's range spans the finite numbers it
  # sees; `nil` and the non-finite floats are skipped. A discrete scale's levels are the distinct
  # values it sees, sorted with `nil` last and otherwise in Erlang term order, so strings sort by
  # their bytes. A position scale's palette is the identity: mapping leaves a continuous value as
  # it is, and puts a discrete value at its level's position, counting from 1, as ggplot2 does
  # before the coordinate system rescales anything. Any other aesthetic's scale maps through its
  # palette: a continuous value's place in the range, from 0 to 1 (R's `rescale()`), onto the
  # palette's range, and a discrete value to its level's share of the palette's spread.
  #
  # ## Aesthetics other than position
  #
  # `alpha` is the one so far (`non_position_aesthetics/0`). Its scale is ggplot2's default for
  # it: a continuous column onto 0.1 to 1, `scale_alpha_continuous()`, and a discrete one spread
  # from 0.1 to 1, `scale_alpha_ordinal()`, which ggplot2's `scale_alpha_discrete()` uses with a
  # warning that Giggly, building a plot without side effects, does not give.

  # Values in, values out: a scale depends on nothing, so it stays extractable.
  use Boundary, deps: [], exports: []

  alias Giggly.Scale.{Continuous, Discrete, Labels, Transform}

  @typedoc "A trained position scale."
  @type t :: Continuous.t() | Discrete.t()

  @typedoc "A break on an axis: its position and its label."
  @type break :: {number(), String.t()}

  @typedoc "Which kind of scale a column needs, or `:none` when no scale can place it yet."
  @type kind :: :continuous | :discrete | :none

  @continuous_dtypes [:integer, :float, :null]
  @discrete_dtypes [:string, :boolean, :atom]

  # ggplot2's default expansion, as {multiple of the width, constant}: `expansion(mult = 0.05)`
  # for a continuous scale and `expansion(add = 0.6)` for a discrete one.
  @continuous_expansion {0.05, 0}
  @discrete_expansion {0, 0.6}

  # R's `zero_range()` tolerance: 1000 times the double-precision machine epsilon.
  @zero_range_tolerance 1000 * 2.220446049250313e-16

  # The kind of scale a column of type `dtype` (a `Giggly.DataFrame` type) needs.
  @doc false
  @spec kind(atom()) :: kind()
  def kind(dtype) when dtype in @continuous_dtypes, do: :continuous
  def kind(dtype) when dtype in @discrete_dtypes, do: :discrete
  def kind(dtype) when is_atom(dtype), do: :none

  # The aesthetics other than position that a scale maps.
  @non_position_aesthetics [:alpha]

  # ggplot2's default range for alpha, 0.1 to 1, which leaves every value visible.
  @alpha_range {0.1, 1.0}

  # An untrained position scale of the given kind, its palette the identity; a continuous one
  # records the identity transformation.
  @doc false
  @spec new(:continuous | :discrete) :: t()
  def new(:continuous), do: %Continuous{range: :none, transform: :identity, palette: :identity}
  def new(:discrete), do: %Discrete{levels: [], continuous_range: :none, palette: :identity}

  # An untrained scale of the given kind for `aesthetic`, one of `non_position_aesthetics/0`, with
  # ggplot2's default palette for it.
  @doc false
  @spec new(:continuous | :discrete, atom()) :: t()
  def new(:continuous, :alpha),
    do: %Continuous{range: :none, transform: :identity, palette: {:rescale, @alpha_range}}

  def new(:discrete, :alpha),
    do: %Discrete{levels: [], continuous_range: :none, palette: {:sequence, @alpha_range}}

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

  # The scale widened to cover `values`. A discrete scale handed positions, such as a bar's edges
  # once its levels are mapped, widens its continuous range instead of its levels, as ggplot2's
  # discrete position scale trains `range_c`.
  @doc false
  @spec train(t(), list()) :: t()
  def train(%Continuous{} = scale, values), do: Continuous.train(scale, values)
  def train(%Discrete{} = scale, values), do: Discrete.train(scale, values)

  # The scale as ggplot2 resets it before training it again on the positioned marks: a continuous
  # scale forgets its range, and a discrete one its continuous range, keeping its levels, since
  # their values can no longer be recovered from positions.
  @doc false
  @spec reset(t()) :: t()
  def reset(%Continuous{} = scale), do: %{scale | range: :none}
  def reset(%Discrete{} = scale), do: %{scale | continuous_range: :none}

  # Each value's position on the scale's axis: a continuous value unchanged, a discrete one at its
  # level's position counting from 1.
  @doc false
  @spec map(t(), list()) :: list()
  def map(%Continuous{} = scale, values), do: Continuous.map(scale, values)
  def map(%Discrete{} = scale, values), do: Discrete.map(scale, values)

  # The extent of the axis in positions, widened as ggplot2 widens it by default before drawing: a
  # continuous range by 5% of its width at each end, and discrete levels, at positions 1 to n, by
  # 0.6, then reaching further where its continuous range does, which is not widened: a bar wider
  # than its level's slot widens the axis, as ggplot2's `expand_limits_discrete()` takes the range
  # of both. A range of zero width is widened as though its width were 1, as R's `expand_range()` does,
  # so one value, zero included, spans 0.05 either side of it; an untrained continuous scale spans 0
  # to 1 before it is widened, ggplot2's default for an empty axis. It is ggplot2's `dimension()`
  # with the default expansion, and the coordinate system maps it onto the panel.
  #
  # Ends that differ only by rounding error, relative to their size, count as one value.
  #
  # An extent still zero wide once widened, by R's `zero_range()`, is its middle, both ends equal:
  # a single value from about 4.5e11 up, where 0.05 either side is rounding error beside its size.
  # ggplot2 keeps such an extent's ends and `scales::rescale()` draws every value on it at the
  # middle of the panel; ends that are equal are how the coordinate system is told to.
  @doc false
  @spec dimension(t()) :: {number(), number()}
  def dimension(%Continuous{range: :none}), do: expand({0, 1}, @continuous_expansion)

  def dimension(%Continuous{range: range}) do
    range
    |> expand(@continuous_expansion)
    |> collapse_zero_width()
  end

  def dimension(%Discrete{levels: levels, continuous_range: :none}),
    do: expand({1, length(levels)}, @discrete_expansion)

  def dimension(%Discrete{levels: levels, continuous_range: {range_low, range_high}}) do
    {low, high} = expand({1, length(levels)}, @discrete_expansion)
    {min(low, range_low), max(high, range_high)}
  end

  # The breaks an axis showing `extent` of the scale draws, each its position and its label, in
  # ascending order: ggplot2's `get_breaks()` and `get_labels()` as its view scale calls them.
  #
  # A continuous scale takes its transformation's breaks (`Giggly.Scale.Transform`), keeps those
  # inside `extent` (ggplot2 computes breaks on the widened extent and drops the rest), and writes
  # them as its transformation writes them. An untrained one has none, and an extent of zero width
  # has one break, at its end, as in ggplot2. A break exactly at an end of the extent is kept.
  #
  # A discrete scale has a break at each level, whatever the extent, labelled as
  # `Giggly.Scale.Labels` writes a level.
  @doc false
  @spec breaks(t(), {float(), float()}) :: [break()]
  def breaks(%Continuous{range: :none}, _extent), do: []

  def breaks(%Continuous{transform: transform}, {low, high} = extent) do
    positions =
      if zero_range?(low, high) do
        [low]
      else
        transform
        |> Transform.breaks(extent)
        |> Enum.filter(fn position -> position >= low and position <= high end)
      end

    Enum.zip(positions, Transform.format(transform, positions))
  end

  def breaks(%Discrete{levels: levels}, _extent) do
    levels
    |> Labels.levels()
    |> Enum.with_index(1)
    |> Enum.map(fn {label, position} -> {position, label} end)
  end

  # The breaks a legend of the scale shows, in ascending order, each the value in the data and its
  # label: ggplot2's `get_breaks()` and `get_labels()` on the scale's limits, its trained range or
  # levels, not an axis's widened extent. A continuous scale's are its transformation's breaks
  # inside the range, taken as floats as R's limits are doubles, one at its low end when it has
  # zero width, and none when untrained; a
  # discrete scale's are its levels, `nil` last and labelled `NA`, as ggplot2's legend keeps `NA`.
  @doc false
  @spec legend_breaks(t()) :: [{term(), String.t()}]
  def legend_breaks(%Continuous{range: :none}), do: []

  def legend_breaks(%Continuous{range: {low, high}} = scale),
    do: breaks(scale, {low / 1, high / 1})

  def legend_breaks(%Discrete{levels: levels}),
    do: Enum.zip(levels, Labels.levels(levels))

  # The minor breaks an axis showing `extent` of the scale draws between `breaks`, the breaks
  # `breaks/2` gives on that extent, in ascending order: ggplot2's `get_breaks_minor()` as its view
  # scale calls it, less the breaks themselves, which ggplot2's grid leaves out of its minor lines.
  #
  # A continuous scale takes its transformation's minor breaks (`Giggly.Scale.Transform`) and keeps
  # those inside `extent`, its ends included. They fall midway between breaks, and between the
  # outermost breaks and the extent's ends.
  #
  # An axis with fewer than two breaks has none, and so does a discrete scale, as in ggplot2.
  @doc false
  @spec minor_breaks(t(), [break()], {float(), float()}) :: [float()]
  def minor_breaks(%Continuous{transform: transform}, breaks, {low, high} = extent) do
    positions = Enum.map(breaks, fn {position, _label} -> position end)

    transform
    |> Transform.minor_breaks(positions, extent)
    |> Enum.filter(fn position -> position >= low and position <= high end)
    |> Enum.reject(fn position -> position in positions end)
  end

  def minor_breaks(%Discrete{}, _breaks, _extent), do: []

  # Widens each end by a multiple of the range's width plus a constant: R's `expand_range()`.
  defp expand({low, high}, {multiple, constant}) do
    width = if zero_range?(low, high), do: 1, else: high - low
    padding = width * multiple + constant
    {low - padding, high + padding}
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
