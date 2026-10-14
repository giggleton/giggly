defmodule Giggly.GeomTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, DataFrame, Geom}
  alias Giggly.Scene.Circles

  describe "draw_panel/3 for points" do
    test "a row missing its x or its y is not drawn" do
      panel_params = Coord.panel_params(:cartesian, {{0.0, 4.0}, [], []}, {{0.0, 4.0}, [], []})
      frame = DataFrame.new(x: [1.0, nil, 2.0, 3.0], y: [1.0, 3.0, :nan, 2.0])

      assert [%Circles{x: [0.25, 0.75], y: [0.25, 0.5]}] =
               Geom.draw_panel(frame, :point, panel_params)
    end
  end
end
