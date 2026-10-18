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

      assert error.message =~ "the plot's data"
      assert error.message =~ "index 0"
      assert error.message =~ ~s("gear")
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
end
