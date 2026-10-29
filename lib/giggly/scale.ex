defmodule Giggly.Scale do
  @moduledoc false

  # Scales: what kind of scale a column's values need, the range or levels those values span once
  # trained, and where each value sits on an axis, or what it becomes as another aesthetic, such
  # as alpha, through the scale's palette (`Scales.Palette`).
  #
  # A scale works on plain values, never on frames or plots: the assembly pulls a column and hands
  # its values here. This is ggplot2's half of a scale; R's scales half, the breaks,
  # transformations, palettes, bounds and data ranges it works with, is the `Scales` package.
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
  #   * a date-time, `{:datetime, zone}`, and a naive one, `:naive_datetime`, get a date-time
  #     scale, a continuous scale of the seconds since 1970-01-01 00:00 through the date-time
  #     transformation, as `scale_type()` gives a `POSIXct` `"datetime"`, the two kinds apart, as
  #     a naive date-time is no instant; the scale takes the zone a plot gave it, else that of the
  #     first column it places (`settle_zone/2`), as ggplot2's takes the first column's `tzone`,
  #     and lays its breaks on that zone's clock. On an aesthetic
  #     other than position they get none yet, and a continuous scale through the identity takes
  #     either at its seconds;
  #   * a time of day, `:time`, gets a time scale, a continuous scale of the seconds since midnight
  #     through the time-of-day transformation, as `scale_type()` gives an `hms` `"time"`; on an
  #     aesthetic other than position it gets none yet, and a continuous scale through the
  #     identity takes one at its seconds;
  #   * lists and `:term` get none yet.
  #
  # ## Transformation
  #
  # A continuous scale records, by name, the transformation its values are put through before it
  # trains on them (`Scales.Transform`), so it trains, and maps, in transformed space. A
  # continuous scale of numbers records the identity, as ggplot2's continuous scales default to
  # `transform = "identity"`: an untransformed axis says so rather than leaving it out. A date
  # scale records the date transformation, and a plot's scale may name log10, square root,
  # reverse or reciprocal; a date-time scale and a time scale record theirs. Its limits, breaks
  # and minor breaks are given in data units and put through the transformation here; its labels
  # are written from the breaks turned back. A discrete scale has no transformation, as in
  # ggplot2.
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
  # breaks and labels replace its transformation's, or `:none` leaves them out. A date or
  # date-time scale's breaks and minor breaks may be a width, `{:width, [week: 1]}`, a break every
  # week, or `[hour: 6]` on a date-time or time scale, and its labels a format,
  # `{:format, "%b %d"}`, each break written in it by `Calendar.strftime/3`.
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
  # to `#56B1F7`, `scale_colour_continuous()`'s, blended in L*a*b* (`Scales.Palette`).
  # Shape's gives a discrete column `pal_shape()`'s six solid shapes, as `scale_shape()` does, and
  # line type's `pal_linetype()`'s 13 line types, as `scale_linetype()` does; a shape or line type
  # scale is always discrete (`discrete_only?/1`): neither has an order, so R has no continuous
  # scale of either and aborts for a continuous column. Line width's maps a continuous column onto
  # widths from 1 to 6, `scale_linewidth_continuous()`, and spreads a discrete one from 2 to 6,
  # `scale_linewidth_ordinal()`, which `scale_linewidth_discrete()` uses with a warning Giggly
  # leaves out. A plot's scale may carry another palette: manual, grey, brewer, another hue range
  # or gradient, open shapes, any of `Scales.Palette`'s, one of the other kind converted when
  # mapped. A continuous value's place runs over the scale's limits, or about its
  # midpoint (R's
  # `rescale_mid()`), or at its share of their high end (R's `rescale_max()`), as the scale's
  # `rescaler` says, and one outside them is censored, as ggplot2's `oob = censor`; a missing or
  # censored value maps to the scale's `na_value`, grey50 for a colour, `nil`, R's `NA`, for alpha,
  # line type, line width, shape and size. Each names the guide that draws it, as ggplot2's scales
  # do: a colour bar for a continuous colour or fill, colour steps for a binned one, a legend for the
  # rest, whose breaks and labels are the scale's on its limits.
  #
  # A plot's colour or fill scale may be binned (`Giggly.Scale.Binned`), ggplot2's third kind,
  # which no column's type chooses: it trains as a continuous scale does, squishes each value into
  # its limits, widened from the data's range where none are given, and cuts it into bins at its
  # breaks, each bin one colour.

  # Values in, values out: a scale depends on nothing but R's scales half, `Scales`, as ggplot2
  # depends on R's `scales`, and R's `as.character()`, which writes a discrete level. It exports
  # the three kinds' structs, which `Giggly.Plot` writes with a user's options and
  # `Giggly.panel_scales/2` returns, a binned one for colour and fill alone.
  use Boundary,
    deps: [Giggly.AsCharacter, Scales],
    exports: [Binned, Continuous, Discrete]

  alias Giggly.AsCharacter
  alias Giggly.Scale.{Binned, Continuous, Discrete}
  alias Scales.{Bounds, DataRange, Palette, Transform}

  @typedoc "A scale: a continuous, a discrete or a binned one."
  @type t :: Continuous.t() | Discrete.t() | Binned.t()

  @typedoc "A break on an axis: its position and its label, `:none` where the axis has no labels."
  @type break :: {number(), String.t() | :none}

  @typedoc "Which kind of scale a column needs, or `:none` when no scale can place it yet."
  @type kind :: :continuous | :discrete | :date | :datetime | :naive_datetime | :time | :none

  # The kinds of column whose scale is continuous through a transformation of their own, which an
  # untransformed continuous scale takes too, and which no aesthetic other than position takes yet.
  @time_kinds [:date, :datetime, :naive_datetime, :time]

  # The time zone database a date-time scale reads its zone with unless a plot gives it another:
  # the standard library's, which knows UTC alone.
  @time_zone_database Calendar.UTCOnlyTimeZoneDatabase

  # The aesthetics other than position that a scale maps, those of them that are colours, and those
  # whose every scale is discrete.
  @non_position_aesthetics [:alpha, :color, :fill, :linetype, :linewidth, :shape, :size]
  @color_aesthetics [:color, :fill]
  @discrete_aesthetics [:linetype, :shape]

  @continuous_dtypes [:integer, :float, :null]
  @discrete_dtypes [:string, :boolean, :atom, :category]

  # The kind of scale a column of type `dtype` (a `Giggly.DataFrame` type) needs.
  @doc false
  @spec kind(atom() | tuple()) :: kind()
  def kind(dtype) when dtype in @continuous_dtypes, do: :continuous
  def kind(dtype) when dtype in @discrete_dtypes, do: :discrete
  def kind(:date), do: :date
  def kind({:datetime, _zone}), do: :datetime
  def kind(:naive_datetime), do: :naive_datetime
  def kind(:time), do: :time
  def kind(dtype) when is_atom(dtype), do: :none
  def kind({:list, _values_dtype}), do: :none

  # The kind of scale a column of type `dtype` needs on `aesthetic`: on a position aesthetic, its
  # `kind/1`; on another, the same but for a date, a date-time or a time, whose scale on any
  # aesthetic but position (ggplot2's `scale_alpha_date()` and `scale_colour_datetime()`) has not
  # arrived.
  @doc false
  @spec kind(atom() | tuple(), atom()) :: kind()
  def kind(dtype, aesthetic) when aesthetic in @non_position_aesthetics do
    case kind(dtype) do
      kind when kind in @time_kinds -> :none
      kind -> kind
    end
  end

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

  # ggplot2's default colour palette for an ordered factor, `scale_colour_viridis_d()`'s, R's
  # `viridis()` with its defaults.
  @viridis_palette {:viridis, %{option: :viridis, begin: 0.0, end: 1.0, direction: 1, alpha: 1.0}}

  # ggplot2's default continuous colour palette, `pal_seq_gradient("#132B43", "#56B1F7")`.
  @gradient_palette {:gradient, ["#132B43", "#56B1F7"]}

  # ggplot2's colour for a missing value, grey50.
  @color_na_value "#7F7F7F"

  # An untrained position scale of the given kind, its palette the identity and its guide an axis,
  # as ggplot2's position scales are drawn by `guide_axis()`; a continuous one records the identity
  # transformation, a date scale, a continuous one, the date transformation, a date-time scale,
  # naive or not, the date-time transformation, its zone left for its first column to settle
  # (`settle_zone/2`) and read by the standard library's database, and a time scale the
  # time-of-day transformation.
  @doc false
  @spec new(:continuous | :discrete | :date | :datetime | :naive_datetime | :time) :: t()
  def new(:continuous), do: %Continuous{}
  def new(:date), do: %Continuous{transform: :date}
  def new(:time), do: %Continuous{transform: :time}

  def new(kind) when kind in [:datetime, :naive_datetime],
    do: %Continuous{transform: {:datetime, :default, @time_zone_database}}

  def new(:discrete), do: %Discrete{}

  # An untrained scale of the given kind for `aesthetic`, one of `non_position_aesthetics/0`, with
  # ggplot2's default palette, value for a missing value and guide for it: a colour bar for a
  # continuous colour or fill, and a legend for the rest. A shape's and a line type's are discrete
  # alone (`discrete_only?/1`). An ordered factor's, `:ordinal`, as ggplot2's `scale_type()` names
  # it, is a discrete scale: for a colour or fill viridis, as `scale_colour_ordinal()` takes
  # `scale_colour_viridis_d()`, its missing value none, R's `NA`; for any other aesthetic the
  # discrete one, which ggplot2's ordinal alpha, size and line width scales match, its ordinal
  # shape scale only warning and line type having none.
  @doc false
  @spec new(:continuous | :discrete | :ordinal, atom()) :: t()
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

  def new(:ordinal, aesthetic) when aesthetic in @color_aesthetics,
    do: %Discrete{palette: @viridis_palette, na_value: :none, guide: :legend}

  def new(:ordinal, aesthetic), do: new(:discrete, aesthetic)

  # The kind a scale is, as `kind/1` names the kind a column needs: a discrete scale, a binned one,
  # a date scale, a date-time scale, a naive one once its first column has settled it, a time
  # scale, or another continuous scale.
  @doc false
  @spec kind_of(t()) ::
          :continuous | :discrete | :binned | :date | :datetime | :naive_datetime | :time
  def kind_of(%Discrete{}), do: :discrete
  def kind_of(%Binned{}), do: :binned
  def kind_of(%Continuous{transform: :date}), do: :date
  def kind_of(%Continuous{transform: :time}), do: :time
  def kind_of(%Continuous{transform: {:datetime, :naive, _database}}), do: :naive_datetime
  def kind_of(%Continuous{transform: {:datetime, _zone, _database}}), do: :datetime
  def kind_of(%Continuous{}), do: :continuous

  # Whether `scale` takes a column that needs a scale of `kind` (`kind/1`): a scale of that kind
  # does; a date-time scale no column has settled takes naive date-times too; and a continuous
  # scale through the identity takes a date at its days since 1970-01-01, a date-time at its
  # seconds and a time at its seconds since midnight, as R stores each and its continuous scale
  # places one. Through another transformation each is refused, where R fails. A binned scale
  # takes numbers alone, as ggplot2's refuses anything else ("Binned scales only support continuous
  # data").
  @doc false
  @spec takes?(t(), kind()) :: boolean()
  def takes?(%Binned{}, kind), do: kind == :continuous
  def takes?(%Continuous{transform: :identity}, kind) when kind in @time_kinds, do: true

  def takes?(%Continuous{transform: {:datetime, :default, _database}}, :naive_datetime), do: true

  def takes?(scale, kind), do: kind_of(scale) == kind

  # A date-time scale whose zone neither a plot nor a column has settled given the zone of the
  # first column it places, of type `dtype`, as ggplot2's date-time scale takes the first column's
  # `tzone` when not given one: a naive one's `:naive`, a date-time's its zone, `{:error, {zone,
  # database}}` where the scale's time zone database does not know it. Any other scale is returned
  # as it is, a zone a plot gave kept whatever the column's.
  @doc false
  @spec settle_zone(t(), atom() | tuple()) :: {:ok, t()} | {:error, {String.t(), module()}}
  def settle_zone(%Continuous{transform: {:datetime, :default, database}} = scale, dtype) do
    case dtype do
      :naive_datetime ->
        {:ok, %{scale | transform: {:datetime, :naive, database}}}

      {:datetime, zone} ->
        if known_zone?(zone, database),
          do: {:ok, %{scale | transform: {:datetime, zone, database}}},
          else: {:error, {zone, database}}
    end
  end

  def settle_zone(scale, _dtype), do: {:ok, scale}

  # Whether `database` knows the time zone `zone`: whether it can say what an instant is there.
  defp known_zone?(zone, database),
    do: match?({:ok, _shifted}, DateTime.shift_zone(~U[1970-01-01 00:00:00Z], zone, database))

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
  def train(%Binned{} = scale, values, :none), do: Binned.train(scale, values)

  # Whether `scale` is discrete, its legend's keys its levels, rather than continuous.
  @doc false
  @spec discrete?(t()) :: boolean()
  def discrete?(%Discrete{}), do: true
  def discrete?(%Continuous{}), do: false
  def discrete?(%Binned{}), do: false

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
  # limits (`limits/1`), from 0 to 1, by its `rescaler` (`rescaled/3`), put through the palette,
  # and the scale's `na_value` for a missing value, one that is not a finite number, one outside the
  # limits, which ggplot2 censors and maps to its `na.value`, or one whose place R makes NaN; a
  # discrete one as `Giggly.Scale.Discrete` maps it; a binned one to its bin's colour, as
  # `Giggly.Scale.Binned` maps it.
  @doc false
  @spec map(t(), list()) :: list()
  def map(%Continuous{palette: :identity} = scale, values), do: Continuous.censor(scale, values)

  # A scale with no limits, every value it was trained on missing, is handed none but missing
  # values, which are not numbers, so `placed_inside?/2` never asks about its bounds.
  def map(%Continuous{palette: palette, na_value: na_value} = scale, values) do
    bounds = limits(scale)

    values
    |> Enum.map(fn value -> if placed_inside?(value, bounds), do: value end)
    |> rescaled(bounds, scale.rescaler)
    |> then(fn places -> Palette.continuous(palette, places) end)
    |> Enum.map(fn mapped -> if is_nil(mapped), do: na_value, else: mapped end)
  end

  def map(%Discrete{} = scale, values), do: Discrete.map(scale, values)
  def map(%Binned{} = scale, values), do: Binned.map(scale, values)

  # Each value's place in `bounds` by the scale's rescaler (`Scales.Bounds`), a `nil` left `nil`:
  # R's `rescale()`, from 0 to 1; about a midpoint, R's `rescale_mid()`, so the further end is at 0
  # or 1 and the midpoint at the middle; or R's `rescale_max()`, the value over the high end, so 0
  # is at 0 and one value at 1, whatever the low end. Over a high end of 0, a value of 0 is R's
  # NaN, `nil`, which maps to the missing value, and any other an infinity, which R cannot draw, so
  # it raises. Without bounds every value is `nil`, and stays so.
  defp rescaled(values, :none, _rescaler), do: values
  defp rescaled(values, bounds, :rescale), do: Bounds.rescale(values, bounds, {0, 1})

  defp rescaled(values, bounds, {:mid, midpoint}),
    do: Bounds.rescale_mid(values, bounds, {0, 1}, midpoint)

  defp rescaled(values, bounds, :max) do
    values
    |> Bounds.rescale_max(bounds, {0, 1})
    |> Enum.zip_with(values, fn place, value -> finite_place(place, value) end)
  end

  defp finite_place(place, _value) when is_number(place) or is_nil(place), do: place

  defp finite_place(_infinite, value) do
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
  # (`Scales.Transform`), found on the extent squished into the transformation's domain and
  # ascending in data units, so a reversing transformation's descend; either way those inside
  # `extent` are kept (ggplot2 computes breaks on the widened extent and drops the rest), a break
  # exactly at an end included, so a given break beyond the limits but inside the widened axis is
  # drawn, and one outside the domain is not. A scale with no limits yet has none by default, and
  # an extent of zero width one, at its end, as in ggplot2. A date scale's width, `{:width, step}`,
  # gives a break every step (`Scales.DateBreaks.width/2`) on the extent, those inside it
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
      |> Transform.width(step, extent)
      |> Enum.filter(fn position -> placed_inside?(position, extent) end)

    Enum.zip(positions, labels(scale, positions, :width, extent))
  end

  def breaks(%Discrete{} = scale, _extent) do
    limits = Discrete.limits(scale)

    position_by_key =
      limits
      |> Enum.with_index(1)
      |> Map.new(fn {limit, position} -> {DataRange.key(limit), position} end)

    scale
    |> discrete_breaks(limits)
    |> Enum.map(fn {value, label} ->
      {Map.fetch!(position_by_key, DataRange.key(value)), label}
    end)
  end

  # A discrete scale's breaks among `limits`, each the limit's value and its label: the values its
  # `breaks` gives among the limits, in the order given, or else every limit; none for `:none`.
  # Each is the limit as the scale holds it, which a given break names by value (`Scales.DataRange.key/1`),
  # so a break of `4` is a level of `4.0`. Each is labelled by `discrete_labels/3`.
  defp discrete_breaks(%Discrete{breaks: :none}, _limits), do: []

  defp discrete_breaks(%Discrete{} = scale, limits) do
    limit_by_key = Map.new(limits, fn limit -> {DataRange.key(limit), limit} end)
    candidates = discrete_candidates(scale, limits)

    {values, indexes} =
      candidates
      |> Enum.with_index()
      |> Enum.flat_map(fn {value, index} ->
        case Map.fetch(limit_by_key, DataRange.key(value)) do
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
  # `count` (its given breaks, or its limits): written as `level_labels/1` writes a level by
  # default; `:none` for each where it has none; its list's labels at those indexes, a list one for
  # each candidate, or the plot cannot be drawn; its map's label for each value it holds, the
  # default for the rest; or what its function returns for the values.
  defp discrete_labels(%Discrete{labels: :default}, values, _indexes), do: level_labels(values)

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
    label_by_key = Map.new(given, fn {value, label} -> {DataRange.key(value), label} end)

    Enum.zip_with(values, level_labels(values), fn value, own ->
      Map.get(label_by_key, DataRange.key(value), own)
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
  # as ggplot2's legend keeps `NA`; a binned scale's are its breaks (`Giggly.Scale.Binned`),
  # labelled by `binned_labels/3`; `:none` gives none.
  @doc false
  @spec legend_breaks(t()) :: [{term(), String.t() | :none}]
  def legend_breaks(%Continuous{} = scale) do
    case limits(scale) do
      :none -> []
      {low, high} -> breaks(scale, {low / 1, high / 1})
    end
  end

  def legend_breaks(%Discrete{} = scale), do: discrete_breaks(scale, Discrete.limits(scale))

  def legend_breaks(%Binned{} = scale) do
    {values, indexes} =
      scale
      |> Binned.breaks()
      |> Enum.unzip()

    Enum.zip(values, binned_labels(scale, values, indexes))
  end

  # The labels of a binned scale's breaks `values`, which are those at `indexes` among the breaks
  # they were chosen from: written as a continuous scale writes a number by default; `:none` for
  # each where it has none; its list's labels at those indexes, a list one for each of its given
  # breaks, or of its default ones, or the plot cannot be drawn, as R fails; or what its function
  # returns for the values.
  defp binned_labels(%Binned{labels: :default}, values, _indexes),
    do: Transform.format(:identity, values, :given)

  defp binned_labels(%Binned{labels: :none}, values, _indexes),
    do: List.duplicate(:none, length(values))

  defp binned_labels(%Binned{labels: given, breaks: breaks}, values, indexes)
       when is_list(given) do
    count = if is_list(breaks), do: length(breaks), else: length(values)

    if length(given) != count do
      raise ArgumentError,
            "a binned scale's #{length(given)} labels must be one for each of its " <>
              "#{count} breaks, got: #{inspect(given)}"
    end

    Enum.map(indexes, fn index -> Enum.at(given, index) end)
  end

  defp binned_labels(%Binned{labels: labeller}, values, _indexes) when is_function(labeller, 1),
    do: labelled(labeller, values)

  # `count` values spread evenly over a continuous scale's limits (`limits/1`), from their low end
  # to their high, as R's `seq(low, high, length.out = count)` spreads them
  # (`Scales.Palette`): the values ggplot2's colour bar takes its colours at
  # (`extract_decor()`).
  @doc false
  @spec samples(Continuous.t(), pos_integer()) :: [number()]
  def samples(%Continuous{} = scale, count) do
    scale
    |> limits()
    |> Palette.spread(count)
  end

  # Each of `values`' place in a continuous scale's limits (`limits/1`), from 0 at their low end
  # to 1 at their high (`Scales.Bounds.rescale/3`), as ggplot2's colour bar places its ticks and
  # its colours, whatever the scale's rescaler.
  @doc false
  @spec places(Continuous.t(), [number()]) :: [float()]
  def places(%Continuous{} = scale, values), do: Bounds.rescale(values, limits(scale), {0, 1})

  # What a colour steps guide draws of a continuous or binned scale whose legend shows the breaks
  # `values`, in order, as ggplot2's `GuideColoursteps` works it out with even steps: each break's
  # place up the bar, 0 to 1, or `nil` where the bar leaves it out, and each bin, its place from
  # and to and its colour. The bar is cut at the limits and the breaks, sorted and each once, into
  # bins all as long, each coloured as the scale maps its middle. A break's place is its count
  # among the breaks shown, in their order, over the bins' count, not its own edge's, as R counts
  # them, one lower where the scale's first break falls on a limit: breaks given out of order, or
  # after a first given outside the limits, are placed where R places them, and one counted past
  # the bar's end is left out. A continuous scale's default breaks on a limit are left out, as R
  # leaves them out of a scale that has not written its breaks back, as a binned one has.
  @doc false
  @spec steps(Continuous.t() | Binned.t(), [float()]) ::
          {[float() | nil], [{float(), float(), String.t() | :none}]}
  def steps(scale, values) do
    {low, high} = limits = step_limits(scale)
    shown = Enum.map(values, fn value -> if step_shown?(scale, value, limits), do: value end)

    edges =
      shown
      |> Enum.reject(&is_nil/1)
      |> then(fn kept -> [low, high | kept] end)
      |> Enum.sort()
      |> Enum.dedup_by(fn edge -> edge + 0.0 end)

    bar = {0, length(edges) - 1}
    lowered = if stepped_down?(scale, values, limits), do: 1, else: 0

    {counts, _next} =
      Enum.map_reduce(shown, 1, fn
        nil, count -> {nil, count}
        _value, count -> {count - lowered, count + 1}
      end)

    places =
      counts
      |> Bounds.rescale(bar, {0, 1})
      |> Enum.map(fn place -> if is_number(place) and place <= 1, do: place end)

    {places, bins(scale, edges, bar)}
  end

  # The bins between consecutive `edges`, each its place along the bar from and to, each edge's
  # place and the next's, and the colour the scale maps its middle to, R's `breaks[-1] -
  # diff(breaks) / 2`.
  defp bins(scale, edges, {_first, last} = bar) do
    middles =
      edges
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [from, to] -> to - (to - from) / 2 end)

    places =
      0..last//1
      |> Enum.to_list()
      |> Bounds.rescale(bar, {0, 1})

    Enum.zip_with(
      [places, Enum.drop(places, 1), map(scale, middles)],
      fn [from, to, color] -> {from, to, color} end
    )
  end

  # The scale's limits, a binned scale's widened.
  defp step_limits(%Continuous{} = scale), do: limits(scale)

  defp step_limits(%Binned{} = scale), do: Binned.limits(scale)

  # Whether a colour steps guide shows a break of the scale's: a continuous scale's default break
  # only off its limits, any other.
  defp step_shown?(%Continuous{breaks: :default}, value, {low, high}),
    do: value != low and value != high

  defp step_shown?(_scale, _value, _limits), do: true

  # Whether the scale's first break, `values`' first or its first given, is on a limit, R's
  # `breaks[1] %in% limits`; never for a continuous scale's default breaks, which R has left out
  # there.
  defp stepped_down?(%Continuous{breaks: :default}, _values, _limits), do: false

  defp stepped_down?(%Continuous{breaks: [first | _given], transform: transform}, _values, limits) do
    [position] = Transform.transform(transform, [first])
    on_limit?(position, limits)
  end

  defp stepped_down?(%Binned{breaks: :default}, [first | _values], limits),
    do: on_limit?(first, limits)

  defp stepped_down?(%Binned{breaks: [first | _given]}, _values, limits),
    do: on_limit?(first, limits)

  defp on_limit?(value, {low, high}), do: value == low or value == high

  # The minor breaks an axis showing `extent` of the scale draws between `breaks`, the breaks
  # `breaks/2` gives on that extent: ggplot2's `get_breaks_minor()` as its view scale calls it,
  # less the breaks themselves, which ggplot2's grid leaves out of its minor lines.
  #
  # A continuous scale takes those its `minor_breaks` gives, in data units, put through its
  # transformation, or a date scale's every step of its width, or by default its transformation's
  # (`Scales.Transform`), and keeps those inside `extent`, its ends included; `:none` gives
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
       do: Transform.width(transform, step, extent)

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
    {low, _high} = squished = Transform.squish(transform, extent)

    if Bounds.zero_range?(squished) do
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
  defp expand({low, high} = extent, mult: {mult_low, mult_high}, add: {add_low, add_high}) do
    width = if Bounds.zero_range?(extent), do: 1, else: high - low
    {low - (width * mult_low + add_low), high + (width * mult_high + add_high)}
  end

  # An extent R's `zero_range()` still calls zero wide, as its middle with both ends equal.
  defp collapse_zero_width({low, high} = extent) do
    if Bounds.zero_range?(extent) do
      middle = (low + high) / 2
      {middle, middle}
    else
      extent
    end
  end

  # The labels of discrete levels, in the order given: each written as R's `as.character()` writes
  # its value (`Giggly.AsCharacter`), as `factor()` labels its levels, `4` for a whole float,
  # `TRUE` for `true`; a missing one (`nil`) as `NA`, as ggplot2 labels a missing level.
  @doc false
  @spec level_labels(list()) :: [String.t()]
  def level_labels(levels), do: Enum.map(levels, &level_label/1)

  defp level_label(nil), do: "NA"
  defp level_label(value), do: AsCharacter.text(value)
end
