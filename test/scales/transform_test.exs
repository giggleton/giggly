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

  # Those of `positions` inside `{low, high}`, its ends included.
  defp inside(positions, {low, high}),
    do: Enum.filter(positions, fn position -> position >= low and position <= high end)

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

    # transform_sqrt()$inverse(c(3, 0.5, -0, -1)) is 9, 0.25, 0, NA
    test "turns a position back by squaring it, one below zero missing" do
      assert Transform.inverse(:sqrt, [3.0, 0.5, -0.0, -1.0]) === [9.0, 0.25, 0.0, nil]
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

    # R's range() of -0 and 0 is the first twice, as min() and max() keep the first of equals;
    # reciprocal of (-0, 4) is -Inf to 0.25, of (-Inf, Inf) -0 twice.
    test "of two equal ends, the first is both, so a zero's sign is the first's" do
      assert {Transform.trim_to_domain(:identity, [-0.0, 0.0]),
              Transform.trim_to_domain(:identity, [0.0, -0.0]),
              Transform.trim_to_domain(:reverse, [0.0, 0.0]),
              Transform.trim_to_domain(:reciprocal, [-0.0, 4.0]),
              Transform.trim_to_domain(:reciprocal, [:neg_infinity, :infinity])} ===
               {{-0.0, -0.0}, {0.0, 0.0}, {-0.0, -0.0}, {:neg_infinity, 0.25}, {-0.0, -0.0}}
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
end
