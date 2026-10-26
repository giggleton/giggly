defmodule Giggly.FacetTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Facet, Scale}

  # A frame whose column "g" holds `count` distinct values, one row each.
  defp distinct_values(count), do: DataFrame.new([{"g", Enum.to_list(1..count//1)}])

  defp wrap(facets, options \\ []) do
    %Facet.Wrap{
      facets: facets,
      nrow: Keyword.get(options, :nrow, :none),
      ncol: Keyword.get(options, :ncol, :none),
      scales: Keyword.get(options, :scales, :fixed)
    }
  end

  defp grid(rows, cols, options \\ []) do
    %Facet.Grid{rows: rows, cols: cols, scales: Keyword.get(options, :scales, :fixed)}
  end

  defp layout(facet, frame), do: Facet.layout(facet, [frame], &Scale.level_key/1)

  # The layout over several tables: the plot's data first, then each layer's.
  defp layout_of(facet, frames), do: Facet.layout(facet, frames, &Scale.level_key/1)

  # Each row's panel once the facet has given a table its panels, and the value of `name` in each,
  # in row order.
  defp panels(facet, frame, facet_layout, name) do
    paneled = Facet.assign_panels(facet, frame, facet_layout)
    {DataFrame.pull(paneled, :panel), DataFrame.pull(paneled, name)}
  end

  # Each panel's row and column, in panel order.
  defp places(layout) do
    rows = DataFrame.pull(layout, :row)
    columns = DataFrame.pull(layout, :column)
    Enum.zip_with(rows, columns, fn row, column -> {row, column} end)
  end

  # The rows and columns a layout uses.
  defp dimensions(layout) do
    {rows, columns} =
      layout
      |> places()
      |> Enum.unzip()

    {Enum.max(rows), Enum.max(columns)}
  end

  describe "the wrapped layout" do
    test "with neither nrow nor ncol, the panels are laid out as ggplot2 lays them out" do
      # Golden: R 4.6.1's `n2mfrow()`, rows and columns swapped as ggplot2 4.0.3's `wrap_dims()`
      # swaps them, at each end of its rule (three, six and twelve panels) and past it.
      expected = %{3 => {1, 3}, 6 => {2, 3}, 12 => {3, 4}, 13 => {4, 4}, 17 => {4, 5}}

      assert Map.new(expected, fn {count, _dimensions} ->
               facet_layout = layout(wrap(["g"]), distinct_values(count))
               {count, dimensions(facet_layout)}
             end) == expected
    end

    test "the panels fill the rows left to right" do
      assert places(layout(wrap(["g"]), distinct_values(5))) ==
               [{1, 1}, {1, 2}, {1, 3}, {2, 1}, {2, 2}]
    end

    test "given nrow alone, the panels take as many columns as they need" do
      # Seven panels in at most five rows need two columns, so only four rows are used, as in
      # ggplot2's `facet_wrap(vars(class), nrow = 5)` on mpg.
      assert dimensions(layout(wrap(["g"], nrow: 5), distinct_values(7))) == {4, 2}
    end

    test "given ncol alone, the panels take as many rows as they need" do
      assert dimensions(layout(wrap(["g"], ncol: 4), distinct_values(7))) == {2, 4}
    end

    test "given both, the panels take them" do
      assert dimensions(layout(wrap(["g"], nrow: 2, ncol: 4), distinct_values(7))) == {2, 4}
    end

    test "given both too few for the panels, the layout is refused naming the counts" do
      error =
        assert_raise ArgumentError, fn ->
          layout(wrap(["g"], nrow: 2, ncol: 3), distinct_values(7))
        end

      assert error.message =~ ~s("g")
      assert error.message =~ "needs 7 panels"
      assert error.message =~ "only 6"
    end

    test "data with no rows makes no panels and is refused" do
      error = assert_raise ArgumentError, fn -> layout(wrap(["g"]), distinct_values(0)) end
      assert error.message =~ "no rows"
    end

    test "every panel uses the first scale of each axis" do
      facet_layout = layout(wrap(["g"]), distinct_values(3))

      assert {DataFrame.pull(facet_layout, :scale_x), DataFrame.pull(facet_layout, :scale_y)} ==
               {[1, 1, 1], [1, 1, 1]}
    end
  end

  describe "the wrapped panels" do
    test "are ordered as a discrete axis orders its levels, a missing value last" do
      frame = DataFrame.new([{"g", ["b", nil, "a", "B", "b", "a"]}])
      facet = wrap(["g"])
      facet_layout = layout(facet, frame)

      # Bytes, not R's locale: ggplot2 orders these a, b, B, NA.
      assert DataFrame.pull(facet_layout, "g") == ["B", "a", "b", nil]

      paneled = Facet.assign_panels(facet, frame, facet_layout)
      assert DataFrame.pull(paneled, :panel) == [3, 4, 2, 1, 3, 2]
    end

    test "of two columns are the combinations that occur, by the first column, then the second" do
      frame = DataFrame.new([{"cyl", [8, 4, 6, 4, 8]}, {"drv", ["f", "4", "r", "f", "4"]}])
      facet = wrap(["cyl", "drv"])
      facet_layout = layout(facet, frame)

      assert {DataFrame.pull(facet_layout, "cyl"), DataFrame.pull(facet_layout, "drv")} ==
               {[4, 4, 6, 8, 8], ["4", "f", "r", "4", "f"]}

      paneled = Facet.assign_panels(facet, frame, facet_layout)
      assert DataFrame.pull(paneled, :panel) == [5, 1, 3, 2, 4]
    end
  end

  # Golden: each answer is ggplot2 4.0.3's in R 4.6.1, read from `ggplot_build(plot)$layout$layout`
  # and each layer's `PANEL` for a plot whose layers draw tables of their own. It moves with how
  # the tables make the panels or a table's rows are repeated across them.
  describe "the wrapped panels over the plot's data and every layer's table" do
    setup do
      %{
        plot_data: DataFrame.new([{"wt", [2.62, 2.875, 2.32]}, {"cyl", [6, 4, 4]}]),
        cylinders_and_gears:
          DataFrame.new([
            {"wt", [2.62, 2.875, 2.32, 3.2, 3.4, 3.5]},
            {"cyl", [6, 4, 4, 8, 6, 8]},
            {"am", [1, 1, 0, 0, 0, 1]}
          ])
      }
    end

    test "a value only a layer's table holds makes a panel", %{plot_data: plot_data} do
      extra = DataFrame.new([{"wt", [5.0]}, {"cyl", [10]}])
      facet = wrap(["cyl"])
      facet_layout = layout_of(facet, [plot_data, plot_data, extra])

      assert DataFrame.pull(facet_layout, "cyl") == [4, 6, 10]
      assert panels(facet, extra, facet_layout, "wt") == {[3], [5.0]}
    end

    test "the plot's data makes panels though no layer draws it", %{plot_data: plot_data} do
      only_four = DataFrame.new([{"wt", [1.0, 2.0]}, {"cyl", [4, 4]}])
      facet_layout = layout_of(wrap(["cyl"]), [plot_data, only_four])

      assert DataFrame.pull(facet_layout, "cyl") == [4, 6]
    end

    test "a table lacking the column makes no panel, and every panel draws all its rows, in turn",
         %{plot_data: plot_data} do
      every = DataFrame.new([{"wt", [1.0, 2.0]}])
      facet = wrap(["cyl"])
      facet_layout = layout_of(facet, [plot_data, every])

      assert DataFrame.pull(facet_layout, "cyl") == [4, 6]
      assert panels(facet, every, facet_layout, "wt") == {[1, 1, 2, 2], [1.0, 2.0, 1.0, 2.0]}
    end

    test "a table lacking one of two columns is drawn in each panel of its values, a row at a time",
         %{cylinders_and_gears: data} do
      partial = DataFrame.new([{"wt", [1.0, 2.0]}, {"am", [1, 0]}])
      facet = wrap(["cyl", "am"])
      facet_layout = layout_of(facet, [data, data, partial])

      assert DataFrame.pull(facet_layout, :panel) == [1, 2, 3, 4, 5, 6]

      assert panels(facet, partial, facet_layout, "wt") ==
               {[2, 1, 4, 3, 6, 5], [1.0, 2.0, 1.0, 2.0, 1.0, 2.0]}
    end

    test "a value only such a table holds makes a panel with each value of the other column",
         %{cylinders_and_gears: data} do
      facet = wrap(["cyl", "am"])
      new_gear = DataFrame.new([{"wt", [1.0]}, {"am", [2]}])
      new_cylinders = DataFrame.new([{"wt", [1.0]}, {"cyl", [10]}])
      by_gear = layout_of(facet, [data, data, new_gear])
      by_cylinders = layout_of(facet, [data, data, new_cylinders])

      assert {DataFrame.pull(by_gear, "cyl"), DataFrame.pull(by_gear, "am")} ==
               {[4, 4, 4, 6, 6, 6, 8, 8, 8], [0, 1, 2, 0, 1, 2, 0, 1, 2]}

      assert panels(facet, new_gear, by_gear, "wt") == {[3, 6, 9], [1.0, 1.0, 1.0]}

      assert {DataFrame.pull(by_cylinders, "cyl"), DataFrame.pull(by_cylinders, "am")} ==
               {[4, 4, 6, 6, 8, 8, 10, 10], [0, 1, 0, 1, 0, 1, 0, 1]}

      assert panels(facet, new_cylinders, by_cylinders, "wt") == {[7, 8], [1.0, 1.0]}
    end

    test "a column only a layer's table holds makes the panels, the plot's data drawn in each",
         %{plot_data: plot_data} do
      geared = DataFrame.new([{"wt", [1.0, 2.0]}, {"gear", [3, 5]}])
      facet = wrap(["gear"])
      facet_layout = layout_of(facet, [plot_data, plot_data, geared])

      assert DataFrame.pull(facet_layout, "gear") == [3, 5]
      assert panels(facet, geared, facet_layout, "wt") == {[1, 2], [1.0, 2.0]}

      assert panels(facet, plot_data, facet_layout, "wt") ==
               {[1, 1, 1, 2, 2, 2], [2.62, 2.875, 2.32, 2.62, 2.875, 2.32]}
    end

    test "unless some table holds every column, the layout is refused naming what each lacks",
         %{plot_data: plot_data} do
      error =
        assert_raise ArgumentError, fn ->
          layout_of(wrap(["gear"]), [plot_data, plot_data])
        end

      assert error.message =~ ~s(facet_wrap by "gear")
      assert error.message =~ "the plot's data"
      assert error.message =~ "index 0"
    end

    test "a table with no rows makes no panel and draws in none", %{plot_data: plot_data} do
      empty_with = DataFrame.new([{"wt", []}, {"cyl", []}])
      empty_without = DataFrame.new([{"wt", []}])
      facet = wrap(["cyl"])
      facet_layout = layout_of(facet, [plot_data, empty_with, empty_without])

      assert DataFrame.pull(facet_layout, "cyl") == [4, 6]
      assert panels(facet, empty_with, facet_layout, "wt") == {[], []}
      assert panels(facet, empty_without, facet_layout, "wt") == {[], []}
    end
  end

  describe "the wrapped panels of a factor" do
    # The facet's values in panel order, read from the layout over `frames`.
    defp panel_values(facets, frames) do
      layout = layout_of(wrap(facets), frames)
      Enum.map(facets, fn name -> DataFrame.pull(layout, name) end)
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 lays `facet_wrap(~f)` out over `f = factor(c("b", "a"),
    # levels = c("b", "a"))` b, a; over levels `c("c", "b", "a")` holding only b and a, b, a too.
    test "a factor's panels follow its levels, a level no row holds making none" do
      held = DataFrame.new([{"f", ["a", "b"], {:category, levels: ["b", "a"]}}])
      unheld = DataFrame.new([{"f", ["a", "b"], {:category, levels: ["c", "b", "a"]}}])

      assert {panel_values(["f"], [held]), panel_values(["f"], [unheld])} ===
               {[["b", "a"]], [["b", "a"]]}
    end

    # Golden: as above, the plot's data a factor with levels `c("b", "a")` and a layer's table a
    # factor with levels `c("z", "a")`: vctrs combines the two into levels b, a, z.
    test "two tables' factors follow the first's levels, then those the next adds" do
      plot_data = DataFrame.new([{"f", ["a", "b"], {:category, levels: ["b", "a"]}}])
      layer_table = DataFrame.new([{"f", ["a", "z"], {:category, levels: ["z", "a"]}}])

      assert panel_values(["f"], [plot_data, layer_table]) === [["b", "a", "z"]]
    end

    # Golden: as above, a factor with levels `c("b", "a")` in one table beside the text `c` and
    # `a` in the other, either way round: vctrs makes the column text, sorted a, b, c.
    test "a factor beside a column of text in another table is sorted as text" do
      factor = DataFrame.new([{"f", ["b", "a"], {:category, levels: ["b", "a"]}}])
      text = DataFrame.new([{"f", ["c", "a"]}])

      assert {panel_values(["f"], [factor, text]), panel_values(["f"], [text, factor])} ===
               {[["a", "b", "c"]], [["a", "b", "c"]]}
    end

    # Golden: as above, `facet_wrap(~f)` over f `b, NA, a` with levels `c("b", "a")`: panels b, a
    # and NA, the rows in panels 1, 3 and 2.
    test "a factor's missing value makes a panel of its own, after its levels" do
      frame = DataFrame.new([{"f", ["b", nil, "a"], {:category, levels: ["b", "a"]}}])
      facet = wrap(["f"])
      facet_layout = layout(facet, frame)

      assert DataFrame.pull(facet_layout, "f") == ["b", "a", nil]
      assert panels(facet, frame, facet_layout, "f") == {[1, 3, 2], ["b", nil, "a"]}
    end

    # Golden: as above, `facet_wrap(~f + g)` over f `b, b, a` with levels `c("b", "a")` and g
    # `y, z, y` with levels `c("z", "y")`: panels (b, z), (b, y), (a, y).
    test "two factor columns order the panels by the first's levels, then the second's" do
      frame =
        DataFrame.new([
          {"f", ["b", "b", "a"], {:category, levels: ["b", "a"]}},
          {"g", ["y", "z", "y"], {:category, levels: ["z", "y"]}}
        ])

      assert panel_values(["f", "g"], [frame]) === [["b", "b", "a"], ["z", "y", "y"]]
    end
  end

  describe "the wrapped layout's axes and strips" do
    test "a panel draws an axis on each side with no panel beside it" do
      facet_layout = layout(wrap(["g"]), distinct_values(5))

      # Two rows of three, the last one short: the third panel has an empty cell below it.
      assert {DataFrame.pull(facet_layout, :axis_bottom),
              DataFrame.pull(facet_layout, :axis_left)} ==
               {[false, false, true, true, true], [true, false, false, true, false]}
    end

    test "each panel's strips label its values, one per column, a missing value as NA" do
      frame = DataFrame.new([{"cyl", [4, nil, 4]}, {"drv", [:f, :r, :awd]}])

      facet_layout = layout(wrap(["cyl", "drv"]), frame)
      assert DataFrame.pull(facet_layout, :strip) == [["4", "awd"], ["4", "f"], ["NA", "r"]]
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 writes the strips of `facet_wrap(~ t + f)` over
    # `t = c(TRUE, FALSE, TRUE)` and `f = c(0.5, 1e5, 2)` FALSE and 1e+05, TRUE and 0.5, TRUE and 2,
    # and mtcars' cylinders, doubles, 4, 6 and 8.
    test "a strip writes its value as R's as.character() does" do
      frame = DataFrame.new([{"t", [true, false, true]}, {"f", [0.5, 1.0e5, 2.0]}])
      cylinders = DataFrame.new([{"cyl", [6.0, 4.0, 8.0]}])

      by_flag_and_number = layout(wrap(["t", "f"]), frame)
      by_cylinders = layout(wrap(["cyl"]), cylinders)

      assert {DataFrame.pull(by_flag_and_number, :strip), DataFrame.pull(by_cylinders, :strip)} ===
               {[["FALSE", "1e+05"], ["TRUE", "0.5"], ["TRUE", "2"]], [["4"], ["6"], ["8"]]}
    end
  end

  describe "the wrapped layout's free scales" do
    test "a free axis gives each panel its own scale and draws every panel's axis" do
      free_x = layout(wrap(["g"], scales: :free_x), distinct_values(5))
      free_y = layout(wrap(["g"], scales: :free_y), distinct_values(5))

      assert {DataFrame.pull(free_x, :scale_x), DataFrame.pull(free_x, :scale_y)} ==
               {[1, 2, 3, 4, 5], [1, 1, 1, 1, 1]}

      assert {DataFrame.pull(free_x, :axis_bottom), DataFrame.pull(free_x, :axis_left)} ==
               {[true, true, true, true, true], [true, false, false, true, false]}

      assert {DataFrame.pull(free_y, :scale_x), DataFrame.pull(free_y, :scale_y)} ==
               {[1, 1, 1, 1, 1], [1, 2, 3, 4, 5]}

      assert {DataFrame.pull(free_y, :axis_bottom), DataFrame.pull(free_y, :axis_left)} ==
               {[false, false, true, true, true], [true, true, true, true, true]}
    end
  end

  describe "the grid layout" do
    # Rows a and b, columns u and v; no row holds a with v.
    setup do
      %{
        data:
          DataFrame.new([
            {"x", [1, 2, 3, 10]},
            {"r", ["a", "a", "b", "b"]},
            {"c", ["u", "u", "v", "u"]}
          ])
      }
    end

    test "every row's values are crossed with every column's, a pair no table holds a panel too",
         %{data: data} do
      facet_layout = layout(grid(["r"], ["c"]), data)

      assert {DataFrame.pull(facet_layout, :panel), places(facet_layout),
              DataFrame.pull(facet_layout, "r"), DataFrame.pull(facet_layout, "c")} ==
               {[1, 2, 3, 4], [{1, 1}, {1, 2}, {2, 1}, {2, 2}], ["a", "a", "b", "b"],
                ["u", "v", "u", "v"]}

      assert panels(grid(["r"], ["c"]), data, facet_layout, "x") == {[1, 1, 4, 3], [1, 2, 3, 10]}
    end

    test "a side splitting on nothing gives a single column or a single row of panels",
         %{data: data} do
      by_rows = layout(grid(["r"], []), data)
      by_columns = layout(grid([], ["c"]), data)

      assert {places(by_rows), places(by_columns)} ==
               {[{1, 1}, {2, 1}], [{1, 1}, {1, 2}]}
    end

    test "a row of panels for each combination of several columns, ordered by the first" do
      frame = DataFrame.new([{"v", [1, 0, 1, 0]}, {"a", [0, 0, 1, 1]}, {"g", [3, 3, 4, 4]}])
      facet_layout = layout(grid(["v", "a"], ["g"]), frame)

      assert {DataFrame.pull(facet_layout, "v"), DataFrame.pull(facet_layout, "a"),
              DataFrame.pull(facet_layout, "g"), dimensions(facet_layout)} ==
               {[0, 0, 0, 0, 1, 1, 1, 1], [0, 0, 1, 1, 0, 0, 1, 1], [3, 4, 3, 4, 3, 4, 3, 4],
                {4, 2}}
    end

    test "every panel uses the first scale of each axis", %{data: data} do
      facet_layout = layout(grid(["r"], ["c"]), data)

      assert {DataFrame.pull(facet_layout, :scale_x), DataFrame.pull(facet_layout, :scale_y)} ==
               {[1, 1, 1, 1], [1, 1, 1, 1]}
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1 numbers `facet_grid(r ~ c, scales = "free")`'s SCALE_X by
    # the panel's column and its SCALE_Y by its row.
    test "a free axis gives each column of panels its x scale and each row its y scale",
         %{data: data} do
      free_x = layout(grid(["r"], ["c"], scales: :free_x), data)
      free_y = layout(grid(["r"], ["c"], scales: :free_y), data)
      free = layout(grid(["r"], ["c"], scales: :free), data)

      assert Enum.map([free_x, free_y, free], fn facet_layout ->
               {DataFrame.pull(facet_layout, :scale_x), DataFrame.pull(facet_layout, :scale_y)}
             end) ==
               [
                 {[1, 2, 1, 2], [1, 1, 1, 1]},
                 {[1, 1, 1, 1], [1, 1, 2, 2]},
                 {[1, 2, 1, 2], [1, 1, 2, 2]}
               ]
    end

    test "an axis is drawn only at the grid's margins, free scales or not", %{data: data} do
      for scales <- [:fixed, :free] do
        facet_layout = layout(grid(["r"], ["c"], scales: scales), data)

        assert {DataFrame.pull(facet_layout, :axis_bottom),
                DataFrame.pull(facet_layout, :axis_left)} ==
                 {[false, false, true, true], [true, false, true, false]}
      end
    end

    test "the first row's panels are labelled with the columns' values, a missing value as NA" do
      frame = DataFrame.new([{"r", ["a", "b"]}, {"c", [nil, 4.0]}, {"d", [true, true]}])
      labelled = layout(grid(["r"], ["c", "d"]), frame)
      unlabelled = layout(grid(["r"], []), frame)

      assert DataFrame.pull(labelled, :strip) == [["4", "TRUE"], ["NA", "TRUE"], [], []]
      assert DataFrame.pull(unlabelled, :strip) == [[], []]
    end
  end

  describe "the grid's panels over the plot's data and every layer's table" do
    setup do
      %{
        plot_data:
          DataFrame.new([
            {"x", [1, 2, 3, 10]},
            {"r", ["a", "a", "b", "b"]},
            {"c", ["u", "u", "u", "v"]}
          ])
      }
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1, `facet_grid(r ~ c)` over the plot's data and a layer's
    # table holding x 5 and 6 and c `w` and `u` but no r: panels a and b by u, v and w, the
    # layer's rows in panels 3, 1, 6 and 4.
    test "a value only a layer's table holds makes a column, the table lacking the rows' column " <>
           "drawn down it",
         %{plot_data: plot_data} do
      extra = DataFrame.new([{"x", [5, 6]}, {"c", ["w", "u"]}])
      facet = grid(["r"], ["c"])
      facet_layout = layout_of(facet, [plot_data, plot_data, extra])

      assert {DataFrame.pull(facet_layout, "r"), DataFrame.pull(facet_layout, "c")} ==
               {["a", "a", "a", "b", "b", "b"], ["u", "v", "w", "u", "v", "w"]}

      assert panels(facet, extra, facet_layout, "x") == {[3, 1, 6, 4], [5, 6, 5, 6]}
    end

    # Golden: as above, a layer's table holding r `b` alone draws in panels 3 and 4; one holding r
    # `z` alone adds a row, its row drawn in panels 5 and 6.
    test "a table holding the rows' column alone is drawn across its row, a new value a new row",
         %{plot_data: plot_data} do
      facet = grid(["r"], ["c"])
      row_b = DataFrame.new([{"x", [7]}, {"r", ["b"]}])
      row_z = DataFrame.new([{"x", [7]}, {"r", ["z"]}])
      with_b = layout_of(facet, [plot_data, plot_data, row_b])
      with_z = layout_of(facet, [plot_data, plot_data, row_z])

      assert panels(facet, row_b, with_b, "x") == {[3, 4], [7, 7]}
      assert dimensions(with_z) == {3, 2}
      assert panels(facet, row_z, with_z, "x") == {[5, 6], [7, 7]}
    end

    # Golden: as above, `facet_grid(r ~ c)` over r `a, NA, a` and c `NA, u, u`: rows a then NA,
    # columns u then NA, the rows in panels 2, 3 and 1.
    test "a missing value is a row or a column of its own, last" do
      frame = DataFrame.new([{"x", [1, 2, 3]}, {"r", ["a", nil, "a"]}, {"c", [nil, "u", "u"]}])
      facet = grid(["r"], ["c"])
      facet_layout = layout(facet, frame)

      assert {DataFrame.pull(facet_layout, "r"), DataFrame.pull(facet_layout, "c")} ==
               {["a", "a", nil, nil], ["u", nil, "u", nil]}

      assert panels(facet, frame, facet_layout, "x") == {[2, 3, 1], [1, 2, 3]}
    end

    # ggplot2 checks the rows' columns and the columns' apart: "At least one layer must contain all
    # faceting variables: `r` and `zz`", naming what each table lacks of those.
    test "unless some table holds every column of a side, the layout is refused naming that side",
         %{plot_data: plot_data} do
      error =
        assert_raise ArgumentError, fn ->
          layout_of(grid(["r", "zz"], ["c"]), [plot_data, plot_data, plot_data])
        end

      assert error.message =~ ~s(facet_grid by rows "r", "zz")

      assert error.message =~
               ~s(the plot's data lacks "zz"; the layer at index 0's table lacks "zz"; ) <>
                 ~s(the layer at index 1's table lacks "zz")

      error = assert_raise ArgumentError, fn -> layout(grid(["r"], ["zz"]), plot_data) end
      assert error.message =~ ~s(facet_grid by cols "zz")
    end

    test "data with no rows makes no panels and is refused" do
      empty = DataFrame.new([{"r", []}, {"c", []}])

      error = assert_raise ArgumentError, fn -> layout(grid(["r"], ["c"]), empty) end
      assert error.message =~ "no rows"
    end
  end
end
