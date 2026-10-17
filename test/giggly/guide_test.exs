defmodule Giggly.GuideTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, Guide, Theme}

  describe "Axis.draw/3 and Axis.titles/4" do
    test "an axis with no breaks and a title of :none draw nothing and take no room" do
      coord = %Coord.Cartesian{}
      params = Coord.panel_params(coord, {{0.0, 1.0}, [], []}, {{0.0, 1.0}, [], []})
      theme = Theme.complete(:gray)

      assert {Guide.Axis.draw(coord, params, theme),
              Guide.Axis.titles(coord, params, %{x: :none, y: :none}, theme)} ===
               {%{bottom: {0.0, []}, left: {0.0, []}}, %{bottom: {0.0, []}, left: {0.0, []}}}
    end
  end

  # Golden: the legend boxes ggplot2 4.0.3 draws through vdiffr 1.0.9 (R 4.6.1) for `alpha = year`
  # on mpg, keys 2000 to 2008 by 2, and for a column named `a_long_column_name`, keys 2.5, 5.0 and
  # 7.5: 53.30 by 112.69 points, and 119.22 by 78.13. They move with the theme's legend values or
  # how a legend is laid out.
  describe "draw/3 for a legend" do
    test "a legend is its margin around a title above a key for each label" do
      keys = Enum.map(~w(2000 2002 2004 2006 2008), fn label -> %{label: label, glyphs: []} end)

      {width, scene} =
        Guide.draw(%Guide.Legend{}, %{title: "year", keys: keys}, Theme.complete(:gray))

      height = height(scene)

      assert {Float.round(width, 2), Float.round(height, 2)} === {53.3, 112.69}
    end

    test "a title wider than its keys and labels widens the legend to it" do
      keys = Enum.map(~w(2.5 5.0 7.5), fn label -> %{label: label, glyphs: []} end)

      {width, scene} =
        Guide.draw(
          %Guide.Legend{},
          %{title: "a_long_column_name", keys: keys},
          Theme.complete(:gray)
        )

      height = height(scene)

      assert {Float.round(width, 2), Float.round(height, 2)} === {119.22, 78.13}
    end
  end

  # Golden: the legends ggplot2 4.0.3 stacks for mpg's `alpha = cyl` above `colour = class`
  # (`guides(order =)`), through vdiffr 1.0.9 (R 4.6.1), test/golden/point_colour_alpha.R: the alpha
  # legend's background 38.61 by 112.69 points, then 10.96 points of `legend.spacing.y`, then the
  # colour legend's 81.18 by 147.25, both at one left edge.
  describe "Box.draw/2" do
    test "legends stack in the order given, as wide as the widest, each hung from the box's left" do
      theme = Theme.complete(:gray)
      alpha = legend("cyl", ~w(4 5 6 7 8), theme)
      colour = legend("class", ~w(2seater compact midsize minivan pickup subcompact suv), theme)

      {width, box} = Guide.Box.draw([alpha, colour], theme)

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

  # Golden: the colour bar ggplot2 4.0.3 draws for mpg's `colour = cty` in its gradient form,
  # through vdiffr 1.0.9 (R 4.6.1): its background 43.51 by 112.69 points, the bar 17.28 by 86.40,
  # and a white tick 0.38 wide reaching 3.46 into each side at each break.
  describe "draw/3 for a colour bar" do
    test "a colour bar is its margin around a title above a bar five keys long, labelled at its ticks" do
      places = [0.0385, 0.231, 0.423, 0.615, 0.808, 1.0]

      keys =
        Enum.zip_with(~w(10 15 20 25 30 35), places, fn label, place ->
          %{label: label, place: place, glyphs: []}
        end)

      decor = [{0.0, "#132B43"}, {1.0, "#56B1F7"}]
      theme = Theme.complete(:gray)

      {width, scene} =
        Guide.draw(%Guide.Colorbar{bins: 15}, %{title: "cty", keys: keys, decor: decor}, theme)

      scene_height = height(scene)
      assert {Float.round(width, 2), Float.round(scene_height, 2)} === {43.51, 112.69}

      [_background, _title, bar, labels] = scene.cells
      [%Giggly.Scene.Gradient{stops: ^decor}, ticks] = bar.primitives

      {:points, bar_width} = Enum.at(scene.widths, 1)
      {:points, bar_length} = Enum.at(scene.heights, 3)
      assert {Float.round(bar_width, 2), Float.round(bar_length, 2)} === {17.28, 86.4}

      assert {Float.round(ticks.stroke_width, 2), length(ticks.lines), ticks.color} ===
               {0.38, 12, List.duplicate("#FFFFFF", 12)}

      [[{inside, first_place}, {1.0, first_place}] | _rest] = ticks.lines
      assert {Float.round((1 - inside) * 17.28, 2), first_place} === {3.46, 0.0385}

      [%Giggly.Scene.Text{y: label_places, labels: label_texts}] = labels.primitives
      assert {label_places, label_texts} === {places, ~w(10 15 20 25 30 35)}
    end
  end

  # A legend titled `title` with a key for each of `labels`, drawn with no glyphs.
  defp legend(title, labels, theme) do
    keys = Enum.map(labels, fn label -> %{label: label, glyphs: []} end)
    Guide.draw(%Guide.Legend{}, %{title: title, keys: keys}, theme)
  end

  defp alpha_width(%{primitives: [legend]}),
    do: Enum.sum(for {:points, width} <- legend.widths, do: width)

  defp height(scene), do: Enum.sum(for {:points, height} <- scene.heights, do: height)
end
