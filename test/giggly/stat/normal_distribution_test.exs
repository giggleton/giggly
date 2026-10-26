defmodule Giggly.Stat.NormalDistributionTest do
  use ExUnit.Case, async: true

  alias Giggly.Stat.NormalDistribution

  describe "central_quantile/1" do
    # Golden: R 4.6.1's `qnorm(level / 2 + 0.5)`, as ggplot2 reads a gam's band, printed to 17
    # significant digits. Up to a level of 0.999 each is within 1e-14 of R's, relatively; past it 1 -
    # `level` holds the little left outside to fewer digits, 5.4e-13 at 0.99999 and 4.5e-12 at
    # 0.999999.
    test "is R's quantile within 1e-14 for levels from 0.01 to 0.999" do
      table = [
        {0.01, 0.012533469508069278},
        {0.1, 0.12566134685507413},
        {0.5, 0.6744897501960817},
        {0.8, 1.2815515655446008},
        {0.9, 1.6448536269514715},
        {0.95, 1.9599639845400536},
        {0.99, 2.5758293035489},
        {0.999, 3.2905267314919255}
      ]

      for {level, quantile} <- table do
        assert abs(NormalDistribution.central_quantile(level) - quantile) <= 1.0e-14 * quantile,
               "level #{level}"
      end

      assert abs(NormalDistribution.central_quantile(0.99999) - 4.417173413467605) <=
               1.0e-12 * 4.417173413467605

      assert abs(NormalDistribution.central_quantile(0.999999) - 4.891638475671084) <=
               1.0e-11 * 4.891638475671084
    end
  end
end
