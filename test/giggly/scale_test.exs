defmodule Giggly.ScaleTest do
  use ExUnit.Case, async: true

  alias Giggly.Scale

  # A new discrete alpha scale trained once on `values`.
  defp discrete_alpha(values) do
    :discrete
    |> Scale.new(:alpha)
    |> Scale.train(values)
  end

  # A new continuous colour scale trained once on `values`.
  defp gradient_scale(values) do
    :continuous
    |> Scale.new(:color)
    |> Scale.train(values)
  end

  # A new discrete colour scale trained once on `values`.
  defp hue_scale(values) do
    :discrete
    |> Scale.new(:color)
    |> Scale.train(values)
  end

  # A new scale of `kind` trained once on `values`.
  defp trained(kind, values) do
    kind
    |> Scale.new()
    |> Scale.train(values)
  end

  describe "kind/1 and kind/2" do
    test "a column's type decides its scale's kind, and a type with no scale yet gets none" do
      dtypes = [:integer, :float, :null, :string, :boolean, :atom, :category, :date, :time, :term]

      assert Enum.map(dtypes, &Scale.kind/1) == [
               :continuous,
               :continuous,
               :continuous,
               :discrete,
               :discrete,
               :discrete,
               :discrete,
               :date,
               :none,
               :none
             ]
    end

    test "a date has a scale on a position aesthetic and none yet on alpha" do
      assert {Scale.kind(:date, :x), Scale.kind(:date, :ymax), Scale.kind(:date, :alpha)} ===
               {:date, :date, :none}

      assert {Scale.kind(:float, :alpha), Scale.kind(:string, :alpha)} ===
               {:continuous, :discrete}
    end

    test "a colour or fill is discrete or continuous as any aesthetic is, and a date has none yet" do
      assert Enum.map([:string, :boolean, :atom, :category], fn dtype ->
               Scale.kind(dtype, :color)
             end) === [:discrete, :discrete, :discrete, :discrete]

      assert Enum.map([:integer, :float, :null, :date], fn dtype -> Scale.kind(dtype, :fill) end) ===
               [:continuous, :continuous, :continuous, :none]
    end
  end

  describe "train/2" do
    test "a continuous range spans the finite numbers only, across trainings" do
      scale =
        :continuous
        |> Scale.new()
        |> Scale.train([nil, 3, :infinity, 1.5])
        |> Scale.train([2])

      assert scale === %Scale.Continuous{
               range: {1.5, 3},
               transform: :identity,
               palette: :identity,
               na_value: nil,
               guide: :axis
             }
    end

    test "discrete levels are the distinct values sorted, nil last, across trainings" do
      scale =
        :discrete
        |> Scale.new()
        |> Scale.train(["b", nil, "a"])
        |> Scale.train(["c", "a"])

      assert scale === %Scale.Discrete{
               levels: ["a", "b", "c", nil],
               continuous_range: :none,
               palette: :identity,
               na_value: nil,
               guide: :axis
             }
    end

    # Golden: R 4.6.1's `levels(factor(c(10, 9, 100, NA)))` is `9 10 100`, `NA` kept last by
    # ggplot2's legend.
    test "a discrete scale takes numbers as levels, in order of value, nil last" do
      assert trained(:discrete, [10, 9, nil, 100, 9]).levels === [9, 10, 100, nil]
    end
  end

  describe "train_positions/2" do
    test "a discrete scale handed positions widens its continuous range, not its levels" do
      scale =
        :discrete
        |> trained(["b", "a"])
        |> Scale.train_positions([1, 2])
        |> Scale.train_positions([0.55, nil, 2.45])

      assert scale === %Scale.Discrete{
               levels: ["a", "b"],
               continuous_range: {0.55, 2.45},
               palette: :identity,
               na_value: nil,
               guide: :axis
             }
    end
  end

  describe "reset/1" do
    test "a continuous scale forgets its range, a discrete one its continuous range alone" do
      continuous = trained(:continuous, [1.0, 3.0])

      discrete =
        :discrete
        |> trained(["b", "a"])
        |> Scale.train_positions([0.55, 2.45])

      assert {Scale.reset(continuous), Scale.reset(discrete)} ===
               {%Scale.Continuous{
                  range: :none,
                  transform: :identity,
                  palette: :identity,
                  na_value: nil,
                  guide: :axis
                },
                %Scale.Discrete{
                  levels: ["a", "b"],
                  continuous_range: :none,
                  palette: :identity,
                  na_value: nil,
                  guide: :axis
                }}
    end
  end

  describe "map/2" do
    test "a discrete value is put at its level's position, counting from 1" do
      scale = trained(:discrete, ["6", "4", nil])

      assert Scale.map(scale, ["6", "4", "6", nil]) === [2, 1, 2, 3]
    end

    test "a continuous value is left as it is" do
      scale = trained(:continuous, [2.62, 2.875])

      assert Scale.map(scale, [2.62, 2.875]) === [2.62, 2.875]
    end
  end

  describe "dimension/1" do
    test "a continuous range is widened by 5% of its width at each end" do
      scale = trained(:continuous, [1, 3])

      assert Scale.dimension(scale) === {0.9, 3.1}
    end

    test "a range of zero width is widened as though its width were 1" do
      scale = trained(:continuous, [0])

      assert Scale.dimension(scale) === {-0.05, 0.05}
    end

    test "ends that differ only by rounding error, relative to their size, count as one value" do
      scale = trained(:continuous, [1000.0, 1000.0000000000001])

      assert Scale.dimension(scale) === {999.95, 1000.0500000000001}
    end

    test "an extent still zero wide once widened is its middle, both ends equal" do
      scale = trained(:continuous, [1.0e12])

      assert Scale.dimension(scale) === {1.0e12, 1.0e12}
    end

    test "an untrained continuous scale spans 0 to 1 before it is widened" do
      scale = Scale.new(:continuous)

      assert Scale.dimension(scale) === {-0.05, 1.05}
    end

    test "discrete levels at positions 1 to n are widened by 0.6" do
      scale = trained(:discrete, ["6", "4", "8"])

      assert Scale.dimension(scale) === {0.4, 3.6}
    end

    # Golden: ggplot2 4.0.3's x extents in R 4.6.1, for bars 0.9 wide on seven levels (`mpg`'s
    # classes) and 1.5 wide on three (`geom_col(width = 1.5)`).
    test "a continuous range widens the levels' extent where it reaches further, unwidened" do
      levels = Enum.map(1..7, fn level -> "level #{level}" end)

      narrow =
        :discrete
        |> trained(levels)
        |> Scale.train_positions([0.55, 7.45])

      wide =
        :discrete
        |> trained(["a", "b", "c"])
        |> Scale.train_positions([0.25, 3.75])

      assert {Scale.dimension(narrow), Scale.dimension(wide)} === {{0.4, 7.6}, {0.25, 3.75}}
    end
  end

  describe "breaks/2" do
    test "a continuous scale's breaks are its transformation's, labelled with shared decimals" do
      scale = trained(:continuous, [0, 10])
      extent = Scale.dimension(scale)

      assert Scale.breaks(scale, extent) ===
               [{0.0, "0.0"}, {2.5, "2.5"}, {5.0, "5.0"}, {7.5, "7.5"}, {10.0, "10.0"}]
    end

    test "breaks outside the extent are dropped, and whole breaks are labelled without decimals" do
      scale = trained(:continuous, [1.513, 5.424])
      extent = Scale.dimension(scale)

      assert Scale.breaks(scale, extent) ===
               [{2.0, "2"}, {3.0, "3"}, {4.0, "4"}, {5.0, "5"}]
    end

    test "a break exactly at an end of the extent is kept" do
      scale = trained(:continuous, [3, 17])

      assert Scale.breaks(scale, {0.0, 20.0}) ===
               [{0.0, "0"}, {5.0, "5"}, {10.0, "10"}, {15.0, "15"}, {20.0, "20"}]
    end

    test "an extent of zero width has one break, at its end" do
      scale = trained(:continuous, [1.0e16])
      extent = Scale.dimension(scale)

      assert Scale.breaks(scale, extent) === [{1.0e16, "10000000000000000"}]
    end

    test "an untrained continuous scale has no breaks" do
      scale = Scale.new(:continuous)

      assert Scale.breaks(scale, {-0.05, 1.05}) === []
    end

    test "a discrete scale has a break at each level, a missing level labelled NA" do
      scale = trained(:discrete, ["6", nil, "4"])
      extent = Scale.dimension(scale)

      assert Scale.breaks(scale, extent) === [{1, "4"}, {2, "6"}, {3, "NA"}]
    end
  end

  describe "minor_breaks/3" do
    test "a continuous scale's minor breaks fall midway between its breaks" do
      scale = trained(:continuous, [0, 10])
      extent = Scale.dimension(scale)
      breaks = Scale.breaks(scale, extent)

      assert Scale.minor_breaks(scale, breaks, extent) ===
               [1.25, 3.75, 6.25, 8.75]
    end

    test "minor breaks fall between the outermost breaks and the extent's ends too" do
      scale = trained(:continuous, [1.513, 5.424])
      extent = Scale.dimension(scale)
      breaks = Scale.breaks(scale, extent)

      assert Scale.minor_breaks(scale, breaks, extent) ===
               [1.5, 2.5, 3.5, 4.5, 5.5]
    end

    test "a minor break exactly at an end of the extent is kept" do
      scale = trained(:continuous, [0, 10])
      breaks = [{2.5, "2.5"}, {5.0, "5.0"}, {7.5, "7.5"}]

      assert Scale.minor_breaks(scale, breaks, {1.25, 8.75}) === [1.25, 3.75, 6.25, 8.75]
    end

    test "an axis with fewer than two breaks has no minor breaks" do
      scale = trained(:continuous, [1.0e16])
      extent = Scale.dimension(scale)
      breaks = Scale.breaks(scale, extent)

      assert Scale.minor_breaks(scale, breaks, extent) === []
    end

    test "a discrete scale has no minor breaks" do
      scale = trained(:discrete, ["a", "b", "c"])
      extent = Scale.dimension(scale)
      breaks = Scale.breaks(scale, extent)

      assert Scale.minor_breaks(scale, breaks, extent) === []
    end
  end

  # Golden throughout: R 4.6.1's `scales` 1.4.0 and ggplot2 4.0.3, printed to 17 significant
  # digits: `scales::rescale()`, `seq(0.1, 1, length.out = n)` and the alpha `layer_data()` of the
  # same values. They move only with R's arithmetic, or with ggplot2's default alpha range.
  describe "rescale/3" do
    test "a value moves linearly from one range to another, in R's order of operations" do
      rescaled =
        Enum.map([2, 4, 10, 6, 3.3], fn value -> Scale.rescale(value, {2, 10}, {0, 1}) end)

      assert rescaled === [0.0, 0.25, 1.0, 0.5, 0.16249999999999998]
    end

    test "a range of zero width puts every value at the middle of the other" do
      assert Scale.rescale(5, {5, 5}, {0, 1}) === 0.5
      assert Scale.rescale(5, {5, 5}, {0.1, 1.0}) === 0.55
    end
  end

  describe "map/2 through a palette" do
    test "a continuous alpha is its place in the range rescaled onto 0.1 to 1, a missing one nil" do
      scale =
        :continuous
        |> Scale.new(:alpha)
        |> Scale.train([2, 4, nil, 10, 6])

      assert Scale.map(scale, [2, 4, nil, 10, 6, 3.3, :nan]) ===
               [0.1, 0.325, nil, 1.0, 0.55, 0.24625, nil]
    end

    test "a continuous alpha of one value is the middle of the palette" do
      scale =
        :continuous
        |> Scale.new(:alpha)
        |> Scale.train([7, 7])

      assert Scale.map(scale, [7, 7]) === [0.55, 0.55]
    end

    test "a discrete alpha spreads its present levels evenly from 0.1 to 1, a missing one nil" do
      scale =
        :discrete
        |> Scale.new(:alpha)
        |> Scale.train(["b", "a", nil, "c", "a"])

      assert Scale.map(scale, ["b", "a", nil, "c", "a"]) === [0.55, 0.1, nil, 1.0, 0.1]
    end

    test "the spread is R's seq(), its middle values found by steps from the first" do
      levels = ~w(a b c d e f g)

      scale =
        :discrete
        |> Scale.new(:alpha)
        |> Scale.train(levels)

      assert Scale.map(scale, levels) ===
               [
                 0.1,
                 0.25,
                 0.4,
                 0.54999999999999993,
                 0.69999999999999996,
                 0.84999999999999998,
                 1.0
               ]
    end

    test "one level is the palette's start, two its ends, none at all leave only nil" do
      one = discrete_alpha(["a", "a"])
      two = discrete_alpha(["a", "b"])
      none = discrete_alpha([nil])

      assert {Scale.map(one, ["a"]), Scale.map(two, ["a", "b"]), Scale.map(none, [nil])} ===
               {[0.1], [0.1, 1.0], [nil]}
    end

    # A position scale's first training is reset before its second, so nothing a plot draws reads
    # its untrained range; only the scale itself pins it.
    test "a position scale is untrained, its palette the identity and its guide an axis" do
      assert {Scale.new(:continuous), Scale.new(:date), Scale.new(:discrete)} ===
               {%Scale.Continuous{
                  range: :none,
                  transform: :identity,
                  palette: :identity,
                  na_value: nil,
                  guide: :axis
                },
                %Scale.Continuous{
                  range: :none,
                  transform: :date,
                  palette: :identity,
                  na_value: nil,
                  guide: :axis
                },
                %Scale.Discrete{
                  levels: [],
                  continuous_range: :none,
                  palette: :identity,
                  na_value: nil,
                  guide: :axis
                }}
    end

    test "an alpha scale records ggplot2's default range and guide, untrained, the identity transformation" do
      assert {Scale.new(:continuous, :alpha), Scale.new(:discrete, :alpha)} ===
               {%Scale.Continuous{
                  range: :none,
                  transform: :identity,
                  palette: {:rescale, {0.1, 1.0}},
                  na_value: nil,
                  guide: :legend
                },
                %Scale.Discrete{
                  levels: [],
                  continuous_range: :none,
                  palette: {:sequence, {0.1, 1.0}},
                  na_value: nil,
                  guide: :legend
                }}
    end
  end

  # Golden: scales 1.4.0's `pal_hue()(n)` in R 4.6.1, through farver 2.1.2; the palette matched
  # R's for every count from 1 to 40. A count of 24 ends on a hue of exactly 360, and 40 on 366,
  # which R takes modulo 360 first. ggplot2's discrete colour scale maps `NA` to grey50.
  describe "map/2 through the hue palette" do
    test "a colour or fill scale records pal_hue()'s hues, chroma and luminance, NA grey50, a legend" do
      expected = %Scale.Discrete{
        levels: [],
        continuous_range: :none,
        palette: {:hue, %{hue: {15, 375}, chroma: 100, luminance: 65}},
        na_value: "#7F7F7F",
        guide: :legend
      }

      assert {Scale.new(:discrete, :color), Scale.new(:discrete, :fill)} === {expected, expected}
    end

    test "each present level takes its hue in level order, and a missing value grey50" do
      scale = hue_scale(["r", "4", nil, "f"])

      assert Scale.map(scale, ["f", nil, "4", "r", "4"]) ===
               ["#00BA38", "#7F7F7F", "#F8766D", "#619CFF", "#F8766D"]
    end

    test "the hues are spaced round the circle, its last share left off, as pal_hue() spaces them" do
      colours = fn count ->
        levels =
          Enum.map(1..count, fn index ->
            index
            |> Integer.to_string()
            |> String.pad_leading(2, "0")
          end)

        levels
        |> hue_scale()
        |> Scale.map(levels)
      end

      assert {colours.(1), colours.(2), colours.(7)} ===
               {["#F8766D"], ["#F8766D", "#00BFC4"],
                ["#F8766D", "#C49A00", "#53B400", "#00C094", "#00B6EB", "#A58AFF", "#FB61D7"]}

      assert colours.(24) === [
               "#F8766D",
               "#ED813E",
               "#DE8C00",
               "#CD9600",
               "#B79F00",
               "#9DA700",
               "#7CAE00",
               "#49B500",
               "#00BA38",
               "#00BE67",
               "#00C08B",
               "#00C1A9",
               "#00BFC4",
               "#00BBDC",
               "#00B4F0",
               "#00A9FF",
               "#619CFF",
               "#9F8CFF",
               "#C77CFF",
               "#E36EF6",
               "#F564E3",
               "#FF61CC",
               "#FF64B0",
               "#FF6C91"
             ]

      forty = colours.(40)

      assert Enum.take(forty, -3) === ["#FF65AA", "#FF6A98", "#FD7083"]
    end

    test "a scale of missing values alone maps them all to grey50" do
      scale = hue_scale([nil])

      assert Scale.map(scale, [nil, nil]) === ["#7F7F7F", "#7F7F7F"]
    end
  end

  # Golden: ggplot2 4.0.3's `scale_colour_continuous()` in R 4.6.1, `layer_data()`'s colours and
  # `pal_seq_gradient("#132B43", "#56B1F7")`, through scales 1.4.0 and farver 2.1.2; a missing
  # value is grey50.
  describe "map/2 through the gradient" do
    test "a colour or fill scale records ggplot2's gradient, NA grey50, and a colour bar" do
      expected = %Scale.Continuous{
        range: :none,
        transform: :identity,
        palette: {:gradient, {"#132B43", "#56B1F7"}},
        na_value: "#7F7F7F",
        guide: :colorbar
      }

      assert {Scale.new(:continuous, :color), Scale.new(:continuous, :fill)} ===
               {expected, expected}
    end

    test "each value is its place in the range along the gradient, blended in Lab, a missing one grey50" do
      scale = gradient_scale([1, 2.5, nil, 4])

      assert Scale.map(scale, [1, 2.5, nil, 4, :nan]) ===
               ["#132B43", "#336A98", "#7F7F7F", "#56B1F7", "#7F7F7F"]
    end

    test "places between the ends are blended as R's approxfun blends L*, a* and b*" do
      scale = gradient_scale([0, 1])

      assert Scale.map(scale, [0.25, 0.75]) === ["#22496C", "#448DC6"]
    end

    test "a scale of one value maps it to the middle of the gradient" do
      scale = gradient_scale([3, 3])

      assert Scale.map(scale, [3]) === ["#336A98"]
    end
  end

  # Golden: ggplot2 4.0.3's colour bar for mpg's `colour = cty` in its gradient form, R 4.6.1:
  # `extract_decor()`'s 15 values over the range 9 to 35 and `extract_params()`'s places of the
  # breaks 10 to 35, printed to 17 digits.
  describe "samples/2 and places/2" do
    test "samples are R's seq() over the trained range" do
      scale = gradient_scale([9, 35])

      assert Scale.samples(scale, 15) === [
               9,
               10.857142857142858,
               12.714285714285715,
               14.571428571428571,
               16.428571428571431,
               18.285714285714285,
               20.142857142857142,
               22.0,
               23.857142857142858,
               25.714285714285715,
               27.571428571428573,
               29.428571428571431,
               31.285714285714285,
               33.142857142857139,
               35
             ]
    end

    test "a value's place runs from 0 at the range's low end to 1 at its high" do
      scale = gradient_scale([9, 35])

      assert Scale.places(scale, [10.0, 15.0, 20.0, 25.0, 30.0, 35.0]) === [
               0.038461538461538464,
               0.23076923076923078,
               0.42307692307692307,
               0.6153846153846154,
               0.8076923076923077,
               1.0
             ]
    end
  end

  describe "legend_breaks/1" do
    test "a continuous scale's are its breaks inside the trained range, labelled as an axis's" do
      scale =
        :continuous
        |> Scale.new(:alpha)
        |> Scale.train([1999, 2008])

      assert Scale.legend_breaks(scale) === [
               {2000.0, "2000"},
               {2002.0, "2002"},
               {2004.0, "2004"},
               {2006.0, "2006"},
               {2008.0, "2008"}
             ]
    end

    test "a range of zero width has one break, its value, and an untrained scale none" do
      one =
        :continuous
        |> Scale.new(:alpha)
        |> Scale.train([7, 7])

      untrained = Scale.new(:continuous, :alpha)

      assert {Scale.legend_breaks(one), Scale.legend_breaks(untrained)} === {[{7.0, "7"}], []}
    end

    test "a discrete scale's are its levels, a missing one last and labelled NA" do
      scale = discrete_alpha(["b", nil, "a"])

      assert Scale.legend_breaks(scale) === [{"a", "a"}, {"b", "b"}, {nil, "NA"}]
    end
  end
end
