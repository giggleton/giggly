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

  # Golden: the legend boxes ggplot2 4.0.3 draws through vdiffr 1.0.9 (R 4.6.1) for `alpha = year`
  # on mpg, keys 2000 to 2008 by 2, and for a column named `a_long_column_name`, keys 2.5, 5.0 and
  # 7.5: 53.30 by 112.69 points, and 119.22 by 78.13. They move with the theme's legend values or
  # how a legend is laid out.
  describe "legends/2" do
    test "a legend is its margin around a title above a key for each label" do
      keys = Enum.map(~w(2000 2002 2004 2006 2008), fn label -> {label, []} end)
      {width, scene} = Guide.legends([{"year", keys}], Theme.complete(:gray))
      height = height(scene)

      assert {Float.round(width, 2), Float.round(height, 2)} === {53.3, 112.69}
    end

    test "a title wider than its keys and labels widens the legend to it" do
      keys = Enum.map(~w(2.5 5.0 7.5), fn label -> {label, []} end)
      {width, scene} = Guide.legends([{"a_long_column_name", keys}], Theme.complete(:gray))
      height = height(scene)

      assert {Float.round(width, 2), Float.round(height, 2)} === {119.22, 78.13}
    end
  end

  # Golden: the legends ggplot2 4.0.3 stacks for mpg's `alpha = cyl` above `colour = class`
  # (`guides(order =)`), through vdiffr 1.0.9 (R 4.6.1), test/golden/point_colour_alpha.R: the alpha
  # legend's background 38.61 by 112.69 points, then 10.96 points of `legend.spacing.y`, then the
  # colour legend's 81.18 by 147.25, both at one left edge.
  describe "legends/2 stacking" do
    test "legends stack in the order given, as wide as the widest, each hung from the box's left" do
      alpha_keys = Enum.map(~w(4 5 6 7 8), fn label -> {label, []} end)

      colour_keys =
        Enum.map(~w(2seater compact midsize minivan pickup subcompact suv), fn label ->
          {label, []}
        end)

      {width, box} =
        Guide.legends([{"cyl", alpha_keys}, {"class", colour_keys}], Theme.complete(:gray))

      [alpha_legend, colour_legend] = box.cells

      assert {Float.round(width, 2),
              Enum.map(box.heights, fn {:points, height} -> Float.round(height, 2) end)} ===
               {81.18, [112.69, 10.96, 147.25]}

      assert {alpha_legend.rows, alpha_legend.hang, colour_legend.rows, colour_legend.hang} ===
               {1..1, {:left, alpha_width(alpha_legend)}, 3..3, {:left, width}}

      alpha_legend_width = alpha_width(alpha_legend)

      assert Float.round(alpha_legend_width, 2) === 38.61
    end
  end

  defp alpha_width(%{primitives: [legend]}),
    do: Enum.sum(for {:points, width} <- legend.widths, do: width)

  defp height(scene), do: Enum.sum(for {:points, height} <- scene.heights, do: height)
end
