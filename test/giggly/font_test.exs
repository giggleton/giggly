defmodule Giggly.FontTest do
  use ExUnit.Case, async: true

  alias Giggly.Font

  describe "width/2" do
    test "a string's width is its characters' advances summed, scaled to the size" do
      assert Font.width("10.0", 8.8) === 17.128320000000002
    end

    test "a character the font lacks takes vdiffr's width for a missing glyph" do
      assert Font.width("中", 12) === 9.0
    end
  end

  describe "ascent/1" do
    test "a line's height above its baseline is the ascent of M, scaled to the size" do
      assert Font.ascent(8.8) === 6.05616
    end
  end

  describe "descent/1" do
    test "the room below a baseline is the deepest descent among gjpqyQ, scaled to the size" do
      assert Font.descent(8.8) === 1.8268800000000003
    end
  end
end
