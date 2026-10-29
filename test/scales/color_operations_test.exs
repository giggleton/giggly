defmodule Scales.ColorOperationsTest do
  use ExUnit.Case, async: true

  doctest Scales.ColorOperations

  alias Scales.ColorOperations

  # Golden: CSS Color Module Level 4's table of named colours and its four hex forms, never Giggly's
  # or the library's: `steelblue` is #4682B4, CSS's `gray` #808080 and `green` #008000 where R's are
  # #BEBEBE and #00FF00; but `transparent` is R's, white with no alpha, where CSS's is black. It
  # moves only with what `parse/1` takes, never with the library's table, which may hold more than
  # CSS's.
  describe "parse/1" do
    test "a CSS colour name is its hex, in any case, as CSS matches a keyword" do
      assert ColorOperations.parse("steelblue") === {:ok, "#4682B4"}
      assert ColorOperations.parse("SteelBlue") === {:ok, "#4682B4"}
      assert ColorOperations.parse("rebeccapurple") === {:ok, "#663399"}
    end

    test "a name R and CSS give different colours is CSS's" do
      assert ColorOperations.parse("gray") === {:ok, "#808080"}
      assert ColorOperations.parse("grey") === {:ok, "#808080"}
      assert ColorOperations.parse("green") === {:ok, "#008000"}
      assert ColorOperations.parse("purple") === {:ok, "#800080"}
    end

    test "each of CSS's hex forms is spelled in uppercase, six digits and an alpha only if not FF" do
      assert ColorOperations.parse("#f00") === {:ok, "#FF0000"}
      assert ColorOperations.parse("#F008") === {:ok, "#FF000088"}
      assert ColorOperations.parse("#4682b4") === {:ok, "#4682B4"}
      assert ColorOperations.parse("#ff000080") === {:ok, "#FF000080"}
      assert ColorOperations.parse("#FF0000FF") === {:ok, "#FF0000"}
      assert ColorOperations.parse("#ABCDEF00") === {:ok, "#ABCDEF00"}
    end

    test "transparent is R's, white with no alpha, in any case" do
      assert ColorOperations.parse("transparent") === {:ok, "#FFFFFF00"}
      assert ColorOperations.parse("Transparent") === {:ok, "#FFFFFF00"}
    end

    test ":none, R's NA, is kept as none" do
      assert ColorOperations.parse(:none) === {:ok, :none}
    end

    test "a name CSS does not define is refused: R's own, and the library's chroma-key colours" do
      for name <- ["grey50", "gray90", "steelblue4", "chromagreen", "chromablue", "notacolour"] do
        assert ColorOperations.parse(name) === :error
      end
    end

    test "what CSS writes otherwise, or does not write at all, is refused" do
      for written <- [
            "light blue",
            "light-blue",
            "light_blue",
            "ff0000",
            "#ff",
            "#12345",
            "#ff00000",
            "#gg0000",
            "#+f+f+f",
            "rgb(255 0 0)",
            "",
            3,
            :red,
            nil
          ] do
        assert ColorOperations.parse(written) === :error
      end
    end
  end

  # Golden: farver 2.1.2's `encode_colour(cbind(h, c, l), from = "hcl")` in R 4.6.1, as scales
  # 1.4.0's `pal_hue()` calls it; the same composition matched all 50,400 colours of a grid of hues
  # every quarter degree, chromas from 0 to 150 and luminances from 0 to 100. It moves only with
  # farver's constants or the library's conversions.
  describe "from_hcl/3" do
    test "a hue, chroma and luminance is the colour farver encodes, as pal_hue() gives it" do
      assert ColorOperations.from_hcl(15, 100, 65) === "#F8766D"
      assert ColorOperations.from_hcl(300.0, 50, 80) === "#E9B5F4"
      assert ColorOperations.from_hcl(250, 30, 20) === "#103155"
    end

    test "a channel outside sRGB is clamped to a byte, as farver clamps it" do
      assert ColorOperations.from_hcl(135, 150, 65) === "#00C300"
      assert ColorOperations.from_hcl(200.25, 150, 20) === "#006B80"
    end

    # Red is 9, on sRGB's straight segment near black, and blue below 0, clamped.
    test "a dark channel is companded on sRGB's straight segment" do
      assert ColorOperations.from_hcl(125, 30, 20) === "#093900"
    end

    test "luminance 0 is black and luminance 100 without chroma is white" do
      assert ColorOperations.from_hcl(0, 0, 0) === "#000000"
      assert ColorOperations.from_hcl(0, 0, 100) === "#FFFFFF"
    end

    # A hue past 360 is capped, not turned round: 400 is 360's colour, not 40's, and -40 is 0's,
    # not 320's.
    test "each is taken into farver's bounds first, a hue and a luminance at the nearer end" do
      assert Enum.map([400, 360, -40, 0], fn hue -> ColorOperations.from_hcl(hue, 100, 65) end) ===
               ["#FF6C91", "#FF6C91", "#FF6C91", "#FF6C91"]

      assert {ColorOperations.from_hcl(15, -40, 65), ColorOperations.from_hcl(15, 100, 120),
              ColorOperations.from_hcl(15, 100, -5)} === {"#9E9E9E", "#FFD9D0", "#000000"}
    end
  end

  # Golden: farver 2.1.2's `decode_colour(to = "lab")` in R 4.6.1, printed to 17 digits, and the
  # colours it encodes back; the composition matched every one of 5,001 samples of ggplot2's
  # default gradient. It moves only with farver's constants or the library's conversions.
  describe "to_lab/1, from_lab/2 and opacity/1" do
    test "a colour's L*a*b* is farver's" do
      {lightness, a, b} = ColorOperations.to_lab("#132B43")
      assert_in_delta lightness, 16.850779893314083, 1.0e-12
      assert_in_delta a, -0.2951089752190883, 1.0e-12
      assert_in_delta b, -17.888407877147195, 1.0e-12

      {lightness, a, b} = ColorOperations.to_lab("#56B1F7")
      assert_in_delta lightness, 69.565125881010957, 1.0e-12
      assert_in_delta a, -5.9043049797686269, 1.0e-12
      assert_in_delta b, -42.778366037596683, 1.0e-12
    end

    test "a colour's L*a*b* encodes back to the colour" do
      for colour <- ["#132B43", "#56B1F7", "#7F7F7F", "#000000", "#FFFFFF"] do
        assert colour
               |> ColorOperations.to_lab()
               |> ColorOperations.from_lab() === colour
      end
    end

    # Golden: farver 2.1.2's `decode_colour(alpha = TRUE, to = "lab")` and `encode_colour(lab,
    # alpha, from = "lab")`, which writes an opaque alpha FF, dropped here.
    test "a colour's alpha is not part of its L*a*b*, and is read apart, its byte over 255" do
      assert ColorOperations.to_lab("#4682B480") === ColorOperations.to_lab("#4682B4")
      assert ColorOperations.opacity("#4682B480") === 128 / 255
      assert ColorOperations.opacity("#FFFFFF00") === 0.0
      assert ColorOperations.opacity("#4682B4") === 1.0
    end

    test "an alpha is appended as farver writes it, rounded half to even, opaque dropped" do
      lab = {52.4664, -4.0763, -32.1991}

      assert Enum.map([0, 0.25, 0.5, 1, 1.5 / 255, 2.5 / 255, 254.5 / 255], fn alpha ->
               ColorOperations.from_lab(lab, alpha)
             end) ===
               [
                 "#4682B400",
                 "#4682B440",
                 "#4682B480",
                 "#4682B4",
                 "#4682B402",
                 "#4682B402",
                 "#4682B4FE"
               ]
    end

    # Each refused value is built as the test runs: a literal the guard refuses fails the type
    # checker.
    test "no colour has no alpha, and an alpha that is not a number is refused" do
      none = Enum.at([:none], 0)

      assert_raise FunctionClauseError, fn -> ColorOperations.opacity(none) end

      assert_raise FunctionClauseError, fn ->
        ColorOperations.from_lab({52.4664, -4.0763, -32.1991}, none)
      end
    end
  end

  # Golden: scales 1.4.0's `col_mix(a, b, amount)` in R 4.6.1, its opaque alpha FF dropped; the
  # same mixing matched every one of 3,012 random pairs and amounts, these ties among them. It moves
  # only with scales' arithmetic or farver's rounding.
  describe "mix/3" do
    test "black ink mixed toward white or clear paper is ggplot2's geoms' default colours" do
      assert Enum.map(
               [{"#FFFFFF", 0.35}, {"#FFFFFF", 0.2}, {"#00000000", 0.35}, {"#00000000", 0.2}],
               fn {paper, amount} -> ColorOperations.mix("#000000", paper, amount) end
             ) === ["#595959", "#333333", "#000000A6", "#000000CC"]
    end

    test "each channel and the alpha is a share of the way between the two, rounded to a byte" do
      assert ColorOperations.mix("#18C665", "#89CD3FE8", 0.048195409588515759) === "#1DC663FE"
      assert ColorOperations.mix("#2E2DE1", "#AE802B27", 0.63301461911760271) === "#7F626E76"
      assert ColorOperations.mix("#FB4AD9E4", "#820C22", 0.019754580687731504) === "#F949D5E5"
    end

    test "a channel or an alpha half way between two bytes rounds to the even one, as farver's" do
      assert Enum.map(
               [
                 {"#000000", "#010101"},
                 {"#000000", "#030303"},
                 {"#7F7F7F", "#808080"},
                 {"#00000000", "#00000005"},
                 {"#000000FE", "#000000FF"}
               ],
               fn {from, to} -> ColorOperations.mix(from, to, 0.5) end
             ) === ["#000000", "#020202", "#808080", "#00000002", "#000000FE"]
    end

    test "no share is the first colour and all of it the second" do
      assert ColorOperations.mix("#123456", "#FEDCBA80", 0) === "#123456"
      assert ColorOperations.mix("#123456", "#FEDCBA80", 1) === "#FEDCBA80"
    end

    test "an amount outside 0 to 1 is refused" do
      assert_raise FunctionClauseError, fn -> ColorOperations.mix("#000000", "#FFFFFF", 1.5) end
      assert_raise FunctionClauseError, fn -> ColorOperations.mix("#000000", "#FFFFFF", -0.1) end
    end
  end

  # Golden for the helpers: scales 1.4.0's `alpha()`, `col2hcl()`, `muted()`, `col_lighter()`,
  # `col_darker()`, `col_saturate()` and `col_shift()` in R 4.6.1, through farver 2.1.2, an opaque
  # alpha's FF dropped. Each matched R on every colour of a grid of 10,336, a cube, the greys and
  # random colours with and without an alpha, and of tens of thousands of random arguments, but
  # where a test below says. They move only with farver's constants and rounding or the library's
  # conversions.
  describe "alpha/2" do
    test "the colour's alpha is set, its own replaced, an opaque one dropped" do
      assert Enum.map(
               [{"#4682B4", 0.5}, {"#4682B480", 0.25}, {"#4682B4", 0}, {"#4682B480", 1}],
               fn
                 {color, alpha} -> ColorOperations.alpha(color, alpha)
               end
             ) === ["#4682B480", "#4682B440", "#4682B400", "#4682B4"]
    end

    test "an alpha half way between two bytes rounds to the even one, as farver's" do
      assert Enum.map([0.5, 1.5, 2.5], fn half -> ColorOperations.alpha("#4682B4", half / 255) end) ===
               ["#4682B400", "#4682B402", "#4682B402"]
    end

    test "an alpha outside 0 to 1 is the nearer end, as farver clamps its byte" do
      assert {ColorOperations.alpha("#4682B4", 1.5), ColorOperations.alpha("#4682B480", -0.5)} ===
               {"#4682B4", "#4682B400"}
    end

    # R writes one colour whose alpha's byte is 1 opaque, `alpha("#4682B4", 1/255)`, since farver
    # checks for opaque after scaling it; `01` is its answer for several colours.
    test "an alpha whose byte is 1 is written, as R writes it for several colours" do
      assert ColorOperations.alpha("#4682B4", 1 / 255) === "#4682B401"
    end

    test "no alpha, R's NA, keeps the colour's own, and no colour stays none" do
      assert {ColorOperations.alpha("#4682B480", nil), ColorOperations.alpha("#4682B4", nil)} ===
               {"#4682B480", "#4682B4"}

      assert {ColorOperations.alpha(:none, 0.5), ColorOperations.alpha(:none, nil)} ===
               {:none, :none}
    end

    # Each refused value is built as the test runs: a literal the guard refuses fails the type
    # checker.
    test "an alpha that is not a number, or a colour not in its one spelling, is refused" do
      [text, name] = Enum.take(["0.5", "red"], 2)

      assert_raise FunctionClauseError, fn -> ColorOperations.alpha("#4682B4", text) end
      assert_raise FunctionClauseError, fn -> ColorOperations.alpha(name, 0.5) end
      assert_raise FunctionClauseError, fn -> ColorOperations.alpha(name, nil) end
      assert_raise FunctionClauseError, fn -> ColorOperations.alpha(:none, text) end
    end
  end

  describe "with_hcl/2 and muted/2" do
    test "each of hue, chroma and luminance given is set, the others the colour's own" do
      assert Enum.map([[hue: 320], [chroma: 20], [luminance: 70]], fn options ->
               ColorOperations.with_hcl("#4682B4", options)
             end) === ["#B162A0", "#6F7F92", "#7CB0E2"]
    end

    test "the colour's own alpha is dropped unless one is given, nil writing none" do
      assert ColorOperations.with_hcl("#4682B480", []) === "#4682B4"
      assert ColorOperations.with_hcl("#4682B480", alpha: nil) === "#4682B4"

      assert ColorOperations.with_hcl("#4682B480",
               hue: 100,
               chroma: 30,
               luminance: 40,
               alpha: 0.5
             ) ===
               "#57633480"

      assert ColorOperations.with_hcl("#4682B4", alpha: 1.5) === "#4682B4"
    end

    test "a hue, chroma or luminance outside farver's bounds is taken as from_hcl/3 takes it" do
      assert Enum.map(
               [
                 [hue: 400],
                 [hue: -40],
                 [hue: 0],
                 [chroma: -30],
                 [luminance: 120],
                 [luminance: -10]
               ],
               fn options -> ColorOperations.with_hcl("#4682B4", options) end
             ) === ["#B76476", "#B76476", "#B76476", "#7D7D7D", "#D4FFFF", "#000000"]
    end

    # farver decodes black's hue as 180 degrees, so a chroma given it is teal; at 0 degrees it is
    # crimson. Its chroma is 0, so a luminance alone gives a grey. White's chroma is a rounding
    # error, its hue 21.8 degrees.
    test "black's hue is 180 degrees and white's farver's rounding error, as farver decodes them" do
      assert ColorOperations.with_hcl("#000000", chroma: 70, luminance: 30) === "#005F4F"
      assert ColorOperations.with_hcl("#000000", hue: 0, chroma: 70, luminance: 30) === "#88193D"
      assert ColorOperations.with_hcl("#000000", luminance: 50) === "#777777"
      assert ColorOperations.muted("#FFFFFF") === "#7F2B00"
      assert ColorOperations.muted("#FFFFFF00") === "#7F2B00"
    end

    test "muted is luminance 30 and chroma 70 by default, the colour's alpha dropped" do
      assert Enum.map(["#4682B4", "#FF0000", "#4682B480"], &ColorOperations.muted/1) ===
               ["#004F91", "#832424", "#004F91"]

      assert ColorOperations.muted("#4682B4", luminance: 60, chroma: 40) === "#7094BA"
    end

    test "no colour stays none" do
      assert {ColorOperations.with_hcl(:none, hue: 10), ColorOperations.muted(:none)} ===
               {:none, :none}
    end

    test "an option that is not a number, or not one of theirs, is refused" do
      assert_raise NimbleOptions.ValidationError, fn ->
        ColorOperations.with_hcl("#4682B4", hue: "10")
      end

      assert_raise NimbleOptions.ValidationError, fn ->
        ColorOperations.with_hcl(:none, alpha: "0.5")
      end

      assert_raise NimbleOptions.ValidationError, fn ->
        ColorOperations.muted("#4682B4", hue: 10)
      end

      assert_raise NimbleOptions.ValidationError, fn ->
        ColorOperations.muted("#4682B4", luminance: :dark)
      end
    end
  end

  describe "lighter/2, darker/2 and saturate/2" do
    test "the lightness or saturation is raised by 10 by default, or by the amount" do
      assert [
               ColorOperations.lighter("#4682B4"),
               ColorOperations.darker("#4682B4"),
               ColorOperations.saturate("#4682B4"),
               ColorOperations.saturate("#4682B4", -10),
               ColorOperations.lighter("#4682B4", -10),
               ColorOperations.darker("#4682B4", -10)
             ] === ["#699BC4", "#38678F", "#3983C1", "#5281A8", "#38678F", "#699BC4"]
    end

    test "a lightness or saturation past 0 or 100 is taken at the nearer end" do
      assert {ColorOperations.lighter("#4682B4", 200), ColorOperations.darker("#4682B4", 200),
              ColorOperations.lighter("#808080", 80), ColorOperations.saturate("#4682B4", 200),
              ColorOperations.saturate("#4682B4", -200)} ===
               {"#FFFFFF", "#000000", "#FFFFFF", "#0088FA", "#7D7D7D"}
    end

    test "the colour's own alpha is kept" do
      assert {ColorOperations.lighter("#4682B480"), ColorOperations.darker("#FFFFFF00"),
              ColorOperations.saturate("#4682B480", -10)} ===
               {"#699BC480", "#E6E6E600", "#5281A880"}
    end

    # A grey's hue and saturation are 0, so saturating it reddens it.
    test "a grey is saturated toward red" do
      assert ColorOperations.saturate("#808080") === "#8D7373"
    end

    # #808080's lightness and 10 are 153.5 bytes, rounded up to the even 154; #7F7F7F's are 152.5,
    # rounded down to 152.
    test "a channel half way between two bytes rounds to the even one, as farver's" do
      assert {ColorOperations.lighter("#808080"), ColorOperations.lighter("#7F7F7F"),
              ColorOperations.lighter("#808080", 0.5)} === {"#9A9A9A", "#989898", "#818181"}
    end

    # Departure: R gives #332B00. Green is exactly 42.5 bytes, and farver's hue a bit above 50
    # degrees rounds it up; the library's HSL lands on 42, even, as exact arithmetic does.
    test "a channel R's HSL rounds the other way at a tie is the library's" do
      assert ColorOperations.darker("#665500") === "#332A00"
    end

    test "no colour stays none" do
      assert Enum.map(
               [
                 &ColorOperations.lighter/1,
                 &ColorOperations.darker/1,
                 &ColorOperations.saturate/1
               ],
               fn helper -> helper.(:none) end
             ) === [:none, :none, :none]
    end

    # R's `col_lighter(x, NA)` fails in farver. Each refused value is built as the test runs: a
    # literal the guard refuses fails the type checker.
    test "an amount that is not a number, or a colour not in its one spelling, is refused" do
      [missing, name] = Enum.take([nil, "red"], 2)

      for helper <- [
            &ColorOperations.lighter/2,
            &ColorOperations.darker/2,
            &ColorOperations.saturate/2
          ] do
        assert_raise FunctionClauseError, fn -> helper.("#4682B4", missing) end
        assert_raise FunctionClauseError, fn -> helper.(:none, missing) end
        assert_raise FunctionClauseError, fn -> helper.(name, 10) end
      end
    end
  end

  describe "shift/2" do
    test "the hue is turned 10 degrees by default, or by the amount, modulo 360" do
      assert Enum.map([10, 40, 400, -30, -300, 130, 490], fn amount ->
               ColorOperations.shift("#4682B4", amount)
             end) === [
               "#5E7DB7",
               "#906FB6",
               "#906FB6",
               "#008CA2",
               "#A566AC",
               "#B46867",
               "#B46867"
             ]

      assert ColorOperations.shift("#4682B4") === "#5E7DB7"
    end

    # `#4682B401` shifted alone is opaque in R, its answer for several colours `01`.
    test "the colour's own alpha is kept, a byte of 1 among them" do
      assert {ColorOperations.shift("#4682B480"), ColorOperations.shift("#4682B401", 0)} ===
               {"#5E7DB780", "#4682B401"}
    end

    test "black and white have no chroma to turn" do
      assert {ColorOperations.shift("#000000", 90), ColorOperations.shift("#FFFFFF", 0)} ===
               {"#000000", "#FFFFFF"}
    end

    test "no amount, R's NA, gives no colour, and no colour stays none" do
      assert {ColorOperations.shift("#4682B4", nil), ColorOperations.shift(:none),
              ColorOperations.shift(:none, nil)} === {:none, :none, :none}
    end

    # Each refused value is built as the test runs: a literal the guard refuses fails the type
    # checker.
    test "an amount that is not a number, or a colour not in its one spelling, is refused" do
      [text, name] = Enum.take(["10", "red"], 2)

      assert_raise FunctionClauseError, fn -> ColorOperations.shift("#4682B4", text) end
      assert_raise FunctionClauseError, fn -> ColorOperations.shift(:none, text) end
      assert_raise FunctionClauseError, fn -> ColorOperations.shift(name, 10) end
      assert_raise FunctionClauseError, fn -> ColorOperations.shift(name, nil) end
    end
  end

  # Golden: viridisLite 0.4.3's `viridis(n, alpha, begin, end, direction, option)` in R 4.6.1, its
  # opaque alpha FF dropped; the same evaluation matched every colour of 19,794 calls, every
  # palette and count to 256 among them. It moves only with R's splines, which
  # `priv/palettes/viridis_splines.csv` copies, or grDevices' constants.
  describe "viridis/2" do
    test "the palettes are viridisLite's eight, in the order of its options A to H" do
      assert ColorOperations.viridis_options() ===
               [:magma, :inferno, :plasma, :viridis, :cividis, :rocket, :mako, :turbo]
    end

    test "each palette's colours are viridisLite's" do
      expected = [
        magma: ["#000004", "#51127C", "#B63679", "#FB8861", "#FCFDBF"],
        inferno: ["#000004", "#56106E", "#BB3754", "#F98C0A", "#FCFFA4"],
        plasma: ["#0D0887", "#7E03A8", "#CC4678", "#F89441", "#F0F921"],
        viridis: ["#440154", "#3B528B", "#21908C", "#5DC863", "#FDE725"],
        cividis: ["#00204D", "#414D6B", "#7C7B78", "#BCAF6F", "#FFEA46"],
        rocket: ["#03051A", "#611F53", "#CB1B4F", "#F4875E", "#FAEBDD"],
        mako: ["#0B0405", "#3E356B", "#357BA2", "#49C1AD", "#DEF5E5"],
        turbo: ["#30123B", "#28BBEC", "#A2FC3C", "#FB8022", "#7A0403"]
      ]

      for {option, colours} <- expected do
        assert viridis(5, option: option) === colours
      end
    end

    # Unrounded, the middle colour's green would be 0x8D.
    test "a place between knots is the splines' colour, rounded to five decimals as R converts it" do
      assert viridis(3) === ["#440154", "#21908C", "#FDE725"]
    end

    test "begin and end narrow the palette, and a direction of -1 runs it from end to begin" do
      assert viridis(4, begin: 0.25, end: 0.75) ===
               ["#3B528B", "#287C8E", "#20A486", "#5DC863"]

      assert viridis(4, begin: 0.25, end: 0.75, direction: -1) ===
               ["#5DC863", "#20A486", "#287C8E", "#3B528B"]

      assert viridis(4, begin: 0.75, end: 0.25) ===
               ["#5DC863", "#20A486", "#287C8E", "#3B528B"]
    end

    test "one colour is begin's, or end's for a direction of -1, two are both ends, none is none" do
      assert viridis(1, begin: 0.2, end: 0.8) === ["#414487"]
      assert viridis(1, begin: 0.2, end: 0.8, direction: -1) === ["#7AD151"]
      assert viridis(2, option: :turbo) === ["#30123B", "#7A0403"]
      assert viridis(0) === []
    end

    # Evaluated from the second knot back, the place would be #0F0788.
    test "a place before the second knot is the first knot's spline's" do
      assert viridis(1, begin: 0.002, option: :plasma) === ["#0F0787"]
    end

    # Golden: `viridis(1, begin = place, option = "turbo")`, whose blue is exactly 0.982355 and
    # 0.966665 before R rounds it, each tie a byte apart either way, found by a search over the
    # palettes and read back from R with OpenBLAS, whose last bit here agrees with Giggly's.
    test "a channel on a five-decimal tie rounds to the even last decimal, as R's round() does" do
      assert viridis(1, begin: 0.21809360163495614, option: :turbo) === ["#37A7FB"]
      assert viridis(1, begin: 0.22852560046188131, option: :turbo) === ["#32ADF6"]
    end

    # The count is built as the test runs: a literal the guard refuses fails the type checker.
    test "a count below none is refused" do
      count = length([:one]) - 2

      assert_raise FunctionClauseError, fn -> viridis(count) end
    end

    test "an alpha is rgb()'s byte, appended, and dropped when it is opaque" do
      assert viridis(3, alpha: 0.3) === ["#4401544D", "#21908C4D", "#FDE7254D"]
      assert viridis(3, alpha: 0.5) === ["#44015480", "#21908C80", "#FDE72580"]
      assert viridis(3, alpha: 0.0) === ["#44015400", "#21908C00", "#FDE72500"]
      assert viridis(3, alpha: 0.998) === ["#440154FE", "#21908CFE", "#FDE725FE"]
      assert viridis(3, alpha: 0.999) === ["#440154", "#21908C", "#FDE725"]
    end
  end

  # R's defaults, `viridis(n)`, with the options given.
  defp viridis(count, options \\ []) do
    parameters =
      Map.merge(
        %{option: :viridis, begin: 0.0, end: 1.0, direction: 1, alpha: 1.0},
        Map.new(options)
      )

    ColorOperations.viridis(count, parameters)
  end
end
