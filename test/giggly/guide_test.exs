defmodule Giggly.GuideTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, Guide, Theme}

  describe "axes/3 and titles/4" do
    test "an axis with no breaks and a title of :none draw nothing and take no room" do
      coord = %Coord.Cartesian{}
      params = Coord.panel_params(coord, {{0.0, 1.0}, [], []}, {{0.0, 1.0}, [], []})
      theme = Theme.complete(:gray)

      assert {Guide.axes(coord, params, theme),
              Guide.titles(coord, params, %{x: :none, y: :none}, theme)} ===
               {%{bottom: {0.0, []}, left: {0.0, []}}, %{bottom: {0.0, []}, left: {0.0, []}}}
    end
  end
end
