defmodule Scales.TransformTest do
  use ExUnit.Case, async: true

  doctest Scales.Transform

  alias Scales.{Breaks, Transform}

  # Golden: every axis below is R's own, from R 4.6.1 with ggplot2 4.0.3 and scales 1.4.0 (the
  # image `giggly-r:ggplot2-4.0.3`): `ggplot_build()`'s panel params for the plot in the comment
  # above each, its continuous range the extent given here, and on it the breaks inside it, their
  # labels, and the minor breaks less the breaks (which ggplot2's grid leaves out). They move only
  # if R's transformations do. R writes a log axis's labels from 1e5 up in scientific notation;
  # the package writes them in plain decimals.

  # What an axis showing `extent` draws from `transformation`'s defaults, as ggplot2's view scale
  # keeps them: the breaks found on the extent squished into the domain, those inside the extent,
  # each with its label, and the minor breaks between them inside the extent, less the breaks.
  defp axis(transformation, extent) do
    squished = Transform.squish(transformation, extent)

    breaks =
      transformation
      |> Transform.breaks(squished)
      |> inside(extent)

    labels = Transform.format(transformation, breaks, extent)

    minor =
      transformation
      |> Transform.minor_breaks(breaks, extent)
      |> inside(extent)
      |> Enum.reject(fn position -> position in breaks end)

    {Enum.zip(breaks, labels), minor}
  end

  # Those of `positions` inside `{low, high}`, its ends included, as numbers: a break at an
  # infinity or NaN is inside none.
  defp inside(positions, {low, high}) do
    Enum.filter(positions, fn position ->
      is_number(position) and position >= low and position <= high
    end)
  end

  # Whether two axes, as `axis/2` gives them, have the same labels and every position within
  # `bound` doubles of the other's.
  defp near_axis?({breaks, minor}, {expected_breaks, expected_minor}, bound) do
    {positions, labels} = Enum.unzip(breaks)
    {expected_positions, expected_labels} = Enum.unzip(expected_breaks)

    labels == expected_labels and near?(positions, expected_positions, bound) and
      near?(minor, expected_minor, bound)
  end

  # Whether two lists of doubles are as long and each within `bound` doubles of the other's.
  defp near?(values, expected, bound) do
    length(values) == length(expected) and
      values
      |> Enum.zip_with(expected, &ulps/2)
      |> Enum.all?(fn distance -> distance <= bound end)
  end

  # A double as R wrote it, for the large ones credo misreads as written (`LargeNumbers` takes a
  # long fraction before a positive exponent for the whole part).
  defp r_double(text), do: String.to_float(text)

  # A double as an R fixture writes one: `NA` missing, `NaN`, `Inf` and `-Inf`, `-0` a negative zero.
  defp r_value("NA"), do: nil
  defp r_value("NaN"), do: :nan
  defp r_value("Inf"), do: :infinity
  defp r_value("-Inf"), do: :neg_infinity
  defp r_value("-0"), do: -0.0

  defp r_value(text) do
    {value, ""} = Float.parse(text)
    value
  end

  # How many doubles apart two finite doubles are, each read from its bits in their order.
  defp ulps(left, right), do: abs(ordinal(left) - ordinal(right))

  defp ordinal(value) do
    <<sign::1, magnitude::63>> = <<value::float>>
    if sign == 1, do: -magnitude, else: magnitude
  end

  # The time-of-day transformation's breaks inside `extent` and their labels.
  defp time_breaks(extent) do
    breaks =
      :time
      |> Transform.breaks(extent)
      |> inside(extent)

    {breaks, Transform.format(:time, breaks, extent)}
  end

  # A wall-clock time in New York, as R's as.POSIXct(..., tz = "America/New_York") reads it.
  defp new_york(wall), do: DateTime.from_naive!(wall, "America/New_York", Tz.TimeZoneDatabase)

  describe "identity" do
    # as.numeric() of each, as R's untransformed continuous scale places it
    test "places a number as it is, a date at its days, a date-time and a time at their seconds" do
      values = [
        2.5,
        nil,
        ~D[1970-01-11],
        ~U[1970-01-01 00:01:00Z],
        ~N[1970-01-01 00:00:30],
        ~T[01:00:00]
      ]

      assert Transform.transform(:identity, values) === [2.5, nil, 10.0, 60.0, 30.0, 3600.0]
    end

    test "turns a position back as it is, reaches without end, and labels its breaks plainly" do
      assert {Transform.inverse(:identity, [1.5]), Transform.squish(:identity, {-1.0e300, 1.0}),
              Transform.format(:identity, [10.0, 20.0], {5.0, 25.0})} ===
               {[1.5], {-1.0e300, 1.0}, ["10", "20"]}
    end
  end

  describe "date" do
    # ggplot(data.frame(d = as.Date(c("2024-01-01", "2024-03-01")), y = 1:2), aes(d, y)) +
    #   geom_point()
    test "marks R's pretty() breaks for dates, labelled by their step, and minor breaks" do
      assert axis(:date, {19_720.0, 19_786.0}) === {
               [
                 {19_723.0, "Jan 01"},
                 {19_737.0, "Jan 15"},
                 {19_754.0, "Feb 01"},
                 {19_768.0, "Feb 15"},
                 {19_783.0, "Mar 01"}
               ],
               [19_730.0, 19_745.5, 19_761.0, 19_775.5]
             }
    end

    # R 4.6.1's transform_date()$inverse(c(19723, 19723.75, -0.5, -1.5)), written by format():
    # "2024-01-01" "2024-01-01" "1969-12-31" "1969-12-30"
    test "turns a position back into the day it falls on, rounded down, and reaches without end" do
      assert {Transform.inverse(:date, [19_723.0, 19_723.75, -0.5, -1.5]),
              Transform.squish(:date, {-1.0e6, 1.0})} ===
               {[~D[2024-01-01], ~D[2024-01-01], ~D[1969-12-31], ~D[1969-12-30]], {-1.0e6, 1.0}}
    end
  end

  describe "log10" do
    test "marks the powers of ten, every one or every second, that leave three inside" do
      # ggplot(data.frame(x = 1:2, y = c(1, 1e6)), aes(x, y)) + geom_point() + scale_y_log10();
      # y = c(5, 20000), where every second power leaves two and every power four
      assert axis(:log10, {-0.30000000000000004, 6.3}) ==
               {[{1.0, "10"}, {3.0, "1000"}, {5.0, "100000"}], [0.0, 2.0, 4.0, 6.0]}

      assert axis(:log10, {0.51886700476962067, 4.4811329952303796}) ==
               {[{1.0, "10"}, {2.0, "100"}, {3.0, "1000"}, {4.0, "10000"}], [1.5, 2.5, 3.5]}
    end

    test "adds multiples of each power, evenest first, when too few powers fall inside" do
      # mpg's hwy, ggplot(mpg, aes(displ, hwy)) + geom_point() + scale_y_log10(); y = c(2, 8);
      # y = c(1.5, 30); diamonds' price on x
      assert axis(:log10, {1.0509676745256968, 1.6716662480081155}) ==
               {[
                  {1.3010299956639813, "20"},
                  {1.4771212547196624, "30"},
                  {1.6020599913279625, "40"}
                ],
                [1.1249387366083001, 1.2129843661361406, 1.3890756251918219, 1.5395906230238126]}

      assert axis(:log10, {0.27092699609758308, 0.93319298655834171}) ==
               {[
                  {0.3010299956639812, "2"},
                  {0.47712125471966244, "3"},
                  {0.69897000433601886, "5"}
                ],
                [
                  0.38907562519182182,
                  0.58804562952784067,
                  0.78701563386385942,
                  0.87506126339170009
                ]}

      assert axis(:log10, {0.11103975927248218, 1.5421727545028614}) ==
               {[{0.47712125471966244, "3"}, {1.0, "10"}, {1.4771212547196624, "30"}],
                [0.21568188207949363, 0.7385606273598313, 1.2385606273598313]}

      assert axis(:log10, {2.4251440379594578, 4.3627624043460393}) ==
               {[
                  {2.4771212547196626, "300"},
                  {3.0, "1000"},
                  {3.4771212547196626, "3000"},
                  {4.0, "10000"}
                ],
                [2.7385606273598313, 3.2385606273598313, 3.7385606273598313, 4.2614393726401687]}
    end

    test "falls back to extended breaks in data units when even nine multiples leave too few" do
      # y = c(100, 101) and y = c(2, 3)
      assert axis(:log10, {1.9997839313108678, 2.0045374424717748}) ==
               {[
                  {2.0, "100.00"},
                  {2.0010843812922201, "100.25"},
                  {2.0021660617565078, "100.50"},
                  {2.0032450548131471, "100.75"},
                  {2.0043213737826426, "101.00"}
                ],
                [2.0005421906461098, 2.001625221524364, 2.0027055582848274, 2.0037832142978949]}

      {breaks, _minor} = axis(:log10, {0.29222543271119716, 0.48592581767244647})

      assert breaks == [
               {0.3010299956639812, "2.00"},
               {0.35218251811136247, "2.25"},
               {0.3979400086720376, "2.50"},
               {0.43933269383026263, "2.75"},
               {0.47712125471966244, "3.00"}
             ]
    end

    # The breaks themselves are `Breaks.log/2`'s, whose test pins R's: here, the extent is turned
    # back into data units, five breaks wanted in base 10, and each put back into log space, those
    # outside the extent left for the scale to drop.
    test "breaks are breaks_log()'s on the extent in data units, put back into log space" do
      for {low, high} = extent <- [{3.7012828388251364, 15.141030670586783}, {-0.74, -0.0017}] do
        expected =
          {:math.pow(10.0, low), :math.pow(10.0, high)}
          |> Breaks.log(n: 5, base: 10)
          |> Enum.map(&:math.log10/1)

        assert Transform.breaks(:log10, extent) == expected
      end
    end

    test "places zero at minus infinity and a negative value at NaN" do
      # data.frame(y = c(0, 10, 100)) with scale_y_log10(): layer_data()'s y is -Inf, 1, 2;
      # log10(-1) is NaN
      assert Transform.transform(:log10, [0, -1, 10, :infinity, nil]) ==
               [:neg_infinity, :nan, 1.0, :infinity, nil]
    end

    # R: trimws(format(10^c(306, 307, 308), scientific = FALSE)), each the double's exact digits,
    # past the 256 characters Erlang's float_to_binary/2 writes; 10^307's double lies just below
    # it, so its 307 digits start 9999.
    test "labels a power near the largest double whole, as R writes it" do
      labels = Transform.format(:log10, [306.0, 307.0, 308.0], {306.0, 308.0})

      assert Enum.map(labels, &String.length/1) == [307, 307, 309]

      assert List.last(labels) ==
               "1000000000000000010979063629440455417404923096773118463368106829031575854049114915371633" <>
                 "2897849468889906124966972117251561159028374314008832830700919814604603127166450293302718" <>
                 "5697489699588559043338384466165001178426897626212945177628091195786707458122783970171784" <>
                 "415105291802893207873272974885715430223118336"
    end
  end

  describe "sqrt" do
    test "marks extended breaks in data units, minor breaks midway in square-root space" do
      # ggplot(mpg, aes(displ, hwy)) + geom_point() + scale_y_sqrt(); with limits = c(16, 36)
      assert axis(:sqrt, {3.3056442168591023, 6.7917069789894517}) ==
               {[
                  {4.4721359549995796, "20"},
                  {5.4772255750516612, "30"},
                  {6.324555320336759, "40"}
                ],
                [3.467046334947498, 3.9695911449735388, 4.9746807650256208, 5.9008904476942101]}

      assert axis(:sqrt, {3.9, 6.1}) ==
               {[
                  {4.4721359549995796, "20"},
                  {5.0, "25"},
                  {5.4772255750516612, "30"},
                  {5.9160797830996161, "35"}
                ],
                [
                  3.9442719099991592,
                  4.2082039324993694,
                  4.7360679774997898,
                  5.238612787525831,
                  5.6966526790756387
                ]}
    end

    test "finds its breaks from zero where the widened axis reaches below it" do
      # data.frame(y = c(0, 4, 9)) with scale_y_sqrt()
      assert axis(:sqrt, {-0.15000000000000002, 3.15}) ==
               {[
                  {0.0, "0.0"},
                  {1.5811388300841898, "2.5"},
                  {2.2360679774997898, "5.0"},
                  {2.7386127875258306, "7.5"}
                ], [0.79056941504209488, 1.9086034037919899, 2.4873403825128104]}
    end

    test "finds its breaks from zero, not below or above it, where the axis is near it" do
      # data.frame(x = c(0, 1)) with scale_x_sqrt(): the breaks 0 to 1 in quarters, found from the
      # domain's 0 where the widened axis reaches below it, and R's minor breaks less the breaks
      assert axis(:sqrt, {-0.05, 1.05}) ==
               {[
                  {0.0, "0.00"},
                  {0.5, "0.25"},
                  {0.70710678118654757, "0.50"},
                  {0.8660254037844386, "0.75"},
                  {1.0, "1.00"}
                ], [0.25, 0.60355339059327373, 0.78656609248549314, 0.9330127018922193]}
    end

    # transform_sqrt()$inverse(c(3, 0.5, -0, -1, -Inf, NaN)) is 9, 0.25, 0, NA, NA, NA: R's
    # `ifelse(x < 0, NA, x^2)` is NA where the test is
    test "turns a position back by squaring it, one below zero, minus infinity and NaN missing" do
      assert Transform.inverse(:sqrt, [3.0, 0.5, -0.0, -1.0, :neg_infinity, :nan]) ===
               [9.0, 0.25, 0.0, nil, nil, nil]
    end
  end

  describe "reverse" do
    test "runs high to low, its breaks descending and its minor breaks R's reversed ones" do
      # ggplot(mpg, aes(displ, hwy)) + geom_point() + scale_y_reverse()
      assert axis(:reverse, {-45.6, -10.4}) ==
               {[{-20.0, "20"}, {-30.0, "30"}, {-40.0, "40"}], [-15.0, -25.0, -35.0, -45.0]}
    end

    test "turns a position back by negating it" do
      assert Transform.inverse(:reverse, [-20.0, :infinity]) === [20.0, :neg_infinity]
    end
  end

  describe "reciprocal" do
    test "places breaks falling as they rise, its minor breaks R's on them in that order" do
      # ggplot(mpg, aes(displ, hwy)) + geom_point() +
      #   scale_y_continuous(transform = scales::transform_reciprocal())
      assert axis(:reciprocal, {0.019696969696969699, 0.086363636363636365}) ==
               {[{0.05, "20"}, {1 / 30, "30"}, {0.025, "40"}, {0.02, "50"}],
                [
                  0.06666666666666668,
                  0.058333333333333341,
                  0.041666666666666671,
                  0.029166666666666667,
                  0.022499999999999999
                ]}
    end

    # 1 / c(0, -0, 4, Inf, -Inf, NA): Inf, -Inf, 0.25, 0, -0, NA
    test "places zero at plus infinity, -0.0 at minus, each infinity at its zero, missing nowhere" do
      assert Transform.transform(:reciprocal, [0, -0.0, 4, :infinity, :neg_infinity, nil]) ===
               [:infinity, :neg_infinity, 0.25, 0.0, -0.0, nil]
    end

    test "turns a position back as it placed it" do
      assert Transform.inverse(:reciprocal, [0.25, 0.0, :infinity]) === [4.0, :infinity, 0.0]
    end

    test "finds its breaks on the data's finite end where the extent reaches zero" do
      # data.frame(y = c(Inf, 4)) with scale_y_continuous(transform =
      # scales::transform_reciprocal(), expand = c(0, 0)): R's extended breaks on the one finite
      # end, 4, give it five times
      assert axis(:reciprocal, {0.0, 0.25}) == {List.duplicate({0.25, "4"}, 5), []}
    end
  end

  describe "the logarithms in a base" do
    test "mark the powers of the base, e's under the natural logarithm, labelled in data units" do
      # y = c(1, 1000) and c(0.5, 20) under scale_y_continuous(transform = "log"); R writes the
      # powers of e with format(), "2.718282", the package in plain decimals
      assert axis(:log, {-0.34538776394910686, 7.253143042931244}) ==
               {[
                  {1.0, "2.71828182845905"},
                  {3.0, "20.08553692318770"},
                  {5.0, "148.41315910257700"},
                  {7.0, "1096.63315842846009"}
                ], [0.0, 2.0, 4.0, 6.0]}

      assert axis(:log, {-0.87759115326564208, 3.1801762462596876}) ==
               {[
                  {0.0, "1.00000000000000"},
                  {1.0, "2.71828182845905"},
                  {2.0, "7.38905609893065"},
                  {3.0, "20.08553692318770"}
                ], [-0.5, 0.5, 1.5, 2.5]}

      # y = c(1, 64) and c(0.3, 3) under "log2"; y = c(2, 30) under transform_log(3)
      assert axis(:log2, {-0.30000000000000004, 6.2999999999999998}) ==
               {[{1.0, "2"}, {3.0, "8"}, {5.0, "32"}], [0.0, 2.0, 4.0, 6.0]}

      assert axis(:log2, {-1.9030619989105744, 1.7510589054655243}) ==
               {[{-1.0, "0.5"}, {0.0, "1.0"}, {1.0, "2.0"}], [-1.5, -0.5, 0.5, 1.5]}

      assert axis({:log, 3}, {0.50768107753556102, 3.2191519503252808}) ==
               {[{1.0, "3"}, {2.0, "9"}, {3.0, "27"}], [1.5, 2.5]}
    end

    test "in base 10 and 2, place, break and label every value as log10 and log2 do" do
      # y = c(2000, 9000) under transform_log(10), R's axis under "log10" too
      assert axis({:log, 10}, {3.2683693699752139, 3.9869031351280921}) ==
               {[
                  {3.3010299956639813, "2000"},
                  {3.4771212547196626, "3000"},
                  {3.6989700043360187, "5000"}
                ],
                [3.3890756251918219, 3.5880456295278407, 3.7870156338638594, 3.8750612633917001]}

      values = [1.0e-300, 0.3, 3.0, 7.0e5, 1.7e308]

      assert {Transform.transform({:log, 10}, values), Transform.transform({:log, 2}, values)} ===
               {Transform.transform(:log10, values), Transform.transform(:log2, values)}
    end

    # As log10's: the breaks are `Breaks.log/2`'s on the extent turned back, in the base.
    test "breaks are breaks_log()'s in the base on the extent in data units" do
      extent = {0.3, 4.1}

      expected =
        {:math.pow(3, 0.3), :math.pow(3, 4.1)}
        |> Breaks.log(n: 5, base: 3)
        |> Enum.map(fn break -> :math.log(break) / :math.log(3) end)

      assert Transform.breaks({:log, 3}, extent) == expected
    end
  end

  describe "log1p, exp, asinh and the pseudo-logarithm" do
    # Golden: ggplot2's axes, as the log10 ones above (`inc4/step3/axes.R`).
    test "take extended breaks in data units, labelled there" do
      # y = c(0, 100) and c(-0.5, 10) under "log1p"
      assert axis(:log1p, {-0.23075602584206301, 4.8458765426833228}) ==
               {[
                  {0.0, "0"},
                  {3.2580965380214821, "25"},
                  {3.9318256327243257, "50"},
                  {4.3307333402863311, "75"},
                  {4.6151205168412597, "100"},
                  {4.836281906951478, "125"}
                ],
                [
                  1.6290482690107411,
                  3.5949610853729039,
                  4.1312794865053286,
                  4.4729269285637958,
                  4.7257012118963688
                ]}

      assert axis(:log1p, {-0.84769930322786113, 2.5524473954662863}) ==
               {[
                  {0.0, "0"},
                  {1.3862943611198906, "3"},
                  {1.9459101490553132, "6"},
                  {2.3025850929940459, "9"}
                ],
                [
                  -0.69314718055994529,
                  0.69314718055994529,
                  1.6661022550876019,
                  2.1242476210246797
                ]}

      # y = c(0, 3) under "exp": the extent turned back reaches -3
      assert axis(:exp, {0.045723153840616759, 21.039813769347049}) ==
               {[
                  {0.049787068367863951, "-3"},
                  {0.1353352832366127, "-2"},
                  {0.36787944117144233, "-1"},
                  {1.0, "0"},
                  {2.7182818284590451, "1"},
                  {7.3890560989306495, "2"},
                  {20.085536923187664, "3"}
                ],
                [
                  0.092561175802238327,
                  0.25160736220402752,
                  0.68393972058572117,
                  1.8591409142295225,
                  5.0536689636948466,
                  13.737296511059157,
                  20.128311030622037,
                  20.171085138056412
                ]}

      # y = c(-100, 100) and c(0, 1000) under "asinh"
      assert axis(:asinh, {-5.8281766021716477, 5.8281766021716477}) ==
               {[{-5.2983423656105888, "-100"}, {0.0, "0"}, {5.2983423656105888, "100"}],
                [-2.6491711828052944, 2.6491711828052944]}

      assert axis(:asinh, {-0.38004513547709945, 7.980947845019088}) ==
               {[{0.0, "0"}, {6.9077562789806368, "500"}, {7.6009027095419883, "1000"}],
                [3.4538781394903184, 7.254329494261313]}

      # y = c(-100, 100) under "pseudo_log"; y = c(0, 50) under transform_pseudo_log(0.5)
      assert axis(:pseudo_log, {-5.0657971880905661, 5.0657971880905661}) ==
               {[{-4.6052701709914237, "-100"}, {0.0, "0"}, {4.6052701709914237, "100"}],
                [-2.3026350854957118, 2.3026350854957118]}

      assert axis({:pseudo_log, sigma: 0.5}, {-0.2302635085495712, 4.8355336795409949}) ==
               {[
                  {0.0, "0"},
                  {3.6895038689889055, "20"},
                  {4.3821828480654981, "40"},
                  {4.7875611799938103, "60"}
                ], [1.8447519344944527, 4.0358433585272016, 4.5848720140296546]}
    end

    # y = c(-1000, 1e4) under transform_pseudo_log(2, 10): turned back, 10000 is
    # 9999.999999999989, which plain decimals to 15 digits write "9999.99999999999"
    test "label each break turned back rounded to 14 significant digits" do
      assert axis({:pseudo_log, base: 10, sigma: 2}, {-3.0188688296640893, 4.0188671098683626}) ==
               {[
                  {0.0, "0"},
                  {3.3979400781591376, "5000"},
                  {3.6989700217077965, "10000"},
                  {3.8750612711124903, "15000"},
                  {4.0000000043429447, "20000"}
                ],
                [
                  -1.6989700390795688,
                  1.6989700390795688,
                  3.5484550499334668,
                  3.7870156464101434,
                  3.9375306377277175
                ]}
    end

    # y = c(0, 10) under transform_exp(2): the extent's low end, -50.15, has no logarithm, so R's
    # extended breaks give its high end, log2(1075.15), five times, as a reciprocal's do
    test "an exponential's extent reaching below zero is broken on its high end alone" do
      assert axis({:exp, 2}, {-50.150000000000006, 1075.1500000000001}) ==
               {List.duplicate({1075.1500000000001, "10.070322236718"}, 5), []}
    end
  end

  describe "asn, atanh and the probabilities" do
    # Golden: ggplot2's axes, as the log10 ones above (`inc4/step4/golden.R`); 0 and 1 under a
    # probability and -1 and 1 under atanh are breaks at the infinities, which no axis shows.
    test "take extended breaks in data units, labelled there" do
      # y = c(0.01, 0.5, 0.99) and c(0, 1) under "asn"
      assert axis(:asn, {0.063288693875941854, 3.078303959713852}) ==
               {[
                  {1.0471975511965979, "0.25"},
                  {1.5707963267948968, "0.50"},
                  {2.0943951023931953, "0.75"}
                ],
                [
                  0.52359877559829893,
                  0.78539816339744839,
                  1.3089969389957474,
                  1.8325957145940461,
                  2.3561944901923448,
                  2.617993877991494
                ]}

      assert axis(:asn, {-0.15707963267948966, 3.2986722862692828}) ==
               {[
                  {0.0, "0.00"},
                  {1.0471975511965979, "0.25"},
                  {1.5707963267948968, "0.50"},
                  {2.0943951023931953, "0.75"},
                  {3.1415926535897931, "1.00"}
                ],
                [0.52359877559829893, 1.3089969389957474, 1.8325957145940461, 2.617993877991494]}

      # y = c(0.99, 0.999) under "atanh"
      assert axis(:atanh, {2.5889749746178481, 3.857878604994597}) ==
               {[
                  {2.5987460030278005, "0.989"},
                  {2.6995838633639879, "0.991"},
                  {2.8257430855787402, "0.993"},
                  {2.9944807084449314, "0.995"},
                  {3.2503945223738522, "0.997"},
                  {3.8002011672501994, "0.999"}
                ],
                [
                  2.6491649331958942,
                  2.7626634744713643,
                  2.910111897011836,
                  3.1224376154093916,
                  3.5252978448120258,
                  3.8506200974182931
                ]}

      # y = c(0.01, 0.5, 0.99) and c(0.1, 0.5) under "logit"
      assert axis(:logit, {-5.054631835148049, 5.0546318351480481}) ==
               {[{-1.0986122886681098, "0.25"}, {0.0, "0.50"}, {1.0986122886681098, "0.75"}],
                [
                  -2.1972245773362196,
                  -1.6479184330021646,
                  -0.54930614433405489,
                  0.54930614433405489,
                  1.6479184330021646,
                  2.1972245773362196
                ]}

      assert axis(:logit, {-2.3070858062030299, 0.10986122886681096}) ==
               {[
                  {-2.1972245773362191, "0.1"},
                  {-1.3862943611198906, "0.2"},
                  {-0.84729786038720345, "0.3"},
                  {-0.40546510810816427, "0.4"},
                  {0.0, "0.5"}
                ],
                [
                  -1.791759469228055,
                  -1.1167961107535471,
                  -0.62638148424768381,
                  -0.20273255405408214
                ]}

      # y = c(0.01, 0.5, 0.99) under "probit"
      assert axis(:probit, {-2.5589826614449249, 2.5589826614449249}) ==
               {[{-0.67448975019608171, "0.25"}, {0.0, "0.50"}, {0.67448975019608171, "0.75"}],
                [
                  -1.3489795003921634,
                  -1.0117346252941226,
                  -0.33724487509804085,
                  0.33724487509804085,
                  1.0117346252941226,
                  1.3489795003921634
                ]}

      # y = c(0.01, 0.5, 0.99) under transform_probability("norm", mean = 1, sd = 2)
      assert axis(
               {:probability, :normal, mean: 1, sd: 2},
               {-4.1179653228898498, 6.1179653228898498}
             ) ==
               {[{-0.34897950039216341, "0.25"}, {1.0, "0.50"}, {2.3489795003921632, "0.75"}],
                [
                  -1.6979590007843268,
                  -1.0234692505882452,
                  0.32551024980391829,
                  1.6744897501960816,
                  3.0234692505882448,
                  3.6979590007843264
                ]}

      # y = c(0.01, 0.5, 0.99) under transform_probability("logis", location = 1, scale = 2)
      assert axis(
               {:probability, :logistic, location: 1, scale: 2},
               {-9.1092636702960981, 11.109263670296096}
             ) ==
               {[{-1.1972245773362196, "0.25"}, {1.0, "0.50"}, {3.1972245773362196, "0.75"}],
                [
                  -3.3944491546724391,
                  -2.2958368660043291,
                  -0.098612288668109782,
                  2.09861228866811,
                  4.2958368660043291,
                  5.3944491546724391
                ]}
    end

    # Golden: as above. The platform's atanh places R's -0.5 and 0.5 a double nearer zero.
    test "atanh's positions are within a double of R's" do
      # y = c(-0.9, 0, 0.9) under "atanh"
      assert near_axis?(
               axis(:atanh, {-1.6194414385415423, 1.6194414385415423}),
               {[{-0.54930614433405489, "-0.5"}, {0.0, "0.0"}, {0.54930614433405489, "0.5"}],
                [
                  -1.0986122886681098,
                  -0.82395921650108228,
                  -0.27465307216702745,
                  0.27465307216702745,
                  0.82395921650108228,
                  1.0986122886681098
                ]},
               1
             )
    end

    # y = c(0.00092, 0.0021) under "logit" and c(0.0091, 0.015) under "probit", the normal
    # quantile within 5 doubles of R's, the package's the nearer the truth at 0.009, 0.01 and
    # 0.015: turned back,
    # 0.0009 is 0.0009000000000000006, which plain decimals to 15 digits write
    # "0.000900000000000001"
    test "a probability labels each break turned back rounded to 14 significant digits" do
      assert axis(:logit, {-7.0337318015544819, -6.1342217744039083}) ==
               {[
                  {-7.0122153893967987, "0.0009"},
                  {-6.7242330016116636, "0.0012"},
                  {-6.5007890447477052, "0.0015"},
                  {-6.3181669921333894, "0.0018"},
                  {-6.1637157261608895, "0.0021"}
                ],
                [
                  -6.8682241955042311,
                  -6.6125110231796844,
                  -6.4094780184405469,
                  -6.2409413591471399
                ]}

      assert near_axis?(
               axis(:probit, {-2.371006829946066, -2.1615072332909611}),
               {[
                  {-2.365618126864292, "0.009"},
                  {-2.3263478740408408, "0.010"},
                  {-2.290367877855267, "0.011"},
                  {-2.257129244486225, "0.012"},
                  {-2.226211769317175, "0.013"},
                  {-2.1972863766410513, "0.014"},
                  {-2.1700903775845601, "0.015"}
                ],
                [
                  -2.3459830004525664,
                  -2.3083578759480536,
                  -2.2737485611707458,
                  -2.2416705069017002,
                  -2.2117490729791132,
                  -2.1836883771128059
                ]},
               5
             )
    end
  end

  describe "Box-Cox, modulus, Yeo-Johnson and timespan" do
    # Golden: `fixtures/r_power_4.6.1.csv` is R 4.6.1's (scales 1.4.0) transform, inverse,
    # d_transform and d_inverse of each at the nine doubles and eleven edges, the exponents near
    # zero and near 2 among them (`inc4/step5/fixture.R`), but two of the package's own, agreed: a
    # Box-Cox value below minus its offset is NaN, where R refuses the whole vector, and yj's
    # inverse derivative below 0 at an exponent of 2 is the slope, exp(-x), where R's fails. Every
    # double is R's but six, where log1p's and expm1's measured methods are a double off R's.
    test "each gives R's doubles, its derivatives too, but log1p's and expm1's last bit" do
      names = %{
        "boxcox -1" => {:boxcox, -1},
        "boxcox 0" => {:boxcox, 0},
        "boxcox 0.5" => {:boxcox, 0.5},
        "boxcox 1" => {:boxcox, 1},
        "boxcox 2" => {:boxcox, 2},
        "boxcox 1e-08" => {:boxcox, 1.0e-8},
        "boxcox 0.5 offset 3" => {:boxcox, 0.5, offset: 3},
        "boxcox 0 offset 3" => {:boxcox, 0, offset: 3},
        "modulus -1" => {:modulus, -1},
        "modulus 0" => {:modulus, 0},
        "modulus 0.5" => {:modulus, 0.5},
        "modulus 1" => {:modulus, 1},
        "modulus 2" => {:modulus, 2},
        "modulus 0.5 offset 3" => {:modulus, 0.5, offset: 3},
        "yj -1" => {:yj, -1},
        "yj 0" => {:yj, 0},
        "yj 0.5" => {:yj, 0.5},
        "yj 1" => {:yj, 1},
        "yj 2" => {:yj, 2},
        "yj 3" => {:yj, 3},
        "yj 1e-08" => {:yj, 1.0e-8},
        "yj 1.99999999" => {:yj, 1.99999999},
        "timespan" => :timespan,
        "timespan minute" => {:timespan, :minute},
        "timespan week" => {:timespan, :week}
      }

      functions = %{
        "transform" => &Transform.transform/2,
        "inverse" => &Transform.inverse/2,
        "derivative" => &Transform.derivative/2,
        "inverse_derivative" => &Transform.inverse_derivative/2
      }

      rows =
        __DIR__
        |> Path.join("fixtures/r_power_4.6.1.csv")
        |> File.stream!()
        |> Stream.drop(1)
        |> Enum.map(fn line ->
          [name, function, value, expected] =
            line
            |> String.trim()
            |> String.split(",")

          {Map.fetch!(names, String.trim(name, ~s("))), String.trim(function, ~s(")),
           r_value(value), r_value(expected)}
        end)

      assert Enum.count(rows) == 1880

      departed =
        Enum.reject(rows, fn {name, function, value, expected} ->
          [ours] = functions[function].(name, [value])
          ours === expected
        end)

      assert Enum.map(departed, fn {name, function, value, _expected} ->
               {name, function, value}
             end) ==
               [
                 {{:yj, 0}, "transform", 2.0},
                 {{:yj, 0}, "inverse", 0.1},
                 {{:yj, 2}, "transform", -2.0},
                 {{:yj, 1.0e-8}, "transform", 2.0},
                 {{:yj, 1.0e-8}, "inverse", 0.1},
                 {{:yj, 1.99999999}, "transform", -2.0}
               ]

      for {name, function, value, expected} <- departed do
        [ours] = functions[function].(name, [value])
        assert ulps(ours, expected) == 1
      end
    end

    # Golden: ggplot2's axes, the plot `ggplot(data.frame(x = seq_along(ys), y = ys), aes(x, y)) +
    # geom_point() + scale_y_continuous(transform = ...)` for the ys named (`inc4/step5/axes*.R`).
    # R writes these labels with format(), so `0.0 2.5` and `10.18059` where the package writes
    # plain decimals to 15 digits.
    test "each finds extended breaks in data units, minor breaks regular in transformed space" do
      # ys = c(1, 100)
      assert axis({:boxcox, 0.5}, {-0.90000000000000002, 18.899999999999999}) ==
               {[
                  {8.0, "25"},
                  {12.142135623730951, "50"},
                  {15.320508075688775, "75"},
                  {18.0, "100"}
                ],
                [
                  3.857864376269049,
                  5.9289321881345245,
                  10.071067811865476,
                  13.731321849709863,
                  16.660254037844389
                ]}

      # ys = c(0, 10): 0 at minus infinity, so the axis is 10's alone
      assert axis({:boxcox, 0}, {2.2525850929940461, 2.3525850929940457}) ==
               {[
                  {2.2772672850097559, "9.75"},
                  {2.3025850929940459, "10.00"},
                  {2.3272777055844172, "10.25"},
                  {2.3513752571634776, "10.50"}
                ],
                [2.2646083810176112, 2.2899261890019007, 2.3149313992892315, 2.3393264813739476]}

      # ys = c(-5, 5)
      assert axis({:modulus, -1}, {-0.91666666666666674, 0.91666666666666674}) ==
               {[
                  {-0.90909090909090906, "-10"},
                  {-0.83333333333333337, "-5"},
                  {-0.0, "0"},
                  {0.83333333333333337, "5"},
                  {0.90909090909090906, "10"}
                ],
                [
                  -0.87121212121212122,
                  -0.41666666666666669,
                  0.41666666666666669,
                  0.87121212121212122
                ]}

      # ys = c(-5, 5), an offset of 3
      assert axis({:modulus, 2, offset: 3}, {-34.649999999999999, 34.649999999999999}) ==
               {[
                  {-31.5, "-5.0"},
                  {-14.625, "-2.5"},
                  {0.0, "0.0"},
                  {14.625, "2.5"},
                  {31.5, "5.0"}
                ], [-23.0625, -7.3125, 7.3125, 23.0625]}

      # ys = c(-100, 100)
      assert axis({:yj, 0.5}, {-710.73119397535902, 52.805986728794203}) ==
               {[
                  {0.0, "0"},
                  {26.354893757515651, "200"},
                  {38.049968789001575, "400"},
                  {47.03060268852505, "600"}
                ],
                [
                  -26.354893757515651,
                  -13.177446878757825,
                  13.177446878757825,
                  32.202431273258611,
                  42.540285738763316
                ]}

      # ys = c(-10, 10)
      assert axis({:yj, 2}, {-5.5177900364382895, 63.11989476363992}) ==
               {[
                  {-5.3033049080590757, "-200"},
                  {-5.0172798368149243, "-150"},
                  {-4.6151205168412597, "-100"},
                  {-3.9318256327243257, "-50"},
                  {0.0, "0"}
                ],
                [
                  -5.446317443681151,
                  -5.1602923724370005,
                  -4.816200176828092,
                  -4.2734730747827925,
                  -1.9659128163621629,
                  0.14301253562207572,
                  0.28602507124415144
                ]}
    end

    # Golden: ggplot2's axes, as above. Where the 5% widening passes a bound the transformation
    # never reaches, ggplot2 squishes the extent onto it, the bound turns back to an infinity, and
    # R's extended breaks on one infinite end are five copies of the other: kept, by a rounding
    # hair, under yj(-1) on c(-10, 10), outside the extent under boxcox(-1) on c(1, 100).
    test "an end that turns back to an infinity is set aside, as R's breaks then sit on the other" do
      assert axis({:boxcox, -1}, {-0.049500000000000002, 1.0395000000000001}) == {[], []}

      stacked = List.duplicate({-465.54545454545422, "-10.1805902224244"}, 5)
      assert axis({:yj, -1}, {-465.5454545454545, 23.121212121212125}) == {stacked, []}

      assert Transform.squish({:yj, -1}, {-465.5454545454545, 23.121212121212125}) ===
               {-465.5454545454545, 1.0}

      # As ggplot2's get_breaks() squishes every transformation's limits into its domain
      # transformed, sorted: exp's from 0, the reverse's not at all, its ends -Inf and Inf
      assert {Transform.squish(:exp, {-1.0, 3.0}), Transform.squish(:reverse, {-3.0, 5.0})} ===
               {{0.0, 3.0}, {-3.0, 5.0}}

      assert Transform.breaks({:modulus, -1}, Transform.squish({:modulus, -1}, {-1.5, 1.5})) == []
    end

    # Golden: ggplot2's axes, as above. R labels each break turned back, so boxcox(0.5, offset =
    # 3)'s 0 is -4.440892e-16 and every label scientific, `-4.440892e-16 5.000000e-01
    # 1.000000e+00`; boxcox(3) keeps few digits near 0, which R's seven hide. Its domain is R's,
    # from 0 whatever the offset, so ys = c(-2.9, 1) finds no break below 0.
    test "each labels its breaks from the values in data units they were found from" do
      assert axis({:boxcox, 0.5, offset: 3}, {-1.5359216913646403, 2.1683772233983163}) ==
               {[{1.4641016151377544, "0.0"}, {1.7416573867739413, "0.5"}, {2.0, "1.0"}],
                [
                  1.1865458435015674,
                  1.3253237293196609,
                  1.6028795009558479,
                  1.8708286933869707,
                  2.1387778858180937
                ]}

      assert axis({:boxcox, 3}, {-0.33333328668611861, -0.33333267514444442}) ==
               {[
                  {-0.33333321900000001, "0.007"},
                  {-0.3333330903333333, "0.009"},
                  {-0.33333288966666669, "0.011"}
                ],
                [
                  -0.33333328333333334,
                  -0.33333315466666669,
                  -0.33333299,
                  -0.3333328253333333,
                  -0.33333276099999998
                ]}

      # A break not among the axis's own, as on an axis of no width, is written as a given one
      assert Transform.format({:boxcox, 3}, [-0.33333321900000001], {0.0, 1.0}) ==
               Transform.format({:boxcox, 3}, [-0.33333321900000001], :given)

      # and, beside one that is, both are
      both = [-0.33333321900000001, -0.333333]
      extent = {-0.33333328668611861, -0.33333267514444442}

      assert Transform.format({:boxcox, 3}, both, extent) ==
               Transform.format({:boxcox, 3}, both, :given)

      # ys = c(0.0012, 0.0061), where the round trip writes 0.00099999999999989
      assert axis({:modulus, 2}, {0.0009548257500000489, 0.0063644992499999383}) ==
               {[
                  {0.0010004999999998487, "0.001"},
                  {0.0020019999999999483, "0.002"},
                  {0.0030044999999998545, "0.003"},
                  {0.0040080000000000116, "0.004"},
                  {0.0050124999999998643, "0.005"},
                  {0.0060179999999999678, "0.006"}
                ],
                [
                  0.0015012499999998985,
                  0.0025032499999999014,
                  0.003506249999999933,
                  0.0045102499999999379,
                  0.0055152499999999161
                ]}

      # A break given is turned back and rounded to 14 significant digits, which keeps the round
      # trip's error here: 0.007 comes back 0.006999999999715905
      assert Transform.format({:boxcox, 3}, [-0.33333321900000001], :given) ==
               ["0.0069999999997159"]

      # 0 and 0.000005 cubed are one double from -1/3: the first labels the position they share
      extent = {-0.3333333333333334, -0.33333333333333054}

      breaks =
        {:boxcox, 3}
        |> Transform.breaks(Transform.squish({:boxcox, 3}, extent))
        |> inside(extent)

      assert [shared, shared | _rest] = breaks

      assert Transform.format({:boxcox, 3}, breaks, extent) ==
               ["0.000000", "0.000000", "0.000010", "0.000015", "0.000020"]
    end

    # Golden: ggplot2's axes, as above, ys counted in the unit named.
    test "a span of time is its seconds, broken and labelled as a span, in its unit" do
      # ys = c(0, 100) seconds
      assert axis(:timespan, {-5.0, 105.0}) ==
               {[
                  {0.0, "0"},
                  {20.0, "20s"},
                  {40.0, "40s"},
                  {60.0, "1m"},
                  {80.0, "80s"},
                  {100.0, "100s"}
                ], [10.0, 30.0, 50.0, 70.0, 90.0]}

      # ys = c(0, 100) minutes
      assert axis({:timespan, :minute}, {-300.0, 6300.0}) ==
               {[
                  {0.0, "0"},
                  {1200.0, "20m"},
                  {2400.0, "40m"},
                  {3600.0, "1h"},
                  {4800.0, "80m"},
                  {6000.0, "100m"}
                ], [600.0, 1800.0, 3000.0, 4200.0, 5400.0]}

      # ys = c(-30, 30) hours
      assert axis({:timespan, :hour}, {-118_800.0, 118_800.0}) ==
               {[{-69_120.0, "-1 152m"}, {0.0, "0"}, {69_120.000000000029, "19h"}],
                [-103_680.0, -34_560.0, 34_560.000000000015, 103_680.00000000003]}

      # ys = c(0, 3) weeks
      assert axis({:timespan, :week}, {-90_720.0, 1_905_120.0}) ==
               {[{0.0, "0"}, {604_800.0, "1w"}, {1_209_600.0, "2w"}, {1_814_400.0, "3w"}],
                [302_400.0, 907_200.0, 1_512_000.0]}
    end

    test "a span of time counts no breaks and has no derivatives, as R's" do
      breaks =
        assert_raise(ArgumentError, fn -> Transform.breaks(:timespan, {0.0, 3.0}, n: 3) end)

      assert breaks.message =~ "the :timespan transformation counts no breaks"

      for name <- [:timespan, {:timespan, :minute}] do
        assert_raise FunctionClauseError, fn -> Transform.derivative(name, [1.0]) end
        assert_raise FunctionClauseError, fn -> Transform.inverse_derivative(name, [1.0]) end
      end

      # R: transform_timespan("secs") and ("days") of 1 and 2.5 are 1 2.5 and 86400 216000, the
      # latter's inverse of 86400 and 3600 1 0.041666666666666664 (`inc4/step5/pins.R`)
      assert {Transform.transform({:timespan, :second}, [1, 2.5]),
              Transform.transform({:timespan, :day}, [1, 2.5]),
              Transform.inverse({:timespan, :day}, [86_400.0, 3600.0])} ===
               {[1.0, 2.5], [86_400.0, 216_000.0], [1.0, 0.041666666666666664]}

      # R: trim_to_domain(transform_timespan("mins"), c(-5, 0.3, 9, NA)) is -300 540
      assert Transform.trim_to_domain({:timespan, :minute}, [-5, 0.3, 9, nil]) === {-300.0, 540.0}
    end

    # R takes any number as an exponent, garbage at Inf and failing at NA, and any offset: a
    # negative one refuses values, and a modulus offset below 1 no longer rises, offset 0 sending
    # 0.5 to -0.586 and -0.5 to 0.586 (`inc4/step5/params.R`).
    test "an exponent not a number, an offset out of range or another unit is refused" do
      for name <- [
            {:boxcox, :infinity},
            {:boxcox, nil},
            {:boxcox, 0.5, offset: -1},
            {:boxcox, 0.5, offset: :infinity},
            {:boxcox, 0.5, scale: 3},
            {:boxcox, 0.5, offset: 1, offset: 2},
            {:modulus, nil},
            {:modulus, 0.5, offset: 0.999},
            {:modulus, 0.5, offset: 0},
            {:yj, :nan},
            {:yj, 0.5, offset: 1},
            {:timespan, :month},
            {:timespan, "mins"}
          ] do
        assert_raise FunctionClauseError, fn -> Transform.transform(name, [1.0]) end
      end

      # R: transform_boxcox(1e-7) of 0.5 and 2 is -0.69314715633872481 0.69314720407831487, a
      # power, an exponent below 1e-7 alone counting as 0 (`inc4/step5/pins.R`)
      assert Transform.transform({:boxcox, 1.0e-7}, [0.5, 2.0]) ===
               [-0.69314715633872481, 0.69314720407831487]

      assert {Transform.transform({:boxcox, 0.5, offset: 0}, [2.0]),
              Transform.transform({:modulus, 0.5, offset: 1}, [2.0])} ===
               {Transform.transform({:boxcox, 0.5}, [2.0]),
                Transform.transform({:modulus, 0.5}, [2.0])}
    end
  end

  describe "a base or a sigma" do
    # R takes a base below 1, falling, and gives garbage or fails at 1, 0, below 0 and NA; a sigma
    # below 0 flips the axis and 0 places every value at an infinity (`inc4/step3/params.R`).
    test "a base not above 1 or a sigma not above 0 is refused wherever the name is handed" do
      for name <- [
            {:log, 1},
            {:log, 0.5},
            {:log, -2},
            {:log, :infinity},
            {:log, nil},
            {:exp, 1.0},
            {:exp, 0.5},
            {:pseudo_log, sigma: 0},
            {:pseudo_log, sigma: -1},
            {:pseudo_log, base: 1},
            {:pseudo_log, sigma: 1, base: 0.5},
            {:pseudo_log, base: 10, sigma: 0}
          ] do
        assert_raise FunctionClauseError, fn -> Transform.transform(name, [1.0]) end
        assert_raise FunctionClauseError, fn -> Transform.breaks(name, {0.0, 1.0}) end
      end
    end

    test "a pseudo-logarithm takes sigma:, base: or both, once each, and nothing else" do
      for name <- [
            {:pseudo_log, []},
            {:pseudo_log, sigma: 1, sigma: 2},
            {:pseudo_log, sigma: 1, bass: 10},
            {:pseudo_log, %{sigma: 1}}
          ] do
        assert_raise FunctionClauseError, fn -> Transform.transform(name, [1.0]) end
      end

      assert Transform.transform({:pseudo_log, base: :math.exp(1), sigma: 1}, [2.0]) ===
               Transform.transform(:pseudo_log, [2.0])

      # Golden: R's transform_pseudo_log(base = 10), sigma 1, of and back from -2, 0.5 and 2
      # (`inc4/step3/base_only.R`)
      assert {Transform.transform({:pseudo_log, base: 10}, [-2.0, 0.5, 2.0]),
              Transform.inverse({:pseudo_log, base: 10}, [-2.0, 0.5, 2.0])} ===
               {[-0.38277568533786305, 0.10747331870609976, 0.38277568533786305],
                [-99.990000000000038, 2.8460498941515415, 99.990000000000038]}
    end
  end

  describe "a distribution's parameters" do
    # R takes an sd or scale of 0, placing every value at the mean, gives NaN below it and
    # garbage or NA at Inf and NA (`inc4/step4/params.R`).
    test "a spread not above 0 or a mean not a number is refused wherever the name is handed" do
      for name <- [
            {:probability, :normal, sd: 0},
            {:probability, :normal, sd: -1},
            {:probability, :normal, sd: :infinity},
            {:probability, :normal, mean: :infinity},
            {:probability, :normal, mean: nil, sd: 1},
            {:probability, :logistic, scale: 0},
            {:probability, :logistic, location: 1, scale: -2},
            {:probability, :logistic, location: :neg_infinity}
          ] do
        assert_raise FunctionClauseError, fn -> Transform.transform(name, [0.5]) end
        assert_raise FunctionClauseError, fn -> Transform.breaks(name, {0.0, 1.0}) end
      end
    end

    test "a distribution takes its own two names, either or both, once each, and nothing else" do
      for name <- [
            {:probability, :normal},
            {:probability, :normal, []},
            {:probability, :normal, mean: 1, mean: 2},
            {:probability, :normal, scale: 2},
            {:probability, :logistic, sd: 2},
            {:probability, :logistic, location: 1, scale: 2, location: 3},
            {:probability, :cauchy, location: 1},
            {:probability, :normal, %{sd: 2}}
          ] do
        assert_raise FunctionClauseError, fn -> Transform.transform(name, [0.5]) end
      end

      values = [0.0, 1.0e-5, 0.3, 0.5, 1.0]

      assert {Transform.transform({:probability, :normal, sd: 1, mean: 0}, values),
              Transform.inverse_derivative({:probability, :logistic, location: 0}, values)} ===
               {Transform.transform(:probit, values),
                Transform.inverse_derivative(:logit, values)}

      assert Transform.transform({:probability, :normal, mean: 1}, [0.5, 0.75]) ===
               Transform.transform({:probability, :normal, mean: 1, sd: 1}, [0.5, 0.75])

      # Golden: R's transform_probability("norm", sd = 2) of 0.7212275324855 and
      # 0.19690938852727413, and transform_probability("logis", scale = 2) of 0.1 and 0.75,
      # each about R's default location of 0 (`inc4/step4/pins.R`, `pins2.R`)
      assert {Transform.transform({:probability, :normal, sd: 2}, [
                0.7212275324855,
                0.19690938852727413
              ]), Transform.transform({:probability, :logistic, scale: 2}, [0.1, 0.75])} ===
               {[1.172984002905157, -1.7054249286588437],
                [-4.3944491546724382, 2.1972245773362196]}
    end
  end

  describe "R's doubles" do
    # Golden: each transformation's `transform`, `d_transform` and `d_inverse` of these values in
    # R (`inc4/step2/probe.R`), a zero's sign read as `1 / x`.
    @doubles [:neg_infinity, -2.0, -0.0, 0.0, 0.5, 2.0, :infinity, nil, :nan]

    test "the identity keeps each, its derivatives 1 everywhere" do
      ones = List.duplicate(1.0, 9)

      assert {Transform.transform(:identity, @doubles), Transform.derivative(:identity, @doubles),
              Transform.inverse_derivative(:identity, @doubles)} === {@doubles, ones, ones}
    end

    test "log10's, NaN below zero" do
      assert Transform.transform(:log10, @doubles) ===
               [
                 :nan,
                 :nan,
                 :neg_infinity,
                 :neg_infinity,
                 -0.3010299956639812,
                 0.3010299956639812,
                 :infinity,
                 nil,
                 :nan
               ]

      assert Transform.derivative(:log10, @doubles) ===
               [
                 -0.0,
                 -0.21714724095162588,
                 :neg_infinity,
                 :infinity,
                 0.86858896380650352,
                 0.21714724095162588,
                 0.0,
                 nil,
                 :nan
               ]

      assert Transform.inverse_derivative(:log10, @doubles) ===
               [
                 0.0,
                 0.023025850929940458,
                 2.3025850929940459,
                 2.3025850929940459,
                 7.2814134002118021,
                 230.25850929940458,
                 :infinity,
                 nil,
                 :nan
               ]
    end

    # 10^400 * log(10) is Inf
    test "log10's inverse derivative past the largest double is plus infinity" do
      assert Transform.inverse_derivative(:log10, [400.0]) === [:infinity]
    end

    test "the square root's, NaN below zero and -0.0's its own" do
      assert Transform.transform(:sqrt, @doubles) ===
               [
                 :nan,
                 :nan,
                 -0.0,
                 0.0,
                 0.70710678118654757,
                 1.4142135623730951,
                 :infinity,
                 nil,
                 :nan
               ]

      assert Transform.derivative(:sqrt, @doubles) ===
               [
                 :nan,
                 :nan,
                 :neg_infinity,
                 :infinity,
                 0.70710678118654746,
                 0.35355339059327373,
                 0.0,
                 nil,
                 :nan
               ]

      assert Transform.inverse_derivative(:sqrt, @doubles) ===
               [:neg_infinity, -4.0, -0.0, 0.0, 1.0, 4.0, :infinity, nil, :nan]
    end

    test "the reversal's, its derivatives -1 everywhere" do
      minus_ones = List.duplicate(-1.0, 9)

      assert {Transform.transform(:reverse, @doubles), Transform.derivative(:reverse, @doubles),
              Transform.inverse_derivative(:reverse, @doubles)} ===
               {[:infinity, 2.0, 0.0, -0.0, -0.5, -2.0, :neg_infinity, nil, :nan], minus_ones,
                minus_ones}
    end

    test "the reciprocal's, each zero to the infinity of its sign" do
      derivatives = [-0.0, -0.25, :neg_infinity, :neg_infinity, -4.0, -0.25, -0.0, nil, :nan]

      assert {Transform.transform(:reciprocal, @doubles),
              Transform.derivative(:reciprocal, @doubles),
              Transform.inverse_derivative(:reciprocal, @doubles)} ===
               {[-0.0, -0.5, :neg_infinity, :infinity, 2.0, 0.5, 0.0, nil, :nan], derivatives,
                derivatives}
    end

    # Golden: R's for step 3's transformations (`inc4/step3/probe.R`), inverses but at `NA`, the
    # infinities' and zeros' in R's IEEE arithmetic, a zero of either sign `+0` from log1p,
    # expm1, asinh, sinh and the pseudo-logarithm, as R's on a vector. Two are the package's own,
    # agreed departures: log1p(2), by Goldberg's method, 1 ulp above R's 1.0986122886681096, and
    # the pseudo-logarithm's of 0.5 in sigma 2, base 10, through the platform's asinh, 2 ulps
    # below R's 0.054146423209630819.
    @log1p_of_two 1.0986122886681098
    @pseudo_log_of_half 0.054146423209630812
    @r_doubles [
      {:log,
       {[
          :nan,
          :nan,
          :neg_infinity,
          :neg_infinity,
          -0.69314718055994529,
          0.69314718055994529,
          :infinity,
          nil,
          :nan
        ],
        [
          0.0,
          0.1353352832366127,
          1.0,
          1.0,
          1.6487212707001282,
          7.3890560989306495,
          :infinity,
          :nan
        ], [-0.0, -0.5, :neg_infinity, :infinity, 2.0, 0.5, 0.0, nil, :nan],
        [
          0.0,
          0.1353352832366127,
          1.0,
          1.0,
          1.6487212707001282,
          7.3890560989306495,
          :infinity,
          nil,
          :nan
        ]}},
      {:log2,
       {[:nan, :nan, :neg_infinity, :neg_infinity, -1.0, 1.0, :infinity, nil, :nan],
        [0.0, 0.25, 1.0, 1.0, 1.4142135623730951, 4.0, :infinity, :nan],
        [
          -0.0,
          -0.72134752044448169,
          :neg_infinity,
          :infinity,
          2.8853900817779268,
          0.72134752044448169,
          0.0,
          nil,
          :nan
        ],
        [
          0.0,
          0.17328679513998632,
          0.69314718055994529,
          0.69314718055994529,
          0.98025814346854723,
          2.7725887222397811,
          :infinity,
          nil,
          :nan
        ]}},
      {{:log, 3},
       {[
          :nan,
          :nan,
          :neg_infinity,
          :neg_infinity,
          -0.63092975357145742,
          0.63092975357145742,
          :infinity,
          nil,
          :nan
        ], [0.0, 0.1111111111111111, 1.0, 1.0, 1.7320508075688772, 9.0, :infinity, :nan],
        [
          -0.0,
          -0.45511961331341866,
          :neg_infinity,
          :infinity,
          1.8204784532536746,
          0.45511961331341866,
          0.0,
          nil,
          :nan
        ],
        [
          0.0,
          0.12206803207423442,
          1.0986122886681098,
          1.0986122886681098,
          1.9028523017926919,
          9.8875105980129874,
          :infinity,
          nil,
          :nan
        ]}},
      {{:log, 10},
       {[
          :nan,
          :nan,
          :neg_infinity,
          :neg_infinity,
          -0.3010299956639812,
          0.3010299956639812,
          :infinity,
          nil,
          :nan
        ], [0.0, 0.01, 1.0, 1.0, 3.1622776601683795, 100.0, :infinity, :nan],
        [
          -0.0,
          -0.21714724095162588,
          :neg_infinity,
          :infinity,
          0.86858896380650352,
          0.21714724095162588,
          0.0,
          nil,
          :nan
        ],
        [
          0.0,
          0.023025850929940458,
          2.3025850929940459,
          2.3025850929940459,
          7.2814134002118021,
          230.25850929940458,
          :infinity,
          nil,
          :nan
        ]}},
      {:log1p,
       {[:nan, :nan, 0.0, 0.0, 0.40546510810816438, @log1p_of_two, :infinity, nil, :nan],
        [
          -1.0,
          -0.8646647167633873,
          0.0,
          0.0,
          0.64872127070012819,
          6.3890560989306504,
          :infinity,
          :nan
        ], [-0.0, -1.0, 1.0, 1.0, 0.66666666666666663, 0.33333333333333331, 0.0, nil, :nan],
        [
          0.0,
          0.1353352832366127,
          1.0,
          1.0,
          1.6487212707001282,
          7.3890560989306504,
          :infinity,
          nil,
          :nan
        ]}},
      {:exp,
       {[
          0.0,
          0.1353352832366127,
          1.0,
          1.0,
          1.6487212707001282,
          7.3890560989306495,
          :infinity,
          nil,
          :nan
        ],
        [
          :nan,
          :nan,
          :neg_infinity,
          :neg_infinity,
          -0.69314718055994529,
          0.69314718055994529,
          :infinity,
          :nan
        ],
        [
          0.0,
          0.1353352832366127,
          1.0,
          1.0,
          1.6487212707001282,
          7.3890560989306495,
          :infinity,
          nil,
          :nan
        ], [-0.0, -0.5, :neg_infinity, :infinity, 2.0, 0.5, 0.0, nil, :nan]}},
      {{:exp, 2},
       {[0.0, 0.25, 1.0, 1.0, 1.4142135623730951, 4.0, :infinity, nil, :nan],
        [:nan, :nan, :neg_infinity, :neg_infinity, -1.0, 1.0, :infinity, :nan],
        [
          0.0,
          0.17328679513998632,
          0.69314718055994529,
          0.69314718055994529,
          0.98025814346854723,
          2.7725887222397811,
          :infinity,
          nil,
          :nan
        ],
        [
          -0.0,
          -0.72134752044448169,
          :neg_infinity,
          :infinity,
          2.8853900817779268,
          0.72134752044448169,
          0.0,
          nil,
          :nan
        ]}},
      {{:exp, 10},
       {[0.0, 0.01, 1.0, 1.0, 3.1622776601683795, 100.0, :infinity, nil, :nan],
        [
          :nan,
          :nan,
          :neg_infinity,
          :neg_infinity,
          -0.3010299956639812,
          0.3010299956639812,
          :infinity,
          :nan
        ],
        [
          0.0,
          0.023025850929940458,
          2.3025850929940459,
          2.3025850929940459,
          7.2814134002118021,
          230.25850929940458,
          :infinity,
          nil,
          :nan
        ],
        [
          -0.0,
          -0.21714724095162588,
          :neg_infinity,
          :infinity,
          0.86858896380650352,
          0.21714724095162588,
          0.0,
          nil,
          :nan
        ]}},
      {:asinh,
       {[
          :neg_infinity,
          -1.4436354751788103,
          0.0,
          0.0,
          0.48121182505960347,
          1.4436354751788103,
          :infinity,
          nil,
          :nan
        ],
        [
          :neg_infinity,
          -3.626860407847019,
          0.0,
          0.0,
          0.52109530549374738,
          3.626860407847019,
          :infinity,
          :nan
        ],
        [
          0.0,
          0.44721359549995793,
          1.0,
          1.0,
          0.89442719099991586,
          0.44721359549995793,
          0.0,
          nil,
          :nan
        ],
        [
          :infinity,
          3.7621956910836314,
          1.0,
          1.0,
          1.1276259652063807,
          3.7621956910836314,
          :infinity,
          nil,
          :nan
        ]}},
      {:pseudo_log,
       {[
          :neg_infinity,
          -0.88137358701954305,
          0.0,
          0.0,
          0.24746646154726346,
          0.88137358701954305,
          :infinity,
          nil,
          :nan
        ],
        [
          :neg_infinity,
          -7.253720815694038,
          0.0,
          0.0,
          1.0421906109874948,
          7.253720815694038,
          :infinity,
          :nan
        ],
        [
          0.0,
          0.35355339059327373,
          0.5,
          0.5,
          0.48507125007266594,
          0.35355339059327373,
          0.0,
          nil,
          :nan
        ],
        [
          :infinity,
          7.5243913821672628,
          2.0,
          2.0,
          2.2552519304127614,
          7.5243913821672628,
          :infinity,
          nil,
          :nan
        ]}},
      {{:pseudo_log, sigma: 2, base: 10},
       {[
          :neg_infinity,
          -0.20898764024997873,
          0.0,
          0.0,
          @pseudo_log_of_half,
          0.20898764024997873,
          :infinity,
          nil,
          :nan
        ],
        [
          :neg_infinity,
          -199.98000000000008,
          0.0,
          0.0,
          5.6920997883030831,
          199.98000000000008,
          :infinity,
          :nan
        ],
        [
          0.0,
          0.097111198378872318,
          0.10857362047581294,
          0.10857362047581294,
          0.10773520159285525,
          0.097111198378872318,
          0.0,
          nil,
          :nan
        ],
        [
          :infinity,
          460.56307030066927,
          9.2103403719761836,
          9.2103403719761836,
          16.019109480465964,
          460.56307030066927,
          :infinity,
          nil,
          :nan
        ]}},
      {{:pseudo_log, sigma: 0.5, base: 2},
       {[
          :neg_infinity,
          -2.0827257408918518,
          0.0,
          0.0,
          0.69424191363061738,
          2.0827257408918518,
          :infinity,
          nil,
          :nan
        ], [:neg_infinity, -1.875, 0.0, 0.0, 0.35355339059327373, 1.875, :infinity, :nan],
        [
          0.0,
          0.64519283644591208,
          1.4426950408889634,
          1.4426950408889634,
          1.2903856728918242,
          0.64519283644591208,
          0.0,
          nil,
          :nan
        ],
        [
          :infinity,
          1.4729377586898837,
          0.69314718055994529,
          0.69314718055994529,
          0.73519360760141028,
          1.4729377586898837,
          :infinity,
          nil,
          :nan
        ]}}
    ]

    test "the logarithms, exponentials, asinh and pseudo-logarithms give R's" do
      inputs = Enum.reject(@doubles, &is_nil/1)

      for {name, expected} <- @r_doubles do
        assert {Transform.transform(name, @doubles), Transform.inverse(name, inputs),
                Transform.derivative(name, @doubles),
                Transform.inverse_derivative(name, @doubles)} === expected,
               inspect(name)
      end
    end

    # R's asinh's d_transform(1e200) is 0, inverse(-1000) -Inf, d_inverse(-1000) Inf; the
    # pseudo-logarithm's likewise; exp's transform(800) and d_transform(800) Inf, d_inverse(0)
    # Inf; log's inverse(800) and d_inverse(800) Inf; log1p's transform(-1) -Inf, d_transform(-1)
    # Inf, inverse(800) Inf and inverse(-1000) -1 (`inc4/step3/extra.R`)
    test "past the largest double, an infinity" do
      assert {Transform.derivative(:asinh, [1.0e200]), Transform.inverse(:asinh, [-1000.0]),
              Transform.inverse_derivative(:asinh, [-1000.0])} ===
               {[0.0], [:neg_infinity], [:infinity]}

      assert {Transform.derivative(:pseudo_log, [1.0e200]),
              Transform.inverse(:pseudo_log, [1000.0]),
              Transform.inverse_derivative(:pseudo_log, [-1000.0])} ===
               {[0.0], [:infinity], [:infinity]}

      assert {Transform.transform(:exp, [800.0]), Transform.derivative(:exp, [800.0]),
              Transform.inverse_derivative(:exp, [0.0]), Transform.inverse(:log, [800.0]),
              Transform.inverse_derivative(:log, [800.0])} ===
               {[:infinity], [:infinity], [:infinity], [:infinity], [:infinity]}

      assert {Transform.transform(:log1p, [-1.0]), Transform.derivative(:log1p, [-1.0]),
              Transform.inverse(:log1p, [800.0, -1000.0]),
              Transform.inverse_derivative(:log1p, [800.0])} ===
               {[:neg_infinity], [:infinity], [:infinity, -1.0], [:infinity]}
    end

    # Golden: R's for step 4's transformations (`inc4/step4/golden.R`), inverses but at `NA`, a
    # zero of either sign `+0` from asin, sin, tanh and atanh, as R's, and `-0.0`'s square root
    # its own, so asn's derivative there minus infinity. Three are the package's own, agreed
    # departures: atanh's of 0.5, through the platform's, a double below R's correctly rounded
    # 0.54930614433405489; and the normal distribution's of -2, two doubles below R's
    # 0.022750131948179212, the nearer the truth, and of 0.5 and -0.5, a double either side of
    # R's 0.69146246127401301 and 0.30853753872598694, each the nearer the truth.
    @atanh_of_half 0.5493061443340548
    @normal_below_minus_two 0.022750131948179205
    @normal_below_half 0.6914624612740131
    @normal_below_minus_half 0.3085375387259869
    @r_proportions [
      {:asn,
       {[:nan, :nan, 0.0, 0.0, 1.5707963267948968, :nan, :nan, nil, :nan],
        [
          :nan,
          0.70807341827357118,
          0.0,
          0.0,
          0.061208719054813648,
          0.70807341827357118,
          :nan,
          :nan
        ], [:nan, :nan, :neg_infinity, :infinity, 2.0, :nan, :nan, nil, :nan],
        [
          :nan,
          -0.45464871341284085,
          0.0,
          0.0,
          0.2397127693021015,
          0.45464871341284085,
          :nan,
          nil,
          :nan
        ]}},
      {:atanh,
       {[:nan, :nan, 0.0, 0.0, @atanh_of_half, :nan, :nan, nil, :nan],
        [-1.0, -0.9640275800758169, 0.0, 0.0, 0.46211715726000974, 0.9640275800758169, 1.0, :nan],
        [
          -0.0,
          -0.33333333333333331,
          1.0,
          1.0,
          1.3333333333333333,
          -0.33333333333333331,
          -0.0,
          nil,
          :nan
        ],
        [
          0.0,
          0.070650824853164471,
          1.0,
          1.0,
          0.78644773296592752,
          0.070650824853164471,
          0.0,
          nil,
          :nan
        ]}},
      {:logit,
       {[:nan, :nan, :neg_infinity, :neg_infinity, 0.0, :nan, :nan, nil, :nan],
        [0.0, 0.11920292202211755, 0.5, 0.5, 0.62245933120185459, 0.88079707797788231, 1.0, :nan],
        [:nan, :nan, :infinity, :infinity, 4.0, :nan, :nan, nil, :nan],
        [
          0.0,
          0.10499358540350651,
          0.25,
          0.25,
          0.23500371220159449,
          0.10499358540350651,
          0.0,
          nil,
          :nan
        ]}},
      {:probit,
       {[:nan, :nan, :neg_infinity, :neg_infinity, 0.0, :nan, :nan, nil, :nan],
        [
          0.0,
          @normal_below_minus_two,
          0.5,
          0.5,
          @normal_below_half,
          0.97724986805182079,
          1.0,
          :nan
        ], [:nan, :nan, :infinity, :infinity, 2.5066282746310002, :nan, :nan, nil, :nan],
        [
          0.0,
          0.053990966513188063,
          0.3989422804014327,
          0.3989422804014327,
          0.35206532676429952,
          0.053990966513188063,
          0.0,
          nil,
          :nan
        ]}},
      {{:probability, :normal, mean: 1, sd: 2},
       {[:nan, :nan, :neg_infinity, :neg_infinity, 1.0, :nan, :nan, nil, :nan],
        [
          0.0,
          0.066807201268858071,
          @normal_below_minus_half,
          @normal_below_minus_half,
          0.4012936743170763,
          @normal_below_half,
          1.0,
          :nan
        ], [:nan, :nan, :infinity, :infinity, 5.0132565492620005, :nan, :nan, nil, :nan],
        [
          0.0,
          0.064758797832945872,
          0.17603266338214976,
          0.17603266338214976,
          0.19333405840142462,
          0.17603266338214976,
          0.0,
          nil,
          :nan
        ]}},
      {{:probability, :logistic, location: 1, scale: 2},
       {[:nan, :nan, :neg_infinity, :neg_infinity, 1.0, :nan, :nan, nil, :nan],
        [
          0.0,
          0.18242552380635635,
          0.37754066879814541,
          0.37754066879814541,
          0.43782349911420193,
          0.62245933120185459,
          1.0,
          :nan
        ], [:nan, :nan, :infinity, :infinity, 8.0, :nan, :nan, nil, :nan],
        [
          0.0,
          0.074573226035166418,
          0.11750185610079725,
          0.11750185610079725,
          0.12306704136879916,
          0.11750185610079725,
          0.0,
          nil,
          :nan
        ]}}
    ]

    test "asn, atanh and the probabilities give R's" do
      inputs = Enum.reject(@doubles, &is_nil/1)

      for {name, expected} <- @r_proportions do
        assert {Transform.transform(name, @doubles), Transform.inverse(name, inputs),
                Transform.derivative(name, @doubles),
                Transform.inverse_derivative(name, @doubles)} === expected,
               inspect(name)
      end
    end

    # Golden: R's transform and d_transform of c(-1, 1, 1e-300, 1 - 2^-53) (`inc4/step4/golden.R`)
    @edges [-1.0, 1.0, 1.0e-300, 0.99999999999999989]
    test "at the domain's ends and near them, R's" do
      assert {Transform.transform(:asn, @edges), Transform.derivative(:asn, @edges)} ===
               {[:nan, 3.1415926535897931, 2.0e-150, 3.1415926237874707],
                [:nan, :infinity, 1.0e150, 94_906_265.624251544]}

      assert {Transform.transform(:atanh, @edges), Transform.derivative(:atanh, @edges)} ===
               {[:neg_infinity, :infinity, 1.0e-300, 18.714973875118524],
                [:infinity, :infinity, 1.0, 4_503_599_627_370_496.0]}

      assert {Transform.transform(:logit, @edges), Transform.derivative(:logit, @edges)} ===
               {[:nan, :infinity, -690.77552789821368, 36.736800569677101],
                [:nan, :infinity, r_double("9.9999999999997626e299"), 9_007_199_254_740_990.0]}

      logistic = {:probability, :logistic, location: 1, scale: 2}

      assert {Transform.transform(logistic, @edges), Transform.derivative(logistic, @edges)} ===
               {[:nan, :infinity, -1380.5510557964274, 74.473601139354201],
                [:nan, :infinity, r_double("1.9999999999999525e300"), 18_014_398_509_481_980.0]}

      assert Transform.transform(:probit, [-1.0, 1.0, 1.0e-300]) ===
               [:nan, :infinity, -37.047096299361201]

      assert Transform.derivative(:probit, [1.0e-300]) === [r_double("2.6973044650427405e298")]
    end

    # Golden: R's d_transform under "probit" at 1 - 2^-53, 1e-20 and 2.54596855398056e-293
    # (`inc4/step4/probe.R`, `golden.R`): 1 over the density at the quantile moves with the
    # quantile's last bit times about its square, 5.2e-13 at the last, where R's own is that far
    # off the truth and the package's 2.3e-15.
    test "the normal's derivative at its far tails is within its measured relative error of R's" do
      derivatives =
        Transform.derivative(:probit, [0.99999999999999989, 1.0e-20, 2.54596855398056e-293])

      expected =
        Enum.map(~w(1081559575103667.4 1.067472533301376e19 1.0728251456687658e291), &r_double/1)

      assert derivatives
             |> Enum.zip_with(expected, fn value, r_value -> abs(value - r_value) / r_value end)
             |> Enum.all?(fn error -> error < 6.0e-13 end)
    end

    test "a date, date-time or time transformation has no derivatives" do
      for name <- [:date, :time, {:datetime, "UTC", Calendar.UTCOnlyTimeZoneDatabase}] do
        assert_raise FunctionClauseError, fn -> Transform.derivative(name, [1.0]) end
        assert_raise FunctionClauseError, fn -> Transform.inverse_derivative(name, [1.0]) end
      end
    end
  end

  describe "trim_to_domain/2" do
    # Golden: R's `trim_to_domain()` of each (`inc4/step2/probe.R`, `trim.R`), a zero's sign read
    # as `1 / x`.
    test "the range squished into the domain, missing values and NaN left out, ends transformed" do
      values = [-5.0, 0.0, 10.0, 1000.0, nil]

      assert Enum.map(
               [:identity, :log10, :sqrt, :reverse, :reciprocal],
               fn name -> Transform.trim_to_domain(name, values) end
             ) ===
               [
                 {-5.0, 1000.0},
                 {-100.0, 3.0},
                 {0.0, 31.622776601683793},
                 {-1000.0, 5.0},
                 {-0.2, 0.001}
               ]

      assert Transform.trim_to_domain(:log10, [0.5, :nan, 2.0]) ===
               {-0.3010299956639812, 0.3010299956639812}
    end

    # Golden: R's trim_to_domain() of c(-5, 0, 10, 1000, NA), and of c(-5, 0, 10) in base 3 and
    # c(-3, -2) under log1p (`inc4/step3/extra.R`)
    test "step 3's domains: every logarithm's from 1e-100, log1p's from -1 + epsilon" do
      values = [-5.0, 0.0, 10.0, 1000.0, nil]

      assert Enum.map(
               [:log, :log2, :log1p, :exp, :asinh, :pseudo_log],
               fn name -> Transform.trim_to_domain(name, values) end
             ) ===
               [
                 {-230.25850929940458, 6.9077552789821368},
                 {-332.19280948873626, 9.965784284662087},
                 {-36.043653389117154, 6.9087547793152204},
                 {0.0067379469990854687, :infinity},
                 {-2.3124383412727525, 7.6009027095419883},
                 {-1.6472311463710958, 6.9077562789806368}
               ]

      assert {Transform.trim_to_domain({:log, 3}, [-5.0, 0.0, 10.0]),
              Transform.trim_to_domain(:log1p, [-3.0, -2.0])} ===
               {{-209.59032742893845, 2.0959032742893848},
                {-36.043653389117154, -36.043653389117154}}
    end

    # Golden: R's trim_to_domain() of c(-5, 0.3, 0.9, NA), c(0.2, 3) and c(-0.5, 0.25)
    # (`inc4/step4/golden.R`), but atanh's of -0.5, the platform's, a double nearer zero than
    # R's -0.54930614433405489.
    test "step 4's domains: asn's and the probabilities' 0 to 1, atanh's -1 to 1" do
      ranges = [[-5.0, 0.3, 0.9, nil], [0.2, 3.0], [-0.5, 0.25]]

      assert Enum.map([:asn, :atanh, :logit], fn name ->
               Enum.map(ranges, fn values -> Transform.trim_to_domain(name, values) end)
             end) ===
               [
                 [
                   {0.0, 2.4980915447965089},
                   {0.92729521800161219, 3.1415926535897931},
                   {0.0, 1.0471975511965979}
                 ],
                 [
                   {:neg_infinity, 1.4722194895832204},
                   {0.20273255405408219, :infinity},
                   {-0.5493061443340548, 0.25541281188299536}
                 ],
                 [
                   {:neg_infinity, 2.1972245773362196},
                   {-1.3862943611198906, :infinity},
                   {:neg_infinity, -1.0986122886681098}
                 ]
               ]
    end

    test "values all below the domain are its end" do
      assert {Transform.trim_to_domain(:log10, [-3.0, -1.0]),
              Transform.trim_to_domain(:sqrt, [-3.0, -1.0])} === {{-100.0, -100.0}, {0.0, 0.0}}
    end

    test "an infinity is kept, not squished, and one outside the domain makes both ends NaN" do
      assert {Transform.trim_to_domain(:log10, [:infinity, 3.0, -2.0]),
              Transform.trim_to_domain(:reverse, [:neg_infinity, 5.0]),
              Transform.trim_to_domain(:log10, [:neg_infinity, 5.0]),
              Transform.trim_to_domain(:sqrt, [:neg_infinity, :infinity])} ===
               {{-100.0, :infinity}, {-5.0, :infinity}, {:nan, :nan}, {:nan, :nan}}
    end

    test "the ends come out sorted, a reversal's and a reciprocal's included" do
      assert {Transform.trim_to_domain(:reverse, [-3.0, -1.0]),
              Transform.trim_to_domain(:reciprocal, [-3.0, -1.0])} ===
               {{1.0, 3.0}, {-1.0, -0.33333333333333331}}
    end

    # R's range() of -0 and 0 is the first twice, as min() and max() keep the first of equals,
    # so reciprocal of (-0, 0) is -Inf twice; reciprocal of (-0, 4) is -Inf to 0.25, of
    # (-Inf, Inf) -0 twice.
    test "of two equal ends, the first is both, so a zero's sign is the first's" do
      assert {Transform.trim_to_domain(:identity, [-0.0, 0.0]),
              Transform.trim_to_domain(:identity, [0.0, -0.0]),
              Transform.trim_to_domain(:reverse, [0.0, 0.0]),
              Transform.trim_to_domain(:reciprocal, [-0.0, 0.0]),
              Transform.trim_to_domain(:reciprocal, [-0.0, 4.0]),
              Transform.trim_to_domain(:reciprocal, [:neg_infinity, :infinity])} ===
               {{-0.0, -0.0}, {0.0, 0.0}, {-0.0, -0.0}, {:neg_infinity, :neg_infinity},
                {:neg_infinity, 0.25}, {-0.0, -0.0}}
    end

    # R warns at a range of nothing and gives the transformed Inf and -Inf.
    test "no value to range over is :none" do
      assert {Transform.trim_to_domain(:identity, []),
              Transform.trim_to_domain(:log10, [nil, :nan])} === {:none, :none}
    end

    test "a date, date-time or time transformation takes none" do
      for name <- [:date, :time, {:datetime, "UTC", Calendar.UTCOnlyTimeZoneDatabase}] do
        assert_raise FunctionClauseError, fn -> Transform.trim_to_domain(name, [1.0]) end
      end
    end
  end

  describe "datetime" do
    @utc {:datetime, "Etc/UTC", Calendar.UTCOnlyTimeZoneDatabase}
    @naive {:datetime, :naive, Calendar.UTCOnlyTimeZoneDatabase}
    @new_york {:datetime, "America/New_York", Tz.TimeZoneDatabase}

    # ggplot(u, aes(at, y)) + geom_point(), `at` 2024-03-09 20:17 and 2024-03-10 08:40 UTC: its
    # breaks every three hours, labelled by the time alone, and its minor breaks midway, less the
    # breaks
    test "marks R's pretty() breaks for date-times, labelled by their step, and minor breaks" do
      extent = {1_710_013_191.0, 1_710_062_229.0}

      assert axis(@utc, extent) ===
               {[
                  {1_710_018_000.0, "21:00"},
                  {1_710_028_800.0, "00:00"},
                  {1_710_039_600.0, "03:00"},
                  {1_710_050_400.0, "06:00"},
                  {1_710_061_200.0, "09:00"}
                ],
                [
                  1_710_023_400.0,
                  1_710_034_200.0,
                  1_710_045_000.0,
                  1_710_055_800.0
                ]}

      assert axis(@naive, extent) == axis(@utc, extent)
    end

    # one point at 2024-03-10 08:40:12 UTC: the axis 0.05 seconds either side, R's pretty()
    # widening it to whole seconds, and the one break inside labelled by its second
    test "a single date-time's axis has the one break, labelled by its second" do
      assert axis(@utc, {1_710_060_011.95, 1_710_060_012.05}) ==
               {[{1_710_060_012.0, "12"}], []}
    end

    # scale_x_datetime(breaks = ...) on the axis above: R's format() writes the date alone where
    # every break is a midnight, else the date and the time to the second, a fraction of a second
    # dropped; and a width of five hours, its breaks inside the axis written alike
    test "breaks it did not choose are written as R's format() writes them" do
      extent = {1_710_013_191.0, 1_710_062_229.0}

      width =
        @utc
        |> Transform.width([hour: 5], extent)
        |> inside(extent)

      assert {Transform.format(@utc, [1_710_028_800.0, 1_710_052_200.0], :given),
              Transform.format(@utc, [1_710_028_800.0], :given),
              Transform.format(@utc, [1_710_028_800.25, 1_710_050_400.0], :given), width,
              Transform.format(@utc, width, :given)} ==
               {["2024-03-10 00:00:00", "2024-03-10 06:30:00"], ["2024-03-10"],
                ["2024-03-10 00:00:00", "2024-03-10 06:00:00"],
                [1_710_028_800.0, 1_710_046_800.0],
                ["2024-03-10 00:00:00", "2024-03-10 05:00:00"]}
    end

    # ggplot(d, aes(at, y)) + geom_point() + scale_x_datetime(breaks = b), `at` 2024-03-09 15:17
    # and 2024-03-11 04:40 in New York and `b` its midnights on 10 and 11 March: R writes the dates
    # alone, each a midnight on the zone's clock, though neither is one in UTC
    test "breaks it did not choose are written on the clock of the scale's zone" do
      assert Transform.format(@new_york, [1_710_046_800.0, 1_710_129_600.0], :given) ==
               ["2024-03-10", "2024-03-11"]
    end

    # as.POSIXct(1710060012.123456, tz = "UTC"), as R parses it, is 1710060012.123456: a
    # microsecond is kept, the double nearest the instant
    test "places a date-time at its seconds since 1970, a naive one alike, a missing one nowhere" do
      assert Transform.transform(@utc, [~U[2024-03-10 08:40:12.123456Z], nil]) ===
               [1_710_060_012.123456, nil]

      assert Transform.transform(@naive, [~N[2024-03-10 08:40:12.123456]]) ===
               [1_710_060_012.123456]

      assert Transform.inverse(@utc, [1_710_060_012.123456, 1_710_060_012.0]) ===
               [~U[2024-03-10 08:40:12.123456Z], ~U[2024-03-10 08:40:12Z]]

      assert Transform.inverse(@naive, [1_710_060_012.0]) === [~N[2024-03-10 08:40:12]]

      assert Transform.inverse(@new_york, [1_710_046_800.0, 1_710_090_000.5]) === [
               new_york(~N[2024-03-10 00:00:00]),
               new_york(~N[2024-03-10 13:00:00.500000])
             ]
    end

    # A transformation whose zone no column has settled lays and writes its breaks as R's
    # date-time scale given no zone does, in UTC.
    test "a zone no column has settled draws its axis as one in UTC" do
      unsettled = {:datetime, :default, Calendar.UTCOnlyTimeZoneDatabase}
      extent = {1_710_013_191.0, 1_710_062_229.0}

      assert axis(unsettled, extent) === axis(@utc, extent)

      assert Transform.inverse(unsettled, [1_710_060_012.0]) === [~U[2024-03-10 08:40:12Z]]
    end

    # A transformation whose zone no column has settled takes naive date-times, as a scale's
    # limits may be, as well as date-times in a zone.
    test "a zone no column has settled places a date-time of either kind" do
      unsettled = {:datetime, :default, Calendar.UTCOnlyTimeZoneDatabase}

      assert Transform.transform(unsettled, [~N[2024-03-10 08:40:12], ~U[2024-03-10 08:40:12Z]]) ===
               [1_710_060_012.0, 1_710_060_012.0]
    end

    test "a transformation of one kind refuses a date-time of the other" do
      naive =
        assert_raise ArgumentError, fn ->
          Transform.transform(@naive, [~U[2024-03-10 08:40:12Z]])
        end

      zoned =
        assert_raise ArgumentError, fn ->
          Transform.transform(@utc, [~N[2024-03-10 08:40:12]])
        end

      assert naive.message =~ "a scale of naive date-times cannot place ~U[2024-03-10 08:40:12Z]"
      assert zoned.message =~ ~s(in "Etc/UTC" cannot place ~N[2024-03-10 08:40:12])
    end
  end

  describe "time" do
    # R's own axes, from the image `giggly-r:ggplot2-4.0.3-hms` (hms 1.1.4): `ggplot_build()`'s
    # panel params for ggplot(d, aes(t, y)) + geom_point() over `t`, the times in each test's name,
    # and `scales:::breaks_hms()` on the extents given. R writes its labels with hms's `format()`,
    # which pads every label with spaces to the widest and gives each six zero decimals where one
    # break is a rounding error off a whole second; the package leaves both out (design-log §4,
    # the entry beginning "A time of day's labels").

    test "10:00:00 and 10:01:00: breaks every 20 seconds, found in seconds" do
      assert axis(:time, {35_997.0, 36_063.0}) ===
               {[
                  {36_000.0, "10:00:00"},
                  {36_020.0, "10:00:20"},
                  {36_040.0, "10:00:40"},
                  {36_060.0, "10:01:00"}
                ], [36_010.0, 36_030.0, 36_050.0]}
    end

    test "22:10:00 and 23:50:00: breaks every half hour, found in minutes" do
      assert axis(:time, {79_500.0, 86_100.0}) ===
               {[{81_000.0, "22:30:00"}, {82_800.0, "23:00:00"}, {84_600.0, "23:30:00"}],
                [80_100.0, 81_900.0, 83_700.0, 85_500.0]}
    end

    test "00:00:00 and 23:59:59: breaks every ten hours, found in hours, minor ones past midnight" do
      assert axis(:time, {-4319.95, 90_718.95}) ===
               {[{0.0, "00:00:00"}, {36_000.0, "10:00:00"}, {72_000.0, "20:00:00"}],
                [18_000.0, 54_000.0, 90_000.0]}
    end

    # R writes every label here with six zero decimals, `10:24:00.000000`: its breaks are 24
    # minutes apart, a rounding error off their whole seconds (36000.000000000007)
    test "09:51:00 and 11:52:30: breaks a rounding error off whole seconds are written without it" do
      assert axis(:time, {35_095.5, 43_114.5}) ===
               {[
                  {36_000.000000000007, "10:00:00"},
                  {37_440.000000000007, "10:24:00"},
                  {38_880.0, "10:48:00"},
                  {40_320.000000000007, "11:12:00"},
                  {41_760.000000000007, "11:36:00"}
                ],
                [
                  35_280.000000000007,
                  36_720.000000000007,
                  38_160.0,
                  39_600.0,
                  41_040.000000000007,
                  42_480.000000000007
                ]}
    end

    test "12:00:00 alone: the axis 0.05 seconds either side, labelled to the hundredth" do
      assert axis(:time, {43_199.95, 43_200.05}) ===
               {[
                  {43_199.950000000004, "11:59:59.95"},
                  {43_199.97, "11:59:59.97"},
                  {43_199.990000000005, "11:59:59.99"},
                  {43_200.01, "12:00:00.01"},
                  {43_200.030000000006, "12:00:00.03"},
                  {43_200.05, "12:00:00.05"}
                ],
                [
                  43_199.960000000006,
                  43_199.98,
                  43_200.0,
                  43_200.020000000004,
                  43_200.04000000001
                ]}
    end

    # The breaks themselves are `Breaks.timespan/2`'s, whose test pins R's at each unit's switch:
    # here, the extent's seconds, five wanted.
    test "breaks are breaks_timespan()'s on the extent's seconds" do
      for extent <- [{36_000.0, 36_120.001}, {36_000.0, 43_200.0}] do
        assert Transform.breaks(:time, extent) == Breaks.timespan(extent, unit: :second, n: 5)
      end
    end

    # extents only a wide expand: reaches, labelled with hours past 99 unpadded, where R writes
    # " 00:00:00" and " 96:00:00"
    test "breaks are found in hours up to two days, in days up to two weeks, in weeks beyond" do
      hours = {-8640.0, 164_160.0}
      days = {-8640.05, 164_160.95}
      weeks = {-60_480.05, 1_149_120.95}

      assert Enum.map([hours, days, weeks], fn extent -> time_breaks(extent) end) == [
               {[0.0, 36_000.0, 72_000.0, 108_000.0, 144_000.0],
                ~w(00:00:00 10:00:00 20:00:00 30:00:00 40:00:00)},
               {[0.0, 34_560.0, 69_120.0, 103_680.00000000001, 138_240.0],
                ~w(00:00:00 09:36:00 19:12:00 28:48:00 38:24:00)},
               {[0.0, 241_920.0, 483_840.0, 725_760.0000000001, 967_680.0],
                ~w(00:00:00 67:12:00 134:24:00 201:36:00 268:48:00)}
             ]

      assert time_breaks({-60_480.0, 1_149_120.0}) ==
               {[0.0, 345_600.0, 691_200.0, 1_036_800.0],
                ~w(00:00:00 96:00:00 192:00:00 288:00:00)}
    end

    test "a break past midnight counts on its hours, one before it is negative, neither padded" do
      assert time_breaks({86_000.0, 87_000.0}) ==
               {[86_040.0, 86_280.0, 86_520.0, 86_760.0, 87_000.0],
                ~w(23:54:00 23:58:00 24:02:00 24:06:00 24:10:00)}

      assert time_breaks({-600.0, 300.0}) ==
               {[-480.0, -240.0, 0.0, 240.0], ~w(-00:08:00 -00:04:00 00:00:00 00:04:00)}
    end

    test "every label takes as many decimals of a second as the most precise break needs" do
      assert time_breaks({10.0, 10.25}) ==
               {[10.0, 10.04, 10.08, 10.12, 10.16, 10.2, 10.24],
                ~w(00:00:10.00 00:00:10.04 00:00:10.08 00:00:10.12 00:00:10.16 00:00:10.20
                   00:00:10.24)}

      assert time_breaks({10.0001, 10.0002}) ==
               {[
                  10.000100000000002,
                  10.000120000000001,
                  10.000140000000002,
                  10.000160000000001,
                  10.000180000000002
                ], ~w(00:00:10.00010 00:00:10.00012 00:00:10.00014 00:00:10.00016 00:00:10.00018)}
    end

    # data a few microseconds apart, from R's random extents: breaks on half a microsecond, which R
    # rounds to the even one, up from an odd one and down from an even, and breaks a rounding error
    # below a whole microsecond, odd or even, and above one
    test "a break is rounded to the microsecond, half to even" do
      assert Enum.map(
               [
                 {8514.789661449999, 8514.78967355},
                 {84_162.636042950006, 84_162.636044049999},
                 {79_034.876414900005, 79_034.876417100008}
               ],
               fn extent ->
                 {_breaks, labels} = time_breaks(extent)
                 labels
               end
             ) == [
               ~w(02:21:54.789662 02:21:54.789664 02:21:54.789668 02:21:54.789670 02:21:54.789674),
               ~w(23:22:42.636043 23:22:42.636044 23:22:42.636044),
               ~w(21:57:14.876415 21:57:14.876416 21:57:14.876417)
             ]
    end

    test "no breaks have no labels" do
      assert Transform.format(:time, [], {0.0, 1.0}) === []
    end

    test "a break a microsecond before midnight is written negative" do
      assert time_breaks({-0.0000015, 0.0000025}) ==
               {[-9.9999999999999995e-07, 0.0, 9.9999999999999995e-07, 2.0000000000000003e-06],
                ~w(-00:00:00.000001 00:00:00.000000 00:00:00.000001 00:00:00.000002)}
    end

    # scale_x_time(breaks = as_hms(c("06:00:00", "12:00:00", "18:30:00"))) over 00:00:00 and
    # 23:59:59: written as R writes its own, minor breaks midway between them
    test "breaks it did not choose are written alike, minor breaks midway between them" do
      extent = {-4319.95, 90_718.95}
      given = [21_600.0, 43_200.0, 66_600.0]

      minor =
        :time
        |> Transform.minor_breaks(given, extent)
        |> inside(extent)
        |> Enum.reject(fn position -> position in given end)

      assert {Transform.format(:time, given, :given), minor} ===
               {["06:00:00", "12:00:00", "18:30:00"],
                [0.0, 10_800.0, 32_400.0, 54_900.0, 77_400.0, 88_200.0]}
    end

    # scales::breaks_width(...)(as_hms(c(low, high))): every multiple of the step from the start
    # rounded down to one to the end rounded up
    test "a width lays every multiple of its step from the extent's start rounded down" do
      assert Transform.width(:time, [hour: 1], {82_000.0, 85_000.0}) ==
               [79_200.0, 82_800.0, 86_400.0]

      assert Transform.width(:time, [minute: 7], {150.0, 3450.0}) ==
               [0.0, 420.0, 840.0, 1260.0, 1680.0, 2100.0, 2520.0, 2940.0, 3360.0, 3780.0]

      assert Transform.width(:time, [second: 10], {-16.5, 46.5}) ==
               [-20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 40.0, 50.0]

      assert Transform.width(:time, [second: 1], {0.5, 2.5}) == [0.0, 1.0, 2.0, 3.0]
    end

    test "places a time at its seconds since midnight, a missing one nowhere" do
      assert Transform.transform(:time, [~T[23:50:00.5], ~T[10:00:00.123456], nil]) ===
               [85_800.5, 36_000.123456, nil]
    end

    # scales::label_time("%H:%M:%OS3")(as_hms(-0.25)), as date_labels: writes it: 23:59:59.750
    test "turns a position back into the time of day, wrapped past midnight" do
      assert Transform.inverse(:time, [86_400.0, -1.0, 36_000.25, 43_200.0, -0.25]) ===
               [
                 ~T[00:00:00],
                 ~T[23:59:59],
                 ~T[10:00:00.250000],
                 ~T[12:00:00],
                 ~T[23:59:59.750000]
               ]
    end
  end

  describe "breaks wanted" do
    # Golden: R 4.6.1's scales 1.4.0, each transformation's `breaks(inverse(extent), n = 3)` put
    # back through it, as ggplot2's `get_breaks()` asks it for `n.breaks`.
    test "the identity, square root, reverse and reciprocal find that many extended breaks" do
      counted =
        Enum.map(
          [
            identity: {1.0, 10.0},
            sqrt: {1.0, 10.0},
            reverse: {-10.0, -1.0},
            reciprocal: {0.1, 1.0}
          ],
          fn {name, extent} -> {name, Transform.breaks(name, extent, n: 3)} end
        )

      assert counted === [
               identity: [0.0, 5.0, 10.0],
               sqrt: [0.0, 7.0710678118654755, 10.0],
               reverse: [-0.0, -5.0, -10.0],
               reciprocal: [:infinity, 0.2, 0.1]
             ]
    end

    # Golden: R 4.6.1's scales 1.4.0: `log10(transform_log10()$breaks(c(1, 1000), n = 10))`;
    # `transform_date()$breaks()` of 2020-01-01 12:00 to 2022-01-01 12:00 with `n = 20` and
    # without, and `transform_time("UTC")$breaks()` of 2020-01-01 00:00 to 09:00 with `n = 3`, each
    # break's label its name, which ggplot2's labels take.
    test "log10, dates and date-times find about that many of their own breaks, so labelled" do
      utc = {:datetime, "Etc/UTC", Calendar.UTCOnlyTimeZoneDatabase}
      days = {18_262.5, 18_993.5}
      hours = {1_577_836_800.0, 1_577_869_200.0}
      monthly = Transform.breaks(:date, days, n: 20)
      three_hourly = Transform.breaks(utc, hours, n: 3)
      monthly_labels = Transform.format(:date, monthly, days, n: 20)

      assert {Transform.breaks(:log10, {0.0, 3.0}, n: 10), Enum.count(monthly),
              Enum.take(monthly_labels, 3),
              Transform.format(:date, Transform.breaks(:date, days), days), three_hourly,
              Transform.format(utc, three_hourly, hours, n: 3)} ===
               {[
                  0.0,
                  0.47712125471966244,
                  0.6989700043360189,
                  1.0,
                  1.4771212547196624,
                  1.6989700043360187,
                  2.0,
                  2.4771212547196626,
                  2.6989700043360187,
                  3.0,
                  3.4771212547196626
                ], 26, ["Jan 2020", "Feb 2020", "Mar 2020"],
                ["2020-01", "2020-07", "2021-01", "2021-07", "2022-01", "2022-07"],
                [1_577_836_800.0, 1_577_847_600.0, 1_577_858_400.0, 1_577_869_200.0],
                ["00:00", "03:00", "06:00", "09:00"]}
    end

    # R's `transform_hms()$breaks(c(0, 3600), n = 10)` fails: "unused argument (n = 10)".
    test "time counts no breaks, as R's takes no number, for breaks or their labels" do
      breaks = assert_raise(ArgumentError, fn -> Transform.breaks(:time, {0.0, 3.0}, n: 3) end)

      labels =
        assert_raise(ArgumentError, fn -> Transform.format(:time, [0.0], {0.0, 3.0}, n: 3) end)

      assert {String.starts_with?(breaks.message, "the :time transformation"),
              breaks.message =~ "[:n]", breaks.message =~ "Scales.Breaks.timespan/2",
              labels.message == breaks.message, Transform.format(:time, [0.0], {0.0, 3.0}, [])} ==
               {true, true, true, true, ["00:00:00"]}
    end

    test "a number wanted is a whole number, one below a breaks function's least refused there" do
      negative =
        assert_raise NimbleOptions.ValidationError, fn ->
          Transform.breaks(:date, {0.0, 10.0}, n: -1)
        end

      extended =
        assert_raise NimbleOptions.ValidationError, fn ->
          Transform.breaks(:identity, {0.0, 1.0}, n: 1)
        end

      log =
        assert_raise NimbleOptions.ValidationError, fn ->
          Transform.breaks(:log10, {0.0, 1.0}, n: 0)
        end

      option_error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Transform.breaks(:identity, {0.0, 1.0}, nice_numbers: [1])
        end

      assert {negative.message =~ "non negative integer", extended.message =~ "2 or more, got: 1",
              log.message =~ "positive integer", option_error.message =~ "nice_numbers"} ==
               {true, true, true, true}
    end
  end

  describe "a composition" do
    # Golden: R 4.6.1's (scales 1.4.0) transform, inverse, d_transform and d_inverse of
    # `transform_compose()` of each list of parts at the nine doubles and eleven edges
    # (`inc4/step6/golden.R`), a span of time's without derivatives, as R's has none. The
    # pseudo-logarithm's and log1p's compositions are left out: their parts' last bits, pinned
    # with those parts, are all they differ by.
    defp edges do
      [
        :neg_infinity,
        -2.0,
        -0.0,
        0.0,
        0.5,
        2.0,
        :infinity,
        nil,
        :nan,
        -1.0,
        1.0,
        -0.5,
        1.0e-300,
        -1.0e-300,
        9.9999999999999995e-21,
        r_double("1.0000000000000001e300"),
        r_double("-1.0000000000000001e300"),
        -3.0,
        3.0,
        0.10000000000000001
      ]
    end

    defp composed do
      [
        {[:log10, :reverse],
         {[
            :nan,
            :nan,
            :infinity,
            :infinity,
            0.3010299956639812,
            -0.3010299956639812,
            :neg_infinity,
            nil,
            :nan,
            :nan,
            -0.0,
            :nan,
            300.0,
            :nan,
            20.0,
            -300.0,
            :nan,
            :nan,
            -0.47712125471966244,
            1.0
          ],
          [
            :infinity,
            100.0,
            1.0,
            1.0,
            0.31622776601683794,
            0.01,
            0.0,
            nil,
            :nan,
            10.0,
            0.10000000000000001,
            3.1622776601683795,
            1.0,
            1.0,
            1.0,
            0.0,
            :infinity,
            1000.0,
            0.001,
            0.79432823472428149
          ],
          [
            0.0,
            0.21714724095162588,
            :infinity,
            :neg_infinity,
            -0.86858896380650352,
            -0.21714724095162588,
            -0.0,
            nil,
            :nan,
            0.43429448190325176,
            -0.43429448190325176,
            0.86858896380650352,
            r_double("-4.3429448190325174e299"),
            r_double("4.3429448190325174e299"),
            r_double("-4.3429448190325178e19"),
            -4.3429448190325176e-301,
            4.3429448190325176e-301,
            0.14476482730108392,
            -0.14476482730108392,
            -4.3429448190325175
          ],
          [
            :neg_infinity,
            -230.25850929940458,
            -2.3025850929940459,
            -2.3025850929940459,
            -0.72814134002118014,
            -0.023025850929940458,
            -0.0,
            nil,
            :nan,
            -23.025850929940461,
            -0.23025850929940461,
            -7.2814134002118021,
            -2.3025850929940459,
            -2.3025850929940459,
            -2.3025850929940459,
            -0.0,
            :neg_infinity,
            -2302.5850929940457,
            -0.0023025850929940458,
            -1.8290083522204059
          ]}},
        {[:reverse, :log10],
         {[
            :infinity,
            0.3010299956639812,
            :neg_infinity,
            :neg_infinity,
            :nan,
            :nan,
            :nan,
            nil,
            :nan,
            0.0,
            :nan,
            -0.3010299956639812,
            :nan,
            -300.0,
            :nan,
            :nan,
            300.0,
            0.47712125471966244,
            :nan,
            :nan
          ],
          [
            -0.0,
            -0.01,
            -1.0,
            -1.0,
            -3.1622776601683795,
            -100.0,
            :neg_infinity,
            nil,
            :nan,
            -0.10000000000000001,
            -10.0,
            -0.31622776601683794,
            -1.0,
            -1.0,
            -1.0,
            :neg_infinity,
            -0.0,
            -0.001,
            -1000.0,
            -1.2589254117941673
          ],
          [
            -0.0,
            -0.21714724095162588,
            :neg_infinity,
            :infinity,
            0.86858896380650352,
            0.21714724095162588,
            0.0,
            nil,
            :nan,
            -0.43429448190325176,
            0.43429448190325176,
            -0.86858896380650352,
            r_double("4.3429448190325174e299"),
            r_double("-4.3429448190325174e299"),
            r_double("4.3429448190325178e19"),
            4.3429448190325176e-301,
            -4.3429448190325176e-301,
            -0.14476482730108392,
            0.14476482730108392,
            4.3429448190325175
          ],
          [
            -0.0,
            -0.023025850929940458,
            -2.3025850929940459,
            -2.3025850929940459,
            -7.2814134002118021,
            -230.25850929940458,
            :neg_infinity,
            nil,
            :nan,
            -0.23025850929940461,
            -23.025850929940461,
            -0.72814134002118014,
            -2.3025850929940459,
            -2.3025850929940459,
            -2.3025850929940459,
            :neg_infinity,
            -0.0,
            -0.0023025850929940458,
            -2302.5850929940457,
            -2.89878288638864
          ]}},
        {[:sqrt, :log10],
         {[
            :nan,
            :nan,
            :neg_infinity,
            :neg_infinity,
            -0.15051499783199057,
            0.1505149978319906,
            :infinity,
            nil,
            :nan,
            :nan,
            0.0,
            :nan,
            -150.0,
            :nan,
            -10.0,
            150.0,
            :nan,
            :nan,
            0.23856062735983119,
            -0.5
          ],
          [
            0.0,
            0.0001,
            1.0,
            1.0,
            10.000000000000002,
            10_000.0,
            :infinity,
            nil,
            nil,
            0.010000000000000002,
            100.0,
            0.10000000000000001,
            1.0,
            1.0,
            1.0,
            :infinity,
            0.0,
            9.9999999999999995e-07,
            1_000_000.0,
            1.5848931924611136
          ],
          [
            :nan,
            :nan,
            :infinity,
            :infinity,
            0.43429448190325171,
            0.10857362047581293,
            0.0,
            nil,
            :nan,
            :nan,
            0.21714724095162588,
            :nan,
            r_double("2.1714724095162591e299"),
            :nan,
            r_double("2.1714724095162589e19"),
            2.1714724095162588e-301,
            :nan,
            :nan,
            0.072382413650541988,
            2.1714724095162583
          ],
          [
            0.0,
            0.0004605170185988092,
            4.6051701859880918,
            4.6051701859880918,
            46.051701859880922,
            46_051.701859880915,
            :infinity,
            nil,
            :nan,
            0.046051701859880924,
            460.51701859880922,
            0.46051701859880917,
            4.6051701859880918,
            4.6051701859880918,
            4.6051701859880918,
            :infinity,
            0.0,
            4.605170185988092e-06,
            4_605_170.1859880909,
            7.2987028778974068
          ]}},
        {[:log10, :sqrt],
         {[
            :nan,
            :nan,
            :nan,
            :nan,
            :nan,
            0.54866200493927153,
            :infinity,
            nil,
            :nan,
            :nan,
            0.0,
            :nan,
            :nan,
            :nan,
            :nan,
            17.320508075688775,
            :nan,
            :nan,
            0.6907396432228734,
            :nan
          ],
          [
            nil,
            nil,
            1.0,
            1.0,
            1.7782794100389228,
            10_000.0,
            :infinity,
            nil,
            nil,
            nil,
            10.0,
            nil,
            1.0,
            nil,
            1.0,
            :infinity,
            nil,
            nil,
            1_000_000_000.0,
            1.0232929922807541
          ],
          [
            :nan,
            :nan,
            :nan,
            :nan,
            :nan,
            0.1978879884125207,
            0.0,
            nil,
            :nan,
            :nan,
            :infinity,
            :nan,
            :nan,
            :nan,
            :nan,
            1.2537001801720571e-302,
            :nan,
            :nan,
            0.10478971977461431,
            :nan
          ],
          [
            nil,
            nil,
            -0.0,
            0.0,
            4.0946396607338702,
            92_103.403719761831,
            :infinity,
            nil,
            nil,
            nil,
            46.051701859880922,
            nil,
            4.6051701859880919e-300,
            nil,
            4.6051701859880915e-20,
            :infinity,
            nil,
            nil,
            13_815_510_557.964275,
            0.47124383795818714
          ]}},
        {[:sqrt, :reverse],
         {[
            :nan,
            :nan,
            0.0,
            -0.0,
            -0.70710678118654757,
            -1.4142135623730951,
            :neg_infinity,
            nil,
            :nan,
            :nan,
            -1.0,
            :nan,
            -1.0e-150,
            :nan,
            -1.0e-10,
            r_double("-9.9999999999999998e149"),
            :nan,
            :nan,
            -1.7320508075688772,
            -0.31622776601683794
          ],
          [
            :infinity,
            4.0,
            0.0,
            0.0,
            nil,
            nil,
            nil,
            nil,
            nil,
            1.0,
            nil,
            0.25,
            nil,
            0.0,
            nil,
            nil,
            :infinity,
            9.0,
            nil,
            nil
          ],
          [
            :nan,
            :nan,
            :infinity,
            :neg_infinity,
            -0.70710678118654746,
            -0.35355339059327373,
            -0.0,
            nil,
            :nan,
            :nan,
            -0.5,
            :nan,
            r_double("-4.9999999999999999e149"),
            :nan,
            -5_000_000_000.0,
            -5.0e-151,
            :nan,
            :nan,
            -0.28867513459481292,
            -1.5811388300841895
          ],
          [
            :neg_infinity,
            -4.0,
            -0.0,
            0.0,
            1.0,
            4.0,
            :infinity,
            nil,
            :nan,
            -2.0,
            2.0,
            -1.0,
            2.0000000000000001e-300,
            -2.0000000000000001e-300,
            1.9999999999999999e-20,
            r_double("2.0000000000000001e300"),
            r_double("-2.0000000000000001e300"),
            -6.0,
            6.0,
            0.20000000000000001
          ]}},
        {[:exp, :log],
         {[
            :neg_infinity,
            -2.0,
            0.0,
            0.0,
            0.5,
            2.0,
            :infinity,
            nil,
            :nan,
            -1.0,
            1.0,
            -0.5,
            0.0,
            0.0,
            0.0,
            :infinity,
            :neg_infinity,
            -3.0,
            3.0,
            0.10000000000000007
          ],
          [
            :neg_infinity,
            -2.0,
            0.0,
            0.0,
            0.5,
            2.0,
            :infinity,
            nil,
            :nan,
            -1.0,
            1.0,
            -0.5,
            0.0,
            0.0,
            0.0,
            :infinity,
            :neg_infinity,
            -3.0,
            3.0,
            0.10000000000000007
          ],
          [
            :nan,
            1.0,
            1.0,
            1.0,
            1.0,
            1.0,
            :nan,
            nil,
            :nan,
            1.0,
            1.0,
            1.0,
            1.0,
            1.0,
            1.0,
            :nan,
            :nan,
            1.0,
            1.0,
            1.0
          ],
          [
            :nan,
            1.0,
            1.0,
            1.0,
            1.0,
            1.0,
            :nan,
            nil,
            :nan,
            1.0,
            1.0,
            1.0,
            1.0,
            1.0,
            1.0,
            :nan,
            :nan,
            1.0,
            1.0,
            1.0
          ]}},
        {[:reciprocal, :reverse],
         {[
            0.0,
            0.5,
            :infinity,
            :neg_infinity,
            -2.0,
            -0.5,
            -0.0,
            nil,
            :nan,
            1.0,
            -1.0,
            2.0,
            r_double("-9.999999999999999e299"),
            r_double("9.999999999999999e299"),
            -1.0e20,
            -1.0e-300,
            1.0e-300,
            0.33333333333333331,
            -0.33333333333333331,
            -10.0
          ],
          [
            0.0,
            0.5,
            :infinity,
            :neg_infinity,
            -2.0,
            -0.5,
            -0.0,
            nil,
            :nan,
            1.0,
            -1.0,
            2.0,
            r_double("-9.999999999999999e299"),
            r_double("9.999999999999999e299"),
            -1.0e20,
            -1.0e-300,
            1.0e-300,
            0.33333333333333331,
            -0.33333333333333331,
            -10.0
          ],
          [
            0.0,
            0.25,
            :infinity,
            :infinity,
            4.0,
            0.25,
            0.0,
            nil,
            :nan,
            1.0,
            1.0,
            4.0,
            :infinity,
            :infinity,
            1.0e40,
            0.0,
            0.0,
            0.1111111111111111,
            0.1111111111111111,
            99.999999999999986
          ],
          [
            0.0,
            0.25,
            :infinity,
            :infinity,
            4.0,
            0.25,
            0.0,
            nil,
            :nan,
            1.0,
            1.0,
            4.0,
            :infinity,
            :infinity,
            1.0e40,
            0.0,
            0.0,
            0.1111111111111111,
            0.1111111111111111,
            99.999999999999986
          ]}},
        {[:log10],
         {[
            :nan,
            :nan,
            :neg_infinity,
            :neg_infinity,
            -0.3010299956639812,
            0.3010299956639812,
            :infinity,
            nil,
            :nan,
            :nan,
            0.0,
            :nan,
            -300.0,
            :nan,
            -20.0,
            300.0,
            :nan,
            :nan,
            0.47712125471966244,
            -1.0
          ],
          [
            0.0,
            0.01,
            1.0,
            1.0,
            3.1622776601683795,
            100.0,
            :infinity,
            nil,
            :nan,
            0.10000000000000001,
            10.0,
            0.31622776601683794,
            1.0,
            1.0,
            1.0,
            :infinity,
            0.0,
            0.001,
            1000.0,
            1.2589254117941673
          ],
          [
            -0.0,
            -0.21714724095162588,
            :neg_infinity,
            :infinity,
            0.86858896380650352,
            0.21714724095162588,
            0.0,
            nil,
            :nan,
            -0.43429448190325176,
            0.43429448190325176,
            -0.86858896380650352,
            r_double("4.3429448190325174e299"),
            r_double("-4.3429448190325174e299"),
            r_double("4.3429448190325178e19"),
            4.3429448190325176e-301,
            -4.3429448190325176e-301,
            -0.14476482730108392,
            0.14476482730108392,
            4.3429448190325175
          ],
          [
            0.0,
            0.023025850929940458,
            2.3025850929940459,
            2.3025850929940459,
            7.2814134002118021,
            230.25850929940458,
            :infinity,
            nil,
            :nan,
            0.23025850929940461,
            23.025850929940461,
            0.72814134002118014,
            2.3025850929940459,
            2.3025850929940459,
            2.3025850929940459,
            :infinity,
            0.0,
            0.0023025850929940458,
            2302.5850929940457,
            2.89878288638864
          ]}},
        {[:logit, :reverse],
         {[
            :nan,
            :nan,
            :infinity,
            :infinity,
            -0.0,
            :nan,
            :nan,
            nil,
            :nan,
            :nan,
            :neg_infinity,
            :nan,
            690.77552789821368,
            :nan,
            46.051701859880914,
            :nan,
            :nan,
            :nan,
            :nan,
            2.1972245773362191
          ],
          [
            1.0,
            0.88079707797788231,
            0.5,
            0.5,
            0.37754066879814541,
            0.11920292202211755,
            0.0,
            nil,
            :nan,
            0.7310585786300049,
            0.2689414213699951,
            0.62245933120185459,
            0.5,
            0.5,
            0.5,
            0.0,
            1.0,
            0.95257412682243336,
            0.047425873177566781,
            0.47502081252105999
          ],
          [
            :nan,
            :nan,
            :neg_infinity,
            :neg_infinity,
            -4.0,
            :nan,
            :nan,
            nil,
            :nan,
            :nan,
            :neg_infinity,
            :nan,
            r_double("-9.9999999999997626e299"),
            :nan,
            r_double("-1.0000000000000008e20"),
            :nan,
            :nan,
            :nan,
            :nan,
            -11.111111111111109
          ],
          [
            -0.0,
            -0.10499358540350651,
            -0.25,
            -0.25,
            -0.23500371220159449,
            -0.10499358540350651,
            -0.0,
            nil,
            :nan,
            -0.19661193324148188,
            -0.19661193324148188,
            -0.23500371220159449,
            -0.25,
            -0.25,
            -0.25,
            -0.0,
            -0.0,
            -0.045176659730912144,
            -0.045176659730912144,
            -0.24937604019289197
          ]}},
        {[:log10, :log10],
         {[
            :nan,
            :nan,
            :nan,
            :nan,
            :nan,
            -0.52139022765432474,
            :infinity,
            nil,
            :nan,
            :nan,
            :neg_infinity,
            :nan,
            :nan,
            :nan,
            :nan,
            2.4771212547196626,
            :nan,
            :nan,
            -0.32137123613054258,
            :nan
          ],
          [
            1.0,
            1.0232929922807541,
            10.0,
            10.0,
            1453.0403018990435,
            1.0e100,
            :infinity,
            nil,
            :nan,
            1.2589254117941673,
            10_000_000_000.0,
            2.071227320480463,
            10.0,
            10.0,
            10.0,
            :infinity,
            1.0,
            1.0023052380778996,
            :infinity,
            18.152038825555795
          ],
          [
            :nan,
            :nan,
            :nan,
            :nan,
            -1.2531089906545259,
            0.31327724766363146,
            0.0,
            nil,
            :nan,
            :nan,
            :infinity,
            :nan,
            r_double("-6.2870565670537959e296"),
            :nan,
            r_double("-9.430584850580695e17"),
            6.2870565670537965e-304,
            :nan,
            :nan,
            0.13177062444530632,
            -1.8861169701161387
          ],
          [
            0.0,
            0.054253951822391171,
            53.018981104783997,
            53.018981104783997,
            24_361.781155792938,
            r_double("5.3018981104783989e102"),
            :infinity,
            nil,
            :nan,
            0.66746942620247363,
            530_189_811_047.83997,
            3.4726350425034731,
            53.018981104783997,
            53.018981104783997,
            53.018981104783997,
            :infinity,
            0.0,
            0.0053141202478878173,
            :infinity,
            121.15930939298748
          ]}},
        {[:asn, :reverse],
         {[
            :nan,
            :nan,
            -0.0,
            -0.0,
            -1.5707963267948968,
            :nan,
            :nan,
            nil,
            :nan,
            :nan,
            -3.1415926535897931,
            :nan,
            -2.0e-150,
            :nan,
            -2.0000000000000001e-10,
            :nan,
            :nan,
            :nan,
            :nan,
            -0.64350110879328437
          ],
          [
            :nan,
            0.70807341827357118,
            0.0,
            0.0,
            0.061208719054813648,
            0.70807341827357118,
            :nan,
            nil,
            :nan,
            0.22984884706593015,
            0.22984884706593015,
            0.061208719054813648,
            0.0,
            0.0,
            2.4999999999999998e-41,
            0.78769305597877448,
            0.78769305597877448,
            0.99499624830022271,
            0.99499624830022271,
            0.002497917360987117
          ],
          [
            :nan,
            :nan,
            :infinity,
            :neg_infinity,
            -2.0,
            :nan,
            :nan,
            nil,
            :nan,
            :nan,
            :neg_infinity,
            :nan,
            r_double("-9.9999999999999998e149"),
            :nan,
            -10_000_000_000.0,
            :nan,
            :nan,
            :nan,
            :nan,
            -3.3333333333333335
          ],
          [
            :nan,
            -0.45464871341284085,
            -0.0,
            -0.0,
            0.2397127693021015,
            0.45464871341284085,
            :nan,
            nil,
            :nan,
            -0.42073549240394825,
            0.42073549240394825,
            -0.2397127693021015,
            5.0000000000000001e-301,
            -5.0000000000000001e-301,
            4.9999999999999997e-21,
            -0.40894095605795427,
            0.40894095605795427,
            -0.070560004029933607,
            0.070560004029933607,
            0.049916708323414077
          ]}},
        {[{:yj, -1}, :reverse],
         {[
            :infinity,
            8.6666666666666661,
            -0.0,
            -0.0,
            -0.33333333333333337,
            -0.66666666666666674,
            -1.0,
            nil,
            nil,
            2.3333333333333335,
            -0.5,
            0.79166666666666663,
            0.0,
            0.0,
            0.0,
            -1.0,
            :infinity,
            21.0,
            -0.75,
            -0.090909090909090939
          ],
          [
            -1.0,
            -2.0,
            0.0,
            0.0,
            -0.35720880829745316,
            -0.91293118277238894,
            :neg_infinity,
            nil,
            nil,
            :infinity,
            -0.58740105196819936,
            1.0,
            0.0,
            0.0,
            0.0,
            r_double("-1.44224957030739e100"),
            -1.0,
            -1.5,
            -1.1544346900318838,
            -0.091392883061105934
          ],
          [
            :neg_infinity,
            -9.0,
            -1.0,
            -1.0,
            -0.44444444444444442,
            -0.1111111111111111,
            -0.0,
            nil,
            nil,
            -4.0,
            -0.25,
            -2.25,
            -1.0,
            -1.0,
            -1.0,
            -0.0,
            :neg_infinity,
            -16.0,
            -0.0625,
            -0.82644628099173545
          ],
          [
            -0.0,
            -1.0,
            -1.0,
            -1.0,
            -0.54288352331898126,
            -0.2732758832531984,
            -0.0,
            nil,
            nil,
            :neg_infinity,
            -0.39685026299204984,
            -4.0,
            -1.0,
            -1.0,
            -1.0,
            -4.8074985676911148e-201,
            -0.0,
            -0.25,
            -0.21544346900318834,
            -0.83953298697008139
          ]}},
        {[{:compose, [:log10, :reverse]}, :sqrt],
         {[
            :nan,
            :nan,
            :infinity,
            :infinity,
            0.54866200493927153,
            :nan,
            :nan,
            nil,
            :nan,
            :nan,
            -0.0,
            :nan,
            17.320508075688775,
            :nan,
            4.4721359549995796,
            :nan,
            :nan,
            :nan,
            :nan,
            1.0
          ],
          [
            nil,
            nil,
            1.0,
            1.0,
            0.56234132519034907,
            0.0001,
            0.0,
            nil,
            nil,
            nil,
            0.10000000000000001,
            nil,
            1.0,
            nil,
            1.0,
            0.0,
            nil,
            nil,
            1.0000000000000001e-09,
            0.97723722095581067
          ],
          [
            :nan,
            :nan,
            :nan,
            :nan,
            -0.7915519536500828,
            :nan,
            :nan,
            nil,
            :nan,
            :nan,
            :infinity,
            :nan,
            r_double("-1.253700180172057e298"),
            :nan,
            r_double("-4.855559918943616e18"),
            :nan,
            :nan,
            :nan,
            :nan,
            -2.1714724095162588
          ],
          [
            nil,
            nil,
            0.0,
            -0.0,
            -1.2948387525578149,
            -0.0009210340371976184,
            :nan,
            nil,
            nil,
            nil,
            -0.46051701859880922,
            nil,
            -4.6051701859880919e-300,
            nil,
            -4.6051701859880915e-20,
            -0.0,
            nil,
            nil,
            -1.3815510557964278e-08,
            -0.45003437145835568
          ]}},
        {[:exp, :reverse],
         {[
            -0.0,
            -0.1353352832366127,
            -1.0,
            -1.0,
            -1.6487212707001282,
            -7.3890560989306495,
            :neg_infinity,
            nil,
            :nan,
            -0.36787944117144233,
            -2.7182818284590451,
            -0.60653065971263342,
            -1.0,
            -1.0,
            -1.0,
            :neg_infinity,
            -0.0,
            -0.049787068367863951,
            -20.085536923187664,
            -1.1051709180756477
          ],
          [
            :infinity,
            0.69314718055994529,
            :neg_infinity,
            :neg_infinity,
            :nan,
            :nan,
            :nan,
            nil,
            :nan,
            0.0,
            :nan,
            -0.69314718055994529,
            :nan,
            -690.77552789821368,
            :nan,
            :nan,
            690.77552789821368,
            1.0986122886681098,
            :nan,
            :nan
          ],
          [
            -0.0,
            -0.1353352832366127,
            -1.0,
            -1.0,
            -1.6487212707001282,
            -7.3890560989306495,
            :neg_infinity,
            nil,
            :nan,
            -0.36787944117144233,
            -2.7182818284590451,
            -0.60653065971263342,
            -1.0,
            -1.0,
            -1.0,
            :neg_infinity,
            -0.0,
            -0.049787068367863951,
            -20.085536923187664,
            -1.1051709180756477
          ],
          [
            -0.0,
            -0.5,
            :neg_infinity,
            :infinity,
            2.0,
            0.5,
            0.0,
            nil,
            :nan,
            -1.0,
            1.0,
            -2.0,
            r_double("9.999999999999999e299"),
            r_double("-9.999999999999999e299"),
            1.0e20,
            1.0e-300,
            -1.0e-300,
            -0.33333333333333331,
            0.33333333333333331,
            10.0
          ]}},
        {[{:timespan, :minute}, :log10],
         {[
            :nan,
            :nan,
            :neg_infinity,
            :neg_infinity,
            1.4771212547196624,
            2.0791812460476247,
            :infinity,
            nil,
            :nan,
            :nan,
            1.7781512503836436,
            :nan,
            -298.22184874961636,
            :nan,
            -18.221848749616356,
            301.77815125038364,
            :nan,
            :nan,
            2.255272505103306,
            0.77815125038364363
          ],
          [
            0.0,
            0.00016666666666666666,
            0.016666666666666666,
            0.016666666666666666,
            0.052704627669472988,
            1.6666666666666667,
            :infinity,
            nil,
            :nan,
            0.0016666666666666668,
            0.16666666666666666,
            0.0052704627669472991,
            0.016666666666666666,
            0.016666666666666666,
            0.016666666666666666,
            :infinity,
            0.0,
            1.6666666666666667e-05,
            16.666666666666668,
            0.020982090196569454
          ]}}
      ]
    end

    test "puts values through each part in turn and back, R's doubles and derivatives" do
      for {parts, expected} <- composed() do
        name = {:compose, parts}
        values = [Transform.transform(name, edges()), Transform.inverse(name, edges())]

        derivatives =
          if tuple_size(expected) == 4,
            do: [Transform.derivative(name, edges()), Transform.inverse_derivative(name, edges())],
            else: []

        assert {parts, List.to_tuple(values ++ derivatives)} === {parts, expected}
      end
    end

    # Golden: R's `$domain`, `trim_to_domain(c(-5, 0.3, 9, NA))` and
    # `trim_to_domain(c(-5, 0, 10, 1000))` of each
    test "takes what every part takes, as R's domain and trim_to_domain()" do
      for {parts, domain, trimmed, wider} <-
            [
              {[:log10, :reverse], [1.0e-100, :infinity], [-0.95424250943932487, 100.0],
               [-3.0, 100.0]},
              {[:reverse, :log10], [:neg_infinity, -1.0e-100], [-100.0, 0.69897000433601886],
               [-100.0, 0.69897000433601886]},
              {[:sqrt, :log10], [9.9999999999999998e-201, :infinity],
               [-100.0, 0.47712125471966244], [-100.0, 1.5]},
              {[:log10, :sqrt], [1.0, :infinity], [0.0, 0.97685337151454055],
               [0.0, 1.7320508075688772]},
              {[:sqrt, :reverse], [0.0, :infinity], [-3.0, -0.0], [-31.622776601683793, -0.0]},
              {[:exp, :log], [-230.25850929940458, :infinity], [-5.0, 9.0], [-5.0, :infinity]},
              {[:log10], [1.0e-100, :infinity], [-100.0, 0.95424250943932487], [-100.0, 3.0]},
              {[:logit, :reverse], [0.0, 1.0], [:neg_infinity, :infinity],
               [:neg_infinity, :infinity]},
              {[:log10, :log10], [1.0, :infinity], [:neg_infinity, -0.02034124046656138],
               [:neg_infinity, 0.47712125471966244]},
              {[:asn, :reverse], [0.0, 1.0], [-3.1415926535897931, -0.0],
               [-3.1415926535897931, -0.0]},
              {[{:yj, -1}, :reverse], [:neg_infinity, :infinity],
               [-0.90000000000000002, 71.666666666666671],
               [-0.99900099900099903, 71.666666666666671]},
              {[{:compose, [:log10, :reverse]}, :sqrt], [1.0e-100, 1.0], [-0.0, 10.0],
               [-0.0, 10.0]},
              {[:pseudo_log, :reverse], [:neg_infinity, :infinity],
               [-2.2093477086153341, 1.6472311463710958],
               [-6.9077562789806368, 1.6472311463710958]},
              {[:exp, :reverse], [:neg_infinity, :infinity],
               [-8103.0839275753797, -0.0067379469990854687],
               [:neg_infinity, -0.0067379469990854687]},
              {[:log1p, :reverse], [-0.99999999999999978, :infinity],
               [-2.3025850929940459, 36.043653389117154],
               [-6.9087547793152204, 36.043653389117154]},
              {[{:timespan, :minute}, :log10], [1.6666666666666667e-102, :infinity],
               [-100.0, 2.7323937598229686], [-100.0, 4.7781512503836439]}
            ] do
        name = {:compose, parts}
        {low, high} = Transform.domain(name)
        {trimmed_low, trimmed_high} = Transform.trim_to_domain(name, [-5, 0.3, 9, nil])
        {wider_low, wider_high} = Transform.trim_to_domain(name, [-5, 0, 10, 1000])

        assert {parts, [low, high], [trimmed_low, trimmed_high], [wider_low, wider_high]} ===
                 {parts, domain, trimmed, wider}
      end
    end

    # R's `transform_compose("reciprocal", "reverse")$domain` is `c(-Inf, -Inf)` and its
    # `trim_to_domain()` of `c(-5, 0, 10, 1000)` is `c(0, 0)`: R's `min()` and `max()` of the
    # reciprocal's equal zeros both give -0. Here the pair is ordered together, so the domain is
    # the reciprocal's own (design-log §4, the entry beginning "A composition's domain"); every
    # other tie is R's, as `sqrt, reverse, sqrt`'s domain 0 to 0 and `exp, reverse, sqrt`'s -Inf
    # to -Inf (`inc4/step6/sweep/table.R`)
    test "orders the range's two ends as a pair where R's domain is an accident, ties as R's" do
      name = {:compose, [:reciprocal, :reverse]}

      assert {Transform.domain(name), Transform.trim_to_domain(name, [-5, 0, 10, 1000])} ===
               {{:neg_infinity, :infinity}, {-0.001, 0.2}}

      assert {Transform.domain({:compose, [:sqrt, :reverse, :sqrt]}),
              Transform.domain({:compose, [:exp, :reverse, :sqrt]})} ===
               {{0.0, 0.0}, {:neg_infinity, :neg_infinity}}
    end

    # Golden: ggplot2 4.0.3's axes of `scale_y_continuous(transform = transform_compose(...))`
    # on each range (`inc4/step6/axes.R`): breaks the first part's, its labels R's but where
    # plain's differ, and minor breaks R's regular ones unreversed, so log10 then reverse on
    # c(0.01, 5) draws 1.5 and 0.5 but not -0.5, as R does.
    test "draws ggplot2's axes from the first part's breaks and labels" do
      for {name, extent, expected} <- [
            # log10 then reverse on c(1, 1000)
            {{:compose, [:log10, :reverse]}, {-3.1499999999999999, 0.15000000000000002},
             {[{-0.0, "1"}, {-1.0, "10"}, {-2.0, "100"}, {-3.0, "1000"}], [-0.5, -1.5, -2.5]}},
            # log10 then reverse on c(0.01, 5)
            {{:compose, [:log10, :reverse]}, {-0.83391850455281979, 2.1349485002168009},
             {[{2.0, "0.01"}, {1.0, "0.10"}, {-0.0, "1.00"}], [1.5, 0.5]}},
            # log2 then reverse on c(1, 1000)
            {{:compose, [:log2, :reverse]}, {-10.464073498895191, 0.49828921423310435},
             {[{-2.0, "4"}, {-5.0, "32"}, {-8.0, "256"}], [-0.5, -3.5, -6.5]}},
            # sqrt then reverse on c(0, 100)
            {{:compose, [:sqrt, :reverse]}, {-10.5, 0.5},
             {[
                {-0.0, "0"},
                {-5.0, "25"},
                {-7.0710678118654755, "50"},
                {-8.6602540378443873, "75"},
                {-10.0, "100"}
              ], [-2.5, -6.0355339059327378, -7.8656609248549314, -9.3301270189221945]}},
            # reverse then log10 on c(-1000, -1)
            {{:compose, [:reverse, :log10]}, {-0.15000000000000002, 3.1499999999999999},
             {[{3.0, "-1000"}, {2.6989700043360187, "-500"}], [2.8494850021680094]}},
            # sqrt then log10 on c(1, 1000)
            {{:compose, [:sqrt, :log10]}, {-0.075000000000000011, 1.575},
             {[{1.3494850021680094, "500"}, {1.5, "1000"}],
              [1.1989700043360187, 1.2742275032520141, 1.4247425010840047]}},
            # logit then reverse on c(0.01, 0.99)
            {{:compose, [:logit, :reverse]}, {-5.0546318351480481, 5.054631835148049},
             {[{1.0986122886681098, "0.25"}, {-0.0, "0.50"}, {-1.0986122886681098, "0.75"}],
              [
                2.1972245773362196,
                1.6479184330021646,
                0.54930614433405489,
                -0.54930614433405489,
                -1.6479184330021646,
                -2.1972245773362196
              ]}},
            # reciprocal then reverse on c(1, 10)
            {{:compose, [:reciprocal, :reverse]}, {-1.0449999999999999, -0.055},
             {[
                {-0.20000000000000001, "5"},
                {-0.10000000000000001, "10"},
                {-0.066666666666666666, "15"}
              ], [-0.30000000000000004, -0.25, -0.15000000000000002, -0.083333333333333343]}},
            # boxcox(2) then reverse on c(0.0012, 0.0061)
            {{:compose, [{:boxcox, 2}, :reverse]}, {0.49998050075, 0.50000017424999998},
             {[
                {0.5, "0.000"},
                {0.499998, "0.002"},
                {0.49999199999999999, "0.004"},
                {0.49998199999999998, "0.006"}
              ], [0.49999899999999997, 0.49999499999999997, 0.49998699999999996]}},
            # pseudo_log then reverse on c(-100, 100)
            {{:compose, [:pseudo_log, :reverse]}, {-5.0657971880905661, 5.0657971880905661},
             {[{4.6052701709914237, "-100"}, {-0.0, "0"}, {-4.6052701709914237, "100"}],
              [2.3026350854957118, -2.3026350854957118]}},
            # log1p then reverse on c(0, 1000)
            {{:compose, [:log1p, :reverse]}, {-7.2541925182809814, 0.34543773896576102},
             {[{-0.0, "0"}, {-6.2166061010848646, "500"}, {-6.9087547793152204, "1000"}],
              [-3.1083030505424323, -6.562680440200042]}},
            # exp then log on c(-300, 5)
            {{:compose, [:exp, :log]}, {-315.25, 20.25},
             {[
                {-250.0, "-250"},
                {-200.0, "-200"},
                {-150.0, "-150"},
                {-100.0, "-100"},
                {-50.0, "-50"},
                {0.0, "0"}
              ], [-300.0, -275.0, -225.0, -175.0, -125.0, -75.0, -25.0]}},
            # reverse then sqrt on c(-100, 0)
            {{:compose, [:reverse, :sqrt]}, {-0.5, 10.5},
             {[
                {10.0, "-100"},
                {8.6602540378443873, "-75"},
                {7.0710678118654755, "-50"},
                {5.0, "-25"},
                {-0.0, "0"}
              ], [9.3301270189221945, 7.8656609248549314, 6.0355339059327378, 2.5]}}
          ] do
        assert {name, extent, axis(name, extent)} === {name, extent, expected}
      end
    end

    # ggplot2 writes "0 mins", "20 mins" ... "100 mins", R's `format()` of the first part's
    # `difftime` breaks; here the first part writes them, as R writes `transform_timespan("mins")`
    # alone (the entry beginning "A composition's labels")
    test "writes its first part's labels" do
      assert axis({:compose, [{:timespan, :minute}, :reverse]}, {-6300.0, 300.0}) ===
               {[
                  {-0.0, "0"},
                  {-1200.0, "20m"},
                  {-2400.0, "40m"},
                  {-3600.0, "1h"},
                  {-4800.0, "80m"},
                  {-6000.0, "100m"}
                ], [-600.0, -1800.0, -3000.0, -4200.0, -5400.0]}
    end

    # ggplot2 warns "Ignoring `n.breaks`" on `transform_compose("log10", "reverse")` and draws
    # 1, 10, 100 and 1000 on c(1, 1000); with `n.breaks = 2` log10 alone draws 100 there
    test "hands n: to its first part, which refuses it as it would alone" do
      name = {:compose, [:log10, :reverse]}
      breaks = Transform.breaks(name, {-3.15, 0.15}, n: 2)

      assert {breaks, Transform.format(name, [-2.0], {-3.15, 0.15}, n: 2)} ===
               {Transform.transform(:reverse, Transform.breaks(:log10, {-0.15, 3.15}, n: 2)),
                ["100"]}

      assert_raise ArgumentError, ~r/counts no breaks/, fn ->
        Transform.breaks({:compose, [:time, :reverse]}, {-7380.0, -3420.0}, n: 3)
      end
    end

    # Golden: ggplot2's axes of `scale_y_continuous(transform = transform_compose("date",
    # "reverse"))` on 2024-01-01 and 2024-03-01, with `breaks = breaks_width("2 weeks")` too,
    # `transform_compose(transform_time("UTC"), "reverse")` on midnight to noon of 2024-01-01 and
    # `transform_compose("hms", "reverse")` on 1h and 2h (`inc4/step6/temporal.R`)
    test "draws a date, date-time or time first part's axis reversed" do
      date = {:compose, [:date, :reverse]}
      datetime = {:compose, [{:datetime, "Etc/UTC", Calendar.UTCOnlyTimeZoneDatabase}, :reverse]}
      time = {:compose, [:time, :reverse]}

      steps =
        date
        |> Transform.width([week: 2], {-19_786.0, -19_720.0})
        |> inside({-19_786.0, -19_720.0})

      assert {elem(axis(date, {-19_786.0, -19_720.0}), 0), steps,
              Transform.format(date, steps, :given)} ===
               {[
                  {-19_723.0, "Jan 01"},
                  {-19_737.0, "Jan 15"},
                  {-19_754.0, "Feb 01"},
                  {-19_768.0, "Feb 15"},
                  {-19_783.0, "Mar 01"}
                ], [-19_730.0, -19_744.0, -19_758.0, -19_772.0, -19_786.0],
                ["2024-01-08", "2024-01-22", "2024-02-05", "2024-02-19", "2024-03-04"]}

      assert {elem(axis(datetime, {-1_704_112_560.0, -1_704_065_040.0}), 0),
              elem(axis(time, {-7380.0, -3420.0}), 0)} ===
               {[
                  {-1_704_067_200.0, "00:00"},
                  {-1_704_078_000.0, "03:00"},
                  {-1_704_088_800.0, "06:00"},
                  {-1_704_099_600.0, "09:00"},
                  {-1_704_110_400.0, "12:00"}
                ],
                [
                  {-3600.0, "01:00:00"},
                  {-4800.0, "01:20:00"},
                  {-6000.0, "01:40:00"},
                  {-7200.0, "02:00:00"}
                ]}

      assert {Transform.transform(date, [~D[2024-01-01], nil]),
              Transform.inverse(date, [-19_723.0])} ===
               {[-19_723.0, nil], [~D[2024-01-01]]}
    end

    test "refuses a date, date-time or time part anywhere but first, and what it cannot do" do
      late =
        assert_raise ArgumentError, fn ->
          Transform.transform({:compose, [:reverse, :date]}, [1])
        end

      trimmed =
        assert_raise ArgumentError, fn ->
          Transform.trim_to_domain({:compose, [:date, :reverse]}, [1])
        end

      assert_raise FunctionClauseError, fn ->
        Transform.derivative({:compose, [:date, :reverse]}, [1])
      end

      assert {String.starts_with?(late.message, "a date, date-time or time transformation comes"),
              late.message =~ "{:compose, [:reverse, :date]}",
              String.starts_with?(trimmed.message, "{:compose, [:date, :reverse]} takes dates")} ==
               {true, true, true}
    end

    # The first part's own domain, every date, whose ends no date's transformation takes
    test "takes a date, date-time or time first part's domain" do
      assert Transform.domain({:compose, [:date, :reverse]}) === {:neg_infinity, :infinity}
    end

    # R aborts `transform_compose("sqrt", "reverse", "log10")`: "Sequence of transformations
    # yields invalid domain", and `transform_compose()`: "must include at least 1 transformer"
    test "refuses parts no value passes, no parts, and derivatives a part lacks" do
      passes_none =
        assert_raise ArgumentError, fn ->
          Transform.transform({:compose, [:sqrt, :reverse, :log10]}, [1])
        end

      assert String.starts_with?(
               passes_none.message,
               "no value passes every part of {:compose, [:sqrt, :reverse, :log10]}"
             )

      for name <- [{:compose, []}, {:compose, :log10}] do
        assert_raise FunctionClauseError, fn -> Transform.transform(name, [1]) end
      end

      assert_raise FunctionClauseError, fn ->
        Transform.derivative({:compose, [:timespan, :reverse]}, [1])
      end
    end

    # R aborts, "Sequence of transformations yields invalid domain", where the domain's ends turn
    # back to NA or NaN or the domain transforms to either: a part of one's own can make any of
    # them happen, at either end
    test "refuses parts whose domain turns back to nothing or transforms to NaN, at either end" do
      for lost <- [nil, :nan],
          ending <- [:infinity, :neg_infinity],
          direction <- [:back, :forward] do
        losing = fn
          ^ending -> lost
          value -> value
        end

        keeping = fn value -> value end

        {transform, inverse} =
          if direction == :forward, do: {losing, keeping}, else: {keeping, losing}

        part = Transform.new("losing", transform: transform, inverse: inverse)

        assert_raise ArgumentError, ~r/no value passes every part/, fn ->
          Transform.transform({:compose, [part, :identity]}, [1])
        end
      end
    end

    # R aborts `transform_compose("asn", "reverse", shift, transform_boxcox(0.5, offset = 3))`,
    # shift `x - 1` (`inc4/step6/disjoint.R`): its range, -1 - pi to -1, lies below Box-Cox's
    # domain from 0, though Box-Cox places -1 and asn's inverse turns anything back to a number
    test "refuses a range wholly outside a later part's domain, though it turns back to numbers" do
      shift =
        Transform.new("shift",
          transform: fn
            value when value in [:infinity, :neg_infinity] -> value
            value -> value - 1
          end,
          inverse: fn
            position when position in [:infinity, :neg_infinity] -> position
            position -> position + 1
          end
        )

      assert_raise ArgumentError, ~r/no value passes every part/, fn ->
        Transform.transform({:compose, [:asn, :reverse, shift, {:boxcox, 0.5, offset: 3}]}, [1])
      end
    end

    # Golden: R's `d_transform` of `transform_compose("sqrt", transform_yj(-1))` at -Inf and -2
    # is NA, yj's NA times sqrt's NaN (`inc4/step6/sweep/table.R`); of a part whose derivative is
    # always NA then sqrt, NaN at -2 and NA at 4, sqrt's NaN times NA (`inc4/step6/nan_na.R`):
    # R's `*` keeps its first operand's, the part's derivative times the product so far
    test "chains derivatives as R multiplies NA and NaN, the part's first" do
      missing_slope =
        Transform.new("missing_slope",
          transform: fn value -> value end,
          inverse: fn position -> position end,
          derivative: fn _value -> nil end
        )

      assert {Transform.derivative({:compose, [:sqrt, {:yj, -1}]}, [:neg_infinity, -2.0]),
              Transform.derivative({:compose, [missing_slope, :sqrt]}, [-2.0, 4.0])} ===
               {[nil, nil], [:nan, nil]}
    end
  end

  describe "a transformation of your own" do
    # The cube and its signed cube root, R's `new_transform("cube", function(x) x^3,
    # function(x) sign(x) * abs(x)^(1/3))`, on the whole line, so handling both infinities.
    defp cube(options \\ []) do
      Transform.new(
        "cube",
        [
          transform: fn
            :infinity -> :infinity
            :neg_infinity -> :neg_infinity
            value -> value * value * value
          end,
          inverse: fn
            :infinity -> :infinity
            :neg_infinity -> :neg_infinity
            position when position < 0 -> -:math.pow(-position, 1 / 3)
            position -> :math.pow(position, 1 / 3)
          end
        ] ++ options
      )
    end

    # Golden: R's `transform`, `inverse`, `d_transform = function(x) 3 * x^2` and
    # `d_inverse = function(x) abs(x)^(-2/3) / 3` at the nine doubles (`inc4/step6/golden2.R`),
    # but the cube of -0, the user's own arithmetic, -0 here where R's `^` gives +0
    test "puts values through its functions, R's doubles" do
      cube =
        cube(
          derivative: fn
            value when value in [:infinity, :neg_infinity] -> :infinity
            value -> 3 * (value * value)
          end,
          inverse_derivative: fn
            position when position in [:infinity, :neg_infinity] ->
              0.0

            position when position == 0 ->
              :infinity

            position ->
              magnitude = abs(position)
              :math.pow(magnitude, -2 / 3) / 3
          end
        )

      doubles = [:neg_infinity, -2.0, -0.0, 0.0, 0.5, 2.0, :infinity, nil, :nan]

      assert {Transform.transform(cube, doubles), Transform.inverse(cube, doubles),
              Transform.derivative(cube, doubles), Transform.inverse_derivative(cube, doubles)} ===
               {[:neg_infinity, -8.0, -0.0, 0.0, 0.125, 8.0, :infinity, nil, :nan],
                [
                  :neg_infinity,
                  -1.2599210498948732,
                  0.0,
                  0.0,
                  0.79370052598409979,
                  1.2599210498948732,
                  :infinity,
                  nil,
                  :nan
                ], [:infinity, 12.0, 0.0, 0.0, 0.75, 12.0, :infinity, nil, :nan],
                [
                  0.0,
                  0.20998684164914552,
                  :infinity,
                  :infinity,
                  0.52913368398939975,
                  0.20998684164914552,
                  0.0,
                  nil,
                  :nan
                ]}
    end

    test "hands its function each value in its domain, its ends among them, integers as floats" do
      test = self()

      root =
        Transform.new("root",
          transform: fn value ->
            send(test, {:handed, value})
            if value == :infinity, do: :infinity, else: :math.sqrt(value)
          end,
          inverse: fn position -> position * position end,
          domain: {0, :infinity}
        )

      assert Transform.transform(root, [4, -1, nil, :nan, :neg_infinity]) ===
               [2.0, :nan, nil, :nan, :nan]

      assert_received {:handed, 4.0}
      refute_received {:handed, _value}

      assert Transform.squish(root, {-0.5, 3.0}) === {0.0, 3.0}
      assert_received {:handed, +0.0}
      assert_received {:handed, :infinity}
    end

    test "makes an integer answered a float and refuses any answer but a double" do
      rounded = Transform.new("rounded", transform: &round/1, inverse: &round/1)
      unplaced = Transform.new("unplaced", transform: fn _value -> :nan end, inverse: &round/1)

      assert {Transform.transform(rounded, [2.4]), Transform.transform(unplaced, [2.4])} ===
               {[2.0], [:nan]}

      error =
        assert_raise ArgumentError, fn ->
          "worded"
          |> Transform.new(transform: fn _value -> "two" end, inverse: &round/1)
          |> Transform.transform([2])
        end

      assert String.starts_with?(
               error.message,
               ~s(the "worded" transformation's transform function returned "two" for 2;)
             )
    end

    test "refuses a missing function, an unknown option, another arity and a domain not low to high" do
      for options <- [
            [transform: &round/1],
            [inverse: &round/1],
            [transform: &round/1, inverse: &round/1, base: 10],
            [transform: &round/1, inverse: &Kernel.+/2],
            [transform: &round/1, inverse: &round/1, domain: {1, 0}],
            [transform: &round/1, inverse: &round/1, domain: {0, 0}],
            [transform: &round/1, inverse: &round/1, domain: {:infinity, :infinity}],
            [transform: &round/1, inverse: &round/1, domain: [0, 1]],
            [transform: &round/1, inverse: &round/1, domain: {"0", 1}],
            [transform: &round/1, inverse: &round/1, domain: {0, "1"}],
            [transform: &round/1, inverse: &round/1, breaks: fn -> [] end]
          ] do
        assert_raise NimbleOptions.ValidationError, fn -> Transform.new("odd", options) end
      end

      reversed =
        assert_raise NimbleOptions.ValidationError, fn ->
          Transform.new("odd", transform: &round/1, inverse: &round/1, domain: {1, 0})
        end

      worded =
        assert_raise NimbleOptions.ValidationError, fn ->
          Transform.new("odd", transform: &round/1, inverse: &round/1, domain: {"0", 1})
        end

      assert {reversed.message =~ "{1, 0}", worded.message =~ ~s({"0", 1})} == {true, true}

      for name <- [:cube, nil] do
        assert_raise FunctionClauseError, fn ->
          Transform.new(name, transform: &round/1, inverse: &round/1)
        end
      end
    end

    # Golden: ggplot2 4.0.3's axes of `scale_y_continuous(transform = new_transform(...))` on
    # each range (`inc4/step6/axes.R`, `golden2.R`): the cube, falling, a square root from 0, a
    # breaks function of one argument, `label_percent()`'s labels, and 1 - 1/x on 1e-100 up,
    # bounded by 1, whose axis on 1 to 100 passes its bound and draws no breaks, and on 0.5 to 3
    # does not
    test "draws ggplot2's axes from its breaks, minor breaks and labels" do
      falling =
        Transform.new("negcube",
          transform: fn
            :infinity -> :neg_infinity
            :neg_infinity -> :infinity
            value -> -(value * value * value)
          end,
          inverse: fn
            :infinity -> :neg_infinity
            :neg_infinity -> :infinity
            position when position > 0 -> -:math.pow(position, 1 / 3)
            position -> :math.pow(-position, 1 / 3)
          end
        )

      root =
        Transform.new("mysqrt",
          transform: fn
            :infinity -> :infinity
            value -> :math.sqrt(value)
          end,
          inverse: fn
            :infinity -> :infinity
            position -> position * position
          end,
          domain: {0, :infinity}
        )

      bounded =
        Transform.new("bounded",
          transform: fn
            :infinity -> 1.0
            value -> 1 - 1 / value
          end,
          inverse: fn
            position when position == 1 -> :infinity
            :neg_infinity -> 0.0
            position -> 1 / (1 - position)
          end,
          domain: {1.0e-100, :infinity}
        )

      for {name, extent, expected} <- [
            {cube(), {-1100.0, 1100.0},
             {[{-1000.0, "-10"}, {-125.0, "-5"}, {0.0, "0"}, {125.0, "5"}, {1000.0, "10"}],
              [-562.5, -62.5, 62.5, 562.5]}},
            {cube(), {-50_000_000.0, 1_050_000_000.0},
             {[{0.0, "0"}, {125_000_000.0, "500"}, {1_000_000_000.0, "1000"}],
              [62_500_000.0, 562_500_000.0]}},
            {falling, {-1100.0, 1100.0},
             {[{1000.0, "-10"}, {125.0, "-5"}, {-0.0, "0"}, {-125.0, "5"}, {-1000.0, "10"}],
              [562.5, 62.5, -62.5, -562.5]}},
            {root, {9.9499999999999993, 10.050000000000001},
             {[
                {9.9749686716300019, "99.5"},
                {10.0, "100.0"},
                {10.024968827881711, "100.5"},
                {10.04987562112089, "101.0"}
              ], [9.9624530074450028, 9.9874843358150009, 10.012484413940856, 10.037422224501301]}},
            {cube(breaks: fn _limits -> [1.0, 2.0, 3.0] end), {-6.25, 131.25},
             {[{1.0, "1"}, {8.0, "2"}, {27.0, "3"}], [-6.0, -2.5, 4.5, 17.5, 30.5, 34.0]}},
            {cube(labels: &Scales.Labels.percent/1), {-0.050000000000000003, 1.05},
             {[{0.0, "0%"}, {0.125, "50%"}, {1.0, "100%"}], [0.0625, 0.5625]}},
            {bounded, {-0.049500000000000002, 1.0395000000000001}, {[], []}},
            {bounded, {-1.0833333333333333, 0.75000000000000011},
             {[{0.0, "1"}, {0.5, "2"}, {0.66666666666666674, "3"}, {0.75, "4"}],
              [-0.5, -0.25, 0.25, 0.58333333333333337, 0.70833333333333337]}}
          ] do
        assert {name.name, extent, axis(name, extent)} === {name.name, extent, expected}
      end
    end

    # Golden: ggplot2 4.0.3's colour legend under the cube on 1 to 10,000 (`inc4/step8/kinds.R`),
    # its breaks' cube roots 2499.999999999999 to 9999.999999999995 in R as here
    # (`inc4/step8/cuberoot.R`), which `format()` writes `2500` to `10000`, and `plain/1` at 15
    # digits `2500.00000000000` to `9999.99999999999`
    test "labels each break turned back rounded to 14 significant digits unless told" do
      extent = {1.0, 1.0e12}
      breaks = Transform.breaks(cube(), extent)

      labels = Transform.format(cube(), breaks, extent)

      plain =
        [labels: &Scales.Labels.plain/1]
        |> cube()
        |> Transform.format(breaks, extent)

      assert {breaks, labels, cube().labels} ===
               {[0.0, 15_625_000_000.0, 125_000_000_000.0, 421_875_000_000.0, 1.0e12],
                ["0", "2500", "5000", "7500", "10000"], &Scales.Labels.plain_round_tripped/1}

      assert plain ==
               [
                 "0.00000000000",
                 "2500.00000000000",
                 "5000.00000000000",
                 "7500.00000000000",
                 "9999.99999999999"
               ]
    end

    # ggplot2 hands `n.breaks = 10` to `extended_breaks()`, which takes `n`, and draws -200 to
    # 1000 by 200 on c(0, 1000) under the cube (`inc4/step6/n10.R`); it ignores it, with a
    # warning, for a breaks function without one
    test "hands n: to a breaks function of two arguments and refuses it for one of one" do
      extent = {-50_000_000.0, 1_050_000_000.0}

      breaks =
        cube()
        |> Transform.breaks(extent, n: 10)
        |> inside(extent)

      assert {breaks, Transform.format(cube(), breaks, extent, n: 10)} ===
               {[
                  -8_000_000.0,
                  0.0,
                  8_000_000.0,
                  64_000_000.0,
                  216_000_000.0,
                  512_000_000.0,
                  1_000_000_000.0
                ], ["-200", "0", "200", "400", "600", "800", "1000"]}

      counting_none = cube(breaks: fn _limits -> [1.0] end)

      refused =
        assert_raise ArgumentError, fn ->
          Transform.breaks(counting_none, {0.0, 1.0}, n: 3)
        end

      assert_raise ArgumentError, fn ->
        Transform.format(counting_none, [1.0], {0.0, 1.0}, n: 3)
      end

      assert {String.starts_with?(
                refused.message,
                ~s(the "cube" transformation's breaks function)
              ), refused.message =~ "[:n]"} == {true, true}
    end

    # ggplot2 draws no breaks on an axis wholly past a bound its transformation never reaches: both
    # ends squish onto it and turn back to infinities, and both are set aside
    test "finds no breaks where both ends turn back to anything but a number" do
      bounded =
        Transform.new("bounded",
          transform: fn
            :infinity -> 1.0
            value -> 1 - 1 / value
          end,
          inverse: fn
            position when position == 1 -> :infinity
            :neg_infinity -> 0.0
            position -> 1 / (1 - position)
          end,
          domain: {1.0e-100, :infinity}
        )

      squished = Transform.squish(bounded, {1.05, 1.2})
      assert {squished, Transform.breaks(bounded, squished)} === {{1.0, 1.0}, []}
    end

    test "takes its minor breaks function, and has no derivative it was not given" do
      first_only = cube(minor_breaks: fn breaks, _extent -> Enum.take(breaks, 1) end)
      assert Transform.minor_breaks(first_only, [1.0, 8.0], {0.0, 10.0}) === [1.0]

      assert_raise ArgumentError, ~r/the "cube" transformation has no derivative/, fn ->
        Transform.derivative(cube(), [1.0])
      end

      assert_raise ArgumentError, ~r/has no inverse_derivative/, fn ->
        Transform.inverse_derivative({:compose, [:log10, cube()]}, [1.0])
      end

      assert inspect(cube()) =~ ~s(name: "cube")
    end

    # Golden: ggplot2's axes of `transform_compose(cube, "log10")` and
    # `transform_compose("log10", cube)` on c(1, 1000), the second's labels R's `1e-01` to `1e+03`
    # written plain; and the first's derivatives at 1, 2 and 10, its inverse's at 0, 1 and 3, and
    # its domain (`inc4/step6/golden2.R`)
    test "is a composition's part" do
      cube =
        cube(
          derivative: fn value -> 3 * (value * value) end,
          inverse_derivative: fn position ->
            magnitude = abs(position)
            :math.pow(magnitude, -2 / 3) / 3
          end
        )

      first = {:compose, [cube, :log10]}

      assert {axis(first, {-0.45000000000000001, 9.4499999999999993}),
              axis({:compose, [:log10, cube]}, {-1.3500000000000001, 28.350000000000001})} ===
               {{[{8.0969100130080562, "500"}, {9.0, "1000"}],
                 [7.1938200260161125, 7.6453650195120844, 8.5484550065040281]},
                {[
                   {-1.0, "0.1"},
                   {0.0, "1.0"},
                   {1.0, "10.0"},
                   {8.0, "100.0"},
                   {27.0, "1000.0"}
                 ], [-0.5, 0.5, 4.5, 17.5, 27.5, 28.0]}}

      assert {Transform.derivative(first, [1, 2, 10]),
              Transform.inverse_derivative(first, [0, 1, 3]), Transform.domain(first)} ===
               {[1.3028834457097553, 0.65144172285487767, 0.13028834457097555],
                [0.76752836433134863, 1.6535897336988881, 7.6752836433134872],
                {4.6415888336127987e-34, :infinity}}
    end
  end

  describe "resolved/1" do
    # A user's function without an infinity's clause fails on a composition's domain, its own
    # error, never read as an unknown name.
    test "says whether a name resolves, an unknown one :unknown and a composition's refusal why" do
      broken =
        Transform.new("broken",
          transform: fn value when is_number(value) -> value end,
          inverse: fn position -> position end
        )

      assert Enum.map(
               [:log10, {:log, 3}, {:compose, [:sqrt, :reverse]}, :ln, {:log, 1}, {:compose, []}],
               &Transform.resolved/1
             ) == [
               {:ok, :log10},
               {:ok, {:log, 3}},
               {:ok, {:compose, [:sqrt, :reverse]}},
               {:error, :unknown},
               {:error, :unknown},
               {:error, :unknown}
             ]

      assert {:error, reason} = Transform.resolved({:compose, [:log10, :date]})
      assert String.starts_with?(reason, "a date, date-time or time transformation comes first")
      assert_raise FunctionClauseError, fn -> Transform.resolved({:compose, [broken]}) end
    end
  end
end
