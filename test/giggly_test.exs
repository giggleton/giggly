defmodule GigglyTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Plot}

  doctest Giggly

  @rows %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "qsec" => [16.46, 17.02]}
  @mixed_rows %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]}
  @mpg_rows %{
    "displ" => [1.8, 2.0, 5.7],
    "hwy" => [29, 26, 17],
    "class" => ["compact", "compact", "suv"]
  }

  # The scale_shape reference page's `dsmall`: the rows of diamonds R 4.6.1's
  # `sample(nrow(diamonds), 100)` picks after `set.seed(596)`, counted from 1.
  @diamond_sample [
    25_666,
    38_189,
    6816,
    23_077,
    19_736,
    25_700,
    11_808,
    25_189,
    26_344,
    4071,
    45_742,
    25_297,
    52_984,
    14_612,
    48_306,
    19_199,
    38_194,
    37_228,
    48_850,
    49_734,
    18_386,
    14_200,
    10_993,
    24_601,
    7011,
    34_308,
    6583,
    38_595,
    30_236,
    1051,
    8079,
    31_287,
    1565,
    30_482,
    44_169,
    50_061,
    13_023,
    48_715,
    16_918,
    4754,
    43_963,
    43_370,
    2115,
    11_166,
    9734,
    31_412,
    31_654,
    45_124,
    49_949,
    51_312,
    41_254,
    39_717,
    20_773,
    13_151,
    19_964,
    12_688,
    6155,
    31_857,
    995,
    32_150,
    46_525,
    40_773,
    52_088,
    46_509,
    15_601,
    45_156,
    43_334,
    43_429,
    37_708,
    30_408,
    19_060,
    32_426,
    11_867,
    24_140,
    8179,
    51_399,
    49_507,
    35_248,
    49_967,
    42_223,
    29_727,
    33_565,
    41_530,
    39_904,
    49_348,
    12_696,
    15_966,
    18_558,
    8009,
    8575,
    13_142,
    32_231,
    6305,
    39_036,
    53_530,
    34_813,
    36_021,
    47_384,
    43_849,
    23_120
  ]

  # The scale_date reference page's `df`: the 30 days to 2026-10-19, latest first, rather than to
  # the day it runs, and the prices R 4.6.1's runif(30) gives after set.seed(1).
  @last_month %{
    "date" => Enum.map(0..29, fn back -> Date.add(~D[2026-10-19], -back) end),
    "price" => [
      0.26550866314209998,
      0.37212389963679016,
      0.57285336335189641,
      0.90820778999477625,
      0.2016819310374558,
      0.89838968496769667,
      0.94467526860535145,
      0.66079779248684645,
      0.62911404389888048,
      0.061786270467564464,
      0.20597457489930093,
      0.17655675252899528,
      0.68702284665778279,
      0.38410371821373701,
      0.76984141999855638,
      0.49769924208521843,
      0.71761850826442242,
      0.9919060948304832,
      0.38003517943434417,
      0.77744522131979465,
      0.93470523110590875,
      0.21214252128265798,
      0.65167376608587801,
      0.12555509596131742,
      0.26722066872753203,
      0.3861140925437212,
      0.013390333158895373,
      0.38238795707002282,
      0.86969084572046995,
      0.34034899668768048
    ]
  }

  describe "layer_data/2" do
    test "a layer's mapping takes an aesthetic the plot also maps" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(%{y: :qsec})

      frame = Giggly.layer_data(plot)
      assert DataFrame.pull(frame, :y) == [16.46, 17.02]
    end

    test "layers are counted in the order they were added" do
      plot =
        @rows
        |> Plot.new(%{x: :wt})
        |> Plot.geom_point(%{y: :mpg})
        |> Plot.geom_point(%{y: :qsec})

      frame = Giggly.layer_data(plot, 1)
      assert DataFrame.pull(frame, :y) == [16.46, 17.02]
    end

    test "a layer the plot does not have is refused rather than read as nothing" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot, 1) end
      assert error.message =~ "no layer 1"
    end

    test "a column no scale can place yet is refused, naming the layer, the column and its type" do
      rows = %{"time" => [~T[09:00:00], ~T[17:30:00]], "mpg" => [21.0, 22.8]}

      plot =
        rows
        |> Plot.new(%{x: :time, y: :mpg})
        |> Plot.geom_point()

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
      assert error.message =~ "index 0"
      assert error.message =~ ":x"
      assert error.message =~ ~s("time")
      assert error.message =~ ":time"
    end

    test "a date mapped to alpha is refused, its scale not having arrived" do
      plot =
        %{"day" => [~D[2026-10-12], ~D[2026-10-13]], "mpg" => [21.0, 22.8]}
        |> Plot.new(%{x: :mpg, y: :mpg, alpha: :day})
        |> Plot.geom_point()

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
      assert error.message =~ ":alpha"
      assert error.message =~ ":date"
    end

    test "a date column beside a column of numbers on one axis is refused, an axis having one scale" do
      plot =
        %{"day" => [~D[2026-10-12], ~D[2026-10-13]], "mpg" => [21.0, 22.8]}
        |> Plot.new(%{y: :mpg})
        |> Plot.geom_point(%{x: :day})
        |> Plot.geom_point(%{x: :mpg})

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot, 1) end
      assert error.message =~ "date"
      assert error.message =~ "continuous"
    end

    # R stores a date as a double, its days since 1970-01-01, and ggplot2's layer data holds them.
    test "a date on an axis is placed at its days since 1970-01-01, a missing one missing" do
      plot =
        %{
          "day" => [~D[1969-12-31], ~D[1970-01-01], nil, ~D[2015-04-01]],
          "y" => [1.0, 2.0, 3.0, 4.0]
        }
        |> Plot.new(%{x: :day, y: :y})
        |> Plot.geom_point()

      frame = Giggly.layer_data(plot)

      assert DataFrame.pull(frame, :x) === [-1.0, 0.0, nil, 16_526.0]
    end

    test "a layer whose axis column disagrees in kind with an earlier layer's is refused" do
      plot =
        @mixed_rows
        |> Plot.new(%{y: :mpg})
        |> Plot.geom_point(%{x: :wt})
        |> Plot.geom_point(%{x: :cyl})

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
      # The later layer is blamed, first and with its own column; the earlier one is named after
      # it as what it disagrees with.
      assert String.starts_with?(error.message, ~s(the layer at index 1 maps :x to "cyl"))
      assert error.message =~ ~s("wt")
    end

    test "a layer that remaps an axis is checked by its own column, not the plot's" do
      plot =
        @mixed_rows
        |> Plot.new(%{x: :cyl, y: :mpg})
        |> Plot.geom_point(%{x: :wt})
        |> Plot.geom_point(%{x: :mpg})

      assert %{x: %Giggly.Scale.Continuous{}} = Giggly.panel_scales(plot)
    end

    test "an aesthetic that is not a position is not checked against the scales" do
      rows = %{
        "day" => [~D[2026-10-12], ~D[2026-10-13]],
        "wt" => [2.62, 2.875],
        "mpg" => [21.0, 22.8]
      }

      plot =
        rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(%{group: :day})

      frame = Giggly.layer_data(plot)
      assert [1, 2] = DataFrame.pull(frame, :group)
    end

    test "a negative index is refused rather than counted from the end" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot, -1) end
      assert error.message =~ "no layer -1"
    end
  end

  # Golden throughout: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same plot, a layer drawing
  # a table of its own. It moves with how a layer's table is evaluated or given its panels.
  describe "layer_data/2, numbers written as integers and as floats" do
    # R has one kind of number, so `facet_wrap(~n)` over `c(4, 4.0, 6)` draws two panels, `4` and
    # `6`, and `group = n` makes two groups.
    test "4 and 4.0 in one column are one value, to the facet and to grouping alike" do
      frame =
        %{"x" => [1.0, 2.0, 3.0], "y" => [1.0, 2.0, 3.0], "n" => [4, 4.0, 6]}
        |> Plot.new(%{x: :x, y: :y, group: :n})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:n)
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :panel), DataFrame.pull(frame, :group)} ===
               {[1, 1, 2], [1, 1, 2]}
    end
  end

  describe "layer_data/2, factor()" do
    @factor_rows %{
      "x" => [1.0, 2.0, 3.0, 4.0],
      "y" => [1.0, 2.0, 3.0, 4.0],
      "v" => [10, 9, 100, nil],
      "w" => [4, 4, 6, 6],
      "b" => [true, false, true, false]
    }

    # Golden: ggplot2 4.0.3 in R 4.6.1 colours `colour = factor(v)` over `v = c(10, 9, 100, NA)`
    # #00BA38, #F8766D, #619CFF and grey50, groups the rows 2, 1, 3, 4, and labels its legend
    # `factor(v)`, keys 9, 10, 100 and NA.
    test "a factor of numbers is a discrete colour, its levels in order of value, NA last" do
      plot =
        @factor_rows
        |> Plot.new(%{x: :x, y: :y, colour: {:factor, [:v]}})
        |> Plot.geom_point()

      frame = Giggly.layer_data(plot)
      [legend] = Giggly.Assembly.run(plot).legends

      assert {DataFrame.pull(frame, :color), DataFrame.pull(frame, :group), legend.title,
              Enum.map(legend.keys, fn key -> key.label end)} ===
               {["#00BA38", "#F8766D", "#619CFF", "#7F7F7F"], [2, 1, 3, 4], "factor(v)",
                ["9", "10", "100", "NA"]}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 places `aes(factor(w), y)` over `w = c(4L, 4L, 6L, 6L)` at
    # 1, 1, 2, 2, counts `geom_bar()` of it 2 and 2, and titles the axis `factor(w)`.
    test "a factor of numbers on x is a discrete axis, counted and titled as R does" do
      points =
        @factor_rows
        |> Plot.new(%{x: {:factor, [:w]}, y: :y})
        |> Plot.geom_point()
        |> Giggly.layer_data()

      bars =
        @factor_rows
        |> Plot.new(%{x: {:factor, [:w]}})
        |> Plot.geom_bar()

      counted = Giggly.layer_data(bars)

      assert {DataFrame.pull(points, :x), DataFrame.pull(counted, :count),
              Giggly.Assembly.run(bars).guide_titles} ===
               {[1, 1, 2, 2], [2.0, 2.0], %{x: "factor(w)", y: "count"}}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 labels a colour legend of `TRUE` and `FALSE` `FALSE`, `TRUE`.
    test "a column of true and false is labelled as R writes it" do
      [legend] =
        @factor_rows
        |> Plot.new(%{x: :x, y: :y, colour: :b})
        |> Plot.geom_point()
        |> Giggly.Assembly.run()
        |> Map.fetch!(:legends)

      assert Enum.map(legend.keys, fn key -> key.label end) === ["FALSE", "TRUE"]
    end
  end

  describe "layer_data/2, a layer's own table" do
    test "the layer draws its own table with the plot's mapping" do
      plot =
        %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => [6, 4]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.geom_point(data: %{"wt" => [3.0, 4.0], "mpg" => [15.0, 16.0]})

      frame = Giggly.layer_data(plot, 1)
      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :y)} == {[3.0, 4.0], [15.0, 16.0]}
    end

    test "groups are numbered within each layer's table, and one colour scale spans the tables" do
      plot =
        %{"x" => [1.0, 2.0], "y" => [1.0, 2.0], "k" => ["b", "c"]}
        |> Plot.new(%{x: :x, y: :y, colour: :k})
        |> Plot.geom_point()
        |> Plot.geom_point(data: %{"x" => [3.0, 4.0], "y" => [3.0, 4.0], "k" => ["a", "c"]})

      first = Giggly.layer_data(plot, 0)
      second = Giggly.layer_data(plot, 1)

      assert {DataFrame.pull(first, :color), DataFrame.pull(first, :group)} ==
               {["#00BA38", "#619CFF"], [1, 2]}

      assert {DataFrame.pull(second, :color), DataFrame.pull(second, :group)} ==
               {["#F8766D", "#619CFF"], [1, 2]}
    end

    test "the facet makes its panels from the plot's data and every layer's table" do
      plot =
        %{"wt" => [2.62, 2.875, 2.32], "mpg" => [21.0, 22.8, 22.8], "cyl" => [6, 4, 4]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(data: %{"wt" => [1.0, 2.0], "mpg" => [10.0, 11.0], "cyl" => [4, 4]})
        |> Plot.geom_point(data: %{"wt" => [5.0, 6.0], "mpg" => [12.0, 13.0]})
        |> Plot.facet_wrap(:cyl)

      own = Giggly.layer_data(plot, 0)
      repeated = Giggly.layer_data(plot, 1)

      assert DataFrame.pull(own, :panel) == [1, 1]

      assert {DataFrame.pull(repeated, :x), DataFrame.pull(repeated, :panel)} ==
               {[5.0, 6.0, 5.0, 6.0], [1, 1, 2, 2]}
    end

    test "each layer's columns are typed from its own table, so an axis refuses a second kind" do
      plot =
        %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.geom_point(data: %{"wt" => ["a", "b"], "mpg" => [1.0, 2.0]})

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
      assert error.message =~ "index 1"
      assert error.message =~ "discrete"
    end
  end

  # Golden throughout: ggplot2 4.0.3's `layer_data()` for the same plot, in R 4.6.1.
  describe "layer_data/2, an annotation" do
    test "a single value is given to every annotation the lists make" do
      frame =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.annotate(:text, x: [2, 3, 4, 5], y: 25, label: "Some text")
        |> Giggly.layer_data(1)

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :y), DataFrame.pull(frame, :label),
              DataFrame.pull(frame, :group)} ===
               {[2.0, 3.0, 4.0, 5.0], [25.0, 25.0, 25.0, 25.0], List.duplicate("Some text", 4),
                [-1, -1, -1, -1]}
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 gives `annotate("text", x = 1, y = 1, label =
    # "a", alpha = c(0.2, 0.8))` two rows, alpha 0.2 and 0.8, and likewise two for colours
    # `c("red", "blue")` and for a rectangle's fills `c("red", "blue")`.
    test "a list of alphas, colours or fills alone makes one annotation per value" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      alphas =
        plot
        |> Plot.annotate(:text, x: 1, y: 1, label: "a", alpha: [0.2, 0.8])
        |> Giggly.layer_data()

      colours =
        plot
        |> Plot.annotate(:text, x: 1, y: 1, label: "a", colour: ["red", "blue"])
        |> Giggly.layer_data()

      fills =
        plot
        |> Plot.annotate(:rect, xmin: 0, xmax: 1, ymin: 0, ymax: 1, fill: ["red", "blue"])
        |> Giggly.layer_data()

      assert {DataFrame.pull(alphas, :alpha), DataFrame.pull(colours, :color),
              DataFrame.pull(fills, :fill)} ===
               {[0.2, 0.8], ["#FF0000", "#0000FF"], ["#FF0000", "#0000FF"]}
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 gives `annotate("rect", ..., fill = c(NA,
    # "red"))` the fills `NA` and `red`, and `annotate("point", ..., colour = c("red", NA))` the
    # colours `red` and `NA`; vdiffr's drawing of the rectangles has only the red one.
    test "a list's :none beside a colour is a missing colour, as R's NA is" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      fills =
        plot
        |> Plot.annotate(:rect,
          xmin: [1, 3],
          xmax: [2, 4],
          ymin: 1,
          ymax: 2,
          fill: [:none, "red"]
        )
        |> Giggly.layer_data()

      colours =
        plot
        |> Plot.annotate(:point, x: [1, 2], y: 3, colour: ["red", :none])
        |> Giggly.layer_data()

      assert {DataFrame.pull(fills, :fill), DataFrame.pull(colours, :color)} ===
               {[nil, "#FF0000"], ["#FF0000", nil]}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 draws `annotate("text", x = 1, y = 1, label = TRUE)` as `TRUE`.
    test "a label of true or false is taken, and written as R writes it" do
      svg =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:text, x: 3, y: 21, label: true)
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()

      assert svg =~ ">TRUE</text>"
    end

    test "lists are taken in step, and a set aesthetic's list alone makes as many annotations" do
      in_step =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:text, x: [2, 3], y: [20, 21], label: ["my label", "label 2"])
        |> Giggly.layer_data()

      assert {DataFrame.pull(in_step, :x), DataFrame.pull(in_step, :y),
              DataFrame.pull(in_step, :label)} ===
               {[2.0, 3.0], [20.0, 21.0], ["my label", "label 2"]}

      by_label =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:text, x: 1, y: 1, label: ["a", "b"])
        |> Giggly.layer_data()

      assert {DataFrame.pull(by_label, :x), DataFrame.pull(by_label, :label)} ===
               {[1.0, 1.0], ["a", "b"]}
    end

    test "a list of one value is one value, given to every annotation" do
      frame =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:text, x: [2], y: [20, 21], label: ["a"])
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :label)} ===
               {[2.0, 2.0], ["a", "a"]}
    end

    test "an empty list makes no annotations, and draws nothing" do
      frame =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.annotate(:text, x: [], y: 10, label: "a")
        |> Giggly.layer_data(1)

      assert DataFrame.row_count(frame) == 0
    end

    test "a list may hold infinite positions beside finite ones" do
      frame =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:rect,
          xmin: [:neg_infinity, 3],
          xmax: [2, :infinity],
          ymin: :neg_infinity,
          ymax: :infinity
        )
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :xmin), DataFrame.pull(frame, :xmax)} ===
               {[:neg_infinity, 3.0], [2.0, :infinity]}
    end

    # Golden: ggplot2 4.0.3's `layer_data()` and x scale range in R 4.6.1 for the same plot. R's
    # dates count days from 1970, so 2000-07-01 is 11139 on the axis, which runs from 10957 to
    # 11323, 2000-01-01 to 2001-01-01.
    test "a date is placed on a date axis" do
      plot =
        [d: [~D[2000-01-01], ~D[2001-01-01]], v: [1.0, 2.0]]
        |> Plot.new(%{x: :d, y: :v})
        |> Plot.geom_line()
        |> Plot.annotate(:text, x: ~D[2000-07-01], y: 1.5, label: "mid")

      frame = Giggly.layer_data(plot, 1)
      assert DataFrame.pull(frame, :x) === [11_139.0]
      assert Giggly.panel_scales(plot).x.range === {10_957.0, 11_323.0}
    end

    test "colours and alphas are set row by row, in step with the positions" do
      frame =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:point, x: [1, 2], y: 10, colour: ["red", "blue"], alpha: [0.2, 0.8])
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :color), DataFrame.pull(frame, :alpha)} ===
               {["#FF0000", "#0000FF"], [0.2, 0.8]}
    end

    # R sets a line's colours on its rows once they are in order of x, so the second colour goes to
    # the second x, not to the row it was given beside.
    test "a line's colours are set on its rows once they are in order, as ggplot2 sets them" do
      frame =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:line, x: [1, 3, 2], y: [10, 30, 20], colour: ["red", "green", "blue"])
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :y), DataFrame.pull(frame, :color)} ===
               {[1.0, 2.0, 3.0], [10.0, 20.0, 30.0], ["#FF0000", "#008000", "#0000FF"]}
    end

    test "a line takes its orientation, and its rows go in order of y" do
      frame =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:line, x: [1, 3, 2], y: [10, 30, 20], orientation: :y)
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :y) === [10.0, 20.0, 30.0]
    end

    test "a path keeps its rows' order and takes its width" do
      frame =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:path, x: [1, 3, 2], y: [10, 30, 20], linewidth: 2)
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :linewidth)} ===
               {[1.0, 3.0, 2.0], [2.0, 2.0, 2.0]}
    end

    test "bars at one x overlap, each from 0 to its y, as an annotation places them" do
      frame =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:col, x: [1, 1, 2], y: [2, 3, 4], fill: "red")
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :xmin), DataFrame.pull(frame, :ymin),
              DataFrame.pull(frame, :ymax)} ===
               {[0.55000000000000004, 0.55000000000000004, 1.55], [0.0, 0.0, 0.0],
                [2.0, 3.0, 4.0]}

      bar =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:bar, x: [1, 2], y: [-2, 3])
        |> Giggly.layer_data()

      assert {DataFrame.pull(bar, :ymin), DataFrame.pull(bar, :ymax)} ===
               {[-2.0, 0.0], [0.0, 3.0]}
    end

    test "a rectangle's corners may be infinite" do
      frame =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:rect,
          xmin: :neg_infinity,
          xmax: 2,
          ymin: :neg_infinity,
          ymax: :infinity
        )
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :xmin), DataFrame.pull(frame, :xmax),
              DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax)} ===
               {[:neg_infinity], [2.0], [:neg_infinity], [:infinity]}
    end

    test "it takes nothing from the plot's mapping, so maps no colour and makes no groups" do
      frame =
        @mixed_rows
        |> Plot.new(%{x: :wt, y: :mpg, colour: :cyl})
        |> Plot.geom_point()
        |> Plot.annotate(:text, x: 4, y: 25, label: "a")
        |> Giggly.layer_data(1)

      assert DataFrame.names(frame) == [:x, :y, :panel, :group, :label]
      assert DataFrame.pull(frame, :group) == [-1]
    end

    test "under a facet it is drawn in every panel" do
      frame =
        @mixed_rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:cyl)
        |> Plot.annotate(:text, x: 4, y: 25, label: "a")
        |> Giggly.layer_data(1)

      assert {DataFrame.pull(frame, :panel), DataFrame.pull(frame, :label)} ==
               {[1, 2], ["a", "a"]}
    end

    # ggplot2 fails here too: "Aesthetics must be either length 1 or the same as the data (6)".
    test "under a facet of several panels, an aesthetic set to a list raises when run" do
      plot =
        @mixed_rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:cyl)
        |> Plot.annotate(:text, x: [2, 3], y: [20, 21], label: ["a", "b"])

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot, 1) end
      assert error.message =~ "the layer at index 1 sets :label to 2 values"
      assert error.message =~ "draws 4 rows"
    end

    test "under a facet of one panel, an aesthetic's list is set row by row" do
      frame =
        %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "am" => [1, 1]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:am)
        |> Plot.annotate(:text, x: [2, 3], y: [20, 21], label: ["a", "b"])
        |> Giggly.layer_data(1)

      assert DataFrame.pull(frame, :label) == ["a", "b"]
    end

    # Golden: mpg's `class` against `hwy`, whose seven classes put "suv" seventh; a value the data
    # lacks is placed after them.
    test "a string is placed on a discrete axis, at its level or after the data's" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, y: :hwy})
        |> Plot.geom_point()

      suv =
        plot
        |> Plot.annotate(:text, x: "suv", y: 40, label: "a")
        |> Giggly.layer_data(1)

      beyond =
        plot
        |> Plot.annotate(:text, x: "zzz", y: 40, label: "a")
        |> Giggly.layer_data(1)

      assert {DataFrame.pull(suv, :x), DataFrame.pull(beyond, :x), DataFrame.pull(beyond, :group)} ==
               {[7], [8], [1]}
    end
  end

  # Golden throughout: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same plot.
  describe "layer_data/2, for geom_rect" do
    test "each rectangle keeps its corners as mapped, reversed or missing ones too" do
      frame =
        %{
          "a" => [1.0, 5.0, nil],
          "b" => [2.0, 3.0, 3.0],
          "c" => [0.0, 2.0, 0.0],
          "d" => [4.0, 1.0, 1.0]
        }
        |> Plot.new(%{xmin: :a, xmax: :b, ymin: :c, ymax: :d})
        |> Plot.geom_rect()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :xmin), DataFrame.pull(frame, :xmax),
              DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax)} ==
               {[1.0, 5.0, nil], [2.0, 3.0, 3.0], [0.0, 2.0, 0.0], [4.0, 1.0, 1.0]}
    end

    test "corners set for every rectangle sit in every row beside the plot's positions" do
      frame =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_rect(xmin: 3, xmax: 4.2, ymin: 12, ymax: 21, alpha: 0.2)
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :xmin),
              DataFrame.pull(frame, :ymax), DataFrame.pull(frame, :alpha)} ===
               {[2.62, 2.875], [3.0, 3.0], [21.0, 21.0], [0.2, 0.2]}
    end
  end

  # Golden throughout: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same plot, printed to 17
  # significant digits. It moves with ggplot2's bar geometry or stacking.
  describe "layer_data/2, for geom_col" do
    test "each bar runs from 0 to its y, 0.9 wide and centred on its level" do
      frame =
        %{"trt" => ["a", "b", "c"], "outcome" => [2.3, 1.9, 3.2]}
        |> Plot.new(%{x: :trt, y: :outcome})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert edges(frame) === %{
               xmin: [0.55000000000000004, 1.55000000000000004, 2.54999999999999982],
               xmax: [1.45, 2.4500000000000002, 3.4500000000000002],
               ymin: [0.0, 0.0, 0.0],
               ymax: [2.3, 1.9, 3.2],
               y: [2.3, 1.9, 3.2]
             }
    end

    test "on a continuous axis a bar is 0.9 of the closest pair's gap, not counting from zero" do
      frame =
        %{"x" => [0.5, 10.0], "y" => [1.0, 2.0]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :xmin), DataFrame.pull(frame, :xmax)} ===
               {[-3.7750000000000004, 5.7249999999999996],
                [4.7750000000000004, 14.2750000000000004]}
    end

    test "bars at one x stack upward in group order, the highest group at the bottom" do
      frame =
        %{"x" => ["a", "a", "a", "b"], "y" => [1.0, 2.0, 4.0, 3.0], "g" => ["p", "q", "r", "p"]}
        |> Plot.new(%{x: :x, y: :y, group: :g})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax),
              DataFrame.pull(frame, :y)} ===
               {[6.0, 4.0, 0.0, 0.0], [7.0, 6.0, 4.0, 3.0], [7.0, 6.0, 4.0, 3.0]}
    end

    test "a bar below zero stacks downward from zero, apart from those above it" do
      frame =
        %{"x" => ["a", "a", "b", "b"], "y" => [1.0, 2.0, 3.0, -1.0], "g" => ["p", "q", "p", "q"]}
        |> Plot.new(%{x: :x, y: :y, group: :g})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax),
              DataFrame.pull(frame, :y)} ===
               {[2.0, 0.0, 0.0, -1.0], [3.0, 2.0, 3.0, 0.0], [3.0, 2.0, 3.0, 0.0]}
    end

    test "with every x different nothing stacks, so a bar below zero keeps its y" do
      frame =
        %{"x" => ["a", "b"], "y" => [2.0, -1.0]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax),
              DataFrame.pull(frame, :y)} === {[0.0, -1.0], [2.0, 0.0], [2.0, -1.0]}
    end

    test "an x shared only across panels still turns stacking on, each panel stacked alone" do
      frame =
        %{"x" => ["a", "a", "b"], "y" => [2.0, -1.0, 3.0], "f" => ["u", "v", "v"]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_col()
        |> Plot.facet_wrap(:f)
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax),
              DataFrame.pull(frame, :y)} === {[0.0, -1.0, 0.0], [2.0, 0.0, 3.0], [2.0, 0.0, 3.0]}
    end

    test "a stacked row missing its y loses its x and edges and stacks as nothing" do
      frame =
        %{"x" => ["a", "a", "b"], "y" => [2.0, nil, 3.0], "g" => ["p", "q", "p"]}
        |> Plot.new(%{x: :x, y: :y, group: :g})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert edges(frame) === %{
               xmin: [0.55000000000000004, nil, 1.55000000000000004],
               xmax: [1.45, nil, 2.4500000000000002],
               ymin: [0.0, nil, 0.0],
               ymax: [2.0, nil, 3.0],
               y: [2.0, 0.0, 3.0]
             }

      assert DataFrame.pull(frame, :x) === [1, nil, 2]
    end
  end

  # Golden throughout: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same plot, on the same
  # `mpg` where it is used, printed to 17 significant digits. It moves with ggplot2's default alpha
  # scales: a continuous column onto 0.1 to 1, a discrete one spread from 0.1 to 1.
  describe "layer_data/2, mapping alpha" do
    @alpha_rows %{
      "x" => [1, 2, 3, 4, 5],
      "y" => [1, 2, 3, 4, 5],
      "a" => [2.0, 4.0, nil, 10.0, 6.0],
      "s" => ["b", "a", nil, "c", "a"]
    }

    test "a continuous alpha is each value's place in the range on 0.1 to 1, a missing one nil" do
      frame =
        @alpha_rows
        |> Plot.new(%{x: :x, y: :y, alpha: :a})
        |> Plot.geom_point()
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :alpha) === [0.1, 0.325, nil, 1.0, 0.55]
    end

    test "a discrete alpha spreads its levels from 0.1 to 1 and groups by them" do
      frame =
        @alpha_rows
        |> Plot.new(%{x: :x, y: :y, alpha: :s})
        |> Plot.geom_point()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :alpha), DataFrame.pull(frame, :group)} ===
               {[0.55, 0.1, nil, 1.0, 0.1], [2, 1, 4, 3, 1]}
    end

    test "groups are numbered y before alpha, as ggplot2's aes() takes y first" do
      frame =
        %{"x" => [1, 2, 3, 4], "y" => ["q", "p", "q", "p"], "s" => ["b", "a", "a", "b"]}
        |> Plot.new(%{x: :x, y: :y, alpha: :s})
        |> Plot.geom_point()
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :group) === [4, 1, 3, 2]
    end

    test "every layer's alpha trains one scale, so each layer's values sit in the whole range" do
      frame =
        @alpha_rows
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{alpha: :a})
        |> Plot.geom_point(%{alpha: :x})
        |> Giggly.layer_data(1)

      assert DataFrame.pull(frame, :alpha) === [0.1, 0.2, 0.3, 0.4, 0.5]
    end

    test "an alpha the layer sets wins over the plot's mapping of it" do
      frame =
        @alpha_rows
        |> Plot.new(%{x: :x, y: :y, alpha: :a})
        |> Plot.geom_point(alpha: 0.3)
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :alpha) === List.duplicate(0.3, 5)
    end

    test "counted bars keep a discrete alpha, each bar shaded by its group's level" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, alpha: :drv})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :count), DataFrame.pull(frame, :alpha)} ===
               {[5.0, 12.0, 35.0, 3.0, 38.0, 11.0, 33.0, 4.0, 22.0, 9.0, 51.0, 11.0],
                [1.0, 0.1, 0.55, 0.1, 0.55, 0.55, 0.1, 0.1, 0.55, 1.0, 0.1, 1.0]}
    end

    test "counting drops an alpha that varies within a bar, so its bars have none" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, alpha: :year})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      refute :alpha in DataFrame.names(frame)
    end

    test "an alpha column no scale can map is refused, naming the layer, the column and its type" do
      rows = %{"x" => [1, 2], "y" => [1, 2], "day" => [~D[2026-10-12], ~D[2026-10-13]]}

      plot =
        rows
        |> Plot.new(%{x: :x, y: :y, alpha: :day})
        |> Plot.geom_point()

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
      assert error.message =~ "index 0"
      assert error.message =~ ":alpha"
      assert error.message =~ ~s("day")
      assert error.message =~ ":date"
    end

    test "layers whose alpha columns disagree in kind are refused, since alpha has one scale" do
      plot =
        @alpha_rows
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{alpha: :a})
        |> Plot.geom_point(%{alpha: :s})

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
      assert error.message =~ "index 1"
      assert error.message =~ "index 0"
      assert error.message =~ "an aesthetic has one scale"
    end
  end

  # Golden throughout: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same plot, on the same
  # `mpg` where it is used, printed to 17 significant digits. It moves with `stat_count()` or the
  # bar geometry.
  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1, its colours scales 1.4.0's `pal_hue()`.
  describe "layer_data/2, mapping colour" do
    test "a discrete colour is each level's hue, a missing one grey50, and groups by them" do
      frame =
        %{"x" => [1, 2, 3, 4], "y" => [1, 2, 3, 4], "g" => ["b", "a", nil, "a"]}
        |> Plot.new(%{x: :x, y: :y, colour: :g})
        |> Plot.geom_point()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :color), DataFrame.pull(frame, :group)} ===
               {["#00BFC4", "#F8766D", "#7F7F7F", "#F8766D"], [2, 1, 3, 1]}
    end

    # ggplot2 lays a layer's mapping over the plot's as `defaults(layer$mapping, plot$mapping)`, so
    # it evaluates the layer's colour before the plot's x, and numbers groups colour first.
    test "groups are numbered by a layer's own aesthetics before those it takes from the plot" do
      rows = %{"x" => ["a", "b", "a", "b"], "y" => [1, 2, 3, 4], "g" => ["q", "q", "p", "p"]}

      in_layer =
        rows
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{colour: :g})
        |> Giggly.layer_data()

      in_plot =
        rows
        |> Plot.new(%{x: :x, y: :y, colour: :g})
        |> Plot.geom_point()
        |> Giggly.layer_data()

      assert {DataFrame.pull(in_layer, :group), DataFrame.pull(in_plot, :group)} ===
               {[3, 4, 1, 2], [2, 4, 1, 3]}
    end

    test "a continuous colour or fill is each value's place along the gradient, a missing one grey50" do
      rows = %{"x" => [1, 2, 3, 4], "y" => [2, 3, 1, 4], "v" => [1, 2.5, nil, 4]}

      points =
        rows
        |> Plot.new(%{x: :x, y: :y, colour: :v})
        |> Plot.geom_point()
        |> Giggly.layer_data()

      columns =
        rows
        |> Plot.new(%{x: :x, y: :y, fill: :v})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(points, :color), DataFrame.pull(columns, :fill)} ===
               {["#132B43", "#336A98", "#7F7F7F", "#56B1F7"],
                ["#132B43", "#336A98", "#7F7F7F", "#56B1F7"]}
    end

    test "a colour mapped to dates is refused when the plot is run, until its scale arrives" do
      plot =
        %{"x" => [1, 2], "y" => [1, 2], "d" => [~D[2020-01-01], ~D[2020-02-01]]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{colour: :d})

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
      assert error.message =~ "maps :color to \"d\", a :date column, which no scale can place yet"
    end
  end

  # Golden throughout: ggplot2 4.0.3's `layer_data()` and `get_guide_data()` in R 4.6.1 for the
  # same plot on the same rows, each shape R's number for the name held here.
  describe "layer_data/2 and the legend, mapping shape" do
    @drives %{"x" => [1, 2, 3, 4], "y" => [4, 3, 2, 1], "drv" => ["f", "4", "r", "f"]}
    @missing %{"x" => [1, 2, 3, 4, 5], "y" => [1, 2, 3, 4, 5], "g" => ["a", "b", nil, "c", "a"]}

    test "a discrete shape gives its levels six shapes in order, solid or open, and groups by them" do
      plot =
        @drives
        |> Plot.new(%{x: :x, y: :y, shape: :drv})
        |> Plot.geom_point()

      groups =
        plot
        |> Giggly.layer_data()
        |> DataFrame.pull(:group)

      assert groups === [2, 1, 3, 2]

      assert {shapes_and_keys(&Function.identity/1),
              shapes_and_keys(fn plot -> Plot.scale_shape_discrete(plot, solid: false) end)} ===
               {{[:triangle, :circle_small, :square, :triangle],
                 [{"4", :circle_small}, {"f", :triangle}, {"r", :square}]},
                {[:triangle_open, :circle_open, :square_open, :triangle_open],
                 [{"4", :circle_open}, {"f", :triangle_open}, {"r", :square_open}]}}
    end

    test "a manual scale's shapes go to the levels in order, by number or name, a map's by value" do
      manual = fn options ->
        shapes_and_keys(fn plot -> Plot.scale_shape_manual(plot, options) end)
      end

      assert {manual.(values: [1, 2, 0]), manual.(values: [:triangle_open, :square, :circle])} ===
               {{[:triangle_open, :circle_open, :square_open, :triangle_open],
                 [{"4", :circle_open}, {"f", :triangle_open}, {"r", :square_open}]},
                {[:square, :triangle_open, :circle, :square],
                 [{"4", :triangle_open}, {"f", :square}, {"r", :circle}]}}

      assert {manual.(values: %{"r" => 17, "f" => 1}),
              manual.(values: [1, 2, 0], breaks: ["r", "f"])} ===
               {{[:circle_open, nil, :triangle, :circle_open],
                 [{"f", :circle_open}, {"r", :triangle}]},
                {[:triangle_open, nil, :circle_open, :triangle_open],
                 [{"r", :circle_open}, {"f", :triangle_open}]}}
    end

    test "a manual shape of :none leaves its rows unshaped, its key drawn in none, as R's NA" do
      assert shapes_and_keys(fn plot -> Plot.scale_shape_manual(plot, values: [1, :none, 0]) end) ===
               {[nil, :circle_open, :square_open, nil],
                [{"4", :circle_open}, {"f", :none}, {"r", :square_open}]}
    end

    test "breaks choose the keys, and limits the values shown, one outside them unshaped" do
      assert {shapes_and_keys(fn plot -> Plot.scale_shape_discrete(plot, breaks: ["r", "4"]) end),
              shapes_and_keys(fn plot -> Plot.scale_shape_discrete(plot, limits: ["r", "f"]) end),
              shapes_and_keys(fn plot -> Plot.lims(plot, shape: ["r", "f"]) end)} ===
               {{[:triangle, :circle_small, :square, :triangle],
                 [{"r", :square}, {"4", :circle_small}]},
                {[:triangle, nil, :circle_small, :triangle],
                 [{"r", :circle_small}, {"f", :triangle}]},
                {[:triangle, nil, :circle_small, :triangle],
                 [{"r", :circle_small}, {"f", :triangle}]}}
    end

    test "a missing value is unshaped, its NA key last, unless na_value: gives it a shape" do
      missing = fn scaled -> shapes_and_keys(scaled, @missing, :g) end

      assert missing.(&Function.identity/1) ===
               {[:circle_small, :triangle, nil, :square, :circle_small],
                [{"a", :circle_small}, {"b", :triangle}, {"c", :square}, {"NA", nil}]}

      assert {missing.(fn plot -> Plot.scale_shape_discrete(plot, na_value: 4) end),
              missing.(fn plot ->
                Plot.scale_shape_manual(plot, values: [1, 2, 0], na_value: 8)
              end)} ===
               {{[:circle_small, :triangle, :cross, :square, :circle_small],
                 [{"a", :circle_small}, {"b", :triangle}, {"c", :square}, {"NA", :cross}]},
                {[:circle_open, :triangle_open, :asterisk, :square_open, :circle_open],
                 [
                   {"a", :circle_open},
                   {"b", :triangle_open},
                   {"c", :square_open},
                   {"NA", :asterisk}
                 ]}}
    end

    test "a shape and a colour of one column are one legend, each key in both" do
      plot =
        @drives
        |> Plot.new(%{x: :x, y: :y, shape: :drv, colour: :drv})
        |> Plot.geom_point()

      [legend] = Giggly.Assembly.run(plot).legends

      assert {legend.aesthetics, Enum.map(legend.keys, fn key -> {key.label, key.values} end)} ===
               {[:color, :shape],
                [
                  {"4", %{color: "#F8766D", shape: :circle_small}},
                  {"f", %{color: "#00BA38", shape: :triangle}},
                  {"r", %{color: "#619CFF", shape: :square}}
                ]}
    end

    # ggplot2 4.0.3 aborts for each: "A continuous variable cannot be mapped to the shape
    # aesthetic."
    test "a continuous or a date column mapped to shape is refused when run, for points or counts" do
      rows = %{"x" => [1, 2], "y" => [1, 2], "day" => [~D[2026-10-12], ~D[2026-10-13]]}

      scaled = fn plot ->
        plot
        |> Plot.geom_point()
        |> Plot.scale_shape_discrete()
      end

      for {column, add, shown} <- [
            {:y, &Plot.geom_point/1, ~s("y", a :integer)},
            {:x, &Plot.geom_count/1, ~s("x", a :integer)},
            {:day, &Plot.geom_point/1, ~s("day", a :date)},
            {:y, scaled, ~s("y", a :integer)}
          ] do
        plot =
          rows
          |> Plot.new(%{x: :x, y: :y, shape: column})
          |> add.()

        error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
        assert error.message =~ "the layer at index 0 maps :shape to #{shown} column"
        assert error.message =~ "a shape scale is discrete"
      end
    end
  end

  # Golden throughout: ggplot2 4.0.3's `layer_data()` and `get_guide_data()` in R 4.6.1 for the
  # same plot on the same rows, printed to 17 significant digits, each line type R writes as the
  # dash pattern held here (`"solid"` `{}`, `"22"` `{2, 2}`, `"dotted"`, `"13"` and 3 `{1, 3}`,
  # `"dashed"` and 2 `{4, 4}`, `"3313"` `{3, 3, 1, 3}`, `NA` `nil`), a line's rows in the order
  # ggplot2's lines put them in.
  describe "layer_data/2 and the legend, mapping line type and width" do
    @series %{
      "x" => [1, 2, 1, 2, 1, 2],
      "y" => [1, 2, 2, 3, 3, 4],
      "g" => ["b", "b", "a", "a", "c", "c"]
    }
    @series_missing %{
      "x" => [1, 2, 1, 2, 1, 2],
      "y" => [1, 2, 2, 3, 3, 4],
      "g" => ["a", "a", nil, nil, "b", "b"]
    }
    @widths %{"x" => [1, 2, 3, 4], "y" => [1, 3, 2, 4], "w" => [2, 4.5, 3, 7]}
    @bars %{"x" => ["p", "q", "r"], "y" => [1, 2, 3], "w" => [1, 2, 4]}

    test "a discrete line type gives its levels R's line types in order, and groups by them" do
      plot =
        @series
        |> Plot.new(%{x: :x, y: :y, linetype: :g})
        |> Plot.geom_line()

      groups =
        plot
        |> Giggly.layer_data()
        |> DataFrame.pull(:group)

      assert {groups, values_and_keys(plot, :linetype)} ===
               {[1, 1, 2, 2, 3, 3],
                {[{}, {}, {2, 2}, {2, 2}, {4, 2}, {4, 2}],
                 [{"a", {}}, {"b", {2, 2}}, {"c", {4, 2}}]}}
    end

    test "limits choose the values shown, one outside them missing, and breaks the keys" do
      assert {line_types(fn plot ->
                Plot.scale_linetype_discrete(plot, limits: ["c", "a"], breaks: ["a", "c"])
              end), line_types(fn plot -> Plot.lims(plot, linetype: ["c", "b"]) end)} ===
               {{[{2, 2}, {2, 2}, nil, nil, {}, {}], [{"a", {2, 2}}, {"c", {}}]},
                {[nil, nil, {2, 2}, {2, 2}, {}, {}], [{"c", {}}, {"b", {2, 2}}]}}
    end

    test "a manual scale's line types go to the levels in order, by name, number or pattern, a map's by value" do
      manual = fn options ->
        line_types(fn plot -> Plot.scale_linetype_manual(plot, options) end)
      end

      assert {manual.(values: [:dotted, :dashed, {3, 3, 1, 3}]), manual.(values: [2, 3, 6]),
              manual.(values: %{"c" => :longdash, "a" => {1, 3}})} ===
               {{[{1, 3}, {1, 3}, {4, 4}, {4, 4}, {3, 3, 1, 3}, {3, 3, 1, 3}],
                 [{"a", {1, 3}}, {"b", {4, 4}}, {"c", {3, 3, 1, 3}}]},
                {[{4, 4}, {4, 4}, {1, 3}, {1, 3}, {2, 2, 6, 2}, {2, 2, 6, 2}],
                 [{"a", {4, 4}}, {"b", {1, 3}}, {"c", {2, 2, 6, 2}}]},
                {[{1, 3}, {1, 3}, nil, nil, {7, 3}, {7, 3}], [{"a", {1, 3}}, {"c", {7, 3}}]}}
    end

    # ggplot2 4.0.3's `manual_scale()` names a list by its breaks after choosing its limits, so the
    # limits stay every level: `scale_colour_manual(values = c("red", "blue", "green"), breaks =
    # c("c", "a"))` leaves `b` grey50 and its keys `c` and `a`, and two values for the three levels,
    # colour, shape or line type alike, fail, "Insufficient values in manual scale. 3 needed but
    # only 2 provided."
    test "a manual list named by breaks leaves the scale its levels, so too few values raise" do
      colored = fn options ->
        @series
        |> Plot.new(%{x: :x, y: :y, colour: :g})
        |> Plot.geom_line()
        |> Plot.scale_color_manual(options)
      end

      plot = colored.(values: ["red", "blue", "green"], breaks: ["c", "a"])

      assert values_and_keys(plot, :color) ===
               {["#0000FF", "#0000FF", "#7F7F7F", "#7F7F7F", "#FF0000", "#FF0000"],
                [{"c", "#FF0000"}, {"a", "#0000FF"}]}

      shaped =
        %{"x" => [1, 2, 3, 4], "y" => [4, 3, 2, 1], "drv" => ["f", "4", "r", "f"]}
        |> Plot.new(%{x: :x, y: :y, shape: :drv})
        |> Plot.geom_point()
        |> Plot.scale_shape_manual(values: [1, 2], breaks: ["r", "f"])

      typed =
        @series
        |> Plot.new(%{x: :x, y: :y, linetype: :g})
        |> Plot.geom_line()
        |> Plot.scale_linetype_manual(values: [:dotted, {1, 3}], breaks: ["c", "a"])

      for plot <- [colored.(values: ["red", "blue"], breaks: ["c", "a"]), shaped, typed] do
        error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
        assert error.message =~ "a manual scale needs a value for each of its 3 levels, but has 2"
      end
    end

    test "a missing value has no line type, its NA key last, unless na_value: gives it one" do
      missing = fn scaled ->
        @series_missing
        |> Plot.new(%{x: :x, y: :y, linetype: :g})
        |> Plot.geom_line()
        |> scaled.()
        |> values_and_keys(:linetype)
      end

      assert {missing.(&Function.identity/1),
              missing.(fn plot -> Plot.scale_linetype_discrete(plot, na_value: :dotted) end)} ===
               {{[{}, {}, {2, 2}, {2, 2}, nil, nil], [{"a", {}}, {"b", {2, 2}}, {"NA", nil}]},
                {[{}, {}, {2, 2}, {2, 2}, {1, 3}, {1, 3}],
                 [{"a", {}}, {"b", {2, 2}}, {"NA", {1, 3}}]}}
    end

    test "a line type and a colour of one column are one legend, each key in both" do
      [legend] =
        @series
        |> Plot.new(%{x: :x, y: :y, linetype: :g, colour: :g})
        |> Plot.geom_line()
        |> Giggly.Assembly.run()
        |> Map.fetch!(:legends)

      assert {legend.aesthetics, Enum.map(legend.keys, fn key -> {key.label, key.values} end)} ===
               {[:color, :linetype],
                [
                  {"a", %{color: "#F8766D", linetype: {}}},
                  {"b", %{color: "#00BA38", linetype: {2, 2}}},
                  {"c", %{color: "#619CFF", linetype: {4, 2}}}
                ]}
    end

    test "a continuous width runs from 1 to 6 mm over the limits, a key for each break, none outside them" do
      widths = fn scaled ->
        @widths
        |> Plot.new(%{x: :x, y: :y, linewidth: :w})
        |> Plot.geom_line()
        |> scaled.()
        |> values_and_keys(:linewidth)
      end

      assert {widths.(&Function.identity/1),
              widths.(fn plot ->
                Plot.scale_linewidth_continuous(plot,
                  range: {0, 4},
                  limits: {0, 5},
                  breaks: [0, 2.5, 5]
                )
              end), widths.(fn plot -> Plot.lims(plot, linewidth: {0, 10}) end)} ===
               {{[1.0, 3.5, 2.0, 6.0],
                 [{"2", 1.0}, {"3", 2.0}, {"4", 3.0}, {"5", 4.0}, {"6", 5.0}, {"7", 6.0}]},
                {[1.6, 3.6, 2.4, nil], [{"0.0", 0.0}, {"2.5", 2.0}, {"5.0", 4.0}]},
                {[2.0, 3.25, 2.5, 4.5],
                 [
                   {"0.0", 1.0},
                   {"2.5", 2.25},
                   {"5.0", 3.5},
                   {"7.5", 4.75},
                   {"10.0", 6.0}
                 ]}}
    end

    test "a discrete width spreads its levels from 2 to 6 mm, a missing one none unless na_value: gives one" do
      assert {@series
              |> Plot.new(%{x: :x, y: :y, linewidth: :g})
              |> Plot.geom_line()
              |> values_and_keys(:linewidth),
              @series_missing
              |> Plot.new(%{x: :x, y: :y, linewidth: :g})
              |> Plot.geom_line()
              |> Plot.scale_linewidth_discrete(range: {1, 3}, na_value: 0.25)
              |> values_and_keys(:linewidth)} ===
               {{[2.0, 2.0, 4.0, 4.0, 6.0, 6.0], [{"a", 2.0}, {"b", 4.0}, {"c", 6.0}]},
                {[1.0, 1.0, 3.0, 3.0, 0.25, 0.25], [{"a", 1.0}, {"b", 3.0}, {"NA", 0.25}]}}
    end

    test "a bar's border takes a mapped width, and a width and line type of one column are one legend" do
      bordered = fn mapping ->
        @bars
        |> Plot.new(mapping)
        |> Plot.geom_col(colour: "black")
      end

      [legend] =
        %{x: :x, y: :y, linewidth: :x, linetype: :x}
        |> bordered.()
        |> Giggly.Assembly.run()
        |> Map.fetch!(:legends)

      widths =
        %{x: :x, y: :y, linewidth: :w}
        |> bordered.()
        |> values_and_keys(:linewidth)

      assert {widths, legend.aesthetics,
              Enum.map(legend.keys, fn key -> {key.label, key.values} end)} ===
               {{[1.0, 2.6666666666666665, 6.0],
                 [{"1", 1.0}, {"2", 2.6666666666666665}, {"3", 4.333333333333333}, {"4", 6.0}]},
                [:linetype, :linewidth],
                [
                  {"p", %{linetype: {}, linewidth: 2.0}},
                  {"q", %{linetype: {2, 2}, linewidth: 4.0}},
                  {"r", %{linetype: {4, 2}, linewidth: 6.0}}
                ]}
    end

    # ggplot2 4.0.3 aborts for each: "A continuous variable cannot be mapped to the linetype
    # aesthetic."
    test "a continuous or a date column mapped to line type is refused when run" do
      rows = %{"x" => [1, 2], "y" => [1, 2], "day" => [~D[2026-10-12], ~D[2026-10-13]]}

      for {column, shown} <- [{:y, ~s("y", a :integer)}, {:day, ~s("day", a :date)}] do
        plot =
          rows
          |> Plot.new(%{x: :x, y: :y, linetype: column})
          |> Plot.geom_line()

        error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
        assert error.message =~ "the layer at index 0 maps :linetype to #{shown} column"
        assert error.message =~ "a line type scale is discrete, since line types have no order"
      end
    end
  end

  describe "layer_data/2 and the legends under a plot's colour, fill or alpha scale" do
    @cylinders %{"mpg" => [22.8, 24.4, 32.4], "wt" => [2.32, 3.19, 2.2], "cyl" => [4.0, 4.0, 4.0]}

    # Golden: ggplot2 4.0.3's lims page in R 4.6.1, `lims(colour = c("4", "6", "8"))` over the
    # rows of mtcars with four cylinders: their colour the first of three hues, the legend's keys
    # 4, 6 and 8, a point drawn only in 4's, as vdiffr's drawing has twelve circles for eleven rows.
    test "a colour scale's limits give the legend a key for each, glyphs only where data is" do
      plot =
        @cylinders
        |> Plot.new(%{x: :mpg, y: :wt, colour: {:factor, [:cyl]}})
        |> Plot.geom_point()
        |> Plot.lims(colour: [4, 6, 8])

      [legend] = Giggly.Assembly.run(plot).legends
      [layer] = legend.layers
      frame = Giggly.layer_data(plot)
      colors = DataFrame.pull(frame, :color)

      assert {colors, Enum.map(legend.keys, fn key -> {key.label, key.values.color} end),
              layer.draws} ===
               {["#F8766D", "#F8766D", "#F8766D"],
                [{"4", "#F8766D"}, {"6", "#00BA38"}, {"8", "#619CFF"}], [true, false, false]}
    end

    # Golden: ggplot2 4.0.3's `keep_key_data()` in R 4.6.1, `scale_colour_hue(limits = c("4",
    # NA))` over the values 4, 6 and 8: the legend's keys 4 and NA, a point drawn in both, as
    # vdiffr's drawing has five circles for three rows, since 6 and 8, outside the limits, map to
    # the missing value.
    test "a layer draws in the NA key where it holds a value no key shows" do
      plot =
        %{"x" => [1, 2, 3], "y" => [1, 2, 3], "v" => ["4", "6", "8"]}
        |> Plot.new(%{x: :x, y: :y, colour: :v})
        |> Plot.geom_point()
        |> Plot.scale_color_hue(limits: ["4", nil])

      [legend] = Giggly.Assembly.run(plot).legends
      [layer] = legend.layers

      assert {Enum.map(legend.keys, fn key -> key.label end), layer.draws} ===
               {["4", "NA"], [true, true]}
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 under `na.value = NA`: the missing value's
    # colour `NA` under `scale_colour_hue()`, its fill `NA` under `scale_fill_gradient()`.
    test "a value its scale maps to :none is missing in the layer's table, as R's is NA" do
      rows = %{"x" => [1, 2, 3], "y" => [1, 2, 3], "v" => ["a", nil, "b"], "z" => [1, nil, 2]}

      hue =
        rows
        |> Plot.new(%{x: :x, y: :y, colour: :v})
        |> Plot.geom_point()
        |> Plot.scale_color_hue(na_value: :none)

      gradient =
        rows
        |> Plot.new(%{x: :x, y: :y, fill: :z})
        |> Plot.geom_col()
        |> Plot.scale_fill_gradient(na_value: :none)

      colors =
        hue
        |> Giggly.layer_data()
        |> DataFrame.pull(:color)

      fills =
        gradient
        |> Giggly.layer_data()
        |> DataFrame.pull(:fill)

      assert {colors, fills} === {["#F8766D", nil, "#00BFC4"], ["#132B43", nil, "#56B1F7"]}
    end

    # Golden: the legends' backgrounds in ggplot2 4.0.3's drawings of the same plots through
    # vdiffr 1.0.9 (R 4.6.1), whose rectangles these match: with no labels and a title narrower
    # than a key, a legend and a colour bar are each a key and the legend margin either side, 28.24
    # points; with labels and a title wider than the bar and its labels, a colour bar is the title
    # and the margins, 96.55. They move with the legend's layout or its place.
    test "a guide is as wide as its keys, labels or title need, the labels' room only with labels" do
      backgrounds = fn plot ->
        plot
        |> to_svg()
        |> String.split("\n")
        |> Enum.filter(fn line -> String.ends_with?(line, "stroke: none; fill: #FFFFFF;' />") end)
      end

      mtcars = Plot.new(Giggly.Datasets.mtcars(), %{x: :mpg, y: :wt})

      legend =
        mtcars
        |> Plot.geom_point(%{colour: {:factor, [:cyl]}})
        |> Plot.labs(colour: "c")
        |> Plot.scale_color_discrete(labels: :none)

      bar =
        mtcars
        |> Plot.geom_point(%{colour: :disp})
        |> Plot.labs(colour: "c")
        |> Plot.scale_color_continuous(labels: :none)

      labelled =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, colour: :cty})
        |> Plot.geom_point()
        |> Plot.labs(colour: "a much wider title")

      assert {backgrounds.(legend), backgrounds.(bar), backgrounds.(labelled)} ===
               {[
                  "<rect x='686.28' y='236.23' width='28.24' height='78.13' " <>
                    "style='stroke-width: 1.07; stroke: none; fill: #FFFFFF;' />"
                ],
                [
                  "<rect x='686.28' y='218.95' width='28.24' height='112.69' " <>
                    "style='stroke-width: 1.07; stroke: none; fill: #FFFFFF;' />"
                ],
                [
                  "<rect x='617.97' y='218.95' width='96.55' height='112.69' " <>
                    "style='stroke-width: 1.07; stroke: none; fill: #FFFFFF;' />"
                ]}
    end

    test "a scale's name titles its legend over a label, whichever comes first" do
      plot =
        @cylinders
        |> Plot.new(%{x: :mpg, y: :wt, fill: {:factor, [:cyl]}})
        |> Plot.geom_col()
        |> Plot.labs(fill: "from labs")
        |> Plot.scale_fill_hue(name: "from the scale")

      [legend] = Giggly.Assembly.run(plot).legends
      assert legend.title === "from the scale"
    end

    # ggplot2 4.0.3 in R 4.6.1 refuses `scale_colour_manual()` over a column of numbers
    # ("Continuous value supplied to a discrete scale") and `scale_colour_gradient()` over
    # `factor(cyl)` ("Discrete value supplied to a continuous scale").
    test "a column of a kind the plot's scale does not take is refused when the plot is run" do
      discrete =
        @cylinders
        |> Plot.new(%{x: :mpg, y: :wt, colour: :cyl})
        |> Plot.geom_point()
        |> Plot.scale_color_manual(values: ["red"])

      continuous =
        @cylinders
        |> Plot.new(%{x: :mpg, y: :wt})
        |> Plot.geom_point(%{alpha: {:factor, [:cyl]}})
        |> Plot.scale_alpha_continuous()

      for {plot, scale, column} <- [
            {discrete, "color scale is discrete", ~s(maps :color to "cyl", a continuous column)},
            {continuous, "alpha scale is continuous",
             ~s(maps :alpha to {:factor, ["cyl"]}, a discrete column)}
          ] do
        error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
        assert error.message =~ scale
        assert error.message =~ column
      end
    end
  end

  describe "layer_data/2, expressions and constants" do
    # Golden: ggplot2 4.0.3's `layer_data()` for `ggplot(d, aes(cty, hwy / cty)) +
    # geom_point(aes(colour = "smooth"))` in R 4.6.1 puts every row in group 1. The values it
    # computes are `Giggly.Mapping`'s doctest.
    test "a string constant is one level in every row, so the layer's rows are one group" do
      frame =
        %{"hwy" => [29, 24], "cty" => [18, 16]}
        |> Plot.new(%{x: :cty, y: {&Kernel.//2, [:hwy, :cty]}})
        |> Plot.geom_point(%{colour: {:constant, "smooth"}})
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :group) === [1, 1]
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 puts every point of `aes(1, hwy)` at x 1, and colours every
    # one of `aes(colour = 7)` #336A98, the gradient's middle, one value having no range.
    test "a number constant is that position in every row, and its colour the gradient's middle" do
      frame =
        @rows
        |> Plot.new(%{x: 1, y: :mpg, colour: 7})
        |> Plot.geom_point()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :color)} ===
               {[1, 1], ["#336A98", "#336A98"]}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 groups `aes(toupper(class), hwy)` 2, 1, 2.
    test "an expression that computes strings places its rows on a discrete axis, and groups them" do
      frame =
        %{"class" => ["suv", "compact", "suv"], "hwy" => [20, 29, 18]}
        |> Plot.new(%{x: {&String.upcase/1, [:class]}, y: :hwy})
        |> Plot.geom_point()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :group)} === {[2, 1, 2], [2, 1, 2]}
    end

    test "an expression whose results are of two types is refused when run, naming its aesthetic" do
      either = fn value -> if value == 1, do: 1, else: "a" end

      plot =
        %{"x" => [1, 2], "y" => [1, 2]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{colour: {either, [:x]}})

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
      assert error.message =~ ":color"
    end

    test "an axis's kinds disagreeing is refused naming each value as the plot holds it" do
      plot =
        %{"class" => ["suv", "compact"], "hwy" => [20, 29], "displ" => [1.8, 2.0]}
        |> Plot.new(%{y: :hwy})
        |> Plot.geom_point(%{x: :displ})
        |> Plot.geom_point(%{x: {&String.upcase/1, [:class]}})

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
      assert error.message =~ ~s(index 1 maps :x to {&String.upcase/1, ["class"]})
      assert error.message =~ ~s(index 0 maps :x to "displ")
    end

    test "a constant no scale can place is refused when run, naming the constant" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(%{colour: ~D[2020-01-01]})

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end

      assert error.message =~
               "maps :color to {:constant, ~D[2020-01-01]}, a :date column, which no scale"
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 counts `aes(class, weight = w * 2)` 8 for compact and 6 for
    # suv.
    test "a computed weight is summed" do
      frame =
        %{"class" => ["suv", "suv", "compact"], "w" => [1, 2, 4]}
        |> Plot.new(%{x: :class, weight: {&Kernel.*/2, [:w, 2]}})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :count) === [8.0, 6.0]
    end

    # ggplot2 4.0.3 in R 4.6.1 warns "Computation failed in `stat_count()`" for `geom_bar(aes(class,
    # weight = as.character(hwy)))`, `rowsum()` refusing a weight that is not a number, and draws
    # nothing of the layer; Giggly cannot warn, so it refuses, as it refuses a column at the call.
    # Golden: ggplot2 4.0.3 in R 4.6.1 counts a weight of missing values only (`NA_real_`) 0 at each
    # x.
    test "a computed weight of missing values only counts nothing, refused by nothing" do
      frame =
        %{"class" => ["suv", "suv", "compact"], "w" => [1, 2, 4]}
        |> Plot.new(%{x: :class, weight: {fn _weight -> nil end, [:w]}})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :count) === [0.0, 0.0]
    end

    test "a computed weight that is not a number is refused when the plot is run" do
      plot =
        %{"class" => ["suv", "compact"], "w" => [1, 2]}
        |> Plot.new(%{x: :class, weight: {&Kernel.to_string/1, [:w]}})
        |> Plot.geom_bar()

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
      assert error.message =~ "weight"
      assert error.message =~ ":string"
    end
  end

  describe "layer_data/2, after_stat" do
    @classes %{
      "class" => ["suv", "compact", "suv", "midsize"],
      "n" => [1, 2, 3, 4],
      "drv" => ["4", "f", "f", "4"]
    }

    # Golden: ggplot2 4.0.3 in R 4.6.1 titles the y axis of `ggplot(d, aes(class, after_stat(prop),
    # group = 1)) + geom_bar() + geom_point(aes(y = n))` `prop`, where counting's own count, a
    # fallback, gives way to `n`. The values it computes are `Giggly.Mapping`'s doctest.
    test "a stat's computed variable titles the axis it maps, as its own title, not a fallback" do
      titles =
        @classes
        |> Plot.new(%{x: :class, y: {:after_stat, [:prop]}, group: 1})
        |> Plot.geom_bar()
        |> Plot.geom_point(%{y: :n})
        |> Giggly.Assembly.run()
        |> Map.fetch!(:guide_titles)

      assert titles === %{x: "class", y: "prop"}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 puts `geom_bar(aes(y = class, x = after_stat(prop), group =
    # 1))` at x 0.25, 0.25, 0.5.
    test "horizontal bars take the variable into x" do
      frame =
        @classes
        |> Plot.new(%{y: :class, x: {:after_stat, [:prop]}, group: 1})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :x) === [0.25, 0.25, 0.5]
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `ggplot(d, aes(class, fill =
    # after_stat(count))) + geom_bar()`: groups 1, 2, 3 and props of 1, the fill computed after the
    # stat; fills #132B43, #132B43, #56B1F7; columns count, prop, x, flipped_aes, PANEL, group, fill,
    # y, the layer's after_stat before the stat's count; a colour bar titled `count`.
    test "an aesthetic computed after the stat takes no part in grouping, and gets its own scale" do
      plot =
        @classes
        |> Plot.new(%{x: :class, fill: {:after_stat, [:count]}})
        |> Plot.geom_bar()

      frame = Giggly.layer_data(plot)
      [legend] = Giggly.Assembly.run(plot).legends
      names = DataFrame.names(frame)

      assert {DataFrame.pull(frame, :group), DataFrame.pull(frame, :prop),
              DataFrame.pull(frame, :fill), Enum.take(names, 8), legend.guide, legend.title} ===
               {[1, 2, 3], [1.0, 1.0, 1.0], ["#132B43", "#132B43", "#56B1F7"],
                [:count, :prop, :x, :flipped_aes, :panel, :group, :fill, :y],
                %Giggly.Guide.Colorbar{bins: 15}, "count"}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 fills `after_stat(factor(count))` #F8766D, #F8766D, #00BFC4
    # on a discrete scale and titles it `factor(count)`.
    test "a factor computed after the stat is a discrete scale's levels" do
      plot =
        @classes
        |> Plot.new(%{x: :class, fill: {:after_stat, [{:factor, [:count]}]}})
        |> Plot.geom_bar()

      frame = Giggly.layer_data(plot)
      [legend] = Giggly.Assembly.run(plot).legends

      assert {DataFrame.pull(frame, :fill), legend.title,
              Enum.map(legend.keys, fn key -> key.label end)} ===
               {["#F8766D", "#F8766D", "#00BFC4"], "factor(count)", ["1", "2"]}
    end

    # ggplot2 4.0.3 in R 4.6.1 adds the fill scale for the second layer's `fill = drv` before any
    # stat runs, then refuses the first's `after_stat(count)`: "Continuous value supplied to a
    # discrete scale."
    test "a scale is chosen by the columns evaluated before the stats, then those computed after" do
      plot =
        @classes
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar(%{fill: {:after_stat, [:count]}})
        |> Plot.geom_col(%{y: :n, fill: :drv})

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end

      assert String.starts_with?(
               error.message,
               ~s(the layer at index 0 maps :fill to {:after_stat, ["count"]}, a continuous)
             )

      assert error.message =~ ~s(index 1 maps :fill to "drv", a discrete)
    end

    # ggplot2 4.0.3 in R 4.6.1 adds a discrete y scale for `y = after_stat(as.character(count))`,
    # nothing having mapped y before the stat; here the axis's scale is chosen before it.
    test "a value on an axis that its scale cannot take is refused when the plot is run" do
      plot =
        @classes
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar(%{y: {:after_stat, [{&Float.to_string/1, [:count]}]}})

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end

      assert error.message =~ ~s(maps :y to {:after_stat, [{&Float.to_string/1, ["count"]}]})
      assert error.message =~ "a :string column"
      assert error.message =~ "is continuous, so it takes numbers"
    end

    # ggplot2 4.0.3 in R 4.6.1 puts `geom_bar(aes(class, after_stat(prop * 4), group = 1))` over a
    # discrete y axis at 1, 1, 2, positions among its levels; it reads strings there as more levels,
    # which it maps after the position, where here the stat's values are positions already.
    test "a value on a discrete axis is a number, a position, and anything else is refused" do
      points =
        @classes
        |> Plot.new()
        |> Plot.geom_point(%{x: :class, y: :drv})

      times_four = {&Kernel.*/2, [:prop, 4]}

      frame =
        points
        |> Plot.geom_bar(%{x: :class, y: {:after_stat, [times_four]}, group: 1})
        |> Giggly.layer_data(1)

      error =
        assert_raise ArgumentError, fn ->
          points
          |> Plot.geom_bar(%{x: :class, y: {:after_stat, [{&Float.to_string/1, [:count]}]}})
          |> Giggly.layer_data(1)
        end

      assert DataFrame.pull(frame, :y) === [1.0, 1.0, 2.0]
      assert error.message =~ "a :string column, but the y axis's scale, chosen before the stat, "
      assert error.message =~ "is discrete, and takes a value computed after the stat as a number"
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 puts `y = after_stat(as.Date(rep(NA, length(count))))` over
    # a date y axis at NA and NA, refusing nothing: a column of no values suits any axis.
    test "a value of missing values only on a date axis is taken, missing" do
      dated = %{
        "day" => [~D[2020-01-01], ~D[2020-01-01], ~D[2020-01-03]],
        "class" => ["a", "b", "a"]
      }

      frame =
        dated
        |> Plot.new()
        |> Plot.geom_point(%{x: :class, y: :day})
        |> Plot.geom_bar(%{x: :class, y: {:after_stat, [{fn _count -> nil end, [:count]}]}})
        |> Giggly.layer_data(1)

      assert DataFrame.pull(frame, :y) === [nil, nil]
    end

    # ggplot2 4.0.3 in R 4.6.1 puts `y = after_stat(as.Date("2020-01-01") + count)` over a date y
    # axis at 18264 and 18263, its days; and reads `geom_bar()`'s counts there as days too, warning
    # "A <numeric> value was passed to a Date scale", which a pure pipeline cannot.
    test "a value on a date axis is put through its scale, and a number there is refused" do
      dated = %{
        "day" => [~D[2020-01-01], ~D[2020-01-01], ~D[2020-01-03]],
        "class" => ["a", "b", "a"]
      }

      dates = fn count -> Date.add(~D[2020-01-01], trunc(count)) end

      points =
        dated
        |> Plot.new()
        |> Plot.geom_point(%{x: :class, y: :day})

      frame =
        points
        |> Plot.geom_bar(%{x: :class, y: {:after_stat, [{dates, [:count]}]}})
        |> Giggly.layer_data(1)

      error =
        assert_raise ArgumentError, fn ->
          points
          |> Plot.geom_bar(%{x: :class})
          |> Giggly.layer_data(1)
        end

      assert DataFrame.pull(frame, :y) === [18_264.0, 18_263.0]

      assert error.message =~ "index 1 puts its stat's :count into :y, a :float column"
      assert error.message =~ "is a date scale, so it takes dates"
    end
  end

  describe "layer_data/2, for geom_bar" do
    # Golden: ggplot2 4.0.3 in R 4.6.1 draws `geom_bar(aes(cyl))` over mtcars, whose cylinders are
    # doubles, 1.8 wide: 0.9 of their spacing, 2, where an integer column's bars are 0.9.
    test "mtcars' cylinders are doubles, as R's are, so their bars are as wide as R's" do
      frame =
        Giggly.Datasets.mtcars()
        |> Plot.new(%{x: :cyl})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      lows = DataFrame.pull(frame, :xmin)
      highs = DataFrame.pull(frame, :xmax)
      widths = Enum.zip_with(lows, highs, fn low, high -> Float.round(high - low, 10) end)

      assert widths === [1.8, 1.8, 1.8]
    end

    test "each bar counts its level's rows, its height the count" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      counts = [5.0, 47.0, 41.0, 11.0, 33.0, 35.0, 62.0]

      assert {DataFrame.pull(frame, :count), DataFrame.pull(frame, :y),
              DataFrame.pull(frame, :prop)} === {counts, counts, List.duplicate(1.0, 7)}

      assert {DataFrame.pull(frame, :xmin), DataFrame.pull(frame, :xmax)} ===
               {[
                  0.55000000000000004,
                  1.55000000000000004,
                  2.54999999999999982,
                  3.54999999999999982,
                  4.54999999999999982,
                  5.54999999999999982,
                  6.54999999999999982
                ],
                [
                  1.45,
                  2.4500000000000002,
                  3.4500000000000002,
                  4.4500000000000002,
                  5.4500000000000002,
                  6.4500000000000002,
                  7.4500000000000002
                ]}
    end

    test "an alpha set on the layer is in each counted bar's row, set after counting" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar(alpha: 0.5)
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :alpha) === List.duplicate(0.5, 7)
    end

    test "groups are counted apart, in group order, each proportion its group's, and stacked" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, group: :drv})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :x) === [2, 3, 5, 6, 7, 2, 3, 4, 6, 1, 6, 7]

      assert DataFrame.pull(frame, :count) ===
               [12.0, 3.0, 33.0, 4.0, 51.0, 35.0, 38.0, 11.0, 22.0, 5.0, 9.0, 11.0]

      assert DataFrame.pull(frame, :prop) === [
               0.116504854368932043,
               0.029126213592233011,
               0.320388349514563131,
               0.038834951456310676,
               0.495145631067961167,
               0.330188679245283001,
               0.358490566037735825,
               0.103773584905660382,
               0.207547169811320764,
               0.200000000000000011,
               0.359999999999999987,
               0.440000000000000002
             ]

      assert {DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :ymax)} ===
               {[35.0, 38.0, 0.0, 31.0, 11.0, 0.0, 0.0, 0.0, 9.0, 0.0, 0.0, 0.0],
                [47.0, 41.0, 33.0, 35.0, 62.0, 35.0, 38.0, 11.0, 31.0, 5.0, 9.0, 11.0]}
    end

    test "a weight sums its rows' weights instead of counting them" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar(%{weight: :displ})
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :y) === [
               30.800000000000001,
               109.299999999999983,
               119.799999999999983,
               37.300000000000004,
               145.800000000000040,
               93.100000000000023,
               276.299999999999898
             ]
    end

    test "on a continuous axis a bar is 0.9 of the closest gap, counting from zero" do
      x = List.duplicate(2.9, 5) ++ List.duplicate(3.1, 10) ++ List.duplicate(4.5, 4)

      frame =
        %{"x" => x}
        |> Plot.new(%{x: :x})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :count), DataFrame.pull(frame, :xmin),
              DataFrame.pull(frame, :xmax)} ===
               {[5.0, 10.0, 4.0], [2.8099999999999996, 3.0099999999999998, 4.4100000000000001],
                [2.9900000000000002, 3.1900000000000004, 4.5899999999999999]}
    end

    test "an integer column's bars are 0.9 wide, a float column's its closest gap's 0.9" do
      integers =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :cyl})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      floats =
        %{"x" => [4.0, 6.0, 8.0, 8.0]}
        |> Plot.new(%{x: :x})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert {DataFrame.pull(integers, :xmin), DataFrame.pull(floats, :xmin)} ===
               {[3.5499999999999998, 4.5499999999999998, 5.5499999999999998, 7.5499999999999998],
                [3.1000000000000001, 5.0999999999999996, 7.0999999999999996]}
    end

    test "a row missing its x is not counted, and a missing weight adds nothing" do
      missing_x =
        %{"x" => [1.0, nil, 1.0, 2.0]}
        |> Plot.new(%{x: :x})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      missing_weight =
        %{"x" => [1.0, 1.0, 2.0], "w" => [1.0, nil, 2.0]}
        |> Plot.new(%{x: :x, weight: :w})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert {DataFrame.pull(missing_x, :count), DataFrame.pull(missing_x, :prop)} ===
               {[2.0, 1.0], [0.66666666666666663, 0.33333333333333331]}

      assert DataFrame.pull(missing_weight, :count) === [1.0, 2.0]
    end

    test "a column constant within every group is carried, one that varies is dropped" do
      constant =
        %{"x" => ["a", "a", "b"], "w" => [2.0, 2.0, 2.0]}
        |> Plot.new(%{x: :x, weight: :w})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      varying =
        %{"x" => [1.0, 1.0, 2.0], "w" => [1.0, 3.0, 2.0]}
        |> Plot.new(%{x: :x, weight: :w})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert DataFrame.pull(constant, :weight) === [2.0, 2.0]
      assert :weight not in DataFrame.names(varying)
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_bar(aes(class, label =
    # factor(cyl)))` over class a, a, b and cyl 4, 4, 6 has a label column of class factor, 4 and 6.
    test "a carried column keeps its type, a factor's category included" do
      frame =
        %{"class" => ["a", "a", "b"], "cyl" => [4, 4, 6]}
        |> Plot.new(%{x: :class, label: {:factor, [:cyl]}})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :label), DataFrame.dtypes(frame).label} ===
               {[4, 6], :category}
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_bar(aes(x, weight = w))` over
    # x a, a, b, b and w 1, 1, 2, 3 has no weight column: it varies within b's group.
    test "a column constant within one group but varying within another is dropped" do
      frame =
        %{"x" => ["a", "a", "b", "b"], "w" => [1.0, 1.0, 2.0, 3.0]}
        |> Plot.new(%{x: :x, weight: :w})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :count), :weight in DataFrame.names(frame)} ===
               {[2.0, 5.0], false}
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_bar(aes(x, weight = w))` over
    # x 1, 2 and w 0, 1 has counts 0 and 1 and props 0 and 1.
    test "a count of zero beside others has a share of zero" do
      frame =
        %{"x" => [1.0, 2.0], "w" => [0.0, 1.0]}
        |> Plot.new(%{x: :x, weight: :w})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :count), DataFrame.pull(frame, :prop)} ===
               {[0.0, 1.0], [0.0, 1.0]}
    end

    test "a group whose counts are all zero has no proportions" do
      frame =
        %{"x" => [1.0, 1.0, 2.0], "w" => [0.0, 0.0, 0.0]}
        |> Plot.new(%{x: :x, weight: :w})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :count), DataFrame.pull(frame, :prop)} ===
               {[0.0, 0.0], [:nan, :nan]}
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_bar(aes(class, weight = displ,
    # group = 1))` over mpg, printed to 17 significant digits: `rowsum()` adds the counts in doubles
    # and `sum()` their total in extended precision.
    test "a proportion divides by its group's total as R sums it, the counts as R's rowsum()" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, weight: :displ, group: 1})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :count) === [
               30.800000000000001,
               109.29999999999998,
               119.79999999999998,
               37.300000000000004,
               145.80000000000004,
               93.100000000000023,
               276.2999999999999
             ]

      assert DataFrame.pull(frame, :prop) === [
               0.037912358444116202,
               0.1345396356474643,
               0.14746430329886753,
               0.045913343180699166,
               0.17946824224519947,
               0.11459871984244217,
               0.34010339734121109
             ]
    end
  end

  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same `geom_count()` layers, printed to
  # 17 significant digits. The default size scale places each count by area from 1 to 6 mm. It moves
  # with `stat_sum()`, how R's `sum()` adds, and the default size scale.
  describe "layer_data/2, for geom_count" do
    test "each place counts the rows there, its share of all of them, and is sized by its count" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :cty, y: :hwy})
        |> Plot.geom_count()
        |> Giggly.layer_data()

      first = fn name ->
        frame
        |> DataFrame.pull(name)
        |> Enum.take(12)
      end

      assert DataFrame.row_count(frame) == 78
      assert first.(:x) === [9, 11, 11, 11, 11, 12, 12, 12, 13, 13, 13, 13]
      assert first.(:y) === [12, 14, 15, 16, 17, 16, 17, 18, 16, 17, 18, 19]
      assert first.(:n) === [5.0, 2.0, 10.0, 3.0, 5.0, 2.0, 1.0, 5.0, 2.0, 12.0, 3.0, 4.0]

      assert first.(:prop) === [
               0.021367521367521368,
               0.0085470085470085479,
               0.042735042735042736,
               0.01282051282051282,
               0.021367521367521368,
               0.0085470085470085479,
               0.0042735042735042739,
               0.021367521367521368,
               0.0085470085470085479,
               0.05128205128205128,
               0.01282051282051282,
               0.017094017094017096
             ]

      assert first.(:size) === [
               3.773500981126146,
               2.386750490563073,
               5.1602514716892189,
               2.9611613513818407,
               3.773500981126146,
               2.386750490563073,
               1.0,
               3.773500981126146,
               2.386750490563073,
               5.5993310550389994,
               2.9611613513818407,
               3.4019223070763069
             ]
    end

    test "weights are summed as R's sum() adds them, each place's share of its group's total" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :drv, y: :cyl, weight: :displ})
        |> Plot.geom_count()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :y)} ===
               {[1, 1, 1, 2, 2, 2, 2, 3, 3], [4, 6, 8, 4, 5, 6, 8, 6, 8]}

      assert DataFrame.pull(frame, :n) === [
               55.5,
               116.09999999999999,
               240.20000000000002,
               118.3,
               10.0,
               137.59999999999999,
               5.2999999999999998,
               15.6,
               113.8
             ]

      assert DataFrame.pull(frame, :prop) === [
               0.13477416221466731,
               0.28193297717338511,
               0.58329286061194763,
               0.4362094395280236,
               0.03687315634218289,
               0.50737463126843663,
               0.019542772861356934,
               0.12055641421947449,
               0.87944358578052539
             ]
    end

    test "a missing weight leaves its count and its group's shares missing, so it is not sized" do
      frame =
        %{
          "x" => [1, 1, 2, 2, 2, 3, nil, 3, :infinity],
          "y" => [1, 1, 1, 2, 2, 3, 1, nil, 1],
          "g" => ["a", "b", "a", "a", "b", "b", "a", "a", "b"],
          "w" => [1, 2, 3, nil, 5, 6, 7, 8, 9]
        }
        |> Plot.new(%{x: :x, y: :y, weight: :w, colour: :g})
        |> Plot.geom_count()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :y), DataFrame.pull(frame, :group)} ===
               {[1.0, 1.0, 2.0, 2.0, 2.0, 3.0], [1, 1, 1, 2, 2, 3], [1, 2, 1, 1, 2, 2]}

      assert DataFrame.pull(frame, :color) ===
               ["#F8766D", "#00BFC4", "#F8766D", "#F8766D", "#00BFC4", "#00BFC4"]

      assert DataFrame.pull(frame, :n) === [1.0, 2.0, 3.0, nil, 5.0, 6.0]

      assert DataFrame.pull(frame, :prop) ===
               [nil, 0.15384615384615385, nil, nil, 0.38461538461538464, 0.46153846153846156]

      assert DataFrame.pull(frame, :size) ===
               [1.0, 3.2360679774997898, 4.16227766016838, nil, 5.4721359549995796, 6.0]
    end

    test "a group of every row, or of each x, sets what each share is of" do
      plot = Plot.new(Giggly.Datasets.mpg(), %{x: :class, y: :drv})

      of_all =
        plot
        |> Plot.geom_count(%{size: {:after_stat, [:prop]}, group: 1})
        |> Giggly.layer_data()

      of_each_class =
        plot
        |> Plot.geom_count(%{size: {:after_stat, [:prop]}, group: :class})
        |> Giggly.layer_data()

      assert {DataFrame.pull(of_all, :x), DataFrame.pull(of_all, :y)} ===
               {[1, 2, 2, 3, 3, 4, 5, 6, 6, 6, 7, 7], [3, 1, 2, 1, 2, 2, 1, 1, 2, 3, 1, 3]}

      assert DataFrame.pull(of_all, :n) ===
               [5.0, 12.0, 35.0, 3.0, 38.0, 11.0, 33.0, 4.0, 22.0, 9.0, 51.0, 11.0]

      assert DataFrame.pull(of_all, :prop) === [
               0.021367521367521368,
               0.05128205128205128,
               0.14957264957264957,
               0.01282051282051282,
               0.1623931623931624,
               0.047008547008547008,
               0.14102564102564102,
               0.017094017094017096,
               0.094017094017094016,
               0.038461538461538464,
               0.21794871794871795,
               0.047008547008547008
             ]

      assert DataFrame.pull(of_all, :size) === [
               2.0206207261596578,
               3.1650635094610968,
               5.0824829046386304,
               1.0,
               5.2695628191498329,
               3.0412414523193152,
               4.9528470752104745,
               1.7216878364870325,
               4.1457643480294797,
               2.7677669529663689,
               6.0,
               3.0412414523193152
             ]

      assert DataFrame.pull(of_each_class, :prop) === [
               1.0,
               0.25531914893617019,
               0.74468085106382975,
               0.073170731707317069,
               0.92682926829268297,
               1.0,
               1.0,
               0.11428571428571428,
               0.62857142857142856,
               0.25714285714285712,
               0.82258064516129037,
               0.17741935483870969
             ]
    end

    test "on discrete axes each combination of levels is a group, and counts at its positions" do
      frame =
        %{
          "g" => ["a", "b", "a", "a", "b", "b", "a", "a", "b"],
          "y" => [1, 1, 1, 2, 2, 3, 1, nil, 1]
        }
        |> Plot.new(%{x: :g, y: :y})
        |> Plot.geom_count()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :y), DataFrame.pull(frame, :group)} ===
               {[1, 1, 2, 2, 2], [1, 2, 1, 2, 3], [1, 1, 2, 2, 2]}

      assert {DataFrame.pull(frame, :n), DataFrame.pull(frame, :prop)} ===
               {[3.0, 1.0, 2.0, 1.0, 1.0], [0.75, 0.25, 0.5, 0.25, 0.25]}

      assert DataFrame.pull(frame, :size) === [6.0, 1.0, 4.5355339059327378, 1.0, 1.0]
    end

    test "each panel counts its own rows, and each share is of its own panel's" do
      frame =
        %{
          "x" => [1, 1, 2, 2, 2, 3],
          "y" => [1, 1, 1, 2, 2, 3],
          "g" => ["a", "b", "a", "a", "b", "b"]
        }
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_count()
        |> Plot.facet_wrap([:g])
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :panel), DataFrame.pull(frame, :x), DataFrame.pull(frame, :y)} ===
               {[1, 1, 1, 2, 2, 2], [1, 2, 2, 1, 2, 3], [1, 1, 2, 1, 2, 3]}

      assert DataFrame.pull(frame, :prop) === List.duplicate(0.33333333333333331, 6)
      assert DataFrame.pull(frame, :size) === List.duplicate(4.5355339059327378, 6)
    end

    test "weights that cancel give a share of an infinity, or NaN where the count is zero" do
      frame =
        %{"x" => [1, 2, 3], "y" => [1, 1, 1], "w" => [1, -1, 0]}
        |> Plot.new(%{x: :x, y: :y, weight: :w})
        |> Plot.geom_count()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :n), DataFrame.pull(frame, :prop)} ===
               {[1.0, -1.0, 0.0], [:infinity, :neg_infinity, :nan]}

      assert DataFrame.pull(frame, :size) === [6.0, 1.0, 4.5355339059327378]
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same plot: shape 16 at (1, 1) twice
    # and at (2, 2) once, shape 17 at (1, 1) once.
    test "a mapped shape is counted over, each of its values at a place a point of its own" do
      frame =
        %{"x" => [1, 1, 1, 2], "y" => [1, 1, 1, 2], "s" => ["a", "a", "b", "a"]}
        |> Plot.new(%{x: :x, y: :y, shape: :s})
        |> Plot.geom_count()
        |> Giggly.layer_data()

      assert Enum.map([:x, :y, :shape, :n, :size, :group], fn name ->
               DataFrame.pull(frame, name)
             end) ===
               [
                 [1, 1, 2],
                 [1, 1, 2],
                 [:circle_small, :triangle, :circle_small],
                 [2.0, 1.0, 1.0],
                 [6.0, 1.0, 1.0],
                 [1, 2, 1]
               ]
    end

    test "a mapped size is counted over in place of the count, and a set one sizes every point" do
      table = %{
        "x" => [1, 1, 2, 2, 2, 3],
        "y" => [1, 1, 1, 2, 2, 3],
        "v" => [10, 10, 20, 20, 20, 30]
      }

      plot = Plot.new(table, %{x: :x, y: :y})

      mapped =
        plot
        |> Plot.geom_count(%{size: :v})
        |> Giggly.layer_data()

      set =
        plot
        |> Plot.geom_count(size: 3)
        |> Giggly.layer_data()

      assert {DataFrame.pull(mapped, :n), DataFrame.pull(mapped, :size)} ===
               {[2.0, 1.0, 2.0, 1.0], [1.0, 4.5355339059327378, 4.5355339059327378, 6.0]}

      assert {DataFrame.pull(set, :n), DataFrame.pull(set, :size)} ===
               {[2.0, 1.0, 2.0, 1.0], [3.0, 3.0, 3.0, 3.0]}
    end

    test "a column the plot's mapping carries in splits the counts only if R's list names it" do
      table = %{"x" => [1, 1, 2], "y" => [1, 1, 1], "v" => [1, 2, 3], "l" => ["p", "q", "p"]}

      line_width =
        table
        |> Plot.new(%{x: :x, y: :y, linewidth: :v})
        |> Plot.geom_count()
        |> Giggly.layer_data()

      labelled =
        table
        |> Plot.new(%{x: :x, y: :y, label: :l})
        |> Plot.geom_count()
        |> Giggly.layer_data()

      assert {DataFrame.pull(line_width, :n), :linewidth in DataFrame.names(line_width)} ===
               {[2.0, 1.0], false}

      assert {DataFrame.pull(labelled, :n), DataFrame.pull(labelled, :label)} ===
               {[1.0, 1.0, 1.0], ["p", "q", "p"]}
    end

    # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `geom_count()` over two rows at one
    # place, the plot mapping one of these to a column that tells them apart, is two rows, a count
    # of 1 each, for every name of `.all_aesthetics` but x, y and weight (linetype and shape from a
    # discrete column, which R requires). It moves with that list.
    test "every aesthetic ggplot2's list names is counted over, from the plot's mapping too" do
      table = %{"x" => [1, 1], "y" => [1, 1], "v" => [1, 2], "l" => ["p", "q"]}

      names =
        ~w(alpha angle color fill group hjust label linetype lower max middle min radius sample
           shape size upper vjust width xend xintercept xmax xmin yend yintercept ymax ymin z)a

      counts =
        Map.new(names, fn name ->
          column = if name in [:linetype, :shape], do: :l, else: :v

          frame =
            table
            |> Plot.new(Map.put(%{x: :x, y: :y}, name, column))
            |> Plot.geom_count()
            |> Giggly.layer_data()

          {name, DataFrame.pull(frame, :n)}
        end)

      assert counts == Map.new(names, fn name -> {name, [1.0, 1.0]} end)
    end

    test "places come out in the order of the layer's columns, its own aesthetics first" do
      frame =
        %{"x" => [2, 1, 1], "y" => [1, 2, 1], "g" => ["b", "a", "b"]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_count(%{colour: :g})
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :color), DataFrame.pull(frame, :x), DataFrame.pull(frame, :y),
              DataFrame.pull(frame, :prop)} ===
               {["#F8766D", "#00BFC4", "#00BFC4"], [1, 1, 2], [2, 1, 1], [1.0, 0.5, 0.5]}
    end

    test "a missing colour is a place's value of its own, sorted last" do
      frame =
        %{"x" => [1, 1, 2], "y" => [1, 1, 1], "g" => ["a", nil, nil]}
        |> Plot.new(%{x: :x, y: :y, colour: :g})
        |> Plot.geom_count()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :color),
              DataFrame.pull(frame, :group), DataFrame.pull(frame, :prop)} ===
               {[1, 1, 2], ["#F8766D", "#7F7F7F", "#7F7F7F"], [1, 2, 2], [1.0, 0.5, 0.5]}
    end

    test "a weight column of only missing values leaves every count and share missing" do
      frame =
        %{"x" => [1, 1, 2], "y" => [1, 1, 1], "w" => [nil, nil, nil]}
        |> Plot.new(%{x: :x, y: :y, weight: :w})
        |> Plot.geom_count()
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :n), DataFrame.pull(frame, :prop),
              DataFrame.pull(frame, :size)} === {[nil, nil], [nil, nil], [nil, nil]}
    end

    test "a weight an expression computes as anything but numbers is refused when run" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :cty, y: :hwy})
        |> Plot.geom_count(%{weight: {&Atom.to_string/1, [{:constant, :heavy}]}})

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end

      assert error.message =~ "weight must be a number"
      assert error.message =~ ":string"
    end
  end

  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1, `geom_bar(position = "dodge")` on the same
  # `mpg`, printed to 17 significant digits. It moves with `position_dodge()`.
  describe "layer_data/2, dodged" do
    test "the groups at one x share a bar's width, lowest group leftmost; a lone group keeps it" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, group: :drv})
        |> Plot.geom_bar(position: :dodge)
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :x) === [
               1.7749999999999999,
               2.7749999999999999,
               5.0,
               5.7000000000000002,
               6.7750000000000004,
               2.2250000000000001,
               3.2250000000000001,
               4.0,
               6.0,
               1.0,
               6.2999999999999998,
               7.2249999999999996
             ]

      assert DataFrame.pull(frame, :xmin) === [
               1.54999999999999982,
               2.54999999999999982,
               4.54999999999999982,
               5.54999999999999982,
               6.55000000000000071,
               2.0,
               3.0,
               3.54999999999999982,
               5.84999999999999964,
               0.55000000000000004,
               6.14999999999999947,
               7.0
             ]

      assert DataFrame.pull(frame, :xmax) === [
               2.0,
               3.0,
               5.4500000000000002,
               5.8500000000000005,
               7.0,
               2.4500000000000002,
               3.4500000000000002,
               4.4500000000000002,
               6.1500000000000004,
               1.45,
               6.4500000000000002,
               7.4499999999999993
             ]
    end
  end

  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same plot, on the same `mpg` where it
  # is used, printed to 17 significant digits. It moves with ggplot2's bar orientation.
  describe "layer_data/2, horizontal bars" do
    test "counting along y draws each bar from 0 rightward to its count" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new()
        |> Plot.geom_bar(%{y: :class})
        |> Giggly.layer_data()

      counts = [5.0, 47.0, 41.0, 11.0, 33.0, 35.0, 62.0]

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :xmin),
              DataFrame.pull(frame, :xmax)} === {counts, List.duplicate(0.0, 7), counts}

      assert {DataFrame.pull(frame, :ymin), DataFrame.pull(frame, :flipped_aes)} ===
               {[
                  0.55000000000000004,
                  1.55000000000000004,
                  2.54999999999999982,
                  3.54999999999999982,
                  4.54999999999999982,
                  5.54999999999999982,
                  6.54999999999999982
                ], List.duplicate(true, 7)}
    end

    test "columns are horizontal when y alone is discrete, vertical when both are" do
      horizontal =
        %{"trt" => ["a", "b", "c"], "outcome" => [2.3, 1.9, 3.2]}
        |> Plot.new(%{x: :outcome, y: :trt})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      both_discrete =
        %{"x" => ["a", "b"], "y" => ["p", "q"]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(horizontal, :xmax), DataFrame.pull(horizontal, :ymax)} ===
               {[2.3, 1.9, 3.2], [1.45, 2.4500000000000002, 3.4500000000000002]}

      assert {DataFrame.pull(both_discrete, :ymin), DataFrame.pull(both_discrete, :ymax),
              DataFrame.pull(both_discrete, :flipped_aes)} ===
               {[0.0, 0.0], [1.0, 2.0], [false, false]}
    end

    test "horizontal bars stack rightward, below zero leftward, apart" do
      counted =
        %{"y" => ["a", "a", "a", "b"], "g" => ["p", "q", "q", "p"]}
        |> Plot.new(%{y: :y, group: :g})
        |> Plot.geom_bar()
        |> Giggly.layer_data()

      negative =
        %{"v" => [1.0, 2.0, -1.0], "k" => ["a", "a", "b"], "g" => ["p", "q", "p"]}
        |> Plot.new(%{x: :v, y: :k, group: :g})
        |> Plot.geom_col()
        |> Giggly.layer_data()

      assert {DataFrame.pull(counted, :xmin), DataFrame.pull(counted, :xmax)} ===
               {[2.0, 0.0, 0.0], [3.0, 1.0, 2.0]}

      assert {DataFrame.pull(negative, :xmin), DataFrame.pull(negative, :xmax),
              DataFrame.pull(negative, :x)} ===
               {[2.0, 0.0, -1.0], [3.0, 2.0, 0.0], [3.0, 2.0, 0.0]}
    end

    test "horizontal bars dodge along y" do
      frame =
        %{"y" => ["a", "a", "a", "b"], "g" => ["p", "q", "q", "p"]}
        |> Plot.new(%{y: :y, group: :g})
        |> Plot.geom_bar(position: :dodge)
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :y), DataFrame.pull(frame, :ymin),
              DataFrame.pull(frame, :ymax)} ===
               {[0.77500000000000002, 2.0, 1.22500000000000009],
                [0.55000000000000004, 1.55000000000000004, 1.0],
                [1.0, 2.4500000000000002, 1.4500000000000002]}
    end
  end

  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same plot, printed to 17 significant
  # digits. It moves with `position_nudge()` and the aesthetics it reads.
  describe "layer_data/2, nudged text" do
    @points %{"x" => [1, 2, 3], "y" => [1, 4, 2], "name" => ["a", "b", "c"]}

    # R's columns in R's order, but the geom's defaults (colour, family, angle...), which Giggly's
    # tables do not carry yet.
    test "a text layer's table says how far each row moved, 0 when nothing sets it" do
      frame =
        @points
        |> Plot.new(%{x: :x, y: :y, label: :name})
        |> Plot.geom_text(size: 5)
        |> Giggly.layer_data()

      assert DataFrame.names(frame) === [
               :x,
               :y,
               :label,
               :panel,
               :group,
               :nudge_x,
               :nudge_y,
               :size
             ]

      assert Enum.map([:x, :y, :nudge_x, :nudge_y], fn name -> DataFrame.pull(frame, name) end) ===
               [[1.0, 2.0, 3.0], [1.0, 4.0, 2.0], [+0.0, +0.0, +0.0], [+0.0, +0.0, +0.0]]
    end

    test "a row missing its x stays missing, and an axis nothing nudges keeps its places" do
      frame =
        %{"x" => [1.0, nil, 3.0], "y" => [1.0, 4.0, 2.0], "name" => ["a", "b", "c"]}
        |> Plot.new(%{x: :x, y: :y, label: :name})
        |> Plot.geom_text(nudge_x: 0.5)
        |> Giggly.layer_data()

      assert {DataFrame.pull(frame, :x), DataFrame.pull(frame, :y)} ===
               {[1.5, nil, 3.5], [1.0, 4.0, 2.0]}
    end

    test "a date is nudged by days" do
      frame =
        %{"day" => [~D[2020-01-01], ~D[2020-01-05]], "y" => [1.0, 2.0], "name" => ["a", "b"]}
        |> Plot.new(%{x: :day, y: :y, label: :name})
        |> Plot.geom_text(nudge_x: 1)
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :x) === [18_263.0, 18_267.0]
    end
  end

  # Golden throughout: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for the same plots of mpg. They
  # move with how a continuous scale's limits censor a position.
  describe "layer_data/2, under a scale's limits" do
    test "a row outside the limits is missing before counting, so it is not counted" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ})
        |> Plot.geom_bar()
        |> Plot.xlim(2, 5)
        |> Giggly.layer_data()

      counts = DataFrame.pull(frame, :count)

      assert Enum.sum(counts) === 176.0
    end

    test "a bar the limits cut once it is placed is missing its end, so it is not drawn" do
      frame =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar()
        |> Plot.ylim(0, 50)
        |> Giggly.layer_data()

      counts = DataFrame.pull(frame, :count)
      ends = DataFrame.pull(frame, :ymax)

      assert Enum.zip(counts, ends) === [
               {5.0, 5.0},
               {47.0, 47.0},
               {41.0, 41.0},
               {11.0, 11.0},
               {33.0, 33.0},
               {35.0, 35.0},
               {62.0, nil}
             ]
    end

    test "an infinite end is kept whatever the limits" do
      frame =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.annotate(:rect,
          xmin: :neg_infinity,
          xmax: 3,
          ymin: :neg_infinity,
          ymax: :infinity
        )
        |> Plot.xlim(2, 5)
        |> Giggly.layer_data(1)

      assert Enum.map([:xmin, :xmax, :ymin, :ymax], fn name -> DataFrame.pull(frame, name) end) ===
               [[:neg_infinity], [3.0], [:neg_infinity], [:infinity]]
    end

    # In R 4.6.1, ggplot2 4.0.3 refuses "Discrete value supplied to a continuous scale", fails on a
    # date under a reversed or a discrete scale ("unary - is not defined for "Date" objects",
    # "Can't convert `x` <date> to <double>") and on text under a date scale; it reads numbers on
    # a date scale as days with a warning, and puts numbers on a discrete axis without breaks,
    # which Giggly refuses, an axis having one kind.
    test "a column on the axis of a kind the plot's scale does not take is refused when run" do
      dates = %{"date" => [~D[2020-01-01], ~D[2020-02-01]], "value" => [1.0, 2.0]}

      for {plot, refusal} <- [
            {@mpg_rows
             |> Plot.new(%{x: :class, y: :hwy})
             |> Plot.geom_point()
             |> Plot.scale_x_continuous(),
             ~s(x scale is continuous, but the layer at index 0 maps :x to "class", a discrete)},
            {dates
             |> Plot.new(%{x: :date, y: :value})
             |> Plot.geom_line()
             |> Plot.xlim(5, 1),
             ~s(x scale is continuous through reverse, but the layer at index 0 maps :x to "date")},
            {dates
             |> Plot.new(%{x: :value, y: :date})
             |> Plot.geom_point()
             |> Plot.scale_y_log10(),
             ~s(y scale is continuous through log10, but the layer at index 0 maps :y to "date")},
            {dates
             |> Plot.new(%{x: :date, y: :value})
             |> Plot.geom_point()
             |> Plot.scale_x_discrete(),
             ~s(x scale is discrete, but the layer at index 0 maps :x to "date", a date column)},
            {@mpg_rows
             |> Plot.new(%{x: :hwy, y: :class})
             |> Plot.geom_point()
             |> Plot.ylim(["suv"])
             |> Plot.xlim(["1"]),
             ~s(x scale is discrete, but the layer at index 0 maps :x to "hwy", a continuous)},
            {@mpg_rows
             |> Plot.new(%{x: :hwy, y: :class})
             |> Plot.geom_point()
             |> Plot.scale_x_date(),
             ~s(x scale is date, but the layer at index 0 maps :x to "hwy", a continuous column)},
            {@mpg_rows
             |> Plot.new(%{x: :class, y: :hwy})
             |> Plot.geom_point()
             |> Plot.scale_x_date(),
             ~s(x scale is date, but the layer at index 0 maps :x to "class", a discrete column)}
          ] do
        error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
        assert error.message =~ refusal
      end
    end
  end

  describe "layer_data/2, under a discrete or a date scale" do
    # Golden: R 4.6.1 with ggplot2 4.0.3, layer_data() of ggplot(s, aes(a)) + geom_bar() +
    # scale_x_discrete(limits = c("r", "p")), `s` holding a row each of "p", "q", "r" and NA: the
    # rows the limits leave out are not counted, and each bar stands at its value's place among
    # them.
    test "a discrete scale's limits leave out the values they do not name, and place the rest" do
      frame =
        %{"a" => ["p", "q", "r", nil]}
        |> Plot.new(%{x: :a})
        |> Plot.geom_bar()
        |> Plot.scale_x_discrete(limits: ["r", "p"])
        |> Giggly.layer_data()

      assert Enum.map([:x, :count, :xmin, :xmax], fn name -> DataFrame.pull(frame, name) end) ===
               [[2, 1], [1.0, 1.0], [1.55, 0.55], [2.45, 1.45]]
    end

    # Golden: as above, for points on 2024-01-01, 2024-01-11 and 2024-02-15 under
    # scale_x_continuous(limits = c(19725, NA)): each date at its days, the first outside.
    test "a continuous scale places a date at its days since 1970-01-01" do
      frame =
        %{"day" => [~D[2024-01-01], ~D[2024-01-11], ~D[2024-02-15]], "value" => [1, 2, 3]}
        |> Plot.new(%{x: :day, y: :value})
        |> Plot.geom_point()
        |> Plot.scale_x_continuous(limits: {19_725, nil})
        |> Giggly.layer_data()

      assert DataFrame.pull(frame, :x) === [nil, 19_733.0, 19_768.0]
    end

    # Golden: as above, for ggplot(s, aes(y = a)) + geom_bar() + scale_x_discrete(): the counts go
    # on a discrete x axis as positions, and the axis spans them alone, widened by 0.6.
    test "a plot's scale is kept on an axis no layer maps, whatever its kind" do
      plot =
        %{"a" => ["p", "q", "r", nil]}
        |> Plot.new(%{y: :a})
        |> Plot.geom_bar()
        |> Plot.scale_x_discrete()

      frame = Giggly.layer_data(plot)

      assert {Enum.map([:x, :xmin, :xmax], fn name -> DataFrame.pull(frame, name) end),
              Giggly.panel_scales(plot).x} ===
               {[[1.0, 1.0, 1.0, 1.0], [0.0, 0.0, 0.0, 0.0], [1.0, 1.0, 1.0, 1.0]],
                %Giggly.Scale.Discrete{continuous_range: {0.0, 1.0}}}
    end
  end

  describe "layer_data/2, under a transformed scale" do
    # Golden: R 4.6.1 with ggplot2 4.0.3, layer_data() of ggplot(mpg, aes(class)) + geom_bar() with
    # scale_y_log10() and with scale_y_reverse(): each class's count is put through the scale and
    # the bar set up on it afterwards, so on a log axis it stands from 0, a count of 1, and on a
    # reversed one from 0 down to minus its count. They move only if ggplot2's bars do.
    test "a bar is set up from zero once its count is transformed" do
      log10 =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar()
        |> Plot.scale_y_log10()
        |> Giggly.layer_data()

      assert DataFrame.pull(log10, :y) == Enum.map([5, 47, 41, 11, 33, 35, 62], &:math.log10/1)
      assert DataFrame.pull(log10, :ymin) == List.duplicate(0.0, 7)

      reversed =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar()
        |> Plot.scale_y_reverse()
        |> Giggly.layer_data()

      assert DataFrame.pull(reversed, :ymin) == [-5.0, -47.0, -41.0, -11.0, -33.0, -35.0, -62.0]
      assert DataFrame.pull(reversed, :ymax) == List.duplicate(0.0, 7)
    end
  end

  describe "the guides' titles" do
    # ggplot2 4.0.3 titles the axis by the scale's name whether `labs()` comes before or after it.
    test "a scale's name titles its axis over a label, whichever comes first, :none included" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      before =
        plot
        |> Plot.labs(x: "from labs", y: "from labs")
        |> Plot.scale_x_continuous(name: "from scale")
        |> Plot.scale_y_continuous(name: :none)

      later =
        plot
        |> Plot.scale_x_continuous(name: "from scale")
        |> Plot.labs(x: "from labs")

      assert {Giggly.Assembly.run(before).guide_titles, Giggly.Assembly.run(later).guide_titles} ===
               {%{x: "from scale", y: :none}, %{x: "from scale", y: "mpg"}}
    end

    test "an axis no layer maps is titled by the column a stat puts into it" do
      assembly =
        %{"class" => ["suv", "compact"]}
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar()
        |> Giggly.Assembly.run()

      assert assembly.guide_titles === %{x: "class", y: "count"}
    end

    test "counting along y titles x by the count" do
      assembly =
        %{"class" => ["suv", "compact"]}
        |> Plot.new()
        |> Plot.geom_bar(%{y: :class})
        |> Giggly.Assembly.run()

      assert assembly.guide_titles === %{x: "count", y: "class"}
    end

    test "a later layer's own mapping titles the axis over an earlier stat's column" do
      assembly =
        %{"x" => ["a", "b"], "y" => [5.0, 7.0]}
        |> Plot.new(%{x: :x})
        |> Plot.geom_bar()
        |> Plot.geom_col(%{y: :y})
        |> Giggly.Assembly.run()

      assert assembly.guide_titles === %{x: "x", y: "y"}
    end

    test "an expression titles its axis by its text, and one with a closure titles none" do
      assembly =
        %{"hwy" => [29, 24], "cty" => [18, 16]}
        |> Plot.new(%{x: {&Kernel.//2, [:hwy, :cty]}, y: {fn hwy -> hwy * 2 end, [:hwy]}})
        |> Plot.geom_point()
        |> Giggly.Assembly.run()

      assert assembly.guide_titles === %{x: "hwy / cty", y: :none}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 titles the colour legend `colour` for `aes(colour =
    # "smooth")` alone, and `class` with a layer mapping colour to `class` before it or after.
    test "a constant titles by its aesthetic's name where no layer's column titles it" do
      legend_title = fn layers ->
        [legend] =
          layers
          |> Enum.reduce(Plot.new(@mpg_rows, %{x: :displ, y: :hwy}), fn mapping, plot ->
            Plot.geom_point(plot, mapping)
          end)
          |> Giggly.Assembly.run()
          |> Map.fetch!(:legends)
          |> Enum.filter(fn legend -> legend.aesthetics == [:color] end)

        legend.title
      end

      constant = %{colour: {:constant, "smooth"}}
      column = %{colour: :class}

      assert Enum.map([[constant], [constant, column], [column, constant]], legend_title) ===
               ["color", "class", "class"]
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 titles y `count` for `geom_point(aes(y = 10)) + geom_bar()`
    # and `y` for the two the other way round: of the fallbacks, the last layer's wins; and
    # `hwy/displ` for `geom_point(aes(y = hwy / displ)) + geom_point(aes(y = hwy))`.
    test "the last layer's fallback titles, a constant's or a stat's; a first expression's wins" do
      y_title = fn plot -> Giggly.Assembly.run(plot).guide_titles.y end
      plot = Plot.new(@mpg_rows, %{x: :class})

      constant_first =
        plot
        |> Plot.geom_point(%{y: 10})
        |> Plot.geom_bar()

      count_first =
        plot
        |> Plot.geom_bar()
        |> Plot.geom_point(%{y: 10})

      expression_first =
        plot
        |> Plot.geom_point(%{y: {&Kernel.//2, [:hwy, :displ]}})
        |> Plot.geom_point(%{y: :hwy})

      assert Enum.map([constant_first, count_first, expression_first], y_title) ===
               ["count", "y", "hwy / displ"]
    end

    test "a closure's title is the first layer's, so a later column does not title the axis" do
      assembly =
        @mpg_rows
        |> Plot.new(%{x: :displ})
        |> Plot.geom_point(%{y: {fn hwy -> hwy * 2 end, [:hwy]}})
        |> Plot.geom_point(%{y: :hwy})
        |> Giggly.Assembly.run()

      assert assembly.guide_titles.y === :none
    end

    # ggplot2 4.0.3 titles the axes `wt` and `mpg` with the annotation added before the points, and
    # draws no title with the annotation alone, its mapping unlabelled.
    test "an annotation titles no axis, added first or alone" do
      first =
        %{"wt" => [2.62, 2.32], "mpg" => [21.0, 22.8]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:text, x: 4, y: 25, label: "zz")
        |> Plot.geom_point()
        |> Giggly.Assembly.run()

      alone =
        %{"wt" => [2.62, 2.32], "mpg" => [21.0, 22.8]}
        |> Plot.new()
        |> Plot.annotate(:text, x: 4, y: 25, label: "zz")
        |> Giggly.Assembly.run()

      assert {first.guide_titles, alone.guide_titles} ===
               {%{x: "wt", y: "mpg"}, %{x: :none, y: :none}}
    end

    # ggplot2 4.0.3: `labs(x = "Class", y = NULL)` set before the layer titles x "Class" and y
    # nothing, over the column and the count.
    test "a label titles an axis over its column and a stat's, set before the layer or after" do
      assembly =
        %{"class" => ["suv", "compact"]}
        |> Plot.new(%{x: :class})
        |> Plot.labs(x: "Class", y: :none)
        |> Plot.geom_bar()
        |> Giggly.Assembly.run()

      assert assembly.guide_titles === %{x: "Class", y: :none}
    end

    test "the plot's own labels are carried for drawing, :none for those labs/2 does not set" do
      assembly =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.labs(title: "Title", caption: "Caption")
        |> Giggly.Assembly.run()

      assert assembly.plot_labels === %{
               title: "Title",
               subtitle: :none,
               caption: "Caption",
               tag: :none
             }
    end
  end

  describe "panel_scales/2" do
    test "a scale the plot sets is trained with its options" do
      labeller = fn breaks -> Enum.map(breaks, &Float.to_string/1) end

      scales =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.scale_x_continuous(limits: {2, nil}, labels: labeller)
        |> Giggly.panel_scales()

      assert scales.x === %Giggly.Scale.Continuous{
               range: {2.62, 2.875},
               limits: {2.0, nil},
               labels: labeller
             }
    end

    test "the scales are trained again on the marks, so a discrete axis holds its bars' edges" do
      scales =
        %{"trt" => ["a", "b", "c"], "outcome" => [2.3, 1.9, 3.2]}
        |> Plot.new(%{x: :trt, y: :outcome})
        |> Plot.geom_col()
        |> Giggly.panel_scales()

      assert scales === %{
               x: %Giggly.Scale.Discrete{
                 levels: ["a", "b", "c"],
                 continuous_range: {0.55000000000000004, 3.4500000000000002},
                 palette: :identity,
                 na_value: nil,
                 guide: :axis
               },
               y: %Giggly.Scale.Continuous{
                 range: {0.0, 3.2},
                 transform: :identity,
                 palette: :identity,
                 na_value: nil,
                 guide: :axis
               }
             }
    end

    # Golden: ggplot2 4.0.3's x and y scale ranges in R 4.6.1 for the same plot, on mtcars' first
    # three cars: corners set for every rectangle are filled in before the scales are trained again,
    # so the axes reach them, as ggplot2 4.0's `GeomRect` fills them in.
    test "corners set for every rectangle widen the axes, as mapped ones do" do
      scales =
        %{"wt" => [2.62, 2.875, 2.32], "mpg" => [21.0, 21.0, 22.8]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.geom_rect(xmin: 3, xmax: 4.2, ymin: 12, ymax: 21, alpha: 0.2)
        |> Giggly.panel_scales()

      assert {scales.x.range, scales.y.range} === {{2.32, 4.2}, {12.0, 22.8}}

      mixed =
        %{"a" => [1.0, 3.0], "b" => [2.0, 5.0]}
        |> Plot.new(%{xmin: :a, xmax: :b})
        |> Plot.geom_rect(ymin: 0, ymax: 10)
        |> Giggly.panel_scales()

      assert {mixed.x.range, mixed.y.range} === {{1.0, 5.0}, {0.0, 10.0}}
    end

    # Golden: ggplot2 4.0.3's x and y scale ranges in R 4.6.1, on mtcars' first three cars.
    test "an annotation's positions widen the axes, and its infinite ones do not" do
      beyond =
        %{"wt" => [2.62, 2.875, 2.32], "mpg" => [21.0, 21.0, 22.8]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.annotate(:text, x: 6, y: 35, label: "beyond")
        |> Giggly.panel_scales()

      assert {beyond.x.range, beyond.y.range} === {{2.32, 6.0}, {21.0, 35.0}}

      band =
        %{"wt" => [2.62, 2.875, 2.32], "mpg" => [21.0, 21.0, 22.8]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.annotate(:rect,
          xmin: :neg_infinity,
          xmax: 2,
          ymin: :neg_infinity,
          ymax: :infinity
        )
        |> Giggly.panel_scales()

      assert {band.x.range, band.y.range} === {{2.0, 2.875}, {21.0, 22.8}}
    end

    # Golden: ggplot2 4.0.3's x scale range in R 4.6.1 for the same plot.
    test "a scale is reset before it is trained again, so a mark that lost its x is not covered" do
      scales =
        %{"x" => [1.0, 1.0, 5.0], "y" => [1.0, 2.0, nil]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_col()
        |> Giggly.panel_scales()

      assert scales.x.range === {-0.80000000000000004, 2.7999999999999998}
    end

    # Golden: ggplot2 4.0.3's x and y scale ranges in R 4.6.1 for the same plot, printed to 17
    # significant digits.
    test "an axis is trained on its nudged labels, not on the places they were nudged from" do
      scales =
        %{"x" => [1.0, 2.0, 3.0], "y" => [1.0, 4.0, 2.0], "name" => ["a", "b", "c"]}
        |> Plot.new(%{x: :x, y: :y, label: :name})
        |> Plot.geom_text(nudge_x: 0.1, nudge_y: -0.2)
        |> Giggly.panel_scales()

      assert {scales.x.range, scales.y.range} ===
               {{1.1000000000000001, 3.1000000000000001},
                {0.80000000000000004, 3.79999999999999982}}
    end

    # Golden: ggplot2 4.0.3's y scale in R 4.6.1 for the same plot: its limits and its continuous
    # range.
    test "a discrete axis widens its continuous range to its nudged labels" do
      scales =
        %{"x" => [1.0, 3.0, 2.0, 5.0], "y" => ["a", "c", "d", "c"]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_text(%{label: :y}, nudge_y: 1)
        |> Giggly.panel_scales()

      assert {scales.y.levels, scales.y.continuous_range} === {["a", "c", "d"], {2.0, 4.0}}
    end

    test "an axis's scale is trained on every layer's column on that axis" do
      plot =
        @rows
        |> Plot.new(%{y: :mpg})
        |> Plot.geom_point(%{x: :wt})
        |> Plot.geom_point(%{x: :qsec})

      assert %{x: %Giggly.Scale.Continuous{range: {2.62, 17.02}}} = Giggly.panel_scales(plot)
    end

    test "a panel the plot does not have is refused rather than read as nothing" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      error = assert_raise ArgumentError, fn -> Giggly.panel_scales(plot, 2) end
      assert error.message =~ "no panel 2"
      assert error.message =~ "panel(s) 1"
    end

    test "a free discrete axis gives each panel the levels of its own rows, placed from 1" do
      plot =
        %{"cyl" => ["6", "4", "8", "6"], "mpg" => [21.0, 22.8, 18.7, 19.2], "am" => [1, 1, 0, 0]}
        |> Plot.new(%{x: :cyl, y: :mpg})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:am, scales: :free_x)

      assert {Giggly.panel_scales(plot, 1).x, Giggly.panel_scales(plot, 2).x} ==
               {%Giggly.Scale.Discrete{
                  levels: ["6", "8"],
                  continuous_range: {1, 2},
                  palette: :identity,
                  na_value: nil,
                  guide: :axis
                },
                %Giggly.Scale.Discrete{
                  levels: ["4", "6"],
                  continuous_range: {1, 2},
                  palette: :identity,
                  na_value: nil,
                  guide: :axis
                }}

      # Each row on its own panel's scale, in row order: "8" is the second level of panel 1's.
      frame = Giggly.layer_data(plot)
      assert DataFrame.pull(frame, :x) == [2, 1, 2, 1]
    end

    test "a fixed axis shares one scale across the panels, a free one beside it does not" do
      plot =
        %{"wt" => [1.0, 2.0, 3.0, 9.0], "mpg" => [10.0, 20.0, 30.0, 40.0], "am" => [0, 0, 1, 1]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:am, scales: :free_y)

      assert {Giggly.panel_scales(plot, 1), Giggly.panel_scales(plot, 2)} ==
               {%{
                  x: %Giggly.Scale.Continuous{
                    range: {1.0, 9.0},
                    transform: :identity,
                    palette: :identity,
                    na_value: nil,
                    guide: :axis
                  },
                  y: %Giggly.Scale.Continuous{
                    range: {10.0, 20.0},
                    transform: :identity,
                    palette: :identity,
                    na_value: nil,
                    guide: :axis
                  }
                },
                %{
                  x: %Giggly.Scale.Continuous{
                    range: {1.0, 9.0},
                    transform: :identity,
                    palette: :identity,
                    na_value: nil,
                    guide: :axis
                  },
                  y: %Giggly.Scale.Continuous{
                    range: {30.0, 40.0},
                    transform: :identity,
                    palette: :identity,
                    na_value: nil,
                    guide: :axis
                  }
                }}
    end

    test "an axis's scale is of the kind its columns need, on the y axis as on the x" do
      plot =
        @mixed_rows
        |> Plot.new(%{x: :wt, y: :cyl})
        |> Plot.geom_point()

      assert %{x: %Giggly.Scale.Continuous{}, y: %Giggly.Scale.Discrete{levels: ["4", "6"]}} =
               Giggly.panel_scales(plot)
    end

    test "an axis no layer maps gets an untrained continuous scale" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      assert %{x: %Giggly.Scale.Continuous{range: :none}} = Giggly.panel_scales(plot)
    end
  end

  describe "to_svg/2" do
    # Golden: test/golden/point.svg. The data spans x 0 to 10 and y 0 to 50 in columns wt and mpg,
    # as ggplot2's own snapshot `tests/testthat/_snaps/coord-cartesian/expand-range.svg` does, and
    # the drawing is checked against ggplot2's drawing of the same plot, made by
    # test/golden/point.R, element by element: the plot's and the panel's backgrounds, every grid
    # line, point, tick, label and title match it in position, size, colour and textLength, and
    # the panel's clip path and its group are svglite's for the same panel, id included. It is
    # drawn at vdiffr's size, 960 by 768 pixels (10 by 8 inches), so it can be set beside ggplot2's
    # own snapshots. The
    # row missing its mpg is not drawn but still widens the x axis, as in ggplot2. It moves only
    # with a change to what a plot draws: the drawing's size, the theme, the look of the points,
    # the expansion, the breaks, a plot title arriving, or the markup.
    test "each row with an x and a y is drawn as a point, with titled axes below and to the left" do
      plot =
        %{"wt" => [0.0, 4.0, 7.0, 10.0], "mpg" => [0.0, 50.0, 20.0, nil]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/point.svg")
    end

    # Golden: test/golden/col.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/col.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. geom_col()'s example from ggplot2's reference page:
    # three bars 0.9 wide on a discrete axis, from 0, which the y axis reaches once its scale is
    # trained again on the bars' edges; the discrete axis has major grid lines at its levels and no
    # minor ones. It moves with what moves test/golden/point.svg, and with the bars' geometry or
    # look.
    test "columns draw a bar from 0 to each y, 0.9 wide on a discrete axis" do
      plot =
        %{"trt" => ["a", "b", "c"], "outcome" => [2.3, 1.9, 3.2]}
        |> Plot.new(%{x: :trt, y: :outcome})
        |> Plot.geom_col()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/col.svg")
    end

    # Golden: test/golden/alpha.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/alpha.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. geom_col()'s example with alpha set on two layers:
    # the columns' fill half opaque and their border, which they do not draw, untouched; the points
    # a third opaque, outline and fill, written as R holds a colour's alpha, 85 of 255. It moves
    # with what moves test/golden/col.svg, and with how an opacity is drawn or written.
    test "an alpha set on a layer makes a column's fill and a point's outline and fill transparent" do
      plot =
        %{"trt" => ["a", "b", "c"], "outcome" => [2.3, 1.9, 3.2]}
        |> Plot.new(%{x: :trt, y: :outcome})
        |> Plot.geom_col(alpha: 0.5)
        |> Plot.geom_point(alpha: 1 / 3)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/alpha.svg")
    end

    # Golden: test/golden/alpha_legend.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/alpha_legend.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. The first example on ggplot2's scale_alpha page:
    # each point as opaque as its year on 0.1 to 1, and the legend, titled year, a key for each of
    # 2000 to 2008 by 2, drawn as its own table right of the panel, centred down it, the panel
    # narrowed to make room. It moves with what moves test/golden/point.svg, with alpha's scale,
    # and with the legend's look or layout.
    test "a mapped alpha has a legend right of the panel, a key for each of its scale's breaks" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy})
        |> Plot.geom_point(%{alpha: :year})

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/alpha_legend.svg")
    end

    # Golden: the legend's box in ggplot2 4.0.3's drawing of the same plot through vdiffr 1.0.9 (R
    # 4.6.1), whose every element this drawing matches: the legend spans the panels' rows, from the
    # first's top to the last's bottom, the strip above the first left out, and is centred down
    # them. It moves with the legend's size or its place.
    test "beside several rows of panels the legend is centred on their whole span" do
      svg =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, alpha: :year})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:drv, ncol: 1)
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg =~ "<rect x='661.22' y='227.27' width='53.30' height='112.69'"
    end

    # Golden: test/golden/alpha_bars.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/alpha_bars.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. mpg's classes counted and shaded by drive train,
    # a text alpha that also groups the bars, the legend's keys drawn as bars, their fill short of
    # the key by their border's width. It moves with what moves test/golden/bar.svg and
    # test/golden/alpha_legend.svg.
    test "a discrete alpha shades counted bars by group, its legend's keys drawn as bars" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, alpha: :drv})
        |> Plot.geom_bar()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/alpha_bars.svg")
    end

    # Golden: test/golden/col_fill_colour.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/col_fill_colour.R: every element matches it, the x axis drawn before the y
    # as in test/golden/point.svg, and every clip path. position_dodge's columns dodged by group,
    # filled in R's grey50, written as its hex since CSS has no name for it, and bordered in black.
    # It moves with what moves test/golden/dodge.svg, and with how a bar's fill and border are
    # written.
    test "columns are filled and bordered in the colours the layer sets" do
      plot =
        %{"x" => ["a", "a", "b", "b"], "y" => [2, 3, 4, 5], "g" => [1, 2, 1, 2]}
        |> Plot.new(%{x: :x, y: :y, group: :g})
        |> Plot.geom_col(position: :dodge, fill: "#7F7F7F", colour: "black")

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/col_fill_colour.svg")
    end

    # Golden: test/golden/point_colour_legend.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/point_colour_legend.R: every element matches it, the x axis drawn
    # before the y as in test/golden/point.svg, and every clip path. mpg's points, every one
    # steelblue and as opaque as its cylinders, the alpha replacing the colour's own, and the
    # legend's keys in the layer's colour at each break's alpha. It moves with what moves
    # test/golden/alpha_legend.svg, and with how a point's colour is written.
    test "points are drawn in the colour the layer sets, and so are their legend's keys" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, alpha: :cyl})
        |> Plot.geom_point(colour: "steelblue")

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/point_colour_legend.svg")
    end

    # Golden: test/golden/point_colour_alpha.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/point_colour_alpha.R: every element matches it, the x axis drawn
    # before the y as in test/golden/point.svg, and every clip path. mpg's points, each in its
    # class's hue, seven round the circle, and as opaque as its cylinders: two legends stacked down
    # the right, alpha's above colour's, each left-aligned. It moves with what moves
    # test/golden/point_colour_legend.svg, with the hue palette, and with how legends stack.
    test "points are drawn in their class's hue, two legends stacked in their aesthetics' order" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, colour: :class, alpha: :cyl})
        |> Plot.geom_point()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/point_colour_alpha.svg")
    end

    # Golden: test/golden/point_shapes.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/point_shapes.R: every element matches it, in the same order, the x axis drawn
    # before the y as in test/golden/point.svg, and every clip path. Each of the 26 shapes, given as
    # a list to one annotation, outlined and filled at half their opacity: every shape's
    # rectangles, polygons, circles and lines where R's graphics engine puts them, in its order. It
    # moves with what moves test/golden/point.svg, and with a shape's geometry or how its elements
    # are written.
    test "each of a point's 26 shapes is drawn as R's graphics engine draws it" do
      shapes = Enum.to_list(0..25)

      plot =
        %{"x" => [0, 5], "y" => [0, 4]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.annotate(:point,
          x: Enum.map(shapes, fn shape -> rem(shape, 6) end),
          y: Enum.map(shapes, fn shape -> div(shape, 6) end),
          shape: shapes,
          size: 5,
          stroke: 1,
          colour: "blue",
          fill: "red",
          alpha: 0.5
        )

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/point_shapes.svg")
    end

    # Golden: test/golden/point_no_stroke.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/point_no_stroke.R: every element matches it, in the same order, R's
    # `stroke-width: nan` written `0.00`, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. The 26 shapes with no stroke but the last: no
    # outlines, no lines. It moves with what moves test/golden/point_shapes.svg.
    test "a point of no stroke is drawn with no outline and none of its lines" do
      shapes = Enum.to_list(0..25)

      strokes =
        :none
        |> List.duplicate(25)
        |> Enum.concat([1])

      plot =
        %{"x" => [0, 5], "y" => [0, 4]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.annotate(:point,
          x: Enum.map(shapes, fn shape -> rem(shape, 6) end),
          y: Enum.map(shapes, fn shape -> div(shape, 6) end),
          shape: shapes,
          size: 5,
          stroke: strokes,
          colour: "blue",
          fill: "red",
          alpha: 0.5
        )

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/point_no_stroke.svg")
    end

    # Golden: test/golden/point_fill_stroke.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/point_fill_stroke.R: every element matches it, in the same order,
    # the x axis drawn before the y as in test/golden/point.svg, and every clip path. geom_point()'s
    # example of a point's fill and border: a heavy stroke widens the outline and the circle. It
    # moves with what moves test/golden/point.svg.
    test "points are drawn in the shape, size, stroke and fill the layer sets" do
      plot =
        Giggly.Datasets.mtcars()
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(shape: 21, colour: "black", fill: "white", size: 5, stroke: 5)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/point_fill_stroke.svg")
    end

    # Golden: test/golden/point_fill_legend.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/point_fill_legend.R: every element matches it, in the same order,
    # the x axis drawn before the y as in test/golden/point.svg, and every clip path. mpg's points
    # filled by drive train from the plot's mapping, the fill legend's keys in the layer's shape
    # and size. It moves with what moves test/golden/point_colour_legend.svg.
    test "points draw in a fill legend, its keys in the shape and size the layer sets" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, fill: :drv})
        |> Plot.geom_point(shape: 21, size: 3)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/point_fill_legend.svg")
    end

    # Golden: test/golden/size_continuous.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/size_continuous.R: every element matches it, the x axis drawn before the y
    # as in test/golden/point.svg, and every clip path. scale_size()'s first example: mpg's points
    # sized by highway mileage, by area from 1 to 6 mm, a legend of three points in keys of the
    # theme's size. It moves with what moves test/golden/point_colour_legend.svg.
    test "points are sized by a mapped column, by area, with a legend of sized keys" do
      svg =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, size: :hwy})
        |> Plot.geom_point()
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/size_continuous.svg")
    end

    # Golden: test/golden/size_range.svg and test/golden/size_area.svg, checked against ggplot2's
    # drawings of the same plots, made by test/golden/size_range.R and test/golden/size_area.R:
    # every element matches, the x axis drawn before the y as in test/golden/point.svg, and every
    # clip path. The same points sized by area from 0 to 10 mm, the legend's keys widened to the
    # largest point and each row as tall as its own; and by area in proportion to the mileage, 0 at
    # size 0. They move with what moves test/golden/size_continuous.svg.
    test "a size scale's range sizes the points and its keys, and size_area draws 0 at size 0" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, size: :hwy})
        |> Plot.geom_point()

      drawn = fn scaled ->
        scaled
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()
      end

      ranged = Plot.scale_size_continuous(plot, range: {0, 10})
      by_area = Plot.scale_size_area(plot)

      assert drawn.(ranged) == File.read!("test/golden/size_range.svg")
      assert drawn.(by_area) == File.read!("test/golden/size_area.svg")
    end

    # Golden: test/golden/count.svg and test/golden/count_size_area.svg, checked against ggplot2's
    # drawings of the same plots, made by test/golden/count.R and test/golden/count_size_area.R:
    # every element matches, the x axis drawn before the y as in test/golden/point.svg, and every
    # clip path. geom_count()'s reference examples: mpg's mileages, a point at each pair sized by
    # how many rows hold it, by area from 1 to 6 mm, then in proportion to its count. They move with
    # what moves test/golden/size_continuous.svg.
    test "a count layer sizes a point at each place by its count, with a size legend titled n" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :cty, y: :hwy})
        |> Plot.geom_count()

      drawn = fn scaled ->
        scaled
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()
      end

      by_area = Plot.scale_size_area(plot)

      assert drawn.(plot) == File.read!("test/golden/count.svg")
      assert drawn.(by_area) == File.read!("test/golden/count_size_area.svg")
    end

    # Golden: test/golden/count_prop.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/count_prop.R: every element matches it but the background's edge, which
    # svglite writes as R's rounding error, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. mpg's classes and drive trains, each point sized
    # by its share of every row. It moves with what moves test/golden/count.svg.
    test "a count layer sizes its points by their shares on discrete axes, titled prop" do
      svg =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, y: :drv})
        |> Plot.geom_count(%{size: {:after_stat, [:prop]}, group: 1})
        |> Plot.scale_size_area(max_size: 10)
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/count_prop.svg")
    end

    # Golden: test/golden/count_colour.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/count_colour.R: every element matches it, the x axis drawn before the y
    # as in test/golden/point.svg, and every clip path. Counts coloured by drive train, the colour
    # legend above the size legend. It moves with what moves test/golden/count.svg and
    # test/golden/point_colour_legend.svg.
    test "a count layer's colour counts each value apart, its legend beside the size legend" do
      svg =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :cty, y: :hwy, colour: :drv})
        |> Plot.geom_count()
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/count_colour.svg")
    end

    # Golden: test/golden/size_merged_rows.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/size_merged_rows.R: every element matches it, the x axis drawn before the
    # y as in test/golden/point.svg, and every clip path. Cylinders as a factor mapped to size and
    # colour, sized by area from 4 to 12 mm: one merged legend, its keys' column as wide as the
    # largest point and each row as tall as its own point or the theme's key. It moves with what
    # moves test/golden/size_continuous.svg, and with how legends merge.
    test "a discrete size merges with a colour of the same column, each key row its point's height" do
      svg =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, size: {:factor, [:cyl]}, colour: {:factor, [:cyl]}})
        |> Plot.geom_point()
        |> Plot.scale_size_discrete(range: {4, 12})
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/size_merged_rows.svg")
    end

    # Golden: test/golden/shape_solid.svg and test/golden/shape_open.svg, checked against ggplot2's
    # drawings of the same plots, made by the R script beside each: every element matches, the x
    # axis drawn before the y as in test/golden/point.svg, and every clip path. scale_shape()'s first
    # example and its `solid = FALSE`: a hundred diamonds R picks at random, each cut in one of the
    # palette's shapes. R's cut is an ordered factor; the limits give the scale its levels' order,
    # which Giggly's column of strings would sort alphabetically. They move with what moves
    # test/golden/point_shapes.svg, and with how a legend lays out its keys.
    test "a discrete shape draws each value in one of six shapes, solid or open, with a legend" do
      cuts = ["Fair", "Good", "Very Good", "Premium", "Ideal"]

      diamonds =
        @diamond_sample
        |> diamond_rows()
        |> Plot.new(%{x: :carat, y: :price})
        |> Plot.geom_point(%{shape: :cut})

      assert {to_svg(Plot.scale_shape_discrete(diamonds, limits: cuts)),
              to_svg(Plot.scale_shape_discrete(diamonds, limits: cuts, solid: false))} ==
               {File.read!("test/golden/shape_solid.svg"),
                File.read!("test/golden/shape_open.svg")}
    end

    # Golden: test/golden/shape_filled.svg, test/golden/shape_missing.svg and
    # test/golden/shape_colour.svg, checked against ggplot2's drawings of the same plots, made by the
    # R script beside each: every element matches, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. Drive trains in shapes 21 to 23 a manual scale
    # gives, filled red and sized 3 by the layer, its keys too; a missing value unshaped, its NA key
    # drawing no glyph; and shape and colour of one column in one legend. They move with what
    # moves test/golden/shape_solid.svg, and with how legends merge.
    test "a manual shape scale's keys take the layer's set look, a missing key none, a merged one colour" do
      mpg = Plot.new(Giggly.Datasets.mpg(), %{x: :displ, y: :hwy, shape: :drv})

      filled =
        mpg
        |> Plot.geom_point(fill: "red", size: 3)
        |> Plot.scale_shape_manual(values: [21, 22, 23])

      missing =
        %{"x" => [1, 2, 3, 4, 5], "y" => [1, 2, 3, 4, 5], "g" => ["a", "b", nil, "c", "a"]}
        |> Plot.new(%{x: :x, y: :y, shape: :g})
        |> Plot.geom_point()

      colored =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, shape: :drv, colour: :drv})
        |> Plot.geom_point()

      assert {to_svg(filled), to_svg(missing), to_svg(colored)} ==
               {File.read!("test/golden/shape_filled.svg"),
                File.read!("test/golden/shape_missing.svg"),
                File.read!("test/golden/shape_colour.svg")}
    end

    # Golden: test/golden/count_shape.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/count_shape.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. Counts shaped by drive train, the shape legend
    # above the size legend. It moves with what moves test/golden/count.svg and
    # test/golden/shape_solid.svg.
    test "a count layer's shape counts each value apart, its legend above the size legend" do
      svg =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :cty, y: :hwy, shape: :drv})
        |> Plot.geom_count()
        |> to_svg()

      assert svg == File.read!("test/golden/count_shape.svg")
    end

    # Golden: test/golden/linetype_economics.svg, test/golden/linetype_colour.svg and
    # test/golden/linetype_manual.svg, checked against ggplot2's drawings of the same plots, made by
    # the R script beside each: every element matches, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. scale_linetype()'s own example, economics_long's
    # five series in the palette's first five line types; the same mapped to colour too, one
    # legend; and line types given by name and by pattern, a missing series drawing no line and its
    # key none. They move with what moves test/golden/date_line.svg and test/golden/line_types.svg.
    test "a mapped line type draws each line dashed as its value's, a key for each in the legend" do
      economics_long = Plot.new(Giggly.Datasets.economics_long(), %{x: :date, y: :value01})

      manual =
        %{
          "x" => [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3],
          "y" => [1, 2, 1.5, 2, 3, 2.5, 3, 4, 3.5, 4, 5, 4.5],
          "g" => ["a", "a", "a", "b", "b", "b", "c", "c", "c", nil, nil, nil]
        }
        |> Plot.new(%{x: :x, y: :y, linetype: :g})
        |> Plot.geom_line()
        |> Plot.scale_linetype_manual(values: [:dotted, :dotdash, {3, 3, 1, 3}])

      typed = Plot.geom_line(economics_long, %{linetype: :variable})
      colored = Plot.geom_line(economics_long, %{linetype: :variable, colour: :variable})

      assert {to_svg(typed), to_svg(colored), to_svg(manual)} ==
               {File.read!("test/golden/linetype_economics.svg"),
                File.read!("test/golden/linetype_colour.svg"),
                File.read!("test/golden/linetype_manual.svg")}
    end

    # Golden: test/golden/linewidth_economics.svg, test/golden/linewidth_name.svg and
    # test/golden/linewidth_range.svg, checked against ggplot2's drawings of the same plots, made by
    # the R script beside each: every element matches, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. scale_linewidth()'s first three examples:
    # economics's unemployment as wide as the median duration of unemployment, a segment from each
    # month to the next with round ends; the legend titled over two lines; and widths from 0 to 4
    # mm, the narrowest written 0.040 points wide as svglite writes a number below 0.1. They move
    # with what moves test/golden/date_line.svg and test/golden/line_key_big.svg.
    test "a mapped width draws a line a segment at a time, each as wide as the month it starts from" do
      widths =
        Giggly.Datasets.economics()
        |> Plot.new(%{x: :date, y: :unemploy, linewidth: :uempmed})
        |> Plot.geom_line(lineend: :round)

      named = Plot.scale_linewidth_continuous(widths, name: "Duration of\nunemployment")
      ranged = Plot.scale_linewidth_continuous(widths, range: {0, 4})

      assert {to_svg(widths), to_svg(named), to_svg(ranged)} ==
               {File.read!("test/golden/linewidth_economics.svg"),
                File.read!("test/golden/linewidth_name.svg"),
                File.read!("test/golden/linewidth_range.svg")}
    end

    # Golden: test/golden/linewidth_bar.svg, test/golden/linewidth_missing.svg and
    # test/golden/annotate_widths.svg, checked against ggplot2's drawings of the same plots, made by
    # the R script beside each: every element matches, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. mpg's classes stacked by drive train, each bar's
    # border in its drive train's line type and width, one legend for both, its keys widened to
    # hold their borders; a line whose width is missing at both ends and once between, the ends
    # dropped and the segment from the missing one not drawn; and a path annotation whose width
    # grows along it. They move with what moves test/golden/bar_key_big.svg and
    # test/golden/line_key_big.svg.
    test "a bar's border takes a mapped type and width, and a missing width draws no segment" do
      bars =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar(%{linetype: :drv, linewidth: :drv}, colour: "black")

      missing =
        %{"x" => [1, 2, 3, 4, 5, 6], "y" => [1, 3, 2, 4, 3, 5], "w" => [nil, 1, 2, nil, 3, nil]}
        |> Plot.new(%{x: :x, y: :y, linewidth: :w})
        |> Plot.geom_line()

      annotated =
        %{"x" => [1, 2, 3, 4], "y" => [1, 3, 2, 4]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point()
        |> Plot.annotate(:path, x: [1, 2, 3, 4], y: [2, 4, 3, 1], linewidth: [0.5, 2, 4, 6])

      assert {to_svg(bars), to_svg(missing), to_svg(annotated)} ==
               {File.read!("test/golden/linewidth_bar.svg"),
                File.read!("test/golden/linewidth_missing.svg"),
                File.read!("test/golden/annotate_widths.svg")}
    end

    # Golden: test/golden/point_key_big.svg, test/golden/bar_key_big.svg,
    # test/golden/line_key_big.svg, test/golden/text_key_big.svg and
    # test/golden/text_key_turned.svg, checked against ggplot2's drawings of the same plots, made by
    # the R script beside each: every element matches, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. A point set to 8 mm, a bar bordered 4 mm wide, a
    # line 8 mm wide, and text at 12 mm and at 8 mm turned 30 degrees, each in a colour or fill
    # legend whose keys widen to fit it, as ggplot2's `set_key_size()` and `draw_key_text()` size
    # them. They move with what moves test/golden/point_colour_legend.svg.
    test "a legend's keys widen to fit what the layers set too big for the theme's key" do
      mpg = Giggly.Datasets.mpg()
      lines = %{"x" => [1, 2, 1, 2], "y" => [1, 2, 2, 1], "g" => ["a", "a", "b", "b"]}
      labelled = Plot.new(mpg, %{x: :displ, y: :hwy, colour: :drv, label: :drv})

      plots = [
        {"point_key_big",
         mpg
         |> Plot.new(%{x: :displ, y: :hwy, colour: :drv})
         |> Plot.geom_point(size: 8)},
        {"bar_key_big",
         mpg
         |> Plot.new(%{x: :class, fill: :drv})
         |> Plot.geom_bar(colour: "black", linewidth: 4)},
        {"line_key_big",
         lines
         |> Plot.new(%{x: :x, y: :y, colour: :g})
         |> Plot.geom_line(linewidth: 8)},
        {"text_key_big", Plot.geom_text(labelled, size: 12)},
        {"text_key_turned", Plot.geom_text(labelled, size: 8, angle: 30, hjust: 0, vjust: 1)}
      ]

      for {name, plot} <- plots do
        svg =
          plot
          |> Giggly.to_svg(width: 960, height: 768)
          |> IO.iodata_to_binary()

        assert svg == File.read!("test/golden/#{name}.svg"), name
      end
    end

    # Golden: test/golden/bar_fill.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/bar_fill.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. geom_bar()'s example from ggplot2's reference page:
    # mpg's classes counted and stacked by drive train, each filled in its hue, the layer's fill
    # numbering the bars before the plot's x, and a legend of bar keys. It moves with what moves
    # test/golden/alpha_bars.svg, and with the hue palette.
    test "counted bars are filled in their drive train's hue, a fill the layer maps" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar(%{fill: :drv})

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/bar_fill.svg")
    end

    # Golden: test/golden/line_colour_missing.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/line_colour_missing.R: every element matches it, the x axis drawn
    # before the y as in test/golden/point.svg, and every clip path. Three lines grouped by their
    # colour, the one whose colour is missing in grey50, its key last and labelled NA. It moves with
    # what moves test/golden/line_missing.svg, and with the hue palette.
    test "lines are drawn in their group's hue, a missing colour in grey50" do
      plot =
        %{
          "x" => [1, 2, 3, 1, 2, 3, 1, 2, 3],
          "y" => [1, 3, 2, 2, 1, 3, 3, 2, 1],
          "g" => ["a", "a", "a", "b", "b", "b", nil, nil, nil]
        }
        |> Plot.new(%{x: :x, y: :y, colour: :g})
        |> Plot.geom_line()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/line_colour_missing.svg")
    end

    # Golden: test/golden/merged_legend.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/merged_legend.R: every element matches it, the x axis drawn before the y
    # as in test/golden/point.svg, and every clip path. Columns filled by g and points coloured by
    # it, whose legends share a title and labels and so merge into one, each key drawn by both
    # layers, each in the aesthetic it maps alone. It moves with what moves test/golden/col.svg,
    # with the hue palette, and with how legends merge.
    test "a fill and a colour of one column merge into one legend, drawn by both layers" do
      plot =
        %{"x" => [1, 2, 3], "y" => [2, 3, 1], "g" => ["b", "a", "b"]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_col(%{fill: :g})
        |> Plot.geom_point(%{colour: :g})

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/merged_legend.svg")
    end

    # Golden: test/golden/point_colourbar.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/point_colourbar.R: every element matches vdiffr's but the colour bar's
    # fill, which vdiffr's device cannot draw, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path; the gradient's stops match svglite 2.2.2's line for
    # line, its ends at the bar's middle from bottom to top. mpg's points coloured by city mileage
    # along ggplot2's default gradient, and a colour bar in its gradient form. It moves with what
    # moves test/golden/point_colour_legend.svg, with the gradient palette, and with the colour bar.
    test "a continuous colour draws points along the gradient and a colour bar" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, colour: :cty})
        |> Plot.geom_point()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/point_colourbar.svg")
    end

    # Golden: test/golden/point_colourbar_alpha.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/point_colourbar_alpha.R, as test/golden/point_colourbar.svg is. A
    # legend and a colour bar, two kinds of guide, stacked down the right, alpha's above colour's.
    # It moves with what moves test/golden/point_colourbar.svg and test/golden/point_colour_alpha.svg.
    test "a colour bar stacks below a legend, each kind drawn by its guide" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, colour: :cty, alpha: :cyl})
        |> Plot.geom_point()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/point_colourbar_alpha.svg")
    end

    # Golden: test/golden/legend_layer_keys.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/legend_layer_keys.R: every element matches it, the x axis drawn before
    # the y as in test/golden/point.svg, and every clip path. Points coloured by g (a, b) and lines
    # by h (a, b, c): key c draws the line alone, as ggplot2 4's `keep_key_data()` leaves a layer
    # out of a key its column lacks. It moves with what moves test/golden/line_colour_missing.svg,
    # and with which layers draw in a key.
    test "a legend's key is drawn only by the layers whose columns hold its value" do
      plot =
        %{
          "x" => [1, 2, 3, 4],
          "y" => [1, 3, 2, 4],
          "g" => ["a", "b", "a", "b"],
          "h" => ["a", "b", "c", "c"]
        }
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{colour: :g})
        |> Plot.geom_line(%{colour: :h})

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/legend_layer_keys.svg")
    end

    # Golden: test/golden/line_missing.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/line_missing.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. The "Missing values break a line" example on
    # ggplot2's geom_path page: the line is two polylines either side of the missing y, and the
    # point with no y is not drawn. It moves with what moves test/golden/point.svg, and with how a
    # line is drawn or broken.
    test "a missing y breaks a line in two, and the point with no y is not drawn" do
      plot =
        %{"x" => [1, 2, 3, 4, 5], "y" => [1.0, 2.0, nil, 4.0, 5.0]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point()
        |> Plot.geom_line()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/line_missing.svg")
    end

    # Golden: test/golden/line_alpha.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/line_alpha.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. A line whose alpha changes along it is a segment
    # from each row to the next, in the alpha of the row it starts from, and its legend's keys are
    # segments across their middles. It moves with what moves test/golden/alpha_legend.svg, and
    # with how a line or its key is drawn.
    test "a line whose alpha changes along it is drawn segment by segment, its keys as lines" do
      plot =
        %{"x" => [1.0, 3.0, 2.0, 4.0], "y" => [1.0, 2.0, 4.0, 3.0], "z" => [1.0, 2.0, 3.0, 4.0]}
        |> Plot.new(%{x: :x, y: :y, alpha: :z})
        |> Plot.geom_line()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/line_alpha.svg")
    end

    # Golden: test/golden/line_types.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/line_types.R: every element matches it, in order, the x axis drawn before the y
    # as in test/golden/point.svg, and every clip path. Each of the seven named line types and a
    # pattern of its own, a path annotation each: dashed as svglite writes R's line types, each
    # length times the line's width in line-width units, alone for a line narrower than one, and
    # the blank line not drawn; and a legend's keys dashed as their lines. It moves with what moves
    # test/golden/line_alpha.svg, and with how a line is dashed.
    test "each line type is dashed as svglite writes it, on a line and on its legend's keys" do
      line_types = [:blank, :solid, :dashed, :dotted, :dotdash, :longdash, :twodash, {3, 3, 1, 3}]

      base =
        %{"x" => [0, 10, 0, 10], "y" => [10, 10, 11, 11], "g" => ["p", "p", "q", "q"]}
        |> Plot.new(%{x: :x, y: :y, colour: :g})
        |> Plot.geom_line(linetype: :longdash, linewidth: 1)

      plot =
        line_types
        |> Enum.with_index(1)
        |> Enum.reduce(base, fn {line_type, index}, annotated ->
          Plot.annotate(annotated, :path, x: [0, 10], y: index, linetype: line_type)
        end)
        |> Plot.annotate(:path, x: [0, 10], y: 9, linetype: :dashed, linewidth: 0.2)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/line_types.svg")
    end

    # Golden: test/golden/bar_line_types.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/bar_line_types.R: every element matches it, in order, the x axis drawn
    # before the y as in test/golden/point.svg, and every clip path. Bars bordered 1.5 mm wide and
    # dotted, their keys short of the key by 1.5 mm and bordered alike; a column annotation and a
    # rectangle annotation each given a list of the eight line types, the rectangles a list of
    # widths too, each border dashed at its own width and the blank one not drawn; and a dashed
    # rectangle with no border colour, its dashes written all the same. It moves with what moves
    # test/golden/bar_fill.svg, and with how a border is dashed.
    test "each line type is dashed as svglite writes it on a bar's border and on its key" do
      line_types = [:blank, :solid, :dashed, :dotted, :dotdash, :longdash, :twodash, {3, 3, 1, 3}]
      positions = Enum.to_list(3..10)

      plot =
        %{"x" => [1, 2], "y" => [3, 2], "g" => ["p", "q"]}
        |> Plot.new(%{x: :x, y: :y, fill: :g})
        |> Plot.geom_col(colour: "black", linewidth: 1.5, linetype: :dotted)
        |> Plot.annotate(:col, x: positions, y: 1, colour: "black", linetype: line_types)
        |> Plot.annotate(:rect,
          xmin: Enum.map(positions, fn position -> position - 0.45 end),
          xmax: Enum.map(positions, fn position -> position + 0.45 end),
          ymin: 2,
          ymax: 3,
          colour: "black",
          linetype: line_types,
          linewidth: [0.2, 0.2, 1, 1, 2, 2, 0.5, 0.5]
        )
        |> Plot.annotate(:rect, xmin: 0.55, xmax: 2.45, ymin: 3.5, ymax: 4, linetype: :dashed)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/bar_line_types.svg")
    end

    # An aesthetic a layer takes from the plot's mapping and cannot use is drawn by nothing, as
    # ggplot2's geoms leave it: a layer may set it, but its geom never reads the plot's column of
    # it as a value set, which once raised for a path's width and drew a point's size unscaled. A
    # number groups nothing, so the drawing is the plot's without the mapping.
    test "an aesthetic a layer carries unused from the plot's mapping changes nothing it draws" do
      data = %{"x" => [1, 2, 3], "y" => [1.0, 3.0, 2.0], "w" => [1, 2, 3]}

      for {add, aesthetic} <- [
            {&Plot.geom_path/1, :stroke},
            {&Plot.geom_point/1, :linewidth},
            {&Plot.geom_point/1, :stroke},
            {&Plot.geom_col/1, :stroke}
          ] do
        drawn = fn mapping ->
          data
          |> Plot.new(mapping)
          |> add.()
          |> Giggly.to_svg(width: 300, height: 200)
          |> IO.iodata_to_binary()
        end

        assert drawn.(%{:x => :x, :y => :y, aesthetic => :w}) == drawn.(%{x: :x, y: :y})
      end
    end

    # Golden: test/golden/date_line.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/date_line.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. geom_path's first example: economics's
    # unemployment from 1967 to 2015, the x axis a date scale with breaks every ten years, labelled
    # by year, and minor grid lines midway. It moves with what moves test/golden/line_missing.svg,
    # and with a date scale's breaks, labels or minor breaks.
    test "a line over dates has an axis of R's pretty dates, labelled by the step they take" do
      plot =
        Giggly.Datasets.economics()
        |> Plot.new(%{x: :date, y: :unemploy})
        |> Plot.geom_line()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/date_line.svg")
    end

    # Golden: test/golden/line_radial.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/line_radial.R: every element matches it, in order, and every clip path but
    # svglite's around the whole drawing, as test/golden/radial.svg's. Each piece of the line
    # changes both its angle and its radius, so it is munched as a spiral's arc and curves round
    # the circle. It moves with what moves test/golden/radial.svg, and with munching.
    test "in radial coordinates a line curves round the circle, each piece a spiral's arc" do
      plot =
        %{"x" => [1, 2, 3, 4, 5], "y" => [1.0, 3.0, 2.0, 5.0, 4.0]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_line()
        |> Plot.coord_radial()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/line_radial.svg")
    end

    # Golden: each key is the one ggplot2 4.0.3 draws for the same plot through vdiffr 1.0.9's
    # svglite (R 4.6.1), with the black stroke svglite leaves to its stylesheet written out. The
    # keys are 2 mm wide only because rendering hands each key what its layer sets; it moves with
    # how a key is drawn.
    test "a line's legend keys are as wide as the lines the layer sets" do
      keys =
        %{"x" => [1.0, 3.0, 2.0, 4.0], "y" => [1.0, 2.0, 4.0, 3.0], "z" => [1.0, 2.0, 3.0, 4.0]}
        |> Plot.new(%{x: :x, y: :y, alpha: :z})
        |> Plot.geom_line(linewidth: 2)
        |> data_lines()
        |> Enum.take(-4)

      assert keys === [
               "<line x1='683.12' y1='257.04' x2='696.94' y2='257.04' style='stroke-width: 4.27; " <>
                 "stroke: #000000; stroke-opacity: 0.10; stroke-linecap: butt;' />",
               "<line x1='683.12' y1='274.32' x2='696.94' y2='274.32' style='stroke-width: 4.27; " <>
                 "stroke: #000000; stroke-opacity: 0.40; stroke-linecap: butt;' />",
               "<line x1='683.12' y1='291.60' x2='696.94' y2='291.60' style='stroke-width: 4.27; " <>
                 "stroke: #000000; stroke-opacity: 0.70; stroke-linecap: butt;' />",
               "<line x1='683.12' y1='308.88' x2='696.94' y2='308.88' style='stroke-width: 4.27; " <>
                 "stroke: #000000; stroke-linecap: butt;' />"
             ]
    end

    # Golden: test/golden/bar.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/bar.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. geom_bar()'s first example from ggplot2's
    # reference page: the number of cars in each of mpg's classes, the y axis titled by the count
    # counting puts into it. It moves with what moves test/golden/col.svg, and with counting.
    test "counted bars rise to the number of rows at each level, the y axis titled count" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/bar.svg")
    end

    # Golden: test/golden/dodge.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/dodge.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. mpg's classes counted by drive train and dodged:
    # the groups at each class share one bar's width side by side, a class with one group keeping
    # all of it. It moves with what moves test/golden/bar.svg, and with dodging.
    test "dodged bars stand side by side within the width one bar takes" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, group: :drv})
        |> Plot.geom_bar(position: :dodge)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/dodge.svg")
    end

    # Golden: test/golden/horizontal_bar.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/horizontal_bar.R: every element matches it, the x axis drawn before the y
    # as in test/golden/point.svg, and every clip path. geom_bar()'s third example from ggplot2's
    # reference page: mpg's classes counted along y, the bars running rightward from 0 and the x
    # axis titled count. It moves with what moves test/golden/bar.svg, and with bar orientation.
    test "bars counted along y run rightward, the x axis titled count" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new()
        |> Plot.geom_bar(%{y: :class})

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/horizontal_bar.svg")
    end

    # Golden: test/golden/radial.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/radial.R: every element matches it, in order, and every clip path. The point
    # golden's data in radial coordinates: the panel is square and the table centred across the
    # drawing, the background a disc and the grid circles and spokes, munched as ggplot2 munches
    # them; the angle axis is drawn round the circle over the points, each label justified by its
    # angle, and the radius axis to the panel's left, its labels centred, up the panel's upper
    # half. It moves with what moves test/golden/point.svg, and with radial placing, munching, or
    # either radial axis's look.
    test "radial coordinates draw a square panel, its grid on a disc and its axes round and up it" do
      plot =
        %{"wt" => [0.0, 4.0, 7.0, 10.0], "mpg" => [0.0, 50.0, 20.0, nil]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.coord_radial()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/radial.svg")
    end

    # Golden: test/golden/facet_wrap.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/facet_wrap.R: every element, in order, and every clip path match it. Five
    # combinations of cyl and drv make five panels in two rows of three, the last row one short, so
    # the panel above the empty cell draws an x axis that hangs into it while its row takes no room
    # for it, and each panel has a strip for each column; the panels share the drawing equally,
    # the theme's spacing between them, and the titles are centred on them. It moves with what
    # moves test/golden/point.svg, and with the strips' look, the panel spacing, the layout of the
    # panels, or the order cells are drawn in.
    test "a wrapped facet draws a panel for each combination, with strips and axes at the margins" do
      plot =
        %{
          "wt" => [0.0, 4.0, 7.0, 10.0, 2.0, 5.0, 8.0, 3.0, 6.0],
          "mpg" => [0.0, 50.0, 20.0, 35.0, 10.0, 40.0, 25.0, 15.0, 30.0],
          "cyl" => [4, 4, 4, 6, 6, 6, 8, 8, 8],
          "drv" => ["f", "r", "r", "4", "4", "f", "f", "f", "f"]
        }
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.facet_wrap([:cyl, :drv])

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/facet_wrap.svg")
    end

    # Golden: test/golden/facet_wrap_radial.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/facet_wrap_radial.R: every element matches it, in order, and every strip's
    # clip path. test/golden/facet_wrap.svg's plot in radial coordinates: the five panels stay
    # square, the width running out first, so the table is centred down the drawing; each panel
    # draws its angle axis, the left column its radius axes, and no panel draws a bottom axis. It
    # moves with what moves test/golden/facet_wrap.svg and test/golden/radial.svg.
    test "faceted radial panels keep their shape together, the table centred in the drawing" do
      plot =
        %{
          "wt" => [0.0, 4.0, 7.0, 10.0, 2.0, 5.0, 8.0, 3.0, 6.0],
          "mpg" => [0.0, 50.0, 20.0, 35.0, 10.0, 40.0, 25.0, 15.0, 30.0],
          "cyl" => [4, 4, 4, 6, 6, 6, 8, 8, 8],
          "drv" => ["f", "r", "r", "4", "4", "f", "f", "f", "f"]
        }
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.facet_wrap([:cyl, :drv])
        |> Plot.coord_radial()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/facet_wrap_radial.svg")
    end

    # Golden: test/golden/facet_wrap_free.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/facet_wrap_free.R: every element, in order, and every clip path match it.
    # Each of five panels is on its own x and y scale, so each draws both axes; the first row's x
    # axes take room but for the one over the empty cell, and the left axes of panels b and e share
    # a column as wide as e's, b's sitting against its panel. It moves with what moves
    # test/golden/facet_wrap.svg, and with how free scales are trained or their axes placed.
    test "free scales give each panel its own scales, and each panel its own axes" do
      plot =
        %{
          "x" => [0.0, 10.0, 0.0, 1.0, 100.0, 200.0, 0.0, 4.0, 2.0, 3.0],
          "y" => [0.0, 50.0, 0.0, 5.0, 0.0, 500.0, 10.0, 20.0, 0.0, 1000.0],
          "g" => ["a", "a", "b", "b", "c", "c", "d", "d", "e", "e"]
        }
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:g, scales: :free)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/facet_wrap_free.svg")
    end

    # Golden: test/golden/facet_wrap_layer_data.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/facet_wrap_layer_data.R: every element, in order, and every clip
    # path match it. facet_wrap()'s "The same data in every panel" on test/golden/facet_wrap.svg's
    # points: the first layer's table lacks the facet column, so all nine points are drawn grey in
    # every panel, under each panel's own three, and the text layer's table holds a value the data
    # lacks, which makes a fourth panel where the other layers draw nothing but the grey points. It
    # moves with what moves test/golden/facet_wrap.svg and test/golden/text.svg, and with how the
    # tables make the panels or a table is repeated across them.
    test "a layer's own table is drawn in every panel without the facet column, or makes one" do
      data = [
        wt: [0.0, 4.0, 7.0, 10.0, 2.0, 5.0, 8.0, 3.0, 6.0],
        mpg: [0.0, 50.0, 20.0, 35.0, 10.0, 40.0, 25.0, 15.0, 30.0],
        cyl: [4, 4, 4, 6, 6, 6, 8, 8, 8]
      ]

      plot =
        data
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(data: Keyword.delete(data, :cyl), colour: "#D9D9D9")
        |> Plot.geom_point()
        |> Plot.geom_text(%{label: :label},
          data: [wt: [5.0], mpg: [25.0], cyl: [10], label: ["ten"]]
        )
        |> Plot.facet_wrap(:cyl)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/facet_wrap_layer_data.svg")
    end

    # Golden: test/golden/scale_continuous.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/scale_continuous.R: every element matches it, the x axis drawn before the
    # y as in test/golden/point.svg, and every clip path. An x scale named "Weight", which titles
    # the axis over labs(), from 2 to 5, so the points at 1.615 and 5.25 are not drawn, its breaks
    # given (1.9, below the limits but inside the widened axis, drawn; 1, outside it, not) and two
    # minor breaks given; a y scale with no labels, its ticks alone, and no room below its data. It
    # moves with what moves test/golden/point.svg, and with a continuous scale's options.
    test "a continuous scale's options set its axis's limits, breaks, labels, title and room" do
      plot =
        [wt: [2.62, 2.32, 3.215, 3.44, 5.25, 1.615], mpg: [21.0, 22.8, 21.4, 18.7, 10.4, 30.4]]
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.labs(x: "not drawn")
        |> Plot.scale_x_continuous(
          name: "Weight",
          limits: {2, 5},
          breaks: [1, 1.9, 3, 3.5, 5],
          minor_breaks: [2.25, 4.25]
        )
        |> Plot.scale_y_continuous(labels: :none, expand: [mult: {0, 0.05}])

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/scale_continuous.svg")
    end

    # Golden: test/golden/scale_bars_cut.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/scale_bars_cut.R: every element matches it and every clip path. mpg's
    # classes counted under a y scale from 0 to 50 with no breaks: the suv bar, 62 rows, reaches
    # past the limit once it is placed, so it is not drawn, and the y axis draws nothing and takes
    # no room. It moves with what moves test/golden/bar.svg, and with how limits censor a bar.
    test "a bar the limits cut is not drawn, and an axis with no breaks takes no room" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class})
        |> Plot.geom_bar()
        |> Plot.scale_y_continuous(limits: {0, 50}, breaks: :none)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/scale_bars_cut.svg")
    end

    # Golden: test/golden/scale_log10.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/scale_log10.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. mpg's highway mileage on a base-10 log axis, too
    # short a span for powers of ten, so marked at 20, 30 and 40, with minor grid lines midway in
    # log space. It moves with what moves test/golden/point.svg, and with the log transformation.
    test "a log axis is marked at multiples of ten in data units, its grid even in log space" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy})
        |> Plot.geom_point()
        |> Plot.scale_y_log10()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/scale_log10.svg")
    end

    # Golden: test/golden/scale_reverse.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/scale_reverse.R: every element matches it, the x axis drawn before the y
    # as in test/golden/point.svg, and every clip path. mtcars' mileage against weight with
    # xlim(20, 15), so the x axis runs from 20 down to 15 and the cars outside it are not drawn. It
    # moves with what moves test/golden/point.svg, and with the reverse transformation.
    test "limits given high to low run the axis from high to low" do
      plot =
        Giggly.Datasets.mtcars()
        |> Plot.new(%{x: :mpg, y: :wt})
        |> Plot.geom_point()
        |> Plot.xlim(20, 15)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/scale_reverse.svg")
    end

    # Golden: test/golden/scale_date_width.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/scale_date_width.R: every element matches it, the x axis drawn before
    # the y as in test/golden/point.svg, and every clip path. The scale_date page's `base`, its 30
    # days ending on 2026-10-19 and its prices R's runif(30) after set.seed(1), with a break every
    # week, each labelled by its day of the month, and a minor grid line every day. It moves with
    # what moves test/golden/date_line.svg, and with a date scale's width and format.
    test "a date scale's breaks every week, labelled in a format, and minor lines every day" do
      plot =
        @last_month
        |> Plot.new(%{x: :date, y: :price})
        |> Plot.geom_line()
        |> Plot.scale_x_date(
          date_breaks: [week: 1],
          date_labels: "%d",
          date_minor_breaks: [day: 1]
        )

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/scale_date_width.svg")
    end

    # Golden: test/golden/scale_date_limits.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/scale_date_limits.R: every element matches it, the x axis drawn
    # before the y as in test/golden/point.svg, and every clip path. The same month from a week
    # before its last day, the line through the earlier days not drawn, breaks every second day.
    # It moves with what moves test/golden/date_line.svg, and with a date scale's limits.
    test "a date scale's limits cut the line outside them" do
      plot =
        @last_month
        |> Plot.new(%{x: :date, y: :price})
        |> Plot.geom_line()
        |> Plot.scale_x_date(limits: {~D[2026-10-12], nil})

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/scale_date_limits.svg")
    end

    # Golden: test/golden/scale_continuous_dates.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/scale_continuous_dates.R: every element matches it, the x axis
    # drawn before the y as in test/golden/point.svg, and every clip path. economics's
    # unemployment under a continuous x scale, each date at its days since 1970-01-01 and the axis
    # labelled as numbers. It moves with what moves test/golden/date_line.svg, and with how a
    # continuous scale places a date.
    test "a continuous scale places dates at their days and labels them as numbers" do
      plot =
        Giggly.Datasets.economics()
        |> Plot.new(%{x: :date, y: :unemploy})
        |> Plot.geom_line()
        |> Plot.scale_x_continuous()

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/scale_continuous_dates.svg")
    end

    # Golden: test/golden/scale_discrete.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/scale_discrete.R: every element matches it, the x axis drawn before the y
    # as in test/golden/point.svg, and every clip path. mpg's highway mileage by class on a
    # discrete x scale named "Class" showing suv, wagon and compact: the other classes not drawn,
    # wagon's place empty, suv labelled by value. It moves with what moves
    # test/golden/point.svg, and with a discrete scale's options.
    test "a discrete scale's limits choose its values and their order, and its labels their text" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, y: :hwy})
        |> Plot.geom_point()
        |> Plot.scale_x_discrete(
          name: "Class",
          limits: ["suv", "wagon", "compact"],
          labels: %{"suv" => "SUV"}
        )

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/scale_discrete.svg")
    end

    # Golden: test/golden/scale_discrete_bars.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/scale_discrete_bars.R: every element matches it, the x axis drawn
    # before the y as in test/golden/point.svg, and every clip path. mpg's classes counted along y
    # on a discrete y scale showing suv, compact and midsize, marking compact and suv alone,
    # labelled by place, a whole level's room beside the first and last. It moves with what moves
    # test/golden/horizontal_bar.svg, and with a discrete scale's breaks, labels and expansion.
    test "a discrete scale's breaks mark some of its values, and its expansion sets its room" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{y: :class})
        |> Plot.geom_bar()
        |> Plot.scale_y_discrete(
          limits: ["suv", "compact", "midsize"],
          breaks: ["compact", "suv"],
          labels: ["Compact", "SUV"],
          expand: [add: 1]
        )

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/scale_discrete_bars.svg")
    end

    # Golden: test/golden/scale_manual.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/scale_manual.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. ggplot2's scale_manual example: mtcars's points
    # coloured by their cylinders through named colours, CSS's agreeing with R's for these four,
    # the legend's keys the breaks given, labelled as given. It moves with what moves
    # test/golden/point.svg, with a manual scale, and with a legend's breaks and labels.
    test "a manual colour scale colours each value by name, its legend's keys its breaks" do
      plot =
        Giggly.Datasets.mtcars()
        |> Plot.new(%{x: :mpg, y: :wt})
        |> Plot.geom_point(%{colour: {:factor, [:cyl]}})
        |> Plot.scale_color_manual(
          values: %{8 => "red", 4 => "blue", 6 => "darkgreen", 10 => "orange"},
          breaks: [4, 6, 8],
          labels: ["four", "six", "eight"]
        )

      assert to_svg(plot) == File.read!("test/golden/scale_manual.svg")
    end

    # Golden: test/golden/scale_manual_limits.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/scale_manual_limits.R: every element matches it, the x axis drawn
    # before the y as in test/golden/point.svg, and every clip path. A manual scale's limits name
    # 10, which mtcars lacks: its key is drawn on its background, orange, with no point in it. It
    # moves with what moves test/golden/scale_manual.svg, and with which keys a layer draws in.
    test "a manual scale's limit the data lacks has a key with no glyph in it" do
      plot =
        Giggly.Datasets.mtcars()
        |> Plot.new(%{x: :mpg, y: :wt})
        |> Plot.geom_point(%{colour: {:factor, [:cyl]}})
        |> Plot.scale_color_manual(
          values: %{8 => "red", 4 => "blue", 6 => "darkgreen", 10 => "orange"},
          limits: [4, 6, 8, 10]
        )

      assert to_svg(plot) == File.read!("test/golden/scale_manual_limits.svg")
    end

    # Golden: test/golden/scale_hue.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/scale_hue.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. mpg's points coloured by drive train through
    # hues from 0 to 90 degrees, spread end to end, chroma 150 and luminance 70, in reverse. It
    # moves with what moves test/golden/point.svg, and with the hue palette.
    test "a hue scale's options choose its hues, chroma, luminance and direction" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, colour: :drv})
        |> Plot.geom_point()
        |> Plot.scale_color_hue(hue: {0, 90}, luminance: 70, chroma: 150, direction: -1)

      assert to_svg(plot) == File.read!("test/golden/scale_hue.svg")
    end

    # Golden: test/golden/scale_gray_bars.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/scale_gray_bars.R: every element matches it, the x axis drawn before the
    # y as in test/golden/point.svg, and every clip path. mpg's classes counted, each bar stacked
    # by drive train and filled in greys from 0.2 to 0.8, as R's grey.colors() spaces them. It
    # moves with what moves test/golden/bar_fill.svg, and with the grey palette.
    test "a grey fill scale fills each value in a grey, spaced evenly to the eye" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, fill: :drv})
        |> Plot.geom_bar()
        |> Plot.scale_fill_gray()

      assert to_svg(plot) == File.read!("test/golden/scale_gray_bars.svg")
    end

    # Golden: test/golden/scale_alpha_range.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/scale_alpha_range.R: every element matches it, the x axis drawn
    # before the y as in test/golden/point.svg, and every clip path. ggplot2's scale_alpha
    # examples in one: each point as opaque as its year on 0 to 1, 1999's invisible, the legend
    # titled by the scale's name. It moves with what moves test/golden/alpha_legend.svg, and with
    # an alpha scale's options.
    test "an alpha scale's range sets its opacities, and its name titles its legend" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy})
        |> Plot.geom_point(%{alpha: :year})
        |> Plot.scale_alpha_continuous(name: "cylinders", range: {0, 1})

      assert to_svg(plot) == File.read!("test/golden/scale_alpha_range.svg")
    end

    # Golden: test/golden/legend_unlabelled.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/legend_unlabelled.R: every element matches it, the x axis drawn
    # before the y as in test/golden/point.svg, and every clip path. A colour legend with no
    # labels: its keys alone under its title, the labels' column and margin left out, so the panel
    # is that much wider. It moves with what moves test/golden/point_colour_legend.svg, and with a
    # legend's layout.
    test "a legend with no labels leaves out their column and its margin" do
      plot =
        Giggly.Datasets.mtcars()
        |> Plot.new(%{x: :mpg, y: :wt})
        |> Plot.geom_point(%{colour: {:factor, [:cyl]}})
        |> Plot.scale_color_discrete(labels: :none)

      assert to_svg(plot) == File.read!("test/golden/legend_unlabelled.svg")
    end

    # Golden: test/golden/guide_legend_reverse.svg, checked against ggplot2's drawing of the same
    # plot, made by test/golden/guide_legend_reverse.R: every element matches it, the x axis drawn
    # before the y as in test/golden/point.svg, and every clip path. guide_legend()'s reference
    # page's reversed legend, twenty keys from t at the top down to a. It moves with what moves
    # test/golden/point_colour_legend.svg.
    test "a legend reversed by guides/2 runs from its last key to its first" do
      letters = Enum.map(?a..?t, fn code -> <<code>> end)

      plot =
        %{"x" => Enum.to_list(1..20), "y" => Enum.to_list(1..20), "color" => letters}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{color: :color})
        |> Plot.guides(color: Plot.guide_legend(reverse: true))

      assert to_svg(plot) == File.read!("test/golden/guide_legend_reverse.svg")
    end

    # Golden: test/golden/legend_continuous_reverse.svg, checked against ggplot2's drawing of the
    # same plot, made by test/golden/legend_continuous_reverse.R: every element matches it, the x
    # axis drawn before the y as in test/golden/point.svg, and every clip path. mtcars's points
    # coloured by horsepower along the default gradient, read back by a reversed legend in place
    # of the colour bar: a point key for each break, the highest at the top. It moves with what
    # moves test/golden/point_colour_legend.svg, and with a gradient's colours.
    test "a continuous colour scale's guide: may be a legend, its keys at its breaks" do
      plot =
        Giggly.Datasets.mtcars()
        |> Plot.new(%{x: :mpg, y: :wt, colour: :hp})
        |> Plot.geom_point()
        |> Plot.scale_color_gradient(guide: Plot.guide_legend(reverse: true))

      assert to_svg(plot) == File.read!("test/golden/legend_continuous_reverse.svg")
    end

    # Golden: test/golden/legends_reverse_unmerged.svg, checked against ggplot2's drawing of the
    # same plot, made by test/golden/legends_reverse_unmerged.R: every element matches it, the x
    # axis drawn before the y as in test/golden/point.svg, and every clip path. mpg's classes
    # counted, each bar outlined and filled by drive train, the colour's legend reversed, so its
    # labels no longer read as the fill's and the two stack apart. It moves with what moves
    # test/golden/bar_fill.svg, and with how legends merge.
    test "a reversed legend merges with none whose keys run the other way" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :class, fill: :drv, colour: :drv})
        |> Plot.geom_bar()
        |> Plot.guides(color: Plot.guide_legend(reverse: true))

      assert to_svg(plot) == File.read!("test/golden/legends_reverse_unmerged.svg")
    end

    # Golden: test/golden/scale_gradient.svg, checked against ggplot2's drawing of the same plot,
    # made by test/golden/scale_gradient.R: every element matches vdiffr's but the colour bar's
    # fill, which vdiffr cannot draw, every gradient stop matches svglite's, the gradient at the
    # middle of its own rectangle in each, and every clip path matches. mpg's points coloured by
    # city mileage from white to black, blended in Lab. It moves with what moves
    # test/golden/point_colourbar.svg, and with a gradient's colours.
    test "a gradient scale blends from its low colour to its high" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, colour: :cty})
        |> Plot.geom_point()
        |> Plot.scale_color_gradient(low: "white", high: "black")

      assert to_svg(plot) == File.read!("test/golden/scale_gradient.svg")
    end

    # Golden: test/golden/scale_gradient2.svg, checked as test/golden/scale_gradient.svg is, against
    # test/golden/scale_gradient2.R's drawings. City mileage diverging from white at 20: 35, the
    # end further from it, dark blue in full, 9 only as far toward dark red as it reaches; the
    # colour bar's ticks at the breaks given, labelled as given, placed over the range whatever
    # the midpoint. It moves with what moves test/golden/scale_gradient.svg, and with a midpoint.
    test "a diverging gradient centres its colours on its midpoint" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, colour: :cty})
        |> Plot.geom_point()
        |> Plot.scale_color_gradient2(
          midpoint: 20,
          breaks: [10, 20, 30],
          labels: ["ten", "twenty", "thirty"]
        )

      assert to_svg(plot) == File.read!("test/golden/scale_gradient2.svg")
    end

    # Golden: test/golden/scale_gradientn.svg, checked as test/golden/scale_gradient.svg is, against
    # test/golden/scale_gradientn.R's drawings. City mileage through R's terrain.colors(10),
    # written out, spaced evenly over limits of 10 to 30: the cars outside them grey50, the colour
    # bar spanning the limits. It moves with what moves test/golden/scale_gradient.svg, and with a
    # continuous colour scale's limits.
    test "a gradient through many colours spans the limits, a value outside them grey" do
      terrain =
        ~w(#00A600 #2DB600 #63C600 #A0D600 #E6E600 #E8C32E #EBB25E #EDB48E #F0C9C0 #F2F2F2)

      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, colour: :cty})
        |> Plot.geom_point()
        |> Plot.scale_color_gradientn(colors: terrain, limits: {10, 30})

      assert to_svg(plot) == File.read!("test/golden/scale_gradientn.svg")
    end

    # Golden: test/golden/scale_gradient_na_none.svg, checked as test/golden/scale_gradient.svg
    # is, against test/golden/scale_gradient_na_none.R's drawings. Six points from yellow to red,
    # the two whose value is missing mapped to none and so not drawn, though the axes span them;
    # the colour bar spans the four values there are. It moves with what moves
    # test/golden/scale_gradient.svg, and with how a point whose colour is none is left out.
    test "a value its scale maps to :none draws no point, though the axes span it" do
      plot =
        %{"x" => Enum.to_list(1..6), "y" => [2, 4, 3, 6, 5, 1], "z" => [nil, 1, 2, nil, 3, 4]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point(%{colour: :z})
        |> Plot.scale_color_gradient(low: "yellow", high: "red", na_value: :none)

      assert to_svg(plot) == File.read!("test/golden/scale_gradient_na_none.svg")
    end

    # Golden: test/golden/colorbar_unlabelled.svg, checked as test/golden/scale_gradient.svg is,
    # against test/golden/colorbar_unlabelled.R's drawings. A colour bar through a palette of three
    # colours with no labels, under a title wider than the bar: its ticks drawn, the labels'
    # column and margin left out, the bar at the title's left. It moves with what moves
    # test/golden/scale_gradient.svg, and with a colour bar's layout.
    test "a colour bar with no labels keeps its ticks and leaves out the labels' room" do
      plot =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, colour: :cty})
        |> Plot.geom_point()
        |> Plot.scale_color_continuous(
          name: "a much wider title",
          palette: ["#FEE0D2", "#FC9272", "#DE2D26"],
          labels: :none
        )

      assert to_svg(plot) == File.read!("test/golden/colorbar_unlabelled.svg")
    end

    test "a labels function that gives no string for each break is refused when drawn" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.scale_x_continuous(labels: fn _breaks -> ["only one"] end)

      assert_raise ArgumentError, ~r/labels function must return a string for each/, fn ->
        Giggly.to_svg(plot)
      end
    end

    # Golden: test/golden/annotate.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/annotate.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. annotate()'s examples on six points: a band shaded
    # from the panel's left edge to 2, foot to top, its corners infinite; the shaded rectangle under
    # the points; one text at four places; two labels in step with their places and colours; and a
    # label beyond the data, which both axes reach. No annotation titles an axis, so the points'
    # mapping does. It moves with what moves test/golden/point.svg and test/golden/text.svg, and
    # with how an annotation's values become its table.
    test "annotations draw their values, the axes reaching them, and title no axis" do
      plot =
        [wt: [2.62, 2.32, 3.215, 3.44, 5.25, 1.615], mpg: [21.0, 22.8, 21.4, 18.7, 10.4, 30.4]]
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.annotate(:rect,
          xmin: :neg_infinity,
          xmax: 2,
          ymin: :neg_infinity,
          ymax: :infinity,
          fill: "steelblue",
          alpha: 0.2
        )
        |> Plot.annotate(:rect, xmin: 3, xmax: 4.2, ymin: 12, ymax: 21, alpha: 0.2)
        |> Plot.geom_point()
        |> Plot.annotate(:text, x: [2, 3, 4, 5], y: 25, label: "Some text")
        |> Plot.annotate(:text,
          x: [2, 3],
          y: [15, 16],
          label: ["my label", "label 2"],
          colour: ["red", "blue"]
        )
        |> Plot.annotate(:text, x: 6, y: 35, label: "beyond")

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/annotate.svg")
    end

    # Golden: test/golden/rect.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/rect.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. geom_rect()'s "Rectangles by their corners" with
    # its corners in the table: each rectangle filled by its level and bordered in grey50, the
    # legend's keys drawn as rectangles; and a layer of one row with its corners set, from the
    # panel's foot to 2, which widens the x axis to 16. Mapping only corners, the plot titles no
    # axis. It moves with how a bar or rectangle is drawn, with the hue palette and the legend.
    test "rectangles are drawn between their corners, mapped or set" do
      xs = [2.0, 5.0, 7.0, 9.0, 12.0, 2.0, 5.0, 7.0, 9.0, 12.0]
      widths = [4.0, 2.0, 2.0, 2.0, 4.0, 4.0, 2.0, 2.0, 2.0, 4.0]
      ys = [1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 2.0, 2.0, 2.0, 2.0]

      plot =
        [
          left: Enum.zip_with(xs, widths, fn x, width -> x - width / 2 end),
          right: Enum.zip_with(xs, widths, fn x, width -> x + width / 2 end),
          bottom: ys,
          top: Enum.map(ys, fn y -> y + 1 end),
          z: ["1", "1", "2", "2", "3", "3", "4", "4", "5", "6"]
        ]
        |> Plot.new(%{xmin: :left, xmax: :right, ymin: :bottom, ymax: :top})
        |> Plot.geom_rect(%{fill: :z}, colour: "#7F7F7F")
        |> Plot.geom_rect(
          data: [a: [1]],
          xmin: 14,
          xmax: 16,
          ymin: :neg_infinity,
          ymax: 2,
          fill: "steelblue"
        )

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/rect.svg")
    end

    # Golden: test/golden/text.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/text.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. geom_text()'s "Avoid overlaps" example: each car's
    # name centred on its weight and mileage, black and 11 points, and the 8 that would cross a name
    # drawn before them left out. It moves with what moves test/golden/point.svg, with how text is
    # measured, and with grid's test for crossing boxes.
    test "text draws each row's label at its place, leaving out those that would cross another" do
      plot =
        Giggly.Datasets.mtcars()
        |> Plot.new(%{x: :wt, y: :mpg, label: :model})
        |> Plot.geom_text(check_overlap: true)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/text.svg")
    end

    # Golden: test/golden/text_legend.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/text_legend.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. Each car's name in its cylinders' hue, half opaque
    # and turned 45 degrees; the legend's keys are the letter "a" in each hue at the layer's alpha,
    # turned with the labels. It moves with what moves test/golden/text.svg, with the hue palette,
    # and with how a turned label is placed and written.
    test "text in a mapped colour, turned and transparent, keys its legend with a turned letter" do
      mtcars = Giggly.Datasets.mtcars()

      cars = %{
        "model" => Keyword.fetch!(mtcars, :model),
        "wt" => Keyword.fetch!(mtcars, :wt),
        "mpg" => Keyword.fetch!(mtcars, :mpg),
        "cyl" =>
          mtcars
          |> Keyword.fetch!(:cyl)
          |> Enum.map(fn cylinders ->
            cylinders
            |> round()
            |> Integer.to_string()
          end)
      }

      plot =
        cars
        |> Plot.new(%{x: :wt, y: :mpg, label: :model, colour: :cyl})
        |> Plot.geom_text(angle: 45, alpha: 0.5)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/text_legend.svg")
    end

    # Golden: test/golden/text_inward.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/text_inward.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. geom_text()'s "Justification" example: labels at
    # the data's corners and middle, each justified inward both ways. It moves with what moves
    # test/golden/text.svg, and with how a word justifies a label.
    test "text justified inward sits inside the panel against its corner, centred in the middle" do
      plot =
        %{
          "x" => [1, 1, 2, 2, 1.5],
          "y" => [1, 2, 1, 2, 1.5],
          "text" => ["bottom-left", "top-left", "bottom-right", "top-right", "center"]
        }
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_text(%{label: :text}, vjust: :inward, hjust: :inward)

      svg =
        plot
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/text_inward.svg")
    end

    # Golden: test/golden/labs.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/labs.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. ggtheme's "The default theme" example: every label
    # labs() sets, the plot's title, subtitle, caption and tag among them. It moves with what moves
    # test/golden/point.svg, with the legend's layout, and with how the plot's labels are drawn.
    test "labs titles the axes and the legend, and gives the plot a title, subtitle, caption and tag" do
      svg =
        Giggly.Datasets.mtcars()
        |> Plot.new()
        |> Plot.geom_point(%{x: :wt, y: :mpg, colour: {:factor, [:gear]}})
        |> Plot.labs(
          title: "Fuel economy declines as weight increases",
          subtitle: "(1973-74)",
          caption: "Data from the 1974 Motor Trend US magazine.",
          tag: "Figure 1",
          x: "Weight (1000 lbs)",
          y: "Fuel economy (mpg)",
          colour: "Gears"
        )
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/labs.svg")
    end

    # Golden: test/golden/labs_none.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/labs_none.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. scale_continuous()'s "Removing axis titles"
    # example. It moves with what moves test/golden/point.svg.
    test "a label of :none removes an axis's title and the room it took" do
      svg =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy})
        |> Plot.geom_point()
        |> Plot.labs(x: :none, y: :none)
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/labs_none.svg")
    end

    # Golden: test/golden/labs_lines.svg, checked against ggplot2's drawing of the same plot, made by
    # test/golden/labs_lines.R: every element matches it, and every clip path. Every label over two
    # lines, on mpg faceted by year. It moves with what moves test/golden/labs.svg and
    # test/golden/facet_wrap.svg, and with how a label's lines are spaced.
    test "a label breaking over lines is drawn a line at a time, spanning the panels" do
      svg =
        Giggly.Datasets.mpg()
        |> Plot.new(%{x: :displ, y: :hwy, colour: :drv})
        |> Plot.geom_point()
        |> Plot.facet_wrap(:year)
        |> Plot.labs(
          title: "Fuel economy\nby engine size",
          subtitle: "Highway mileage,\nby year",
          caption: "Source:\nggplot2's mpg",
          tag: "A\nB",
          x: "Engine\ndisplacement (l)",
          y: "Highway\nmpg",
          colour: "Drive\ntrain"
        )
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/labs_lines.svg")
    end

    # Golden: test/golden/labs_untitled.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/labs_untitled.R: every element matches it but the colour bar's fill, which
    # vdiffr's device cannot draw, the x axis drawn before the y as in test/golden/point.svg, and
    # every clip path. It moves with the legend's and the colour bar's layouts.
    test "a legend and a colour bar whose labels are :none take no room for a title" do
      mtcars = Giggly.Datasets.mtcars()

      gears =
        mtcars
        |> Keyword.fetch!(:gear)
        |> Enum.map(fn gear ->
          gear
          |> round()
          |> Integer.to_string()
        end)

      svg =
        %{
          "wt" => Keyword.fetch!(mtcars, :wt),
          "mpg" => Keyword.fetch!(mtcars, :mpg),
          "qsec" => Keyword.fetch!(mtcars, :qsec),
          "gear" => gears
        }
        |> Plot.new(%{x: :wt, y: :mpg, colour: :qsec, alpha: :gear})
        |> Plot.geom_point()
        |> Plot.labs(colour: :none, alpha: :none)
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/labs_untitled.svg")
    end

    # Golden: ggplot2 4.0.3's drawing with vdiffr 1.0.9 of the same plot: the tag's lines centred at
    # 37.04 points, the margin and half the longer line's width, and the panel from 103.26.
    test "a title over several lines is as wide as its widest line" do
      svg =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.labs(tag: "A\nLonger tag")
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg =~ "<text x='37.04' y='15.93' text-anchor='middle'"
      assert svg =~ "<text x='37.04' y='30.19' text-anchor='middle'"
      assert svg =~ "<rect x='103.26' y='31.56' width='611.27' height='513.55'"
    end

    # ggplot2 4.0.3 with vdiffr 1.0.9: `labs(x = "")` places every other element where a one-line
    # title leaves it, and writes no text for the title.
    test "an empty label keeps its title's room and draws nothing" do
      draw = fn title ->
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()
        |> Plot.labs(x: title)
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()
      end

      titled = draw.("Weight")
      [titled_element] = Regex.run(~r/<text[^\n]*>Weight<\/text>\n/, titled)

      assert String.replace(titled, titled_element, "") == draw.("")
    end

    # Golden: test/golden/text_nudge.svg, checked against ggplot2's drawing of the same plot, made
    # by test/golden/text_nudge.R: every element matches it, the x axis drawn before the y as in
    # test/golden/point.svg, and every clip path. position_nudge()'s "Or, in brief" example: points
    # on a discrete y axis, each labelled with its level a tenth of a level below it. It moves with
    # what moves test/golden/text.svg, and with how a label is nudged.
    test "text nudged down on a discrete axis sits a tenth of a level below its point" do
      svg =
        %{"x" => [1.0, 3.0, 2.0, 5.0], "y" => ["a", "c", "d", "c"]}
        |> Plot.new(%{x: :x, y: :y})
        |> Plot.geom_point()
        |> Plot.geom_text(%{label: :y}, nudge_y: -0.1)
        |> Giggly.to_svg(width: 960, height: 768)
        |> IO.iodata_to_binary()

      assert svg == File.read!("test/golden/text_nudge.svg")
    end

    test "a label's &, < and > are escaped, so a level cannot break the document" do
      svg =
        %{"make" => ["<a & b>"], "mpg" => [21.0]}
        |> Plot.new(%{x: :make, y: :mpg})
        |> Plot.geom_point()
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()

      assert svg =~ ">&lt;a &amp; b&gt;</text>"
    end

    test "an axis is titled by the first layer to map it, through that layer's own mapping" do
      svg =
        %{"wt" => [2.62], "hp" => [110], "mpg" => [21.0]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(%{x: :hp})
        |> Plot.geom_point()
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()

      assert svg =~ ">hp</text>"
    end

    # Drawn at the default size, 700 by 433 pixels, which the document gives in points.
    test "a plot with no layers maps no axis, so it draws its backgrounds but no axes or titles" do
      svg =
        %{"wt" => [2.62], "mpg" => [21.0]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Giggly.to_svg()
        |> IO.iodata_to_binary()

      assert svg ==
               "<svg xmlns='http://www.w3.org/2000/svg' width='525.00pt' height='324.75pt' " <>
                 "viewBox='0 0 525.00 324.75' " <>
                 "stroke-linecap='round' stroke-linejoin='round' stroke-miterlimit='10.00'>\n" <>
                 "<defs>\n  <clipPath id='cpMC4wMHw1MjUuMDB8MC4wMHwzMjQuNzU='>\n" <>
                 "    <rect x='0.00' y='0.00' width='525.00' height='324.75' />\n" <>
                 "  </clipPath>\n</defs>\n" <>
                 "<g clip-path='url(#cpMC4wMHw1MjUuMDB8MC4wMHwzMjQuNzU=)'>\n" <>
                 "<rect x='0.00' y='0.00' width='525.00' height='324.75' " <>
                 "style='stroke-width: 1.07; stroke: #FFFFFF; fill: #FFFFFF;' />\n</g>\n" <>
                 "<defs>\n  <clipPath id='cpNS40OHw1MTkuNTJ8NS40OHwzMTkuMjc='>\n" <>
                 "    <rect x='5.48' y='5.48' width='514.04' height='313.79' />\n" <>
                 "  </clipPath>\n</defs>\n" <>
                 "<g clip-path='url(#cpNS40OHw1MTkuNTJ8NS40OHwzMTkuMjc=)'>\n" <>
                 "<rect x='5.48' y='5.48' width='514.04' height='313.79' " <>
                 "style='stroke-width: 1.07; stroke: none; fill: #EBEBEB;' />\n</g>\n</svg>\n"
    end

    test "an option it does not take is refused at the call, naming the option" do
      plot =
        %{"wt" => [2.62], "mpg" => [21.0]}
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      error =
        assert_raise NimbleOptions.ValidationError, fn -> Giggly.to_svg(plot, widht: 700) end

      assert error.key == [:widht]
    end
  end

  # The layer's shapes, and the legend's keys, each its label and shape, of a plot of `rows`
  # with `column` mapped to shape, through `scaled`.
  defp shapes_and_keys(scaled, rows \\ @drives, column \\ :drv) do
    plot =
      rows
      |> Plot.new(%{x: :x, y: :y, shape: column})
      |> Plot.geom_point()
      |> scaled.()

    [legend] = Giggly.Assembly.run(plot).legends
    keys = Enum.map(legend.keys, fn key -> {key.label, key.values.shape} end)

    shapes =
      plot
      |> Giggly.layer_data()
      |> DataFrame.pull(:shape)

    {shapes, keys}
  end

  # Each row's `aesthetic` in the plot's layer's table, and each key of its one legend, its label
  # and its value of `aesthetic`.
  defp values_and_keys(plot, aesthetic) do
    [legend] = Giggly.Assembly.run(plot).legends
    keys = Enum.map(legend.keys, fn key -> {key.label, Map.fetch!(key.values, aesthetic)} end)

    values =
      plot
      |> Giggly.layer_data()
      |> DataFrame.pull(aesthetic)

    {values, keys}
  end

  # `values_and_keys/2` of lines whose line type `@series`'s `g` maps, put through `scaled`.
  defp line_types(scaled) do
    @series
    |> Plot.new(%{x: :x, y: :y, linetype: :g})
    |> Plot.geom_line()
    |> scaled.()
    |> values_and_keys(:linetype)
  end

  # The rows of `Giggly.Datasets.diamonds/0` at `indices`, counted from 1 as R counts rows, each
  # column a list.
  defp diamond_rows(indices) do
    Map.new(Giggly.Datasets.diamonds(), fn {name, values} ->
      column = List.to_tuple(values)
      {name, Enum.map(indices, fn index -> elem(column, index - 1) end)}
    end)
  end

  defp edges(frame) do
    Map.new([:xmin, :xmax, :ymin, :ymax, :y], fn name -> {name, DataFrame.pull(frame, name)} end)
  end

  # The plot drawn at vdiffr's size, 720 by 576 points, as its goldens are.
  defp to_svg(plot) do
    plot
    |> Giggly.to_svg(width: 960, height: 768)
    |> IO.iodata_to_binary()
  end

  # The lines a plot's layers and legend draw, as its drawing at vdiffr's size writes them: every
  # polyline and line but the grid's, white, and the ticks', grey.
  defp data_lines(plot) do
    plot
    |> Giggly.to_svg(width: 960, height: 768)
    |> IO.iodata_to_binary()
    |> String.split("\n")
    |> Enum.filter(fn line -> String.starts_with?(line, ["<polyline", "<line "]) end)
    |> Enum.reject(fn line -> String.contains?(line, ["#FFFFFF", "#333333"]) end)
  end
end
