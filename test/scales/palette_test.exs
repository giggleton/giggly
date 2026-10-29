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

    # One colour reads no place, so only the check refuses one.
    test "a place that is neither a number nor nil is refused, even by one colour" do
      assert_raise FunctionClauseError, fn ->
        Palette.continuous({:gradient, ["#4682B4"]}, [:infinity])
      end
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

    # R's `pal_manual()` takes a vector, whose names it drops; matching values by name is a
    # scale's, not the palette's.
    # The map is built as the test runs: a literal the guard refuses fails the type checker.
    test "a manual palette's values are a list, and a map is refused" do
      named = Map.new([{"a", "#FF0000"}])

      assert_raise FunctionClauseError, fn -> Palette.discrete({:manual, named}, 1) end
    end
  end

  # Golden: scales 1.4.0's `pal_brewer()` in R 4.6.1, with RColorBrewer 1.1-3; past a palette's
  # largest set R gives `NA` and warns.
  describe "discrete/2 of a brewer palette" do
    test "each count from 3 to the largest takes the palette's own set" do
      assert {brewer("Blues", 3), brewer("Blues", 9), brewer("RdBu", 5)} ===
               {["#DEEBF7", "#9ECAE1", "#3182BD"],
                [
                  "#F7FBFF",
                  "#DEEBF7",
                  "#C6DBEF",
                  "#9ECAE1",
                  "#6BAED6",
                  "#4292C6",
                  "#2171B5",
                  "#08519C",
                  "#08306B"
                ], ["#CA0020", "#F4A582", "#F7F7F7", "#92C5DE", "#0571B0"]}
    end

    test "fewer than 3 levels take the start of the set of 3, and none take none" do
      assert {brewer("Blues", 2), brewer("Blues", 1), brewer("Blues", 0)} ===
               {["#DEEBF7", "#9ECAE1"], ["#DEEBF7"], []}
    end

    test "past the largest set each level is nil" do
      assert brewer("Paired", 13) === [
               "#A6CEE3",
               "#1F78B4",
               "#B2DF8A",
               "#33A02C",
               "#FB9A99",
               "#E31A1C",
               "#FDBF6F",
               "#FF7F00",
               "#CAB2D6",
               "#6A3D9A",
               "#FFFF99",
               "#B15928",
               nil
             ]
    end

    test "a direction of -1 reverses the set once it is padded, so the nils come first" do
      assert {brewer("Blues", 4, -1), brewer("Blues", 10, -1)} ===
               {["#2171B5", "#6BAED6", "#BDD7E7", "#EFF3FF"],
                [
                  nil,
                  "#08306B",
                  "#08519C",
                  "#2171B5",
                  "#4292C6",
                  "#6BAED6",
                  "#9ECAE1",
                  "#C6DBEF",
                  "#DEEBF7",
                  "#F7FBFF"
                ]}
    end

    # R's `pal_brewer(palette = "set1")` warns and gives Greens.
    test "a name R does not spell so is refused" do
      assert_raise FunctionClauseError, fn -> brewer("set1", 3) end
    end
  end

  # Golden: scales 1.4.0's `scales:::brewer`, the names `pal_brewer(type, palette)` numbers, and
  # `pal_brewer("qual", 5)(3)` and `pal_brewer("div", 2)(3)` in R 4.6.1.
  describe "brewer_palettes/1" do
    test "each type's names are in R's order, so a number picks R's palette" do
      assert {Palette.brewer_palettes(:seq), Palette.brewer_palettes(:div)} ===
               {[
                  "Blues",
                  "BuGn",
                  "BuPu",
                  "GnBu",
                  "Greens",
                  "Greys",
                  "Oranges",
                  "OrRd",
                  "PuBu",
                  "PuBuGn",
                  "PuRd",
                  "Purples",
                  "RdPu",
                  "Reds",
                  "YlGn",
                  "YlGnBu",
                  "YlOrBr",
                  "YlOrRd"
                ],
                [
                  "BrBG",
                  "PiYG",
                  "PRGn",
                  "PuOr",
                  "RdBu",
                  "RdGy",
                  "RdYlBu",
                  "RdYlGn",
                  "Spectral"
                ]}

      qualitative = Palette.brewer_palettes(:qual)
      diverging = Palette.brewer_palettes(:div)
      fifth_qualitative = Enum.at(qualitative, 4)
      second_diverging = Enum.at(diverging, 1)

      assert {brewer(fifth_qualitative, 3), brewer(second_diverging, 3)} ===
               {["#B3E2CD", "#FDCDAC", "#CBD5E8"], ["#E9A3C9", "#F7F7F7", "#A1D76A"]}
    end

    # The type is built as the test runs: a literal the guard refuses fails the type checker.
    test "a type R does not have is refused" do
      type = Enum.at([:sequential], 0)

      assert_raise FunctionClauseError, fn -> Palette.brewer_palettes(type) end
    end
  end

  # Golden: scales 1.4.0's `palette_type()` and `palette_nlevels()` in R 4.6.1: `pal_identity()`
  # and `abs_area(6)` `NA` and `NA`, `pal_rescale()` and `pal_area()` `"numeric"` and `NA`,
  # `pal_gradient_n()` `"colour"` and `NA`, `pal_hue()`, `pal_grey()` and `pal_viridis()` `"colour"`
  # and 255, `pal_shape()` `"shape"` and 6, `pal_linetype()` `"linetype"` and 13, `pal_brewer()`
  # `"colour"` and 9 for Set1, 12 for Paired, 11 for Spectral and 8 for Accent; `pal_manual()`
  # `"numeric"` for numbers, `"colour"` for colours, lowercase hex, an alpha and no values,
  # `"character"` for other strings or a colour beside `NA`, `"logical"` for `TRUE` and `FALSE`, and
  # its values' count.
  describe "type/1 and nlevels/1" do
    test "each palette's type and levels are R's" do
      palettes = [
        :identity,
        {:abs_area, 6.0},
        {:rescale, {0.1, 1.0}},
        {:area, {1.0, 6.0}},
        {:gradient, ["#132B43", "#56B1F7"]},
        {:hue, %{hue: {15.0, 375.0}, chroma: 100.0, luminance: 65.0, direction: 1}},
        {:gray, {0.2, 0.8}},
        {:viridis, %{option: :viridis, begin: 0.0, end: 1.0, direction: 1, alpha: 1.0}},
        {:shape, :solid},
        {:shape, :open},
        :linetype,
        {:brewer, %{palette: "Set1", direction: 1}},
        {:brewer, %{palette: "Paired", direction: -1}},
        {:brewer, %{palette: "Spectral", direction: 1}},
        {:brewer, %{palette: "Accent", direction: 1}}
      ]

      assert Enum.map(palettes, fn palette ->
               {Palette.type(palette), Palette.nlevels(palette)}
             end) ===
               [
                 {nil, nil},
                 {nil, nil},
                 {:numeric, nil},
                 {:numeric, nil},
                 {:color, nil},
                 {:color, 255},
                 {:color, 255},
                 {:color, 255},
                 {:shape, 6},
                 {:shape, 6},
                 {:linetype, 13},
                 {:color, 9},
                 {:color, 12},
                 {:color, 11},
                 {:color, 8}
               ]
    end

    test "a manual palette's type is guessed from its values, and its levels are its values" do
      manuals = [
        [1, 2.5, 9],
        ["#ff0000", "SteelBlue", "#FF000080"],
        [],
        ["a", "b"],
        ["#FF0000", nil],
        [true, false],
        [:circle_small, :triangle],
        ["#FF0000", 1]
      ]

      assert Enum.map(manuals, fn values ->
               {Palette.type({:manual, values}), Palette.nlevels({:manual, values})}
             end) ===
               [
                 {:numeric, 3},
                 {:color, 3},
                 {:color, 0},
                 {nil, 2},
                 {nil, 2},
                 {nil, 2},
                 {nil, 2},
                 {nil, 2}
               ]
    end

    # R's colour test is hex or one of its own names, so it reads these two the other way round.
    test "a colour is what ColorOperations reads, so grey50 is not one and transparent is" do
      assert {Palette.type({:manual, ["grey50"]}), Palette.type({:manual, ["transparent"]})} ===
               {nil, :color}
    end

    # Each refused value is built as the test runs: a literal the guard refuses fails the type
    # checker.
    test "a value that is no palette is refused" do
      named = Map.new([{"a", "#FF0000"}])
      fill = Enum.at([:hollow], 0)
      brewer = {:brewer, %{palette: Enum.at(["set1"], 0), direction: 1}}

      assert_raise FunctionClauseError, fn -> Palette.type({:manual, named}) end
      assert_raise FunctionClauseError, fn -> Palette.nlevels({:manual, named}) end
      assert_raise FunctionClauseError, fn -> Palette.type({:shape, fill}) end
      assert_raise FunctionClauseError, fn -> Palette.nlevels({:shape, fill}) end
      assert_raise FunctionClauseError, fn -> Palette.nlevels(brewer) end
    end
  end

  # Golden: scales 1.4.0's `scales:::get_palette()` in R 4.6.1: `"SET1"`, `"Magma"`, `"GREY"`,
  # `"Hue"`, `"blues"`, `"ylorrd"` and `"brbg"` give the palettes below, `get_palette("rdbu")` has
  # 11 levels, and `"gray"` fails ("Unknown palette: gray"); R also knows `"Okabe-Ito"`, one of
  # grDevices' palettes, left out.
  describe "named/1" do
    test "scales' own names give R's palettes with R's defaults, in any case" do
      assert Enum.map(~w(SET1 Magma GREY Hue blues ylorrd brbg), &Palette.named/1) === [
               {:brewer, %{palette: "Set1", direction: 1}},
               {:viridis, %{option: :magma, begin: 0.0, end: 1.0, direction: 1, alpha: 1.0}},
               {:gray, {0.2, 0.8}},
               {:hue, %{hue: {15.0, 375.0}, chroma: 100.0, luminance: 65.0, direction: 1}},
               {:brewer, %{palette: "Blues", direction: 1}},
               {:brewer, %{palette: "YlOrRd", direction: 1}},
               {:brewer, %{palette: "BrBG", direction: 1}}
             ]
    end

    test "the names are scales' 45, each brewer palette and viridis option its own, in any case" do
      brewer_names = Enum.flat_map([:seq, :div, :qual], &Palette.brewer_palettes/1)
      options = ColorOperations.viridis_options()

      names =
        brewer_names
        |> Enum.concat(Enum.map(options, &Atom.to_string/1))
        |> Enum.concat(["grey", "hue"])

      named =
        Enum.map(names, fn name ->
          name
          |> String.upcase()
          |> Palette.named()
        end)

      brewer = Enum.map(brewer_names, fn name -> {:brewer, %{palette: name, direction: 1}} end)

      viridis =
        Enum.map(options, fn option ->
          {:viridis, %{option: option, begin: 0.0, end: 1.0, direction: 1, alpha: 1.0}}
        end)

      assert {length(names), Enum.take(named, length(brewer) + length(viridis))} ===
               {45, Enum.concat(brewer, viridis)}
    end

    test "a name scales does not know raises, naming it and those it knows" do
      for name <- ["gray", "Okabe-Ito", " set1", ""] do
        error = assert_raise ArgumentError, fn -> Palette.named(name) end

        assert error.message =~ "palette #{inspect(name)};"
        assert error.message =~ ~s("Blues", "BuGn")
        assert error.message =~ ~s("Set3", "magma")
        assert error.message =~ ~s("turbo", "grey", "hue")
      end
    end

    # The name is built as the test runs: a literal the guard refuses fails the type checker.
    test "a name that is not a string is refused" do
      name = Enum.at([:set1], 0)

      assert_raise FunctionClauseError, fn -> Palette.named(name) end
    end
  end

  # Golden: scales 1.4.0's `as_continuous_pal()` in R 4.6.1, each palette's colours through
  # farver 2.1.2 and its numbers through `approxfun()`: a discrete colour palette's `nlevels`
  # colours as a gradient, so hue at 1 is its 255th hue, `#F97571`, not its first; numbers joined
  # by straight lines, `NA` outside 0 to 1; one number fails ("need at least two non-NA values to
  # interpolate"), and shapes, line types and other strings fail ("Don't know how to convert a
  # discrete ... palette to a continuous palette.").
  describe "continuous/2 of a discrete palette" do
    test "a colour palette is a gradient through its nlevels colours" do
      hue = {:hue, %{hue: {15.0, 375.0}, chroma: 100.0, luminance: 65.0, direction: 1}}
      reversed_hue = {:hue, %{hue: {15.0, 375.0}, chroma: 100.0, luminance: 65.0, direction: -1}}
      magma = {:viridis, %{option: :magma, begin: 0.2, end: 1.0, direction: -1, alpha: 1.0}}

      assert {Palette.continuous(hue, [0, 0.1, 0.25, 0.5, 0.77, 1, nil]),
              Palette.continuous(reversed_hue, [0, 0.3, 1]),
              Palette.continuous({:gray, {0.2, 0.8}}, [0, 0.3, 0.5, 1]),
              Palette.continuous(magma, [0, 0.3, 1])} ===
               {["#F8766D", "#D88F00", "#7DAE00", "#00BFC3", "#D476FE", "#F97571", nil],
                ["#F97571", "#9190FF", "#F8766D"], ["#333333", "#7C7C7C", "#989898", "#CCCCCC"],
                ["#FCFDBF", "#FC8C63", "#3B0F70"]}
    end

    test "a brewer palette is a gradient through its largest set, in its direction" do
      assert {brewer_ramp("Set1", 1, [0, 0.3, 0.5, 1]), brewer_ramp("Blues", -1, [0, 0.3, 1]),
              brewer_ramp("Paired", 1, [0, 0.3, 1])} ===
               {["#E41A1C", "#7B8D72", "#FF7F00", "#999999"], ["#08306B", "#307EBC", "#F7FBFF"],
                ["#A6CEE3", "#80A34F", "#B15928"]}
    end

    test "a manual palette's colours, written any way they are read, are a gradient" do
      assert {Palette.continuous({:manual, ["red", "#0000ff", "#00FF00"]}, [
                0,
                0.25,
                0.5,
                0.6,
                1,
                nil
              ]), Palette.continuous({:manual, ["red"]}, [0, 0.5])} ===
               {["#FF0000", "#CA0088", "#0000FF", "#644FDC", "#00FF00", nil],
                ["#FF0000", "#FF0000"]}
    end

    test "a manual palette's numbers are joined by straight lines, nil outside them" do
      assert Palette.continuous({:manual, [1, 5, 9]}, [0, 0.25, 0.5, 0.9, 1, nil, -0.1, 1.1]) ===
               [1, 3.0, 5, 8.1999999999999993, 9, nil, nil, nil]
    end

    # Each refused palette is built as the test runs: a literal the guard refuses fails the type
    # checker.
    test "shapes, line types, other values, one number and no colours are refused" do
      refused =
        Enum.concat([
          [{:shape, :solid}, :linetype],
          Enum.map([["a", "b"], [:circle_small], [4], []], fn values -> {:manual, values} end)
        ])

      for palette <- refused do
        assert_raise FunctionClauseError, fn -> Palette.continuous(palette, [0.5]) end
      end
    end
  end

  # Golden: scales 1.4.0's `as_discrete_pal()` in R 4.6.1: `pal_rescale(c(1, 6))` for 4 levels and
  # 1, `pal_rescale()` for 7, `pal_area()` for 3, the gradient for 7 and none; R hands
  # `pal_identity()` and `abs_area(6)` back as they are, so for 3 levels they give 3 and
  # 10.392304845413264.
  describe "discrete/2 of a continuous palette" do
    test "the palette is handed the levels' places, spaced evenly from 0 to 1" do
      assert {Palette.discrete({:rescale, {1, 6}}, 4), Palette.discrete({:rescale, {1, 6}}, 1),
              Palette.discrete({:rescale, {0.1, 1.0}}, 7), Palette.discrete({:area, {1, 6}}, 3)} ===
               {[1.0, 2.6666666666666665, 4.333333333333333, 6.0], [1.0],
                [
                  0.10000000000000001,
                  0.25,
                  0.40000000000000002,
                  0.55000000000000004,
                  0.69999999999999996,
                  0.84999999999999998,
                  1.0
                ], [1.0, 4.5355339059327378, 6.0]}
    end

    test "a gradient's colours are sampled, and no levels give none" do
      gradient = {:gradient, ["#132B43", "#56B1F7"]}

      assert {Palette.discrete(gradient, 7), Palette.discrete(gradient, 0)} ===
               {["#132B43", "#1D3F5E", "#28547A", "#336A98", "#3E81B7", "#4A99D6", "#56B1F7"], []}
    end

    test "the identity and an absolute area, which R gives no type, are refused" do
      for palette <- [:identity, {:abs_area, 6.0}] do
        assert_raise FunctionClauseError, fn -> Palette.discrete(palette, 3) end
      end
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

  # `count` colours of R's `pal_brewer(palette = name, direction = direction)`.
  defp brewer(name, count, direction \\ 1),
    do: Palette.discrete({:brewer, %{palette: name, direction: direction}}, count)

  # The colours at `places` of R's `as_continuous_pal(pal_brewer(palette = name, direction =
  # direction))`.
  defp brewer_ramp(name, direction, places),
    do: Palette.continuous({:brewer, %{palette: name, direction: direction}}, places)
end
