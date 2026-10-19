defmodule Giggly.Scale.TransformTest do
  use ExUnit.Case, async: true

  alias Giggly.{Datasets, Scale}
  alias Giggly.Scale.Continuous

  # Golden: every axis below is R's own, from R 4.6.1 with ggplot2 4.0.3 and scales 1.4.0 (the
  # image `giggly-r:ggplot2-4.0.3`): `ggplot_build()`'s panel params for the plot in the comment
  # above each, their continuous range, breaks inside it, labels, and minor breaks less the breaks
  # (which ggplot2's grid leaves out). They move only if ggplot2's transformations do. R writes a
  # log axis's labels from 1e5 up in scientific notation; Giggly writes them in plain decimals.

  # An axis of `values` on a continuous scale through `transform`: its extent, its breaks and its
  # minor breaks, as the assembly finds them.
  defp axis(transform, values, options \\ []) do
    scale = struct!(Continuous, [{:transform, transform} | options])
    trained = Scale.train(scale, Scale.transform(scale, values))
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
      trained = Scale.train(scale, Scale.transform(scale, [1, 10, 100]))
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
      assert Scale.transform(%Continuous{transform: :reciprocal}, [0, 4, :infinity, nil]) ==
               [:infinity, 0.25, 0.0, nil]
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

      trained = Scale.train(scale, Scale.transform(scale, column(Datasets.mpg(), :hwy)))
      extent = Scale.dimension(trained)

      assert labels(trained, extent) == ["20.0", "30.0", "40.0"]
    end

    test "a labels function on a date axis is handed dates" do
      # scale_x_date(labels = function(dates) ...) is handed Date objects
      scale = %Continuous{
        transform: :date,
        labels: fn dates -> Enum.map(dates, &Date.to_iso8601/1) end
      }

      trained = Scale.train(scale, Scale.transform(scale, [~D[2020-01-01], ~D[2020-01-03]]))
      extent = Scale.dimension(trained)

      assert labels(trained, extent) == ~w(2020-01-01 2020-01-02 2020-01-03)
    end

    test "a limit outside the transformation's domain cannot be placed" do
      # scale_y_log10(limits = c(0, 100)) fails in R: 'from' must be a finite number
      scale = %Continuous{transform: :log10, limits: {0, 100}, range: {0.0, 2.0}}

      error = assert_raise ArgumentError, fn -> Scale.dimension(scale) end
      assert error.message =~ "{0, 100}"
      assert error.message =~ "log10"
    end
  end
end
