defmodule Giggly.Stat.TDistribution do
  @moduledoc false

  # Student's t distribution with a whole number of degrees of freedom, as far as a smooth's band
  # reads it: the t within which a share `level` of the distribution lies, so a band from `y - t *
  # se` to `y + t * se` holds that share, R's `-qt((1 - level) / 2, df)`, which `predict()` reads
  # for a linear fit's band. It is Giggly's own (design-log §4, the entry beginning "Smoothing and
  # densities are Phase 3's twelfth increment"): no Elixir library has the distribution, so it is
  # worked out from its closed form, never from R's source.
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
  # with Neumaier's compensation. The t is then found by bisection: doubling from 1 until the share
  # reaches `level`, then halving the interval until its ends are neighbouring doubles, the end
  # whose share lies nearer `level` kept.
  #
  # Against R's `qt()` over 1 to 100,000 degrees of freedom it is within 7e-14 of R's quantile,
  # relatively, for levels from 0.1 to 0.99, and 4e-13 at 0.999. Past about 0.99999 the share
  # within `-t` and `t` holds the little left outside it to fewer digits than R's tail, so the
  # quantile drifts further, 1.2e-10 at 0.999999; near a level of 0, R's is the one that drifts,
  # where Giggly's agrees with exact arithmetic. One quantile takes a third of a millisecond at
  # 232 degrees of freedom and about 130 at 100,000.

  # How many powers of cos²θ are taken from the one before before one is worked out afresh.
  @power_block 32

  # The t within which a share `level`, above 0 and below 1, of the t distribution with
  # `degrees_of_freedom` lies: NaN for none, as R's `qt()` gives it.
  @doc false
  @spec central_quantile(float(), non_neg_integer()) :: float() | :nan
  def central_quantile(_level, 0), do: :nan

  def central_quantile(level, degrees_of_freedom)
      when is_float(level) and level > 0 and level < 1 and is_integer(degrees_of_freedom) and
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
        nearer(low, high, level, degrees_of_freedom)

      share_within(middle, degrees_of_freedom) < level ->
        bisect(middle, high, level, degrees_of_freedom)

      true ->
        bisect(low, middle, level, degrees_of_freedom)
    end
  end

  # Of two neighbouring doubles, the one whose share lies nearer `level`, the lower on a tie.
  defp nearer(low, high, level, degrees_of_freedom) do
    low_gap = abs(share_within(low, degrees_of_freedom) - level)
    high_gap = abs(share_within(high, degrees_of_freedom) - level)
    if low_gap <= high_gap, do: low, else: high
  end

  # A(t | ν), the share of the distribution within `-quantile` and `quantile`.
  defp share_within(quantile, 1), do: 2 * :math.atan(quantile) / :math.pi()

  defp share_within(quantile, degrees_of_freedom) do
    spread = quantile * quantile + degrees_of_freedom
    cosine_squared = degrees_of_freedom / spread
    log_cosine_squared = log1p(-(quantile * quantile / spread))
    powers = {cosine_squared, log_cosine_squared}

    if rem(degrees_of_freedom, 2) == 1 do
      root = :math.sqrt(degrees_of_freedom)
      theta = :math.atan2(quantile, root)
      terms = series(div(degrees_of_freedom - 3, 2), powers, &odd_ratio/1)
      2 / :math.pi() * (theta + quantile * root / spread * terms)
    else
      terms = series(div(degrees_of_freedom - 2, 2), powers, &even_ratio/1)
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

  # A term added to a running sum with Neumaier's compensation for what the addition rounds away.
  defp add({total, compensation}, term) do
    sum = total + term

    lost =
      if abs(total) >= abs(term),
        do: total - sum + term,
        else: term - sum + total

    {sum, compensation + lost}
  end

  # log(1 + value) held to its last bits for a `value` near 0, where `1 + value` rounds most of
  # them away: the logarithm of the rounded sum, scaled by how far rounding moved it.
  defp log1p(value) do
    sum = 1.0 + value
    if sum == 1.0, do: value, else: :math.log(sum) * value / (sum - 1.0)
  end
end
