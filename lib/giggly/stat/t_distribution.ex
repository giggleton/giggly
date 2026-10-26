defmodule Giggly.Stat.TDistribution do
  @moduledoc false

  # Student's t distribution, as far as a smooth's band reads it: the t within which a share `level`
  # of the distribution lies, so a band from `y - t * se` to `y + t * se` holds that share, R's
  # `-qt((1 - level) / 2, df)`, which `predict()` reads for a linear fit's band. It is Giggly's own
  # (design-log §4, the entry beginning "Smoothing and densities are Phase 3's twelfth increment"):
  # no Elixir library has the distribution, so it is worked out from its closed form, never from R's
  # source.
  #
  # The share within `-t` and `t`, A(t | ν), is Abramowitz and Stegun's 26.7.3 for an odd number of
  # degrees of freedom ν and 26.7.4 for an even one, with θ = atan(t / √ν):
  #
  #   * ν = 1: 2θ / π;
  #   * ν odd, above 1: (2 / π) (θ + sin θ cos θ (1 + 2/3 cos²θ + (2·4)/(3·5) cos⁴θ + ...)), up to
  #     cos^(ν - 3) θ;
  #   * ν even: sin θ (1 + 1/2 cos²θ + (1·3)/(2·4) cos⁴θ + ...), up to cos^(ν - 2) θ.
  #
  # A series has ν / 2 terms, so tens of thousands for a fit of as many rows. cos²θ = ν / (ν + t²)
  # is then within a hair of 1, and its powers taken from that rounded double would drift by the
  # power times its rounding; so each 32nd power is worked out afresh as exp(k log(1 - u)), u =
  # t² / (ν + t²) held to its last bit, and the powers between from it, and the terms are added
  # with Neumaier's compensation, of which only its first case arises: the running sum, from 1, is
  # never smaller than a term. The t is then found by bisection: doubling from 1 until the share
  # reaches `level`, then halving the interval until its ends are neighbouring doubles, the upper
  # kept, the least double whose share reaches `level`.
  #
  # Against R's `qt()` over 1 to 100,000 degrees of freedom it is within 7e-14 of R's quantile,
  # relatively, for levels from 0.1 to 0.99, and 4e-13 at 0.999. Past about 0.99999 the share
  # within `-t` and `t` holds the little left outside it to fewer digits than R's tail, so the
  # quantile drifts further, 1.2e-10 at 0.999999; near a level of 0, R's is the one that drifts,
  # where Giggly's agrees with exact arithmetic. One quantile takes a third of a millisecond at
  # 232 degrees of freedom and about 130 at 100,000.
  #
  # A fractional number of degrees of freedom, as a loess band's are, has no such series: its share
  # outside `-t` and `t` is the regularized incomplete beta function I_x(ν / 2, 1/2) at x = ν / (ν
  # + t²), worked out where t² is at least ν from its continued fraction (NIST DLMF 8.17.22) by
  # Lentz's method, which converges in a few steps there; and below that, from its symmetry, the
  # share within as I_(1 - x)(1/2, ν / 2), summed from its series of positive terms (DLMF 8.17.8),
  # each the last times (ν / 2 + 1/2 + n) (1 - x) / (n + 3/2), so nothing cancels. The continued
  # fraction runs through hundreds of steps where x is near 1 and its rounding adds up past
  # 1e-12, and the series past t² of ν grows for as many terms as there are degrees of freedom.
  # Both need the beta function B(ν / 2, 1/2) = √π Γ(ν / 2) / Γ(ν / 2 + 1/2), whose logarithm takes
  # the difference of the two log-gammas from Stirling's series (Abramowitz and Stegun 6.1.41),
  # each argument raised to 20 or more by the recurrence Γ(x + 1) = x Γ(x), with its leading terms
  # taken together, so nothing large cancels. The t is found by the same bisection. Against R's
  # `qt()` at 2,000 random fractional degrees of freedom from 0.3 to 100,000 and levels from 0.05
  # to 0.999 it is within 1.6e-13 of R's quantile, relatively; over a grid of them, within 1e-12
  # but at the fewest degrees of freedom and highest levels, 1.1e-12 at 0.3 and 0.999, where R's
  # own is 9.4e-13 from the quantile worked out in 50-digit decimals and Giggly's 1.9e-13.

  # How many powers of cos²θ are taken from the one before before one is worked out afresh.
  @power_block 32

  # The least argument Stirling's series is summed at, the log-gamma of a smaller one reached by the
  # recurrence: there its first omitted term is below 1e-17.
  @stirling_from 20

  # How near 1 each step of the continued fraction must leave it before the fraction stops.
  @fraction_tolerance 1.0e-16

  # The t within which a share `level`, above 0 and below 1, of the t distribution with
  # `degrees_of_freedom` lies, a whole number or a fraction: NaN for none, as R's `qt()` gives it.
  @doc false
  @spec central_quantile(float(), number()) :: float() | :nan
  def central_quantile(_level, degrees_of_freedom) when degrees_of_freedom == 0, do: :nan

  def central_quantile(level, degrees_of_freedom)
      when is_float(level) and level > 0 and level < 1 and is_number(degrees_of_freedom) and
             degrees_of_freedom > 0 do
    high = bracket(1.0, level, degrees_of_freedom)
    bisect(0.0, high, level, degrees_of_freedom)
  end

  # The first of 1, 2, 4, ... within which at least `level` lies.
  defp bracket(high, level, degrees_of_freedom) do
    if share_within(high, degrees_of_freedom) >= level,
      do: high,
      else: bracket(high * 2, level, degrees_of_freedom)
  end

  defp bisect(low, high, level, degrees_of_freedom) do
    middle = low + (high - low) / 2

    cond do
      middle == low or middle == high ->
        high

      share_within(middle, degrees_of_freedom) < level ->
        bisect(middle, high, level, degrees_of_freedom)

      true ->
        bisect(low, middle, level, degrees_of_freedom)
    end
  end

  # A(t | ν), the share of the distribution within `-quantile` and `quantile`.
  defp share_within(quantile, 1), do: 2 * :math.atan(quantile) / :math.pi()

  defp share_within(quantile, degrees_of_freedom) when is_float(degrees_of_freedom) do
    half = degrees_of_freedom / 2
    spread = quantile * quantile + degrees_of_freedom
    log_beta = 0.5 * :math.log(:math.pi()) - log_gamma_step(half)
    log_complement = 2 * :math.log(quantile) - :math.log(spread)

    # log x as the logarithm of 1 less the share t² takes where x is near 1, and of the ratio
    # where it is not, so neither rounds away.
    if quantile * quantile < degrees_of_freedom do
      log_x = log1p(-(quantile * quantile / spread))
      incomplete_beta_series(0.5, half, log_complement, log_x, log_beta)
    else
      log_x = :math.log(degrees_of_freedom) - :math.log(spread)
      1 - incomplete_beta(half, 0.5, log_x, log_complement, log_beta)
    end
  end

  defp share_within(quantile, degrees_of_freedom) do
    spread = quantile * quantile + degrees_of_freedom
    cosine_squared = degrees_of_freedom / spread
    log_cosine_squared = log1p(-(quantile * quantile / spread))
    powers = {cosine_squared, log_cosine_squared}

    # The last power of cos²θ is ν - 3 for an odd ν and ν - 2 for an even one, so either series
    # runs to the term half ν, rounded down, less one.
    last = div(degrees_of_freedom, 2) - 1

    if rem(degrees_of_freedom, 2) == 1 do
      root = :math.sqrt(degrees_of_freedom)
      theta = :math.atan2(quantile, root)
      terms = series(last, powers, &odd_ratio/1)
      2 / :math.pi() * (theta + quantile * root / spread * terms)
    else
      terms = series(last, powers, &even_ratio/1)
      quantile / :math.sqrt(spread) * terms
    end
  end

  # Each odd term's coefficient over the one before, (2k) / (2k + 1), and each even term's,
  # (2k - 1) / (2k).
  defp odd_ratio(index), do: 2 * index / (2 * index + 1)
  defp even_ratio(index), do: (2 * index - 1) / (2 * index)

  # The sum of the terms from the 0th, 1, to the `last`th, each its coefficient times the power of
  # cos²θ, the coefficients built by `ratio`, added with Neumaier's compensation.
  defp series(last, powers, ratio), do: summed(1, last, powers, ratio, {1.0, 1.0}, {1.0, 0.0})

  defp summed(index, last, _powers, _ratio, _term, {total, compensation}) when index > last,
    do: total + compensation

  defp summed(index, last, powers, ratio, {coefficient, power}, sum) do
    coefficient = coefficient * ratio.(index)
    power = next_power(index, power, powers)

    summed(index + 1, last, powers, ratio, {coefficient, power}, add(sum, coefficient * power))
  end

  # cos²θ to the `index`th power: worked out afresh from its logarithm at each block's start, and
  # from the one before within a block.
  defp next_power(index, _power, {_cosine_squared, log_cosine_squared})
       when rem(index, @power_block) == 0,
       do: :math.exp(index * log_cosine_squared)

  defp next_power(_index, power, {cosine_squared, _log_cosine_squared}),
    do: power * cosine_squared

  # A term added to a running sum with Neumaier's compensation for what the addition rounds away,
  # in the case where the sum is the larger: it starts at 1, and every term is at most 1.
  defp add({total, compensation}, term) do
    sum = total + term
    {sum, compensation + (total - sum + term)}
  end

  # I_y(p, q), the regularized incomplete beta function at y, from log y, log(1 - y) and log B(p,
  # q): its factor y^p (1 - y)^q / (p B(p, q)) over its continued fraction 1 + d1 / (1 + d2 / (1 +
  # ...)), d(2m + 1) = -(p + m)(p + q + m) y / ((p + 2m)(p + 2m + 1)) and d(2m) = m(q - m) y / ((p +
  # 2m - 1)(p + 2m)), evaluated by Lentz's method without its stand-in for a zero denominator: at y
  # of 1/2 or less, where it is read, every denominator and ratio the method takes stays above 1/2,
  # checked over p from 0.15 to 50,000.
  defp incomplete_beta(p, q, log_y, log_complement, log_beta) do
    factor = :math.exp(p * log_y + q * log_complement - :math.log(p) - log_beta)
    factor / fraction(1, p, q, :math.exp(log_y), {1.0, 1.0, 0.0})
  end

  defp fraction(step, p, q, y, {value, previous, denominator}) do
    coefficient = fraction_coefficient(step, p, q, y)
    denominator = 1 + coefficient * denominator
    previous = 1 + coefficient / previous
    change = previous / denominator
    value = value * change

    if abs(change - 1) < @fraction_tolerance,
      do: value,
      else: fraction(step + 1, p, q, y, {value, previous, 1 / denominator})
  end

  defp fraction_coefficient(step, p, q, y) when rem(step, 2) == 1 do
    m = div(step, 2)
    -((p + m) * (p + q + m) * y) / ((p + 2 * m) * (p + 2 * m + 1))
  end

  defp fraction_coefficient(step, p, q, y) do
    m = div(step, 2)
    m * (q - m) * y / ((p + 2 * m - 1) * (p + 2 * m))
  end

  # I_y(p, q) from its series: its factor y^p (1 - y)^q / (p B(p, q)) times 1 plus the sum of the
  # terms T(0) = (p + q) y / (p + 1) and T(n + 1) = T(n) (p + q + n + 1) y / (p + n + 2), all
  # positive, until one no longer changes the sum.
  defp incomplete_beta_series(p, q, log_y, log_complement, log_beta) do
    factor = :math.exp(p * log_y + q * log_complement - :math.log(p) - log_beta)
    y = :math.exp(log_y)
    factor * series_sum(0, p, q, y, (p + q) * y / (p + 1), 1.0)
  end

  defp series_sum(index, p, q, y, term, sum) do
    next = sum + term

    if next == sum,
      do: sum,
      else: series_sum(index + 1, p, q, y, term * (p + q + index + 1) * y / (p + index + 2), next)
  end

  # log Γ(x + 1/2) - log Γ(x): for x of 20 or more, Stirling's series, log Γ(x) = (x - 1/2) log x
  # - x + log √(2π) + δ(x), with the leading terms of the two taken together, x log(1 + 1/(2x)) +
  # (1/2) log x - 1/2, so they cancel nothing; for a smaller x, the same at x + k less the
  # logarithms of (x + j + 1/2) / (x + j) for j below k, by the recurrence.
  defp log_gamma_step(x) when x >= @stirling_from do
    x * log1p(1 / (2 * x)) + 0.5 * :math.log(x) - 0.5 + stirling_tail(x + 0.5) - stirling_tail(x)
  end

  defp log_gamma_step(x), do: log_gamma_step(x + 1) - log1p(0.5 / x)

  # δ(x), Stirling's series past its leading terms: 1/(12x) - 1/(360x³) + 1/(1260x⁵) - 1/(1680x⁷) +
  # 1/(1188x⁹), its next term below 1e-17 for x of 20 or more.
  defp stirling_tail(x) do
    inverse = 1 / x
    square = inverse * inverse

    inverse *
      (1 / 12 -
         square * (1 / 360 - square * (1 / 1260 - square * (1 / 1680 - square * (1 / 1188)))))
  end

  # log(1 + value) held to its last bits for a `value` near 0, where `1 + value` rounds most of
  # them away: the logarithm of the rounded sum, scaled by how far rounding moved it.
  defp log1p(value) do
    sum = 1.0 + value
    if sum == 1.0, do: value, else: :math.log(sum) * value / (sum - 1.0)
  end
end
