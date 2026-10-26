defmodule Giggly.Stat.Gam do
  @moduledoc false

  # A gam curve, the one ggplot2 fits, R's `mgcv::gam(y ~ s(x, bs = "cs"), weights = weight,
  # method = "REML")` read through `predict()`, worked out from mgcv's documentation and the
  # published method, never mgcv's source (design-log §4, the entry beginning "gam is Giggly's
  # own"), for smoothing (`Giggly.Stat.Smooth`).
  #
  # The curve is a natural cubic regression spline written as its values at 10 knots, the type-7
  # quantiles of the group's distinct x, as Wood's Generalized Additive Models (2nd ed., 2017)
  # §5.3.1 writes it: between the knots x_j and x_j+1, h_j apart, it is a⁻β_j + a⁺β_j+1 + c⁻δ_j +
  # c⁺δ_j+1, the β its values at the knots and the δ its second derivatives there, with a⁻ = (x_j+1
  # - x) / h_j, a⁺ = (x - x_j) / h_j and c± = h_j² (a±³ - a±) / 6; the δ are F β, F = B⁻¹D, the
  # end knots' 0, from the tridiagonal B and D the continuity of its slope gives; and its
  # wiggliness, the integral of its second derivative squared, is βᵀSβ, S = Dᵀ B⁻¹ D. Past the end
  # knots it is straight, at its slope there, as a natural spline is. x is measured across the
  # knots' range, which leaves the curve as it is and its arithmetic clear of overflow wherever x
  # lies. S leaves the constant and the straight line unpenalised; mgcv's shrinkage version gives
  # those two directions penalties of 0.1 and 0.01 of S's smallest positive eigenvalue, along
  # whichever two directions its eigen-decomposition's rounding picks, so Giggly gives each 0.055,
  # their mean over every pair it could pick (design-log §4, the entry beginning "A gam's
  # shrinkage"). The curve is fitted beside a constant, so it is held to sum to 0 over the group's
  # rows, unweighted, as mgcv constrains it: with C the basis's column totals, the penalty is
  # PᵀSP, P = I - 1Cᵀ / Σ C, and the constant goes unpenalised.
  #
  # The fit is penalised least squares, β = (Xᵀ W X + λ S)⁻¹ Xᵀ W y, y centred at its weighted
  # mean, and λ minimises the restricted likelihood (REML, Wood 2011, "Fast stable restricted
  # maximum likelihood and marginal likelihood estimation of semiparametric generalized linear
  # models", JRSS B 73), its scale worked out at each λ: (m - 1) log D + log |Xᵀ W X + λ S| - 9 log
  # λ, m the rows weighted above 0 and D = yᵀ W y - βᵀ Xᵀ W y, the residuals' and the penalty's
  # sum. It is searched over log λ at 61 places a step apart about the scale of Xᵀ W X's trace
  # over S's, then narrowed by golden-section search to 1e-11 round the least. The standard error
  # at x is √(φ xᵀ (Xᵀ W X + λ S)⁻¹ x), mgcv's Bayesian covariance, φ the weighted residuals' sum
  # of squares, held at 0 or above against rounding, over every row less the effective degrees of
  # freedom, trace((Xᵀ W X + λ S)⁻¹ Xᵀ W X), so rows on a straight line are fitted the line with a
  # band of no width, where R's band is rounding's width; the band is the curve ∓ the normal
  # quantile at `level` times it, as ggplot2 reads a gam's band, its `predictdf()` for a glm
  # (`Giggly.Stat.NormalDistribution`).
  #
  # What scales with the rows runs through the frame (design-log §4, the entry beginning
  # "Smoothing and densities compute over the rows"): each group's distinct x and their quantiles,
  # its weights' totals, and, its rows cut at its own knots as binning cuts each panel's, each
  # row's four weights a⁻, a⁺, c⁻ and c⁺ in its interval, and each interval's extended sums of their
  # products with each other and with the row's centred y, weighted, and of the weights themselves,
  # unweighted, for the constraint. The 10 by 10 algebra on those sums is plain Elixir
  # (`Giggly.Stat.Matrix`). Against mgcv fitting the same model it is within 1.1e-7 of the range of
  # the group's y, its standard errors 4.4e-7 relatively.
  #
  # As R's `gam()` takes its rows, a row missing its weight is left out, and a row of weight 0 is
  # kept for the knots, the constraint and the scale's count of rows, but not REML's; a group of
  # fewer than 10 distinct x among the rest, or whose rows weighted above 0 share one y, is fitted
  # nothing, where `gam()` fails and ggplot2 warns.

  alias Giggly.DataFrame
  alias Giggly.Stat.{Matrix, NormalDistribution}

  # The spline's knots, mgcv's default for a cubic regression spline.
  @knots 10

  # The share of S's smallest positive eigenvalue each of its two unpenalised directions is
  # penalised by: the mean of mgcv's 0.1 and 0.01.
  @shrinkage 0.055

  # How many steps of 1 in log λ the search reaches either side of its scale, and how narrow
  # golden-section search leaves its interval.
  @reach 30
  @narrowest 1.0e-11

  # The golden ratio's conjugate, (√5 - 1) / 2.
  @golden 0.6180339887498949

  # Each row's weights in its knot interval, on the values (a⁻, a⁺) and second derivatives (c⁻,
  # c⁺) at the interval's lower and upper knots, and the names of the sums each interval is given:
  # the weighted products of each pair, the weighted products with the centred y, and the weights'
  # unweighted totals.
  @weights [:lower, :upper, :lower_bend, :upper_bend]
  @pairs for {first, index} <- Enum.with_index(@weights),
             second <- Enum.drop(@weights, index),
             do: {first, second}
  @products Enum.map(@pairs, fn {first, second} -> :"#{first}_#{second}" end)
  @responses Enum.map(@weights, fn weight -> :"#{weight}_y" end)
  @totals Enum.map(@weights, fn weight -> :"#{weight}_total" end)

  # The quantiles of a group's distinct x the knots are, by name.
  @knot_names Enum.map(1..@knots, fn index -> :"knot_#{index}" end)

  # What a gam fit reads of each group it fits, by `{panel, group}`, from the rows of a smooth's
  # fitted groups, their x, y and weights finite but for a weight missing, none below 0 and some
  # above: the knots, the weighted mean of y, the count of rows and of rows weighted above 0, the
  # weighted sum of the centred y's squares, and each knot interval's sums, by interval from 1. A
  # group a gam cannot fit is absent.
  @doc false
  @spec sums(DataFrame.t()) :: %{optional({term(), term()}) => map()}
  def sums(rows) do
    weighed = DataFrame.filter(rows, {:is_finite, [:weight]})
    groups = groups(weighed)

    weighed
    |> DataFrame.split(:panel)
    |> Enum.flat_map(fn {panel, panel_rows} -> panel_sums(panel, panel_rows, groups) end)
    |> Map.new()
  end

  # A panel's groups' sums, each group's rows cut at its own knots, as binning cuts each panel's.
  defp panel_sums(panel, rows, groups) do
    rows
    |> DataFrame.split(:group)
    |> Enum.flat_map(fn {group, group_rows} -> group_sums({panel, group}, group_rows, groups) end)
  end

  defp group_sums(key, rows, groups) do
    case Map.fetch(groups, key) do
      {:ok, group} -> [{key, intervals(rows, group)}]
      :error -> []
    end
  end

  # The groups a gam fits, by `{panel, group}`: each one's knots, weighted mean of y and counts of
  # rows, from three summaries of a row a group, joined.
  defp groups(weighed) do
    counts =
      weighed
      |> DataFrame.mutate(weighted_y: {:*, [:weight, :y]})
      |> DataFrame.summarise([:panel, :group],
        rows: {:count, [:x]},
        distinct: {:n_distinct, [:x]},
        total: {:sum, [:weight]},
        weighted_y: {:sum, [:weighted_y]}
      )
      |> DataFrame.mutate(centre: {:/, [:weighted_y, :total]})
      |> DataFrame.select(
        panel: :panel,
        group: :group,
        rows: :rows,
        distinct: :distinct,
        centre: :centre
      )

    weighted =
      weighed
      |> DataFrame.filter({:>, [:weight, 0]})
      |> DataFrame.summarise([:panel, :group],
        weighted_rows: {:count, [:y]},
        y_low: {:min, [:y]},
        y_high: {:max, [:y]}
      )

    quantiles =
      Enum.with_index(@knot_names, fn name, index ->
        {name, {:quantile, [:x], probability: index / (@knots - 1)}}
      end)

    knots =
      weighed
      |> DataFrame.summarise([:panel, :group, :x], repeats: {:count, [:x]})
      |> DataFrame.summarise([:panel, :group], quantiles)

    fitted =
      counts
      |> DataFrame.join(weighted, [:panel, :group])
      |> DataFrame.join(knots, [:panel, :group])
      |> DataFrame.filter({:and, [{:>, [:distinct, @knots - 1]}, {:<, [:y_low, :y_high]}]})

    columns = [:panel, :group, :rows, :weighted_rows, :centre | @knot_names]

    columns
    |> Enum.map(fn name -> DataFrame.pull(fitted, name) end)
    |> Enum.zip_with(fn [panel, group, rows, weighted_rows, centre | knots] ->
      {{panel, group}, %{knots: knots, centre: centre, rows: rows, weighted_rows: weighted_rows}}
    end)
    |> Map.new()
  end

  # A group's sums: its rows cut at its knots, each one's four weights in its interval, and each
  # interval's sums, with the weighted sum of the centred y's squares.
  defp intervals(rows, %{knots: knots, centre: centre} = group_sums) do
    [first | _rest] = knots
    range = List.last(knots) - first

    bounds =
      knots
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [low, high] -> {low, high, high - low} end)

    table =
      DataFrame.new(
        interval: Enum.to_list(1..(@knots - 1)),
        low: Enum.map(bounds, fn {low, _high, _width} -> low end),
        high: Enum.map(bounds, fn {_low, high, _width} -> high end),
        width: Enum.map(bounds, fn {_low, _high, width} -> width end),
        curvature: Enum.map(bounds, fn {_low, _high, width} -> curvature(width / range) end)
      )

    products =
      Enum.zip_with(@pairs, @products, fn {first_weight, second_weight}, name ->
        {name, {:*, [:weight, {:*, [first_weight, second_weight]}]}}
      end)

    responses =
      Enum.zip_with(@weights, @responses, fn weight, name ->
        {name, {:*, [:weighted_centred, weight]}}
      end)

    names = Enum.concat([@products, @responses, @totals, [:squares]])

    sums =
      Enum.zip_with(names, Enum.concat([@products, @responses, @weights, [:squares]]), &sum/2)

    summarised =
      rows
      |> DataFrame.mutate(
        interval: {:cut, [:x], breaks: knots, closed: :right},
        centred: {:-, [:y, centre]}
      )
      |> DataFrame.join(table, [:interval])
      |> DataFrame.mutate(
        lower: {:/, [{:-, [:high, :x]}, :width]},
        upper: {:/, [{:-, [:x, :low]}, :width]},
        weighted_centred: {:*, [:weight, :centred]}
      )
      |> DataFrame.mutate(lower_bend: bend(:lower), upper_bend: bend(:upper))
      |> DataFrame.mutate(
        Enum.concat(products, [{:squares, {:*, [:weighted_centred, :centred]}} | responses])
      )
      |> DataFrame.summarise([:interval], sums)

    columns = Enum.map([:interval | names], fn name -> DataFrame.pull(summarised, name) end)

    blocks =
      Enum.zip_with(columns, fn [interval | values] ->
        {products, rest} = Enum.split(values, length(@products))
        {responses, rest} = Enum.split(rest, length(@responses))
        {totals, [squares]} = Enum.split(rest, length(@totals))
        {interval, %{products: products, responses: responses, totals: totals, squares: squares}}
      end)

    squares =
      blocks
      |> Enum.map(fn {_interval, block} -> block.squares end)
      |> Enum.sum()

    Map.merge(group_sums, %{blocks: blocks, squares: squares})
  end

  defp sum(name, column), do: {name, {:sum, [column]}}

  # c± from a±, with the interval's h² / 6 across the knots' range: h² (a±³ - a±) / 6.
  defp bend(weight),
    do: {:*, [:curvature, {:-, [{:*, [weight, {:*, [weight, weight]}]}, weight]}]}

  defp curvature(width), do: width * width / 6

  # A group's curve at `places`, each a map of its place `x` and curve `y`, and with `se` its
  # `ymin`, `ymax` and standard error `se` at `level`.
  @doc false
  @spec curve(map(), [float()], boolean(), float()) :: [map()]
  def curve(group_sums, places, se, level) do
    spline = spline(group_sums.knots)
    {gram, response, totals} = assembled(group_sums.blocks, spline)
    penalty = constrained(shrunk(spline), totals)
    fit = fit(gram, response, penalty, group_sums)
    Enum.map(places, fn place -> curve_row(place, spline, fit, se, level) end)
  end

  # The spline's knots, their widths across the knots' range, F with its rows at the end knots 0,
  # and S.
  defp spline(knots) do
    [first | _rest] = knots
    range = List.last(knots) - first

    widths =
      knots
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [low, high] -> (high - low) / range end)

    consecutive = Enum.chunk_every(widths, 2, 1, :discard)

    differences =
      consecutive
      |> Enum.with_index()
      |> Enum.map(fn {[width, next], row} ->
        for column <- 0..(@knots - 1), do: difference(column - row, width, next)
      end)

    spans =
      consecutive
      |> Enum.with_index()
      |> Enum.map(fn {[width, next], row} ->
        for column <- 0..row, do: span(column - row, width, next)
      end)

    {:ok, factor} = Matrix.cholesky(spans)

    bends =
      differences
      |> Matrix.transpose()
      |> Enum.map(fn column -> Matrix.solve(factor, column) end)
      |> Matrix.transpose()

    zeros = List.duplicate(0.0, @knots)

    %{
      knots: knots,
      first: first,
      range: range,
      widths: widths,
      bends: Enum.concat([[zeros], bends, [zeros]]),
      wiggliness:
        differences
        |> Matrix.transpose()
        |> Matrix.multiply(bends)
    }
  end

  # D's entry `offset` columns past its row's own: the change in slope across a knot, h_j wide
  # before it and h_j+1 after.
  defp difference(0, width, _next), do: 1 / width
  defp difference(1, width, next), do: -1 / width - 1 / next
  defp difference(2, _width, next), do: 1 / next
  defp difference(_offset, _width, _next), do: 0.0

  # B's entry `offset` columns past its row's own, up to its diagonal: the lower triangle of the
  # symmetric B, which is all its Cholesky factor reads.
  defp span(-1, width, _next), do: width / 6
  defp span(0, width, next), do: (width + next) / 3
  defp span(_offset, _width, _next), do: 0.0

  # Xᵀ W X, Xᵀ W y and the basis's column totals, each interval's 4 by 4 sums spread through its
  # rows of the basis, the interval's two knots' values and their second derivatives.
  defp assembled(blocks, spline) do
    zero_matrix =
      0.0
      |> List.duplicate(@knots)
      |> List.duplicate(@knots)

    zero_vector = List.duplicate(0.0, @knots)

    Enum.reduce(blocks, {zero_matrix, zero_vector, zero_vector}, fn {interval, block},
                                                                    {gram, response, totals} ->
      rows = interval_basis(spline, interval - 1)
      columns = Matrix.transpose(rows)
      square = block_matrix(block.products)

      {Matrix.add(gram, Matrix.multiply(Matrix.multiply(columns, square), rows)),
       add_vectors(response, Matrix.multiply_vector(columns, block.responses)),
       add_vectors(totals, Matrix.multiply_vector(columns, block.totals))}
    end)
  end

  # The four rows taking the spline's knot values to its value and second derivative at an
  # interval's lower and upper knots.
  defp interval_basis(spline, index) do
    [
      unit(index),
      unit(index + 1),
      Enum.at(spline.bends, index),
      Enum.at(spline.bends, index + 1)
    ]
  end

  # The 4 by 4 symmetric matrix of an interval's weighted products, from its upper triangle.
  defp block_matrix(products) do
    by_pair =
      @pairs
      |> Enum.zip(products)
      |> Map.new()

    for first <- @weights, do: Enum.map(@weights, fn second -> entry(by_pair, first, second) end)
  end

  defp entry(by_pair, first, second) do
    case Map.fetch(by_pair, {first, second}) do
      {:ok, product} -> product
      :error -> Map.fetch!(by_pair, {second, first})
    end
  end

  defp add_vectors(left, right),
    do: Enum.zip_with(left, right, fn left_entry, right_entry -> left_entry + right_entry end)

  defp unit(index),
    do: for(column <- 0..(@knots - 1), do: if(column == index, do: 1.0, else: 0.0))

  # S with its two unpenalised directions, the constant and the straight line through the knots,
  # each penalised by the shrinkage's share of its smallest positive eigenvalue.
  defp shrunk(%{wiggliness: wiggliness, knots: knots}) do
    smallest =
      wiggliness
      |> Matrix.eigenvalues()
      |> Enum.at(@knots - 3)

    constant = List.duplicate(1 / :math.sqrt(@knots), @knots)
    mean = Enum.sum(knots) / @knots
    centred = Enum.map(knots, fn knot -> knot - mean end)

    length =
      centred
      |> Matrix.dot(centred)
      |> :math.sqrt()

    line = Enum.map(centred, fn value -> value / length end)
    along_line = Matrix.outer(line, line)

    constant
    |> Matrix.outer(constant)
    |> Matrix.add(along_line)
    |> Matrix.scale(@shrinkage * smallest)
    |> Matrix.add(wiggliness)
  end

  # The penalty on the curve held to sum to 0 over the rows: PᵀSP, P = I - 1Cᵀ / Σ C.
  defp constrained(penalty, totals) do
    total = Enum.sum(totals)
    sweep = Enum.map(totals, fn column_total -> column_total / total end)

    projection =
      @knots
      |> Matrix.identity()
      |> Enum.map(fn row -> Enum.zip_with(row, sweep, fn entry, share -> entry - share end) end)

    projection
    |> Matrix.transpose()
    |> Matrix.multiply(penalty)
    |> Matrix.multiply(projection)
  end

  # The fit at the λ REML picks: β, the covariance's factor (Xᵀ W X + λ S)⁻¹ and the scale. A λ
  # the criterion cannot be worked out at gives `:none`, an atom, which Erlang orders after every
  # number, so neither the scan's least nor the narrowing settles on one.
  defp fit(gram, response, penalty, group_sums) do
    criterion = fn log_lambda ->
      criterion(log_lambda, gram, response, penalty, group_sums)
    end

    scale_guess = :math.log(trace(gram) / trace(penalty))

    least =
      -@reach..@reach
      |> Enum.map(fn step -> scale_guess + step end)
      |> Enum.min_by(criterion)

    log_lambda = narrowed(criterion, least - 1, least + 1)
    fitted(:math.exp(log_lambda), gram, response, penalty, group_sums)
  end

  # REML's criterion at log λ, or `:none` where Xᵀ W X + λ S is not positive definite as rounded
  # or D, as rounded, is not above 0, as it can come out at the least λ for rows on a line.
  defp criterion(log_lambda, gram, response, penalty, group_sums) do
    lambda = :math.exp(log_lambda)
    matrix = penalised(gram, penalty, lambda)

    with {:ok, factor} <- Matrix.cholesky(matrix),
         coefficients = Matrix.solve(factor, response),
         deviance = group_sums.squares - Matrix.dot(coefficients, response),
         true <- deviance > 0 do
      (group_sums.weighted_rows - 1) * :math.log(deviance) + Matrix.log_determinant(factor) -
        (@knots - 1) * log_lambda
    else
      _none -> :none
    end
  end

  defp penalised(gram, penalty, lambda), do: Matrix.add(gram, Matrix.scale(penalty, lambda))

  defp trace(matrix) do
    matrix
    |> Enum.with_index()
    |> Enum.map(fn {row, index} -> Enum.at(row, index) end)
    |> Enum.sum()
  end

  # Golden-section search for the least of `criterion` between `low` and `high`, until they are
  # within the narrowest width.
  defp narrowed(criterion, low, high) do
    inner_low = high - @golden * (high - low)
    inner_high = low + @golden * (high - low)

    narrowed(
      criterion,
      {low, high},
      {inner_low, criterion.(inner_low)},
      {inner_high, criterion.(inner_high)}
    )
  end

  defp narrowed(_criterion, {low, high}, _inner_low, _inner_high) when high - low < @narrowest,
    do: (low + high) / 2

  defp narrowed(criterion, {low, high}, {at_low, value_low} = inner_low, {at_high, value_high}) do
    if value_low < value_high do
      moved = at_high - @golden * (at_high - low)
      narrowed(criterion, {low, at_high}, {moved, criterion.(moved)}, inner_low)
    else
      moved = at_low + @golden * (high - at_low)
      narrowed(criterion, {at_low, high}, {at_high, value_high}, {moved, criterion.(moved)})
    end
  end

  defp fitted(lambda, gram, response, penalty, group_sums) do
    {:ok, factor} =
      gram
      |> penalised(penalty, lambda)
      |> Matrix.cholesky()

    coefficients = Matrix.solve(factor, response)
    covariance = Matrix.inverse(factor)
    deviance = group_sums.squares - Matrix.dot(coefficients, response)
    roughness = lambda * Matrix.dot(coefficients, Matrix.multiply_vector(penalty, coefficients))

    degrees_of_freedom =
      Enum.zip_reduce(covariance, gram, 0.0, fn covariance_row, gram_row, sum ->
        sum + Matrix.dot(covariance_row, gram_row)
      end)

    # The residuals' sum of squares, D less the penalty's part, is 0 where the curve passes through
    # every row, a straight line's say, and may come out just below it in rounding, where R's comes
    # out just above it, its band rounding's width.
    residual_squares = max(deviance - roughness, 0.0)
    scale = residual_squares / (group_sums.rows - degrees_of_freedom)
    %{coefficients: coefficients, covariance: covariance, scale: scale, centre: group_sums.centre}
  end

  # The curve's row at a place.
  defp curve_row(place, spline, fit, se, level) do
    basis = basis(spline, place)
    value = Matrix.dot(basis, fit.coefficients) + fit.centre
    band(place, value, basis, fit, se, level)
  end

  defp band(place, value, _basis, _fit, false, _level), do: %{x: place, y: value}

  defp band(place, value, basis, fit, true, level) do
    spread = Matrix.dot(basis, Matrix.multiply_vector(fit.covariance, basis))
    error = :math.sqrt(fit.scale * spread)
    reach = NormalDistribution.central_quantile(level) * error
    %{x: place, y: value, ymin: value - reach, ymax: value + reach, se: error}
  end

  # The basis's row at a place, the spline's value there from its knot values: in the knot
  # interval holding it, its four weights through that interval's rows; past an end knot, the end
  # knot's value plus the distance across the range times the slope there.
  defp basis(%{knots: knots, first: first, range: range, widths: widths} = spline, place) do
    last = List.last(knots)

    cond do
      place < first ->
        width = hd(widths)

        slope =
          combined([
            {-1 / width, unit(0)},
            {1 / width, unit(1)},
            {-width / 6, Enum.at(spline.bends, 1)}
          ])

        combined([{1.0, unit(0)}, {(place - first) / range, slope}])

      place > last ->
        width = List.last(widths)

        slope =
          combined([
            {-1 / width, unit(@knots - 2)},
            {1 / width, unit(@knots - 1)},
            {width / 6, Enum.at(spline.bends, @knots - 2)}
          ])

        combined([{1.0, unit(@knots - 1)}, {(place - last) / range, slope}])

      true ->
        index =
          knots
          |> tl()
          |> Enum.find_index(fn knot -> place <= knot end)

        low = Enum.at(knots, index)
        high = Enum.at(knots, index + 1)
        lower = (high - place) / (high - low)
        upper = (place - low) / (high - low)
        curvature = curvature(Enum.at(widths, index))

        weights = [
          lower,
          upper,
          curvature * (lower * lower * lower - lower),
          curvature * (upper * upper * upper - upper)
        ]

        weights
        |> Enum.zip(interval_basis(spline, index))
        |> combined()
    end
  end

  # The sum of vectors, each times its coefficient.
  defp combined(terms) do
    Enum.reduce(terms, List.duplicate(0.0, @knots), fn {coefficient, vector}, sum ->
      Enum.zip_with(sum, vector, fn total, entry -> total + coefficient * entry end)
    end)
  end
end
