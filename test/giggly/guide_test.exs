defmodule Giggly.GuideTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, Guide, Theme}

  describe "axes/4" do
    test "an axis with no breaks and a title of :none draw nothing and take no room" do
      coord = %Coord.Cartesian{}
      params = Coord.panel_params(coord, {{0.0, 1.0}, [], []}, {{0.0, 1.0}, [], []})

      assert Guide.axes(coord, params, %{x: :none, y: :none}, Theme.complete(:gray)) === %{
               bottom: %{axis: {0.0, []}, title: {0.0, []}},
               left: %{axis: {0.0, []}, title: {0.0, []}}
             }
    end
  end
end
