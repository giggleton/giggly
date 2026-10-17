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
end
