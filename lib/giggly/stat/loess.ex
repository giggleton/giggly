defmodule Giggly.Stat.Loess do
  @moduledoc false

  # A loess curve, R's `loess(y ~ x, weights = weight, span = span)` worked out directly at each
  # place, as R's `surface = "direct"` works it (design-log §4, the entry beginning "loess is
  # Giggly's own"), with its band, for smoothing (`Giggly.Stat.Smooth`). It works on one group's
  # rows as lists, since no frame engine could run it (design-log §4, the entry beginning
  # "Smoothing and densities compute over the rows"), in plain Elixir rather than Nx, which on its
  # binary backend takes some thirty times as long over these small fits (the entry beginning "Nx is
  # a core dependency").
  #
  # At each place x₀ the q = ⌊n × span⌋ rows nearest it, n the rows, are weighed by the tricube of
  # their distance over the qth nearest's, d, (1 - (|x - x₀| / d)³)³, so the qth itself weighs
  # nothing, times each row's own weight; for a span past 1, every row, d the largest distance times
  # the span's square root, as R's loess takes it (its documentation says the span itself; checked
  # against R). A quadratic in u = (x - x₀) / d is fitted to them by weighted least squares, its 3
  # by 3 normal equations solved by cofactors, and its value at x₀ is the curve's there. The
  # quadratic's coefficients are linear in the rows' y, so the curve at x₀ is a weighted sum of
  # them, the operator's row ℓ(x₀): ℓⱼ = wⱼ (c₀ + c₁ uⱼ + c₂ uⱼ²), (c₀, c₁, c₂) the first row of the
  # equations' inverse. Checked against R's direct loess within 3e-13 of the curve's range.
  #
  # Its band is the curve ∓ t × se. With L the operator at every row, its first trace δ₁ =
  # trace((I - L)ᵀ(I - L)) = Σᵢⱼ (Iᵢⱼ - Lᵢⱼ)², the residuals' scale s = √(Σ wᵢ rᵢ² / δ₁), rᵢ = yᵢ -
  # (L y)ᵢ, and se at x₀ = s √(Σⱼ ℓⱼ² / wⱼ), as R's exact statistics have them, a row of weight 0
  # making it NaN, 0 over 0, as R's is. t is the quantile holding `level` of the t distribution with
  # δ₁ degrees of freedom (`Giggly.Stat.TDistribution`), where R reads δ₁² / δ₂, whose second trace
  # costs n³ (design-log §4, the entry beginning "A loess band takes its first trace"): the band's
  # edges sit within 5e-5 of the curve's range of R's exact band on ordinary data, nearer than R's
  # own default approximation of the traces.
  #
  # A place outside the rows' extent is missing, as R's default surface leaves it (the entry
  # beginning "A loess curve stops at its rows"). Where a neighbourhood holds fewer than three
  # distinct x weighed above 0, or has no width, the quadratic is undetermined, and the group is
  # fitted nothing, where R warns and returns its pivoted solver's values (the entry beginning "A
  # loess group whose neighbourhoods cannot hold a quadratic"): a neighbourhood at a place, or with
  # the band at a row, whose operator the band reads. Without the band, R's curve is its fits at the
  # places alone, whatever it warns of at the rows.

  alias Giggly.DataFrame.Arithmetic
  alias Giggly.Stat.TDistribution

  # A loess curve's rows at `places`, from one group's rows' `xs`, `ys` and `weights`, all finite,
  # the weights 0 or more: each a map of its place `x` and curve `y`, and with `se` its `ymin`,
  # `ymax` and standard error `se`, at `level`, all but `x` `nil` at a place outside the rows; or
  # `:none` where a neighbourhood cannot hold a quadratic.
  @doc false
  @spec curve([number()], [number()], [number()], [float()], float(), boolean(), float()) ::
          [map()] | :none
  def curve(xs, ys, weights, places, span, se, level) do
    rows = Enum.zip([xs, ys, weights])
    {low, high} = Enum.min_max(xs)
    inside = Enum.filter(places, fn place -> place >= low and place <= high end)

    with {:ok, fits} <- local_fits(rows, inside, span),
         {:ok, band} <- band(rows, span, se, level) do
      fitted = Map.new(fits)
      Enum.map(places, fn place -> row(place, Map.fetch(fitted, place), band) end)
    end
  end

  # A place's row: its fit's, or outside the rows a missing one, its band's columns missing too,
  # which the smooth reads only with its band.
  defp row(place, {:ok, fit}, band), do: curve_row(place, fit, band)
  defp row(place, :error, _band), do: %{x: place, y: nil, ymin: nil, ymax: nil, se: nil}

  # Each place's fit, `{place, {value, operator}}`, or `:none` where any cannot be made.
  defp local_fits(rows, places, span) do
    Enum.reduce_while(places, {:ok, []}, fn place, {:ok, fits} ->
      case local_fit(rows, place, span) do
        {:ok, fit} -> {:cont, {:ok, [{place, fit} | fits]}}
        :none -> {:halt, :none}
      end
    end)
  end

  # The quadratic fitted round `place`: its value there and the operator's row, or `:none` where
  # its neighbourhood has no width.
  defp local_fit(rows, place, span) do
    distances = Enum.map(rows, fn {x, _y, _weight} -> abs(x - place) end)

    case width(distances, span) do
      width when width > 0 -> weighed_fit(rows, distances, place, width)
      _none -> :none
    end
  end

  # The fit from each row's u, y, weight and x, or `:none` where fewer than three distinct x weigh
  # above 0, which a quadratic needs.
  defp weighed_fit(rows, distances, place, width) do
    weighed =
      Enum.zip_with(rows, distances, fn {x, y, weight}, distance ->
        {(x - place) / width, y, tricube(distance, width) * weight, x}
      end)

    distinct =
      weighed
      |> Enum.filter(fn {_u, _y, weight, _x} -> weight > 0 end)
      |> Enum.map(fn {_u, _y, _weight, x} -> x end)
      |> Enum.uniq()

    if Enum.count_until(distinct, 3) == 3, do: {:ok, solved(weighed)}, else: :none
  end

  # d, the neighbourhood's width: the qth nearest distance, or past a span of 1 the largest times
  # the span's square root.
  defp width(distances, span) when span > 1, do: Enum.max(distances) * :math.sqrt(span)

  defp width(distances, span) do
    nearest = floor(length(distances) * span)

    case nearest do
      0 ->
        0.0

      _rows ->
        sorted = Enum.sort(distances)
        Enum.at(sorted, nearest - 1)
    end
  end

  defp tricube(distance, width) when distance < width do
    ratio = distance / width
    lessened = 1 - ratio * ratio * ratio
    lessened * lessened * lessened
  end

  defp tricube(_distance, _width), do: 0.0

  # The fit from the weighed rows `{u, y, weight, x}`: the normal equations' sums of w uᵏ, k up to
  # 4, and of w uᵏ y, k up to 2, the first row of their inverse by cofactors, the value at the place
  # and the operator's row.
  defp solved(weighed) do
    {s0, s1, s2, s3, s4, t0, t1, t2} =
      Enum.reduce(weighed, {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}, fn {u, y, weight, _x},
                                                                        {s0, s1, s2, s3, s4, t0,
                                                                         t1, t2} ->
        wu = weight * u
        wuu = wu * u

        {s0 + weight, s1 + wu, s2 + wuu, s3 + wuu * u, s4 + wuu * u * u, t0 + weight * y,
         t1 + wu * y, t2 + wuu * y}
      end)

    first = s2 * s4 - s3 * s3
    second = -(s1 * s4 - s2 * s3)
    third = s1 * s3 - s2 * s2
    determinant = s0 * first + s1 * second + s2 * third
    {c0, c1, c2} = {first / determinant, second / determinant, third / determinant}
    value = c0 * t0 + c1 * t1 + c2 * t2

    operator =
      Enum.map(weighed, fn {u, _y, weight, _x} -> weight * (c0 + c1 * u + c2 * u * u) end)

    {value, operator}
  end

  # What the band needs from the operator at every row, `{scale, quantile, weights}`, or `nil`
  # without a band; `:none` where a row's neighbourhood cannot hold a quadratic.
  defp band(_rows, _span, false, _level), do: {:ok, nil}

  defp band(rows, span, true, level) do
    xs = Enum.map(rows, fn {x, _y, _weight} -> x end)

    case local_fits(rows, xs, span) do
      {:ok, fits} -> {:ok, band_statistics(rows, Enum.reverse(fits), level)}
      :none -> :none
    end
  end

  # δ₁, the residuals' scale and the t quantile at `level` with δ₁ degrees of freedom.
  defp band_statistics(rows, fits, level) do
    ys = Enum.map(rows, fn {_x, y, _weight} -> y end)
    weights = Enum.map(rows, fn {_x, _y, weight} -> weight end)

    {first_trace, residual_squares} =
      fits
      |> Enum.with_index()
      |> Enum.zip_with(rows, fn {{_place, {_value, operator}}, index}, {_x, y, weight} ->
        fitted = dot(operator, ys)
        residual = y - fitted
        {own_trace(operator, index), weight * residual * residual}
      end)
      |> Enum.reduce({0.0, 0.0}, fn {trace, square}, {traces, squares} ->
        {traces + trace, squares + square}
      end)

    scale =
      residual_squares
      |> Arithmetic.divide(first_trace)
      |> square_root()

    {scale, TDistribution.central_quantile(level, first_trace), weights}
  end

  # A row's part of δ₁: Σⱼ (Iᵢⱼ - Lᵢⱼ)² for the operator's row i.
  defp own_trace(operator, index) do
    operator
    |> Enum.with_index()
    |> Enum.reduce(0.0, fn {entry, column}, total ->
      difference = if column == index, do: 1 - entry, else: -entry
      total + difference * difference
    end)
  end

  defp dot(left, right), do: Enum.zip_reduce(left, right, 0.0, fn a, b, sum -> sum + a * b end)

  defp curve_row(place, {value, _operator}, nil), do: %{x: place, y: value}

  defp curve_row(place, {value, operator}, {scale, quantile, weights}) do
    spread =
      Enum.zip_reduce(operator, weights, 0.0, fn entry, weight, total ->
        Arithmetic.add(total, Arithmetic.divide(entry * entry, weight))
      end)

    error = Arithmetic.multiply(scale, square_root(spread))
    reach = Arithmetic.multiply(quantile, error)

    %{
      x: place,
      y: value,
      ymin: Arithmetic.subtract(value, reach),
      ymax: Arithmetic.add(value, reach),
      se: error
    }
  end

  defp square_root(value) when is_number(value), do: :math.sqrt(value)
  defp square_root(value), do: value
end
