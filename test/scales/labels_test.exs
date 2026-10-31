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
