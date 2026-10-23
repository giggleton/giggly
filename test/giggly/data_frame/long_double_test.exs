defmodule Giggly.DataFrame.LongDoubleTest do
  use ExUnit.Case, async: true

  alias Giggly.DataFrame.LongDouble

  # A long double is its mantissa times 2 to its exponent, so {1, 10} is 1024: one above 1023,
  # one below 1025 and equal to {1024, 0}, whichever of the two has the larger exponent.
  test "compare is exact whichever value has the larger exponent" do
    comparisons = [
      LongDouble.compare({1, 10}, {1023, 0}),
      LongDouble.compare({1023, 0}, {1, 10}),
      LongDouble.compare({1, 10}, {1025, 0}),
      LongDouble.compare({1, 10}, {1024, 0})
    ]

    assert comparisons === [:gt, :lt, :lt, :eq]
  end
end
