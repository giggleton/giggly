defmodule Giggly.PlotTest do
  use ExUnit.Case, async: true

  alias Giggly.Plot

  doctest Giggly.Plot

  @rows %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "cyl" => ["6", "4"]}

  describe "new/2" do
    test "a missing column's refusal names the call, the aesthetic, the column as written and the columns" do
      error = assert_raise ArgumentError, fn -> Plot.new(@rows, %{x: :wt, y: :mgp}) end

      assert error.message =~ "Plot.new/2"
      assert error.message =~ ":y"
      assert error.message =~ ":mgp"
      assert error.message =~ ~s("mpg")
    end

    test "a value that is not a column reference is refused rather than read as a column's name" do
      rows = %{"2.5" => [2.62, 2.875], "mpg" => [21.0, 22.8]}

      error = assert_raise ArgumentError, fn -> Plot.new(rows, %{x: 2.5, y: :mpg}) end
      assert error.message =~ ":x"
      assert error.message =~ "2.5"
    end
  end

  describe "geom_point/2" do
    test "a point layer records its geom, the identity stat and position, and its resolved mapping" do
      plot =
        @rows
        |> Plot.new()
        |> Plot.geom_point(%{x: :wt, y: :mpg, group: :cyl})

      assert plot.reversed_layers == [
               %Plot.Layer{
                 geom: :point,
                 stat: :identity,
                 position: :identity,
                 mapping: %{x: "wt", y: "mpg", group: "cyl"}
               }
             ]
    end

    test "a column the data does not have is refused by the layer that maps it" do
      plot = Plot.new(@rows, %{x: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot, %{y: :mgp}) end
      assert error.message =~ "Plot.geom_point/2"
    end

    test "an aesthetic points cannot use is refused" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot, %{color: :cyl}) end
      assert error.message =~ ":color"
      assert error.message =~ ":group"
    end

    test "an aesthetic points cannot use is refused when the plot's mapping gives it" do
      plot = Plot.new(@rows, %{x: :wt, y: :mpg, color: :cyl})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot) end
      assert error.message =~ ":color"
    end

    test "x or y mapped by neither the layer nor the plot is refused" do
      plot = Plot.new(@rows, %{x: :wt})

      error = assert_raise ArgumentError, fn -> Plot.geom_point(plot) end
      assert error.message =~ ":y"
    end
  end
end
