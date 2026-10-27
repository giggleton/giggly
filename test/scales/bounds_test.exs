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
end
