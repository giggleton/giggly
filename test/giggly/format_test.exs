defmodule Giggly.FormatTest do
  use ExUnit.Case, async: true

  alias Giggly.Format

  doctest Giggly.Format

  # Golden: every expected label below is R's own, from R 4.6.1 with scales 1.4.0 (the image
  # `giggly-r:ggplot2-4.0.3`), each from the call in the comment above it. They move only if
  # scales' formatting does.

  describe "comma/2's default accuracy" do
    test "is a tenth of the power of ten at or below the smallest gap, shared by every label" do
      # label_comma()(c(2, 2.25, 3)); c(10, 12.5)
      assert Format.comma([2, 2.25, 3]) == ["2.00", "2.25", "3.00"]
      assert Format.comma([10, 12.5]) == ["10.0", "12.5"]
    end

    test "is that power of ten itself when every break is a multiple of it" do
      # label_comma()(c(0, 0.5, 1)); c(0.1, 0.2, 0.3); c(-0.4, 0.4)
      assert Format.comma([0, 0.5, 1]) == ["0.0", "0.5", "1.0"]
      assert Format.comma([0.1, 0.2, 0.3]) == ["0.1", "0.2", "0.3"]
      assert Format.comma([-0.4, 0.4]) == ["-0.4", "0.4"]
    end

    test "is 1 for one break or breaks closer than rounding error, and never more than 1" do
      # label_comma()(1234.5678); c(3); c(1e-10, 2e-10); c(0, 1e5, 2e5, 3e5); c(-1500.5, 0, 2000)
      assert Format.comma([1234.5678]) == ["1,235"]
      assert Format.comma([3]) == ["3"]
      assert Format.comma([1.0e-10, 2.0e-10]) == ["0", "0"]
      assert Format.comma([0, 1.0e5, 2.0e5, 3.0e5]) == ["0", "100,000", "200,000", "300,000"]
      assert Format.comma([-1500.5, 0, 2000]) == ["-1,500", "0", "2,000"]
    end

    test "reads the smallest gap however the breaks come: repeated, unsorted, between any two" do
      # label_comma()(c(0.5, 0.5, 1)); c(1, 0.5); c(0, 1, 1.25)
      assert Format.comma([0.5, 0.5, 1]) == ["0.5", "0.5", "1.0"]
      assert Format.comma([1, 0.5]) == ["1.0", "0.5"]
      assert Format.comma([0, 1, 1.25]) == ["0.00", "1.00", "1.25"]
    end

    test "takes a gap of exactly the rounding error's size as a gap" do
      # label_comma()(c(0, sqrt(.Machine$double.eps))); c(3, 3 + 1e-9), a gap below it, whose
      # accuracy of 1 leaves 3 as it is
      assert Format.comma([0, :math.sqrt(2.220446049250313e-16)]) ==
               ["0.000000000", "0.000000015"]

      assert Format.comma([3, 3 + 1.0e-9]) == ["3", "3"]
    end

    test "counts a negative zero and a zero as one break" do
      # label_comma()(c(-0, 0, 1))
      assert Format.comma([-0.0, 0.0, 1]) == ["0", "0", "1"]
    end
  end

  describe "comma/2's rounding" do
    test "takes a half to the even neighbour" do
      # label_comma(accuracy = 1)(c(0.5, 1.5, 2.5, 12.5, -2.5))
      assert Format.comma([0.5, 1.5, 2.5, 12.5, -2.5], accuracy: 1) ==
               ["0", "2", "2", "12", "-2"]
    end

    test "rounds to a multiple of the accuracy given, with its decimals, at most twenty" do
      # label_comma(accuracy = 10)(c(1234, 5678)); accuracy = 0.001 on c(1, 2);
      # accuracy = 1e-25 on c(1, 2)
      assert Format.comma([1234, 5678], accuracy: 10) == ["1,230", "5,680"]
      assert Format.comma([1, 2], accuracy: 0.001) == ["1.000", "2.000"]

      assert Format.comma([1, 2], accuracy: 1.0e-25) ==
               ["0.99999999999999988898", "1.99999999999999977796"]
    end

    test "gives every label the decimals any needs at seven significant digits" do
      # label_comma(accuracy = 0.25)(c(0.25, 0.5, 1234567.25)); c(1234567.25, 1234567.5)
      assert Format.comma([0.25, 0.5, 1_234_567.25], accuracy: 0.25) ==
               ["0.25", "0.50", "1,234,567.25"]

      assert Format.comma([1_234_567.25, 1_234_567.5], accuracy: 0.25) ==
               ["1,234,567.2", "1,234,567.5"]
    end

    test "counts seven significant digits, no more and no fewer, from the first" do
      # label_comma(accuracy = 0.25)(c(12345.25, 12345.5)), seven digits;
      # c(123456.25, 123456.5), eight; accuracy = 1.25e-6 on c(0.1234575, 0.25), seven below 1
      assert Format.comma([12_345.25, 12_345.5], accuracy: 0.25) == ["12,345.25", "12,345.50"]
      assert Format.comma([123_456.25, 123_456.5], accuracy: 0.25) == ["123,456.2", "123,456.5"]

      assert Format.comma([0.1234575, 0.25], accuracy: 1.25e-6) == ["0.1234575", "0.2500000"]
    end

    test "prints a last digit halfway between two as the even one" do
      # label_comma(accuracy = 0.25)(c(1234567.75, 1234568.25)): 12345677.5 tenths up to
      # 12345678, 12345682.5 down to 12345682
      assert Format.comma([1_234_567.75, 1_234_568.25], accuracy: 0.25) ==
               ["1,234,567.8", "1,234,568.2"]
    end

    test "leaves no sign on a number that rounds to zero" do
      # label_comma(accuracy = 1)(c(-0.001, 0.001, -1))
      assert Format.comma([-0.001, 0.001, -1], accuracy: 1) == ["0", "0", "-1"]
    end
  end

  describe "comma/2's marks" do
    test "marks every three whole digits, however many" do
      # label_comma()(c(1e20, 2e20)); c(1000L, 2500L)
      assert Format.comma([1.0e20, 2.0e20]) ==
               ["100,000,000,000,000,000,000", "200,000,000,000,000,000,000"]

      assert Format.comma([1000, 2500]) == ["1,000", "2,500"]
      # label_comma()(c(3e15, 1))
      assert Format.comma([3.0e15, 1]) == ["3,000,000,000,000,000", "1"]
    end

    test "takes the marks given, even a comma as both" do
      # label_comma(big.mark = " ", decimal.mark = ",")(c(1234567.5, 2));
      # big.mark = "" on c(1990, 2000, 2010); decimal.mark = "," on c(1234.5, 1)
      assert Format.comma([1_234_567.5, 2], big_mark: " ", decimal_mark: ",") ==
               ["1 234 568", "2"]

      assert Format.comma([1990, 2000, 2010], big_mark: "") == ["1990", "2000", "2010"]
      assert Format.comma([1234.5, 1], decimal_mark: ",") == ["1,234", "1"]
    end

    test "writes the prefix and suffix around the number, after a negative's sign" do
      # label_comma(prefix = "~", suffix = " t")(c(-1000, 2000));
      # scale = 1e-3, suffix = "k" on c(0, 1500, 3000)
      assert Format.comma([-1000, 2000], prefix: "~", suffix: " t") == ["-~1,000 t", "~2,000 t"]
      assert Format.comma([0, 1500, 3000], scale: 1.0e-3, suffix: "k") == ["0.0k", "1.5k", "3.0k"]
    end

    test "marks negatives and positives in the style given" do
      # label_comma(style_negative = "minus")(c(-1, 0, 1));
      # style_negative = "parens", style_positive = "plus"; style_positive = "space"
      assert Format.comma([-1, 0, 1], style_negative: :minus) == ["−1", "0", "1"]

      assert Format.comma([-1, 0, 1], style_negative: :parens, style_positive: :plus) ==
               ["(1)", "0", "+1"]

      assert Format.comma([-1, 0, 1], style_positive: :space) == ["-1", "0", " 1"]
    end

    test "labels no breaks with no labels" do
      # label_comma()(numeric())
      assert Format.comma([]) == []
    end
  end

  describe "comma/2 untrimmed" do
    test "pads each number to the widest, marks included" do
      # label_comma(trim = FALSE)(c(1, 1000)); big.mark = "" on c(1, 1e6);
      # c(-0.5, 1000.25, 12)
      assert Format.comma([1, 1000], trim: false) == ["    1", "1,000"]
      assert Format.comma([1, 1.0e6], trim: false, big_mark: "") == ["      1", "1000000"]
      assert Format.comma([-0.5, 1000.25, 12], trim: false) == ["    0", "1,000", "   12"]
      # label_comma(trim = FALSE)(c(0, 0.5)): zero shows one whole digit
      assert Format.comma([0, 0.5], trim: false) == ["0.0", "0.5"]
    end

    test "pads to the width R estimates, a digit wider when rounding carries a number up" do
      # label_comma(trim = FALSE, accuracy = 0.1)(c(99999999.94, 1.5)), with and without
      # big.mark = ""
      assert Format.comma([99_999_999.94, 1.5], trim: false, accuracy: 0.1) ==
               [" 99,999,999.9", "          1.5"]

      assert Format.comma([99_999_999.94, 1.5], trim: false, accuracy: 0.1, big_mark: "") ==
               [" 99999999.9", "        1.5"]
    end

    test "pads to the digits printed when rounding to seven digits carries past them" do
      # label_comma(trim = FALSE, accuracy = 1)(c(99999996, 1)), with and without big.mark = "":
      # seven digits round 99999996 to 1e8, but it prints with eight
      assert Format.comma([99_999_996, 1], trim: false, accuracy: 1) ==
               ["99,999,996", "         1"]

      assert Format.comma([99_999_996, 1], trim: false, accuracy: 1, big_mark: "") ==
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
        assert Format.comma(breaks, trim: false, big_mark: "", accuracy: accuracy) == expected
      end
    end

    test "counts characters, not bytes, in a wide mark" do
      # label_comma(trim = FALSE, big.mark = "’")(c(1, 1e6));
      # decimal.mark = "::", accuracy = 0.01 on c(1.5, 1000.25)
      assert Format.comma([1, 1.0e6], trim: false, big_mark: "’") ==
               ["        1", "1’000’000"]

      assert Format.comma([1.5, 1000.25], trim: false, decimal_mark: "::", accuracy: 0.01) ==
               ["    1::50", "1,000::25"]
    end
  end

  describe "percent/2" do
    test "multiplies by 100, writes a %, and marks thousands with a space" do
      # label_percent()(c(-0.05, 0, 25)); c(0.001, 0.002); scale = 1 on c(10, 20)
      assert Format.percent([-0.05, 0, 25]) == ["-5%", "0%", "2 500%"]
      assert Format.percent([0.001, 0.002]) == ["0.1%", "0.2%"]
      assert Format.percent([10, 20], scale: 1) == ["10%", "20%"]
    end

    test "rounds in R's order of floating-point operations" do
      # label_percent(accuracy = 1)(c(0.145, 0.155, 0.285)): 0.145 / 0.01 is just under 14.5
      assert Format.percent([0.145, 0.155, 0.285], accuracy: 1) == ["14%", "16%", "28%"]
    end

    test "takes the options comma/2 does" do
      # label_percent(big.mark = ",")(c(0, 12.345));
      # decimal.mark = ",", accuracy = 0.1 on c(0.125, 0.5); trim = FALSE on
      # c(0.001, 0.0125, 0.5) and c(0.05, 0.5, 1); style_negative = "parens" on c(-0.1, 0.1)
      assert Format.percent([0, 12.345], big_mark: ",") == ["0%", "1,234%"]
      assert Format.percent([0.125, 0.5], decimal_mark: ",", accuracy: 0.1) == ["12,5%", "50,0%"]
      assert Format.percent([0.001, 0.0125, 0.5], trim: false) == [" 0.1%", " 1.2%", "50.0%"]
      assert Format.percent([0.05, 0.5, 1], trim: false) == ["  5%", " 50%", "100%"]
      assert Format.percent([-0.1, 0.1], style_negative: :parens) == ["(10%)", "10%"]
    end
  end

  describe "currency/2's cents" do
    test "show when some amount is not whole and none is over 100,000" do
      # label_currency()(c(1e5, 1.5)); c(-2e5, 0, 1.5); c(100000.5); scale = 100 on
      # c(0.125, 1)
      assert Format.currency([1.0e5, 1.5]) == ["$100,000.00", "$1.50"]
      assert Format.currency([-2.0e5, 0, 1.5]) == ["-$200,000", "$0", "$2"]
      assert Format.currency([100_000.5]) == ["$100,000"]
      assert Format.currency([0.125, 1], scale: 100) == ["$12.50", "$100.00"]
      # label_currency(scale = 1000)(c(0.5, 1)): whole once scaled
      assert Format.currency([0.5, 1], scale: 1000) == ["$500", "$1,000"]
    end

    test "move with largest_with_fractional and give way to accuracy: and scale_cut:" do
      # label_currency(largest_with_fractional = 10)(c(1.5, 20)); accuracy = 1 on
      # c(0.25, 1.75); scale = 1e-6, suffix = "M", accuracy = 0.1 on c(0, 2.5e6, 5e6)
      assert Format.currency([1.5, 20], largest_with_fractional: 10) == ["$2", "$20"]
      assert Format.currency([0.25, 1.75], accuracy: 1) == ["$0", "$2"]

      assert Format.currency([0, 2.5e6, 5.0e6], scale: 1.0e-6, suffix: "M", accuracy: 0.1) ==
               ["$0.0M", "$2.5M", "$5.0M"]

      # label_currency(scale_cut = cut_short_scale())(c(0, 1.5e6, 2e6)): the millions' own
      # accuracy, not whole dollars
      assert Format.currency([0, 1.5e6, 2.0e6], scale_cut: Format.cut_short_scale()) ==
               ["$0", "$1.5M", "$2.0M"]
    end
  end

  describe "currency/2's marks" do
    test "mark thousands with a space when both marks would be a comma" do
      # label_currency(decimal.mark = ",")(c(1234.5, 1))
      assert Format.currency([1234.5, 1], decimal_mark: ",") == ["$1 234,50", "$1,00"]
    end

    test "write a negative's sign outside the prefix, in the style given" do
      # label_currency(prefix = "€")(c(-1, 2.5)); style_negative = "parens" and "minus" on
      # c(-1, 0, 1); trim = FALSE on c(-1.5, 1000)
      assert Format.currency([-1, 2.5], prefix: "€") == ["-€1.00", "€2.50"]
      assert Format.currency([-1, 0, 1], style_negative: :parens) == ["($1)", "$0", "$1"]
      assert Format.currency([-1, 0, 1], style_negative: :minus) == ["−$1", "$0", "$1"]
      assert Format.currency([-1.5, 1000], trim: false) == ["-$    1.50", "$1,000.00"]
    end

    test "label no amounts with no labels" do
      # label_currency()(numeric())
      assert Format.currency([]) == []
    end
  end

  describe "scale_cut:" do
    test "writes each label in the largest step it reaches, sharing decimals within a step" do
      # label_comma(scale_cut = cut_short_scale())(c(0, 5e5, 1e6, 1.5e6, 2e6));
      # c(0, 2500, 5000, 7500, 10000); c(999.9, 1000); c(1e15, 2e15)
      assert Format.comma([0, 5.0e5, 1.0e6, 1.5e6, 2.0e6], scale_cut: Format.cut_short_scale()) ==
               ["0", "500K", "1.0M", "1.5M", "2.0M"]

      assert Format.comma([0, 2500, 5000, 7500, 10_000], scale_cut: Format.cut_short_scale()) ==
               ["0", "2.5K", "5.0K", "7.5K", "10.0K"]

      assert Format.comma([999.9, 1000], scale_cut: Format.cut_short_scale()) == ["1,000", "1K"]

      assert Format.comma([1.0e15, 2.0e15], scale_cut: Format.cut_short_scale()) ==
               ["1,000T", "2,000T"]
    end

    test "rounds in R's order of floating-point operations, a lone label to a whole number" do
      # label_comma(scale_cut = cut_short_scale())(c(0, 1500, 1e6, 2.5e9)): 1/1e-9 is not
      # exact, so two and a half billion rounds up; c(-1500, 1500); cut_long_scale() on
      # c(5e8, 1.5e12)
      assert Format.comma([0, 1500, 1.0e6, 2.5e9], scale_cut: Format.cut_short_scale()) ==
               ["0", "2K", "1M", "3B"]

      assert Format.comma([-1500, 1500], scale_cut: Format.cut_short_scale()) == ["-1.5K", "1.5K"]
      assert Format.comma([5.0e8, 1.5e12], scale_cut: Format.cut_long_scale()) == ["500M", "2B"]
    end

    test "writes a label in the step below when that is not a power of ten lower" do
      # label_comma(scale_cut = c(" sec" = 0, " min" = 60, " hr" = 3600))(c(30, 90, 5400, 7200));
      # cut_si("g") on c(0.0015, 1.5, 1500)
      steps = [{" sec", 0}, {" min", 60}, {" hr", 3600}]

      assert Format.comma([30, 90, 5400, 7200], scale_cut: steps) ==
               ["30 sec", "90 sec", "90 min", "2 hr"]

      assert Format.comma([0.0015, 1.5, 1500], scale_cut: Format.cut_si("g")) ==
               ["2 mg", "2 g", "2 kg"]
    end

    test "takes steps in any order, and an empty suffix on any step as no step" do
      # label_comma(scale_cut = c(M = 1e6, K = 1e3, 0))(c(500, 1500, 2e6));
      # scale_cut = c(x = 0, 1000) on c(500, 1500), whose 1000 R never finds by its empty name
      steps = [{"M", 1.0e6}, {"K", 1000}, {"", 0}]
      assert Format.comma([500, 1500, 2.0e6], scale_cut: steps) == ["500", "2K", "2M"]

      assert Format.comma([500, 1500], scale_cut: [{"x", 0}, {"", 1000}]) == ["500x", "1,500"]
    end

    test "steps down only for a whole number of the step below, after scale:" do
      # label_comma(scale = 60, scale_cut = cut_time_scale())(c(1.5, 2)); scale_cut =
      # c(0, a = 2, b = 5) on 6, steps 2.5 apart; cut_time_scale() on 5430, not a whole minute
      assert Format.comma([1.5, 2], scale: 60, scale_cut: Format.cut_time_scale()) ==
               ["90s", "2m"]

      assert Format.comma([6], scale_cut: [{"", 0}, {"a", 2}, {"b", 5}]) == ["3a"]
      assert Format.comma([5430], scale_cut: Format.cut_time_scale()) == ["2h"]
    end

    test "writes the step's suffix before suffix:, and takes accuracy: for every step" do
      # label_comma(scale_cut = cut_short_scale(), suffix = " t")(c(0, 1500));
      # scale_cut = c(0, K = 1e3), accuracy = 0.1 on c(500, 1500);
      # label_currency(scale_cut = cut_short_scale(), accuracy = 0.1)(c(0, 1500, 2e6))
      assert Format.comma([0, 1500], scale_cut: Format.cut_short_scale(), suffix: " t") ==
               ["0 t", "2K t"]

      assert Format.comma([500, 1500], scale_cut: [{"", 0}, {"K", 1000}], accuracy: 0.1) ==
               ["500.0", "1.5K"]

      assert Format.currency([0, 1500, 2.0e6], scale_cut: Format.cut_short_scale(), accuracy: 0.1) ==
               ["$0.0", "$1.5K", "$2.0M"]
    end

    test "applies after scale:, and leaves zero at scale 1 with the zero step's suffix" do
      # label_percent(scale_cut = cut_short_scale())(c(0, 5, 10, 20)); c(0, 0.0125), where zero
      # at the percent's scale would give both labels a decimal; cut_time_scale(TRUE) on
      # c(0, 0.5, 30)
      assert Format.percent([0, 5, 10, 20], scale_cut: Format.cut_short_scale()) ==
               ["0%", "500%", "1K%", "2K%"]

      assert Format.percent([0, 0.0125], scale_cut: Format.cut_short_scale()) == ["0%", "1%"]
      # label_comma(scale_cut = cut_short_scale())(c(0, 0.5)): zero shares 0.5's scale of 1
      assert Format.comma([0, 0.5], scale_cut: Format.cut_short_scale()) == ["0.0", "0.5"]

      assert Format.comma([0, 0.5, 30], scale_cut: Format.cut_time_scale(space: true)) ==
               ["0 ", "500 ms", "30 s"]
    end

    test "pads each step's labels apart when untrimmed" do
      # label_comma(scale_cut = cut_short_scale(), trim = FALSE)(c(1, 1.5e6, 2e6, 2.5e6, 10e6))
      assert Format.comma([1, 1.5e6, 2.0e6, 2.5e6, 1.0e7],
               scale_cut: Format.cut_short_scale(),
               trim: false
             ) == ["1", " 1.5M", " 2.0M", " 2.5M", "10.0M"]
    end
  end

  describe "the steps" do
    test "are R's cut_short_scale() and cut_long_scale(), with and without spaces" do
      # cut_short_scale(); cut_short_scale(TRUE); cut_long_scale()
      assert Format.cut_short_scale() ==
               [{"", 0}, {"K", 1.0e3}, {"M", 1.0e6}, {"B", 1.0e9}, {"T", 1.0e12}]

      assert Format.cut_short_scale(space: true) ==
               [{" ", 0}, {" K", 1.0e3}, {" M", 1.0e6}, {" B", 1.0e9}, {" T", 1.0e12}]

      assert Format.cut_long_scale() ==
               [{"", 0}, {"K", 1.0e3}, {"M", 1.0e6}, {"B", 1.0e12}, {"T", 1.0e18}]

      assert Format.cut_long_scale(space: false) == Format.cut_long_scale()
    end

    test "are R's cut_si(), its thresholds R's 10^si_powers, its micro sign U+00B5" do
      # cut_si("g"), each threshold printed with sprintf("%.17g")
      assert Format.cut_si("g") == [
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
      assert Format.cut_time_scale(space: true) == [
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

  describe "a call Giggly.Format refuses" do
    test "names breaks that are not a list of numbers" do
      for breaks <- [[1, nil], 5] do
        error = assert_raise ArgumentError, fn -> Format.comma(breaks) end
        assert error.message =~ "Format.comma/2"
        assert error.message =~ inspect(breaks)
      end

      percent = assert_raise ArgumentError, fn -> Format.percent([1, nil]) end
      assert percent.message =~ "Format.percent/2"
      currency = assert_raise ArgumentError, fn -> Format.currency([1, nil]) end
      assert currency.message =~ "Format.currency/2"
    end

    test "names an option the formatter does not take, and the ones it does" do
      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Format.comma([1], largest_with_fractional: 10)
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
          assert_raise NimbleOptions.ValidationError, fn -> Format.percent([1], [option]) end

        {name, value} = option
        assert error.message =~ inspect(name)
        assert error.message =~ "got: #{inspect(value)}"
      end

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Format.currency([1], largest_with_fractional: "big")
        end

      assert error.message =~ ":largest_with_fractional"
      assert error.message =~ ~s(got: "big")
    end

    test "names steps without a zero, with a threshold twice, or not pairs" do
      no_zero =
        assert_raise NimbleOptions.ValidationError, fn ->
          Format.comma([1], scale_cut: [{"K", 1000}])
        end

      assert no_zero.message =~ "threshold 0"
      assert no_zero.message =~ inspect([{"K", 1000}])

      twice =
        assert_raise NimbleOptions.ValidationError, fn ->
          Format.comma([1], scale_cut: [{"", 0}, {"K", 1000}, {"J", 1000.0}])
        end

      assert twice.message =~ "twice"
      assert twice.message =~ ~s({"J", 1000.0})

      for steps <- [[], [{"", -1}], [{:k, 0}], [{"", 0}, {:k, 1000}], [{"", 0}, "K"], %{"" => 0}] do
        error =
          assert_raise NimbleOptions.ValidationError, fn ->
            Format.comma([1], scale_cut: steps)
          end

        assert error.message =~ "{suffix, threshold} pairs"
        assert error.message =~ inspect(steps)
      end
    end

    test "names a step set's option it does not take, and a unit that is not a string" do
      for options <- [[space: 1], [gap: true]] do
        error =
          assert_raise NimbleOptions.ValidationError, fn -> Format.cut_short_scale(options) end

        assert error.message =~ ":space"
      end

      error = assert_raise ArgumentError, fn -> Format.cut_si(:g) end
      assert error.message =~ "unit"
      assert error.message =~ ":g"
    end
  end
end
