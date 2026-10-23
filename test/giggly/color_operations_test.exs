defmodule Giggly.ColorOperationsTest do
  use ExUnit.Case, async: true

  alias Giggly.ColorOperations

  # Golden: CSS Color Module Level 4's table of named colours and its four hex forms, never Giggly's
  # or the library's: `steelblue` is #4682B4, CSS's `gray` #808080 and `green` #008000 where R's are
  # #BEBEBE and #00FF00, and `transparent` black with no alpha where R's is white. It moves only
  # with what `parse/1` takes, never with the library's table, which may hold more than CSS's.
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

    test "transparent is CSS's, black with no alpha, in any case" do
      assert ColorOperations.parse("transparent") === {:ok, "#00000000"}
      assert ColorOperations.parse("Transparent") === {:ok, "#00000000"}
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
  end

  # Golden: farver 2.1.2's `decode_colour(to = "lab")` in R 4.6.1, printed to 17 digits, and the
  # colours it encodes back; the composition matched every one of 5,001 samples of ggplot2's
  # default gradient. It moves only with farver's constants or the library's conversions.
  describe "to_lab/1 and from_lab/1" do
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
