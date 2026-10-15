defmodule Giggly.ResolutionTest do
  use ExUnit.Case, async: true

  alias Giggly.Resolution

  # Golden: R 4.6.1's `ggplot2::resolution()` (ggplot2 4.0.3, scales 1.4.0) on the same values,
  # printed to 17 significant digits, each chosen so one rule decides it. It moves only with
  # ggplot2's `resolution()` or R's `zero_range()`.
  describe "of/2" do
    test "the closest pair decides, by its gap as floating point gives it" do
      assert Resolution.of([2.9, 3.1, 4.5], zero: false) === 0.20000000000000018
      assert Resolution.of([2.9, 3.1, 4.5], zero: true) === 0.20000000000000018
    end

    test "counting from zero adds the gap from 0 to the nearest position" do
      assert Resolution.of([0.5, 10.0], zero: true) === 0.5
      assert Resolution.of([0.5, 10.0], zero: false) === 9.5
      assert Resolution.of([-3.0, 0.5, 10.0], zero: true) === 0.5
      assert Resolution.of([0.3, 10.0], zero: true) === 0.29999999999999999
    end

    test "positions that are all integers are 1 apart, as R's integer columns are" do
      assert Resolution.of([4, 6, 8], zero: false) === 1
      assert Resolution.of([4.0, 6.0, 8.0], zero: false) === 2.0
    end

    test "a range zero wide, by R's zero_range(), is 1, one position or many" do
      assert Resolution.of([5.0], zero: true) === 1
      assert Resolution.of([5.0, 5.0], zero: false) === 1
      assert Resolution.of([1.0e10, 1.0e10 + 1.0e-3], zero: false) === 1
    end

    test "gaps within rounding error are left out, and with none left the positions are 1 apart" do
      assert Resolution.of([1.0, 1.0 + 1.0e-9, 3.0], zero: false) === 1.9999999989999999
      assert Resolution.of([0.0, 1.0e-9], zero: false) === 1
    end

    test "a missing position is left out, and with none left the positions are 1 apart" do
      assert Resolution.of([2.0, nil, 4.0], zero: false) === 2.0
      assert Resolution.of([nil, nil], zero: false) === 1
    end
  end
end
