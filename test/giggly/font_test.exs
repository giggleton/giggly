defmodule Giggly.FontTest do
  use ExUnit.Case, async: true

  alias Giggly.Font

  describe "width/4 from the table" do
    test "a string's width is its characters' advances summed, scaled to the size" do
      assert Font.width("10.0", 8.8, "", :plain) === 17.128320000000002
    end

    test "a character the font lacks takes vdiffr's width for a missing glyph" do
      assert Font.width("中", 12, "", :plain) === 9.0
    end
  end

  describe "ascent/3 from the table" do
    test "a line's height above its baseline is the ascent of M, scaled to the size" do
      assert Font.ascent(8.8, "", :plain) === 6.05616
    end
  end

  describe "descent/3 from the table" do
    test "the room below a baseline is the deepest descent among gjpqyQ, scaled to the size" do
      assert Font.descent(8.8, "", :plain) === 1.8268800000000003
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
      assert Font.width("AV", 12, "Lato", :plain) === 15.609375
    end

    test "the size is truncated to 1/64 point, as svglite hands it to FreeType" do
      # 13.2 and 7.04 points are 844.8 and 450.56 sixty-fourths; rounded, they measure 17.15625
      # and 16.375.
      assert {Font.width("AV", 13.2, "Lato", :plain), Font.width("1971", 7.04, "Lato", :plain)} ===
               {17.125, 16.3125}
    end

    test "a size under 1/64 point is measured as 1 point, as svglite's FreeType takes it" do
      assert {Font.width("AV", 0, "Lato", :plain), Font.ascent(0.01, "Lato", :plain)} ===
               {1.296875, 0.72}
    end

    test "a character the font lacks takes the width of the font's glyph for one" do
      assert Font.width("A中V", 12, "Lato", :plain) === 22.625
    end

    test "a line's height is the top of M's box, rounded up to a pixel at 10,000 dots per inch" do
      # At 12 points the top is 1194.2 pixels, and at 13.2 points, truncated to 13.1875, 1312.3.
      assert {Font.ascent(12, "Lato", :plain), Font.ascent(13.2, "Lato", :plain)} ===
               {8.604, 9.4536}
    end

    test "the room below a baseline is the lowest of gjpqyQ's boxes, rounded down to a pixel" do
      # At 12 points the lowest bottom is -304.2 pixels.
      assert Font.descent(12, "Lato", :plain) === 2.196
    end

    test "each face is measured from the font registered for it" do
      # Not its ascent: Bold's M tops out at exactly 1205 pixels at 12 points, which svglite's
      # FreeType, sizing the font its own way, makes 1206 (8.6832), the pixel the module allows.
      assert {Font.width("AV", 12, "Lato", :bold), Font.descent(12, "Lato", :bold)} ===
               {15.96875, 2.1672}
    end

    test "a face no font is registered for is measured from the table, never another face" do
      assert {Font.width("AV", 12, "Lato", :italic), Font.ascent(12, "Lato", :italic),
              Font.descent(12, "Lato", :italic)} ===
               {Font.width("AV", 12, "", :plain), Font.ascent(12, "", :plain),
                Font.descent(12, "", :plain)}
    end

    test "a family no font is registered under is measured from the table" do
      assert Font.width("AV", 12, "Lobster", :plain) === Font.width("AV", 12, "", :plain)
    end
  end

  describe "a project without Pica" do
    @describetag :without_pica

    test "every family is measured from the table" do
      assert {Font.width("AV", 12, "Lato", :plain), Font.ascent(12, "Lato", :plain),
              Font.descent(12, "Lato", :plain)} ===
               {Font.width("AV", 12, "", :plain), Font.ascent(12, "", :plain),
                Font.descent(12, "", :plain)}
    end
  end
end
