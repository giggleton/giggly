defmodule Giggly.Stat.NormalDistribution do
  @moduledoc false

  # The standard normal distribution, as far as a gam smooth's band reads it: the z within which a
  # share `level` of the distribution lies, so a band from `y - z * se` to `y + z * se` holds that
  # share, R's `qnorm(level / 2 + 0.5)`, which ggplot2 reads for a gam's band, as its `predictdf()`
  # reads any glm's. It is Giggly's own, as the t distribution is (`Giggly.Stat.TDistribution`):
  # the share outside `-z` and `z` is erfc(z / √2), the complementary error function, Erlang's
  # `:math.erfc`, and z is found by the t quantile's bisection, doubling from 1 until the share
  # outside is at most 1 - `level`, then halving the interval until its ends are neighbouring
  # doubles, the upper kept. Against R's `qnorm()` it is within 1e-14 of R's quantile, relatively,
  # for levels from 0.01 to 0.999, 5.4e-13 at 0.99999 and 4.5e-12 at 0.999999, where 1 - `level`
  # holds the little left outside to fewer digits.

  # The z within which a share `level`, above 0 and below 1, of the standard normal distribution
  # lies.
  @doc false
  @spec central_quantile(float()) :: float()
  def central_quantile(level) when is_float(level) and level > 0 and level < 1 do
    outside = 1 - level
    high = bracket(1.0, outside)
    bisect(0.0, high, outside)
  end

  # The first of 1, 2, 4, ... outside which at most `outside` lies.
  defp bracket(high, outside) do
    if share_outside(high) <= outside,
      do: high,
      else: bracket(high * 2, outside)
  end

  defp bisect(low, high, outside) do
    middle = low + (high - low) / 2

    cond do
      middle == low or middle == high -> high
      share_outside(middle) > outside -> bisect(middle, high, outside)
      true -> bisect(low, middle, outside)
    end
  end

  # The share of the distribution outside `-quantile` and `quantile`.
  defp share_outside(quantile), do: :math.erfc(quantile / :math.sqrt(2))
end
