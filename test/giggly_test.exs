defmodule GigglyTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Plot}

  doctest Giggly

  @rows %{"wt" => [2.62, 2.875], "mpg" => [21.0, 22.8], "qsec" => [16.46, 17.02]}

  describe "layer_data/2" do
    test "a layer's mapping takes an aesthetic the plot also maps" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point(%{y: :qsec})

      frame = Giggly.layer_data(plot)
      assert DataFrame.pull(frame, :y) == [16.46, 17.02]
    end

    test "layers are counted in the order they were added" do
      plot =
        @rows
        |> Plot.new(%{x: :wt})
        |> Plot.geom_point(%{y: :mpg})
        |> Plot.geom_point(%{y: :qsec})

      frame = Giggly.layer_data(plot, 1)
      assert DataFrame.pull(frame, :y) == [16.46, 17.02]
    end

    test "a layer the plot does not have is refused rather than read as nothing" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot, 1) end
      assert error.message =~ "no layer 1"
    end

    test "a negative index is refused rather than counted from the end" do
      plot =
        @rows
        |> Plot.new(%{x: :wt, y: :mpg})
        |> Plot.geom_point()

      error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot, -1) end
      assert error.message =~ "no layer -1"
    end
  end
end
