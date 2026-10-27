defmodule Scales.BoundsTest do
  use ExUnit.Case, async: true

  alias Scales.Bounds

  describe "rescale/3" do
    test "a value moves linearly from one range to another, in R's order of operations" do
      rescaled =
        Enum.map([2, 4, 10, 6, 3.3], fn value -> Bounds.rescale(value, {2, 10}, {0, 1}) end)

      assert rescaled === [0.0, 0.25, 1.0, 0.5, 0.16249999999999998]
    end

    test "a range of zero width puts every value at the middle of the other" do
      assert Bounds.rescale(5, {5, 5}, {0, 1}) === 0.5
      assert Bounds.rescale(5, {5, 5}, {0.1, 1.0}) === 0.55
    end
  end

  describe "zero_range?/2" do
    # Golden: R 4.6.1's `scales::zero_range()` (scales 1.4.0) on each pair: ends 1000 machine
    # epsilons apart, relative to the smaller, are not zero wide and 999 are, either sign. Moves
    # only with R's tolerance, `1000 * .Machine$double.eps`.
    test "ends closer than R's tolerance relative to the smaller are zero wide, ends at it are not" do
      assert {Bounds.zero_range?(1.0, 1.000000000000222),
              Bounds.zero_range?(1.0, 1.0000000000002218),
              Bounds.zero_range?(-1.000000000000222, -1.0),
              Bounds.zero_range?(-1.0000000000002218, -1.0)} === {false, true, false, true}
    end
  end
end
