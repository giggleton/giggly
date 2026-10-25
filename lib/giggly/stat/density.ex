defmodule Giggly.Stat.Density do
  @moduledoc false

  # Densities, ggplot2's `stat_density()`, which `geom_density()` computes with: for each group in
  # each panel, in that order, a kernel density estimate, R's `density()`, `n` rows evenly spaced
  # across the panel's axis short of its widening, or across the group's own extent with `trim`,
  # each its place `x`, its `density`, `scaled` and `ndensity`, the density over the group's
  # greatest, `count`, the density times the group's rows, `wdensity`, the density times the
  # weights' total, the rows `n`, and `flipped_aes`. y takes the density by default
  # (`after_stat(density)`), and a mapping's after_stat reads `density`, `count`, `scaled`,
  # `ndensity`, `wdensity` and `n`, the variables ggplot2 documents. It runs along whichever of x
  # and y is mapped, along y with the two swapped and swapped back, as ggplot2's `flip_data()`
  # does. Run it through `Giggly.Stat`.
  #
  # Its bandwidth, the kernel's standard deviation, is a number, or a rule worked out from the
  # group's rows, unweighted: Silverman's (`:nrd0`), 0.9 times the lesser of the standard
  # deviation and the interquartile range over 1.34, or failing that the standard deviation, the
  # first row's magnitude or 1, times the rows to the power -0.2; or Scott's variation (`:nrd`),
  # 1.06 times the lesser of the two, times the rows to the power -1/5, as R's `bw.nrd0()` and
  # `bw.nrd()`; then times `adjust`. Its kernel is one of R's seven, each scaled so its standard
  # deviation is the bandwidth.
  #
  # R's `density()` method, as its documentation gives it: the weighted rows spread linearly over
  # a grid of evenly spaced points, at least 512, a power of two past that, running from four
  # bandwidths below the curve's first place to four above its last, each row's share split
  # between the two points either side of it by how near it is to each, and kept where it lands on
  # the grid; those totals, padded with as many zeros, convolved with the kernel at each distance
  # along the grid, wrapping round, by the fast Fourier transform (`Giggly.Tensor`); what is left
  # below 0 by round-off raised to 0; and the curve read at each of its places by R's `approx()`
  # formula (`Giggly.Stat.Curve`). Each row's share is its weight over the group's total, `1 /
  # rows` unweighted.
  #
  # With a finite bound in `bounds`, the rows outside them are left out and the rest's shares
  # divided by what they leave, where that is above 0; the curve is worked out across the axis
  # widened by its own width beyond each finite bound, on `n` times one more than the finite
  # bounds' count of places, and each part of it beyond a bound folded back inside, added to
  # what is there, read on as many places from the lower bound or the curve's start, whichever is
  # higher, to the upper bound or its end, as ggplot2's `reflect_density()` does.
  #
  # A row missing its x, or at an infinite one, is left out first, as ggplot2's `remove_missing()`
  # drops it. A group of fewer than two rows inside the bounds is one row, every computed column
  # missing, as ggplot2 gives one. Where R's `density()` fails, ggplot2 computes nothing for the
  # whole panel, and warns, which a pure pipeline cannot, and so neither does this stat: a share
  # missing, infinite or below 0, which a missing, infinite or negative weight makes, or a group's
  # weights totalling 0; a bandwidth not finite and above 0, a rule's for rows all at one x; or,
  # with rows outside the bounds, the shares inside them totalling a missing value. A weight that
  # is not a number is refused. A group's constant columns are carried to its rows
  # (`Giggly.Stat.Carry`), counted over the groups given rows.
  #
  # The frame does what scales with the rows (`Giggly.DataFrame`), in four passes, each summarised
  # to a row a group or a grid point (design-log §4, the entry beginning "Smoothing and densities
  # compute over the rows"): each group's weights' total, rows and extent; each row's share, and
  # each group's rows, shares and spread inside the bounds, the bandwidth's count, variance,
  # quartiles and first x; each row's place on its group's grid, `floor` of it its grid point, and
  # the two parts of its share either side; and the parts summed at each grid point of each group,
  # lower and upper apart, in row order, as R's binning adds them, then added together. The grid,
  # the kernel, the convolution and the curve are worked out on those totals. Its values are R's
  # within 1e-12 of the largest magnitude a group's column holds, its x R's to the last digit
  # (design-log §4, the entry beginning "A stat's values reached by another route").

  @enforce_keys [:bandwidth, :adjust, :kernel, :n, :trim, :bounds]
  defstruct @enforce_keys

  @typedoc "One of R's seven kernels, each scaled so its standard deviation is the bandwidth."
  @type kernel ::
          :gaussian
          | :epanechnikov
          | :rectangular
          | :triangular
          | :biweight
          | :cosine
          | :optcosine

  @type t :: %__MODULE__{
          bandwidth: :nrd0 | :nrd | float(),
          adjust: float(),
          kernel: kernel(),
          n: pos_integer(),
          trim: boolean(),
          bounds: {float() | :neg_infinity, float() | :infinity}
        }

  # The aesthetics a layer of densities can use for its estimate, from its own mapping or the
  # plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :weight, :x, :y]

  # The aesthetics a density cannot be computed without: one of x and y, ggplot2's `required_aes =
  # "x|y"`.
  @doc false
  @spec required_aesthetics() :: [[atom()]]
  def required_aesthetics, do: [[:x, :y]]

  # The aesthetics of which a layer of densities maps at most one, since ggplot2's density drops
  # the other and its geom then fails without it.
  @doc false
  @spec exclusive_aesthetics() :: [[atom()]]
  def exclusive_aesthetics, do: [[:x, :y]]

  # The variables a density computes that a mapping's after_stat can read, as ggplot2 documents
  # `stat_density()`'s.
  @doc false
  @spec computed_variables() :: [atom()]
  def computed_variables, do: [:count, :density, :n, :ndensity, :scaled, :wdensity]

  # The aesthetics a density consumes, ggplot2's `dropped_aes`: a weight is spread over the grid.
  @doc false
  @spec dropped_aesthetics() :: [atom()]
  def dropped_aesthetics, do: [:weight]

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.{Aesthetics, DataFrame, Tensor}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Stat.{Carry, Curve}

    # The columns a density writes, in ggplot2's order.
    @computed [:x, :density, :scaled, :ndensity, :count, :wdensity, :n, :flipped_aes]

    # The fewest points R's `density()` spreads its rows over.
    @least_points 512

    # How many bandwidths beyond the curve's first and last places R's grid reaches, its `ext`.
    @reach 4

    # 1 over the square root of 2π, R's `M_1_SQRT_2PI`, the normal density's height at its mean.
    @normal_height 0.398_942_280_401_432_7

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{x: :density, y: :density}

    @impl Giggly.Stat
    def compute_layer(stat, frame, axes) do
      check_weight(frame)
      flipped = :x not in DataFrame.names(frame)
      axis = if flipped, do: :y, else: :x
      along = Map.new(axes, fn {panel, panel_axes} -> {panel, Map.fetch!(panel_axes, axis)} end)

      frame
      |> flip(flipped)
      |> densities(stat, along, flipped)
      |> flip(flipped)
    end

    # A weight is spread over the grid, so it must hold numbers, as binning's must.
    defp check_weight(frame) do
      case DataFrame.dtypes(frame) do
        %{weight: dtype} when dtype not in [:integer, :float, :null] ->
          raise ArgumentError,
                "a density spreads each row's weight over its grid, so a weight must be a " <>
                  "number, but the layer's weight is a #{inspect(dtype)} column"

        _numbers_or_no_weight ->
          :ok
      end
    end

    defp flip(frame, false), do: frame

    defp flip(frame, true) do
      renames =
        frame
        |> DataFrame.names()
        |> Aesthetics.flipped()

      DataFrame.select(frame, renames)
    end

    defp densities(frame, stat, along, flipped) do
      carried =
        frame
        |> DataFrame.names()
        |> Enum.reject(fn name -> name in @computed end)

      rows =
        frame
        |> DataFrame.filter({:is_finite, [:x]})
        |> weighted()

      totals =
        DataFrame.summarise(rows, [:panel, :group],
          total: {:sum, [:weight]},
          rows: {:count, [:x]},
          x_low: {:min, [:x]},
          x_high: {:max, [:x]}
        )

      shared =
        rows
        |> DataFrame.join(
          DataFrame.select(totals, panel: :panel, group: :group, total: :total),
          [:panel, :group]
        )
        |> DataFrame.mutate(share: {:/, [:weight, :total]})
        |> inside_bounds(stat.bounds)

      inside =
        DataFrame.summarise(shared, [:panel, :group],
          rows: {:count, [:x]},
          share_total: {:sum, [:share]},
          shares: {:count, [:share]},
          share_low: {:min, [:share]},
          share_high: {:max, [:share]},
          spread: {:variance, [:x]},
          lower_quartile: {:quantile, [:x], probability: 0.25},
          upper_quartile: {:quantile, [:x], probability: 0.75},
          first: {:first, [:x]}
        )

      plans = plans(totals, inside, stat, along)
      kept_rows = kept_rows(rows, totals, plans)
      constant = Carry.constant_columns(kept_rows, carried)
      firsts = for name <- constant, name not in [:panel, :group], do: {name, {:first, [name]}}
      groups = DataFrame.summarise(kept_rows, [:panel, :group], firsts)
      grid_totals = grid_totals(shared, inside, plans)

      groups
      |> rows_by_group([])
      |> Enum.map(fn {key, _group} ->
        {key, curve(Map.fetch!(plans, key), Map.get(grid_totals, key, []), stat)}
      end)
      |> output(groups, constant, flipped)
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
    defp plans(totals, inside, stat, along) do
      inside_groups =
        inside
        |> rows_by_group([
          :rows,
          :share_total,
          :shares,
          :share_low,
          :share_high,
          :spread,
          :lower_quartile,
          :upper_quartile,
          :first
        ])
        |> Map.new()

      planned =
        totals
        |> rows_by_group([:total, :rows, :x_low, :x_high])
        |> Map.new(fn {{panel, _group} = key, group} ->
          {key, plan(group, Map.get(inside_groups, key), stat, Map.fetch!(along, panel))}
        end)

      failed = for {{panel, _group}, :fails} <- planned, into: MapSet.new(), do: panel

      Map.new(planned, fn {{panel, _group} = key, plan} ->
        if panel in failed, do: {key, :dropped}, else: {key, plan}
      end)
    end

    # A group none of whose rows is inside the bounds has no shares to total, so it comes to one
    # row of missing values, as ggplot2's does.
    defp plan(_group, nil, _stat, _axis), do: :too_few

    defp plan(group, inside, stat, axis) do
      outside = inside.rows < group.rows

      cond do
        outside and inside.share_total in [nil, :nan] -> :fails
        inside.rows < 2 -> :too_few
        true -> estimate(group, inside, stat, axis, outside)
      end
    end

    # The plan of a group's estimate, or `:fails` where its bandwidth is not finite and above 0, or
    # its shares are not all finite and 0 or more.
    defp estimate(group, inside, stat, axis, outside) do
      rule = bandwidth(stat.bandwidth, inside)
      bandwidth = Arithmetic.multiply(stat.adjust, rule)

      if positive?(rule) and positive?(bandwidth) and shares?(inside),
        do: estimate_plan(group, inside, stat, axis, outside, bandwidth),
        else: :fails
    end

    defp estimate_plan(group, inside, stat, axis, outside, bandwidth) do
      {low_bound, high_bound} = stat.bounds
      finite_bounds = Enum.count([low_bound, high_bound], &is_number/1)
      points = stat.n * (finite_bounds + 1)
      grid = grid_points(points)
      {from, to} = extent(stat.trim, group, axis)
      {from, to} = {min(from, to), max(from, to)}
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

    # The bandwidth of a group's rows inside the bounds: a number given, or a rule's, as R's
    # `bw.nrd0()` and `bw.nrd()` work it out, a missing or infinite value where the rows give one.
    defp bandwidth(given, _inside) when is_float(given), do: given

    defp bandwidth(:nrd0, inside) do
      deviation = square_root(inside.spread)
      lesser = lesser(deviation, interquartile(inside))

      least =
        cond do
          lesser != 0 -> lesser
          deviation != 0 -> deviation
          inside.first != 0 -> abs(inside.first)
          true -> 1
        end

      0.9
      |> Arithmetic.multiply(least)
      |> Arithmetic.multiply(:math.pow(inside.rows, -0.2))
    end

    defp bandwidth(:nrd, inside) do
      lesser = lesser(square_root(inside.spread), interquartile(inside))

      1.06
      |> Arithmetic.multiply(lesser)
      |> Arithmetic.multiply(:math.pow(inside.rows, -1 / 5))
    end

    # The interquartile range over 1.34, a normal distribution's in standard deviations.
    defp interquartile(inside) do
      inside.upper_quartile
      |> Arithmetic.subtract(inside.lower_quartile)
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
    # `dimension()`, or the group's own with `trim`.
    defp extent(false, _group, axis), do: axis.limits
    defp extent(true, group, _axis), do: {group.x_low, group.x_high}

    # What a group's shares inside the bounds are divided by: what they total, where some rows
    # are outside and that is above 0, else 1, which leaves each as it is.
    defp divisor(true, share_total) when is_number(share_total) and share_total > 0,
      do: share_total

    defp divisor(_outside, _share_total), do: 1.0

    # The weights' total a group's `wdensity` is the density times: its rows' weights', times
    # what its shares total inside the bounds where some rows are outside.
    defp weights_total(true, share_total, total), do: Arithmetic.multiply(share_total, total)
    defp weights_total(false, _share_total, total), do: total

    # The rows of the groups given rows, those of no panel that fails.
    defp kept_rows(rows, totals, plans) do
      kept =
        totals
        |> rows_by_group([])
        |> Enum.map(fn {key, _group} -> Map.fetch!(plans, key) != :dropped end)

      flags =
        totals
        |> DataFrame.select(panel: :panel, group: :group)
        |> DataFrame.put(:kept, kept)

      rows
      |> DataFrame.join(flags, [:panel, :group])
      |> DataFrame.filter(:kept)
    end

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
    defp curve(:too_few, _totals, _stat) do
      [%{x: nil, density: nil, scaled: nil, ndensity: nil, count: nil, wdensity: nil, n: nil}]
    end

    defp curve(plan, totals, stat) do
      places =
        plan.from
        |> Curve.places(plan.to, plan.points)
        |> Enum.map(fn place -> place / 1 end)

      estimates = convolved(plan, totals, stat)

      estimated =
        plan
        |> grid()
        |> Enum.zip(estimates)
        |> Curve.interpolate(places)

      {places, densities} = reflected(places, estimated, plan, stat.bounds)
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
    defp grid(plan) do
      plan.low
      |> Curve.places(plan.high, plan.grid)
      |> Enum.map(fn point -> point / 1 end)
    end

    # The estimate at each grid point: the totals at the grid's points, padded with as many
    # zeros, convolved with the kernel at each distance along the padded grid, wrapping round, and
    # raised to 0 where round-off leaves it below, as R's `density()` does.
    defp convolved(plan, totals, stat) do
      slots = 2 * plan.grid

      signal =
        totals
        |> Enum.reduce(%{}, fn {point, lower, upper}, signal ->
          signal
          |> on_grid(point, lower, plan.grid)
          |> on_grid(point + 1, upper, plan.grid)
        end)
        |> then(fn signal ->
          Enum.map(0..(slots - 1), fn slot -> Map.get(signal, slot, 0.0) end)
        end)

      kernel =
        plan
        |> distances()
        |> Enum.map(fn distance -> kernel(stat.kernel, distance, plan.bandwidth) end)

      signal
      |> Tensor.circular_correlation(kernel)
      |> Enum.take(plan.grid)
      |> Enum.map(fn value -> if value < 0, do: 0.0, else: value end)
    end

    # A part of a share added at a grid point, kept only where the point is on the grid.
    defp on_grid(signal, point, part, grid) when point >= 0 and point < grid,
      do: Map.update(signal, point, part, fn total -> total + part end)

    defp on_grid(signal, _point, _part, _grid), do: signal

    # The distance from the first point of the padded grid to each, wrapping round: R's `kords`,
    # 0 up to just past the grid's span over its first half and back down through the negatives
    # over its second, the distance from the first grid point each way.
    defp distances(plan) do
      slots = 2 * plan.grid
      span = (slots - 1) / (plan.grid - 1) * (plan.high - plan.low)

      upward =
        0
        |> Curve.places(span, slots)
        |> Enum.map(fn distance -> distance / 1 end)
        |> List.to_tuple()

      Enum.map(0..(slots - 1), fn index ->
        if index <= plan.grid, do: elem(upward, index), else: -elem(upward, slots - index)
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
    # its ends, as ggplot2's `reflect_density()` reads it; else as it is.
    defp reflected(places, estimated, _plan, {low, high})
         when not is_number(low) and not is_number(high),
         do: {places, estimated}

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

    # A summarised table's rows by `{panel, group}`, each a map of the columns `names`.
    defp rows_by_group(frame, names) do
      columns = Enum.map([:panel, :group | names], fn name -> DataFrame.pull(frame, name) end)

      Enum.zip_with(columns, fn [panel, group | values] ->
        {{panel, group}, Map.new(Enum.zip(names, values))}
      end)
    end

    # The stat's table: each group's curve's rows in its group's order, the columns ggplot2's,
    # then each carried column's group's value.
    defp output(curves, groups, constant, flipped) do
      rows =
        Enum.flat_map(curves, fn {key, curve} ->
          Enum.map(curve, fn row -> Map.put(row, :key, key) end)
        end)

      computed =
        for name <- [:x, :density, :scaled, :ndensity, :count, :wdensity, :n],
            do: {name, Enum.map(rows, fn row -> Map.fetch!(row, name) end)}

      flipped_aes = {:flipped_aes, List.duplicate(flipped, length(rows))}
      dtypes = DataFrame.dtypes(groups)

      carried =
        Enum.map(constant, fn name ->
          by_group =
            Map.new(rows_by_group(groups, [name]), fn {key, values} -> {key, values[name]} end)

          values = Enum.map(rows, fn row -> Map.fetch!(by_group, row.key) end)

          if Map.fetch!(dtypes, name) == :category,
            do: {name, values, DataFrame.category(groups, name)},
            else: {name, values}
        end)

      [computed, [flipped_aes], carried]
      |> Enum.concat()
      |> DataFrame.new()
    end
  end
end
