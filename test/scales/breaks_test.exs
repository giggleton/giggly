defmodule Scales.BreaksTest do
  use ExUnit.Case, async: true

  alias Scales.Breaks

  # The examples' breaks are R 4.6.1's `labeling::extended(9.225, 35.075, 5)`,
  # `extended(0, 10, 5)`, the same with `Q = c(1, 2, 1.5, 4, 3)`, and `extended(52, 335, 2)`;
  # scales 1.4.0's `breaks_log()(c(1, 1e5))`, `breaks_log()(c(2000, 9000))`,
  # `breaks_log(base = 2)(c(3, 5))`, `breaks_exp(n = 4)(c(0, 100))`, `breaks_exp()(c(100, 102))`,
  # `breaks_timespan("mins")(c(0, 100))` and `breaks_timespan(n = 3)(c(0, 100))`; and the rest
  # R's `fullseq()` and `breaks_width()`.
  doctest Scales.Breaks

  # Golden: R's own `labeling::extended(low, high, 5)` (labeling 0.4.3, R 4.6.1, run in Docker's
  # `r-base` image), each break printed to 17 significant digits. extended Wilkinson is a search
  # scored on simplicity, coverage and density, so a slip in one score changes the winner only for
  # ranges where that score decides it; each range here is the shortest-written one found for one
  # winning combination of nice number (1, 5, 2, 2.5, 4, 3), skip (1 or 2), break count (4 to 8)
  # and the bonus for passing through zero, so that every score decides some row. The last rows
  # are ranges from 813 random and degenerate ones, all of which the port matches, where a
  # mutation that review's mutation step left alive gives other breaks than R's: there the shape
  # of a score or of the search's pruning, not only which score is highest, decides the winner.
  # It moves only if the port stops matching R, which is a bug.
  @r_breaks [
    {{1.1, 1.4}, [1.1, 1.2000000000000002, 1.3, 1.4000000000000001]},
    {{-2.0, 1.1}, [-2.0, -1.0, 0.0, 1.0]},
    {{4.0, 8.0}, [4.0, 5.0, 6.0, 7.0, 8.0]},
    {{-1.7, 2.0}, [-2.0, -1.0, 0.0, 1.0, 2.0]},
    {{3.8, 9.1}, [4.0, 5.0, 6.0, 7.0, 8.0, 9.0]},
    {{0.6, 5.4}, [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]},
    {{9.0, 9.6}, [9.0, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6]},
    {{-2.7, 3.2}, [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0]},
    {{5.1, 69.0}, [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0]},
    {{2.3, 3.1},
     [2.3000000000000003, 2.5000000000000004, 2.7, 2.9000000000000004, 3.1000000000000005]},
    {{1.9, 2.9}, [1.9000000000000001, 2.1, 2.3000000000000003, 2.5, 2.7, 2.9000000000000004]},
    {{2.4, 8.9}, [2.0, 4.0, 6.0, 8.0]},
    {{0.4, 6.5}, [0.0, 2.0, 4.0, 6.0]},
    {{2.2, 3.1}, [2.2, 2.4000000000000004, 2.6, 2.8000000000000003, 3.0]},
    {{1.1, 7.5}, [0.0, 2.0, 4.0, 6.0, 8.0]},
    {{2.6, 3.7}, [2.6, 2.8000000000000003, 3.0, 3.2, 3.4000000000000004, 3.6]},
    {{-8.3, 1.3}, [-8.0, -6.0, -4.0, -2.0, 0.0, 2.0]},
    {{2.6, 3.8},
     [2.6, 2.8000000000000003, 3.0, 3.2, 3.4000000000000004, 3.6, 3.8000000000000003]},
    {{-7.7, 4.0}, [-8.0, -6.0, -4.0, -2.0, 0.0, 2.0, 4.0]},
    {{2.2, 3.7}, [2.2, 2.6, 3.0, 3.4000000000000004, 3.8000000000000003]},
    {{0.44, 1.3}, [0.5, 0.75, 1.0, 1.25]},
    {{-4.9, 2.6}, [-5.0, -2.5, 0.0, 2.5]},
    {{1.5, 2.5}, [1.5, 1.75, 2.0, 2.25, 2.5]},
    {{1.4, 9.7}, [0.0, 2.5, 5.0, 7.5, 10.0]},
    {{2.2, 3.5}, [2.25, 2.5, 2.75, 3.0, 3.25, 3.5]},
    {{-4.1, 7.6}, [-5.0, -2.5, 0.0, 2.5, 5.0, 7.5]},
    {{0.76, 2.2}, [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25]},
    {{-0.2, 1.3}, [-0.25, 0.0, 0.25, 0.5, 0.75, 1.0, 1.25]},
    {{2.4, 3.6},
     [2.4000000000000004, 2.7, 3.0000000000000004, 3.3000000000000007, 3.6000000000000005]},
    {{-9.4, 2.6}, [-9.0, -6.0, -3.0, 0.0, 3.0]},
    {{2.7, 4.2}, [2.7, 3.0, 3.3000000000000003, 3.6000000000000005, 3.9000000000000004, 4.2]},
    {{1.9, 3.2}, [2.0, 2.4, 2.8, 3.2]},
    {{-4.4, 8.5}, [-4.0, 0.0, 4.0, 8.0]},
    {{1.5, 3.2}, [1.6, 2.0, 2.4000000000000004, 2.8000000000000003, 3.2]},
    {{0.2, 1.6}, [0.0, 0.4, 0.8, 1.2000000000000002, 1.6]},
    {{7.5, 28.0}, [8.0, 12.0, 16.0, 20.0, 24.0, 28.0]},
    {{-1.2, 0.77},
     [
       -1.2000000000000002,
       -0.8000000000000002,
       -0.40000000000000013,
       0.0,
       0.3999999999999999,
       0.7999999999999998
     ]},
    {{1.3, 3.0}, [1.5, 2.0, 2.5, 3.0]},
    {{0.1, 1.4}, [0.0, 0.5, 1.0, 1.5]},
    {{1.2, 3.2}, [1.0, 1.5, 2.0, 2.5, 3.0]},
    {{0.2, 2.0}, [0.0, 0.5, 1.0, 1.5, 2.0]},
    {{5.8, 8.6}, [6.0, 6.5, 7.0, 7.5, 8.0, 8.5]},
    {{-0.8, 1.4}, [-1.0, -0.5, 0.0, 0.5, 1.0, 1.5]},
    {{5.4, 8.5}, [5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5]},
    {{-0.4, 2.6}, [-0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5]},
    {{1.5, 5.5}, [1.5, 2.5, 3.5, 4.5, 5.5]},
    {{-2.8454459622739803, 22.539646152886917}, [0.0, 5.0, 10.0, 15.0, 20.0]},
    {{-127.64969904577114, 83.35437027570634}, [-150.0, -100.0, -50.0, 0.0, 50.0, 100.0]},
    {{-0.0001188766746673246, 9.00877904950166e-06},
     [
       -0.00012000000000000002,
       -9.000000000000002e-05,
       -6.000000000000001e-05,
       -2.9999999999999997e-05,
       0.0
     ]},
    {{1.1023960925732955e-07, 9.512209886584008e-07}, [0.0, 2.5e-07, 5.0e-07, 7.5e-07, 1.0e-06]},
    {{-1_114_521.4184030483, 1_931_586.545608003}, [-1_000_000.0, 0.0, 1_000_000.0, 2_000_000.0]},
    {{-2327.0960655913523, 12_828.392576279577}, [-4000.0, 0.0, 4000.0, 8000.0, 12_000.0]},
    {{0.0005687182043870695, 0.006913090937256849},
     [0.0, 0.001, 0.002, 0.003, 0.004, 0.005, 0.006, 0.007]},
    {{-0.11014927034905725, -0.013424435614324173},
     [-0.1, -0.07500000000000001, -0.05, -0.024999999999999994, 0.0]},
    {{109_529_464.04875724, 687_717_721.6287981},
     [
       100_000_000.0,
       200_000_000.0,
       300_000_000.0,
       400_000_000.0,
       500_000_000.0,
       600_000_000.0,
       700_000_000.0
     ]}
  ]

  test "breaks are R's labeling::extended() breaks for every winning nice number, skip and count" do
    for {extent, r_breaks} <- @r_breaks do
      assert {extent, Breaks.extended(extent)} == {extent, r_breaks}
    end
  end

  test "a range narrower than 100 machine epsilons gets five breaks spaced evenly end to end" do
    assert Breaks.extended({0.001, 0.00100000000001}) ===
             [0.001, 0.0010000000000025, 0.001000000000005, 0.0010000000000075, 0.00100000000001]
  end

  test "a range wider than the square root of the largest float gets five breaks spaced evenly" do
    assert Breaks.extended({-1.0e154, 1.3e154}) ===
             [
               -1.0e154,
               -4.250_000_000_000_000_4e153,
               1.499_999_999_999_999_5e153,
               7.25e153,
               1.3e154
             ]
  end

  test "a best sequence whose span is rounding error beside its size is its first break alone" do
    assert Breaks.extended({1.0e15, 1.0e15 + 0.25}) === [1.0e15]
  end

  # Golden: labeling::extended(low, high, 5), labeling 0.4.3 in R 4.6.1, on a range exactly 100
  # epsilons wide and one exactly sqrt(.Machine$double.xmax) wide, which R searches, being neither
  # narrower nor wider; at the second, squares past the largest double take R's coverage to minus
  # infinity
  test "a range 100 epsilons or the square root of the largest float wide is searched, as R does" do
    assert Breaks.extended({0.0, 100 * 2.220446049250313e-16}) ===
             [
               0.0,
               5.000000000000001e-15,
               1.0000000000000002e-14,
               1.5000000000000002e-14,
               2.0000000000000003e-14
             ]

    assert Breaks.extended({0.0, 1.340_780_792_994_259_6e154}) === [
             0.0,
             5.0e153,
             1.0e154,
             1.5e154
           ]
  end

  # Golden: labeling::extended(321908391.83131832, 321908391.83131838, 5), as above, from R's
  # random ranges: steps of rounding error put a sequence's first and last breaks on one number,
  # whose density R reaches as minus infinity, dividing by zero
  # Golden: labeling::extended(2.0118520021534377e154, 2.6864075978932322e154, 5), as above: a
  # sequence reaching far past the range squares a distance past the largest double, taking R's
  # coverage of it to minus infinity while the bound stays finite
  test "a sequence whose coverage squares past the largest double never wins" do
    assert Breaks.extended({2.011_852_002_153_437_7e154, 2.686_407_597_893_232_2e154}) ===
             [2.0e154, 2.2e154, 2.4e154, 2.600_000_000_000_000_2e154]
  end

  test "a sequence of steps that leave its first and last breaks one number never wins" do
    assert Breaks.extended({321_908_391.83131832, 321_908_391.83131838}) === [
             321_908_391.83131832
           ]
  end

  # Golden: R's own `labeling::extended(low, high, m)` (labeling 0.4.3, R 4.6.1), each break
  # printed to 17 significant digits, for 684 ranges, random and degenerate, and m from 2 to 15
  # (this session's scratchpad `r/ext.R`), all of which match: a random range for each of five
  # counts where five wanted would give other breaks, so the count steers the density score and
  # its bound, and the narrow, the zero-wide and the too-wide ranges, whose breaks are the count
  # spaced evenly. It moves only if the port stops matching R, which is a bug.
  @r_counted_breaks [
    {{1.6329492840570092, 5.139685381437919}, 2, [2.0, 5.0]},
    {{-4.079952342473251, 40.15559576881623}, 3, [0.0, 20.0, 40.0]},
    {{21.813925948942064, 32.471167877330366}, 8, [22.0, 24.0, 26.0, 28.0, 30.0, 32.0]},
    {{1048.463745628539, 5099.781556777183}, 12,
     [1000.0, 1500.0, 2000.0, 2500.0, 3000.0, 3500.0, 4000.0, 4500.0, 5000.0]},
    {{-8.044567559905397, 37.496904388516484}, 15,
     [-10.0, -5.0, 0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0]},
    {{5.0, 5.0}, 2, [5.0, 5.0]},
    {{1.0, 1.000000000000001}, 3, [1.0, 1.0000000000000004, 1.000000000000001]},
    {{1.0e300, 1.5e300}, 7,
     [
       1.0e300,
       1.083_333_333_333_333_4e300,
       1.166_666_666_666_666_7e300,
       1.25e300,
       1.333_333_333_333_333_4e300,
       1.416_666_666_666_666_6e300,
       1.5e300
     ]}
  ]

  test "breaks for another number wanted are R's labeling::extended() breaks for that count" do
    for {extent, wanted, r_breaks} <- @r_counted_breaks do
      assert {extent, wanted, Breaks.extended(extent, n: wanted)} == {extent, wanted, r_breaks}
    end
  end

  # R's search finds no sequence for one break wanted and fails, and for none never ends.
  test "the number of breaks wanted is a whole number from 2, and anything else is refused" do
    for wanted <- [1, 0, -3, 2.5, :five] do
      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Breaks.extended({0.0, 10.0}, n: wanted)
        end

      assert error.message =~
               "expected a whole number of breaks, 2 or more, got: #{inspect(wanted)}"
    end
  end

  # The search stops only on a nice number that cannot win, so none would never stop; one has no
  # place in a list, which R's labeling::extended(0, 10, 5, Q = 1) reaches as NaN and fails on.
  test "the nice numbers are positive numbers, at least two, and anything else is refused" do
    for numbers <- [[], [2], [0, 1], [1, -2], [:five, 1]] do
      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Breaks.extended({0.0, 10.0}, nice_numbers: numbers)
        end

      assert error.message =~ "got: #{inspect(numbers)}"
    end
  end

  # Golden: R's own labeling::extended(low, high, 5, only.loose = TRUE), as above: the breaks the
  # search keeps reach both limits, where the best sequence on its own falls inside one or both
  # (the test above gives those for the first four ranges).
  test "breaks that must reach the limits are the best sequence that does, as R's only.loose" do
    for {range, r_breaks} <- [
          {{0.4, 6.5}, [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]},
          {{2.2, 8.3}, [2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0]},
          {{1.5, 7.5}, [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]},
          {{3.8, 9.1}, [3.5, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5]},
          {{1.1, 9.2}, [0.0, 2.5, 5.0, 7.5, 10.0]}
        ] do
      assert {range, Breaks.extended(range, only_loose: true)} == {range, r_breaks}
    end
  end

  # Golden: labeling::extended(-2.668842, 0.131158, 3, only.loose = TRUE), as above, from 3,000
  # random ranges: two sequences, steps 0.8 and 1.6, score exactly alike, and the first found, the
  # smaller skip, wins; a square taken as `:math.pow/2` takes it lands a bit away from R's product
  # and hands the second the win.
  test "of two sequences scoring alike the first found wins, each square R's own product" do
    assert Breaks.extended({-2.6688420000000002, 0.13115799999999966}, n: 3, only_loose: true) ==
             [
               -2.8000000000000003,
               -2.0,
               -1.2000000000000002,
               -0.3999999999999999,
               0.3999999999999999
             ]
  end

  # Golden: labeling::extended(low, high, 5, w = weights), as above: weighting simplicity or
  # coverage more chooses other breaks than the defaults, 0, 2.5, 5, 7.5 and 10, on each range.
  test "the weights of the four scores are R's w" do
    assert Breaks.extended({0.3, 9.7}, weights: [1, 0.2, 0.5, 0.05]) ==
             [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]

    assert Breaks.extended({1.1, 9.2}, weights: [0.25, 1, 0.5, 0.05]) ==
             [1.0, 3.0, 5.0, 7.0, 9.0]
  end

  # R's labeling::extended(0.3, 9.7, 5, w = c(0.25, 0.2, 0.5, -10)) fails, "'from' must be of
  # length 1": a legibility weight that low takes every score below -2, where its search starts.
  test "weights that leave every sequence scoring below -2 find none, and raise as R fails" do
    error =
      assert_raise ArgumentError, fn ->
        Breaks.extended({0.3, 9.7}, weights: [0.25, 0.2, 0.5, -10])
      end

    assert error.message =~ "no sequence of breaks over {0.3, 9.7} scores above -2"
    assert error.message =~ "[0.25, 0.2, 0.5, -10]"
  end

  # R's search never ends with simplicity, coverage or density weighted 0 or below.
  test "the weights are four numbers, the first three positive, and anything else is refused" do
    for weights <- [
          [0, 0.2, 0.5, 0.05],
          [0.25, 0.0, 0.5, 0.05],
          [0.25, 0.2, -0.5, 0.05],
          [0.25, 0.2, 0.5],
          [0.25, 0.2, 0.5, 0.05, 1],
          [0.25, 0.2, 0.5, :none],
          [:one, 0.2, 0.5, 0.05],
          :default
        ] do
      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Breaks.extended({0.0, 10.0}, weights: weights)
        end

      assert error.message =~
               "expected four weights, of simplicity, coverage, density and legibility, the " <>
                 "first three positive, got: #{inspect(weights)}"
    end
  end

  # Golden: R 4.6.1's scales 1.4.0 `breaks_log(n, base)(c(low, high))` (the giggly-r:ggplot2-4.0.3
  # image), each break printed to 17 significant digits, from 4,000 random limits (this session's
  # scratchpad `step2/sweep.R`), all of which match but 63 in base 1.2 (below): for each base the
  # shortest-written limits taking each of R's branches, every power or every few, a smaller step
  # than the first tried, multiples of the powers, kept with one more each side, the powers alone
  # for a base of 2 or less, extended breaks, and one power; and the limits where a slip in the
  # port first departed from R, as the log10 transformation's test chose them.
  @r_log_breaks [
    {{700.0, 8.0e6}, 5, 10, [100.0, 1000.0, 10_000.0, 100_000.0, 1_000_000.0, 10_000_000.0]},
    {{8.0, 6.0}, 1, 10, [1.0]},
    {{6.0, 3.0}, 5, 10, [2.0, 3.0, 4.0, 5.0, 7.0]},
    {{2.0, 2.0}, 5, 10, [2.0, 2.0, 2.0, 2.0, 2.0]},
    {{10.0, 10.0}, 5, 10, [10.0]},
    {{9.0, 16.0}, 1, 2, [8.0]},
    {{10.0, 1.125}, 4, 2, [1.0, 2.0, 4.0, 8.0, 16.0]},
    {{3.0, 3.0}, 5, 2, [2.0, 4.0]},
    {{10.0, 8.0}, 7, 1.5, [7.59375, 11.390625]},
    {{1.1851851851851851, 7.59375}, 5, 1.5, [1.0, 1.5, 2.25, 3.375, 5.0625, 7.59375]},
    {{1.4715177646857693, 2.9430355293715387}, 4, :math.exp(1),
     [1.0, 2.0, 2.718281828459045, 5.43656365691809]},
    {{10.0, 6.0}, 6, :math.exp(1), [6.0, 7.0, 8.0, 9.0, 10.0]},
    {{2.0, 1.03}, 3, 3, [1.0, 2.0, 3.0]},
    {{25.0, 7.0}, 5, 5, [5.0, 10.0, 15.0, 25.0, 50.0]},
    {{771.75, 441.0}, 5, 10.5, [441.0, 551.25, 661.5, 771.75, 882.0]},
    {{63.0, 6.0}, 2, 10.5, [1.0, 110.25]},
    {{1.0, 8.0}, 6, 16, [1.0, 2.0, 4.0, 8.0, 16.0]},
    {{5026.6985194453346, 1_383_664_092_143_159.8}, 5, 10,
     [1000.0, 1_000_000.0, 1_000_000_000.0, 1_000_000_000_000.0, 1_000_000_000_000_000.0]},
    {{0.0102334543596924, 1_032_592.3367269166}, 5, 10,
     [0.01, 1.0, 100.0, 10_000.0, 1_000_000.0]},
    {{0.18163834220367195, 0.99615005832268066}, 5, 10,
     [0.1, 0.2, 0.30000000000000004, 0.5, 1.0]},
    {{0.0021137140550216722, 0.0029440614246860489}, 5, 10,
     [0.0022, 0.0024000000000000002, 0.0026000000000000003, 0.0028000000000000004, 0.003]},
    {{867.39957125837964, 1102.4468893403894}, 5, 10,
     [850.0, 900.0, 950.0, 1000.0, 1050.0, 1100.0]},
    {{7_615_976.3697186578, 16_647_593.767485669}, 5, 10,
     [7_000_000.0, 8_000_000.0, 9_000_000.0, 10_000_000.0, 20_000_000.0]},
    {{10.0, 1000.0}, 5, 10, [10.0, 100.0, 1000.0]}
  ]

  test "breaks for a logarithmic axis are R's breaks_log() on each of its branches" do
    for {limits, wanted, base, r_breaks} <- @r_log_breaks do
      assert {limits, wanted, base, Breaks.log(limits, n: wanted, base: base)} ==
               {limits, wanted, base, r_breaks}
    end
  end

  # Golden: breaks_log(base = 1.2)(c(1.77, 1.934)), as above: R raises 1.2 to the third power as
  # 1.728, a bit above the double nearest the power, 1.7279999999999998, which `:math.pow/2` gives;
  # of 7,000 powers of twelve bases R raised, that one and 1.1 to the fourth alone differ.
  test "a power of a base is the double nearest it, where R's x86 power can land a bit away" do
    assert Breaks.log({1.77, 1.934}, base: 1.2) == [1.7279999999999998, 2.0736]
  end

  # R's breaks_log(n = 0) fails, "missing value where TRUE/FALSE needed".
  test "the number of breaks wanted on a logarithmic axis is a positive whole number" do
    for wanted <- [0, -1, 2.5] do
      assert_raise NimbleOptions.ValidationError, fn -> Breaks.log({3.0, 500.0}, n: wanted) end
    end
  end

  # R's breaks_log(base = 1) gives 1 on any limits, and below 1 fails on most: a logarithm there
  # falls as its value rises.
  test "a logarithm's base is a number above 1, and anything else is refused" do
    for base <- [1, 0.5, 0, -10, :ten] do
      error =
        assert_raise NimbleOptions.ValidationError, fn -> Breaks.log({3.0, 500.0}, base: base) end

      assert error.message =~ "expected a number above 1, got: #{inspect(base)}"
    end
  end

  # R's breaks_log()(c(0, 5)) fails, "'from' must be a finite number", and on a negative limit
  # takes its logarithm to NaN and fails.
  test "limits of a logarithmic axis are positive numbers, and anything else is refused" do
    for limits <- [{0.0, 5.0}, {-1.0, 5.0}, {3.0, 0}, {nil, 5.0}] do
      error = assert_raise ArgumentError, fn -> Breaks.log(limits) end

      assert error.message =~ "expected limits of two positive numbers"
      assert error.message =~ inspect(limits)
    end
  end

  # Golden: scales 1.4.0's `breaks_exp(n)(c(low, high))` and with `only.loose`, `Q` and `w`, as
  # above; all of 2,000 random limits, counts, nice numbers and only.loose matched R
  # (`step2/sweep.R`).
  test "breaks for an axis of exponentials are R's breaks_exp()" do
    for {limits, options, r_breaks} <- [
          {{0.0, 100.0}, [n: 4], [100.0, 99.0, 98.0, 0.0]},
          {{100.0, 0.0}, [], [100.0, 99.0, 98.0, 97.0, 0.0]},
          {{0.0, 3.5}, [], [3.0, 2.0, 1.0, 0.0]},
          {{0.0, 3.0}, [n: 2], [3.0, 0.0]},
          {{1.5, 4.5}, [], [4.0, 3.0, 2.0, 1.0, 0.0]},
          {{-5.0, 3.0}, [], [3.0, 2.0, 1.0, 0.0]},
          {{1.5, 4.4}, [], [1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5]},
          {{-0.5, 2.99}, [], [0.0, 1.0, 2.0, 3.0]},
          {{-5.0, -1.0}, [], [0.0, 0.0, 0.0, 0.0, 0.0]},
          {{0.3, 2.2}, [], [0.0, 0.5, 1.0, 1.5, 2.0]},
          {{0.3, 2.2}, [only_loose: true], [0.25, 0.75, 1.25, 1.75, 2.25]},
          {{0.3, 2.2}, [nice_numbers: [1, 2]], [0.0, 1.0, 2.0]}
        ] do
      assert {limits, options, Breaks.exp(limits, options)} == {limits, options, r_breaks}
    end
  end

  # Golden: scales 1.4.0's `breaks_timespan(unit, n)(c(low, high))`, as above, its difftime's
  # seconds; all of 3,000 random limits in each unit and count matched R (`step2/sweep.R`), and all
  # of 4,900 a time scale's breaks were checked against before. Each unit counts the limits, and
  # each switch, two minutes, two hours, two days and two weeks, finds its breaks in the unit below
  # at the switch and the unit above past it.
  test "breaks for spans of time are R's breaks_timespan(), in seconds" do
    for {limits, options, r_breaks} <- [
          {{0.0, 10.0}, [], [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]},
          {{0.0, 10.0}, [unit: :minute], [0.0, 120.0, 240.0, 360.0, 480.0, 600.0]},
          {{0.0, 10.0}, [unit: :hour], [0.0, 7200.0, 14_400.0, 21_600.0, 28_800.0, 36_000.0]},
          {{0.0, 10.0}, [unit: :day],
           [0.0, 172_800.0, 345_600.0, 518_400.0, 691_200.0, 864_000.0]},
          {{0.0, 10.0}, [unit: :week],
           [0.0, 1_209_600.0, 2_419_200.0, 3_628_800.0, 4_838_400.0, 6_048_000.0]},
          {{0.0, 120.0}, [], [0.0, 30.0, 60.0, 90.0, 120.0]},
          {{0.0, 120.001}, [], [0.0, 24.0, 48.0, 72.000000000000014, 96.0, 120.0]},
          {{0.0, 7200.0}, [], [0.0, 1800.0, 3600.0, 5400.0, 7200.0]},
          {{0.0, 7200.001}, [], [0.0, 1440.0, 2880.0, 4320.0000000000009, 5760.0, 7200.0]},
          {{0.0, 172_800.0}, [], [0.0, 36_000.0, 72_000.0, 108_000.0, 144_000.0, 180_000.0]},
          {{0.0, 172_800.001}, [],
           [0.0, 34_560.0, 69_120.0, 103_680.00000000001, 138_240.0, 172_800.0]},
          {{0.0, 1_209_600.0}, [], [0.0, 345_600.0, 691_200.0, 1_036_800.0, 1_382_400.0]},
          {{0.0, 1_209_600.001}, [],
           [0.0, 241_920.0, 483_840.0, 725_760.00000000012, 967_680.0, 1_209_600.0]},
          {{2.0, 0.0}, [unit: :minute], [0.0, 30.0, 60.0, 90.0, 120.0]},
          {{0.0, 100.0}, [n: 3], [0.0, 100.0]},
          {{0.0, 30.0}, [unit: :hour, n: 9],
           [0.0, 14_400.0, 28_800.0, 43_200.0, 57_600.0, 72_000.0, 86_400.0, 100_800.0, 115_200.0]},
          {{5.0, 5.0}, [], [5.0, 5.0, 5.0, 5.0, 5.0]}
        ] do
      assert {limits, options, Breaks.timespan(limits, options)} == {limits, options, r_breaks}
    end
  end

  test "a span of time's unit is one of the five R counts in, and anything else is refused" do
    for unit <- [:month, :secs, "second"] do
      assert_raise NimbleOptions.ValidationError, fn ->
        Breaks.timespan({0.0, 10.0}, unit: unit)
      end
    end
  end

  # Golden: R 4.6.1's scales 1.4.0 `fullseq()` and `breaks_width()`, each value printed to 17
  # significant digits (the giggly-r:ggplot2-4.0.3 image; this session's scratchpad
  # `step1/width.R`). All of 3,000 random numeric ranges, sizes, pads and offsets, 2,000 random
  # date widths with up to three offsets each, and 935 New York date-time widths across its
  # changes of offset matched R (`step1/sweep.R`, `step1/compare.exs`). The figures of this test
  # and the width tests below are R's but where a test says it departs (a time of day wrapping);
  # they move only if the package stops matching R, which is a bug.
  test "a sequence of numbers steps from the low limit rounded down, each step R's seq() takes" do
    assert Breaks.fullseq({0.1, 0.7}, 0.1) === [
             0.1,
             0.2,
             0.30000000000000004,
             0.4,
             0.5,
             0.6,
             0.7000000000000001
           ]

    assert Breaks.fullseq({0.3, 0.9}, 0.3) === [0.3, 0.6, 0.8999999999999999]
  end

  test "limits high to low give the sequence of limits low to high" do
    assert Breaks.fullseq({7, 1.6}, 2) === [0.0, 2.0, 4.0, 6.0, 8.0]
    assert Breaks.fullseq({4.1, -3.2}, 2) === [-4.0, -2.0, 0.0, 2.0, 4.0, 6.0]
  end

  test "padding adds a step before the sequence and one after it" do
    assert Breaks.fullseq({1.6, 7.0}, 2, pad: true) === [-2.0, 0.0, 2.0, 4.0, 6.0, 8.0, 10.0]
  end

  # R returns before padding, so a zero-wide range is never padded.
  test "limits that are one number give it half a size either side, padded or not" do
    assert Breaks.fullseq({5, 5}, 4) === [3.0, 7.0]
    assert Breaks.fullseq({5, 5}, 4, pad: true) === [3.0, 7.0]
  end

  test "an offset moves every break of a width, back for a negative one" do
    forward = Breaks.width({326, 18_823}, 800, offset: 200)
    back = Breaks.width({326, 18_823}, 800, offset: -200)
    unmoved = Breaks.width({326, 18_823}, 800)

    assert Enum.take(forward, 3) === [200.0, 1000.0, 1800.0]
    assert Enum.take(back, 3) === [-200.0, 600.0, 1400.0]
    assert List.last(unmoved) === 19_200.0
  end

  test "a size that is not a positive number is refused" do
    for size <- [0, -2, :two] do
      assert_raise FunctionClauseError, fn -> Breaks.fullseq({1.0, 7.0}, size) end
    end
  end

  test "a width's offset between numbers is a number, and a step is refused" do
    error = assert_raise ArgumentError, fn -> Breaks.width({1.0, 7.0}, 1, offset: [day: 1]) end
    assert error.message =~ "expected a number as the offset of breaks between numbers"
    assert error.message =~ "got: [day: 1]"
  end

  test "a month offset carries a day past the month's end into the next, unsorted as R leaves it" do
    assert Breaks.width({~D[2026-01-29], ~D[2026-02-02]}, [day: 1], offset: [month: 1]) == [
             ~D[2026-03-01],
             ~D[2026-03-02],
             ~D[2026-03-03],
             ~D[2026-03-01],
             ~D[2026-03-02],
             ~D[2026-03-03]
           ]

    assert Breaks.width({~D[2026-03-28], ~D[2026-04-02]}, [week: 1], offset: [month: -1]) ==
             [~D[2026-02-23], ~D[2026-03-02], ~D[2026-03-06]]
  end

  test "a year offset carries 29 February into 1 March" do
    assert Breaks.width({~D[2028-02-28], ~D[2028-03-01]}, [day: 1], offset: [year: 1]) ==
             [~D[2029-02-28], ~D[2029-03-01], ~D[2029-03-01], ~D[2029-03-02]]
  end

  test "each step of an offset moves the breaks in turn, in the order given" do
    assert Breaks.width({~D[2026-01-05], ~D[2026-02-20]}, [week: 2], offset: [month: 1, day: 1]) ==
             [~D[2026-02-06], ~D[2026-02-20], ~D[2026-03-03], ~D[2026-03-17], ~D[2026-04-03]]
  end

  test "a width with no offset is its sequence, the limits in either order" do
    assert Breaks.width({~D[2026-04-20], ~D[2026-01-10]}, month: 1) == [
             ~D[2026-01-01],
             ~D[2026-02-01],
             ~D[2026-03-01],
             ~D[2026-04-01],
             ~D[2026-05-01]
           ]
  end

  test "dates the same day give the step's unit either side of it" do
    assert Breaks.fullseq({~D[2026-03-04], ~D[2026-03-04]}, month: 1) ==
             [~D[2026-03-01], ~D[2026-04-01]]
  end

  test "naive date-times step on UTC's clock, an hour by elapsed time and a month on the calendar" do
    assert Breaks.width(
             {~N[2026-01-31 10:07:00], ~N[2026-01-31 11:02:00]},
             [minute: 15],
             offset: [hour: 1, month: 1]
           ) == [
             ~N[2026-03-03 11:00:00],
             ~N[2026-03-03 11:15:00],
             ~N[2026-03-03 11:30:00],
             ~N[2026-03-03 11:45:00],
             ~N[2026-03-03 12:00:00],
             ~N[2026-03-03 12:15:00]
           ]
  end

  test "naive date-times move a week and a second by elapsed time" do
    assert Breaks.width(
             {~N[2026-01-31 10:00:00], ~N[2026-02-02 10:00:00]},
             [day: 1],
             offset: [week: 1, second: 1]
           ) == [
             ~N[2026-02-07 00:00:01],
             ~N[2026-02-08 00:00:01],
             ~N[2026-02-09 00:00:01],
             ~N[2026-02-10 00:00:01]
           ]
  end

  defp new_york(naive) do
    DateTime.from_naive!(naive, "America/New_York", Tz.TimeZoneDatabase)
  end

  defp walls(datetimes) do
    Enum.map(datetimes, fn datetime -> {DateTime.to_naive(datetime), datetime.zone_abbr} end)
  end

  test "a date-time in a zone steps on its clock, six hours across a change by elapsed time" do
    breaks =
      Breaks.width(
        {new_york(~N[2026-03-07 20:10:00]), new_york(~N[2026-03-09 05:00:00])},
        [hour: 6],
        offset: [minute: 30],
        time_zone_database: Tz.TimeZoneDatabase
      )

    assert walls(breaks) == [
             {~N[2026-03-07 20:30:00], "EST"},
             {~N[2026-03-08 03:30:00], "EDT"},
             {~N[2026-03-08 09:30:00], "EDT"},
             {~N[2026-03-08 15:30:00], "EDT"},
             {~N[2026-03-08 21:30:00], "EDT"},
             {~N[2026-03-09 03:30:00], "EDT"},
             {~N[2026-03-09 09:30:00], "EDT"}
           ]
  end

  test "a month offset onto a skipped time reads it at the offset before the change" do
    breaks =
      Breaks.width(
        {new_york(~N[2026-02-08 02:10:00]), new_york(~N[2026-02-08 02:50:00])},
        [minute: 30],
        offset: [month: 1],
        time_zone_database: Tz.TimeZoneDatabase
      )

    assert walls(breaks) == [
             {~N[2026-03-08 03:00:00], "EDT"},
             {~N[2026-03-08 03:30:00], "EDT"},
             {~N[2026-03-08 03:00:00], "EDT"},
             {~N[2026-03-08 03:30:00], "EDT"}
           ]
  end

  test "a month offset onto a repeated time takes the earlier" do
    breaks =
      Breaks.width(
        {new_york(~N[2026-10-01 01:10:00]), new_york(~N[2026-10-01 01:50:00])},
        [minute: 30],
        offset: [month: 1],
        time_zone_database: Tz.TimeZoneDatabase
      )

    assert walls(breaks) == [
             {~N[2026-11-01 01:00:00], "EDT"},
             {~N[2026-11-01 01:30:00], "EDT"},
             {~N[2026-11-01 02:00:00], "EST"},
             {~N[2026-11-01 02:30:00], "EST"}
           ]
  end

  # R rounds the high limit up by adding a step and rounding to the nearest, so 10:40 reaches 11:00.
  test "a year offset in a zone carries 29 February into 1 March on its clock" do
    breaks =
      Breaks.width(
        {new_york(~N[2028-02-28 10:00:00]), new_york(~N[2028-03-01 10:00:00])},
        [day: 1],
        offset: [year: 1],
        time_zone_database: Tz.TimeZoneDatabase
      )

    assert walls(breaks) == [
             {~N[2029-02-28 00:00:00], "EST"},
             {~N[2029-03-01 00:00:00], "EST"},
             {~N[2029-03-01 00:00:00], "EST"},
             {~N[2029-03-02 00:00:00], "EST"}
           ]
  end

  test "date-times in UTC need no database and stay date-times" do
    assert Breaks.fullseq({~U[2026-01-31 10:07:00Z], ~U[2026-01-31 10:40:00Z]}, minute: 15) == [
             ~U[2026-01-31 10:00:00Z],
             ~U[2026-01-31 10:15:00Z],
             ~U[2026-01-31 10:30:00Z],
             ~U[2026-01-31 10:45:00Z],
             ~U[2026-01-31 11:00:00Z]
           ]
  end

  test "date-times in another zone without a database that knows it are refused" do
    error =
      assert_raise ArgumentError, fn ->
        Breaks.fullseq({new_york(~N[2026-01-31 10:00:00]), new_york(~N[2026-01-31 12:00:00])},
          hour: 1
        )
      end

    assert error.message =~ "need a time zone database that knows it"
    assert error.message =~ ~s("America/New_York")
  end

  # R's hms gives 4200 to 15000 seconds; a time of day wraps where R's runs on past 24 hours.
  test "times of day step from the low limit rounded down, and wrap past midnight" do
    assert Breaks.width({~T[01:12:00], ~T[03:42:00]}, [minute: 30], offset: [minute: 10]) == [
             ~T[01:10:00],
             ~T[01:40:00],
             ~T[02:10:00],
             ~T[02:40:00],
             ~T[03:10:00],
             ~T[03:40:00],
             ~T[04:10:00]
           ]

    assert Breaks.fullseq({~T[23:10:00], ~T[23:50:00]}, minute: 30) ==
             [~T[23:00:00], ~T[23:30:00], ~T[00:00:00]]
  end

  # R's hms gives 7230 to 18030 seconds.
  test "times of day move an hour and seconds" do
    assert Breaks.width({~T[01:12:00], ~T[03:42:00]}, [minute: 30], offset: [hour: 1, second: 30]) ==
             [
               ~T[02:00:30],
               ~T[02:30:30],
               ~T[03:00:30],
               ~T[03:30:30],
               ~T[04:00:30],
               ~T[04:30:30],
               ~T[05:00:30]
             ]
  end

  test "a step of more than one unit, or a unit its values cannot take, is refused" do
    dates = "[:day, :week, :month, :year] for dates"

    for {limits, step, units} <- [
          {{~D[2026-01-01], ~D[2026-02-01]}, [month: 1, day: 2], dates},
          {{~D[2026-01-01], ~D[2026-02-01]}, [hour: 6], dates},
          {{~D[2026-01-01], ~D[2026-02-01]}, [month: 0], dates},
          {{~T[01:00:00], ~T[02:00:00]}, [day: 1], "[:second, :minute, :hour] for times"},
          {{~N[2026-01-01 00:00:00], ~N[2026-01-02 00:00:00]}, [fortnight: 1],
           "[:second, :minute, :hour, :day, :week, :month, :year] for date-times"}
        ] do
      error = assert_raise ArgumentError, fn -> Breaks.fullseq(limits, step) end
      assert error.message =~ "expected a step of one unit and a positive whole count"
      assert error.message =~ units
      assert error.message =~ inspect(step)
    end
  end

  test "an offset of dates, date-times or times is a list of steps they can take" do
    dates = "between dates as a list of steps, each a unit of [:day, :week, :month, :year]"

    for {limits, step, offset, kind} <- [
          {{~D[2026-01-01], ~D[2026-02-01]}, [day: 1], 8, dates},
          {{~D[2026-01-01], ~D[2026-02-01]}, [day: 1], [hour: 1], dates},
          {{~D[2026-01-01], ~D[2026-02-01]}, [day: 1], [day: 1, hour: 1], dates},
          {{~T[01:00:00], ~T[02:00:00]}, [minute: 30], [month: 1],
           "between times as a list of steps, each a unit of [:second, :minute, :hour]"},
          {{~N[2026-01-01 00:00:00], ~N[2026-01-02 00:00:00]}, [day: 1], [day: 1.5],
           "between date-times as a list of steps"}
        ] do
      error = assert_raise ArgumentError, fn -> Breaks.width(limits, step, offset: offset) end
      assert error.message =~ kind
      assert error.message =~ "got: #{inspect(offset)}"
    end
  end

  test "padding is refused for dates, date-times and times" do
    error =
      assert_raise ArgumentError, fn ->
        Breaks.fullseq({~D[2026-01-01], ~D[2026-02-01]}, [month: 1], pad: true)
      end

    assert error.message =~ "pad: widens a sequence of numbers alone"
    assert error.message =~ "{~D[2026-01-01], ~D[2026-02-01]}"
  end
end
