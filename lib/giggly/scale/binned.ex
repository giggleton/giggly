defmodule Giggly.Scale.Binned do
  @moduledoc """
  A binned scale: a colour or fill scale that cuts its continuous values into bins at its breaks
  and gives every value in a bin the same colour. Its fields:

    * `range`: the range of the finite numbers it has seen, or `:none` before it has seen any.
    * `palette`: what gives each bin its colour: `{:binned, palette}`, a discrete palette of
      `Scales.Palette`'s, such as `{:binned, {:brewer, %{palette: "Blues", direction: -1}}}`, its
      colours for as many levels as there are bins, the first for the lowest; or a continuous
      palette, such as `{:gradient, colors}`, or any other of `Scales.Palette`'s, the colour at the
      middle of each bin's place in the limits.
    * `rescaler`: how a value's place in the limits is found: `:rescale`, its distance from the
      low end over the limits' width; or `{:mid, midpoint}`, its distance from the midpoint over
      twice the further end's, so the midpoint is at the middle and the further end at 0 or 1.
    * `na_value`: what a missing value, or one not a finite number, maps to: grey, `"#7F7F7F"`,
      or `:none`, no colour.
    * `guide`: the guide that draws it: `:colorsteps`, a bar of one block of colour for each
      bin; `:legend`, a key for each break; or `:none` for none.
    * `name`: its guide's title, `:none` for none, or `:default` for the title its mapping
      gives.
    * `limits`: `{low, high}`, the values it spans whatever the data, `nil` at an end the data
      decides. A value outside them takes the colour of the bin at the nearer end. With neither
      end given and its breaks the default, the limits are the data's range widened so the end
      bins are as wide as their neighbours: from the lowest break inside the range less the step
      to the next, to the highest plus the step from the one before; with one break inside, so
      it is the middle, from it less its distance to the further end of the range to it plus the
      same; with none inside, not widened, its ends its breaks, and a range of one value widened
      by 0.05 either side first.
    * `breaks`: the values its bins are cut at, beside the limits: a list, those inside the
      limits kept, in the order given; `:none` for one bin; or `:default` for about `n_breaks`,
      chosen as `nice_breaks` says on the limits, those at either end of the data's range left
      out where the limits are widened.
    * `n_breaks`: how many default breaks are wanted, 5 unless given; nice breaks may number a
      few more or fewer.
    * `nice_breaks`: `true` for default breaks chosen to be round numbers, as a continuous
      scale's are, `n_breaks` of them wanted, 2 or more; `false` for `n_breaks` breaks spaced
      evenly between the ends of the limits, 1 or more.
    * `labels`: a label for each break: a list, one for each of its given breaks, or of its
      default ones, a break left out taking its label with it; a function handed every break
      kept, that returns their labels; `:none` for none; or `:default`, each written as a
      continuous scale writes a number.
    * `right`: where a value on a break falls: `true` in the bin below it, `false` in the bin
      above; the lowest value is in the lowest bin, and the highest in the highest.
    * `show_limits`: `true` to have colour steps label the ends of the bar with the limits,
      written by its `labels` as its breaks are, unless a break is already there; `false` for
      the breaks alone. A legend shows the breaks alone either way.
  """

  # Use it through `Giggly.Scale`: ggplot2's `ScaleBinned` for colour and fill.
  #
  # Its breaks and its widened limits are worked out from the trained range and the options each
  # time they are read (`breaks/1`, `limits/1`), never stored: R's `get_breaks()` writes them into
  # the scale when it first runs, which happens before the scale maps only when a guide asks first,
  # so the limits it maps with depend on the guide; here they are the widened limits always, R's
  # answer with a guide drawn (design-log §4, the entry beginning "A binned scale's breaks and
  # limits").
  #
  # Mapping is R's `ScaleBinned$map()`: each value squished into the limits (`oob = squish`,
  # `Scales.Bounds.squish/2`), placed in them by the rescaler, then cut at the breaks' places with
  # the limits' as the outer edges, R's `cut(include.lowest = TRUE, right)`; a bin's colour is the
  # palette's for the bins' count, `pal_binned()`, or the continuous palette's at its middle. Given
  # breaks outside the limits are left out, where R cuts at them too and gives a bin beyond the
  # limits, whose middle no gradient colours, so a value on the limit there drew as missing. One
  # bin colours every value but a missing one, which R's single colour, recycled, colours too.

  alias Scales.{Bounds, DataRange, Palette, Transform}

  # Every field's default is `scale_colour_binned()`'s before it has seen any data: the gradient
  # from `#132B43` to `#56B1F7`, places between the limits' ends, grey50 for a missing value,
  # colour steps, and every option the default, five nice breaks wanted, a value on a break in the
  # bin below it, and the limits not shown.
  defstruct range: :none,
            palette: {:gradient, ["#132B43", "#56B1F7"]},
            rescaler: :rescale,
            na_value: "#7F7F7F",
            guide: :colorsteps,
            name: :default,
            limits: {nil, nil},
            breaks: :default,
            labels: :default,
            n_breaks: 5,
            nice_breaks: true,
            right: true,
            show_limits: false

  @type t :: %__MODULE__{
          range: :none | {number(), number()},
          palette: {:binned, Palette.t()} | Palette.t(),
          rescaler: :rescale | {:mid, number()},
          na_value: String.t() | :none,
          guide: :colorsteps | :legend | :none,
          name: :default | :none | String.t(),
          limits: {number() | nil, number() | nil},
          breaks: :default | :none | [number()],
          labels: :default | :none | [String.t()] | ([float()] -> [String.t()]),
          n_breaks: pos_integer(),
          nice_breaks: boolean(),
          right: boolean(),
          show_limits: boolean()
        }

  # The scale widened to cover the finite numbers in `values`, as a continuous scale's is.
  @doc false
  @spec train(t(), list()) :: t()
  def train(%__MODULE__{range: range} = scale, values) do
    %{scale | range: DataRange.train_continuous(range, values)}
  end

  # The scale's limits as floats, R's doubles: each end given, else its trained range's, as R's
  # `get_limits()`, the two sorted when both are given; widened, where neither end is given and
  # its breaks are the default, as R's `get_breaks()` widens them; `:none` where an end has
  # neither, before the scale has seen any data.
  @doc false
  @spec limits(t()) :: :none | {float(), float()}
  def limits(%__MODULE__{} = scale) do
    {_breaks, limits} = resolved(scale)
    limits
  end

  # The scale's breaks, each a float and its index among the breaks it was chosen from, its given
  # breaks or its default ones, in their order: those given inside its limits (`limits/1`), ends
  # included; its default breaks inside its limits, less those at the trained range's ends where
  # the limits are widened, or, for a range of one value, the widened limits; none for
  # `breaks: :none` and before it has limits.
  @doc false
  @spec breaks(t()) :: [{float(), non_neg_integer()}]
  def breaks(%__MODULE__{} = scale) do
    {breaks, _limits} = resolved(scale)
    breaks
  end

  # Each value's colour: the colour of the bin it falls in once squished into the limits, or the
  # scale's `na_value` for a missing value, one not a finite number, or one whose bin the palette
  # gives no colour; every value the `na_value` before the scale has limits.
  @doc false
  @spec map(t(), list()) :: list()
  def map(%__MODULE__{na_value: na_value} = scale, values) do
    case resolved(scale) do
      {_breaks, :none} ->
        Enum.map(values, fn _missing -> na_value end)

      {breaks, limits} ->
        binned(scale, values, breaks, limits)
    end
  end

  defp binned(%__MODULE__{rescaler: rescaler, na_value: na_value} = scale, values, breaks, limits) do
    {low, high} = limits

    # The edges sorted and each once, R's `sort(unique())`, which counts a negative zero as zero,
    # as `-0.0 + 0.0` is.
    edges =
      breaks
      |> Enum.map(fn {break, _index} -> break end)
      |> then(fn inner -> [low, high | inner] end)
      |> Enum.sort()
      |> Enum.dedup_by(fn edge -> edge + 0.0 end)
      |> rescaled(limits, rescaler)

    places =
      values
      |> Bounds.squish(limits)
      |> Enum.map(fn value -> if is_number(value), do: value end)
      |> rescaled(limits, rescaler)

    {bins, middles} = cut(places, edges, scale.right)

    colors =
      scale.palette
      |> bin_colors(middles)
      |> List.to_tuple()

    Enum.map(bins, fn bin ->
      if is_nil(bin), do: na_value, else: elem(colors, bin - 1) || na_value
    end)
  end

  # The breaks and the limits, worked out from the trained range and the options as R's
  # `get_limits()` and `get_breaks()` work them out.
  defp resolved(%__MODULE__{} = scale), do: resolved(scale, given_limits(scale))

  defp resolved(_scale, :none), do: {[], :none}
  defp resolved(%__MODULE__{breaks: :none}, limits), do: {[], limits}

  defp resolved(%__MODULE__{breaks: given}, limits) when is_list(given) do
    breaks =
      given
      |> Enum.map(fn break -> break / 1 end)
      |> indexed_inside(limits)

    {breaks, limits}
  end

  defp resolved(%__MODULE__{breaks: :default, limits: {nil, nil}} = scale, limits),
    do: widened(scale, limits)

  defp resolved(%__MODULE__{breaks: :default} = scale, limits) do
    breaks =
      scale
      |> default_breaks(limits)
      |> indexed_inside(limits)

    {breaks, limits}
  end

  # Each end given, else the trained range's, as floats; both given, sorted.
  defp given_limits(%__MODULE__{limits: {low, high}}) when is_number(low) and is_number(high),
    do: {min(low, high) / 1, max(low, high) / 1}

  defp given_limits(%__MODULE__{range: :none}), do: :none

  defp given_limits(%__MODULE__{limits: {low, high}, range: {range_low, range_high}}),
    do: {(low || range_low) / 1, (high || range_high) / 1}

  # The default breaks on the limits sorted, as R sorts them before breaking them: nice ones, the
  # identity's with `n_breaks` wanted, or `n_breaks` spaced evenly between the ends, R's
  # `seq(low, high, length.out = n_breaks + 2)` less its first and last.
  defp default_breaks(%__MODULE__{nice_breaks: true, n_breaks: wanted}, {low, high}),
    do: Transform.breaks(:identity, {min(low, high), max(low, high)}, n: wanted)

  defp default_breaks(%__MODULE__{nice_breaks: false, n_breaks: wanted}, {low, high}) do
    {min(low, high), max(low, high)}
    |> Palette.spread(wanted + 2)
    |> Enum.slice(1..wanted//1)
  end

  # The default breaks strictly inside the trained range, and the range widened, R's
  # `get_breaks()` with no limits given: with two or more breaks, so the end bins are as wide as
  # their neighbours; with one, to that break less and plus its distance to the further end; with
  # none, not widened but for a range of one value, whose breaks all fall on it, widened by 0.05
  # either side, and its ends its breaks.
  defp widened(scale, {low, high} = range) do
    inner =
      scale
      |> default_breaks(range)
      |> Enum.filter(fn break -> break > low and break < high end)

    case inner do
      [first, second | _more] ->
        [last, before_last | _fewer] = Enum.reverse(inner)
        {indexed(inner), {first + (first - second), last + (last - before_last)}}

      [break] ->
        bin = max(break - low, high - break)
        {indexed(inner), {break - bin, break + bin}}

      [] ->
        {widened_low, widened_high} = widened = widened_ends(range)
        {indexed([widened_low, widened_high]), widened}
    end
  end

  defp widened_ends({low, high} = range) do
    if Bounds.zero_range?(range), do: {low - 0.05, high + 0.05}, else: range
  end

  defp indexed_inside(breaks, {low, high}) do
    breaks
    |> indexed()
    |> Enum.filter(fn {break, _index} -> break >= min(low, high) and break <= max(low, high) end)
  end

  defp indexed(breaks), do: Enum.with_index(breaks)

  defp rescaled(values, limits, :rescale), do: Bounds.rescale(values, limits, {0, 1})

  defp rescaled(values, limits, {:mid, midpoint}),
    do: Bounds.rescale_mid(values, limits, {0, 1}, midpoint)

  # Each place's bin, counting from 1, and each bin's middle, R's `cut()` with `include.lowest`: a
  # place on an edge in the bin below it where `right`, else above, the lowest edge in the first
  # bin and the highest in the last; a `nil` place in none. A single edge, limits of zero width
  # with no break between, is one bin with its middle at 0.5.
  defp cut(places, [_edge], _right),
    do: {Enum.map(places, fn place -> if is_number(place), do: 1 end), [0.5]}

  defp cut(places, edges, right) do
    middles =
      edges
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [low, high] -> high - (high - low) / 2 end)

    {Enum.map(places, fn place -> bin(place, edges, right) end), middles}
  end

  defp bin(nil, _edges, _right), do: nil

  defp bin(place, edges, true) do
    edges
    |> Enum.count(fn edge -> edge < place end)
    |> max(1)
  end

  defp bin(place, edges, false) do
    edges
    |> Enum.count(fn edge -> edge <= place end)
    |> min(length(edges) - 1)
  end

  # Each bin's colour: a discrete palette's colours for as many levels as there are bins, the
  # first for the lowest, as ggplot2's `pal_binned()` gives them, refused where it holds fewer, as
  # a brewer palette does past its largest set, which R gives `NA` with a warning and leaves
  # undrawn; or a continuous palette's at each bin's middle.
  defp bin_colors({:binned, palette}, middles) do
    count = length(middles)
    colors = Palette.discrete(palette, count)
    held = Enum.count(colors, fn color -> not is_nil(color) end)

    if held < count do
      raise ArgumentError,
            "a binned scale's palette has #{held} colours, too few for its #{count} bins; " <>
              "give the scale fewer breaks"
    end

    colors
  end

  defp bin_colors(palette, middles), do: Palette.continuous(palette, middles)
end
