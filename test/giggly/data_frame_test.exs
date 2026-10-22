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
          payload: [%{id: 1}, {2}]
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

  describe "new/1, lists" do
    # Explorer 0.13.0's `Series.from_list/1` types `[[1, 2.0], [3]]` `{:list, {:f, 64}}` holding
    # `[[1.0, 2.0], [3.0]]`, `[[], []]` `{:list, :null}`, `[[1.0, nil], nil]` keeping both nils, and
    # `[[[1.0]], [[]]]` `{:list, {:list, {:f, 64}}}`.
    test "a column of lists is a list of the type its lists' values have together" do
      frame =
        DataFrame.new(
          mixed: [[1, 2.0], [3]],
          empty: [[], []],
          missing: [[1.0, nil], nil],
          nested: [[[1]], [[]]],
          labels: [["a"], []]
        )

      assert DataFrame.dtypes(frame) == %{
               mixed: {:list, :float},
               empty: {:list, :null},
               missing: {:list, :float},
               nested: {:list, {:list, :integer}},
               labels: {:list, :string}
             }

      assert {DataFrame.pull(frame, :mixed), DataFrame.pull(frame, :missing)} ===
               {[[1.0, 2.0], [3.0]], [[1.0, nil], nil]}
    end

    # Explorer 0.13.0 refuses `[[1.0, "a"]]` and `[[1.0], ["a"]]`: "the value "a" does not match the
    # inferred dtype {:f, 64}".
    test "lists whose values mix two types are refused, within a list or across them" do
      within =
        assert_raise ArgumentError, fn -> DataFrame.new(tags: [[1.0, "a"]]) end

      across =
        assert_raise ArgumentError, fn -> DataFrame.new(tags: [[1.0], ["a"]]) end

      assert within.message =~ ~s{:tags holds values of more than one type (1.0 and "a")}
      assert across.message =~ ~s{:tags holds values of more than one type ([1.0] and ["a"])}
    end

    test "a list among values that are not lists is refused" do
      assert_raise ArgumentError, fn -> DataFrame.new(tags: [[1.0], 2.0]) end
    end

    test "a category holds no lists" do
      error =
        assert_raise ArgumentError, fn ->
          DataFrame.new([{:tags, [nil, [1]], :category}])
        end

      assert error.message =~ ":tags"
      assert error.message =~ "[1]"
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

  describe "filter/2" do
    test "the rows where the expression is true are kept in order, each column keeping its type" do
      frame =
        DataFrame.new([
          {:x, [1.0, nil, :infinity, 2.0, :nan, :neg_infinity]},
          {:label, [4, 6, 8, 4, 6, 8], :category}
        ])

      filtered = DataFrame.filter(frame, {:is_finite, [:x]})

      assert DataFrame.pull(filtered, :x) === [1.0, 2.0]
      assert DataFrame.pull(filtered, :label) === [4, 4]
      assert DataFrame.dtypes(filtered) == %{x: :float, label: :category}
    end

    test "a column of booleans filters as itself, a row where it is false or missing left out" do
      frame = DataFrame.new(keep: [false, true, nil, true], y: [1, 2, 3, 4])

      filtered = DataFrame.filter(frame, :keep)

      assert DataFrame.pull(filtered, :y) === [2, 4]
    end

    test "a missing constant keeps no row" do
      frame = DataFrame.new(y: [1, 2])

      filtered = DataFrame.filter(frame, {:constant, nil})

      assert DataFrame.row_count(filtered) == 0
    end

    test "an expression that is not a boolean one is refused" do
      frame = DataFrame.new(x: [1.0])

      assert_raise FunctionClauseError, fn -> DataFrame.filter(frame, :x) end
    end
  end

  describe "mutate/2" do
    test "a constant fills every row, typed as a column of it, each added after the last" do
      frame = DataFrame.new(x: [1.0, 2.0])

      mutated =
        DataFrame.mutate(frame,
          weight: 1,
          share: 0.5,
          kept: true,
          day: ~D[2026-10-21],
          time: ~T[12:00:00],
          naive: ~N[2026-10-21 12:00:00],
          instant: ~U[2026-10-21 12:00:00Z],
          kind: {:constant, "smooth"},
          gap: {:constant, nil}
        )

      assert DataFrame.names(mutated) ==
               [:x, :weight, :share, :kept, :day, :time, :naive, :instant, :kind, :gap]

      assert DataFrame.dtypes(mutated) == %{
               x: :float,
               weight: :integer,
               share: :float,
               kept: :boolean,
               day: :date,
               time: :time,
               naive: :naive_datetime,
               instant: :datetime,
               kind: :string,
               gap: :null
             }

      assert DataFrame.pull(mutated, :kind) === ["smooth", "smooth"]
      assert DataFrame.pull(mutated, :day) === [~D[2026-10-21], ~D[2026-10-21]]
    end

    test "a column named alone is copied with its type, a replaced column keeping its place" do
      frame = DataFrame.new([{:x, [1.0, 2.0]}, {"cyl", [4, 6], :category}, {:y, [3, 4]}])

      mutated = DataFrame.mutate(frame, x: "cyl", copy: :y)

      assert DataFrame.names(mutated) == [:x, "cyl", :y, :copy]
      assert DataFrame.pull(mutated, :x) === [4, 6]

      assert DataFrame.dtypes(mutated) == %{
               :x => :category,
               "cyl" => :category,
               :y => :integer,
               :copy => :integer
             }
    end

    test "every expression reads the frame as given, never a column the same call computes" do
      frame = DataFrame.new(y: [5.0])

      mutated = DataFrame.mutate(frame, y: 2.0, z: :y)

      assert {DataFrame.pull(mutated, :y), DataFrame.pull(mutated, :z)} === {[2.0], [5.0]}
    end

    test "is_finite is whether each number is finite, missing where the number is" do
      frame =
        DataFrame.new(
          x: [1.0, nil, :nan, :infinity, :neg_infinity],
          n: [3, nil, 4, 5, 6]
        )

      mutated =
        DataFrame.mutate(frame, finite: {:is_finite, [:x]}, whole: {:is_finite, [:n]})

      assert DataFrame.pull(mutated, :finite) === [true, nil, false, false, false]
      assert DataFrame.pull(mutated, :whole) === [true, nil, true, true, true]
      assert DataFrame.dtypes(mutated).finite == :boolean
    end

    test "and is false where either side is, true where both are, and otherwise missing" do
      frame =
        DataFrame.new(
          left: [true, true, false, false, nil, true, nil, nil, false],
          right: [true, false, true, nil, false, nil, true, nil, false]
        )

      mutated = DataFrame.mutate(frame, both: {:and, [:left, :right]})

      assert DataFrame.pull(mutated, :both) ===
               [true, false, false, false, false, nil, nil, nil, false]

      assert DataFrame.dtypes(mutated).both == :boolean
    end

    # Explorer 0.13.0's `Series.or/2` of these two columns gives these booleans.
    test "or is true where either side is, false where both are, and otherwise missing" do
      frame =
        DataFrame.new(
          left: [true, true, false, false, nil, true, nil, nil, false],
          right: [true, false, true, nil, false, nil, true, nil, false]
        )

      mutated = DataFrame.mutate(frame, either: {:or, [:left, :right]})

      assert DataFrame.pull(mutated, :either) ===
               [true, true, true, nil, nil, true, true, nil, false]

      assert DataFrame.dtypes(mutated).either == :boolean
    end

    test "not is the opposite of a boolean, missing where it is" do
      frame = DataFrame.new(kept: [true, false, nil])

      mutated = DataFrame.mutate(frame, dropped: {:not, [:kept]})

      assert DataFrame.pull(mutated, :dropped) === [false, true, nil]
      assert DataFrame.dtypes(mutated).dropped == :boolean
    end

    # Explorer 0.13.0's `Series.less/2` and `Series.greater/2` of these two columns give these
    # booleans: NaN sorts above every number, infinity included, and is neither below nor above
    # NaN.
    test "a comparison is missing where either number is, and puts NaN above every number" do
      frame =
        DataFrame.new(
          left: [1.0, :nan, nil, :infinity, :neg_infinity, :nan, 2.0],
          right: [2.0, 1.0, 1.0, :nan, -1.0e308, :nan, 2]
        )

      mutated =
        DataFrame.mutate(frame,
          below: {:<, [:left, :right]},
          above: {:>, [:left, :right]}
        )

      assert DataFrame.pull(mutated, :below) === [true, false, nil, true, true, false, false]
      assert DataFrame.pull(mutated, :above) === [false, true, nil, false, false, false, false]
      assert DataFrame.dtypes(mutated).below == :boolean
    end

    test "a comparison reads a constant and an integer column alike" do
      frame = DataFrame.new(x: [1, 3, 5])

      kept = DataFrame.filter(frame, {:and, [{:>, [:x, 1.5]}, {:<, [:x, 5]}]})

      assert DataFrame.pull(kept, :x) === [3]
    end

    test "an operation given a column of the wrong type, or one not in the vocabulary, is refused" do
      frame = DataFrame.new(x: [1.0], label: ["a"], kept: [true])

      assert_raise FunctionClauseError, fn ->
        DataFrame.mutate(frame, finite: {:is_finite, [:label]})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.mutate(frame, both: {:and, [:kept, :x]})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.mutate(frame, both: {:and, [:x, :kept]})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.mutate(frame, either: {:xor, [:kept, :kept]})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.mutate(frame, below: {:<, [:label, :x]})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.mutate(frame, above: {:>, [:x, :kept]})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.mutate(frame, either: {:or, [:kept, :x]})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.mutate(frame, either: {:or, [:x, :kept]})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.mutate(frame, opposite: {:not, [:x]})
      end

      assert_raise FunctionClauseError, fn -> DataFrame.mutate(frame, y: :missing) end
    end

    test "an operation's types are checked when the column has no rows" do
      frame =
        [label: ["a"]]
        |> DataFrame.new()
        |> DataFrame.filter({:constant, false})

      assert DataFrame.dtypes(frame) == %{label: :string}

      assert_raise FunctionClauseError, fn ->
        DataFrame.mutate(frame, finite: {:is_finite, [:label]})
      end
    end

    test "is_finite of a column of only missing values is missing in every row" do
      frame = DataFrame.new(x: [nil, nil])

      mutated = DataFrame.mutate(frame, finite: {:is_finite, [:x]})

      assert DataFrame.pull(mutated, :finite) === [nil, nil]
    end

    test "a struct other than a date or a time is no constant written alone" do
      frame = DataFrame.new(x: [1.0])

      assert_raise FunctionClauseError, fn -> DataFrame.mutate(frame, set: MapSet.new([1])) end
    end

    test "columns are given as a list of pairs, never a map" do
      frame = DataFrame.new(x: [1.0])
      # Built as the test runs, since the type checker warns of a literal map it knows fails.
      columns = Map.new([{:weight, 1.0}])

      assert_raise FunctionClauseError, fn -> DataFrame.mutate(frame, columns) end
    end

    test "cut numbers each value's interval from 1, closed on the right, the lowest at both ends" do
      frame = DataFrame.new(x: [0.0, 0.5, 1.0, 2.0, 3.0, 4.0, -1.0, 5.0, nil, :nan])

      mutated =
        DataFrame.mutate(frame, bin: {:cut, [:x], breaks: [0.0, 1.0, 2.0, 4.0], closed: :right})

      assert DataFrame.pull(mutated, :bin) === [1, 1, 1, 2, 3, 3, nil, nil, nil, nil]
      assert DataFrame.dtypes(mutated).bin == :integer
    end

    test "cut closed on the left puts a value on a break in the interval it opens, the highest at both ends" do
      frame = DataFrame.new(x: [0.0, 1.0, 2.0, 3.0, 4.0])

      mutated =
        DataFrame.mutate(frame, bin: {:cut, [:x], breaks: [0.0, 1.0, 2.0, 4.0], closed: :left})

      assert DataFrame.pull(mutated, :bin) === [1, 2, 3, 3, 3]
    end

    test "cut finds the interval among many breaks, an infinity outside them all" do
      breaks = Enum.map(0..16, fn step -> step / 1 end)
      frame = DataFrame.new(x: [0.25, 7.5, 12.0, 15.75, :infinity, :neg_infinity])

      mutated = DataFrame.mutate(frame, bin: {:cut, [:x], breaks: breaks, closed: :right})

      assert DataFrame.pull(mutated, :bin) === [1, 8, 12, 16, nil, nil]
    end

    test "cut places an infinity among infinite breaks, below or above every number" do
      frame = DataFrame.new(x: [:neg_infinity, 0.0, :infinity])

      mutated =
        DataFrame.mutate(frame,
          bin: {:cut, [:x], breaks: [:neg_infinity, 0.0, :infinity], closed: :right}
        )

      assert DataFrame.pull(mutated, :bin) === [1, 1, 2]
    end

    test "cut of a column that is not numbers is refused" do
      frame = DataFrame.new(label: ["a"])

      assert_raise FunctionClauseError, fn ->
        DataFrame.mutate(frame, bin: {:cut, [:label], breaks: [0.0, 1.0], closed: :right})
      end
    end

    test "true, false and nil name no column" do
      frame = DataFrame.new([{true, [1]}, {nil, [2]}])

      mutated = DataFrame.mutate(frame, kept: true)

      assert DataFrame.pull(mutated, :kept) === [true]
      assert_raise FunctionClauseError, fn -> DataFrame.mutate(frame, gap: nil) end
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

      summarised = DataFrame.summarise(frame, [:panel, :color], n: {:sum, [:weight]})

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

      summarised = DataFrame.summarise(frame, [:x, :y], n: {:sum, [:weight]})

      assert DataFrame.dtypes(summarised) == %{x: :category, y: :integer, n: :float}
      assert DataFrame.pull(summarised, :n) === [4.0, 2.0]
    end

    # Golden: R 4.6.1's sum(c(0.1, 0.2, 0.3)) is 0.59999999999999998, added in extended
    # precision, and rowsum(c(0.1, 0.2, 0.3), rep(1, 3)) is 0.60000000000000009, added in doubles in
    # row order, printed to 17 significant digits. It moves with nothing but how R adds.
    test "a sum is compensated as R's sum() adds, or plain as R's rowsum() does" do
      frame = DataFrame.new(group: [1, 1, 1], weight: [0.1, 0.2, 0.3])

      compensated = DataFrame.summarise(frame, [:group], n: {:sum, [:weight]})

      plain =
        DataFrame.summarise(frame, [:group], n: {:sum, [:weight], summation: :plain})

      assert DataFrame.pull(compensated, :n) === [0.59999999999999998]
      assert DataFrame.pull(plain, :n) === [0.60000000000000009]
    end

    # Golden: R 4.6.1's sum(c(1, NA)), sum(c(2, NaN)), sum(Inf), sum(c(Inf, -Inf)), sum(c(NA,
    # NaN)), sum(c(5, -Inf)) and sum(c(NaN, NA, Inf)) are NA, NaN, Inf, NaN, NA, -Inf and NaN, and
    # with na.rm = TRUE 1, 2, Inf, NaN, 0, -Inf and Inf: a missing value is NA or NaN, the first
    # met kept, and an infinity adds as IEEE adds one.
    test "a missing value makes its group's sum missing, or is skipped, and an infinity adds" do
      frame =
        DataFrame.new(
          group: [1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6, 7, 7, 7],
          weight:
            [1.0, nil, 2.0, :nan, :infinity, :infinity, :neg_infinity, nil, :nan] ++
              [5.0, :neg_infinity, :nan, nil, :infinity]
        )

      propagated = DataFrame.summarise(frame, [:group], n: {:sum, [:weight]})

      skipped =
        DataFrame.summarise(frame, [:group], n: {:sum, [:weight], missing: :skip})

      assert DataFrame.pull(propagated, :n) ===
               [nil, :nan, :infinity, :nan, nil, :neg_infinity, :nan]

      assert DataFrame.pull(skipped, :n) ===
               [1.0, 2.0, :infinity, :nan, 0.0, :neg_infinity, :infinity]
    end

    test "n_distinct counts each group's distinct values, a missing value counting as one" do
      frame =
        DataFrame.new(
          group: [1, 1, 1, 1, 2, 2],
          label: ["a", "a", nil, nil, "b", "c"]
        )

      summarised = DataFrame.summarise(frame, [:group], label: {:n_distinct, [:label]})

      assert DataFrame.pull(summarised, :label) === [2, 2]
      assert DataFrame.dtypes(summarised).label == :integer
    end

    test "first is each group's first value in row order, of its column's type" do
      frame =
        DataFrame.new([
          {:group, [2, 1, 1, 2]},
          {:label, [nil, 6, 4, 8], :category}
        ])

      summarised = DataFrame.summarise(frame, [:group], label: {:first, [:label]})

      assert DataFrame.pull(summarised, :label) === [6, nil]
      assert DataFrame.dtypes(summarised).label == :category
    end

    # Golden: R 4.6.1's quantile(group, probability, na.rm = TRUE), type 7, of the groups c(54.6,
    # 60.4), c(81.6, 7.1), c(1, 2, 3, 4, 10), c(3, 1, 2), c(5, NA, NaN, 1) and NA, printed to 17
    # significant digits; they move only with R's `quantile()`. `lower + h * (higher - lower)`
    # gives 56.05, 58.95 and 44.35 where R's order gives 56.050000000000004, 58.949999999999996 and
    # 44.349999999999994.
    test "a quantile is R's type 7, worked in R's order, a missing value left out" do
      frame =
        DataFrame.new(
          group: [1, 1, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 5, 5, 5, 5, 6],
          y:
            [54.6, 60.4, 81.6, 7.1, 1, 2, 3, 4, 10, 3.0, 1.0, 2.0] ++
              [5.0, nil, :nan, 1.0, nil]
        )

      quantiles =
        for probability <- [0.25, 0.75, 0.5, 0.3, 0, 1] do
          frame
          |> DataFrame.summarise([:group], q: {:quantile, [:y], probability: probability})
          |> DataFrame.pull(:q)
        end

      assert quantiles === [
               [56.050000000000004, 25.724999999999998, 2.0, 1.5, 2.0, nil],
               [58.949999999999996, 62.974999999999994, 4.0, 2.5, 4.0, nil],
               [57.5, 44.349999999999994, 3.0, 2.0, 3.0, nil],
               [56.340000000000003, 29.449999999999999, 2.2000000000000002] ++
                 [1.6000000000000001, 2.2000000000000002, nil],
               [54.600000000000001, 7.0999999999999996, 1.0, 1.0, 1.0, nil],
               [60.399999999999999, 81.599999999999994, 10.0, 3.0, 5.0, nil]
             ]
    end

    # Golden: R 4.6.1's quantile(c(1, Inf, 2, 3), c(0.25, 0.5, 0.75)) is 1.75, 2.5 and Inf, and
    # quantile(c(-Inf, Inf, 2, 3), c(0, 0.25, 0.5, 0.75, 1)) is -Inf, -Inf, 2.5, Inf and Inf.
    test "a quantile puts an infinity at either end and interpolates as R's arithmetic does" do
      frame =
        DataFrame.new(
          group: [1, 1, 1, 1, 2, 2, 2, 2],
          y: [1, :infinity, 2, 3, :neg_infinity, :infinity, 2, 3]
        )

      quantiles =
        for probability <- [0, 0.25, 0.5, 0.75, 1] do
          frame
          |> DataFrame.summarise([:group], q: {:quantile, [:y], probability: probability})
          |> DataFrame.pull(:q)
        end

      assert quantiles === [
               [1.0, :neg_infinity],
               [1.75, :neg_infinity],
               [2.5, 2.5],
               [:infinity, :infinity],
               [:infinity, :infinity]
             ]
    end

    test "a quantile of integers is a float" do
      frame = DataFrame.new(group: [1, 1, 1], y: [3, 1, 2])

      summarised = DataFrame.summarise(frame, [:group], q: {:quantile, [:y], probability: 0.5})

      assert DataFrame.pull(summarised, :q) === [2.0]
      assert DataFrame.dtypes(summarised).q == :float
    end

    # Golden: R 4.6.1's min(c(3, NA, NaN, -Inf), na.rm = TRUE) is -Inf and max(c(3, NA, NaN, 2),
    # na.rm = TRUE) is 3.
    test "min and max leave a missing value out, keep their column's type, and order infinities" do
      frame =
        DataFrame.new(
          group: [1, 1, 1, 1, 2, 2, 2, 2, 3],
          y: [3.0, nil, :nan, :neg_infinity, 3.0, nil, :nan, 2.0, nil],
          n: [4, 1, 2, 9, 5, 5, 6, 3, nil]
        )

      summarised =
        DataFrame.summarise(frame, [:group],
          low: {:min, [:y]},
          high: {:max, [:y]},
          fewest: {:min, [:n]},
          most: {:max, [:n]}
        )

      assert Enum.map([:low, :high, :fewest, :most], fn name ->
               DataFrame.pull(summarised, name)
             end) === [
               [:neg_infinity, 2.0, nil],
               [3.0, 3.0, nil],
               [1, 3, nil],
               [9, 6, nil]
             ]

      dtypes = DataFrame.dtypes(summarised)

      assert Map.take(dtypes, [:low, :fewest]) == %{
               low: :float,
               fewest: :integer
             }
    end

    test "count is how many of a group's values are not missing, nil or NaN" do
      frame =
        DataFrame.new(
          group: [1, 1, 1, 1, 2],
          y: [1.0, nil, :nan, :infinity, nil],
          label: ["a", nil, "b", "c", nil]
        )

      summarised =
        DataFrame.summarise(frame, [:group], y: {:count, [:y]}, label: {:count, [:label]})

      assert {DataFrame.pull(summarised, :y), DataFrame.pull(summarised, :label)} ===
               {[2, 0], [3, 0]}

      assert DataFrame.dtypes(summarised).y == :integer
    end

    # Explorer 0.13.0's grouped `summarise` of a plain float column gives each group's values,
    # `nil` and NaN among them, as a `{:list, {:f, 64}}` column.
    test "list is each group's values in row order, missing ones kept, a list of their type" do
      frame =
        DataFrame.new(
          group: [2, 1, 2, 1, 2],
          y: [3.0, 1.0, nil, :nan, 5],
          cyl: [4, 6, 4, 8, 6]
        )

      summarised =
        DataFrame.summarise(frame, [:group], y: {:list, [:y]}, cyl: {:list, [:cyl]})

      assert {DataFrame.pull(summarised, :y), DataFrame.pull(summarised, :cyl)} ===
               {[[1.0, :nan], [3.0, nil, 5.0]], [[6, 8], [4, 4, 6]]}

      dtypes = DataFrame.dtypes(summarised)

      assert Map.take(dtypes, [:y, :cyl]) == %{
               y: {:list, :float},
               cyl: {:list, :integer}
             }
    end

    test "a frame of no rows summarises into no rows, its columns named" do
      frame = DataFrame.new(group: [], weight: [])

      summarised = DataFrame.summarise(frame, [:group], n: {:sum, [:weight]})

      assert DataFrame.row_count(summarised) == 0
      assert DataFrame.names(summarised) == [:group, :n]
    end

    test "a sum of a column that is not numbers is refused, naming the column and its type" do
      frame = DataFrame.new(group: [1], weight: ["heavy"])

      error =
        assert_raise ArgumentError, fn ->
          DataFrame.summarise(frame, [:group], n: {:sum, [:weight]})
        end

      assert error.message =~ ":weight"
      assert error.message =~ ":string"
    end

    test "a quantile, a minimum or a maximum of a column that is not numbers is refused" do
      frame = DataFrame.new(group: [1], label: ["a"])

      for {aggregate, purpose} <- [
            {{:quantile, [:label], probability: 0.5}, "a quantile orders numbers"},
            {{:min, [:label]}, "a minimum compares numbers"},
            {{:max, [:label]}, "a maximum compares numbers"}
          ] do
        error =
          assert_raise ArgumentError, fn ->
            DataFrame.summarise(frame, [:group], q: aggregate)
          end

        assert error.message ==
                 "#{purpose}, but the column :label is a :string column"
      end
    end

    test "a quantile takes a probability from 0 to 1 and no other option" do
      frame = DataFrame.new(group: [1], y: [1.0])

      for options <- [[], [probability: -0.1], [probability: 1.5], [probability: "half"]] do
        assert_raise FunctionClauseError, fn ->
          DataFrame.summarise(frame, [:group], q: {:quantile, [:y], options})
        end
      end

      assert_raise ArgumentError, fn ->
        DataFrame.summarise(frame, [:group], q: {:quantile, [:y], probability: 0.5, type: 8})
      end
    end

    test "an option not listed, or a value it does not take, is refused" do
      frame = DataFrame.new(group: [1], weight: [1.0])

      assert_raise ArgumentError, fn ->
        DataFrame.summarise(frame, [:group], n: {:sum, [:weight], rounding: :plain})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.summarise(frame, [:group], n: {:sum, [:weight], summation: :kahan})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.summarise(frame, [:group], n: {:sum, [:weight], missing: :zero})
      end
    end

    test "no column to group by, or a sum named as one, is refused" do
      frame = DataFrame.new(group: [1], weight: [1.0])
      # Built as the test runs, since the type checker warns of a literal `[]` it knows fails.
      no_columns = Enum.drop([:group], 1)

      assert_raise FunctionClauseError, fn ->
        DataFrame.summarise(frame, no_columns, n: {:sum, [:weight]})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.summarise(frame, [:group], group: {:sum, [:weight]})
      end
    end

    test "an aggregate not listed, or given other than one column, is refused" do
      frame = DataFrame.new(group: [1], weight: [1.0])

      assert_raise FunctionClauseError, fn ->
        DataFrame.summarise(frame, [:group], n: {:mean, [:weight]})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.summarise(frame, [:group], n: {:sum, :weight})
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.summarise(frame, [:group], n: {:first, [:weight, :weight]})
      end
    end
  end

  describe "join/3" do
    # Explorer 0.13.0's `DataFrame.join(left, right, how: :left, on: :k)` of these gives k `[1, 1,
    # 2, nil, 3]`, a `[10, 10, 20, 30, 40]` and b `["x", "z", nil, nil, nil]`.
    test "each left row in order, once per matching right row, a missing key matching none" do
      left = DataFrame.new(k: [1, 2, nil, 3], a: [10, 20, 30, 40])
      right = DataFrame.new(k: [1, nil, 1, 4], b: ["x", "y", "z", "w"])

      joined = DataFrame.join(left, right, [:k])

      assert DataFrame.names(joined) == [:k, :a, :b]

      assert Enum.map([:k, :a, :b], fn name -> DataFrame.pull(joined, name) end) === [
               [1, 1, 2, nil, 3],
               [10, 10, 20, 30, 40],
               ["x", "z", nil, nil, nil]
             ]
    end

    test "rows join on every key column together, each column keeping its type" do
      left =
        DataFrame.new([
          {:panel, [1, 1, 2]},
          {:group, [1, 2, 1]},
          {:x, [4, 6, 4], :category}
        ])

      right =
        DataFrame.new([
          {:group, [1, 2]},
          {:panel, [2, 1]},
          {:outliers, [[1.0], []]},
          {:fill, ["a", "b"], :category}
        ])

      joined = DataFrame.join(left, right, [:panel, :group])

      assert Enum.map([:outliers, :fill], fn name -> DataFrame.pull(joined, name) end) === [
               [nil, [], [1.0]],
               [nil, "b", "a"]
             ]

      assert DataFrame.dtypes(joined) == %{
               panel: :integer,
               group: :integer,
               x: :category,
               outliers: {:list, :float},
               fill: :category
             }
    end

    test "a frame of no rows on either side joins" do
      left = DataFrame.new(k: [1, 2], a: [10, 20])

      none =
        [k: [1], b: [1.0]]
        |> DataFrame.new()
        |> DataFrame.filter({:constant, false})

      onto_none = DataFrame.join(none, left, [:k])
      none_onto = DataFrame.join(left, none, [:k])

      assert DataFrame.pull(none_onto, :b) === [nil, nil]
      assert DataFrame.row_count(onto_none) == 0
    end

    test "keys of two types, a key a frame lacks, a column in both or no key at all is refused" do
      left = DataFrame.new(k: [1], a: [10])
      no_keys = Enum.drop([:k], 1)

      assert_raise FunctionClauseError, fn ->
        DataFrame.join(left, DataFrame.new(k: [1.0], b: [1]), [:k])
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.join(left, DataFrame.new(j: [1], b: [1]), [:k])
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.join(left, DataFrame.new(k: [1], a: [1]), [:k])
      end

      assert_raise FunctionClauseError, fn ->
        DataFrame.join(left, DataFrame.new(k: [1], b: [1]), no_keys)
      end
    end
  end
end
