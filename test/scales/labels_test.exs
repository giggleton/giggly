defmodule Scales.LabelsTest do
  use ExUnit.Case, async: true

  alias Scales.Labels

  doctest Scales.Labels

  # Golden: every expected label below is R's own, from R 4.6.1 with scales 1.4.0 (the image
  # `giggly-r:ggplot2-4.0.3`), each from the call in the comment above it. They move only if
  # scales' formatting does.

  describe "number/2" do
    test "is comma/2 with a space between each three whole digits" do
      # label_number()(c(1234567, 0.5)); trim = FALSE on c(NA, 1, 1000)
      assert Labels.number([1_234_567, 0.5]) == ["1 234 567", "0"]
      assert Labels.number([nil, 1, 1000], trim: false) == [nil, "    1", "1 000"]
    end
  end

  describe "a missing break" do
    test "has no label, and leaves the others' accuracy to them" do
      # label_number()(c(NA_real_)); c(NA_real_, NA_real_); accuracy = 0.01 on c(NA, 2);
      # label_comma()(c(NA, 1234.5, 2000))
      assert Labels.number([nil]) == [nil]
      assert Labels.number([nil, nil]) == [nil, nil]
      assert Labels.number([nil, 2], accuracy: 0.01) == [nil, "2.00"]
      assert Labels.comma([nil, 1234.5, 2000]) == [nil, "1,234", "2,000"]
    end

    test "widens the others' padding to its NA, untrimmed" do
      # label_number(trim = FALSE)(c(1, NA)); c(NA, 1, 10); scale_cut = cut_short_scale() on
      # c(1, 1500, NA)
      assert Labels.number([1, nil], trim: false) == [" 1", nil]
      assert Labels.number([nil, 1, 10], trim: false) == [nil, " 1", "10"]

      assert Labels.number([1, 1500, nil], trim: false, scale_cut: Labels.cut_short_scale()) ==
               [" 1", " 2K", nil]
    end

    test "takes no step under scale_cut:, and no sign" do
      # label_number(scale_cut = cut_short_scale())(c(1500, NA, 2e6)); c(NA, 0, 2500);
      # style_positive = "plus", style_negative = "parens" on c(-1, NA, 1)
      assert Labels.number([1500, nil, 2.0e6], scale_cut: Labels.cut_short_scale()) ==
               ["2K", nil, "2M"]

      assert Labels.number([nil, 0, 2500], scale_cut: Labels.cut_short_scale()) ==
               [nil, "0", "2K"]

      assert Labels.number([-1, nil, 1], style_positive: :plus, style_negative: :parens) ==
               ["(1)", nil, "+1"]
    end

    test "leaves currency's cents to the amounts given" do
      # label_currency()(c(1.5, NA)); c(NA, 2); c(NA_real_); label_percent()(c(NA, 0.5))
      assert Labels.currency([1.5, nil]) == ["$1.50", nil]
      assert Labels.currency([nil, 2]) == [nil, "$2"]
      assert Labels.currency([nil]) == [nil]
      assert Labels.percent([nil, 0.5]) == [nil, "50%"]
    end
  end

  describe "comma/2's default accuracy" do
    test "is a tenth of the power of ten at or below the smallest gap, shared by every label" do
      # label_comma()(c(2, 2.25, 3)); c(10, 12.5)
      assert Labels.comma([2, 2.25, 3]) == ["2.00", "2.25", "3.00"]
      assert Labels.comma([10, 12.5]) == ["10.0", "12.5"]
    end

    test "is that power of ten itself when every break is a multiple of it" do
      # label_comma()(c(0, 0.5, 1)); c(0.1, 0.2, 0.3); c(-0.4, 0.4)
      assert Labels.comma([0, 0.5, 1]) == ["0.0", "0.5", "1.0"]
      assert Labels.comma([0.1, 0.2, 0.3]) == ["0.1", "0.2", "0.3"]
      assert Labels.comma([-0.4, 0.4]) == ["-0.4", "0.4"]
    end

    test "is 1 for one break or breaks closer than rounding error, and never more than 1" do
      # label_comma()(1234.5678); c(3); c(1e-10, 2e-10); c(0, 1e5, 2e5, 3e5); c(-1500.5, 0, 2000)
      assert Labels.comma([1234.5678]) == ["1,235"]
      assert Labels.comma([3]) == ["3"]
      assert Labels.comma([1.0e-10, 2.0e-10]) == ["0", "0"]
      assert Labels.comma([0, 1.0e5, 2.0e5, 3.0e5]) == ["0", "100,000", "200,000", "300,000"]
      assert Labels.comma([-1500.5, 0, 2000]) == ["-1,500", "0", "2,000"]
    end

    test "reads the smallest gap however the breaks come: repeated, unsorted, between any two" do
      # label_comma()(c(0.5, 0.5, 1)); c(1, 0.5); c(0, 1, 1.25)
      assert Labels.comma([0.5, 0.5, 1]) == ["0.5", "0.5", "1.0"]
      assert Labels.comma([1, 0.5]) == ["1.0", "0.5"]
      assert Labels.comma([0, 1, 1.25]) == ["0.00", "1.00", "1.25"]
    end

    test "takes a gap of exactly the rounding error's size as a gap" do
      # label_comma()(c(0, sqrt(.Machine$double.eps))); c(3, 3 + 1e-9), a gap below it, whose
      # accuracy of 1 leaves 3 as it is
      assert Labels.comma([0, :math.sqrt(2.220446049250313e-16)]) ==
               ["0.000000000", "0.000000015"]

      assert Labels.comma([3, 3 + 1.0e-9]) == ["3", "3"]
    end

    test "counts a negative zero and a zero as one break" do
      # label_comma()(c(-0, 0, 1))
      assert Labels.comma([-0.0, 0.0, 1]) == ["0", "0", "1"]
    end
  end

  describe "comma/2's rounding" do
    test "takes a half to the even neighbour" do
      # label_comma(accuracy = 1)(c(0.5, 1.5, 2.5, 12.5, -2.5))
      assert Labels.comma([0.5, 1.5, 2.5, 12.5, -2.5], accuracy: 1) ==
               ["0", "2", "2", "12", "-2"]
    end

    test "rounds to a multiple of the accuracy given, with its decimals, at most twenty" do
      # label_comma(accuracy = 10)(c(1234, 5678)); accuracy = 0.001 on c(1, 2);
      # accuracy = 1e-25 on c(1, 2)
      assert Labels.comma([1234, 5678], accuracy: 10) == ["1,230", "5,680"]
      assert Labels.comma([1, 2], accuracy: 0.001) == ["1.000", "2.000"]

      assert Labels.comma([1, 2], accuracy: 1.0e-25) ==
               ["0.99999999999999988898", "1.99999999999999977796"]
    end

    test "gives every label the decimals any needs at seven significant digits" do
      # label_comma(accuracy = 0.25)(c(0.25, 0.5, 1234567.25)); c(1234567.25, 1234567.5)
      assert Labels.comma([0.25, 0.5, 1_234_567.25], accuracy: 0.25) ==
               ["0.25", "0.50", "1,234,567.25"]

      assert Labels.comma([1_234_567.25, 1_234_567.5], accuracy: 0.25) ==
               ["1,234,567.2", "1,234,567.5"]
    end

    test "counts seven significant digits, no more and no fewer, from the first" do
      # label_comma(accuracy = 0.25)(c(12345.25, 12345.5)), seven digits;
      # c(123456.25, 123456.5), eight; accuracy = 1.25e-6 on c(0.1234575, 0.25), seven below 1
      assert Labels.comma([12_345.25, 12_345.5], accuracy: 0.25) == ["12,345.25", "12,345.50"]
      assert Labels.comma([123_456.25, 123_456.5], accuracy: 0.25) == ["123,456.2", "123,456.5"]

      assert Labels.comma([0.1234575, 0.25], accuracy: 1.25e-6) == ["0.1234575", "0.2500000"]
    end

    test "prints a last digit halfway between two as the even one" do
      # label_comma(accuracy = 0.25)(c(1234567.75, 1234568.25)): 12345677.5 tenths up to
      # 12345678, 12345682.5 down to 12345682
      assert Labels.comma([1_234_567.75, 1_234_568.25], accuracy: 0.25) ==
               ["1,234,567.8", "1,234,568.2"]
    end

    test "leaves no sign on a number that rounds to zero" do
      # label_comma(accuracy = 1)(c(-0.001, 0.001, -1))
      assert Labels.comma([-0.001, 0.001, -1], accuracy: 1) == ["0", "0", "-1"]
    end
  end

  describe "comma/2's marks" do
    test "marks every three whole digits, however many" do
      # label_comma()(c(1e20, 2e20)); c(1000L, 2500L)
      assert Labels.comma([1.0e20, 2.0e20]) ==
               ["100,000,000,000,000,000,000", "200,000,000,000,000,000,000"]

      assert Labels.comma([1000, 2500]) == ["1,000", "2,500"]
      # label_comma()(c(3e15, 1))
      assert Labels.comma([3.0e15, 1]) == ["3,000,000,000,000,000", "1"]
    end

    test "takes the marks given, even a comma as both" do
      # label_comma(big.mark = " ", decimal.mark = ",")(c(1234567.5, 2));
      # big.mark = "" on c(1990, 2000, 2010); decimal.mark = "," on c(1234.5, 1)
      assert Labels.comma([1_234_567.5, 2], big_mark: " ", decimal_mark: ",") ==
               ["1 234 568", "2"]

      assert Labels.comma([1990, 2000, 2010], big_mark: "") == ["1990", "2000", "2010"]
      assert Labels.comma([1234.5, 1], decimal_mark: ",") == ["1,234", "1"]
    end

    test "writes the prefix and suffix around the number, after a negative's sign" do
      # label_comma(prefix = "~", suffix = " t")(c(-1000, 2000));
      # scale = 1e-3, suffix = "k" on c(0, 1500, 3000)
      assert Labels.comma([-1000, 2000], prefix: "~", suffix: " t") == ["-~1,000 t", "~2,000 t"]
      assert Labels.comma([0, 1500, 3000], scale: 1.0e-3, suffix: "k") == ["0.0k", "1.5k", "3.0k"]
    end

    test "marks negatives and positives in the style given" do
      # label_comma(style_negative = "minus")(c(-1, 0, 1));
      # style_negative = "parens", style_positive = "plus"; style_positive = "space", a figure
      # space (U+2007)
      assert Labels.comma([-1, 0, 1], style_negative: :minus) == ["−1", "0", "1"]

      assert Labels.comma([-1, 0, 1], style_negative: :parens, style_positive: :plus) ==
               ["(1)", "0", "+1"]

      assert Labels.comma([-1, 0, 1], style_positive: :space) == ["-1", "0", "\u20071"]
    end

    test "labels no breaks with no labels" do
      # label_comma()(numeric())
      assert Labels.comma([]) == []
    end
  end

  describe "comma/2 untrimmed" do
    test "pads each number to the widest, marks included" do
      # label_comma(trim = FALSE)(c(1, 1000)); big.mark = "" on c(1, 1e6);
      # c(-0.5, 1000.25, 12)
      assert Labels.comma([1, 1000], trim: false) == ["    1", "1,000"]
      assert Labels.comma([1, 1.0e6], trim: false, big_mark: "") == ["      1", "1000000"]
      assert Labels.comma([-0.5, 1000.25, 12], trim: false) == ["    0", "1,000", "   12"]
      # label_comma(trim = FALSE)(c(0, 0.5)): zero shows one whole digit
      assert Labels.comma([0, 0.5], trim: false) == ["0.0", "0.5"]
    end

    test "pads to the width R estimates, a digit wider when rounding carries a number up" do
      # label_comma(trim = FALSE, accuracy = 0.1)(c(99999999.94, 1.5)), with and without
      # big.mark = ""
      assert Labels.comma([99_999_999.94, 1.5], trim: false, accuracy: 0.1) ==
               [" 99,999,999.9", "          1.5"]

      assert Labels.comma([99_999_999.94, 1.5], trim: false, accuracy: 0.1, big_mark: "") ==
               [" 99999999.9", "        1.5"]
    end

    test "pads to the digits printed when rounding to seven digits carries past them" do
      # label_comma(trim = FALSE, accuracy = 1)(c(99999996, 1)), with and without big.mark = "":
      # seven digits round 99999996 to 1e8, but it prints with eight
      assert Labels.comma([99_999_996, 1], trim: false, accuracy: 1) ==
               ["99,999,996", "         1"]

      assert Labels.comma([99_999_996, 1], trim: false, accuracy: 1, big_mark: "") ==
               ["99999996", "       1"]
    end

    test "counts a carry as printing fewer digits only from 1e8 to 1e27, more than half below" do
      # label_comma(trim = FALSE, big.mark = "", accuracy = a)(c(x, 1)) for each row: 999.99996
      # carries to 1000 but prints its three whole digits, so R pads it; 99999999.5 is exactly
      # half below 1e8, and 99999999.25 more than half; past 1e27 R asks no more
      for {breaks, accuracy, expected} <- [
            {[999.99996, 1], 1.0e-5, [" 999.99996", "   1.00000"]},
            {[99_999_999.5, 1], 0.5, [" 99999999.5", "        1.0"]},
            {[99_999_999.25, 1], 0.25, ["99999999.2", "       1.0"]},
            {[9.999_999_6e26, 1], 1,
             ["999999959999999953822810112", "                          1"]},
            {[9.999_999_6e27, 1], 1,
             [" 9999999600000000362861821952", "                            1"]}
          ] do
        assert Labels.comma(breaks, trim: false, big_mark: "", accuracy: accuracy) == expected
      end
    end

    test "counts characters, not bytes, in a wide mark" do
      # label_comma(trim = FALSE, big.mark = "’")(c(1, 1e6));
      # decimal.mark = "::", accuracy = 0.01 on c(1.5, 1000.25)
      assert Labels.comma([1, 1.0e6], trim: false, big_mark: "’") ==
               ["        1", "1’000’000"]

      assert Labels.comma([1.5, 1000.25], trim: false, decimal_mark: "::", accuracy: 0.01) ==
               ["    1::50", "1,000::25"]
    end
  end

  describe "percent/2" do
    test "multiplies by 100, writes a %, and marks thousands with a space" do
      # label_percent()(c(-0.05, 0, 25)); c(0.001, 0.002); scale = 1 on c(10, 20)
      assert Labels.percent([-0.05, 0, 25]) == ["-5%", "0%", "2 500%"]
      assert Labels.percent([0.001, 0.002]) == ["0.1%", "0.2%"]
      assert Labels.percent([10, 20], scale: 1) == ["10%", "20%"]
    end

    test "rounds in R's order of floating-point operations" do
      # label_percent(accuracy = 1)(c(0.145, 0.155, 0.285)): 0.145 / 0.01 is just under 14.5
      assert Labels.percent([0.145, 0.155, 0.285], accuracy: 1) == ["14%", "16%", "28%"]
    end

    test "takes the options comma/2 does" do
      # label_percent(big.mark = ",")(c(0, 12.345));
      # decimal.mark = ",", accuracy = 0.1 on c(0.125, 0.5); trim = FALSE on
      # c(0.001, 0.0125, 0.5) and c(0.05, 0.5, 1); style_negative = "parens" on c(-0.1, 0.1)
      assert Labels.percent([0, 12.345], big_mark: ",") == ["0%", "1,234%"]
      assert Labels.percent([0.125, 0.5], decimal_mark: ",", accuracy: 0.1) == ["12,5%", "50,0%"]
      assert Labels.percent([0.001, 0.0125, 0.5], trim: false) == [" 0.1%", " 1.2%", "50.0%"]
      assert Labels.percent([0.05, 0.5, 1], trim: false) == ["  5%", " 50%", "100%"]
      assert Labels.percent([-0.1, 0.1], style_negative: :parens) == ["(10%)", "10%"]
    end
  end

  describe "currency/2's cents" do
    test "show when some amount is not whole and none is over 100,000" do
      # label_currency()(c(1e5, 1.5)); c(-2e5, 0, 1.5); c(100000.5); scale = 100 on
      # c(0.125, 1)
      assert Labels.currency([1.0e5, 1.5]) == ["$100,000.00", "$1.50"]
      assert Labels.currency([-2.0e5, 0, 1.5]) == ["-$200,000", "$0", "$2"]
      assert Labels.currency([100_000.5]) == ["$100,000"]
      assert Labels.currency([0.125, 1], scale: 100) == ["$12.50", "$100.00"]
      # label_currency(scale = 1000)(c(0.5, 1)): whole once scaled
      assert Labels.currency([0.5, 1], scale: 1000) == ["$500", "$1,000"]
    end

    test "move with largest_with_fractional and give way to accuracy: and scale_cut:" do
      # label_currency(largest_with_fractional = 10)(c(1.5, 20)); accuracy = 1 on
      # c(0.25, 1.75); scale = 1e-6, suffix = "M", accuracy = 0.1 on c(0, 2.5e6, 5e6)
      assert Labels.currency([1.5, 20], largest_with_fractional: 10) == ["$2", "$20"]
      assert Labels.currency([0.25, 1.75], accuracy: 1) == ["$0", "$2"]

      assert Labels.currency([0, 2.5e6, 5.0e6], scale: 1.0e-6, suffix: "M", accuracy: 0.1) ==
               ["$0.0M", "$2.5M", "$5.0M"]

      # label_currency(scale_cut = cut_short_scale())(c(0, 1.5e6, 2e6)): the millions' own
      # accuracy, not whole dollars
      assert Labels.currency([0, 1.5e6, 2.0e6], scale_cut: Labels.cut_short_scale()) ==
               ["$0", "$1.5M", "$2.0M"]
    end
  end

  describe "currency/2's marks" do
    test "mark thousands with a space when both marks would be a comma" do
      # label_currency(decimal.mark = ",")(c(1234.5, 1))
      assert Labels.currency([1234.5, 1], decimal_mark: ",") == ["$1 234,50", "$1,00"]
    end

    test "write a negative's sign outside the prefix, in the style given" do
      # label_currency(prefix = "€")(c(-1, 2.5)); style_negative = "parens" and "minus" on
      # c(-1, 0, 1); trim = FALSE on c(-1.5, 1000)
      assert Labels.currency([-1, 2.5], prefix: "€") == ["-€1.00", "€2.50"]
      assert Labels.currency([-1, 0, 1], style_negative: :parens) == ["($1)", "$0", "$1"]
      assert Labels.currency([-1, 0, 1], style_negative: :minus) == ["−$1", "$0", "$1"]
      assert Labels.currency([-1.5, 1000], trim: false) == ["-$    1.50", "$1,000.00"]
    end

    test "label no amounts with no labels" do
      # label_currency()(numeric())
      assert Labels.currency([]) == []
    end
  end

  describe "scale_cut:" do
    test "writes each label in the largest step it reaches, sharing decimals within a step" do
      # label_comma(scale_cut = cut_short_scale())(c(0, 5e5, 1e6, 1.5e6, 2e6));
      # c(0, 2500, 5000, 7500, 10000); c(999.9, 1000); c(1e15, 2e15)
      assert Labels.comma([0, 5.0e5, 1.0e6, 1.5e6, 2.0e6], scale_cut: Labels.cut_short_scale()) ==
               ["0", "500K", "1.0M", "1.5M", "2.0M"]

      assert Labels.comma([0, 2500, 5000, 7500, 10_000], scale_cut: Labels.cut_short_scale()) ==
               ["0", "2.5K", "5.0K", "7.5K", "10.0K"]

      assert Labels.comma([999.9, 1000], scale_cut: Labels.cut_short_scale()) == ["1,000", "1K"]

      assert Labels.comma([1.0e15, 2.0e15], scale_cut: Labels.cut_short_scale()) ==
               ["1,000T", "2,000T"]
    end

    test "rounds in R's order of floating-point operations, a lone label to a whole number" do
      # label_comma(scale_cut = cut_short_scale())(c(0, 1500, 1e6, 2.5e9)): 1/1e-9 is not
      # exact, so two and a half billion rounds up; c(-1500, 1500); cut_long_scale() on
      # c(5e8, 1.5e12)
      assert Labels.comma([0, 1500, 1.0e6, 2.5e9], scale_cut: Labels.cut_short_scale()) ==
               ["0", "2K", "1M", "3B"]

      assert Labels.comma([-1500, 1500], scale_cut: Labels.cut_short_scale()) == ["-1.5K", "1.5K"]
      assert Labels.comma([5.0e8, 1.5e12], scale_cut: Labels.cut_long_scale()) == ["500M", "2B"]
    end

    test "writes a label in the step below when that is not a power of ten lower" do
      # label_comma(scale_cut = c(" sec" = 0, " min" = 60, " hr" = 3600))(c(30, 90, 5400, 7200));
      # cut_si("g") on c(0.0015, 1.5, 1500)
      steps = [{" sec", 0}, {" min", 60}, {" hr", 3600}]

      assert Labels.comma([30, 90, 5400, 7200], scale_cut: steps) ==
               ["30 sec", "90 sec", "90 min", "2 hr"]

      assert Labels.comma([0.0015, 1.5, 1500], scale_cut: Labels.cut_si("g")) ==
               ["2 mg", "2 g", "2 kg"]
    end

    test "takes steps in any order, and an empty suffix on any step as no step" do
      # label_comma(scale_cut = c(M = 1e6, K = 1e3, 0))(c(500, 1500, 2e6));
      # scale_cut = c(x = 0, 1000) on c(500, 1500), whose 1000 R never finds by its empty name
      steps = [{"M", 1.0e6}, {"K", 1000}, {"", 0}]
      assert Labels.comma([500, 1500, 2.0e6], scale_cut: steps) == ["500", "2K", "2M"]

      assert Labels.comma([500, 1500], scale_cut: [{"x", 0}, {"", 1000}]) == ["500x", "1,500"]
    end

    test "steps down only for a whole number of the step below, after scale:" do
      # label_comma(scale = 60, scale_cut = cut_time_scale())(c(1.5, 2)); scale_cut =
      # c(0, a = 2, b = 5) on 6, steps 2.5 apart; cut_time_scale() on 5430, not a whole minute
      assert Labels.comma([1.5, 2], scale: 60, scale_cut: Labels.cut_time_scale()) ==
               ["90s", "2m"]

      assert Labels.comma([6], scale_cut: [{"", 0}, {"a", 2}, {"b", 5}]) == ["3a"]
      assert Labels.comma([5430], scale_cut: Labels.cut_time_scale()) == ["2h"]
    end

    test "writes the step's suffix before suffix:, and takes accuracy: for every step" do
      # label_comma(scale_cut = cut_short_scale(), suffix = " t")(c(0, 1500));
      # scale_cut = c(0, K = 1e3), accuracy = 0.1 on c(500, 1500);
      # label_currency(scale_cut = cut_short_scale(), accuracy = 0.1)(c(0, 1500, 2e6))
      assert Labels.comma([0, 1500], scale_cut: Labels.cut_short_scale(), suffix: " t") ==
               ["0 t", "2K t"]

      assert Labels.comma([500, 1500], scale_cut: [{"", 0}, {"K", 1000}], accuracy: 0.1) ==
               ["500.0", "1.5K"]

      assert Labels.currency([0, 1500, 2.0e6], scale_cut: Labels.cut_short_scale(), accuracy: 0.1) ==
               ["$0.0", "$1.5K", "$2.0M"]
    end

    test "applies after scale:, and leaves zero at scale 1 with the zero step's suffix" do
      # label_percent(scale_cut = cut_short_scale())(c(0, 5, 10, 20)); c(0, 0.0125), where zero
      # at the percent's scale would give both labels a decimal; cut_time_scale(TRUE) on
      # c(0, 0.5, 30)
      assert Labels.percent([0, 5, 10, 20], scale_cut: Labels.cut_short_scale()) ==
               ["0%", "500%", "1K%", "2K%"]

      assert Labels.percent([0, 0.0125], scale_cut: Labels.cut_short_scale()) == ["0%", "1%"]
      # label_comma(scale_cut = cut_short_scale())(c(0, 0.5)): zero shares 0.5's scale of 1
      assert Labels.comma([0, 0.5], scale_cut: Labels.cut_short_scale()) == ["0.0", "0.5"]

      assert Labels.comma([0, 0.5, 30], scale_cut: Labels.cut_time_scale(space: true)) ==
               ["0 ", "500 ms", "30 s"]
    end

    test "pads each step's labels apart when untrimmed" do
      # label_comma(scale_cut = cut_short_scale(), trim = FALSE)(c(1, 1.5e6, 2e6, 2.5e6, 10e6))
      assert Labels.comma([1, 1.5e6, 2.0e6, 2.5e6, 1.0e7],
               scale_cut: Labels.cut_short_scale(),
               trim: false
             ) == ["1", " 1.5M", " 2.0M", " 2.5M", "10.0M"]
    end
  end

  describe "the steps" do
    test "are R's cut_short_scale() and cut_long_scale(), with and without spaces" do
      # cut_short_scale(); cut_short_scale(TRUE); cut_long_scale()
      assert Labels.cut_short_scale() ==
               [{"", 0}, {"K", 1.0e3}, {"M", 1.0e6}, {"B", 1.0e9}, {"T", 1.0e12}]

      assert Labels.cut_short_scale(space: true) ==
               [{" ", 0}, {" K", 1.0e3}, {" M", 1.0e6}, {" B", 1.0e9}, {" T", 1.0e12}]

      assert Labels.cut_long_scale() ==
               [{"", 0}, {"K", 1.0e3}, {"M", 1.0e6}, {"B", 1.0e12}, {"T", 1.0e18}]

      assert Labels.cut_long_scale(space: false) == Labels.cut_long_scale()
    end

    test "are R's cut_si(), its thresholds R's 10^si_powers, its micro sign U+00B5" do
      # cut_si("g"), each threshold printed with sprintf("%.17g")
      assert Labels.cut_si("g") == [
               {" g", 0},
               {" yg", 1.0e-24},
               {" zg", 1.0e-21},
               {" ag", 1.0e-18},
               {" fg", 1.0e-15},
               {" pg", 1.0e-12},
               {" ng", 1.0e-9},
               {" µg", 1.0e-6},
               {" mg", 1.0e-3},
               {" g", 1},
               {" kg", 1.0e3},
               {" Mg", 1.0e6},
               {" Gg", 1.0e9},
               {" Tg", 1.0e12},
               {" Pg", 1.0e15},
               {" Eg", 1.0e18},
               {" Zg", 1.0e21},
               {" Yg", 1.0e24}
             ]
    end

    test "are R's cut_time_scale(), its micro sign U+03BC" do
      # cut_time_scale(TRUE), in a UTF-8 locale
      assert Labels.cut_time_scale(space: true) == [
               {" ", 0},
               {" ns", 1.0e-9},
               {" μs", 1.0e-6},
               {" ms", 1.0e-3},
               {" s", 1},
               {" m", 60},
               {" h", 3600},
               {" d", 86_400},
               {" w", 604_800}
             ]
    end
  end

  describe "a break scale: takes past the largest double" do
    test "is Inf, its sign styled, its prefix and suffix dropped once rounding passes it" do
      # label_number(scale = 100)(c(1e307, 1)); trim = FALSE on c(-1e307, 1, 2.5) and
      # c(1e307, 0.01); accuracy = 0.1 on c(1e307, 1); prefix = "$", suffix = "!",
      # style_positive = "plus" on c(1e307, -1e307); style_negative = "parens" and "minus" on
      # c(-1e307, 1)
      assert Labels.number([1.0e307, 1], scale: 100) == ["Inf", "100"]
      assert Labels.number([-1.0e307, 1, 2.5], scale: 100, trim: false) == ["-Inf", "100", "250"]
      assert Labels.number([1.0e307, 0.01], scale: 100, trim: false) == ["Inf", "  1"]
      assert Labels.number([1.0e307, 1], scale: 100, accuracy: 0.1) == ["Inf", "100.0"]

      assert Labels.number([1.0e307, -1.0e307],
               scale: 100,
               prefix: "$",
               suffix: "!",
               style_positive: :plus
             ) == ["+Inf", "-Inf"]

      assert Labels.number([-1.0e307, 1], scale: 100, style_negative: :parens) == ["(Inf)", "100"]
      assert Labels.number([-1.0e307, 1], scale: 100, style_negative: :minus) == ["−Inf", "100"]
    end

    test "is Inf where rounding to the accuracy takes it past" do
      # label_number(accuracy = 1e308)(c(1.79e308, 1e308)), the second label's start
      assert ["Inf", "100 000 000 000 000 001 097 906" <> _rest] =
               Labels.number([1.79e308, 1.0e308], accuracy: 1.0e308)
    end

    test "keeps its prefix and suffix when only the scaling passes it" do
      # label_number(scale = 100, accuracy = 1000, prefix = "$", suffix = "!")(c(1e307, 5));
      # prefix = "$", trim = FALSE on c(1e307, 5, -1e307)
      assert Labels.number([1.0e307, 5], scale: 100, accuracy: 1000, prefix: "$", suffix: "!") ==
               ["$Inf!", "$0!"]

      assert Labels.number([1.0e307, 5, -1.0e307],
               scale: 100,
               accuracy: 1000,
               prefix: "$",
               trim: false
             ) == ["$Inf", "$  0", "-$Inf"]
    end

    test "takes no step, no cents and no part in the others' accuracy" do
      # label_comma(scale = 100)(c(1e307, 1234, NA)); label_percent()(c(1e307, 0.5));
      # label_currency(scale = 100)(c(1e307, 1.5, 2)); label_number(scale = 100, scale_cut =
      # cut_short_scale())(c(1e307, 1500, 2500)); suffix = "m", prefix = "$", accuracy = 1e6 on
      # c(1e307, 15); label_number(scale = 1e300)(c(1e10, 1)), the second label's start;
      # scale = 100 on c(1e307, 1, 1.5); label_number()(c(-1e308, 1e308)), whose gap passes the
      # largest double, the labels' starts and lengths
      assert Labels.comma([1.0e307, 1234, nil], scale: 100) == ["Inf", "123,400", nil]
      assert Labels.percent([1.0e307, 0.5]) == ["Inf", "50%"]
      assert Labels.currency([1.0e307, 1.5, 2], scale: 100) == ["Inf", "$150", "$200"]

      assert Labels.number([1.0e307, 1500, 2500], scale: 100, scale_cut: Labels.cut_short_scale()) ==
               ["Inf", "150K", "250K"]

      assert Labels.number([1.0e307, 15],
               scale: 100,
               scale_cut: Labels.cut_short_scale(),
               suffix: "m",
               prefix: "$",
               accuracy: 1.0e6
             ) == ["$Infm", "$0Km"]

      assert ["Inf", "999 999 999 999 999 903 803 069" <> _rest] =
               Labels.number([1.0e10, 1], scale: 1.0e300)

      assert Labels.number([1.0e307, 1, 1.5], scale: 100) == ["Inf", "100", "150"]

      assert [
               "-100 000 000 000 000 001 097 9" <> _negative,
               "100 000 000 000 000 001 097 90" <> _positive
             ] = labels = Labels.number([-1.0e308, 1.0e308])

      assert Enum.map(labels, &String.length/1) == [412, 411]
    end

    test "takes no part in the others' accuracy where dividing it by one passes the double" do
      # label_number()(c(-1.5e308, 1, 1.25)); c(1.5e308, 1, 1.25); label_bytes("kiB", accuracy =
      # NULL)(c(1e15, 0.803, 6658.14, 0, -2.29e307))
      assert Labels.number([-1.5e308, 1, 1.25]) == ["-Inf", "1.00", "1.25"]
      assert Labels.number([1.5e308, 1, 1.25]) == ["Inf", "1.00", "1.25"]

      assert Labels.bytes([1.0e15, 0.803, 6658.14, 0, -2.29e307],
               units: "kiB",
               accuracy: nil,
               trim: false
             ) ==
               ["976 562 500 000.00012 kiB", "              0.00078 kiB"] ++
                 ["              6.50209 kiB", "              0.00000 kiB", "-Inf"]

      # R fails on these ("missing value where TRUE/FALSE needed"), so they are not R's: the
      # accuracy is the others' alone (design-log §4, the entry beginning "A break whose
      # quotient"), 1 leaving the first finite and 0.01, the gap a hair under 0.1, taking it past
      assert ["150 000 000 000 000 001 646 859" <> _rest, "1", "2"] =
               Labels.number([1.5e308, 1, 2])

      assert Labels.number([1.5e308, 1.1, 1.2]) == ["Inf", "1.10", "1.20"]
    end

    test "is Inf in scientific notation, inside its prefix and suffix" do
      # label_scientific(scale = 100)(c(1e307, -1e307, 1, NA)); prefix = "<", suffix = ">" on
      # c(1e307, 1)
      assert Labels.scientific([1.0e307, -1.0e307, 1, nil], scale: 100) ==
               ["Inf", "-Inf", "1e+02", nil]

      assert Labels.scientific([1.0e307, 1], scale: 100, prefix: "<", suffix: ">") ==
               ["<Inf>", "<1e+02>"]
    end
  end

  describe "scientific/2" do
    test "rounds as R's signif() does, in floats scaled into the digits" do
      # label_scientific(digits = 1)(c(0.15, 0.25, 0.35, 0.45)); label_scientific()(c(2.675,
      # 1.005, 0.125)); digits = 2 on c(0.125, 0.375, 12.5)
      assert Labels.scientific([0.15, 0.25, 0.35, 0.45], digits: 1) ==
               ["2e-01", "2e-01", "4e-01", "4e-01"]

      assert Labels.scientific([2.675, 1.005, 0.125]) == ["2.68e+00", "1.00e+00", "1.25e-01"]

      # digits = 1 on c(650000); digits = 2 on c(1250000, 1450000): divided by the power of
      # ten, 6.5 rounds to 6, where multiplying by its reciprocal lands above the half
      assert Labels.scientific([650_000], digits: 1) == ["6e+05"]
      assert Labels.scientific([1_250_000, 1_450_000], digits: 2) == ["1.2e+06", "1.4e+06"]

      assert Labels.scientific([0.125, 0.375, 12.5], digits: 2) == [
               "1.2e-01",
               "3.8e-01",
               "1.2e+01"
             ]
    end

    test "shares the mantissas' decimals, and shows at most 7 significant digits" do
      # label_scientific()(c(1, 10, 100)); c(1.234, 5); c(1e100, 1); digits = 8 on c(1/3, 1);
      # digits = 22 on c(123456.789)
      assert Labels.scientific([1, 10, 100]) == ["1e+00", "1e+01", "1e+02"]
      assert Labels.scientific([1.234, 5]) == ["1.23e+00", "5.00e+00"]
      assert Labels.scientific([1.0e100, 1]) == ["1e+100", "1e+00"]
      assert Labels.scientific([1 / 3, 1], digits: 8) == ["3.333333e-01", "1.000000e+00"]
      assert Labels.scientific([123_456.789], digits: 22) == ["1.234568e+05"]
    end

    test "rounds the largest and smallest doubles in R's two steps" do
      # label_scientific(digits = 2)(c(1.09e308, 1.2345e307, 1.75e306)); c(1.79e308,
      # 1.7976931348623157e308), which R rounds down; digits = 3 on c(6.2097656959666999e-311,
      # 1.23456e-307, 2.5e-306); digits = 1 on 2.5e306, 2.5e-306 and c(2.5e305, 2.5e-305,
      # 3.5e306, 3.5e-306), either side of the branch
      assert Labels.scientific([1.09e308, 1.234_5e307, 1.75e306], digits: 2) ==
               ["1.1e+308", "1.2e+307", "1.7e+306"]

      assert Labels.scientific([1.79e308, 1.797_693_134_862_315_7e308], digits: 2) ==
               ["1.7e+308", "1.7e+308"]

      assert Labels.scientific([2.5e306], digits: 1) == ["2e+306"]
      assert Labels.scientific([2.5e-306], digits: 1) == ["3e-306"]

      assert Labels.scientific([2.5e305, 2.5e-305, 3.5e306, 3.5e-306], digits: 1) ==
               ["2e+305", "3e-305", "3e+306", "4e-306"]

      assert Labels.scientific([6.2097656959666999e-311, 1.23456e-307, 2.5e-306], digits: 3) ==
               ["6.21e-311", "1.23e-307", "2.50e-306"]
    end

    test "scales a number below 1e-287 by its digits in two powers" do
      # label_scientific(digits = 22)(c(1.234567890123456789e-300));
      # digits = 15 on c(1.5e-290, 2.5e-300); digits = 9 on c(1.234567e-303)
      assert Labels.scientific([1.234567890123456789e-300], digits: 22) == ["1.234568e-300"]
      assert Labels.scientific([1.5e-290, 2.5e-300], digits: 15) == ["1.5e-290", "2.5e-300"]
      assert Labels.scientific([1.234567e-303], digits: 9) == ["1.234567e-303"]
    end

    test "writes the sign, a zero, the scale and the marks, and no label for a missing break" do
      # label_scientific()(c(-1, 0, 1, NA)); scale = 100, prefix = "~", suffix = "%" on
      # c(0.0123, -0.5); decimal.mark = "," on c(1234, 5)
      assert Labels.scientific([-1, 0, 1, nil]) == ["-1e+00", "0e+00", "1e+00", nil]

      assert Labels.scientific([0.0123, -0.5], scale: 100, prefix: "~", suffix: "%") ==
               ["~1.23e+00%", "~-5.00e+01%"]

      assert Labels.scientific([1234, 5], decimal_mark: ",") == ["1,23e+03", "5,00e+00"]
      assert Labels.scientific([]) == []
    end
  end

  describe "number_auto/1" do
    test "writes breaks past a million in whole numbers or scientific notation, the shorter" do
      # label_number_auto()(c(0, 2e6, 4e6)); c(1, 1e7, 123456789); c(0, 1.5e6, 2e6, 2.5e6);
      # c(-3e6, 0, 3e6); c(1e6, 1000001); c(0, 1e6); c(0, 1000000.5); c(1000, 2e6), a tie
      assert Labels.number_auto([0, 2.0e6, 4.0e6]) == ["0", "2e+06", "4e+06"]
      assert Labels.number_auto([1, 1.0e7, 123_456_789]) == ["1", "10 000 000", "123 456 789"]

      assert Labels.number_auto([0, 1.5e6, 2.0e6, 2.5e6]) ==
               ["0", "1.5e+06", "2.0e+06", "2.5e+06"]

      assert Labels.number_auto([-3.0e6, 0, 3.0e6]) == ["-3e+06", "0", "3e+06"]
      assert Labels.number_auto([1.0e6, 1_000_001]) == ["1 000 000", "1 000 001"]
      assert Labels.number_auto([0, 1.0e6]) == ["0", "1 000 000"]
      assert Labels.number_auto([0, 1_000_000.5]) == ["0", "1e+06"]
      assert Labels.number_auto([1000, 2.0e6]) == ["1 000", "2e+06"]
    end

    test "writes breaks below 0.001 in plain decimals or scientific notation, the shorter" do
      # label_number_auto()(c(0, 0.0005, 0.25, 0.5)); c(0.0001234, 0.5); c(0.0001, 0.0002,
      # 0.5); c(1e-10, 1); c(0.001, 0.002); c(0.00012, 0.5), a tie
      assert Labels.number_auto([0, 0.0005, 0.25, 0.5]) ==
               ["0.0000", "0.0005", "0.2500", "0.5000"]

      assert Labels.number_auto([0.0001234, 0.5]) == ["0.0001234", "0.5000000"]
      assert Labels.number_auto([0.0001, 0.0002, 0.5]) == ["1e-04", "2e-04", "5e-01"]
      assert Labels.number_auto([1.0e-10, 1]) == ["1e-10", "1e+00"]
      assert Labels.number_auto([0.001, 0.002]) == ["0.001", "0.002"]
      assert Labels.number_auto([0.000_12, 0.5]) == ["0.00012", "0.50000"]
    end

    test "writes years as they are" do
      # label_number_auto()(c(1990, 2000, 2010)); c(1000, 2200); c(1990.5, 2000); c(999.5,
      # 2000); c(1000, 2200.5); c(0, 1990, 2000); c(-1990, 2000)
      assert Labels.number_auto([1990, 2000, 2010]) == ["1990", "2000", "2010"]
      assert Labels.number_auto([1000, 2200]) == ["1000", "2200"]
      assert Labels.number_auto([1990.5, 2000]) == ["1990.5", "2000.0"]
      assert Labels.number_auto([999.5, 2000]) == ["1 000", "2 000"]
      assert Labels.number_auto([1000, 2200.5]) == ["1 000", "2 200"]
      assert Labels.number_auto([0, 1990, 2000]) == ["0", "1 990", "2 000"]
      assert Labels.number_auto([-1990, 2000]) == ["-1 990", "2 000"]
    end

    test "writes breaks past 1000 in whole numbers, and the rest as R's format() does" do
      # label_number_auto()(c(0, 5000, 10000)); c(1000.5, 2500); c(-1500, 1500); c(0, 0.5, 1);
      # c(0.1234567891, 1); c(0.001, 1000); c(0, 0); c(1000, 1000.5); c(0, 1000.5)
      assert Labels.number_auto([0, 5000, 10_000]) == ["0", "5 000", "10 000"]
      assert Labels.number_auto([1000.5, 2500]) == ["1 000", "2 500"]
      assert Labels.number_auto([-1500, 1500]) == ["-1 500", "1 500"]
      assert Labels.number_auto([0, 0.5, 1]) == ["0.0", "0.5", "1.0"]
      assert Labels.number_auto([0.1234567891, 1]) == ["0.1234568", "1.0000000"]
      assert Labels.number_auto([0.001, 1000]) == ["1e-03", "1e+03"]
      assert Labels.number_auto([0, 0]) == ["0", "0"]
      assert Labels.number_auto([1000, 1000.5]) == ["1000.0", "1000.5"]
      assert Labels.number_auto([0, 1000.5]) == ["0", "1 000"]
      assert Labels.number_auto([]) == []
    end

    test "labels a missing break NA where R's format() writes them all, and not otherwise" do
      # label_number_auto()(c(NA, 0.5, 1)); c(NA_real_); c(-1, 1990, NA); c(0, 5000, NA). The
      # last three rows are not R's: it fails on a missing break among years, and gives no
      # vector of labels with one past a million or below 0.001, where both its ways of writing
      # it give NA (design-log §4, the entry beginning "A missing break's label").
      assert Labels.number_auto([nil, 0.5, 1]) == ["NA", "0.5", "1.0"]
      assert Labels.number_auto([nil]) == ["NA"]
      assert Labels.number_auto([-1, 1990, nil]) == ["-1", "1 990", nil]
      assert Labels.number_auto([0, 5000, nil]) == ["0", "5 000", nil]
      assert Labels.number_auto([1990, 2000, nil]) == ["1990", "2000", "NA"]
      assert Labels.number_auto([0, 2.0e6, nil]) == ["0", "2e+06", nil]
      assert Labels.number_auto([0, 0.0005, nil]) == ["0e+00", "5e-04", nil]
    end
  end

  describe "format_log/2" do
    test "writes each exponent as R's format() writes them together, padded" do
      # format_log(c(0.01, 1, 100, 1e5)); c(1, 10, NA); c(0.5, 2, 8); digits = 3 on c(0.5, 2,
      # 8); digits = 1 on c(2, 3); c(1e-300, 1e300)
      assert Labels.format_log([0.01, 1, 100, 1.0e5]) == ["10^-2", "10^ 0", "10^ 2", "10^ 5"]
      assert Labels.format_log([1, 10, nil]) == ["10^ 0", "10^ 1", nil]
      assert Labels.format_log([0.5, 2, 8]) == ["10^-0.30103", "10^ 0.30103", "10^ 0.90309"]

      assert Labels.format_log([0.5, 2, 8], digits: 3) ==
               ["10^-0.301", "10^ 0.301", "10^ 0.903"]

      assert Labels.format_log([2, 3], digits: 1) == ["10^0.3", "10^0.5"]
      assert Labels.format_log([1.0e-300, 1.0e300]) == ["10^-300", "10^ 300"]
      assert Labels.format_log([]) == []
    end

    test "signs each power and writes a zero 0, when signed" do
      # format_log(c(-100, 0, 100)); c(-100, NA, 100); signed = TRUE on c(1, 100); c(-0.5, 2);
      # c(0, 10, 100), a zero signing them alone
      assert Labels.format_log([-100, 0, 100]) == ["-10^2", "0", "+10^2"]
      assert Labels.format_log([-100, nil, 100]) == ["-10^ 2", nil, "+10^ 2"]
      assert Labels.format_log([1, 100], signed: true) == ["+10^0", "+10^2"]
      assert Labels.format_log([-0.5, 2]) == ["-10^-0.30103", "+10^ 0.30103"]
      assert Labels.format_log([0, 10, 100]) == ["0", "+10^1", "+10^2"]
    end

    test "writes the base as R writes a number alone" do
      # format_log(c(1, 2, 8), base = 2); c(1, 2, 3), base = 2; c(1, exp(1), exp(2)), base =
      # exp(1); c(1, 1e12), base = 1e6; c(1, 4), base = 0.5; c(1, 4, 100), base = 1/3;
      # c(1, 1e12), base = 1e15
      assert Labels.format_log([1, 2, 8], base: 2) == ["2^0", "2^1", "2^3"]
      assert Labels.format_log([1, 2, 3], base: 2) == ["2^0.000000", "2^1.000000", "2^1.584963"]

      assert Labels.format_log([1, :math.exp(1), :math.exp(2)], base: :math.exp(1)) ==
               ["2.71828182845905^0", "2.71828182845905^1", "2.71828182845905^2"]

      assert Labels.format_log([1, 1.0e12], base: 1.0e6) == ["1e+06^0", "1e+06^2"]
      assert Labels.format_log([1, 4], base: 0.5) == ["0.5^ 0", "0.5^-2"]

      assert Labels.format_log([1, 4, 100], base: 1 / 3) == [
               "0.333333333333333^ 0.000000",
               "0.333333333333333^-1.261860",
               "0.333333333333333^-4.191807"
             ]

      assert Labels.format_log([1, 1.0e12], base: 1.0e15) == ["1e+15^0.0", "1e+15^0.8"]
    end

    test "rounds the exponents as R's zapsmall() does first" do
      # format_log(c(1, 1e300), base = 1.0001, digits = 3); c(1, 1e300), base = 1.0001; the
      # same with digits = 9, rounded whole; c(1, 1e300), base = 1.00001, past 1e7;
      # c(1, 1 + 1e-10); c(1), every exponent 0; c(0.001, 0.01), every one negative; c(1e-300, 2),
      # rounded by the largest magnitude, not the largest exponent
      assert Labels.format_log([1, 1.0e300], base: 1.0001, digits: 3) ==
               ["1.0001^      0", "1.0001^6908101"]

      assert Labels.format_log([1, 1.0e300], base: 1.0001) == ["1.0001^      0", "1.0001^6908101"]

      assert Labels.format_log([1, 1.0e300], base: 1.0001, digits: 9) ==
               ["1.0001^      0", "1.0001^6908101"]

      assert Labels.format_log([1, 1.0e300], base: 1.000_01) ==
               ["1.00001^       0", "1.00001^69077898"]

      assert Labels.format_log([1, 1 + 1.0e-10]) == ["10^0.000000e+00", "10^4.342945e-11"]
      assert Labels.format_log([1]) == ["10^0"]
      assert Labels.format_log([0.001, 0.01]) == ["10^-3", "10^-2"]
      assert Labels.format_log([1.0e-300, 2]) == ["10^-300.00000", "10^   0.30103"]
    end
  end

  describe "log/2" do
    test "gives each break's power, its exponent read back and written alone" do
      # label_log()(c(0.01, 1, 100, 1e5)); c(1, 10, NA); c(0.5, 2, 8); c(1, 2, 3); 10^c(-2.5,
      # 0, 2.5); c(1e-300, 1e300); c(1, 1 + 1e-10); c(1); c(1, 1e300), base = 1.00001, each
      # deparsed
      assert Labels.log([0.01, 1, 100, 1.0e5]) == [
               {:power, "10", "-2"},
               {:power, "10", "0"},
               {:power, "10", "2"},
               {:power, "10", "5"}
             ]

      assert Labels.log([1, 10, nil]) == [{:power, "10", "0"}, {:power, "10", "1"}, nil]

      assert Labels.log([0.5, 2, 8]) ==
               [{:power, "10", "-0.301"}, {:power, "10", "0.301"}, {:power, "10", "0.903"}]

      assert Labels.log([1, 2, 3]) ==
               [{:power, "10", "0"}, {:power, "10", "0.301"}, {:power, "10", "0.477"}]

      assert Labels.log([10 ** -2.5, 1, 10 ** 2.5]) ==
               [{:power, "10", "-2.5"}, {:power, "10", "0"}, {:power, "10", "2.5"}]

      assert Labels.log([1.0e-300, 1.0e300]) == [{:power, "10", "-300"}, {:power, "10", "300"}]
      assert Labels.log([1, 1 + 1.0e-10]) == [{:power, "10", "0"}, {:power, "10", "4.34e-11"}]
      assert Labels.log([1]) == [{:power, "10", "0"}]

      assert Labels.log([1, 1.0e300], base: 1.000_01) ==
               [{:power, "1.00001", "0"}, {:power, "1.00001", "69077898"}]

      assert Labels.log([]) == []
    end

    test "shows up to digits: significant digits, and never more than 7" do
      # label_log(digits = 1)(c(2, 3)); digits = 22
      assert Labels.log([2, 3], digits: 1) == [{:power, "10", "0.3"}, {:power, "10", "0.5"}]

      assert Labels.log([2, 3], digits: 22) ==
               [{:power, "10", "0.30103"}, {:power, "10", "0.4771213"}]
    end

    test "puts each sign before its power, and labels a zero 0, when signed" do
      # label_log()(c(-100, 0, 100)); signed = TRUE on c(1, 100); c(-0.5, 2); c(0, 10, 100)
      assert Labels.log([-100, 0, 100]) == [
               {:signed, "-", {:power, "10", "2"}},
               "0",
               {:signed, "+", {:power, "10", "2"}}
             ]

      assert Labels.log([1, 100], signed: true) ==
               [{:signed, "+", {:power, "10", "0"}}, {:signed, "+", {:power, "10", "2"}}]

      assert Labels.log([-0.5, 2]) ==
               [{:signed, "-", {:power, "10", "-0.301"}}, {:signed, "+", {:power, "10", "0.301"}}]

      assert Labels.log([0, 10, 100]) ==
               ["0", {:signed, "+", {:power, "10", "1"}}, {:signed, "+", {:power, "10", "2"}}]
    end

    test "writes the base and the exponents as R deparses them" do
      # label_log(base = 2)(c(1, 2, 8)); base = exp(1) on c(1, exp(1), 20); base = 1e6 on c(1,
      # 1e12); base = 0.5 on c(1, 4); base = 1/3 on c(1, 4); base = 1e15 on c(1, 1e12);
      # base = 1.0001 on c(1, 1e300) and c(1.0001, 1e300)
      assert Labels.log([1, 2, 8], base: 2) ==
               [{:power, "2", "0"}, {:power, "2", "1"}, {:power, "2", "3"}]

      euler = "2.71828182845905"

      assert Labels.log([1, :math.exp(1), 20], base: :math.exp(1)) ==
               [{:power, euler, "0"}, {:power, euler, "1"}, {:power, euler, "3"}]

      assert Labels.log([1, 1.0e12], base: 1.0e6) == [
               {:power, "1e+06", "0"},
               {:power, "1e+06", "2"}
             ]

      assert Labels.log([1, 4], base: 0.5) == [{:power, "0.5", "0"}, {:power, "0.5", "-2"}]

      third = "0.333333333333333"

      assert Labels.log([1, 4], base: 1 / 3) == [{:power, third, "0"}, {:power, third, "-1.26"}]

      assert Labels.log([1, 1.0e12], base: 1.0e15) == [
               {:power, "1e+15", "0"},
               {:power, "1e+15", "0.8"}
             ]

      assert Labels.log([1, 1.0e300], base: 1.0001) ==
               [{:power, "1.0001", "0"}, {:power, "1.0001", "6908101"}]

      assert Labels.log([1.0001, 1.0e300], base: 1.0001) ==
               [{:power, "1.0001", "1"}, {:power, "1.0001", "6908101"}]
    end
  end

  describe "bytes/2" do
    test "writes each break in the SI unit it reaches, plain bytes B" do
      # label_bytes()(c(NA, 0, 1, 999, 1000, 1023, 1024, 1500, 1e6, 1048576, 1.5e9, -2048, 1e27,
      # 1e30)); c(1e24, 1e25, 9.99e23, 5e23); c(999.5, 999500, 999.4999)
      assert Labels.bytes(
               [nil, 0, 1, 999, 1000, 1023, 1024, 1500, 1.0e6, 1_048_576] ++
                 [1.5e9, -2048, 1.0e27, 1.0e30]
             ) ==
               [nil, "0 B", "1 B", "999 B", "1 kB", "1 kB", "1 kB", "2 kB", "1 MB", "1 MB"] ++
                 ["2 GB", "-2 kB", "1 000 YB", "1 000 000 YB"]

      assert Labels.bytes([1.0e24, 1.0e25, 9.99e23, 5.0e23]) ==
               ["1 YB", "10 YB", "999 ZB", "500 ZB"]

      assert Labels.bytes([999.5, 999_500, 999.4999]) == ["1 000 B", "1 000 kB", "999 B"]
    end

    # R writes plain bytes " iB" under binary units, which these rows write " B" (design-log §4,
    # the entry beginning "Plain bytes under binary units").
    test "writes each break in the binary unit it reaches, a break not whole in it in bytes" do
      # label_bytes("auto_binary")(c(NA, 0, 1, 999, 1000, 1023, 1024, 1500, 1e6, 1048576, 1.5e9,
      # -2048, 1e27, 1e30)); c(1023.5, 1048064, 1048063)
      assert Labels.bytes(
               [nil, 0, 1, 999, 1000, 1023, 1024, 1500, 1.0e6, 1_048_576] ++
                 [1.5e9, -2048, 1.0e27, 1.0e30],
               units: :auto_binary
             ) ==
               [nil, "0 B", "1 B", "999 B", "1 000 B", "1 023 B", "1 kiB", "1 500 B"] ++
                 ["1 000 000 B", "1 MiB", "1 GiB", "-2 kiB", "827 YiB", "827 181 YiB"]

      assert Labels.bytes([1023.5, 1_048_064, 1_048_063], units: :auto_binary) ==
               ["1 024 B", "1 048 064 B", "1 048 063 B"]
    end

    test "writes every break in a unit given, its scale divided by the unit's size" do
      # label_bytes("kB")(c(NA, 0, 1, 999, 1000, 1500, 1e6, 1048576, -2048, 1e27)); "kiB" on
      # c(0, 1, 1024, 1500, 1e6, 1048576, 1e27); "MB" on c(1e5, 5e5, 1.5e6); "GiB" on c(2^30,
      # 2^31, 3e9); "TB" on c(1e12, 2.5e12); "PiB" on c(2^50, 2^51); "EB", accuracy = 0.1 on
      # c(1e18, 2.25e18); "ZB" on c(1e21, 3e21); "YiB" on c(1e24, 1e27, 1e30); "kB", scale = 2 on
      # c(1000, 2000); "MiB", scale = 1000 on c(1048.576, 2097.152)
      assert Labels.bytes([nil, 0, 1, 999, 1000, 1500, 1.0e6, 1_048_576, -2048, 1.0e27],
               units: "kB"
             ) ==
               [
                 nil,
                 "0 kB",
                 "0 kB",
                 "1 kB",
                 "1 kB",
                 "2 kB",
                 "1 000 kB",
                 "1 049 kB",
                 "-2 kB",
                 "999 999 999 999 999 983 222 784 kB"
               ]

      assert Labels.bytes([0, 1, 1024, 1500, 1.0e6, 1_048_576, 1.0e27], units: "kiB") ==
               [
                 "0 kiB",
                 "0 kiB",
                 "1 kiB",
                 "1 kiB",
                 "977 kiB",
                 "1 024 kiB",
                 "976 562 500 000 000 012 976 128 kiB"
               ]

      assert Labels.bytes([1.0e5, 5.0e5, 1.5e6], units: "MB") == ["0 MB", "0 MB", "2 MB"]

      assert Labels.bytes([1_073_741_824, 2_147_483_648, 3.0e9], units: "GiB") ==
               ["1 GiB", "2 GiB", "3 GiB"]

      assert Labels.bytes([1.0e12, 2.5e12], units: "TB") == ["1 TB", "2 TB"]

      assert Labels.bytes([1_125_899_906_842_624, 2_251_799_813_685_248], units: "PiB") ==
               ["1 PiB", "2 PiB"]

      assert Labels.bytes([1.0e18, 2.25e18], units: "EB", accuracy: 0.1) == ["1.0 EB", "2.2 EB"]
      assert Labels.bytes([1.0e21, 3.0e21], units: "ZB") == ["1 ZB", "3 ZB"]

      assert Labels.bytes([1.0e24, 1.0e27, 1.0e30], units: "YiB") ==
               ["1 YiB", "827 YiB", "827 181 YiB"]

      assert Labels.bytes([1000, 2000], units: "kB", scale: 2) == ["2 kB", "4 kB"]

      assert Labels.bytes([1048.576, 2097.152], units: "MiB", scale: 1000) ==
               ["1 MiB", "2 MiB"]
    end

    test "rounds to whole units, to the accuracy given, or to one worked out under nil" do
      # label_bytes(accuracy = NULL)(c(1500, 2500, 1e6)); accuracy = 0.1 on it;
      # label_bytes("auto_binary", accuracy = NULL)(c(512, 1536, 2560, 1048576));
      # label_bytes("kB", accuracy = NULL)(c(1250, 1500, 1750))
      assert Labels.bytes([1500, 2500, 1.0e6], accuracy: nil) == ["1.5 kB", "2.5 kB", "1 MB"]
      assert Labels.bytes([1500, 2500, 1.0e6], accuracy: 0.1) == ["1.5 kB", "2.5 kB", "1.0 MB"]

      assert Labels.bytes([512, 1536, 2560, 1_048_576], units: :auto_binary, accuracy: nil) ==
               ["512 B", "1 536 B", "2 560 B", "1 MiB"]

      assert Labels.bytes([1250, 1500, 1750], units: "kB", accuracy: nil) ==
               ["1.25 kB", "1.50 kB", "1.75 kB"]
    end

    test "takes number/2's scale, marks, padding, prefix and styles" do
      # label_bytes(scale = 1024)(c(1, 2, 1000)); big.mark = ",", trim = FALSE on c(1, 1e6,
      # 999999); "kB", big.mark = "," on c(1e9); style_negative = "parens", prefix = "~" on
      # c(-2048, 3000); style_negative = "minus", style_positive = "plus" on c(-2048, 0, 3000);
      # "kB", decimal.mark = ",", accuracy = 0.01 on c(1234, 5678); trim = FALSE on c(NA, 1, 1500)
      assert Labels.bytes([1, 2, 1000], scale: 1024) == ["1 kB", "2 kB", "1 MB"]

      assert Labels.bytes([1, 1.0e6, 999_999], big_mark: ",", trim: false) ==
               ["    1 B", "    1 MB", "1,000 kB"]

      assert Labels.bytes([1.0e9], units: "kB", big_mark: ",") == ["1,000,000 kB"]

      assert Labels.bytes([-2048, 3000], style_negative: :parens, prefix: "~") ==
               ["(~2 kB)", "~3 kB"]

      assert Labels.bytes([-2048, 0, 3000], style_negative: :minus, style_positive: :plus) ==
               ["−2 kB", "0 B", "+3 kB"]

      assert Labels.bytes([1234, 5678], units: "kB", decimal_mark: ",", accuracy: 0.01) ==
               ["1,23 kB", "5,68 kB"]

      assert Labels.bytes([nil, 1, 1500], trim: false) == [nil, " 1 B", " 2 kB"]
    end

    test "labels a break scale: takes past the largest double Inf, and no breaks with none" do
      # label_bytes(scale = 10)(c(1e308, 1)); "YiB", scale = 1e300 on c(1e300, 1e290);
      # label_bytes()(numeric(0))
      assert Labels.bytes([1.0e308, 1], scale: 10) == ["Inf", "10 B"]
      assert Labels.bytes([1.0e300, 1.0e290], units: "YiB", scale: 1.0e300) == ["Inf", "Inf"]
      assert Labels.bytes([]) == []
    end
  end

  describe "ordinal/2" do
    test "rounds each break half to even and writes English ordinals" do
      # label_ordinal()(c(NA, 0, 1, 2, 3, 4, 11, 12, 13, 21, 101, 111, 112, 1001, 1e4, 1e5,
      # 123456, 1e6, -1, -11, -12, 0.5, 1.5, 2.5, 2.4999, -0.4)); c(22, 23, 24, 211, 212, 213,
      # 1011, 1021, 3.5, -2.5, -3.5, 113); c(1e14, 999999999999999, 123456789012345)
      assert Labels.ordinal(
               [nil, 0, 1, 2, 3, 4, 11, 12, 13, 21, 101, 111, 112, 1001, 1.0e4, 1.0e5] ++
                 [123_456, 1.0e6, -1, -11, -12, 0.5, 1.5, 2.5, 2.4999, -0.4]
             ) ==
               [nil, "0th", "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st"] ++
                 ["101st", "111th", "112th", "1 001st", "10 000th", "100 000th", "123 456th"] ++
                 ["1 000 000th", "-1st", "-11th", "-12th", "0th", "2nd", "2nd", "2nd", "0th"]

      assert Labels.ordinal([22, 23, 24, 211, 212, 213, 1011, 1021, 3.5, -2.5, -3.5, 113]) ==
               ["22nd", "23rd", "24th", "211th", "212th", "213th", "1 011th", "1 021st"] ++
                 ["4th", "-2nd", "-4th", "113th"]

      assert Labels.ordinal([1.0e14, 999_999_999_999_999, 123_456_789_012_345]) ==
               ["100 000 000 000 000th", "999 999 999 999 999th", "123 456 789 012 345th"]
    end

    test "takes number/2's marks, padding, prefix and styles, and a suffix after its own" do
      # label_ordinal(big.mark = ",")(c(1001, 1e6)); prefix = "#", suffix = " place" on c(1, 2,
      # NA); prefix = "#" on c(-1, 2); style_negative = "parens" on c(-1, -2, 3);
      # style_negative = "minus", style_positive = "space" on c(-1, 0, 2); style_positive =
      # "plus" on c(-1, 0, 2); trim = FALSE on c(1, 1000)
      assert Labels.ordinal([1001, 1.0e6], big_mark: ",") == ["1,001st", "1,000,000th"]

      assert Labels.ordinal([1, 2, nil], prefix: "#", suffix: " place") ==
               ["#1st place", "#2nd place", nil]

      assert Labels.ordinal([-1, 2], prefix: "#") == ["-#1st", "#2nd"]
      assert Labels.ordinal([-1, -2, 3], style_negative: :parens) == ["(1)st", "(2)nd", "3rd"]

      assert Labels.ordinal([-1, 0, 2], style_negative: :minus, style_positive: :space) ==
               ["−1st", "0th", "\u20072nd"]

      assert Labels.ordinal([-1, 0, 2], style_positive: :plus) == ["-1st", "0th", "+2nd"]
      assert Labels.ordinal([1, 1000], trim: false) == ["    1st", "1 000th"]
    end

    test "pads a missing break's neighbours as though it were 1, as R writes it" do
      # label_ordinal(trim = FALSE)(c(NA, 1, 22)); prefix = "$", trim = FALSE, rules = list(a =
      # "^1$", b = "(?<=[02468])$", c = "[13579]$", d = ".") on c(1.5, NA)
      assert Labels.ordinal([nil, 1, 22], trim: false) == [nil, " 1st", "22nd"]

      rules = [{"a", ~r/^1$/}, {"b", ~r/(?<=[02468])$/}, {"c", ~r/[13579]$/}, {"d", ~r/./}]
      assert Labels.ordinal([1.5, nil], prefix: "$", trim: false, rules: rules) == ["$2b", nil]
    end

    test "takes the first rule matching the digits, a negative's minus among them" do
      # label_ordinal(rules = list(a = "1", b = "."))(c(1, 2, 3, 12)); rules = list(a = "1",
      # a = "2", b = ".") on c(1, 2, 3); rules = list(x = "^1$", y = ".") on c(-1, 1, 1e5);
      # rules = list(neg = "^-", pos = ".") on c(-3, -0.4, 0, 3); rules = ordinal_english() on
      # c(1, 2)
      assert Labels.ordinal([1, 2, 3, 12], rules: [{"a", ~r/1/}, {"b", ~r/./}]) ==
               ["1a", "2b", "3b", "12a"]

      assert Labels.ordinal([1, 2, 3], rules: [{"a", ~r/1/}, {"a", ~r/2/}, {"b", ~r/./}]) ==
               ["1a", "2a", "3b"]

      assert Labels.ordinal([-1, 1, 1.0e5], rules: [{"x", ~r/^1$/}, {"y", ~r/./}]) ==
               ["-1y", "1x", "100 000y"]

      assert Labels.ordinal([-3, -0.4, 0, 3], rules: [{"neg", ~r/^-/}, {"pos", ~r/./}]) ==
               ["-3neg", "0pos", "0pos", "3pos"]

      assert Labels.ordinal([1, 2], rules: Labels.ordinal_english()) == ["1st", "2nd"]
    end

    # R matches its rules against as.character(), which writes a round number in scientific
    # notation where that is shorter; the digits are matched here (design-log §4, the entry
    # beginning "`ordinal/2`'s rules are matched"), so these rows are not R's.
    test "matches a round number's digits, where R matches its scientific notation" do
      # R: label_ordinal()(c(1e21, 2e22)) is "...st", "...nd", from "1e+21" and "2e+22";
      # rules = list(even = "[02468]$", odd = ".") on 2e5 is "200 000odd", from "2e+05"
      assert Labels.ordinal([1.0e21, 2.0e22]) ==
               ["1 000 000 000 000 000 000 000th", "20 000 000 000 000 000 000 000th"]

      assert Labels.ordinal([2.0e5], rules: [{"even", ~r/[02468]$/}, {"odd", ~r/./}]) ==
               ["200 000even"]
    end

    test "labels no breaks with none" do
      assert Labels.ordinal([]) == []
    end
  end

  describe "pvalue/2" do
    test "writes a p-value below the accuracy as less, and above 1 less it as more" do
      # label_pvalue()(c(NA, -0.5, 0, 0.0004, 0.0005, 0.00051, 0.001, 0.0015, 0.0025, 0.01, 0.05,
      # 0.5, 0.999, 0.9994, 0.9995, 0.9996, 1, 1.5, 1e6)); c(1e308, -1e308, 0.0125, 0.0135)
      assert Labels.pvalue(
               [nil, -0.5, 0, 0.0004, 0.0005, 0.00051, 0.001, 0.0015, 0.0025, 0.01, 0.05] ++
                 [0.5, 0.999, 0.9994, 0.9995, 0.9996, 1, 1.5, 1.0e6]
             ) ==
               [nil, "<0.001", "<0.001", "<0.001", "<0.001", "<0.001", "0.001", "0.002"] ++
                 ["0.002", "0.010", "0.050", "0.500", "0.999", ">0.999", ">0.999", ">0.999"] ++
                 [">0.999", ">0.999", ">0.999"]

      assert Labels.pvalue([1.0e308, -1.0e308, 0.0125, 0.0135]) ==
               [">0.999", "<0.001", "0.012", "0.014"]
    end

    test "rounds the bounds' labels to the accuracy too" do
      # label_pvalue(accuracy = 0.01)(c(0.001, 0.005, 0.0051, 0.01, 0.123, 0.985, 0.99, 0.995,
      # 0.999)); accuracy = 0.05 on c(0.01, 0.05, 0.07, 0.5, 0.94, 0.95, 0.96); 0.5 on c(0, 0.25,
      # 0.5, 0.75, 1); 0.3 on c(0.1, 0.3, 0.5, 0.65, 0.7, 0.8); 0.25 on c(0.1, 0.25, 0.5, 0.75,
      # 0.8); 0.002 on c(0.001, 0.003, 0.5, 0.997, 0.999); 0.1 on c(0.05, 0.1, 0.9, 0.95); 1e-4 on
      # c(5e-5, 0.12345, 0.99995); 1e-10 on c(1e-11, 0.5, 1 - 1e-11)
      assert Labels.pvalue([0.001, 0.005, 0.0051, 0.01, 0.123, 0.985, 0.99, 0.995, 0.999],
               accuracy: 0.01
             ) == ["<0.01", "<0.01", "<0.01", "0.01", "0.12", "0.98", "0.99", ">0.99", ">0.99"]

      assert Labels.pvalue([0.01, 0.05, 0.07, 0.5, 0.94, 0.95, 0.96], accuracy: 0.05) ==
               ["<0.05", "0.05", "0.05", "0.50", "0.95", "0.95", ">0.95"]

      assert Labels.pvalue([0, 0.25, 0.5, 0.75, 1], accuracy: 0.5) ==
               ["<0.5", "<0.5", "0.5", ">0.5", ">0.5"]

      assert Labels.pvalue([0.1, 0.3, 0.5, 0.65, 0.7, 0.8], accuracy: 0.3) ==
               ["<0.3", "0.3", "0.6", "0.6", "0.6", ">0.6"]

      assert Labels.pvalue([0.1, 0.25, 0.5, 0.75, 0.8], accuracy: 0.25) ==
               ["<0.25", "0.25", "0.50", "0.75", ">0.75"]

      assert Labels.pvalue([0.001, 0.003, 0.5, 0.997, 0.999], accuracy: 0.002) ==
               ["<0.002", "0.004", "0.500", "0.996", ">0.998"]

      assert Labels.pvalue([0.05, 0.1, 0.9, 0.95], accuracy: 0.1) ==
               ["<0.1", "0.1", "0.9", ">0.9"]

      assert Labels.pvalue([5.0e-5, 0.12345, 0.99995], accuracy: 1.0e-4) ==
               ["<0.0001", "0.1234", ">0.9999"]

      assert Labels.pvalue([1.0e-11, 0.5, 1 - 1.0e-11], accuracy: 1.0e-10) ==
               ["<0.0000000001", "0.5000000000", ">0.9999999999"]
    end

    test "takes the prefixes, p's prefixes, and the decimal mark given" do
      # label_pvalue(add_p = TRUE)(c(NA, -0.5, 0, 0.0005, 0.001, 0.05, 0.999, 0.9995, 1.5));
      # prefix = c("less ", "is ", "more ") on c(1e-4, 0.05, 0.9999, NA); decimal.mark = "," on
      # c(1e-4, 0.05, 0.9999)
      assert Labels.pvalue([nil, -0.5, 0, 0.0005, 0.001, 0.05, 0.999, 0.9995, 1.5], add_p: true) ==
               [nil, "p<0.001", "p<0.001", "p<0.001", "p=0.001", "p=0.050", "p=0.999"] ++
                 ["p>0.999", "p>0.999"]

      assert Labels.pvalue([1.0e-4, 0.05, 0.9999, nil], prefix: {"less ", "is ", "more "}) ==
               ["less 0.001", "is 0.050", "more 0.999", nil]

      assert Labels.pvalue([1.0e-4, 0.05, 0.9999], decimal_mark: ",") ==
               ["<0,001", "0,050", ">0,999"]
    end

    test "labels no p-values with none" do
      assert Labels.pvalue([]) == []
    end
  end

  describe "timespan/2" do
    test "writes seconds in the largest step of time each reaches" do
      # label_timespan()(c(NA, 0, 1e-10, 1e-9, 5e-7, 0.001, 0.5, 1, 30, 59, 60, 90, 120, 3600,
      # 5400, 86400, 129600, 604800, 1209600, 1e7, -90)); space = TRUE on c(NA, 0, 1e-10, 1e-9,
      # 5e-7, 0.001, 0.5, 1, 30, 90, 120, 5400, 129600, 604800, 1e7, -90)
      assert Labels.timespan(
               [nil, 0, 1.0e-10, 1.0e-9, 5.0e-7, 0.001, 0.5, 1, 30, 59, 60, 90, 120] ++
                 [3600, 5400, 86_400, 129_600, 604_800, 1_209_600, 1.0e7, -90]
             ) ==
               [nil, "0", "0", "1ns", "500ns", "1ms", "500ms", "1s", "30s", "59s", "1m"] ++
                 ["90s", "2m", "1h", "90m", "1d", "36h", "1.0w", "2.0w", "16.5w", "-90s"]

      assert Labels.timespan(
               [nil, 0, 1.0e-10, 1.0e-9, 5.0e-7, 0.001, 0.5, 1, 30, 90, 120, 5400] ++
                 [129_600, 604_800, 1.0e7, -90],
               space: true
             ) ==
               [nil, "0 ", "0 ", "1 ns", "500 ns", "1 ms", "500 ms", "1 s", "30 s", "90 s"] ++
                 ["2 m", "90 m", "36 h", "1 w", "17 w", "-90 s"]
    end

    test "counts the breaks in the unit given" do
      # label_timespan("mins")(c(0, 0.5, 1, 1.5, 60, 90, 1440, 10080)); "hours" on c(0, 0.5, 1,
      # 1.5, 24, 36, 168); "days" on c(0, 0.5, 1, 1.5, 7, 10); "weeks" on c(0, 0.5, 1, 1.5, 52)
      # and c(0.1, 0.3); "hours" on c(1/3, 2/3)
      assert Labels.timespan([0, 0.5, 1, 1.5, 60, 90, 1440, 10_080], unit: :minute) ==
               ["0", "30s", "1m", "90s", "1h", "90m", "1d", "1w"]

      assert Labels.timespan([0, 0.5, 1, 1.5, 24, 36, 168], unit: :hour) ==
               ["0", "30m", "1h", "90m", "1d", "36h", "1w"]

      assert Labels.timespan([0, 0.5, 1, 1.5, 7, 10], unit: :day) ==
               ["0", "12h", "1d", "36h", "1w", "10d"]

      assert Labels.timespan([0, 0.5, 1, 1.5, 52], unit: :week) ==
               ["0", "84h", "1.0w", "1.5w", "52.0w"]

      assert Labels.timespan([0.1, 0.3], unit: :week) == ["1 008m", "2d"]
      assert Labels.timespan([1 / 3, 2 / 3], unit: :hour) == ["20m", "40m"]
    end

    test "takes number/2's accuracy, scale, marks, padding, prefix, suffix and styles" do
      # label_timespan(accuracy = 0.1)(c(1, 90, 5400)); accuracy = 1, scale = 60 on c(1, 1.5,
      # 90); suffix = " ago", prefix = "~" on c(1, 60, -60); big.mark = "," on 1e4 * 604800;
      # trim = FALSE on c(1, 100, 3600) and c(NA, 1, 100); style_positive = "plus",
      # style_negative = "minus" on c(-60, 0, 60); "days", decimal.mark = ",", accuracy = 0.1 on
      # c(0.25, 1.5)
      assert Labels.timespan([1, 90, 5400], accuracy: 0.1) == ["1.0s", "90.0s", "90.0m"]
      assert Labels.timespan([1, 1.5, 90], accuracy: 1, scale: 60) == ["1m", "90s", "90m"]

      assert Labels.timespan([1, 60, -60], suffix: " ago", prefix: "~") ==
               ["~1s ago", "~1m ago", "-~1m ago"]

      assert Labels.timespan([1.0e4 * 604_800], big_mark: ",") == ["10,000w"]
      assert Labels.timespan([1, 100, 3600], trim: false) == ["  1s", "100s", "  1h"]
      assert Labels.timespan([nil, 1, 100], trim: false) == [nil, "  1s", "100s"]

      assert Labels.timespan([-60, 0, 60], style_positive: :plus, style_negative: :minus) ==
               ["−1m", "0", "+1m"]

      assert Labels.timespan([0.25, 1.5], unit: :day, decimal_mark: ",", accuracy: 0.1) ==
               ["6,0h", "36,0h"]
    end

    test "labels a break its unit or scale: takes past the largest double Inf" do
      # label_timespan("weeks")(c(1e303, 3e302, -1e303, 1)); "weeks", style_negative = "parens",
      # prefix = "~", suffix = "!" on c(-1e303, 1e303, 1); "weeks", trim = FALSE on c(1e303, 1,
      # 2); "weeks", accuracy = 0.5 on c(1e303, 1, 2); scale = 1e10 on c(1e300, 1)
      assert Labels.timespan([1.0e303, 3.0e302, -1.0e303, 1], unit: :week) ==
               ["Inf", "Inf", "-Inf", "1w"]

      assert Labels.timespan([-1.0e303, 1.0e303, 1],
               unit: :week,
               style_negative: :parens,
               prefix: "~",
               suffix: "!"
             ) == ["(Inf)", "Inf", "~1w!"]

      assert Labels.timespan([1.0e303, 1, 2], unit: :week, trim: false) == ["Inf", "  1w", "  2w"]

      assert Labels.timespan([1.0e303, 1, 2], unit: :week, accuracy: 0.5) ==
               ["Inf", "1.0w", "2.0w"]

      assert Labels.timespan([1.0e300, 1], scale: 1.0e10) == ["Inf", "16 534w"]
    end

    test "labels no breaks with none" do
      assert Labels.timespan([]) == []
    end
  end

  describe "a call Scales.Labels refuses" do
    test "names a digits: outside 1 to 22, for every function that takes it" do
      for digits <- [0, 23, 2.5, -1] do
        for label <- [
              fn -> Labels.scientific([1], digits: digits) end,
              fn -> Labels.log([1], digits: digits) end,
              fn -> Labels.format_log([1], digits: digits) end
            ] do
          error = assert_raise NimbleOptions.ValidationError, label
          assert error.message =~ ":digits"
          assert error.message =~ inspect(digits)
        end
      end
    end

    test "names an option scientific/2 does not take, trim: among them" do
      for option <- [trim: false, big_mark: ","] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Labels.scientific([1], [option]) end

        {name, _value} = option
        assert error.message =~ inspect(name)
      end
    end

    test "names a base that is not a positive number other than 1" do
      for base <- [1, 1.0, 0, -2, "10"] do
        for label <- [
              fn -> Labels.log([1], base: base) end,
              fn -> Labels.format_log([1], base: base) end
            ] do
          error = assert_raise NimbleOptions.ValidationError, label
          assert error.message =~ "positive number other than 1"
          assert error.message =~ "got: #{inspect(base)}"
        end
      end
    end

    test "names a break at or below zero labelled unsigned" do
      for {breaks, value} <- [{[0, 10], "0.0"}, {[-100, 10, nil], "-100.0"}] do
        log = assert_raise ArgumentError, fn -> Labels.log(breaks, signed: false) end
        assert log.message =~ "Labels.log/2"
        assert log.message =~ "got: #{value}"

        format_log =
          assert_raise ArgumentError, fn -> Labels.format_log(breaks, signed: false) end

        assert format_log.message =~ "Labels.format_log/2"
      end

      error = assert_raise NimbleOptions.ValidationError, fn -> Labels.log([1], signed: :yes) end
      assert error.message =~ ":signed"
    end

    test "names breaks that are not a list of numbers and nils, for the new labellers too" do
      for {label, name} <- [
            {fn -> Labels.scientific([1, "2"]) end, "Labels.scientific/2"},
            {fn -> Labels.number_auto([1, "2"]) end, "Labels.number_auto/1"},
            {fn -> Labels.log([1, "2"]) end, "Labels.log/2"},
            {fn -> Labels.format_log([1, "2"]) end, "Labels.format_log/2"}
          ] do
        error = assert_raise ArgumentError, label
        assert error.message =~ name
      end
    end

    test "names breaks that are not a list of numbers and nils" do
      for breaks <- [[1, "2"], [1, :infinity], 5] do
        error = assert_raise ArgumentError, fn -> Labels.comma(breaks) end
        assert error.message =~ "Labels.comma/2"
        assert error.message =~ inspect(breaks)
      end

      number = assert_raise ArgumentError, fn -> Labels.number([1, "2"]) end
      assert number.message =~ "Labels.number/2"
      percent = assert_raise ArgumentError, fn -> Labels.percent([1, "2"]) end
      assert percent.message =~ "Labels.percent/2"
      currency = assert_raise ArgumentError, fn -> Labels.currency([1, "2"]) end
      assert currency.message =~ "Labels.currency/2"
    end

    test "names an option the formatter does not take, and the ones it does" do
      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Labels.comma([1], largest_with_fractional: 10)
        end

      assert error.message =~ ":largest_with_fractional"
      assert error.message =~ ":style_positive"
    end

    test "names an option's value it cannot use" do
      for option <- [
            accuracy: 0,
            scale: -1,
            prefix: :dollar,
            big_mark: 1,
            decimal_mark: "",
            trim: nil,
            style_negative: :dash,
            style_positive: :plus_sign
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Labels.percent([1], [option]) end

        {name, value} = option
        assert error.message =~ inspect(name)
        assert error.message =~ "got: #{inspect(value)}"
      end

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Labels.currency([1], largest_with_fractional: "big")
        end

      assert error.message =~ ":largest_with_fractional"
      assert error.message =~ ~s(got: "big")
    end

    test "names steps without a zero, with a threshold twice, or not pairs" do
      no_zero =
        assert_raise NimbleOptions.ValidationError, fn ->
          Labels.comma([1], scale_cut: [{"K", 1000}])
        end

      assert no_zero.message =~ "threshold 0"
      assert no_zero.message =~ inspect([{"K", 1000}])

      twice =
        assert_raise NimbleOptions.ValidationError, fn ->
          Labels.comma([1], scale_cut: [{"", 0}, {"K", 1000}, {"J", 1000.0}])
        end

      assert twice.message =~ "twice"
      assert twice.message =~ ~s({"J", 1000.0})

      for steps <- [[], [{"", -1}], [{:k, 0}], [{"", 0}, {:k, 1000}], [{"", 0}, "K"], %{"" => 0}] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Labels.comma([1], scale_cut: steps)
          end

        assert error.message =~ "{suffix, threshold} pairs"
        assert error.message =~ inspect(steps)
      end
    end

    test "names a step set's option it does not take, and a unit that is not a string" do
      for options <- [[space: 1], [gap: true]] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Labels.cut_short_scale(options) end

        assert error.message =~ ":space"
      end

      error = assert_raise ArgumentError, fn -> Labels.cut_si(:g) end
      assert error.message =~ "unit"
      assert error.message =~ ":g"
    end

    # R: label_bytes("KiB") "must be one of "kB", ..., "YiB", not "KiB""; label_bytes(suffix =
    # "x") and label_bytes(scale_cut = ...) "matched by multiple actual arguments"
    test "names a unit bytes/2 does not spell, and the options it does not take" do
      for units <- ["KiB", "KB", "B", "iB", "kb", :auto, :kB, nil] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Labels.bytes([1], units: units) end

        assert error.message =~ ~s(:auto_si, :auto_binary or one of "kB", "MB")
        assert error.message =~ ~s("YiB")
        assert error.message =~ "got: #{inspect(units)}"
      end

      for option <- [suffix: "x", scale_cut: Labels.cut_short_scale(), accuracy: 0] do
        {name, _value} = option
        error = assert_raise NimbleOptions.ValidationError, fn -> Labels.bytes([1], [option]) end
        assert error.message =~ inspect(name)
      end
    end

    # R: label_ordinal(accuracy = 0.1) "matched by multiple actual arguments"; scale writes the
    # unscaled break's suffix ("10st"); rules = list() "at least one vector element is
    # required"; a break no rule matches takes another's suffix ("1a" "2b" "3a" "4b")
    test "names an option ordinal/2 does not take, rules that are not rules, and a break none match" do
      for option <- [
            accuracy: 0.1,
            scale: 10,
            scale_cut: Labels.cut_short_scale(),
            decimal_mark: ","
          ] do
        {name, _value} = option

        error =
          assert_raise NimbleOptions.ValidationError, fn -> Labels.ordinal([1], [option]) end

        assert error.message =~ inspect(name)
      end

      for rules <- [
            [],
            [{"a", "1"}],
            [{:a, ~r/1/}],
            ["st"],
            %{"st" => ~r/1/},
            [{"st", ~r/1/}, {"th", "."}]
          ] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Labels.ordinal([1], rules: rules) end

        assert error.message =~ "{suffix, regex} pair"
        assert error.message =~ inspect(rules)
      end

      for {breaks, digits} <- [{[2, 3], ~s("3")}, {[2, nil, -2.6], ~s("-3")}] do
        error =
          assert_raise ArgumentError, fn ->
            Labels.ordinal(breaks, rules: [{"a", ~r/2/}])
          end

        assert error.message =~ "Labels.ordinal/2 found no rule matching #{digits}"
        assert error.message =~ inspect([{"a", ~r/2/}])
      end
    end

    # R: label_pvalue(accuracy = 1)(c(0, 0.5, 1)) is "<1" ">0" ">0"; accuracy = 0 "NA"; a
    # negative fails in format(); prefix = c("a", "b") "must be a length 3 character vector";
    # with add_p = TRUE, prefix silently wins
    test "names an accuracy above 0.5, a prefix not three strings, and add_p: beside prefix:" do
      for accuracy <- [0.6, 1, 2, 0, -0.1, nil, "0.01"] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Labels.pvalue([0.5], accuracy: accuracy)
          end

        assert error.message =~ "positive number no larger than 0.5"
        assert error.message =~ "got: #{inspect(accuracy)}"
      end

      for prefix <-
            [{"a", "b"}, ["a", "b", "c"], {"a", "b", "c", "d"}] ++
              [{:a, "b", "c"}, {"a", :b, "c"}, {"a", "b", :c}] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Labels.pvalue([0.5], prefix: prefix)
          end

        assert error.message =~ "three strings"
        assert error.message =~ "got: #{inspect(prefix)}"
      end

      error =
        assert_raise ArgumentError, fn ->
          Labels.pvalue([0.5], prefix: {"a", "b", "c"}, add_p: true)
        end

      assert error.message =~ "add_p: true or prefix:, not both"
      assert error.message =~ ~s(prefix: {"a", "b", "c"})

      assert Labels.pvalue([0.5], prefix: {"a", "b", "c"}, add_p: false) == ["b0.500"]
    end

    # R: label_timespan("min") "must be one of "secs", ..."; scale_cut "matched by multiple
    # actual arguments"
    test "names a unit timespan/2 does not count in, and scale_cut:" do
      for unit <- ["mins", :min, :month] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Labels.timespan([1], unit: unit) end

        assert error.message =~ ":unit"
        assert error.message =~ ":week"
      end

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Labels.timespan([1], scale_cut: Labels.cut_short_scale())
        end

      assert error.message =~ ":scale_cut"
    end

    test "names breaks that are not a list of numbers and nils, for bytes, ordinals, p-values and spans of time" do
      for {label, name} <- [
            {fn -> Labels.bytes([1, "2"]) end, "Labels.bytes/2"},
            {fn -> Labels.ordinal([1, "2"]) end, "Labels.ordinal/2"},
            {fn -> Labels.pvalue([1, "2"]) end, "Labels.pvalue/2"},
            {fn -> Labels.timespan([1, "2"]) end, "Labels.timespan/2"}
          ] do
        error = assert_raise ArgumentError, label
        assert error.message =~ name
      end
    end
  end

  # `plain/1` writes numbers the Elixir way, not R's, so these labels are worked out from what it
  # promises, not R's output.
  describe "plain/1" do
    test "every label gets the decimals the most precise needs, rounding error and -0.0 dropped" do
      assert Labels.plain([2.5, 2.75, 0.30000000000000004, -0.0]) ==
               ["2.50", "2.75", "0.30", "0.00"]
    end

    test "rounding error in the 16th significant digit, as R's extended breaks carry, is dropped" do
      assert Labels.plain([
               0.0,
               4.9999999999999996e-6,
               9.999999999999999e-6,
               1.4999999999999999e-5
             ]) ==
               ["0.000000", "0.000005", "0.000010", "0.000015"]
    end

    test "a break that needs all 15 significant digits keeps them" do
      assert Labels.plain([1_000_000_000_000.0, 1_000_000_000_000.25]) ==
               ["1000000000000.00", "1000000000000.25"]
    end

    test "whole breaks have no decimals and no thousands separators" do
      assert Labels.plain([0.0, 100_000.0, 200_000.0]) == ["0", "100000", "200000"]
    end

    test "small breaks are written in plain decimals, never scientific notation" do
      assert Labels.plain([0.0, 0.00005, 0.0001]) == ["0.00000", "0.00005", "0.00010"]
    end

    test "no breaks have no labels" do
      assert Labels.plain([]) == []
    end
  end
end
