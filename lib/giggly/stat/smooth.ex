defmodule Giggly.Stat.Smooth do
  @moduledoc false

  # Smoothing, ggplot2's `stat_smooth()`, `geom_smooth()`'s stat: for each group in each panel, in
  # that order, a curve fitted to its rows, `n` rows evenly spaced along x from the group's least x
  # to its greatest, or across the unwidened extent of the panel's axis it runs along with
  # `fullrange`, R's `seq()`,
  # each its fitted `y`, and with `se` its standard error `se` and the band `ymin` to `ymax`, `y`
  # less and plus the quantile holding `level` of the distribution times `se`, the t distribution's,
  # or for gam the normal's; and `flipped_aes`.
  # Its method is a straight line by weighted least squares, R's `lm(y ~ x, weights = weight)`
  # read through `predict()` as ggplot2's `predictdf()` reads it, or a loess curve, R's `loess(y ~
  # x, weights = weight, span = span)` fitted directly at each place (`Giggly.Stat.Loess`), or a
  # gam curve, R's `mgcv::gam(y ~ s(x, bs = "cs"), weights = weight, method = "REML")`
  # (`Giggly.Stat.Gam`). A smooth given no method (`:none`) is fitted by loess where the largest
  # group in any panel has under 1,000 rows, every row counted, as ggplot2 chooses, and by gam from
  # there. Its orientation is the layer's (`:x`, or `:y` to fit x
  # along y, the two swapped and swapped back, as ggplot2's `flip_data()` does), ggplot2's taking an
  # unstated one as along x. Run it through `Giggly.Stat`.
  #
  # It needs `:x` and `:y`, takes `:group` and `:weight`, which it consumes, and computes `y`,
  # `ymin`, `ymax` and `se`, `x`, `xmin` and `xmax` along y, which a mapping's after_stat can read.
  #
  # A row missing its x or y, or at an infinite one, is left out, as ggplot2's `remove_missing()`
  # drops it; a group then holding fewer than two distinct x is fitted nothing, as ggplot2 fits
  # none. R's `lm()` then leaves out a row missing its weight, `nil` or NaN, and fails on a
  # negative or infinite one, so such a group is fitted nothing, where ggplot2 also warns, which a
  # pure pipeline cannot; it leaves out a row of weight 0 before fitting, so the degrees of freedom
  # are the rows of a weight above 0 less two, and a group whose weights are all 0 is fitted
  # nothing. A weight that is not a number is refused by the frame as it finds each group's least
  # weight, naming the column and its type. Where its weighted rows hold one x, its curve is flat
  # at their weighted mean, with a degree of freedom more, as R's `lm()` drops the slope it cannot
  # fit; where they hold more, the slope is fitted however little x varies, where R's `lm()` drops
  # it once x's spread is under a ten-millionth of its size (design-log §4, the entry beginning "A
  # linear smooth fits the slope"). Of no degrees of freedom, the band and `se` are NaN. Loess, as
  # R's `loess()`, leaves out a row missing its weight and fails on an infinite one; a negative one
  # fits its group nothing, where R fits 0, and a row of weight 0 stays among the rows, making the
  # band NaN, as R's; a loess curve's places past its rows are missing, and a group whose
  # neighbourhoods cannot hold a quadratic is fitted nothing (`Giggly.Stat.Loess`). gam, as R's
  # `gam()`, leaves out a row missing its weight and keeps a row of weight 0 for its knots, and
  # a group of fewer than 10 distinct x, or whose rows weighted above 0 share one y, is fitted
  # nothing (`Giggly.Stat.Gam`). A group's
  # constant columns are carried to its rows (`Giggly.Stat.Carry`), counted over the groups given a
  # curve, as ggplot2 reads only the groups its fit gives rows.
  #
  # Its fullrange reads the panel's axis it runs along, its y axis along y, where ggplot2's
  # `StatSmooth` reads `scales$x` though it fits along y (design-log §4, the entry beginning "A
  # full-range smooth spans").
  #
  # A straight line is worked out where the frame does what scales with the rows
  # (`Giggly.DataFrame`), in three passes of weighted sums
  # over each group's rows, each summarised to a row a group (design-log §4, the entry beginning
  # "Smoothing and densities compute over the rows"): the weights' total and the weighted means of
  # x and y; the weighted sums of squares and of products of each row's x and y about them, whose
  # ratio is the slope; and the weighted sum of the squares of each row's residual from the line.
  # Each group's curve is worked out on its one summarised row, its fitted value the mean of y
  # plus the slope times its x's distance from the mean of x, its standard error the residuals'
  # variance times one over the weights' total plus that distance squared over the sum of
  # squares, square-rooted, and its quantile Giggly's own (`Giggly.Stat.TDistribution`). Its
  # values are R's to within 1e-12 of the largest magnitude a group's column holds, its x R's to
  # the last digit (design-log §4, the entry beginning "A stat's values reached by another route").
  # A loess curve pulls each group's rows instead, by the frame's `list` aggregate, since no engine
  # could run it, and is held to R's direct loess as closely. A gam curve sums each group's rows by
  # knot interval through the frame and works out the rest on those sums, held to mgcv fitting the
  # same model within 1e-6 of the range of the group's y, its standard errors 1e-5 relatively
  # (design-log §4, the entry beginning "A gam's shrinkage").

  @enforce_keys [:method, :se, :level, :n, :span, :fullrange, :orientation]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          method: :none | :lm | :loess | :gam,
          se: boolean(),
          level: float(),
          n: pos_integer(),
          span: float(),
          fullrange: boolean(),
          orientation: :x | :y
        }

  # The aesthetics a layer that smooths can use for its fit, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :weight, :x, :y]

  # The aesthetics a smooth cannot be fitted without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  # The variables smoothing computes that a mapping's after_stat can read, as ggplot2 documents
  # them, each in either orientation: the fitted value, the band's ends and the standard error.
  @doc false
  @spec computed_variables() :: [atom()]
  def computed_variables, do: [:se, :x, :xmax, :xmin, :y, :ymax, :ymin]

  # The aesthetics smoothing consumes, ggplot2's `dropped_aes`.
  @doc false
  @spec dropped_aesthetics() :: [atom()]
  def dropped_aesthetics, do: [:weight]

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.{Aesthetics, DataFrame}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Stat.{Carry, Curve, Gam, Loess, TDistribution}

    # The columns the stat writes, in ggplot2's order.
    @computed [:x, :y, :ymin, :ymax, :se, :flipped_aes]

    # The rows of a layer's largest group under which ggplot2 fits a smooth given no method by
    # loess, and by gam from there.
    @loess_rows 1000

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{}

    @impl Giggly.Stat
    def compute_layer(stat, frame, axes) do
      method = method(stat, frame)
      flipped = stat.orientation == :y

      frame
      |> flip(flipped)
      |> smooths(stat, method, axes, flipped)
      |> flip(flipped)
    end

    # A smooth given no method is fitted as ggplot2 fits one: by loess where the layer's largest
    # group in any panel has under 1,000 rows, every row counted, as ggplot2's `setup_params()`
    # counts them, and by gam from there.
    defp method(%{method: :none}, frame) do
      largest =
        frame
        |> DataFrame.summarise([:panel, :group], rows: {:count, [:group]})
        |> DataFrame.pull(:rows)
        |> Enum.max(fn -> 0 end)

      if largest < @loess_rows, do: :loess, else: :gam
    end

    defp method(%{method: method}, _frame), do: method

    defp flip(frame, false), do: frame

    defp flip(frame, true) do
      renames =
        frame
        |> DataFrame.names()
        |> Aesthetics.flipped()

      DataFrame.select(frame, renames)
    end

    defp smooths(frame, stat, method, axes, flipped) do
      carried =
        frame
        |> DataFrame.names()
        |> Enum.reject(fn name -> name in @computed end)

      fitted_rows =
        frame
        |> DataFrame.filter({:and, [{:is_finite, [:x]}, {:is_finite, [:y]}]})
        |> weighted()
        |> fitted_groups()

      extents =
        DataFrame.summarise(fitted_rows, [:panel, :group],
          x_low: {:min, [:x]},
          x_high: {:max, [:x]}
        )

      curves = curves(method, fitted_rows, extents, stat, axes)
      kept_rows = kept_rows(fitted_rows, extents, curves)
      constant = Carry.constant_columns(kept_rows, carried)
      firsts = for name <- constant, name not in [:panel, :group], do: {name, {:first, [name]}}
      groups = DataFrame.summarise(kept_rows, [:panel, :group], firsts)

      output(curves, groups, constant, stat.se, flipped)
    end

    # The rows of the groups given a curve: every group lm fits, those loess finds a quadratic for
    # in every neighbourhood, and those gam fits.
    defp kept_rows(rows, extents, curves) do
      given = MapSet.new(curves, fn {key, _curve} -> key end)

      kept =
        extents
        |> rows_by_group([])
        |> Enum.map(fn {key, _extent} -> key in given end)

      flags =
        extents
        |> DataFrame.select(panel: :panel, group: :group)
        |> DataFrame.put(:kept, kept)

      rows
      |> DataFrame.join(flags, [:panel, :group])
      |> DataFrame.filter(:kept)
    end

    # The rows with each one's weight, 1 where the layer maps none, as R's `lm()` weighs each row
    # 1.
    defp weighted(frame) do
      if :weight in DataFrame.names(frame),
        do: frame,
        else: DataFrame.mutate(frame, weight: 1.0)
    end

    # The rows of the groups R's `lm()` fits: those holding two distinct x or more, every row
    # counted, as ggplot2 counts them before it fits, whose weights, a missing one left out, are
    # none of them negative or infinite, and some of them above 0.
    defp fitted_groups(rows) do
      checked =
        DataFrame.summarise(rows, [:panel, :group],
          x_count: {:n_distinct, [:x]},
          weight_low: {:min, [:weight]},
          weight_high: {:max, [:weight]}
        )

      fitted =
        {:and,
         [
           {:>, [:x_count, 1]},
           {:and,
            [
              {:is_finite, [:weight_high]},
              {:and, [{:>, [:weight_high, 0]}, {:not, [{:<, [:weight_low, 0]}]}]}
            ]}
         ]}

      rows
      |> DataFrame.join(checked, [:panel, :group])
      |> DataFrame.filter(fitted)
    end

    # Each fitted group's line, by `{panel, group}`: the weights' total, the weighted means of x and
    # y, the sum of squares of x about its mean, the slope, the residuals' weighted sum of squares
    # and the degrees of freedom, from the rows of a weight above 0, as R's `lm()` fits them.
    defp fits(rows) do
      weighed =
        rows
        |> DataFrame.filter({:and, [{:is_finite, [:weight]}, {:>, [:weight, 0]}]})
        |> DataFrame.select(panel: :panel, group: :group, x: :x, y: :y, weight: :weight)

      means =
        weighed
        |> DataFrame.mutate(weighted_x: {:*, [:weight, :x]}, weighted_y: {:*, [:weight, :y]})
        |> DataFrame.summarise([:panel, :group],
          total: {:sum, [:weight]},
          weighted_x: {:sum, [:weighted_x]},
          weighted_y: {:sum, [:weighted_y]},
          rows: {:count, [:weight]},
          x_count: {:n_distinct, [:x]}
        )
        |> DataFrame.mutate(
          mean_x: {:/, [:weighted_x, :total]},
          mean_y: {:/, [:weighted_y, :total]}
        )

      centred =
        weighed
        |> DataFrame.join(
          DataFrame.select(means, panel: :panel, group: :group, mean_x: :mean_x, mean_y: :mean_y),
          [:panel, :group]
        )
        |> DataFrame.mutate(
          across: {:-, [:x, :mean_x]},
          up: {:-, [:y, :mean_y]},
          weighted_across: {:*, [:weight, {:-, [:x, :mean_x]}]}
        )

      squares =
        centred
        |> DataFrame.mutate(
          squares: {:*, [:weighted_across, :across]},
          products: {:*, [:weighted_across, :up]}
        )
        |> DataFrame.summarise([:panel, :group],
          squares: {:sum, [:squares]},
          products: {:sum, [:products]}
        )

      lines = lines(means, squares)
      residuals = residuals(centred, means, lines)

      lines
      |> Enum.zip_with(residuals, fn {key, line}, residual_squares ->
        {key, Map.put(line, :residual_squares, residual_squares)}
      end)
      |> Map.new()
    end

    # Each group's line from its summarised sums, in the summaries' order, the groups': the slope,
    # the products over the squares, or 0 where its rows hold one x, with a degree of freedom
    # more, as R's `lm()` drops a slope it cannot fit.
    defp lines(means, squares) do
      means
      |> rows_by_group([:total, :mean_x, :mean_y, :rows, :x_count])
      |> Enum.zip_with(rows_by_group(squares, [:squares, :products]), fn {key, line},
                                                                         {key, sums} ->
        {slope, rank} =
          if line.x_count == 1,
            do: {0.0, 1},
            else: {Arithmetic.divide(sums.products, sums.squares), 2}

        {key,
         Map.merge(line, %{
           squares: sums.squares,
           slope: slope,
           rank: rank,
           degrees_of_freedom: line.rows - rank
         })}
      end)
    end

    # Each group's weighted sum of the squares of its rows' residuals from its line, in the groups'
    # order.
    defp residuals(centred, means, lines) do
      slopes =
        means
        |> DataFrame.select(panel: :panel, group: :group)
        |> DataFrame.put(:slope, Enum.map(lines, fn {_key, line} -> line.slope end))

      centred
      |> DataFrame.join(slopes, [:panel, :group])
      |> DataFrame.mutate(residual: {:-, [:up, {:*, [:slope, :across]}]})
      |> DataFrame.mutate(residual_squares: {:*, [{:*, [:weight, :residual]}, :residual]})
      |> DataFrame.summarise([:panel, :group], residual_squares: {:sum, [:residual_squares]})
      |> DataFrame.pull(:residual_squares)
    end

    # A summarised table's rows by `{panel, group}`, each a map of the columns `names`.
    defp rows_by_group(frame, names) do
      columns = Enum.map([:panel, :group | names], fn name -> DataFrame.pull(frame, name) end)

      Enum.zip_with(columns, fn [panel, group | values] ->
        {{panel, group}, Map.new(Enum.zip(names, values))}
      end)
    end

    # Each fitted group's curve, in the groups' order: its x evenly spaced, and its fitted values,
    # standard errors and band, a straight line's for every group, a loess curve's for each whose
    # every neighbourhood holds a quadratic, and a gam curve's for each gam fits. Loess pulls each
    # group's rows, a row missing its weight left out, as R's `loess()` leaves it out; gam reads
    # each group's sums by knot interval (`Giggly.Stat.Gam`).
    defp curves(:lm, rows, extents, stat, axes) do
      fits = fits(rows)

      extents
      |> rows_by_group([:x_low, :x_high])
      |> Enum.map(fn {key, extent} ->
        {key, curve(Map.fetch!(fits, key), positions(key, extent, stat, axes), stat)}
      end)
    end

    defp curves(:loess, rows, extents, stat, axes) do
      lists =
        rows
        |> DataFrame.filter({:is_finite, [:weight]})
        |> DataFrame.summarise([:panel, :group],
          xs: {:list, [:x]},
          ys: {:list, [:y]},
          weights: {:list, [:weight]}
        )
        |> rows_by_group([:xs, :ys, :weights])
        |> Map.new()

      extents
      |> rows_by_group([:x_low, :x_high])
      |> Enum.flat_map(fn {key, extent} ->
        group = Map.fetch!(lists, key)
        places = positions(key, extent, stat, axes)

        case Loess.curve(
               group.xs,
               group.ys,
               group.weights,
               places,
               stat.span,
               stat.se,
               stat.level
             ) do
          :none -> []
          curve -> [{key, curve}]
        end
      end)
    end

    defp curves(:gam, rows, extents, stat, axes) do
      sums = Gam.sums(rows)

      extents
      |> rows_by_group([:x_low, :x_high])
      |> Enum.flat_map(fn {key, extent} ->
        case Map.fetch(sums, key) do
          {:ok, group} ->
            [{key, Gam.curve(group, positions(key, extent, stat, axes), stat.se, stat.level)}]

          :error ->
            []
        end
      end)
    end

    # The places a group's curve is worked out at: `n` evenly spaced along its extent, each a
    # double, as R's positions are, though the axis's ends be whole numbers.
    defp positions({panel, _group}, extent, stat, axes) do
      along =
        axes
        |> Map.fetch!(panel)
        |> Map.fetch!(stat.orientation)

      {low, high} = extent(stat.fullrange, extent, along)

      low
      |> Curve.places(high, stat.n)
      |> Enum.map(fn position -> position / 1 end)
    end

    # The positions the curve spans along the axis it runs along: the group's, or with `fullrange`
    # the panel's axis's unwidened extent, as ggplot2's `dimension()`.
    defp extent(false, %{x_low: low, x_high: high}, _axis), do: {low, high}
    defp extent(true, _extent, %{limits: limits}), do: limits

    # The curve's rows, each its x, fitted value and, with `se`, its standard error and band.
    defp curve(line, positions, %{se: false}) do
      Enum.map(positions, fn position ->
        %{x: position, y: fitted(line, Arithmetic.subtract(position, line.mean_x))}
      end)
    end

    defp curve(line, positions, %{level: level}) do
      variance = variance(line)
      quantile = TDistribution.central_quantile(level, line.degrees_of_freedom)

      Enum.map(positions, fn position ->
        distance = Arithmetic.subtract(position, line.mean_x)
        fitted = fitted(line, distance)
        error = standard_error(line, variance, distance)
        reach = Arithmetic.multiply(quantile, error)

        %{
          x: position,
          y: fitted,
          ymin: Arithmetic.subtract(fitted, reach),
          ymax: Arithmetic.add(fitted, reach),
          se: error
        }
      end)
    end

    # The line's value at `distance` from the mean of x.
    defp fitted(line, distance),
      do: Arithmetic.add(line.mean_y, Arithmetic.multiply(line.slope, distance))

    # The residuals' variance, their weighted sum of squares over the degrees of freedom: NaN for
    # none, as R's `lm()` holds no residual where it fits every row, its 0 over 0.
    defp variance(%{degrees_of_freedom: 0}), do: :nan

    defp variance(line),
      do: Arithmetic.divide(line.residual_squares, line.degrees_of_freedom)

    # The fitted value's standard error at `distance` from the mean of x: the residuals' variance
    # times one over the weights' total, plus the distance squared over the sum of squares where
    # the line has a slope, square-rooted.
    defp standard_error(line, variance, distance) do
      share = Arithmetic.divide(1, line.total)

      share =
        if line.rank == 2 do
          distance
          |> Arithmetic.multiply(distance)
          |> Arithmetic.divide(line.squares)
          |> Arithmetic.add(share)
        else
          share
        end

      variance
      |> Arithmetic.multiply(share)
      |> square_root()
    end

    defp square_root(value) when is_number(value), do: :math.sqrt(value)
    defp square_root(value), do: value

    # The stat's table: each curve's rows in its group's order, the columns ggplot2's, then each
    # carried column's group's value.
    defp output(curves, groups, constant, se, flipped) do
      rows =
        Enum.flat_map(curves, fn {key, curve} ->
          Enum.map(curve, fn row -> Map.put(row, :key, key) end)
        end)

      names = if se, do: [:x, :y, :ymin, :ymax, :se], else: [:x, :y]

      computed =
        for name <- names, do: {name, Enum.map(rows, fn row -> Map.fetch!(row, name) end)}

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
