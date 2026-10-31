defmodule Giggly.Facet.LabellerTest do
  use ExUnit.Case, async: true

  alias Giggly.Facet.Labeller

  # Every expected label is ggplot2 4.0.3's in R 4.6.1, read from the strips of the plot each test
  # names (`ggplotGrob()`'s strip grobs); a side's labels for a subset of its panels are that
  # subset of R's.

  @value {:value, %{}}
  @both {:both, %{sep: ": "}}
  @context {:context, %{}}

  # A labeller given alone, as a plot records it: the labeller of both sides.
  defp alone(labeller, multi_line \\ true) do
    %{rows: labeller, cols: labeller, columns: %{}, default: @value, multi_line: multi_line}
  end

  # A keyword list of labellers, as a plot records it, its columns by name.
  defp labellers(options) do
    columns = Keyword.get(options, :columns, [])

    %{
      rows: Keyword.get(options, :rows, :none),
      cols: Keyword.get(options, :cols, :none),
      columns: Map.new(columns),
      default: Keyword.get(options, :default, @value),
      multi_line: Keyword.get(options, :multi_line, true)
    }
  end

  # R's `capitalize()` from the labeller page, upper-casing the first letter alone; it is handed a
  # label, never a missing value, so it has no clause for one.
  defp capitalize(label) when is_binary(label) do
    {first, rest} = String.split_at(label, 1)
    String.upcase(first) <> rest
  end

  # The labeller page's `appender()`.
  defp appender(label) when is_binary(label), do: label <> "-foo"

  describe "the kinds of label" do
    # Golden: `facet_wrap(vars(cyl, drv))` over mpg, and over a column `g` holding `NA`.
    test "the value alone, a strip for each column, a missing value as NA" do
      labeller = alone(@value)

      assert Labeller.label(labeller, :wrap, ["cyl", "drv"], [[4, "4"], [8.0, nil]]) ==
               [["4", "4"], ["8", "NA"]]
    end

    # Golden: `facet_wrap(vars(cyl, drv), labeller = "label_both")` over mpg; `facet_grid(. ~ cyl,
    # labeller = \(x) label_both(x, sep = "="))`; `label_both` over `g = c("a", NA, "b")`.
    test "both writes each column's name, the separator and the value" do
      labeller = alone(@both)
      equals = alone({:both, %{sep: "="}})

      assert Labeller.label(labeller, :wrap, ["cyl", "drv"], [[4, "4"], [6, "r"]]) ==
               [["cyl: 4", "drv: 4"], ["cyl: 6", "drv: r"]]

      assert Labeller.label(equals, :cols, ["cyl"], [[4.0], [6.0]]) == [["cyl=4"], ["cyl=6"]]
      assert Labeller.label(labeller, :wrap, ["g"], [["a"], [nil]]) == [["g: a"], ["g: NA"]]
    end

    # Golden: `facet_wrap(vars(cyl, drv), labeller = labeller(.multi_line = FALSE))` over mpg, and
    # with `\(x) label_both(x, multi_line = FALSE)`.
    test "in one strip the labels are joined, and both joins the names and then the values" do
      combinations = [[8, "4"], [5, "f"]]
      values = alone(@value, false)
      both = alone(@both, false)

      assert Labeller.label(values, :wrap, ["cyl", "drv"], combinations) == [["8, 4"], ["5, f"]]

      assert Labeller.label(both, :wrap, ["cyl", "drv"], combinations) ==
               [["cyl, drv: 8, 4"], ["cyl, drv: 5, f"]]
    end

    # Golden: `facet_grid(am ~ vs + cyl, labeller = label_context)` over mtcars.
    test "context writes the value alone for one column, and both for several" do
      labeller = alone(@context)

      assert Labeller.label(labeller, :rows, ["am"], [[0.0], [1.0]]) == [["0"], ["1"]]

      assert Labeller.label(labeller, :cols, ["vs", "cyl"], [[0.0, 4.0], [1.0, 6.0]]) ==
               [["vs: 0", "cyl: 4"], ["vs: 1", "cyl: 6"]]
    end

    # Golden: `facet_wrap(~am, labeller = as_labeller(appender))` and `as_labeller(c(`0` =
    # "Zero"))` over mtcars, a value the table lacks drawn NA.
    test "a function, or a map, gives each label, the value alone around it" do
      appended = alone(&appender/1)
      looked_up = alone(%{"0" => "Zero"})

      assert Labeller.label(appended, :wrap, ["am"], [[0.0], [1.0]]) == [["0-foo"], ["1-foo"]]
      assert Labeller.label(looked_up, :wrap, ["am"], [[0.0], [1.0]]) == [["Zero"], ["NA"]]
    end

    test "a function that returns anything but a string is refused, naming what it returned" do
      labeller = alone(fn _label -> 4 end)

      error =
        assert_raise ArgumentError, fn -> Labeller.label(labeller, :wrap, ["am"], [[0.0]]) end

      assert String.starts_with?(error.message, "a labeller function must return a string")
      assert error.message =~ ~s(returned 4 for the label "0")
    end

    test "a side splitting on no columns has no strips" do
      labeller = alone(@both)

      assert Labeller.label(labeller, :cols, [], [[]]) == [[]]
    end
  end

  describe "a side's own labeller" do
    # Golden: `facet_grid(vs + am ~ gear, labeller = labeller(.rows = label_both, .cols =
    # label_value))` over mtcars; and with `.cols = label_both` alone over `vs ~ am`.
    test "each side is labelled by its own, or else each column alone" do
      labeller = labellers(rows: @both, cols: @value)
      columns_only = labellers(cols: @both)

      assert Labeller.label(labeller, :rows, ["vs", "am"], [[0.0, 1.0]]) == [["vs: 0", "am: 1"]]
      assert Labeller.label(labeller, :cols, ["gear"], [[3.0]]) == [["3"]]
      assert Labeller.label(columns_only, :rows, ["vs"], [[0.0]]) == [["0"]]
      assert Labeller.label(columns_only, :cols, ["am"], [[0.0]]) == [["am: 0"]]
    end

    # Golden: `facet_wrap(~am)` under `labeller(.rows = label_both)` and under `labeller(.cols =
    # label_both)`, both `am: 0`.
    test "a wrap's strips are labelled by the columns' labeller, else the rows'" do
      rows = labellers(rows: @both)
      cols = labellers(cols: @both)
      both_sides = labellers(rows: @value, cols: @both)

      assert Labeller.label(rows, :wrap, ["am"], [[0.0]]) == [["am: 0"]]
      assert Labeller.label(cols, :wrap, ["am"], [[0.0]]) == [["am: 0"]]
      assert Labeller.label(both_sides, :wrap, ["am"], [[0.0]]) == [["am: 0"]]
    end

    # Golden: `facet_grid(vs + am ~ gear, labeller = labeller(.rows = label_both, .multi_line =
    # FALSE))`, and `.rows = label_value`.
    test "in one strip a side's labeller joins its columns as it does alone" do
      both = labellers(rows: @both, multi_line: false)
      values = labellers(rows: @value, multi_line: false)

      assert Labeller.label(both, :rows, ["vs", "am"], [[1.0, 0.0]]) == [["vs, am: 1, 0"]]
      assert Labeller.label(values, :rows, ["vs", "am"], [[1.0, 0.0]]) == [["1, 0"]]
    end

    # Golden: `facet_wrap(~am, labeller = labeller(.cols = appender, .default = c(`0-foo` =
    # "Zero")))`: the function, then the default's map, then the value.
    test "a side's function is written by the default" do
      labeller = labellers(cols: &appender/1, default: %{"0-foo" => "Zero"})

      assert Labeller.label(labeller, :wrap, ["am"], [[0.0], [1.0]]) == [["Zero"], ["NA"]]
    end
  end

  describe "each column alone" do
    # Golden: `facet_grid(vs + am ~ gear, labeller = labeller(vs = label_both, am = label_value))`
    # over mtcars, and `facet_wrap(~am, labeller = labeller(nonexistent = label_both))`.
    test "a column is labelled by its own labeller, else the default; one not split on is passed " <>
           "over" do
      labeller = labellers(columns: [{"vs", @both}, {"am", @value}, {"nonexistent", @both}])

      assert Labeller.label(labeller, :rows, ["vs", "am"], [[0.0, 1.0]]) == [["vs: 0", "1"]]
      assert Labeller.label(labeller, :cols, ["gear"], [[3.0]]) == [["3"]]
    end

    # Golden: `labeller(g = capitalize, .default = label_both)` over `g = c("a", NA, "b")`, and
    # `labeller(am = c(`0` = "Zero"), .default = label_both)` over mtcars, where the value the map
    # lacks is `am: NA`, not missing, so not filled in.
    test "a column's function or map gives its labels, and the default writes them" do
      with_function = labellers(columns: [{"g", &capitalize/1}], default: @both)
      with_map = labellers(columns: [{"am", %{"0" => "Zero"}}], default: @both)

      assert Labeller.label(with_function, :wrap, ["g"], [["a"], [nil]]) == [["g: A"], ["g: NA"]]

      assert Labeller.label(with_map, :wrap, ["am"], [[0.0], [1.0]]) ==
               [["am: Zero"], ["am: NA"]]
    end

    # Golden: `labeller(am = c(`0` = "Zero"))` over mtcars, the second strip `1`; `labeller(g =
    # c(a = "Aye"))` over `g = c("a", NA, "b")`; `labeller(g = label_value, .default = label_both)`
    # over it, the missing value `g: NA`.
    test "a label a column's own leaves missing is the default's" do
      zero = labellers(columns: [{"am", %{"0" => "Zero"}}])
      aye = labellers(columns: [{"g", %{"a" => "Aye"}}])
      value_over_both = labellers(columns: [{"g", @value}], default: @both)

      assert Labeller.label(zero, :wrap, ["am"], [[0.0], [1.0]]) == [["Zero"], ["1"]]

      assert Labeller.label(aye, :wrap, ["g"], [["a"], ["b"], [nil]]) ==
               [["Aye"], ["b"], ["NA"]]

      assert Labeller.label(value_over_both, :wrap, ["g"], [["a"], [nil]]) == [["a"], ["g: NA"]]
    end

    # Golden: `labeller(am = appender, .default = c(`0-foo` = "Zero"))`: the column's function,
    # then the default's map; `1-foo` it lacks, so the default's own label of `1`, which the map
    # lacks too, NA.
    test "the default writes a column's labels, and fills in those it leaves missing" do
      labeller = labellers(columns: [{"am", &appender/1}], default: %{"0-foo" => "Zero"})

      assert Labeller.label(labeller, :wrap, ["am"], [[0.0], [1.0]]) == [["Zero"], ["NA"]]
    end

    # Golden: `facet_wrap(vars(cyl, drv), labeller = labeller(.default = label_context))` over
    # mpg: each column labelled alone is one column, so its value.
    test "context labels each column alone, so writes its value" do
      labeller = labellers(default: @context)

      assert Labeller.label(labeller, :wrap, ["cyl", "drv"], [[8, "4"]]) == [["8", "4"]]
    end

    # Golden: `labeller(cyl = label_both, .multi_line = FALSE)` and `labeller(.default =
    # label_both, .multi_line = FALSE)` over mpg; `labeller(vs = label_both, am = label_value,
    # .multi_line = FALSE)` over mtcars' rows.
    test "in one strip each column's whole label is joined" do
      combinations = [[8, "4"]]
      own = labellers(columns: [{"cyl", @both}], multi_line: false)
      every = labellers(default: @both, multi_line: false)
      grid_rows = labellers(columns: [{"vs", @both}, {"am", @value}], multi_line: false)

      assert Labeller.label(own, :wrap, ["cyl", "drv"], combinations) == [["cyl: 8, 4"]]
      assert Labeller.label(every, :wrap, ["cyl", "drv"], combinations) == [["cyl: 8, drv: 4"]]
      assert Labeller.label(grid_rows, :rows, ["vs", "am"], [[0.0, 1.0]]) == [["vs: 0, 1"]]
    end
  end

  describe "a missing value" do
    # Golden: `labeller(g = capitalize)` over `g = c("a", NA, "b")`: R hands `capitalize()` NA,
    # which gives NA, and the strip is drawn NA. Giggly never hands it over: `capitalize/1` has no
    # clause for one.
    test "is never handed to a function, and is drawn NA" do
      labeller = labellers(columns: [{"g", &capitalize/1}])

      assert Labeller.label(labeller, :wrap, ["g"], [["a"], [nil]]) == [["A"], ["NA"]]
    end

    # R hands its missing value to the function, which writes `NA-foo` over `g = c("a", NA,
    # "b")` under `labeller(g = appender)`, and the map's miss under `labeller(am = c(`0` =
    # "Zero"), .default = appender)` likewise; a missing value handed to nothing, Giggly draws NA,
    # and the miss filled in by the default's own label of `1`, `1-foo`.
    test "a function adding to a label adds nothing to a missing one" do
      appended = labellers(columns: [{"g", &appender/1}])
      looked_up = labellers(columns: [{"am", %{"0" => "Zero"}}], default: &appender/1)

      assert Labeller.label(appended, :wrap, ["g"], [["a"], [nil]]) == [["a-foo"], ["NA"]]
      assert Labeller.label(looked_up, :wrap, ["am"], [[0.0], [1.0]]) == [["Zero-foo"], ["1-foo"]]
    end
  end
end
