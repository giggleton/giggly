defmodule Scales.Labels.FormatTest do
  use ExUnit.Case, async: true

  alias Scales.Labels.Format

  # Golden: every expected text below is R's own `format()`, from R 4.6.1 (the image
  # `giggly-r:ggplot2-4.0.3`), each from the call in the comment above it, untrimmed as R's
  # `format()` is unless `trim = TRUE` says. They move only if R's formatting does.

  # R's `format()` defaults: seven digits, untrimmed, either notation, R's marks.
  defp write(values, options \\ []) do
    settings =
      Map.merge(
        %{digits: 7, nsmall: 0, trim: false, notation: :auto, decimal_mark: ".", big_mark: ""},
        Map.new(options)
      )

    Format.write(values, settings)
  end

  describe "the notation" do
    test "is scientific where that is narrower than plain decimals, for every number" do
      # format(c(1e5, 2e5)); c(1e5, 123456); c(1e15, 1); c(1e22, 1e-22)
      assert write([1.0e5, 2.0e5]) == ["1e+05", "2e+05"]
      assert write([1.0e5, 123_456.0]) == ["100000", "123456"]
      assert write([1.0e15, 1.0]) == ["1e+15", "1e+00"]
      assert write([1.0e22, 1.0e-22]) == ["1e+22", "1e-22"]
    end

    test "is plain where the widths tie" do
      # format(123456789012); format(c(9.9999999, 1)): rounded to seven digits, 10
      assert write([123_456_789_012.0]) == ["123456789012"]
      assert write([9.9999999, 1.0]) == ["10", " 1"]
    end

    test "counts a negative's sign in both widths" do
      # format(c(-1e5, 1)): its sign makes plain decimals 7 wide to scientific notation's 6;
      # format(c(-0.5, 1.5e5)): the sign makes scientific notation 8 wide, plain decimals' width
      assert write([-1.0e5, 1.0]) == ["-1e+05", " 1e+00"]
      assert write([-0.5, 1.5e5]) == ["    -0.5", "150000.0"]
    end

    test "counts a number rounding carries past the digits it prints at the digits printed" do
      # format(c(99999999.4, 123.4567)): seven digits round 99999999.4 to 1e8, but it prints
      # eight whole digits, so plain decimals are 13 wide to scientific notation's 12
      assert write([99_999_999.4, 123.4567]) == ["1.000000e+08", "1.234567e+02"]
    end

    test "is scientific unless 100 characters narrower in plain decimals, where asked" do
      # format(c(0, 5e5, -1230), scientific = TRUE); c(0.5, 100), scientific = TRUE
      assert write([0.0, 5.0e5, -1.23e3], notation: :scientific) ==
               [" 0.00e+00", " 5.00e+05", "-1.23e+03"]

      assert write([0.5, 1.0e2], notation: :scientific) == ["5e-01", "1e+02"]
      # format(0, scientific = TRUE); 9.9999999; c(9.9999999, 1.5), a mantissa carried to 10
      assert write([0.0], notation: :scientific) == ["0e+00"]
      assert write([9.9999999], notation: :scientific) == ["1e+01"]
      assert write([9.9999999, 1.5], notation: :scientific) == ["1.0e+01", "1.5e+00"]
    end

    test "is plain unless more than 310 characters wider, where asked" do
      # format(c(1e5, 1), scientific = FALSE); 1e-5; 1e-110; c(1e-100, 1e214), 316 characters
      # to scientific notation's 6; c(1e-100, 1e215), 317; c(1.5e-157, 1e157), 317 to 8
      assert write([1.0e5, 1.0], notation: :fixed) == ["100000", "     1"]
      assert write([1.0e-5], notation: :fixed) == ["0.00001"]
      assert write([1.0e-110], notation: :fixed) == ["0." <> String.duplicate("0", 109) <> "1"]

      assert [plain, _large] = write([1.0e-100, 1.0e214], notation: :fixed)
      assert String.length(plain) == 316
      assert write([1.0e-100, 1.0e215], notation: :fixed) == ["1e-100", "1e+215"]

      assert [two_digits, _large] = write([1.5e-157, 1.0e157], notation: :fixed)
      assert String.length(two_digits) == 317
    end

    test "takes an exponent of three digits for the margin from either end's power" do
      # format(c(1e-215, 1e99), scientific = FALSE) and c(1e304, 1e-10): 316 characters each,
      # within the margin only of scientific notation 6 wide; c(1e304, 1e-11), 317
      for values <- [[1.0e-215, 1.0e99], [1.0e304, 1.0e-10]] do
        assert values
               |> write(notation: :fixed)
               |> Enum.map(&String.length/1) == [316, 316]
      end

      assert write([1.0e304, 1.0e-11], notation: :fixed) == ["1e+304", " 1e-11"]
    end

    test "writes an exponent in three digits for a group with a power past 99 either way" do
      # format(c(1e-100, 1)); c(1.5e200, 2)
      assert write([1.0e-100, 1.0]) == ["1e-100", " 1e+00"]
      assert write([1.5e200, 2.0]) == ["1.5e+200", " 2.0e+00"]
    end
  end

  describe "the digits" do
    test "are the most any number needs at seven significant digits, shared by all" do
      # format(c(0.0001, 0.00025)); c(0.1, 0.25, 1/3); c(1234567.1); c(-1e-20, 1)
      assert write([0.0001, 0.00025]) == ["0.00010", "0.00025"]
      assert write([0.1, 0.25, 0.3333333333333333]) == ["0.1000000", "0.2500000", "0.3333333"]
      assert write([1_234_567.1]) == ["1234567"]
      assert write([-1.0e-20, 1.0]) == ["-1e-20", " 1e+00"]
    end

    test "are counted at the significant digits given, from 1 to 22" do
      # format(c(2.5, 3.5), digits = 1); 9.5, digits = 1; 0.000099995, digits = 4;
      # c(1/3, 2/3), digits = 22; 0.1 + 0.2, digits = 17
      assert write([2.5, 3.5], digits: 1) == ["2", "4"]
      assert write([9.5], digits: 1) == ["10"]
      assert write([9.9995e-5], digits: 4) == ["9.999e-05"]

      assert write([0.3333333333333333, 0.6666666666666666], digits: 22) ==
               ["0.3333333333333333148296", "0.6666666666666666296592"]

      assert write([0.30000000000000004], digits: 17) == ["0.30000000000000004"]
    end

    test "round each number's exact value half to even" do
      # format(0.125, digits = 2); 0.375, digits = 2
      assert write([0.125], digits: 2) == ["0.12"]
      assert write([0.375], digits: 2) == ["0.38"]
    end

    test "are at least nsmall in plain decimals, and nsmall leaves scientific notation alone" do
      # format(c(1, 10, 100), nsmall = 2); c(1e-5, 1e5, 123), nsmall = 3
      assert write([1.0, 1.0e1, 1.0e2], nsmall: 2) == ["  1.00", " 10.00", "100.00"]
      assert write([1.0e-5, 1.0e5, 123.0], nsmall: 3) == ["1.00e-05", "1.00e+05", "1.23e+02"]
    end

    test "reach a subnormal number's" do
      # format(5e-324)
      assert write([5.0e-324]) == ["4.940656e-324"]
    end

    test "are counted from the power of ten below a number its log10 rounds up to the next" do
      # format(1e-20, digits = 22): the double 1e-20 is just below 10^-20, where log10 gives -20
      assert write([1.0e-20], digits: 22) == ["9.999999999999999451533e-21"]
    end
  end

  describe "the padding" do
    test "is to the widest, its sign counted" do
      # format(c(-1.5, 2)); c(-123456, 0.5); c(-0, 1.5), a negative zero written 0
      assert write([-1.5, 2.0]) == ["-1.5", " 2.0"]
      assert write([-123_456.0, 0.5]) == ["-123456.0", "      0.5"]
      assert write([-0.0, 1.5]) == ["0.0", "1.5"]
    end

    test "is to the width of the digits printed when rounding carries a number past them" do
      # format(c(99999999.9, 1)), and with scientific = FALSE: seven digits round it to 1e8,
      # which it reaches printed
      assert write([99_999_999.9, 1.0]) == ["1e+08", "1e+00"]
      assert write([99_999_999.9, 1.0], notation: :fixed) == ["100000000", "        1"]
    end

    test "is left out when trimmed" do
      # format(c(-1.5, 2), trim = TRUE); c(1, NA, Inf), trim = TRUE
      assert write([-1.5, 2.0], trim: true) == ["-1.5", "2.0"]
      assert write([1.0, nil, :infinity], trim: true) == ["1", "NA", "Inf"]
    end
  end

  describe "no numbers" do
    test "are written as no texts" do
      # format(numeric())
      assert write([]) == []
    end
  end

  describe "a missing or non-finite value" do
    test "is NA, NaN, Inf or -Inf, its width the least its group is padded to" do
      # format(c(1, NA, Inf, NaN, -Inf)); c(NA_real_, NA_real_); c(Inf, -Inf, NaN)
      assert write([1.0, nil, :infinity, :nan, :neg_infinity]) ==
               ["   1", "  NA", " Inf", " NaN", "-Inf"]

      assert write([nil, nil]) == ["NA", "NA"]
      assert write([:infinity, :neg_infinity, :nan]) == [" Inf", "-Inf", " NaN"]
    end

    test "takes no marks" do
      # format(c(1.5, NA), nsmall = 2, decimal.mark = ",")
      assert write([1.5, nil], nsmall: 2, decimal_mark: ",") == ["1,50", "  NA"]
    end
  end

  describe "the marks" do
    test "go before the decimals in either notation, a wide one lengthening every number" do
      # format(c(1.5e10, 1), scientific = TRUE, decimal.mark = "::"); c(1.5, 10),
      # decimal.mark = "::"
      assert write([1.5e10, 1.0], notation: :scientific, decimal_mark: "::") ==
               ["1::5e+10", "1::0e+00"]

      assert write([1.5, 10.0], decimal_mark: "::") == [" 1::5", "10::0"]
    end

    test "go between each three whole digits, after a sign and its padding" do
      # format(c(-1234567, 1), big.mark = ","); -123456; c(-123456, 1e7)
      assert write([-1_234_567.0, 1.0], big_mark: ",") == ["-1,234,567", "         1"]
      assert write([-123_456.0], big_mark: ",") == ["-123,456"]
      assert write([-123_456.0, 1.0e7], big_mark: ",") == ["  -123,456", "10,000,000"]
    end
  end
end
