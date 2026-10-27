defmodule Scales.DataRangeTest do
  use ExUnit.Case, async: true

  alias Scales.DataRange

  describe "train_discrete/3" do
    # Golden: R 4.6.1's `levels(factor(c(0, 1e-20)))`, and a `DiscreteRange` trained on that factor
    # (scales 1.4.0), are two levels, `0` and `1e-20`: numbers are matched as floats, so however
    # close two are, they are one level only when equal.
    test "numbers however close are distinct levels unless equal" do
      assert DataRange.train_discrete({[], :none}, [1.0e-20, 0], :none) === {[0, 1.0e-20], false}
    end
  end
end
