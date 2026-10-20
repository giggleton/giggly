defmodule Giggly.DataFrameTest do
  use ExUnit.Case, async: true

  alias Giggly.DataFrame

  doctest Giggly.DataFrame

  describe "from_table/1" do
    test "a map of columns is read with its names as strings and a lazy column into a list" do
      frame = DataFrame.from_table(%{wt: [2.62, 2.875, 2.32], id: 1..3})

      assert DataFrame.names(frame) == ["id", "wt"]
      assert DataFrame.pull(frame, "id") === [1, 2, 3]
    end

    test "a list that is not a table is refused, naming what was given" do
      error = assert_raise ArgumentError, fn -> DataFrame.from_table([1, 2, 3]) end

      assert error.message =~ "[1, 2, 3]"
    end

    test "columns of different lengths are refused rather than misaligning the rows" do
      error =
        assert_raise ArgumentError, fn ->
          DataFrame.from_table(%{"wt" => [2.62, 2.875], "mpg" => [21.0]})
        end

      assert error.message =~ ~s("mpg")
    end

    test "two names that become the same string are refused rather than one column winning" do
      error =
        assert_raise ArgumentError, fn ->
          DataFrame.from_table(%{:wt => [2.62], "wt" => [2.875]})
        end

      assert error.message =~ ":wt"
    end
  end

  describe "new/1" do
    test "columns keep the order they are given in" do
      frame = DataFrame.new(x: [1.5, 2.0], color: ["a", "b"])

      assert DataFrame.names(frame) == [:x, :color]
    end

    test "a frame of no columns has no rows" do
      frame = DataFrame.new([])

      assert DataFrame.row_count(frame) === 0
    end

    test "a column mixing two types is refused, naming the column and two values that disagree" do
      error = assert_raise ArgumentError, fn -> DataFrame.new(mpg: [21.0, nil, "n/a"]) end

      # The column is named as the column: swapped with a value, every datum would still appear.
      assert error.message =~ "column :mpg "
      assert error.message =~ "21.0"
      assert error.message =~ ~s("n/a")
    end

    test "each column's type is worked out by Explorer's rules for a series built from a list" do
      frame =
        DataFrame.new(
          count: [1, nil],
          mpg: [21, 22.8],
          ratio: [:nan, 2],
          limit: [:infinity, :neg_infinity],
          model: ["Mazda RX4", "Datsun 710"],
          manual: [true, false],
          species: [:setosa, :virginica],
          day: [~D[2026-10-12], nil],
          clock: [~T[09:30:00], ~T[17:00:00]],
          logged: [~N[2026-10-12 09:30:00], ~N[2026-10-12 17:00:00]],
          stamped: [~U[2026-10-12 09:30:00Z], ~U[2026-10-12 17:00:00Z]],
          missing: [nil, nil],
          payload: [%{id: 1}, [2]]
        )

      assert DataFrame.dtypes(frame) == %{
               count: :integer,
               mpg: :float,
               ratio: :float,
               limit: :float,
               model: :string,
               manual: :boolean,
               species: :atom,
               day: :date,
               clock: :time,
               logged: :naive_datetime,
               stamped: :datetime,
               missing: :null,
               payload: :term
             }
    end

    # Explorer's `Series.from_list([1, 2.0])` is `f64 [1.0, 2.0]`: a mix of integers and floats is
    # cast to floats.
    test "an integer among floats becomes a float, and a column of integers keeps them" do
      frame = DataFrame.new(mixed: [4, 4.0, nil, :nan], whole: [4, 6, nil, 8])

      assert {DataFrame.pull(frame, :mixed), DataFrame.pull(frame, :whole)} ===
               {[4.0, 4.0, nil, :nan], [4, 6, nil, 8]}
    end

    test "a name given twice is refused rather than the later column replacing the earlier" do
      assert_raise FunctionClauseError, fn ->
        DataFrame.new(x: [1, 2], x: [3, 4])
      end
    end

    test "columns of different lengths are refused" do
      assert_raise FunctionClauseError, fn ->
        DataFrame.new(x: [1, 2], y: [3])
      end
    end
  end

  describe "new/1, a category" do
    test "a column declared a category is typed :category, its values typed and cast as any" do
      frame = DataFrame.new([{:cyl, [4, 4.0, nil, 6], :category}, {:wt, [2.6, 2.9, 3.2, 3.4]}])

      assert {DataFrame.dtypes(frame), DataFrame.pull(frame, :cyl)} ===
               {%{cyl: :category, wt: :float}, [4.0, 4.0, nil, 6.0]}
    end

    test "a category keeps its type through select/2, split/2 and slice/2" do
      frame = DataFrame.new([{:cyl, [4, 6], :category}, {:panel, [1, 2]}])
      selected = DataFrame.select(frame, [{:x, :cyl}])
      sliced = DataFrame.slice(frame, [1])

      part =
        frame
        |> DataFrame.split(:panel)
        |> Map.fetch!(1)

      assert {DataFrame.dtypes(selected), DataFrame.dtypes(part)[:cyl],
              DataFrame.dtypes(sliced)[:cyl]} === {%{x: :category}, :category, :category}
    end

    test "a category of values with no type of their own is refused, naming the column" do
      error =
        assert_raise ArgumentError, fn ->
          DataFrame.new([{:payload, [nil, %{id: 1}], :category}])
        end

      assert error.message =~ ":payload"
      assert error.message =~ "%{id: 1}"
    end
  end

  describe "select/2" do
    test "columns are chosen and renamed, one may be chosen twice, and each keeps its type" do
      frame = DataFrame.from_table(%{"wt" => [2.62, 2.875], "cyl" => ["6", "4"]})
      selected = DataFrame.select(frame, x: "wt", color: "cyl", label: "wt")

      assert DataFrame.names(selected) == [:x, :color, :label]
      assert DataFrame.dtypes(selected) == %{x: :float, color: :string, label: :float}
      assert DataFrame.pull(selected, :label) === [2.62, 2.875]
    end

    test "the rows are kept even when no column is" do
      frame = DataFrame.from_table(%{"wt" => [2.62, 2.875], "cyl" => ["6", "4"]})

      selected = DataFrame.select(frame, [])

      assert DataFrame.row_count(selected) === 2
    end
  end

  describe "pull/2" do
    test "a column the frame does not have is refused rather than read as nil" do
      frame = DataFrame.new(x: [1, 2])

      assert_raise FunctionClauseError, fn ->
        DataFrame.pull(frame, :y)
      end
    end
  end

  describe "put/3" do
    test "a new column is added after the last, and a replaced one keeps its place with a new type" do
      frame =
        [x: ["a", "b"]]
        |> DataFrame.new()
        |> DataFrame.put(:group, [1, 1])
        |> DataFrame.put(:x, [1.0, 2.0])

      assert DataFrame.names(frame) == [:x, :group]
      assert DataFrame.dtypes(frame) == %{x: :float, group: :integer}
      assert DataFrame.pull(frame, :x) === [1.0, 2.0]
    end

    test "replacing a column with the wrong number of values is refused" do
      frame = DataFrame.new(x: [1, 2])

      assert_raise FunctionClauseError, fn ->
        DataFrame.put(frame, :x, [1, 2, 3])
      end
    end
  end

  describe "put/4" do
    test "a column put as a category is declared one, added or replacing in its place" do
      frame =
        [x: [1, 2]]
        |> DataFrame.new()
        |> DataFrame.put(:fill, [4, 6.0], :category)
        |> DataFrame.put(:x, ["a", "b"], :category)

      assert DataFrame.names(frame) == [:x, :fill]
      assert DataFrame.dtypes(frame) == %{x: :category, fill: :category}
      assert DataFrame.pull(frame, :fill) === [4.0, 6.0]
    end

    test "a category of values with no type of their own is refused" do
      frame = DataFrame.new(x: [1])

      assert_raise ArgumentError, ~r/declared a category/, fn ->
        DataFrame.put(frame, :fill, [%{}], :category)
      end
    end
  end

  describe "split/2" do
    test "each value's rows keep their order, every column and each column's type" do
      frame = DataFrame.new(x: [1.0, 2.0, 3.0, 4.0], panel: [2, 1, 2, 1])

      parts = DataFrame.split(frame, :panel)

      assert Map.keys(parts) == [1, 2]
      assert DataFrame.pull(parts[1], :x) === [2.0, 4.0]
      assert DataFrame.pull(parts[2], :x) === [1.0, 3.0]
      assert DataFrame.names(parts[2]) == [:x, :panel]
      assert DataFrame.row_count(parts[2]) == 2
    end

    test "a part keeps its column's type even when its own values would read as another" do
      frame = DataFrame.new(x: [1, 2.5], panel: [1, 2])

      assert DataFrame.dtypes(DataFrame.split(frame, :panel)[1]) == %{x: :float, panel: :integer}
    end
  end

  describe "slice/2" do
    test "the rows at the indices are taken in that order, repeated or left out, each column whole" do
      frame = DataFrame.new(x: [1.0, 2.0, 3.0], group: [1, 2, 3])

      sliced = DataFrame.slice(frame, [2, 0, 0])

      assert DataFrame.pull(sliced, :x) === [3.0, 1.0, 1.0]
      assert DataFrame.pull(sliced, :group) === [3, 1, 1]
      assert DataFrame.names(sliced) == [:x, :group]
      assert DataFrame.row_count(sliced) == 3
    end

    test "a slice keeps each column's type even when its own values would read as another" do
      frame = DataFrame.new(x: [1, 2.5])

      sliced = DataFrame.slice(frame, [0])

      assert DataFrame.dtypes(sliced) == %{x: :float}
    end

    test "no indices leave no rows" do
      sliced =
        [x: [1.0]]
        |> DataFrame.new()
        |> DataFrame.slice([])

      assert DataFrame.row_count(sliced) == 0
    end
  end

  describe "summarise/3" do
    test "one row per combination the rows hold, sorted by the columns in order, missing last" do
      frame =
        DataFrame.new([
          {:panel, [2, 1, 1, 1, 1]},
          {:color, ["b", nil, "b", "a", "b"]},
          {:weight, [1.0, 2.0, 3.0, 4.0, 5.0]}
        ])

      summarised = DataFrame.summarise(frame, [:panel, :color], n: {:sum, :weight})

      assert DataFrame.names(summarised) == [:panel, :color, :n]
      assert DataFrame.pull(summarised, :panel) === [1, 1, 1, 2]
      assert DataFrame.pull(summarised, :color) === ["a", "b", nil, "b"]
      assert DataFrame.pull(summarised, :n) === [4.0, 8.0, 2.0, 1.0]
    end

    test "each column grouped by keeps its type, a category's included, and a sum is a float" do
      frame =
        DataFrame.new([
          {:x, [4, 6, 4], :category},
          {:y, [1, 2, 1]},
          {:weight, [1, 2, 3]}
        ])

      summarised = DataFrame.summarise(frame, [:x, :y], n: {:sum, :weight})

      assert DataFrame.dtypes(summarised) == %{x: :category, y: :integer, n: :float}
      assert DataFrame.pull(summarised, :n) === [4.0, 2.0]
    end

    # Golden: R 4.6.1's sum(c(0.1, 0.2, 0.3)) is 0.59999999999999998, added in extended
    # precision, and rowsum(c(0.1, 0.2, 0.3), rep(1, 3)) is 0.60000000000000009, added in doubles in
    # row order, printed to 17 significant digits. It moves with nothing but how R adds.
    test "a sum is compensated as R's sum() adds, or plain as R's rowsum() does" do
      frame = DataFrame.new(group: [1, 1, 1], weight: [0.1, 0.2, 0.3])

      compensated = DataFrame.summarise(frame, [:group], n: {:sum, :weight})

      plain =
        DataFrame.summarise(frame, [:group], n: {:sum, :weight, summation: :plain})

      assert DataFrame.pull(compensated, :n) === [0.59999999999999998]
      assert DataFrame.pull(plain, :n) === [0.60000000000000009]
    end

    test "a missing or non-finite value makes its group's sum missing, or is skipped" do
      frame =
        DataFrame.new(
          group: [1, 1, 2, 2, 3, 4],
          weight: [1.0, nil, 2.0, :nan, :infinity, 5.0]
        )

      propagated = DataFrame.summarise(frame, [:group], n: {:sum, :weight})

      skipped =
        DataFrame.summarise(frame, [:group], n: {:sum, :weight, missing: :skip})

      assert DataFrame.pull(propagated, :n) === [nil, nil, nil, 5.0]
      assert DataFrame.pull(skipped, :n) === [1.0, 2.0, 0.0, 5.0]
    end

    test "a frame of no rows summarises into no rows, its columns named" do
      frame = DataFrame.new(group: [], weight: [])

      summarised = DataFrame.summarise(frame, [:group], n: {:sum, :weight})

      assert DataFrame.row_count(summarised) == 0
      assert DataFrame.names(summarised) == [:group, :n]
    end

    test "a sum of a column that is not numbers is refused, naming the column and its type" do
      frame = DataFrame.new(group: [1], weight: ["heavy"])

      error =
        assert_raise ArgumentError, fn ->
          DataFrame.summarise(frame, [:group], n: {:sum, :weight})
        end

      assert error.message =~ ":weight"
      assert error.message =~ ":string"
    end

    test "an option not listed, or a value it does not take, is refused" do
      frame = DataFrame.new(group: [1], weight: [1.0])

      assert_raise ArgumentError, fn ->
        DataFrame.summarise(frame, [:group], n: {:sum, :weight, rounding: :plain})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.summarise(frame, [:group], n: {:sum, :weight, summation: :kahan})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.summarise(frame, [:group], n: {:sum, :weight, missing: :zero})
      end
    end

    test "no column to group by, or a sum named as one, is refused" do
      frame = DataFrame.new(group: [1], weight: [1.0])
      # Built as the test runs, since the type checker warns of a literal `[]` it knows fails.
      no_columns = Enum.drop([:group], 1)

      assert_raise FunctionClauseError, fn ->
        DataFrame.summarise(frame, no_columns, n: {:sum, :weight})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.summarise(frame, [:group], group: {:sum, :weight})
      end
    end
  end
end
