defmodule Scales.PaletteTest do
  use ExUnit.Case, async: true

  alias Scales.{ColorOperations, Palette}

  doctest Scales.Palette

  # Golden: scales 1.4.0's `pal_identity()`, `pal_rescale()`, `pal_area()` and `abs_area()` in R
  # 4.6.1, each palette handed the places, `NA` as `nil`, R's figures to the last digit.
  describe "continuous/2 of a number's palettes" do
    test "the identity leaves each place as it is" do
      assert Palette.continuous(:identity, [1, 2.5, nil]) === [1, 2.5, nil]
    end

    test "a rescale palette moves each place onto its range, a missing one left missing" do
      assert {Palette.continuous({:rescale, {2, 5}}, [0, 0.3, 1, nil]),
              Palette.continuous({:rescale, {1.0, 6.0}}, [0.5])} ===
               {[2.0, 2.8999999999999999, 5.0, nil], [3.5]}
    end

    test "an area palette moves each place's square root onto its range, so the area grows" do
      assert Palette.continuous({:area, {1.0, 6.0}}, [0.5, 0.2, 1, nil]) ===
               [4.5355339059327378, 3.2360679774997898, 6.0, nil]
    end

    test "an absolute area palette takes a place below 0 by its distance, and one past 1 beyond" do
      assert Palette.continuous({:abs_area, 6.0}, [4, 2, 1, -0.5, -0.25, 0.25, nil]) ===
               [12.0, 8.4852813742385713, 6.0, 4.2426406871192857, 3.0, 3.0, nil]
    end
  end

  # Golden: scales 1.4.0's `pal_gradient_n()` and `colour_ramp()` in R 4.6.1, through farver
  # 2.1.2: the gradient matched R's on all 30,054 places sampled through six sets of colours, among
  # them R's `terrain.colors(10)` and ggplot2's gradient2 default, `muted("red")`, white and
  # `muted("blue")`. A place at a colour takes that colour exactly.
  describe "continuous/2 of a gradient" do
    @terrain ~w(#00A600 #2DB600 #63C600 #A0D600 #E6E600 #E8C32E #EBB25E #EDB48E #F0C9C0 #F2F2F2)

    test "two colours blend between their ends as R's approxfun blends L*, a* and b*" do
      assert Palette.continuous({:gradient, ["#132B43", "#56B1F7"]}, [0, 0.5, 1, 0.25, 0.75, nil]) ===
               ["#132B43", "#336A98", "#56B1F7", "#22496C", "#448DC6", nil]
    end

    test "the colours are spaced evenly, a place between two blended, one at a colour exactly" do
      assert Palette.continuous(
               {:gradient, @terrain},
               [0, 0.25, 0.5, 1, 0.1111111111111111, 0.44444444444444442]
             ) === ["#00A600", "#74CA00", "#E7D520", "#F2F2F2", "#2DB600", "#E6E600"]
    end

    test "three colours blend through the middle one" do
      assert Palette.continuous(
               {:gradient, ["#832424", "#FFFFFF", "#3A3A98"]},
               [0, 0.25, 0.5, 0.75, 1]
             ) === ["#832424", "#C89089", "#FFFFFF", "#A197CC", "#3A3A98"]
    end

    test "one colour is every place's" do
      assert Palette.continuous({:gradient, ["#4682B4"]}, [0, 0.3, 1, nil]) ===
               ["#4682B4", "#4682B4", "#4682B4", nil]
    end
  end

  # Golden: scales 1.4.0's `pal_hue(h, c, l, direction = )(n)` in R 4.6.1, through farver 2.1.2;
  # the palette matched R's for every count from 1 to 40 at the default and on 2,160 ranges,
  # chromas, luminances, directions and counts. A count of 24 ends on a hue of exactly 360, and
  # 40 on 366, which R takes modulo 360 first. A range less than a degree short of the circle,
  # modulo 360 as R's `%%` takes it, leaves its last share off: 10 to 370.5 does, 10 to 371 does
  # not, and 375 to 15 does.
  describe "discrete/2 of a hue palette" do
    test "the hues are spaced round the circle, its last share left off" do
      colours = fn count -> hues({15.0, 375.0}, count) end

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

    test "a range is spread end to end unless it is within a degree of the whole circle" do
      assert {hues({0.0, 90.0}, 4), hues({10.0, 370.5}, 3), hues({10.0, 371.0}, 3),
              hues({375.0, 15.0}, 3), hues({200.0, 100.0}, 3)} ===
               {["#FF6C91", "#ED813E", "#CD9600", "#9DA700"], ["#FB737A", "#00B820", "#43A0FF"],
                ["#FB737A", "#00C0BD", "#FA7377"], ["#F8766D", "#00BA38", "#619CFF"],
                ["#00BECD", "#00BE67", "#88AC00"]}
    end

    test "a direction of -1 hands the colours out in reverse, and chroma and luminance set them" do
      assert {hues({15.0, 375.0}, 3, direction: -1),
              hues({15.0, 375.0}, 3, chroma: 30.0, luminance: 70.0)} ===
               {["#619CFF", "#00BA38", "#F8766D"], ["#CEA09E", "#8BB594", "#9FABCC"]}
    end

    # R's `pal_hue()(0)` fails ("Must request at least one colour from a hue palette."), where
    # `pal_grey()(0)` gives none.
    test "no levels give no colours" do
      assert {hues({15.0, 375.0}, 0), Palette.discrete({:gray, {0.2, 0.8}}, 0)} === {[], []}
    end
  end

  # Golden: scales 1.4.0's `pal_grey(start, end)(n)`, grDevices' `grey.colors()`, in R 4.6.1;
  # the palette matched R's for every count from 1 to 40 on seven ranges.
  describe "discrete/2 of a grey palette" do
    test "the greys run from start to end, spaced evenly once raised to the power 2.2" do
      greys = fn range, count -> Palette.discrete({:gray, range}, count) end

      assert {greys.({0.2, 0.8}, 1), greys.({0.2, 0.8}, 2), greys.({0.2, 0.8}, 5),
              greys.({0.2, 0.0}, 4), greys.({1.0, 0.0}, 3)} ===
               {["#333333"], ["#333333", "#CCCCCC"],
                ["#333333", "#737373", "#989898", "#B4B4B4", "#CCCCCC"],
                ["#333333", "#2A2A2A", "#1F1F1F", "#000000"], ["#FFFFFF", "#BABABA", "#000000"]}
    end
  end

  describe "discrete/2 of a viridis palette" do
    # `Scales.ColorOperations`' tests pin viridisLite's colours.
    test "the levels take viridis's colours, the palette's options passed on" do
      parameters = %{option: :magma, begin: 0.2, end: 1.0, direction: -1, alpha: 0.5}

      assert Palette.discrete({:viridis, parameters}, 3) ===
               ColorOperations.viridis(3, parameters)
    end
  end

  # Golden: scales 1.4.0's `pal_shape()`, `pal_linetype()` and `pal_manual()` in R 4.6.1:
  # `pal_shape()(7)` is `16 17 15 3 7 8 NA`, `pal_shape(FALSE)(7)` `1 2 0 3 7 8 NA`, each number
  # here its name; `pal_linetype()` is `pal_manual()` over `"solid"`, `"22"`, `"42"`, `"44"`,
  # `"13"`, `"1343"`, `"73"`, `"2262"`, `"12223242"`, `"F282"`, `"F4448444"`, `"224282F2"` and
  # `"F1"`, each held as its dash pattern, a hex digit its length; and past a manual palette's end
  # R gives `NA` and warns.
  describe "discrete/2 of a shape, line type or manual palette" do
    test "the shapes are R's six, solid or open, and nil past them" do
      assert {Palette.discrete({:shape, :solid}, 7), Palette.discrete({:shape, :open}, 7)} ===
               {[:circle_small, :triangle, :square, :plus, :square_cross, :asterisk, nil],
                [:circle_open, :triangle_open, :square_open, :plus, :square_cross, :asterisk, nil]}
    end

    test "the line types are R's 13 dash patterns in order, and nil past them" do
      assert Palette.discrete(:linetype, 14) === [
               {},
               {2, 2},
               {4, 2},
               {4, 4},
               {1, 3},
               {1, 3, 4, 3},
               {7, 3},
               {2, 2, 6, 2},
               {1, 2, 2, 2, 3, 2, 4, 2},
               {15, 2, 8, 2},
               {15, 4, 4, 4, 8, 4, 4, 4},
               {2, 2, 4, 2, 8, 2, 15, 2},
               {15, 1},
               nil
             ]
    end

    test "a manual palette gives its first values, one for each level" do
      assert Palette.discrete({:manual, ["#FF0000", "#0000FF", "#00FF00"]}, 2) ===
               ["#FF0000", "#0000FF"]
    end
  end

  # Golden: R 4.6.1's `seq(0.1, 1, length.out = n)` for n of 7, 2, 1 and 0.
  describe "spread/2" do
    test "the spread is R's seq(), its middle values found by steps from the first" do
      assert Palette.spread({0.1, 1.0}, 7) === [
               0.1,
               0.25,
               0.4,
               0.54999999999999993,
               0.69999999999999996,
               0.84999999999999998,
               1.0
             ]
    end

    test "one number is the low end, two are both ends, and none is none" do
      assert {Palette.spread({0.1, 1.0}, 1), Palette.spread({0.1, 1.0}, 2),
              Palette.spread({0.1, 1.0}, 0)} === {[0.1], [0.1, 1.0], []}
    end
  end

  # `count` colours of R's `pal_hue(h = range)`, chroma 100, luminance 65 and direction 1 unless
  # `options` say otherwise.
  defp hues(range, count, options \\ []) do
    parameters = Enum.into(options, %{hue: range, chroma: 100.0, luminance: 65.0, direction: 1})
    Palette.discrete({:hue, parameters}, count)
  end
end
