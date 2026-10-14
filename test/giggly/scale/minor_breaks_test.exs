defmodule Giggly.Scale.MinorBreaksTest do
  use ExUnit.Case, async: true

  alias Giggly.Scale.MinorBreaks

  describe "regular/2" do
    test "a step is added below the first break when the extent reaches below it" do
      assert MinorBreaks.regular([0.0, 5.0, 10.0], {-1.0, 10.0}) ===
               [-5.0, -2.5, 0.0, 2.5, 5.0, 7.5, 10.0]
    end

    test "a step is added above the last break when the extent reaches above it" do
      assert MinorBreaks.regular([0.0, 5.0, 10.0], {0.0, 11.0}) ===
               [0.0, 2.5, 5.0, 7.5, 10.0, 12.5, 15.0]
    end

    test "a gap's middle is its start plus half its width, as R's seq() finds it" do
      # 0.4, not the two ends' mean, which differs in the last bit here.
      assert MinorBreaks.regular([0.1, 0.7, 1.3], {0.1, 1.3}) === [0.1, 0.4, 0.7, 1.0, 1.3]
    end

    test "fewer than two breaks have no gap between them, and so no minor breaks" do
      assert MinorBreaks.regular([3.0], {2.0, 4.0}) === []
    end
  end
end
