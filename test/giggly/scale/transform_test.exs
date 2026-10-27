defmodule Giggly.Scale.TransformTest do
  use ExUnit.Case, async: true

  alias Giggly.{Datasets, Scale}
  alias Giggly.Scale.{Continuous, Transform}

  # Golden: every axis below is R's own, from R 4.6.1 with ggplot2 4.0.3 and scales 1.4.0 (the
  # image `giggly-r:ggplot2-4.0.3`): `ggplot_build()`'s panel params for the plot in the comment
  # above each, their continuous range, breaks inside it, labels, and minor breaks less the breaks
  # (which ggplot2's grid leaves out). They move only if ggplot2's transformations do. R writes a
  # log axis's labels from 1e5 up in scientific notation; Giggly writes them in plain decimals.

  # An axis of `values` on a continuous scale through `transform`: its extent, its breaks and its
  # minor breaks, as the assembly finds them.
  defp axis(transform, values, options \\ []) do
    scale = struct!(Continuous, [{:transform, transform} | options])
    trained = Scale.train(scale, Scale.transform(scale, values), :none)
    extent = Scale.dimension(trained)
    breaks = Scale.breaks(trained, extent)
    {extent, breaks, Scale.minor_breaks(trained, breaks, extent)}
  end

  defp column(dataset, name), do: Keyword.fetch!(dataset, name)

  # The labels of a trained scale's breaks on `extent`, in order.
  defp labels(scale, extent) do
    scale
    |> Scale.breaks(extent)
    |> Enum.map(fn {_position, label} -> label end)
  end

  describe "log10" do
    test "marks the powers of ten, every one or every second, that leave three inside" do
      # ggplot(data.frame(x = 1:2, y = c(1, 1e6)), aes(x, y)) + geom_point() + scale_y_log10();
      # y = c(5, 20000), where every second power leaves two and every power four
      assert axis(:log10, [1, 1.0e6]) ==
               {{-0.30000000000000004, 6.3}, [{1.0, "10"}, {3.0, "1000"}, {5.0, "100000"}],
                [0.0, 2.0, 4.0, 6.0]}

      assert axis(:log10, [5, 20_000]) ==
               {{0.51886700476962067, 4.4811329952303796},
                [{1.0, "10"}, {2.0, "100"}, {3.0, "1000"}, {4.0, "10000"}], [1.5, 2.5, 3.5]}
    end

    test "adds multiples of each power, evenest first, when too few powers fall inside" do
      # mpg's hwy, ggplot(mpg, aes(displ, hwy)) + geom_point() + scale_y_log10(); y = c(2, 8);
      # y = c(1.5, 30); diamonds' price on x
      assert axis(:log10, column(Datasets.mpg(), :hwy)) ==
               {{1.0509676745256968, 1.6716662480081155},
                [
                  {1.3010299956639813, "20"},
                  {1.4771212547196624, "30"},
                  {1.6020599913279625, "40"}
                ],
                [1.1249387366083001, 1.2129843661361406, 1.3890756251918219, 1.5395906230238126]}

      assert axis(:log10, [2, 8]) ==
               {{0.27092699609758308, 0.93319298655834171},
                [
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

      assert axis(:log10, [1.5, 30]) ==
               {{0.11103975927248218, 1.5421727545028614},
                [{0.47712125471966244, "3"}, {1.0, "10"}, {1.4771212547196624, "30"}],
                [0.21568188207949363, 0.7385606273598313, 1.2385606273598313]}

      assert axis(:log10, column(Datasets.diamonds(), :price)) ==
               {{2.4251440379594578, 4.3627624043460393},
                [
                  {2.4771212547196626, "300"},
                  {3.0, "1000"},
                  {3.4771212547196626, "3000"},
                  {4.0, "10000"}
                ],
                [2.7385606273598313, 3.2385606273598313, 3.7385606273598313, 4.2614393726401687]}
    end

    test "falls back to extended breaks in data units when even nine multiples leave too few" do
      # y = c(100, 101) and y = c(2, 3)
      assert axis(:log10, [100, 101]) ==
               {{1.9997839313108678, 2.0045374424717748},
                [
                  {2.0, "100.00"},
                  {2.0010843812922201, "100.25"},
                  {2.0021660617565078, "100.50"},
                  {2.0032450548131471, "100.75"},
                  {2.0043213737826426, "101.00"}
                ],
                [2.0005421906461098, 2.001625221524364, 2.0027055582848274, 2.0037832142978949]}

      {_extent, breaks, _minor} = axis(:log10, [2, 3])

      assert breaks == [
               {0.3010299956639812, "2.00"},
               {0.35218251811136247, "2.25"},
               {0.3979400086720376, "2.50"},
               {0.43933269383026263, "2.75"},
               {0.47712125471966244, "3.00"}
             ]
    end

    # Golden: scales 1.4.0's `breaks_log()(10^extent)`, those inside the extent, in log space, on
    # extents chosen from 600 random ones (seed 20261019) as the first where a slip in R's port
    # departs from R: the first step's size, how many breaks are enough, how evenness is measured,
    # the multiples tried, the fallback, and how many powers a step leaves; and an extent ending
    # exactly on powers of ten, which count as inside.
    test "breaks inside the extent are R's breaks_log() wherever a slip would show" do
      for {extent, expected} <- [
            {{3.7012828388251364, 15.141030670586783}, [6.0, 9.0, 12.0, 15.0]},
            {{-1.989977743010968, 6.0139288976533276}, [0.0, 2.0, 4.0, 6.0]},
            {{-0.74079247051849961, -0.0016752352783626634},
             [-0.69897000433601875, -0.52287874528033751, -0.3010299956639812]},
            {{-2.67495376477018, -2.5310531331511439},
             [-2.6575773191777938, -2.6197887582883941, -2.5850266520291818, -2.5528419686577806]},
            {{2.9382192031480372, 3.0423576763965769},
             [2.9542425094393248, 2.9777236052888476, 3.0, 3.0211892990699383, 3.0413926851582249]},
            {{6.8817255878821015, 7.2213514697328911},
             [6.9030899869919438, 6.9542425094393252, 7.0]},
            {{1.0, 3.0}, [1.0, 2.0, 3.0]}
          ] do
        {low, high} = extent

        inside =
          :log10
          |> Transform.breaks(extent)
          |> Enum.filter(fn position -> position >= low and position <= high end)

        assert inside == expected
      end
    end

    test "finds its breaks from 1e-100 up, R's domain" do
      # data.frame(y = c(1e-120, 1e-80)) with scale_y_log10(): the extent from -122 is squished
      # to -100 before its breaks are found
      {extent, breaks, _minor} = axis(:log10, [1.0e-120, 1.0e-80])

      assert extent == {-122.0, -78.0}

      assert Enum.map(breaks, fn {position, _label} -> position end) ==
               [-100.0, -95.0, -90.0, -85.0, -80.0]
    end

    test "takes limits, breaks and minor breaks in data units" do
      # hwy with scale_y_log10(limits = c(10, 100)); y = c(1, 10, 100) with breaks = c(0, 10, 100),
      # 0 outside the domain, and minor_breaks = c(5, 50)
      assert axis(:log10, column(Datasets.mpg(), :hwy), limits: {10, 100}) ==
               {{0.95, 2.05}, [{1.0, "10"}, {1.4771212547196624, "30"}, {2.0, "100"}],
                [1.2385606273598313, 1.7385606273598313]}

      {_extent, breaks, minor} =
        axis(:log10, [1, 10, 100], breaks: [0, 10, 100], minor_breaks: [5, 50])

      assert breaks == [{1.0, "10"}, {2.0, "100"}]
      assert minor == [0.69897000433601886, 1.6989700043360187]
    end

    test "places zero at minus infinity and a negative value nowhere" do
      # data.frame(y = c(0, 10, 100)) with scale_y_log10(): layer_data()'s y is -Inf, 1, 2;
      # log10(-1) is NaN, missing
      scale = %Continuous{transform: :log10}

      assert Scale.transform(scale, [0, -1, 10, :infinity, nil]) ==
               [:neg_infinity, nil, 1.0, :infinity, nil]
    end
  end

  describe "sqrt" do
    test "marks extended breaks in data units, minor breaks midway in square-root space" do
      # ggplot(mpg, aes(displ, hwy)) + geom_point() + scale_y_sqrt(); with limits = c(16, 36)
      assert axis(:sqrt, column(Datasets.mpg(), :hwy)) ==
               {{3.3056442168591023, 6.7917069789894517},
                [
                  {4.4721359549995796, "20"},
                  {5.4772255750516612, "30"},
                  {6.324555320336759, "40"}
                ],
                [3.467046334947498, 3.9695911449735388, 4.9746807650256208, 5.9008904476942101]}

      assert axis(:sqrt, column(Datasets.mpg(), :hwy), limits: {16, 36}) ==
               {{3.9, 6.1},
                [
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
      assert axis(:sqrt, [0, 4, 9]) ==
               {{-0.15000000000000002, 3.15},
                [
                  {0.0, "0.0"},
                  {1.5811388300841898, "2.5"},
                  {2.2360679774997898, "5.0"},
                  {2.7386127875258306, "7.5"}
                ], [0.79056941504209488, 1.9086034037919899, 2.4873403825128104]}
    end

    test "finds its breaks from zero, not below or above it, where the axis is near it" do
      # data.frame(x = c(0, 1)) with scale_x_sqrt(): the breaks 0 to 1 in quarters, found from the
      # domain's 0 where the widened axis reaches below it, and R's minor breaks less the breaks
      assert axis(:sqrt, [0, 1]) ==
               {{-0.05, 1.05},
                [
                  {0.0, "0.00"},
                  {0.5, "0.25"},
                  {0.70710678118654757, "0.50"},
                  {0.8660254037844386, "0.75"},
                  {1.0, "1.00"}
                ], [0.25, 0.60355339059327373, 0.78656609248549314, 0.9330127018922193]}
    end

    test "places a negative value nowhere" do
      # data.frame(y = c(-1, 4, 9)) with scale_y_sqrt(): layer_data()'s y is NA, 2, 3
      assert Scale.transform(%Continuous{transform: :sqrt}, [-1, 4, 9, :infinity]) ==
               [nil, 2.0, 3.0, :infinity]
    end
  end

  describe "reverse" do
    test "runs high to low, its breaks descending and its minor breaks R's reversed ones" do
      # ggplot(mpg, aes(displ, hwy)) + geom_point() + scale_y_reverse()
      assert axis(:reverse, column(Datasets.mpg(), :hwy)) ==
               {{-45.6, -10.4}, [{-20.0, "20"}, {-30.0, "30"}, {-40.0, "40"}],
                [-15.0, -25.0, -35.0, -45.0]}
    end

    test "sorts its limits once negated, and leaves an end to the data unsorted" do
      # ggplot(mtcars, aes(mpg, wt)) + geom_point() + xlim(20, 15); data.frame(y = c(1, 10, 100))
      # with scale_y_reverse(limits = c(50, NA)), whose 100 is censored
      assert axis(:reverse, column(Datasets.mtcars(), :mpg), limits: {20, 15}) ==
               {{-20.25, -14.75},
                [
                  {-15.0, "15"},
                  {-16.0, "16"},
                  {-17.0, "17"},
                  {-18.0, "18"},
                  {-19.0, "19"},
                  {-20.0, "20"}
                ], [-15.5, -16.5, -17.5, -18.5, -19.5]}

      scale = %Continuous{transform: :reverse, limits: {50, nil}}
      trained = Scale.train(scale, Scale.transform(scale, [1, 10, 100]), :none)
      extent = Scale.dimension(trained)

      assert extent == {-52.45, 1.4500000000000002}
      assert labels(trained, extent) == ~w(0 10 20 30 40 50)
      assert Scale.map(trained, Scale.transform(scale, [1, 10, 100])) == [-1, -10, nil]
    end

    test "swaps the infinities" do
      assert Scale.transform(%Continuous{transform: :reverse}, [:infinity, :neg_infinity, 2, nil]) ==
               [:neg_infinity, :infinity, -2, nil]
    end
  end

  describe "reciprocal" do
    test "places breaks falling as they rise, its minor breaks R's on them in that order" do
      # ggplot(mpg, aes(displ, hwy)) + geom_point() +
      #   scale_y_continuous(transform = scales::transform_reciprocal())
      assert axis(:reciprocal, column(Datasets.mpg(), :hwy)) ==
               {{0.019696969696969699, 0.086363636363636365},
                [{0.05, "20"}, {1 / 30, "30"}, {0.025, "40"}, {0.02, "50"}],
                [
                  0.06666666666666668,
                  0.058333333333333341,
                  0.041666666666666671,
                  0.029166666666666667,
                  0.022499999999999999
                ]}
    end

    test "places zero at plus infinity and either infinity at zero" do
      assert Scale.transform(%Continuous{transform: :reciprocal}, [0, 4, :infinity, :neg_infinity]) ==
               [:infinity, 0.25, 0.0, 0.0]
    end

    test "finds its breaks on the data's finite end where the extent reaches zero" do
      # data.frame(y = c(Inf, 4)) with scale_y_continuous(transform =
      # scales::transform_reciprocal(), expand = c(0, 0)): R's extended breaks on the one finite
      # end, 4, give it five times
      assert axis(:reciprocal, [:infinity, 4], expand: [mult: {0, 0}, add: {0, 0}]) ==
               {{0.0, 0.25}, List.duplicate({0.25, "4"}, 5), []}
    end
  end

  describe "datetime" do
    @utc {:datetime, "Etc/UTC", Calendar.UTCOnlyTimeZoneDatabase}
    @naive {:datetime, :naive, Calendar.UTCOnlyTimeZoneDatabase}

    # ggplot(u, aes(at, y)) + geom_point(), `at` 2024-03-09 20:17 and 2024-03-10 08:40 UTC: the
    # axis's continuous range, its breaks every three hours, labelled by the time alone, and its
    # minor breaks midway, less the breaks
    test "marks R's pretty() breaks for date-times, labelled by their step, and minor breaks" do
      values = [~U[2024-03-09 20:17:00Z], ~U[2024-03-10 08:40:00Z]]

      assert axis(@utc, values) ===
               {{1_710_013_191.0, 1_710_062_229.0},
                [
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

      naive = Enum.map(values, &DateTime.to_naive/1)
      assert axis(@naive, naive) == axis(@utc, values)
    end

    # one point at 2024-03-10 08:40:12 UTC: the axis 0.05 seconds either side, R's pretty()
    # widening it to whole seconds, and the one break inside labelled by its second
    test "a single date-time's axis has the one break, labelled by its second" do
      assert axis(@utc, [~U[2024-03-10 08:40:12Z]]) ==
               {{1_710_060_011.95, 1_710_060_012.05}, [{1_710_060_012.0, "12"}], []}
    end

    # scale_x_datetime(breaks = ...): R's format() writes the date alone where every break is a
    # midnight, else the date and the time to the second, a fraction of a second dropped
    test "breaks it did not choose are written as R's format() writes them" do
      values = [~U[2024-03-09 20:17:00Z], ~U[2024-03-10 08:40:00Z]]
      given = fn breaks -> axis(@utc, values, breaks: breaks) end

      {_extent, breaks, _minor} = given.([~U[2024-03-10 00:00:00Z], ~U[2024-03-10 06:30:00Z]])
      {_extent, midnights, _minor} = given.([~U[2024-03-09 00:00:00Z], ~U[2024-03-10 00:00:00Z]])

      {_extent, fraction, _minor} =
        given.([~U[2024-03-10 00:00:00.250000Z], ~U[2024-03-10 06:00:00Z]])

      {_extent, width, _minor} = axis(@utc, values, breaks: {:width, [hour: 5]})

      assert {breaks, midnights, fraction, width} ==
               {[
                  {1_710_028_800.0, "2024-03-10 00:00:00"},
                  {1_710_052_200.0, "2024-03-10 06:30:00"}
                ], [{1_710_028_800.0, "2024-03-10"}],
                [
                  {1_710_028_800.25, "2024-03-10 00:00:00"},
                  {1_710_050_400.0, "2024-03-10 06:00:00"}
                ],
                [
                  {1_710_028_800.0, "2024-03-10 00:00:00"},
                  {1_710_046_800.0, "2024-03-10 05:00:00"}
                ]}
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
    end

    # A scale on an axis no column maps keeps its zone unsettled, and takes naive date-times, as
    # its limits may be, as well as date-times in a zone.
    test "a scale no column has settled places a date-time of either kind" do
      unsettled = {:datetime, :default, Calendar.UTCOnlyTimeZoneDatabase}

      assert Transform.transform(unsettled, [~N[2024-03-10 08:40:12], ~U[2024-03-10 08:40:12Z]]) ===
               [1_710_060_012.0, 1_710_060_012.0]
    end

    test "a scale of one kind refuses a date-time of the other" do
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

  describe "a transformed scale's labels and limits" do
    test "a labels function is handed the breaks in data units" do
      # hwy with scale_y_log10(labels = function(b) ...): the function is handed 20, 30 and 40
      scale = %Continuous{
        transform: :log10,
        labels: fn breaks ->
          Enum.map(breaks, fn data ->
            data
            |> Float.round(9)
            |> inspect()
          end)
        end
      }

      trained = Scale.train(scale, Scale.transform(scale, column(Datasets.mpg(), :hwy)), :none)
      extent = Scale.dimension(trained)

      assert labels(trained, extent) == ["20.0", "30.0", "40.0"]
    end

    test "a labels function under reverse, sqrt and reciprocal is handed breaks in data units" do
      # ggplot(mtcars, aes(wt, mpg)) + geom_point() under scale_x_reverse(labels = f),
      # scale_x_sqrt(labels = f) and scale_x_continuous(transform = "reciprocal", labels = f): f
      # is handed 2, 3, 4 and 5, then their squares' roots squared, then 2 to 6
      handed = fn transform ->
        scale = %Continuous{
          transform: transform,
          labels: fn breaks -> Enum.map(breaks, &Float.to_string/1) end
        }

        values = Scale.transform(scale, column(Datasets.mtcars(), :wt))
        trained = Scale.train(scale, values, :none)
        labels(trained, Scale.dimension(trained))
      end

      assert Enum.map([:reverse, :sqrt, :reciprocal], handed) == [
               ["2.0", "3.0", "4.0", "5.0"],
               ["2.0000000000000004", "2.9999999999999996", "4.0", "5.000000000000001"],
               ["2.0", "3.0", "4.0", "5.0", "6.0"]
             ]
    end

    test "a labels function on a date axis is handed dates" do
      # scale_x_date(labels = function(dates) ...) is handed Date objects
      scale = %Continuous{
        transform: :date,
        labels: fn dates -> Enum.map(dates, &Date.to_iso8601/1) end
      }

      trained =
        Scale.train(scale, Scale.transform(scale, [~D[2020-01-01], ~D[2020-01-03]]), :none)

      extent = Scale.dimension(trained)

      assert labels(trained, extent) == ~w(2020-01-01 2020-01-02 2020-01-03)
    end

    test "a labels function on a date-time axis is handed date-times, to the second" do
      # scale_x_datetime(labels = function(b) ...) is handed POSIXct objects in the scale's zone
      scale = %Continuous{
        transform: {:datetime, "Etc/UTC", Calendar.UTCOnlyTimeZoneDatabase},
        labels: fn datetimes -> Enum.map(datetimes, &inspect/1) end
      }

      values = [~U[2024-03-09 20:17:00Z], ~U[2024-03-10 08:40:00Z]]
      trained = Scale.train(scale, Scale.transform(scale, values), :none)
      extent = Scale.dimension(trained)

      assert labels(trained, extent) ==
               Enum.map(
                 [
                   ~U[2024-03-09 21:00:00Z],
                   ~U[2024-03-10 00:00:00Z],
                   ~U[2024-03-10 03:00:00Z],
                   ~U[2024-03-10 06:00:00Z],
                   ~U[2024-03-10 09:00:00Z]
                 ],
                 &inspect/1
               )
    end

    test "a limit outside the transformation's domain cannot be placed, at either end" do
      # scale_y_log10(limits = c(0, 100)) fails in R: 'from' must be a finite number
      for limits <- [{0, 100}, {100, 0}] do
        scale = %Continuous{transform: :log10, limits: limits, range: {0.0, 2.0}}

        error = assert_raise ArgumentError, fn -> Scale.dimension(scale) end
        assert error.message =~ inspect(limits)
        assert error.message =~ "log10"
      end
    end

    test "limits are sorted once transformed, so either order names the same axis" do
      # ggplot(mtcars, aes(mpg, wt)) + geom_point() + scale_x_continuous(limits = c(20, 15)):
      # 14.75 to 20.25; under scale_x_reverse(), c(15, 20) and c(20, 15) both -20.25 to -14.75
      mpg = column(Datasets.mtcars(), :mpg)
      {identity_extent, _breaks, _minor} = axis(:identity, mpg, limits: {20, 15})
      {reverse_extent, _breaks, _minor} = axis(:reverse, mpg, limits: {15, 20})

      assert {identity_extent, reverse_extent} == {{14.75, 20.25}, {-20.25, -14.75}}
    end

    test "a labels function's refusal shows the breaks in data units" do
      scale = %Continuous{transform: :log10, labels: fn _breaks -> ["one"] end}
      trained = Scale.train(scale, Scale.transform(scale, column(Datasets.mpg(), :hwy)), :none)

      error =
        assert_raise ArgumentError, fn -> Scale.breaks(trained, Scale.dimension(trained)) end

      assert error.message =~ "[20.0"
    end
  end
end
