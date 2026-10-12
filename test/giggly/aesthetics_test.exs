defmodule Giggly.AestheticsTest do
  use ExUnit.Case, async: true

  alias Giggly.Aesthetics

  doctest Giggly.Aesthetics

  describe "canonicalize/1" do
    test "a keyword list keeps its order and values, with only the aliased key rewritten" do
      assert Aesthetics.canonicalize(alpha: 0.4, colour: "red", size: 2) ==
               [alpha: 0.4, color: "red", size: 2]
    end

    test "an aesthetic given under both spellings is refused rather than one value winning" do
      error =
        assert_raise ArgumentError, fn ->
          Aesthetics.canonicalize(%{color: :cyl, colour: :gear})
        end

      assert error.message =~ ":colour"
    end

    test "an aesthetic given twice in a keyword list is refused" do
      assert_raise ArgumentError, fn ->
        Aesthetics.canonicalize(color: "red", alpha: 0.4, color: "blue")
      end
    end
  end
end
