defmodule Giggly.Stat.KernelDensity do
  @moduledoc false

  # A kernel density estimate for each group of a layer's rows, ggplot2's `compute_density()`,
  # which a density's stat (`Giggly.Stat.Density`) and a violin's (`Giggly.Stat.Ydensity`) compute
  # with: for each group in each panel, `n` rows evenly spaced across a span, each its place `x`,
  # its `density`, `scaled` and `ndensity`, the density over the group's greatest, `count`, the
  # density times the group's rows inside the bounds, `wdensity`, the density times the weights'
  # total, and the rows `n`. It estimates along x: a stat estimating along another column renames
  # it x first.
  #
  # The span is the panel's axis short of its widening (`{:axis, along}`, each panel's axis by
  # panel), as a density's untrimmed curve spans it, or the group's own extent widened by a number
  # of the rule's bandwidths, before `adjust`, either end (`{:group, bandwidths}`), as a trimmed
  # density spans it at 0 and a violin's untrimmed curve at 3.
  #
  # Its bandwidth, the kernel's standard deviation, is a number, or a rule worked out from the
  # group's rows, unweighted, those inside the bounds (`:inside`), as `compute_density()` works it
  # out, or all of them (`:all`), as a violin's stat works it out before handing it over:
  # Silverman's (`:nrd0`), 0.9 times the lesser of the standard deviation and the interquartile
  # range over 1.34, or failing that the standard deviation, the first row's magnitude or 1, times
  # the rows to the power -0.2; or Scott's variation (`:nrd`), 1.06 times the lesser of the two,
  # times the rows to the power -1/5, as R's `bw.nrd0()` and `bw.nrd()`; then times `adjust`. Its
  # kernel is one of R's seven, each scaled so its standard deviation is the bandwidth.
  #
  # R's `density()` method, as its documentation gives it: the weighted rows spread linearly over
  # a grid of evenly spaced points, at least 512, a power of two past that, running from four
  # bandwidths below the curve's first place to four above its last, each row's share split
  # between the two points either side of it by how near it is to each, every row landing inside
  # the grid; those totals, padded with as many zeros, convolved with the kernel at each distance
  # along the grid, wrapping round, by the fast Fourier transform (`Giggly.Tensor`); what is left
  # below 0 by round-off raised to 0; and the curve read at each of its places by R's `approx()`
  # formula (`Giggly.Stat.Curve`). Each row's share is its weight over the group's total, `1 /
  # rows` unweighted.
  #
  # With a finite bound in `bounds`, the rows outside them are left out and the rest's shares
  # divided by what they leave, where that is above 0; the curve is worked out across the span
  # widened by its own width beyond each finite bound, on `n` times one more than the finite
  # bounds' count of places, and each part of it beyond a bound folded back inside, added to
  # what is there, read on as many places from the lower bound or the curve's start, whichever is
  # higher, to the upper bound or its end, as ggplot2's `reflect_density()` does.
  #
  # The rows it is handed are the ones to estimate from: the stat leaves out those it drops first.
  # A group of fewer than two rows inside the bounds is one row, every computed column missing,
  # as ggplot2 gives one. Where R's `density()` fails, ggplot2 computes nothing for the whole
  # panel, and warns, which a pure pipeline cannot, and so a panel is `:dropped`: a share missing,
  # infinite or below 0, which a missing, infinite or negative weight makes, or a group's weights
  # totalling 0; a bandwidth not finite and above 0, a rule's for rows all at one x; or, with rows
  # outside the bounds, the shares inside them totalling a missing value. A weight that is not a
  # number is refused (`check_weight/1`).
  #
  # The frame does what scales with the rows (`Giggly.DataFrame`), in four passes, each summarised
  # to a row a group or a grid point (design-log §4, the entry beginning "Smoothing and densities
  # compute over the rows"): each group's weights' total, rows and extent, and with `:all` the
  # bandwidth's count, variance, quartiles and first x; each row's share, and each group's rows,
  # shares and spread inside the bounds, and the bandwidth's figures there; each row's place on
  # its group's grid, `floor` of it its grid point, and the two parts of its share either side;
  # and the parts summed at each grid point of each group, lower and upper apart, in row order, as
  # R's binning adds them, then added together. The grid, the kernel, the convolution and the
  # curve are worked out on those totals. Its values are R's within 1e-12 of the largest magnitude
  # a group's column holds, its x R's to the last digit (design-log §4, the entry beginning "A
  # stat's values reached by another route").

  alias Giggly.{DataFrame, Tensor}
  alias Giggly.DataFrame.Arithmetic
  alias Giggly.Stat.Curve

  @typedoc "One of R's seven kernels, each scaled so its standard deviation is the bandwidth."
  @type kernel ::
          :gaussian
          | :epanechnikov
          | :rectangular
          | :triangular
          | :biweight
          | :cosine
          | :optcosine

  @typedoc "How the estimate is worked out, as `compute_density()` and its caller take it."
  @type settings :: %{
          bandwidth: :nrd0 | :nrd | float(),
          bandwidth_rows: :inside | :all,
          adjust: float(),
          kernel: kernel(),
          n: pos_integer(),
          span: {:axis, %{optional(term()) => Giggly.Stat.axis()}} | {:group, number()},
          bounds: {float() | :neg_infinity, float() | :infinity}
        }

  @typedoc "A group's key in the layer, its panel and group."
  @type key :: {term(), term()}

  @typedoc "A row of a group's curve, each computed column by name."
  @type row :: %{
          x: float() | nil,
          density: float() | nil,
          scaled: float() | nil,
          ndensity: float() | nil,
          count: float() | nil,
          wdensity: float() | nil,
          n: non_neg_integer() | nil
        }

  # The fewest points R's `density()` spreads its rows over.
  @least_points 512

  # How many bandwidths beyond the curve's first and last places R's grid reaches, its `ext`.
  @reach 4

  # 1 over the square root of 2π, R's `M_1_SQRT_2PI`, the normal density's height at its mean.
  @normal_height 0.398_942_280_401_432_7

  # The aggregates the bandwidth's rule reads, of the rows it is worked out from.
  @bandwidth_figures [
    spread: {:variance, [:x]},
    lower_quartile: {:quantile, [:x], probability: 0.25},
    upper_quartile: {:quantile, [:x], probability: 0.75},
    first: {:first, [:x]}
  ]

  # A weight is spread over the grid, so it must hold numbers, as binning's must.
  @doc false
  @spec check_weight(DataFrame.t()) :: :ok
  def check_weight(frame) do
    case DataFrame.dtypes(frame) do
      %{weight: dtype} when dtype not in [:integer, :float, :null] ->
        raise ArgumentError,
              "a density spreads each row's weight over its grid, so a weight must be a " <>
                "number, but the layer's weight is a #{inspect(dtype)} column"

      _numbers_or_no_weight ->
        :ok
    end
  end

  # Each group's curve of `rows`, a table of `panel`, `group`, `x` and an optional `weight`, by
  # `{panel, group}` in the groups' order: `:dropped` for every group of a panel whose estimate
  # fails, else its rows.
  @doc false
  @spec curves(DataFrame.t(), settings()) :: [{key(), :dropped | [row()]}]
  def curves(rows, settings) do
    weighted = weighted(rows)
    figures = if settings.bandwidth_rows == :all, do: @bandwidth_figures, else: []

    totals =
      DataFrame.summarise(
        weighted,
        [:panel, :group],
        Enum.concat(
          [
            total: {:sum, [:weight]},
            rows: {:count, [:x]},
            x_low: {:min, [:x]},
            x_high: {:max, [:x]}
          ],
          figures
        )
      )

    shared =
      weighted
      |> DataFrame.join(
        DataFrame.select(totals, panel: :panel, group: :group, total: :total),
        [:panel, :group]
      )
      |> DataFrame.mutate(share: {:/, [:weight, :total]})
      |> inside_bounds(settings.bounds)

    inside =
      DataFrame.summarise(
        shared,
        [:panel, :group],
        Enum.concat(
          [
            rows: {:count, [:x]},
            share_total: {:sum, [:share]},
            shares: {:count, [:share]},
            share_low: {:min, [:share]},
            share_high: {:max, [:share]}
          ],
          @bandwidth_figures
        )
      )

    group_names = Enum.concat([:total, :rows, :x_low, :x_high], Keyword.keys(figures))
    plans = plans(totals, group_names, inside, settings)
    grid_totals = grid_totals(shared, inside, plans)

    totals
    |> rows_by_group([])
    |> Enum.map(fn {key, _group} ->
      case Map.fetch!(plans, key) do
        :dropped -> {key, :dropped}
        plan -> {key, curve(plan, Map.get(grid_totals, key, []), settings)}
      end
    end)
  end

  # A summarised table's rows by `{panel, group}`, each a map of the columns `names`.
  @doc false
  @spec rows_by_group(DataFrame.t(), [DataFrame.name()]) :: [{key(), map()}]
  def rows_by_group(frame, names) do
    columns = Enum.map([:panel, :group | names], fn name -> DataFrame.pull(frame, name) end)

    Enum.zip_with(columns, fn [panel, group | values] ->
      {{panel, group}, Map.new(Enum.zip(names, values))}
    end)
  end

  # The rows with each one's weight, 1 where the layer maps none, so each share is 1 over the
  # group's rows, as R's `density()` weighs each row.
  defp weighted(frame) do
    if :weight in DataFrame.names(frame),
      do: frame,
      else: DataFrame.mutate(frame, weight: 1.0)
  end

  # The rows inside the bounds, a row on one included, as ggplot2's `fit_data_to_bounds()` keeps
  # them; every row where neither bound is finite.
  defp inside_bounds(frame, {low, high}) do
    above_low = if is_number(low), do: [{:not, [{:<, [:x, low]}]}], else: []
    below_high = if is_number(high), do: [{:not, [{:>, [:x, high]}]}], else: []
    tests = Enum.concat(above_low, below_high)

    case tests do
      [] -> frame
      [test] -> DataFrame.filter(frame, test)
      [low_test, high_test] -> DataFrame.filter(frame, {:and, [low_test, high_test]})
    end
  end

  # What each group, by `{panel, group}`, comes to, in ggplot2's `compute_density()`'s order:
  # nothing for its whole panel where any group of the panel fails (`:dropped`), as ggplot2
  # computes nothing for a panel whose computing fails; else one row of missing values for one
  # of fewer than two rows inside the bounds (`:too_few`); else its estimate's plan.
  defp plans(totals, group_names, inside, settings) do
    inside_groups =
      inside
      |> rows_by_group([
        :rows,
        :share_total,
        :shares,
        :share_low,
        :share_high | Keyword.keys(@bandwidth_figures)
      ])
      |> Map.new()

    planned =
      totals
      |> rows_by_group(group_names)
      |> Map.new(fn {{panel, _group} = key, group} ->
        {key, plan(group, Map.get(inside_groups, key), settings, panel)}
      end)

    failed = for {{panel, _group}, :fails} <- planned, into: MapSet.new(), do: panel

    Map.new(planned, fn {{panel, _group} = key, plan} ->
      if panel in failed, do: {key, :dropped}, else: {key, plan}
    end)
  end

  # A group none of whose rows is inside the bounds has no shares to total, so it comes to one
  # row of missing values, as ggplot2's does.
  defp plan(_group, nil, _settings, _panel), do: :too_few

  defp plan(group, inside, settings, panel) do
    outside = inside.rows < group.rows

    cond do
      outside and inside.share_total in [nil, :nan] -> :fails
      inside.rows < 2 -> :too_few
      true -> estimate(group, inside, settings, panel, outside)
    end
  end

  # The plan of a group's estimate, or `:fails` where its bandwidth is not finite and above 0, or
  # its shares are not all finite and 0 or more.
  defp estimate(group, inside, settings, panel, outside) do
    source = if settings.bandwidth_rows == :all, do: group, else: inside
    rule = bandwidth(settings.bandwidth, source)
    bandwidth = Arithmetic.multiply(settings.adjust, rule)

    if positive?(rule) and positive?(bandwidth) and shares?(inside),
      do: estimate_plan(group, inside, settings, panel, outside, {rule, bandwidth}),
      else: :fails
  end

  defp estimate_plan(group, inside, settings, panel, outside, {rule, bandwidth}) do
    {low_bound, high_bound} = settings.bounds
    finite_bounds = Enum.count([low_bound, high_bound], &is_number/1)
    points = settings.n * (finite_bounds + 1)
    grid = grid_points(points)
    {from, to} = extent(settings.span, group, panel, rule)
    width = to - from
    from = if is_number(low_bound), do: from - width, else: from
    to = if is_number(high_bound), do: to + width, else: to
    low = from - @reach * bandwidth
    high = to + @reach * bandwidth

    %{
      points: points,
      grid: grid,
      from: from,
      to: to,
      bandwidth: bandwidth,
      low: low,
      high: high,
      step: (high - low) / (grid - 1),
      divisor: divisor(outside, inside.share_total),
      rows: inside.rows,
      weights_total: weights_total(outside, inside.share_total, group.total)
    }
  end

  # The bandwidth of a group's rows: a number given, or a rule's, as R's `bw.nrd0()` and
  # `bw.nrd()` work it out, a missing or infinite value where the rows give one.
  defp bandwidth(given, _source) when is_float(given), do: given

  defp bandwidth(:nrd0, source) do
    deviation = square_root(source.spread)
    lesser = lesser(deviation, interquartile(source))

    least =
      cond do
        lesser != 0 -> lesser
        deviation != 0 -> deviation
        source.first != 0 -> abs(source.first)
        true -> 1
      end

    0.9
    |> Arithmetic.multiply(least)
    |> Arithmetic.multiply(:math.pow(source.rows, -0.2))
  end

  defp bandwidth(:nrd, source) do
    lesser = lesser(square_root(source.spread), interquartile(source))

    1.06
    |> Arithmetic.multiply(lesser)
    |> Arithmetic.multiply(:math.pow(source.rows, -1 / 5))
  end

  # The interquartile range over 1.34, a normal distribution's in standard deviations.
  defp interquartile(source) do
    source.upper_quartile
    |> Arithmetic.subtract(source.lower_quartile)
    |> Arithmetic.divide(1.34)
  end

  defp square_root(value) when is_number(value), do: :math.sqrt(value)
  defp square_root(value), do: value

  # The lesser of two numbers, as R's `min()` takes it, an infinity above every number.
  defp lesser(left, right) do
    if Arithmetic.sort_key(right) < Arithmetic.sort_key(left), do: right, else: left
  end

  defp positive?(value), do: is_number(value) and value > 0

  # Whether a group's shares inside the bounds are all finite and 0 or more, as R's `density()`
  # requires of its weights: dividing them by what they total inside, a finite number above 0,
  # changes neither.
  defp shares?(inside) do
    inside.shares == inside.rows and is_number(inside.share_low) and inside.share_low >= 0 and
      is_number(inside.share_high)
  end

  # How many points R's `density()` spreads a curve of `points` places over: at least 512, and
  # past that the least power of two holding them.
  defp grid_points(points) when points <= @least_points, do: @least_points

  defp grid_points(points) do
    exponent =
      points
      |> :math.log2()
      |> Float.ceil()
      |> trunc()

    2 ** exponent
  end

  # The extent a group's curve spans: the panel's axis short of its widening, as ggplot2's
  # `dimension()`, or the group's own widened by a number of the rule's bandwidths either end.
  defp extent({:axis, along}, _group, panel, _rule), do: Map.fetch!(along, panel).limits

  defp extent({:group, bandwidths}, group, _panel, rule),
    do: {group.x_low - bandwidths * rule, group.x_high + bandwidths * rule}

  # What a group's shares inside the bounds are divided by: what they total, where some rows
  # are outside and that is above 0, else 1, which leaves each as it is.
  defp divisor(true, share_total) when is_number(share_total) and share_total > 0,
    do: share_total

  defp divisor(_outside, _share_total), do: 1.0

  # The weights' total a group's `wdensity` is the density times: its rows' weights', times
  # what its shares total inside the bounds where some rows are outside.
  defp weights_total(true, share_total, total), do: Arithmetic.multiply(share_total, total)
  defp weights_total(false, _share_total, total), do: total

  # Each estimated group's totals at its grid points, by `{panel, group}`, each `{point, lower,
  # upper}` ascending: of the parts of its rows' shares either side of each row's place on its
  # grid, the lower at the point below it and the upper there too, to be added to the point
  # above, each summed in row order, as R's binning adds them.
  defp grid_totals(shared, inside, plans) do
    keyed =
      inside
      |> rows_by_group([])
      |> Enum.map(fn {key, _group} -> Map.fetch!(plans, key) end)

    grids =
      inside
      |> DataFrame.select(panel: :panel, group: :group)
      |> DataFrame.put(:grid_low, Enum.map(keyed, fn plan -> plan_value(plan, :low) end))
      |> DataFrame.put(:grid_step, Enum.map(keyed, fn plan -> plan_value(plan, :step) end))
      |> DataFrame.put(:divisor, Enum.map(keyed, fn plan -> plan_value(plan, :divisor) end))

    summed =
      shared
      |> DataFrame.join(grids, [:panel, :group])
      |> DataFrame.filter({:is_finite, [:grid_low]})
      |> DataFrame.mutate(place: {:/, [{:-, [:x, :grid_low]}, :grid_step]})
      |> DataFrame.mutate(point: {:floor, [:place]})
      |> DataFrame.mutate(fraction: {:-, [:place, :point]}, portion: {:/, [:share, :divisor]})
      |> DataFrame.mutate(
        lower: {:*, [:portion, {:-, [1, :fraction]}]},
        upper: {:*, [:portion, :fraction]}
      )
      |> DataFrame.summarise([:panel, :group, :point],
        lower: {:sum, [:lower], summation: :plain},
        upper: {:sum, [:upper], summation: :plain}
      )

    summed
    |> rows_by_group([:point, :lower, :upper])
    |> Enum.group_by(
      fn {key, _totals} -> key end,
      fn {_key, totals} -> {trunc(totals.point), totals.lower, totals.upper} end
    )
  end

  defp plan_value(plan, name) when is_map(plan), do: Map.fetch!(plan, name)
  defp plan_value(_plan, _name), do: nil

  # A group's curve: one row of missing values for too few rows, else its estimate at each of
  # its places, each row its place, density, scaled densities, count, weighted density and rows.
  defp curve(:too_few, _totals, _settings) do
    [%{x: nil, density: nil, scaled: nil, ndensity: nil, count: nil, wdensity: nil, n: nil}]
  end

  defp curve(plan, totals, settings) do
    places =
      plan.from
      |> Curve.places(plan.to, plan.points)
      |> Enum.map(fn place -> place / 1 end)

    estimates = convolved(plan, totals, settings)

    estimated =
      plan
      |> grid()
      |> Enum.zip(estimates)
      |> Curve.interpolate(places)

    {places, densities} = reflected(places, estimated, plan, settings.bounds)
    peak = Enum.max(densities)

    Enum.zip_with(places, densities, fn place, density ->
      scaled = Arithmetic.divide(density, peak)

      %{
        x: place,
        density: density,
        scaled: scaled,
        ndensity: scaled,
        count: Arithmetic.multiply(density, plan.rows),
        wdensity: Arithmetic.multiply(density, plan.weights_total),
        n: plan.rows
      }
    end)
  end

  # The grid's points, evenly spaced from its low end to its high.
  defp grid(plan), do: Curve.places(plan.low, plan.high, plan.grid)

  # The estimate at each grid point: the totals at the grid's points, padded with as many
  # zeros, convolved with the kernel at each distance along the padded grid, wrapping round, and
  # raised to 0 where round-off leaves it below, as R's `density()` does.
  defp convolved(plan, totals, settings) do
    slots = 2 * plan.grid

    signal =
      totals
      |> Enum.reduce(%{}, fn {point, lower, upper}, signal ->
        signal
        |> added(point, lower)
        |> added(point + 1, upper)
      end)
      |> then(fn signal ->
        Enum.map(0..(slots - 1), fn slot -> Map.get(signal, slot, 0.0) end)
      end)

    kernel =
      plan
      |> distances()
      |> Enum.map(fn distance -> kernel(settings.kernel, distance, plan.bandwidth) end)

    signal
    |> Tensor.circular_correlation(kernel)
    |> Enum.take(plan.grid)
    |> Enum.map(fn value -> if value < 0, do: 0.0, else: value end)
  end

  # A part of a share added at a grid point. Every row's place is inside the grid, which runs
  # four bandwidths past the curve's places either end, so its parts land on the grid's points.
  defp added(signal, point, part),
    do: Map.update(signal, point, part, fn total -> total + part end)

  # The distance from the first point of the padded grid to each, wrapping round: R's `kords`,
  # 0 up to just past the grid's span over its first half and back down over its second, the
  # distance from the first grid point the shorter way. R gives the second half's as negatives,
  # which every kernel, symmetric, reads alike.
  defp distances(plan) do
    slots = 2 * plan.grid
    span = (slots - 1) / (plan.grid - 1) * (plan.high - plan.low)

    upward =
      0.0
      |> Curve.places(span, slots)
      |> List.to_tuple()

    Enum.map(0..(slots - 1), fn index ->
      if index <= plan.grid, do: elem(upward, index), else: elem(upward, slots - index)
    end)
  end

  # The kernel's height at `distance` from its middle, scaled so its standard deviation is the
  # bandwidth, as R's `density()` writes each.
  defp kernel(:gaussian, distance, bandwidth) do
    standardised = distance / bandwidth
    @normal_height * :math.exp(-0.5 * standardised * standardised) / bandwidth
  end

  defp kernel(:rectangular, distance, bandwidth) do
    reach = bandwidth * :math.sqrt(3)
    if abs(distance) < reach, do: 0.5 / reach, else: 0.0
  end

  defp kernel(:triangular, distance, bandwidth) do
    reach = bandwidth * :math.sqrt(6)
    if abs(distance) < reach, do: (1 - abs(distance) / reach) / reach, else: 0.0
  end

  defp kernel(:epanechnikov, distance, bandwidth) do
    reach = bandwidth * :math.sqrt(5)
    ratio = abs(distance) / reach
    if abs(distance) < reach, do: 3 / 4 * (1 - ratio * ratio) / reach, else: 0.0
  end

  defp kernel(:biweight, distance, bandwidth) do
    reach = bandwidth * :math.sqrt(7)
    ratio = abs(distance) / reach
    lessened = 1 - ratio * ratio
    if abs(distance) < reach, do: 15 / 16 * (lessened * lessened) / reach, else: 0.0
  end

  defp kernel(:cosine, distance, bandwidth) do
    reach = bandwidth / :math.sqrt(1 / 3 - 2 / (:math.pi() * :math.pi()))

    if abs(distance) < reach,
      do: (1 + :math.cos(:math.pi() * distance / reach)) / (2 * reach),
      else: 0.0
  end

  defp kernel(:optcosine, distance, bandwidth) do
    reach = bandwidth / :math.sqrt(1 - 8 / (:math.pi() * :math.pi()))

    if abs(distance) < reach,
      do: :math.pi() / 4 * :math.cos(:math.pi() * distance / (2 * reach)) / reach,
      else: 0.0
  end

  # A curve with a finite bound folded back inside it: read on as many places from the lower
  # bound or its start, whichever is higher, to the upper bound or its end, whichever is lower,
  # its height there plus its heights at each place's reflection in each finite bound, 0 beyond
  # its ends, as ggplot2's `reflect_density()` reads it, so a curve with no finite bound is read
  # at its own places, each its height, and nothing added.
  defp reflected(places, estimated, plan, {low, high}) do
    knots = Enum.zip(places, estimated)
    left = if is_number(low), do: max(plan.from, low), else: plan.from
    right = if is_number(high), do: min(plan.to, high), else: plan.to

    folded_places =
      left
      |> Curve.places(right, plan.points)
      |> Enum.map(fn place -> place / 1 end)

    inside = heights(knots, folded_places)
    from_low = reflection(knots, folded_places, low)
    from_high = reflection(knots, folded_places, high)

    heights =
      Enum.zip_with([inside, from_low, from_high], fn [height, low_part, high_part] ->
        height + low_part + high_part
      end)

    {folded_places, heights}
  end

  # The curve's heights at places ascending, 0 beyond its ends, as R's `approxfun(yleft = 0,
  # yright = 0)` reads it.
  defp heights(knots, places) do
    knots
    |> Curve.interpolate(places)
    |> Enum.map(fn height -> height || 0.0 end)
  end

  # The curve's heights at each place's reflection in a bound, `bound + (bound - place)`, 0
  # beyond its ends, and so 0 everywhere for an infinite bound.
  defp reflection(_knots, places, bound) when not is_number(bound),
    do: List.duplicate(0.0, length(places))

  defp reflection(knots, places, bound) do
    reflections =
      places
      |> Enum.map(fn place -> bound + (bound - place) end)
      |> Enum.reverse()

    knots
    |> heights(reflections)
    |> Enum.reverse()
  end
end
