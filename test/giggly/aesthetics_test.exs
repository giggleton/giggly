defmodule Giggly.AestheticsTest do
  use ExUnit.Case, async: true

  alias Giggly.Aesthetics

  describe "canonical/1" do
    test "an aliased name is rewritten to its canonical spelling" do
      assert Aesthetics.canonical(:colour) == :color
    end

    test "a name with no alias is returned as given" do
      assert Aesthetics.canonical(:fill) == :fill
    end
  end

  describe "canonicalize/1" do
    test "a mapping's aliased keys are rewritten and its values untouched" do
      assert Aesthetics.canonicalize(%{x: :wt, colour: :cyl}) == %{x: :wt, color: :cyl}
    end

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

  describe "family/1" do
    test "an x position beyond :x is in the x family" do
      assert Aesthetics.family(:xend) == :x
    end

    test "a boxplot hinge is in the y family" do
      assert Aesthetics.family(:lower) == :y
    end

    test "a non-position aesthetic is in neither family" do
      assert Aesthetics.family(:color) == :none
    end
  end

  describe "flipped/1" do
    test "each name becomes its counterpart, paired new name first as select/2 takes them" do
      assert Aesthetics.flipped([:y, :xmin, :group]) === [
               {:x, :y},
               {:ymin, :xmin},
               {:group, :group}
             ]
    end
  end

  describe "counterpart/1" do
    test "an x name's partner is its y name" do
      assert Aesthetics.counterpart(:xmin) == :ymin
    end

    test "a y hinge's partner is the irregular x hinge" do
      assert Aesthetics.counterpart(:upper) == :xupper
    end

    test "a non-position name is returned as given" do
      assert Aesthetics.counterpart(:fill) == :fill
    end
  end
end
