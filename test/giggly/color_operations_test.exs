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
end
