defmodule Scales.MinorBreaksTest do
  use ExUnit.Case, async: true

  alias Scales.MinorBreaks

  # The reversed example is R 4.6.1's `regular_minor_breaks(reverse = TRUE)(c(30, 20, 10), c(5,
  # 35), 2)`, scales 1.4.0; the others are R's `minor_breaks_n(3)(c(0.5, 9.5), c(2, 4, 6, 8))`,
  # `minor_breaks_width(2, 0.5)` and `minor_breaks_width("1 week", 0)` on those limits and breaks
  # and on `c(2026-01-01, 2026-01-25)` with the break 2026-01-15, `minor_breaks_log(5)(c(1, 100))`
  # and `minor_breaks_log(10, 1)(c(-10, 10))`. Every figure below is R's own output.
  doctest Scales.MinorBreaks

  describe "regular/3" do
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

    test "reverse is true or false, and anything else is refused" do
      assert_raise NimbleOptions.ValidationError, fn ->
        MinorBreaks.regular([0.0, 5.0], {0.0, 5.0}, reverse: :yes)
      end
    end
  end

  describe "n/3" do
    test "each gap is laid from the limit or break it starts at, in the order given" do
      # R's `minor_breaks_n(3)(c(0.5, 9.5), c(6, 2, 8))`: 6 to 2, 2 to 8.
      assert MinorBreaks.n({0.5, 9.5}, [6.0, 2.0, 8.0], 3) ===
               [0.5, 3.25, 6.0, 4.0, 2.0, 5.0, 8.0, 8.75, 9.5]
    end

    test "limits and breaks high to low are laid high to low" do
      assert MinorBreaks.n({9.5, 0.5}, [8.0, 6.0, 4.0, 2.0], 3) ===
               [9.5, 8.75, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.25, 0.5]
    end

    test "one break makes two gaps" do
      assert MinorBreaks.n({0.5, 9.5}, [2.0], 3) === [0.5, 1.25, 2.0, 5.75, 9.5]
    end

    test "one to a gap is its start, and none is nothing" do
      assert MinorBreaks.n({0.5, 9.5}, [2.0, 4.0, 6.0, 8.0], 1) === [0.5, 2.0, 4.0, 6.0, 8.0]
      assert MinorBreaks.n({0.5, 9.5}, [2.0, 4.0, 6.0, 8.0], 0) === []
    end

    test "0 and -0 are one value, the first laid kept, as R's unique() keeps it" do
      assert MinorBreaks.n({-0.0, 0.003}, [0.0, 0.001, 0.002, 0.003], 1) ===
               [-0.0, 0.001, 0.002, 0.003]
    end

    test "integers are laid as floats" do
      assert MinorBreaks.n({0, 4}, [2], 3) === [0.0, 1.0, 2.0, 3.0, 4.0]
    end

    test "dates are refused, since a fraction of a day is no date" do
      # Built as the test runs: a literal the guard refuses fails the type checker.
      limits = List.to_tuple([~D[2026-01-01], ~D[2026-01-20]])

      assert_raise FunctionClauseError, fn -> MinorBreaks.n(limits, [~D[2026-01-05]], 4) end

      mixed = List.to_tuple([0.0, ~D[2026-01-20]])
      assert_raise FunctionClauseError, fn -> MinorBreaks.n(mixed, [2.0], 4) end

      error =
        assert_raise ArgumentError, ~r/expected breaks that are numbers/, fn ->
          MinorBreaks.n({0.0, 20.0}, [2.0, ~D[2026-01-05]], 4)
        end

      assert error.message =~ "~D[2026-01-05]"
    end

    test "no breaks, or a count below 0 or not whole, are refused by n/3 itself" do
      for {breaks, count} <- [{[], 3}, {[2.0], -1}, {[2.0], 2.5}] do
        error =
          assert_raise FunctionClauseError, fn -> MinorBreaks.n({0.5, 9.5}, breaks, count) end

        assert {error.module, error.function} == {MinorBreaks, :n}
      end
    end

    test "values too small to move 1 when added to it are still told apart" do
      # R's `minor_breaks_n(3)(c(0, 1e-20), c(5e-21))`.
      assert MinorBreaks.n({0.0, 1.0e-20}, [5.0e-21], 3) ===
               [
                 0.0,
                 2.4999999999999999e-21,
                 4.9999999999999997e-21,
                 7.4999999999999992e-21,
                 9.9999999999999995e-21
               ]
    end
  end

  describe "width/4" do
    test "the offset is 0 unless given" do
      assert MinorBreaks.width({0.5, 9.5}, [2.0, 4.0, 6.0, 8.0], 1) ===
               [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    end

    test "limits and breaks high to low are laid in that order, each gap low to high" do
      assert MinorBreaks.width({9.5, 0.5}, [8.0, 6.0, 4.0, 2.0], 2) ===
               [8.0, 10.0, 6.0, 4.0, 2.0, 0.0]
    end

    test "a gap of no width gives half a width either side of it, as R's fullseq() does" do
      # R's `minor_breaks_width(1, 0)(c(2, 9.5), c(2, 4, 6, 8))`.
      assert MinorBreaks.width({2.0, 9.5}, [2.0, 4.0, 6.0, 8.0], 1) ===
               [1.5, 2.5, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
    end

    test "options reach each gap's breaks, a zone's date-times kept unsorted as R keeps them" do
      # R's `minor_breaks_width("2 hours", 0)` in New York, 20:00 on 7 March 2026 to 06:00, the
      # break at 01:00, an hour before the clocks go forward.
      walls =
        {new_york(~N[2026-03-07 20:00:00]), new_york(~N[2026-03-08 06:00:00])}
        |> MinorBreaks.width([new_york(~N[2026-03-08 01:00:00])], [hour: 2],
          time_zone_database: Tz.TimeZoneDatabase
        )
        |> Enum.map(fn datetime -> {DateTime.to_naive(datetime), datetime.zone_abbr} end)

      assert walls == [
               {~N[2026-03-07 20:00:00], "EST"},
               {~N[2026-03-07 22:00:00], "EST"},
               {~N[2026-03-08 00:00:00], "EST"},
               {~N[2026-03-08 03:00:00], "EDT"},
               {~N[2026-03-08 01:00:00], "EST"},
               {~N[2026-03-08 04:00:00], "EDT"},
               {~N[2026-03-08 06:00:00], "EDT"},
               {~N[2026-03-08 08:00:00], "EDT"}
             ]
    end

    test "no breaks are refused" do
      # Built as the test runs: a literal the guard refuses fails the type checker.
      breaks = Enum.drop([2.0], 1)
      assert_raise FunctionClauseError, fn -> MinorBreaks.width({0.5, 9.5}, breaks, 1) end
    end
  end

  describe "log/2" do
    test "every multiple comes after the powers and their fives, each power's in turn" do
      assert MinorBreaks.log({1.0, 100.0}, detail: 1) === [
               0.1,
               1.0,
               10.0,
               100.0,
               1000.0,
               0.5,
               5.0,
               50.0,
               500.0,
               5000.0,
               0.2,
               0.30000000000000004,
               0.4,
               0.6000000000000001,
               0.7000000000000001,
               0.8,
               0.9,
               2.0,
               3.0,
               4.0,
               6.0,
               7.0,
               8.0,
               9.0,
               20.0,
               30.0,
               40.0,
               60.0,
               70.0,
               80.0,
               90.0,
               200.0,
               300.0,
               400.0,
               600.0,
               700.0,
               800.0,
               900.0,
               2000.0,
               3000.0,
               4000.0,
               6000.0,
               7000.0,
               8000.0,
               9000.0
             ]
    end

    test "the detail is chosen by the powers spanned: 1 over 8, 5 over 9 to 15, 10 over more" do
      # R's `minor_breaks_log()` on 1 and each high limit: 81 values of detail 1, 20 and 32 of
      # detail 5, 17 of detail 10.
      for {high, count} <- [{1.0e6, 81}, {1.5e6, 20}, {1.0e13, 32}, {1.5e13, 17}] do
        assert length(MinorBreaks.log({1.0, high})) == count
      end
    end

    test "the powers spanned that choose the detail start from ten times smallest:" do
      # R's `minor_breaks_log(smallest = 1)(c(-1e7, 1e7))`: 1e0 to 1e8, 8 powers, detail 1.
      breaks = MinorBreaks.log({-1.0e7, 1.0e7}, smallest: 1)
      assert Enum.count(breaks) == 163
    end

    test "a high limit of 0 reaches 0, however the limits are ordered" do
      # R's `minor_breaks_log(5)(c(5, 0))` is its `c(0, 5)`'s, pinned above.
      assert MinorBreaks.log({5.0, 0.0}, detail: 5) === MinorBreaks.log({0.0, 5.0}, detail: 5)
    end

    test "limits high to low span the same powers" do
      assert MinorBreaks.log({1000.0, 1.0}, detail: 10) ===
               [0.1, 1.0, 10.0, 100.0, 1000.0, 10_000.0]
    end

    test "limits reaching 0 or below give the powers either side of 0, from 0.1 up" do
      assert MinorBreaks.log({-1000.0, -10.0}, detail: 10) === [
               0.1,
               1.0,
               10.0,
               100.0,
               1000.0,
               10_000.0,
               -0.1,
               -1.0,
               -10.0,
               -100.0,
               -1000.0,
               -10_000.0,
               0.0
             ]
    end

    test "a limit of 0 gives the powers either side of it, then the fives" do
      assert MinorBreaks.log({0.0, 5.0}, detail: 5) === [
               0.1,
               1.0,
               10.0,
               100.0,
               -0.1,
               -1.0,
               -10.0,
               -100.0,
               0.0,
               0.5,
               5.0,
               50.0,
               500.0,
               -0.5,
               -5.0,
               -50.0,
               -500.0
             ]
    end

    test "limits smaller than 1 keep values from a tenth of the larger's size" do
      assert MinorBreaks.log({-0.2, 0.1}, detail: 5) === [
               0.1,
               1.0,
               10.0,
               -0.1,
               -1.0,
               -10.0,
               0.0,
               0.05,
               0.5,
               5.0,
               50.0,
               -0.05,
               -0.5,
               -5.0,
               -50.0
             ]
    end

    test "smallest: says where the values either side of 0 start" do
      assert MinorBreaks.log({-2000.0, 10.0}, detail: 5, smallest: 3) === [
               10.0,
               100.0,
               1000.0,
               10_000.0,
               100_000.0,
               -10.0,
               -100.0,
               -1000.0,
               -10_000.0,
               -100_000.0,
               0.0,
               5.0,
               50.0,
               500.0,
               5000.0,
               50_000.0,
               500_000.0,
               -5.0,
               -50.0,
               -500.0,
               -5000.0,
               -50_000.0,
               -500_000.0
             ]
    end

    test "limits both 0 are refused, where R fails" do
      assert_raise ArgumentError, ~r/not both 0/, fn -> MinorBreaks.log({0.0, 0.0}) end
    end

    test "smallest: 1.0e-100 is taken, as R takes it" do
      # R's `minor_breaks_log(10, 1e-100)(c(-1e-99, 1e-99))`.
      assert MinorBreaks.log({-1.0e-99, 1.0e-99}, detail: 10, smallest: 1.0e-100) ===
               [
                 1.0e-100,
                 1.0e-99,
                 9.9999999999999994e-99,
                 -1.0e-100,
                 -1.0e-99,
                 -9.9999999999999994e-99,
                 0.0
               ]
    end

    test "a detail other than 1, 5 or 10, or a smallest below 1.0e-100, is refused" do
      for options <- [[detail: 2], [smallest: 1.0e-101], [smallest: 0], [smallest: :infinity]] do
        assert_raise NimbleOptions.ValidationError, fn ->
          MinorBreaks.log({1.0, 10.0}, options)
        end
      end

      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          MinorBreaks.log({1.0, 10.0}, smallest: 1.0e-101)
        end

      assert Exception.message(error) =~ "1.0e-101"
    end

    test "limits that are not numbers are refused" do
      # Built as the test runs: a literal the guard refuses fails the type checker.
      limits = List.to_tuple([:neg_infinity, 10.0])
      assert_raise FunctionClauseError, fn -> MinorBreaks.log(limits) end
    end
  end

  defp new_york(naive), do: DateTime.from_naive!(naive, "America/New_York", Tz.TimeZoneDatabase)
end
