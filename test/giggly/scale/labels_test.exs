defmodule Giggly.Scale.LabelsTest do
  use ExUnit.Case, async: true

  alias Giggly.Scale.Labels

  describe "numbers/1" do
    test "every label gets the decimals the most precise needs, rounding error and -0.0 dropped" do
      assert Labels.numbers([2.5, 2.75, 0.30000000000000004, -0.0]) ==
               ["2.50", "2.75", "0.30", "0.00"]
    end

    test "rounding error in the 16th significant digit, as R's extended breaks carry, is dropped" do
      assert Labels.numbers([
               0.0,
               4.9999999999999996e-6,
               9.999999999999999e-6,
               1.4999999999999999e-5
             ]) ==
               ["0.000000", "0.000005", "0.000010", "0.000015"]
    end

    test "a break that needs all 15 significant digits keeps them" do
      assert Labels.numbers([1_000_000_000_000.0, 1_000_000_000_000.25]) ==
               ["1000000000000.00", "1000000000000.25"]
    end

    test "whole breaks have no decimals and no thousands separators" do
      assert Labels.numbers([0.0, 100_000.0, 200_000.0]) == ["0", "100000", "200000"]
    end

    test "small breaks are written in plain decimals, never scientific notation" do
      assert Labels.numbers([0.0, 0.00005, 0.0001]) == ["0.00000", "0.00005", "0.00010"]
    end

    test "no breaks have no labels" do
      assert Labels.numbers([]) == []
    end
  end

  describe "levels/1" do
    test "a level is written with to_string/1 and a missing one as NA" do
      assert Labels.levels(["manual", :auto, true, nil]) == ["manual", "auto", "true", "NA"]
    end
  end
end
