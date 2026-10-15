defmodule Giggly.FacetTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Facet, Scale}

  # A frame whose column "g" holds `count` distinct values, one row each.
  defp distinct_values(count), do: DataFrame.new([{"g", Enum.to_list(1..count//1)}])

  defp wrap(facets, options \\ []) do
    %Facet.Wrap{
      facets: facets,
      nrow: Keyword.get(options, :nrow, :none),
      ncol: Keyword.get(options, :ncol, :none)
    }
  end

  defp layout(facet, frame), do: Facet.layout(facet, frame, &Scale.level_key/1)

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
  end
end
