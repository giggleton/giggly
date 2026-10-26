defmodule Giggly.Stat.TDistributionTest do
  use ExUnit.Case, async: true

  alias Giggly.Stat.TDistribution

  # The levels each row of the table gives R's quantile at.
  @levels [0.5, 0.9, 0.95, 0.99, 0.999]

  describe "central_quantile/2" do
    # Golden: R 4.6.1's `-qt((1 - level) / 2, df)`, as `predict()` reads a linear fit's band, at
    # each of the levels, printed to 17 significant digits. 1e-12 relatively is the bar a smooth's
    # band is held to (design-log §4, the entry beginning "A stat's values reached by another
    # route"); each sits within 4e-13.
    test "is R's quantile within 1e-12 for 1 to 100,000 degrees of freedom, odd and even" do
      table = [
        {1,
         [
           1.0000000000000002,
           6.3137515146750447,
           12.706204736174694,
           63.656741162871526,
           636.6192487687191
         ]},
        {2,
         [
           0.81649658092772592,
           2.919985580353726,
           4.3026527297494619,
           9.9248432009182892,
           31.599054576443603
         ]},
        {3,
         [
           0.76489232840434518,
           2.3533634348018255,
           3.1824463052837078,
           5.8409093097333544,
           12.923978636687481
         ]},
        {4,
         [
           0.74069708411268265,
           2.1318467863266499,
           2.7764451051977934,
           4.6040948713499921,
           8.6103015813792716
         ]},
        {5,
         [
           0.72668684380042292,
           2.0150483733330238,
           2.5705818356363137,
           4.0321429835552287,
           6.868826625881109
         ]},
        {10,
         [
           0.69981206131243168,
           1.8124611228116765,
           2.2281388519862739,
           3.16927267261695,
           4.5868938587026351
         ]},
        {30,
         [
           0.68275569332129227,
           1.6972608865939582,
           2.0422724563012378,
           2.7499956535672254,
           3.6459586350420214
         ]},
        {31,
         [
           0.68248630600257232,
           1.6955187825458657,
           2.0395134463964082,
           2.7440419192942689,
           3.6334563497583301
         ]},
        {100,
         [
           0.67695104301147091,
           1.6602343260853236,
           1.9839715185235516,
           2.6258905214380182,
           3.3904913111642299
         ]},
        {232,
         [
           0.67554870474654938,
           1.6514480623403665,
           1.9702419362015688,
           2.5971864374612963,
           3.3329550384009323
         ]},
        {1000,
         [
           0.67473516460700933,
           1.6463788172854645,
           1.9623390808264076,
           2.5807546980659501,
           3.3002826484239121
         ]},
        {53_938,
         [
           0.67449429868508526,
           1.6448818778224392,
           1.9600079669561565,
           2.5759204584192616,
           3.2907071277836115
         ]},
        {100_000,
         [
           0.6744922035532922,
           1.6448688647849694,
           1.9599877075346088,
           2.5758784699083743,
           3.2906240314118822
         ]}
      ]

      for {degrees_of_freedom, quantiles} <- table,
          {level, expected} <- Enum.zip(@levels, quantiles) do
        quantile = TDistribution.central_quantile(level, degrees_of_freedom)

        assert abs(quantile - expected) <= 1.0e-12 * expected,
               "#{degrees_of_freedom} degrees of freedom at #{level}: #{quantile}, R #{expected}"
      end
    end

    # One and two degrees of freedom have quantiles in closed form, tan(π level / 2) and level √2 /
    # √(1 - level²), which hold near a level of 0, where R's `qt()` drifts from exact arithmetic,
    # and near 1, where the share within the quantile holds fewer of its digits.
    test "is the closed form's quantile for one and two degrees of freedom, at either end" do
      for level <- [1.0e-7, 0.25, 0.75, 0.9999] do
        cauchy = :math.tan(:math.pi() * level / 2)
        two = level * :math.sqrt(2) / :math.sqrt(1 - level * level)

        assert_in_delta TDistribution.central_quantile(level, 1), cauchy, 1.0e-12 * cauchy
        assert_in_delta TDistribution.central_quantile(level, 2), two, 1.0e-12 * two
      end
    end

    test "is NaN for no degrees of freedom, as R's qt() is" do
      assert TDistribution.central_quantile(0.95, 0) == :nan
      assert TDistribution.central_quantile(0.95, 0.0) == :nan
    end

    # Golden: R 4.6.1's `qt(level / 2 + 0.5, df)` at fractional degrees of freedom, as a loess band
    # reads them, printed to 17 significant digits; a sweep of 2,000 random ones from 0.3 to 100,000
    # sat within 1.6e-13, each worked from the incomplete beta function.
    test "is R's quantile within 1e-12 for fractional degrees of freedom" do
      for {level, degrees_of_freedom, expected} <- [
            {0.95, 2.37, 3.7189208397974554},
            {0.95, 3.02, 3.1705564372379627},
            {0.99, 7.6, 3.4073472798512054},
            {0.95, 26.93, 2.052080099840897},
            {0.5, 228.56, 0.6755646653583568},
            {0.999, 993.93, 3.3003423897184203},
            {0.8, 0.5, 10.270324410234281},
            {0.95, 100_000.5, 1.9599877074159935}
          ] do
        quantile = TDistribution.central_quantile(level, degrees_of_freedom)

        assert abs(quantile - expected) <= 1.0e-12 * expected,
               "level #{level}, #{degrees_of_freedom} degrees of freedom: #{quantile}"
      end
    end

    # The incomplete beta function's quantile at a whole number held as a float, beside the closed
    # form's at that number, either side of t² against the degrees of freedom: each is held to R's
    # within 1e-12, so they are to each other.
    test "a whole number of degrees of freedom held as a float is the closed form's quantile" do
      for {level, degrees_of_freedom} <- [{0.95, 26}, {0.5, 228}, {0.999, 98_105}, {0.2, 3}] do
        whole = TDistribution.central_quantile(level, degrees_of_freedom)
        fractional = TDistribution.central_quantile(level, degrees_of_freedom / 1)

        assert abs(whole - fractional) <= 1.0e-12 * whole
      end
    end

    # Golden: R 4.6.1's `-qt((1 - 0.999) / 2, 86377)`, where summing the series without Neumaier's
    # compensation misses by 1.1e-12.
    test "is R's quantile within 1e-12 where plain summation would not be" do
      expected = 3.2906393776039278
      quantile = TDistribution.central_quantile(0.999, 86_377)

      assert abs(quantile - expected) <= 1.0e-12 * expected
    end

    # Golden: R 4.6.1's `dt(0, 100)`. Near a level of 0 the quantile is the level over twice the
    # density at 0, to first order, and the cos²θ that 66 or more degrees of freedom work out afresh
    # from its logarithm rounds to 1.
    test "is the level over twice the density at 0 for a level near 0" do
      expected = 1.0e-9 / (2 * 0.39794618693589384)
      quantile = TDistribution.central_quantile(1.0e-9, 100)

      assert abs(quantile - expected) <= 1.0e-12 * expected
    end

    test "refuses a level of 0, 1 or past it, and degrees of freedom below 0" do
      for {level, degrees_of_freedom} <- [{0.0, 5}, {1.0, 5}, {1.5, 5}, {0.95, -1}] do
        assert_raise FunctionClauseError, fn ->
          TDistribution.central_quantile(level, degrees_of_freedom)
        end
      end
    end
  end
end
