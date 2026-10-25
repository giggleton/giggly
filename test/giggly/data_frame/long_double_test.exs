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

  # (2^32 + 1)^2 is 2^64 + 2^33 + 1, 65 bits: rounded to 64 the last 1 goes, half a last place
  # below a tie, where 2^-3 times 2^5 needs no rounding at all.
  test "multiply rounds the exact product to 64 bits" do
    wide = 2 ** 32 + 1
    square = LongDouble.multiply({wide, 0}, {wide, 0})
    product = LongDouble.multiply({1, -3}, {-3, 5})

    comparisons = [
      LongDouble.compare(square, {2 ** 64 + 2 ** 33, 0}),
      LongDouble.compare(product, {-12, 0})
    ]

    assert comparisons === [:eq, :eq]
  end
end
