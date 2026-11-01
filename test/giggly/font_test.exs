defmodule Giggly.FontTest do
  use ExUnit.Case, async: true

  alias Giggly.Font

  describe "width/5 from the table" do
    test "a string's width is its characters' advances summed, scaled to the size" do
      assert Font.width("10.0", 8.8, "", :plain, false) === 17.128320000000002
    end

    test "a character the font lacks takes vdiffr's width for a missing glyph" do
      assert Font.width("中", 12, "", :plain, false) === 9.0
    end
  end

  describe "ascent/4 from the table" do
    test "a line's height above its baseline is the ascent of M, scaled to the size" do
      assert Font.ascent(8.8, "", :plain, false) === 6.05616
    end
  end

  describe "descent/4 from the table" do
    test "the room below a baseline is the deepest descent among gjpqyQ, scaled to the size" do
      assert Font.descent(8.8, "", :plain, false) === 1.8268800000000003
    end
  end

  # Golden: vdiffr 1.0.9's `glyph_dims.h`, the rows priv/fonts/liberation_sans.txt and
  # priv/fonts/symbola.txt copy: "g" reaches 6.4440 above its baseline and 2.4912 below, "j"
  # 8.6976 and 2.4912, "x" 6.3432 and none, codepoint 1 8.2584 and none, at 12 points.
  describe "box/5 from the table" do
    test "a string reaches as high and as deep as its highest and deepest characters" do
      assert {Font.box("gjx", 12, "", :plain, false), Font.box("gjx", 6, "", :plain, false)} ===
               {{8.6976, 2.4912}, {4.3488, 1.2456}}
    end

    test "a character the font lacks takes vdiffr's metrics for a missing glyph" do
      assert Font.box("中", 12, "", :plain, false) === {8.2584, 0.0}
    end

    test "a box reaches no lower than its baseline nor below none, as plotmath's starts from none" do
      # Symbola's minus sits 3.168 points above its baseline at 12 points.
      assert {Font.box("−", 12, "", :symbol, false), Font.box("", 12, "", :plain, false)} ===
               {{3.6504, 0.0}, {0.0, 0.0}}
    end
  end

  # Golden: vdiffr 1.0.9's Symbola table, which it measures R's symbol font with: "−" 9.3240 wide,
  # "+" 7.0776 high and 0.2592 deep, "M" 7.8696 high, at 12 points, where Liberation Sans's "−" is
  # 7.0128 wide.
  describe "the symbol face from the table" do
    test "is measured from Symbola's metrics, whatever the family" do
      assert {Font.width("−", 12, "", :symbol, false), Font.width("−", 12, "", :plain, false),
              Font.box("+", 12, "Lobster", :symbol, false), Font.ascent(12, "", :symbol, false)} ===
               {9.324, 7.0128, {7.0776, 0.2592}, 7.8696}
    end
  end

  # Golden: svglite 2.2.2's measurements of the files test/test_helper.exs registers under "Lato",
  # Lato 2.015 Regular and Bold, given to it as `user_fonts` (R 4.6.1, systemfonts 1.3.2,
  # textshaping 1.0.5): `stringWidth()`, and `grobHeight()` of "M" and `grobDescent()` of
  # "gjpqyQ", in big points, from a viewport at each size, as the probe in Pica's plan, Appendix
  # C, measures them. They move with how a registered font is measured, or with the font files.
  describe "a family registered with Pica" do
    @describetag :pica

    test "a string's width is its glyphs' advances once shaped, kerning applied" do
      # Lato's "A" and "V" advance 8.125 points each at 12, and kern 0.640625 closer.
      assert Font.width("AV", 12, "Lato", :plain, false) === 15.609375
    end

    test "the size is truncated to 1/64 point, as svglite hands it to FreeType" do
      # 13.2 and 7.04 points are 844.8 and 450.56 sixty-fourths; rounded, they measure 17.15625
      # and 16.375.
      assert {Font.width("AV", 13.2, "Lato", :plain, false),
              Font.width("1971", 7.04, "Lato", :plain, false)} ===
               {17.125, 16.3125}
    end

    test "a size under 1/64 point is measured as 1 point, as svglite's FreeType takes it" do
      assert {Font.width("AV", 0, "Lato", :plain, false),
              Font.ascent(0.01, "Lato", :plain, false)} ===
               {1.296875, 0.72}
    end

    test "a character the font lacks takes the width of the font's glyph for one" do
      assert Font.width("A中V", 12, "Lato", :plain, false) === 22.625
    end

    test "a line's height is the top of M's box, rounded up to a pixel at 10,000 dots per inch" do
      # At 12 points the top is 1194.2 pixels, and at 13.2 points, truncated to 13.1875, 1312.3.
      assert {Font.ascent(12, "Lato", :plain, false), Font.ascent(13.2, "Lato", :plain, false)} ===
               {8.604, 9.4536}
    end

    test "the room below a baseline is the lowest of gjpqyQ's boxes, rounded down to a pixel" do
      # At 12 points the lowest bottom is -304.2 pixels.
      assert Font.descent(12, "Lato", :plain, false) === 2.196
    end

    test "each face is measured from the font registered for it" do
      # Not its ascent: Bold's M tops out at exactly 1205 pixels at 12 points, which svglite's
      # FreeType, sizing the font its own way, makes 1206 (8.6832), the pixel the module allows.
      assert {Font.width("AV", 12, "Lato", :bold, false), Font.descent(12, "Lato", :bold, false)} ===
               {15.96875, 2.1672}
    end

    test "a face no font is registered for is measured from the table, never another face" do
      assert {Font.width("AV", 12, "Lato", :italic, false),
              Font.ascent(12, "Lato", :italic, false), Font.descent(12, "Lato", :italic, false)} ===
               {Font.width("AV", 12, "", :plain, false), Font.ascent(12, "", :plain, false),
                Font.descent(12, "", :plain, false)}
    end

    test "a family no font is registered under is measured from the table" do
      assert Font.width("AV", 12, "Lobster", :plain, false) ===
               Font.width("AV", 12, "", :plain, false)
    end

    # Golden: svglite's `grobAscent()` and `grobDescent()` of a plotmath string, `textGrob(
    # expression("10"))` in the family at each size, in big points; at 12 points "gjx" and at 13.2
    # "10" reach a pixel higher there, as svglite's FreeType sizes the font.
    test "a string's box is its glyphs' boxes, each rounded outward to a pixel" do
      assert {Font.box("10", 12, "Lato", :plain, false),
              Font.box("gjx", 13.2, "Lato", :plain, false),
              Font.box(" ", 12, "Lato", :plain, false)} ===
               {{8.6976, 0.0936}, {9.6264, 2.412}, {0.0, 0.0}}
    end

    test "the symbol face is measured from the table where no font is registered as symbol" do
      assert Font.width("−", 12, "Lato", :symbol, false) ===
               Font.width("−", 12, "", :symbol, false)
    end

    # The tests below read the glyphs a font gives, which the build without Pica, where
    # `Font.glyphs/5` gives none, would type as code that can never run, so they are compiled
    # only where Pica is.
    if Code.ensure_loaded?(Pica) do
      test "a label's glyphs are placed as shaped, so they end at its measured width" do
        # Lato has 2000 units to the em (its `head` table, as fontTools 4.67.0 reads it), so at 12
        # points a unit is 0.006 points. "A" advances 8.125 points less the kerning, 0.640625,
        # which places "V", and "V"'s own 8.125 ends the label.
        %Giggly.Scene.Glyphs{scale: scale, runs: [[{_a, a_along, a_up}, {_v, v_along, v_up}]]} =
          Font.glyphs(["AV"], 12, "Lato", :plain, false)

        assert {scale, a_along, a_up, v_along + 8.125, v_up} ===
                 {0.006, 0.0, 0.0, Font.width("AV", 12, "Lato", :plain, false), 0.0}
      end

      # Golden: hb-shape 10.2.0's shaping of "שָׁלוֹם" in Lato at 1/64 point (Pica's
      # test/fixtures/shaping.exs), which Lato draws as its box for a missing character, its
      # vowel points placed by HarfBuzz's fallback: advances of 408, 0, 408, 408, 0, 0 and 408,
      # and offsets of (-17, 598) on the second glyph, (-1, -598) on the fifth and (16, 598) on the
      # sixth, in 1/64 point. It moves with how a glyph is placed from its advance and offset.
      test "a glyph is drawn its offset from the pen, which only its advance moves on" do
        %Giggly.Scene.Glyphs{runs: [run]} = Font.glyphs(["שָׁלוֹם"], 12, "Lato", :plain, false)

        assert Enum.map(run, fn {_outline, along, up} -> {along * 64, up * 64} end) === [
                 {0.0, 0.0},
                 {408.0 - 17, 598.0},
                 {408.0, 0.0},
                 {816.0, 0.0},
                 {1224.0 - 1, -598.0},
                 {1224.0 + 16, 598.0},
                 {1224.0, 0.0}
               ]
      end

      test "each glyph's outline is the font's own, and a glyph that draws nothing is left out" do
        {:ok, font} = Pica.lookup("Lato", installed: false)
        %Giggly.Scene.Glyphs{runs: [run]} = Font.glyphs(["A V"], 12, "Lato", :plain, false)

        assert Enum.map(run, fn {outline, _along, _up} -> outline end) ===
                 Pica.glyph_outlines(font, Pica.glyph_ids(font, "AV"))
      end

      test "glyphs are drawn at the size truncated to 1/64 point, as their label is measured" do
        # 13.2 points is 844.8 sixty-fourths, truncated to 844, 13.1875 points; rounded, 845.
        assert Font.glyphs(["AV"], 13.2, "Lato", :plain, false) ===
                 Font.glyphs(["AV"], 13.1875, "Lato", :plain, false)
      end

      test "each label has its own run, in order, and an empty label an empty one" do
        %Giggly.Scene.Glyphs{runs: runs} = Font.glyphs(["AV", "", "A"], 12, "Lato", :plain, false)
        assert Enum.map(runs, fn run -> length(run) end) === [2, 0, 1]
      end
    end

    test "a face or a family no font is registered for has no glyphs, as it is measured" do
      assert {Font.glyphs(["AV"], 12, "Lato", :italic, false),
              Font.glyphs(["AV"], 12, "Lobster", :plain, false)} ===
               {:none, :none}
    end
  end

  describe "glyphs/5 from the table" do
    test "a text measured from the table has no glyphs" do
      assert Font.glyphs(["AV"], 12, "", :plain, false) === :none
    end
  end

  describe "a project without Pica" do
    @describetag :without_pica

    test "every family is measured from the table" do
      assert {Font.width("AV", 12, "Lato", :plain, false), Font.ascent(12, "Lato", :plain, false),
              Font.descent(12, "Lato", :plain, false)} ===
               {Font.width("AV", 12, "", :plain, false), Font.ascent(12, "", :plain, false),
                Font.descent(12, "", :plain, false)}
    end

    test "no family has glyphs" do
      assert Font.glyphs(["AV"], 12, "Lato", :plain, false) === :none
    end
  end
end
