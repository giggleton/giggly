defmodule Giggly.GuideTest do
  use ExUnit.Case, async: true

  alias Giggly.{Coord, Guide, Theme}

  describe "Axis.draw/3 and Axis.titles/4" do
    test "an axis with no breaks and a title of :none draw nothing and take no room" do
      coord = %Coord.Cartesian{}
      params = Coord.panel_params(coord, {{0.0, 1.0}, [], []}, {{0.0, 1.0}, [], []})
      theme = Theme.complete(%{complete: :none, settings: %{}})

      assert {Guide.Axis.draw(coord, params, theme),
              Guide.Axis.titles(coord, params, %{x: :none, y: :none}, theme)} ===
               {%{bottom: {0.0, []}, left: {0.0, []}}, %{bottom: {0.0, []}, left: {0.0, []}}}
    end

    # Golden: in ggplot2 4.0.3 (R 4.6.1), `scale_x_continuous(labels = NULL)` leaves the x axis
    # 2.74 points deep, its ticks' length, where its labels make it 13.37.
    test "an axis with no labels draws its ticks alone and reaches only as far as they do" do
      coord = %Coord.Cartesian{}
      breaks = [{2.0, :none}, {3.0, :none}]
      params = Coord.panel_params(coord, {{1.0, 4.0}, breaks, []}, {{1.0, 4.0}, breaks, []})
      theme = Theme.complete(%{complete: :none, settings: %{}})
      %{bottom: {height, bottom}, left: {width, left}} = Guide.Axis.draw(coord, params, theme)

      assert {Float.round(height, 2), width == height,
              Enum.map(bottom ++ left, fn primitive -> primitive.__struct__ end)} ===
               {2.74, true, [Giggly.Scene.Polylines, Giggly.Scene.Polylines]}
    end

    test "a radial panel's background is the polygon round its disc, its border opaque" do
      coord = %Coord.Radial{}
      params = Coord.panel_params(coord, {{1.0, 4.0}, [], []}, {{1.0, 4.0}, [], []})

      theme =
        Theme.complete(%{complete: :none, settings: %{panel_background: %{color: "#FF0000"}}})

      assert [%Giggly.Scene.Polygons{color: ["#FF0000"], color_opacity: [1.0]} | _lines] =
               Guide.Grid.draw(coord, params, theme)
    end

    test "an angle axis whose labels the theme removes draws its ticks alone" do
      coord = %Coord.Radial{}
      breaks = [{2.0, "2"}, {3.0, "3"}]
      params = Coord.panel_params(coord, {{1.0, 4.0}, breaks, []}, {{1.0, 4.0}, [], []})
      theme = Theme.complete(%{complete: :none, settings: %{axis_text_theta: :none}})

      assert coord
             |> Guide.Axis.draw_inside(params, theme)
             |> Enum.map(fn primitive -> primitive.__struct__ end) === [Giggly.Scene.Polylines]
    end

    # Golden: ggplot2 4.0.3 (vdiffr 1.0.9, R 4.6.1) draws no tick of `element_line(linetype =
    # "blank")` and leaves the panel where solid ticks leave it, as R's graphics engine draws no
    # line of the blank line type.
    test "ticks, an axis's line and grid lines of the blank line type draw nothing, the ticks keeping their room" do
      coord = %Coord.Cartesian{}
      breaks = [{2.0, "2"}, {3.0, "3"}]
      params = Coord.panel_params(coord, {{1.0, 4.0}, breaks, []}, {{1.0, 4.0}, breaks, []})
      solid = Theme.complete(%{complete: :none, settings: %{}})

      blank =
        Theme.complete(%{
          complete: :none,
          settings: %{
            axis_ticks: %{linetype: :none},
            axis_line: %{linetype: :none},
            panel_grid: %{linetype: :none}
          }
        })

      %{bottom: {solid_height, _bottom}, left: {solid_width, _left}} =
        Guide.Axis.draw(coord, params, solid)

      %{bottom: {height, bottom}, left: {width, left}} = Guide.Axis.draw(coord, params, blank)

      assert {height === solid_height, width === solid_width, structs(bottom), structs(left),
              structs(Guide.Grid.draw(coord, params, blank))} ===
               {true, true, [Giggly.Scene.Text], [Giggly.Scene.Text], [Giggly.Scene.Rect]}
    end

    test "round a radial panel, ticks and a line of the blank line type draw nothing" do
      coord = %Coord.Radial{}
      breaks = [{2.0, "2"}, {3.0, "3"}]
      params = Coord.panel_params(coord, {{1.0, 4.0}, breaks, []}, {{1.0, 4.0}, [], []})

      theme =
        Theme.complete(%{
          complete: :none,
          settings: %{axis_ticks: %{linetype: :none}, axis_line: %{linetype: :none}}
        })

      assert coord
             |> Guide.Axis.draw_inside(params, theme)
             |> structs() === [Giggly.Scene.Text, Giggly.Scene.Text]
    end

    test "an axis around a radial panel with no labels draws its ticks alone" do
      coord = %Coord.Radial{}
      breaks = [{2.0, :none}, {3.0, :none}]
      params = Coord.panel_params(coord, {{1.0, 4.0}, breaks, []}, {{1.0, 4.0}, [], []})

      assert coord
             |> Guide.Axis.draw_inside(params, Theme.complete(%{complete: :none, settings: %{}}))
             |> Enum.map(fn primitive -> primitive.__struct__ end) === [Giggly.Scene.Polylines]
    end
  end

  # Golden: the legend boxes ggplot2 4.0.3 draws through vdiffr 1.0.9 (R 4.6.1) for `alpha = year`
  # on mpg, keys 2000 to 2008 by 2, and for a column named `a_long_column_name`, keys 2.5, 5.0 and
  # 7.5: 53.30 by 112.69 points, and 119.22 by 78.13. They move with the theme's legend values or
  # how a legend is laid out.
  # Golden: R's `rotate_just()` and the width and height of ggplot2 4.0.3's `titleGrob()` under
  # vdiffr 1.0.9's device (R 4.6.1) for "a longer label" at 8.8 points, `hjust = 0.2, vjust =
  # 0.7`, margins of 1, 2, 3 and 4 points: one angle in each quarter turn, one just short of the
  # first quarter turn and of a whole turn, where a turn is read a quarter at a time, and one just
  # below 0, which R's `%% 360` reads as 0 at the second step. It moves with how a text is
  # anchored or measured.
  describe "Parts, the rule every text is placed and measured by" do
    test "a text is anchored at its justification turned a quarter turn at a time, and measured turned" do
      margin = %{top: 1.0, right: 2.0, bottom: 3.0, left: 4.0}

      measured =
        Enum.map([30.0, 120.0, 210.0, 300.0, 89.5, 359.5, -1.0e-14], fn angle ->
          look = %{size: 8.8, angle: angle, hjust: 0.2, vjust: 0.7, margin: margin}
          {across, up} = Guide.Parts.turned_justification(look)
          {width, height} = Guide.Parts.extent(["a longer label"], look)
          rounded = fn number -> Float.round(number, 9) end

          {rounded.(across), rounded.(up), rounded.(4.0 + width + 2.0),
           rounded.(1.0 + height + 3.0)}
        end)

      assert measured === [
               {0.2, 0.7, 55.699669619, 37.245392899},
               {0.3, 0.2, 39.245392899, 53.699669619},
               {0.8, 0.3, 55.699669619, 37.245392899},
               {0.7, 0.8, 39.245392899, 53.699669619},
               {0.2, 0.7, 14.343823445, 56.903739759},
               {0.7, 0.8, 58.903739759, 12.343823445},
               {0.2, 0.7, 58.83696, 11.88304}
             ]
    end

    # Golden: the place ggplot2 4.0.3's `titleGrob()` gives "a" at 30 degrees, `hjust = 0.2, vjust
    # = 0.7`, margins of 1, 2, 3 and 4 points, counting its margins across (`margin_x`), as a y
    # axis's title and labels do, up (`margin_y`), as an x axis's do, or both: across, `0.2npc -
    # 0.4 + 3.2` points and up `0.7npc`, or `0.2npc` and `0.7npc - 0.7 + 0.9` points.
    test "a text counts only the margins it is told to, moving its anchor by them" do
      look = %{
        size: 8.8,
        angle: 30.0,
        hjust: 0.2,
        vjust: 0.7,
        margin: %{top: 1.0, right: 2.0, bottom: 3.0, left: 4.0}
      }

      anchors =
        Enum.map([:across, :up, :both], fn counted ->
          {{across, up}, {across_offset, up_offset}} = Guide.Parts.anchor(look, counted)
          rounded = fn number -> Float.round(number, 9) end
          {across, up, rounded.(across_offset), rounded.(up_offset)}
        end)

      assert anchors === [{0.2, 0.7, 2.8, +0.0}, {0.2, 0.7, +0.0, 0.2}, {0.2, 0.7, 2.8, 0.2}]
    end

    # A title any wider than the keys and labels below it adds the rest of its room either side of
    # them, split by its justification, as ggplot2's `add_title()` adds columns, here a fifth left
    # of them and four fifths right; so the legend is as wide as the title and its margins.
    test "a title even a fraction of a point wider than the keys leaves its room either side" do
      look = %{
        size: 11.0,
        color: "#000000",
        opacity: 1.0,
        family: "",
        face: :plain,
        angle: 0.0,
        hjust: 0.2,
        vjust: 0.5,
        margin: %{top: 0.0, right: 0.0, bottom: 0.0, left: 0.0},
        line_spacing: 11.88
      }

      {title_width, _height} = Guide.Parts.extent(["year"], look)

      {widths, _heights, first, _cells} =
        Guide.Parts.title_above("year", look, [title_width - 0.5])

      [left, grid, right] = Enum.map(widths, fn width -> Float.round(width, 9) end)

      assert {first, left, grid + left + right, right} ===
               {3, 0.1, Float.round(title_width, 9), 0.4}
    end
  end

  describe "draw/3 for a legend" do
    test "a legend is its margin around a title above a key for each label" do
      keys =
        Enum.map(~w(2000 2002 2004 2006 2008), fn label ->
          %{label: label, glyphs: [], sizes: []}
        end)

      {width, scene} =
        Guide.draw(
          %Guide.Legend{},
          %{title: "year", keys: keys, direction: :vertical},
          Theme.complete(%{complete: :none, settings: %{}})
        )

      height = height(scene)

      assert {Float.round(width, 2), Float.round(height, 2)} === {53.3, 112.69}
    end

    test "a title wider than its keys and labels widens the legend to it" do
      keys = Enum.map(~w(2.5 5.0 7.5), fn label -> %{label: label, glyphs: [], sizes: []} end)

      {width, scene} =
        Guide.draw(
          %Guide.Legend{},
          %{title: "a_long_column_name", keys: keys, direction: :vertical},
          Theme.complete(%{complete: :none, settings: %{}})
        )

      height = height(scene)

      assert {Float.round(width, 2), Float.round(height, 2)} === {119.22, 78.13}
    end

    # Golden: the merged size and colour legend of test/golden/merged_rows.svg, ggplot2 4.0.3's
    # through vdiffr 1.0.9: its keys' column 34.02 points wide, as wide as its widest point, and its
    # rows 17.28, 21.71, 28.53 and 34.02 points tall, each as tall as its own point or the theme's
    # key, as `measure_legend_keys()` sizes them.
    test "the keys' column is as wide as the widest glyph, and each row as tall as its tallest" do
      sizes = [[{11.34, 11.34}], [{21.71, 21.71}], [{28.53, 28.53}, {5.0, 5.0}], [{34.02, 34.02}]]

      keys =
        Enum.zip_with(~w(4 5 6 8), sizes, fn label, glyph_sizes ->
          %{label: label, glyphs: [], sizes: glyph_sizes}
        end)

      {_width, scene} =
        Guide.draw(
          %Guide.Legend{},
          %{title: "cyl", keys: keys, direction: :vertical},
          Theme.complete(%{complete: :none, settings: %{}})
        )

      [_margin, {:points, key_column} | _labels] = scene.widths

      # The key rows follow the margin and the title's row, a row of no spacing after each.
      key_rows =
        scene.heights
        |> Enum.slice(2..-2//2)
        |> Enum.map(fn {:points, height} -> Float.round(height, 2) end)

      assert {key_column, key_rows} === {34.02, [17.28, 21.71, 28.53, 34.02]}
    end

    # Golden: with `legend.text = element_blank()`, ggplot2 4.0.3's legend for mpg's `colour = drv`
    # through vdiffr 1.0.9 is 28.24 by 78.13 points, its labels and their margins gone.
    test "labels the theme removes draw nothing and take no room" do
      theme = Theme.complete(%{complete: :none, settings: %{legend_text: :none}})
      {width, scene} = legend("drv", ~w(4 f r), theme)

      texts =
        for cell <- scene.cells, %Giggly.Scene.Text{labels: labels} <- cell.primitives, do: labels

      legend_height = height(scene)

      assert {Float.round(width, 2), Float.round(legend_height, 2), texts} ===
               {28.24, 78.13, [["drv"]]}
    end
  end

  # Golden: the legends ggplot2 4.0.3 stacks for mpg's `alpha = cyl` above `colour = class`
  # (`guides(order =)`), through vdiffr 1.0.9 (R 4.6.1), test/golden/point_colour_alpha.R: the alpha
  # legend's background 38.61 by 112.69 points, then 10.96 points of `legend.spacing.y`, then the
  # colour legend's 81.18 by 147.25, both at one left edge, in a box with no margin.
  describe "Box.draw/3" do
    test "legends stack in the order given, as wide as the widest, each hung from the box's left" do
      theme = Theme.complete(%{complete: :none, settings: %{}})
      alpha = legend("cyl", ~w(4 5 6 7 8), theme)
      colour = legend("class", ~w(2seater compact midsize minivan pickup subcompact suv), theme)

      {width, height, box} = Guide.Box.draw([alpha, colour], :vertical, theme)

      [alpha_legend, colour_legend] = box.cells
      {:at, place, justification, {alpha_width, alpha_height}} = alpha_legend.hang
      {:at, _place, _justification, {colour_width, colour_height}} = colour_legend.hang

      assert {Float.round(width, 2), Float.round(height, 2),
              Enum.map(box.heights, fn {:points, height} -> Float.round(height, 2) end)} ===
               {81.18, 270.9, [0.0, 112.69, 10.96, 147.25, 0.0]}

      assert {alpha_legend.rows, colour_legend.rows, place, justification, colour_width} ===
               {2..2, 4..4, {0.0, 1.0}, {0.0, 1.0}, width}

      assert {Float.round(alpha_width, 2), Float.round(alpha_height, 2),
              Float.round(colour_height, 2)} === {38.61, 112.69, 147.25}
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
          %{label: label, place: place, glyphs: [], sizes: []}
        end)

      decor = [{0.0, "#132B43"}, {1.0, "#56B1F7"}]
      theme = Theme.complete(%{complete: :none, settings: %{}})

      {width, scene} =
        Guide.draw(
          %Guide.Colorbar{bins: 15},
          %{title: "cty", keys: keys, decor: decor, direction: :vertical},
          theme
        )

      scene_height = height(scene)
      assert {Float.round(width, 2), Float.round(scene_height, 2)} === {43.51, 112.69}

      [_background, _title, bar, labels] = scene.cells
      [%Giggly.Scene.Gradient{stops: ^decor}, ticks] = bar.primitives

      {:points, bar_width} = Enum.at(scene.widths, 1)
      {:points, bar_length} = Enum.at(scene.heights, 2)
      assert {Float.round(bar_width, 2), Float.round(bar_length, 2)} === {17.28, 86.4}

      assert {Float.round(ticks.stroke_width, 2), length(ticks.lines), ticks.color} ===
               {0.38, 12, List.duplicate("#FFFFFF", 12)}

      [[{inside, first_place}, {1.0, first_place}] | _rest] = ticks.lines
      assert {Float.round((1 - inside) * 17.28, 2), first_place} === {3.46, 0.0385}

      [%Giggly.Scene.Text{y: label_places, labels: label_texts}] = labels.primitives
      assert {label_places, label_texts} === {places, ~w(10 15 20 25 30 35)}
    end

    # Golden: with `legend.title`, `legend.text`, `legend.ticks` and `legend.background` set to
    # `element_blank()`, ggplot2 4.0.3's legend box for the same scale is 28.24 by 97.36 points,
    # its margin around the bar alone.
    test "a title, labels, ticks and background the theme removes draw nothing and take no room" do
      keys = [%{label: "10", place: 0.0385, glyphs: [], sizes: []}]

      theme =
        Theme.complete(%{
          complete: :none,
          settings: %{
            legend_title: :none,
            legend_text: :none,
            legend_ticks: :none,
            legend_background: :none
          }
        })

      {width, scene} =
        Guide.draw(
          %Guide.Colorbar{bins: 15},
          %{
            title: "cty",
            keys: keys,
            decor: [{0.0, "#132B43"}, {1.0, "#56B1F7"}],
            direction: :vertical
          },
          theme
        )

      scene_height = height(scene)

      assert {Float.round(width, 2), Float.round(scene_height, 2),
              Enum.map(scene.cells, fn cell ->
                Enum.map(cell.primitives, fn primitive -> primitive.__struct__ end)
              end)} ===
               {28.24, 97.36, [[Giggly.Scene.Gradient]]}
    end

    test "ticks of the blank line type draw nothing across the bar" do
      keys = [%{label: "10", place: 0.0385, glyphs: [], sizes: []}]
      theme = Theme.complete(%{complete: :none, settings: %{legend_ticks: %{linetype: :none}}})

      {_width, scene} =
        Guide.draw(
          %Guide.Colorbar{bins: 15},
          %{
            title: "cty",
            keys: keys,
            decor: [{0.0, "#132B43"}, {1.0, "#56B1F7"}],
            direction: :vertical
          },
          theme
        )

      [_background, _title, bar, _labels] = scene.cells
      assert structs(bar.primitives) === [Giggly.Scene.Gradient]
    end
  end

  # Golden: the legends' backgrounds ggplot2 4.0.3 draws above the panels through vdiffr 1.0.9
  # (R 4.6.1): mpg's `colour = hwy` as a colour bar in its gradient form, 122.41 by 41.60 points,
  # its bar 86.40 by 17.28 inside the 5.48-point margin, so the title's column 25.05 wide and the
  # labels' row 13.36 deep; with `legend.title` and `legend.text` set to `element_blank()`, 97.36
  # by 28.24, the bar alone in its margin; and mpg's `colour = drv` as a legend with its title
  # removed, 100.47 by 28.24. They move with how a guide running across is laid out.
  describe "draw/3 for guides running across" do
    test "a colour bar is its margin round a title left of a bar five keys long, labelled below" do
      places = [0.0625, 0.375, 0.6875, 1.0]

      keys =
        Enum.zip_with(~w(20 30 40 50), places, fn label, place ->
          %{label: label, place: place, glyphs: [], sizes: []}
        end)

      decor = [{0.0, "#132B43"}, {1.0, "#56B1F7"}]

      {width, scene} =
        Guide.draw(
          %Guide.Colorbar{bins: 15},
          %{title: "hwy", keys: keys, decor: decor, direction: :horizontal},
          Theme.complete(%{complete: :none, settings: %{}})
        )

      [_background, _title, bar, labels] = scene.cells
      [%Giggly.Scene.Gradient{direction: :across}, ticks] = bar.primitives
      [%Giggly.Scene.Text{x: label_places, hjust: hjust}] = labels.primitives
      rounded = fn sizes -> Enum.map(sizes, fn {:points, size} -> Float.round(size, 2) end) end
      scene_height = height(scene)

      assert {Float.round(width, 2), Float.round(scene_height, 2), rounded.(scene.widths),
              rounded.(scene.heights)} ===
               {122.41, 41.6, [5.48, 25.05, 86.4, 5.48], [5.48, 0.0, 17.28, 13.36, 0.0, 5.48]}

      [[{first_place, inside}, {first_place, +0.0}] | _rest] = ticks.lines
      [{top_place, top_inside}, {top_place, 1.0}] = Enum.at(ticks.lines, 4)

      assert {first_place, Float.round(inside * 17.28, 2), top_place,
              Float.round((1 - top_inside) * 17.28, 2), label_places, hjust} ===
               {0.0625, 3.46, 0.0625, 3.46, places, List.duplicate(0.5, 4)}
    end

    # Golden: ggplot2 4.0.3's colour bar below the panels for mpg's `colour = cty`, with
    # `legend.text = element_text(margin = margin(t = 2, b = 4))`, through vdiffr 1.0.9: its
    # background 116.90 by 42.10 points, the labels' row as deep as the labels and both margins.
    test "the labels below a colour bar running across count their margins above and below" do
      places = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]

      keys =
        Enum.zip_with(~w(10 15 20 25 30 35), places, fn label, place ->
          %{label: label, place: place, glyphs: [], sizes: []}
        end)

      theme =
        Theme.complete(%{
          complete: :none,
          settings: %{legend_text: %{margin: %{top: {2, :pt}, bottom: {4, :pt}}}}
        })

      {width, scene} =
        Guide.draw(
          %Guide.Colorbar{bins: 15},
          %{
            title: "cty",
            keys: keys,
            decor: [{0.0, "#132B43"}, {1.0, "#56B1F7"}],
            direction: :horizontal
          },
          theme
        )

      scene_height = height(scene)
      assert {Float.round(width, 2), Float.round(scene_height, 2)} === {116.9, 42.1}
    end

    test "a colour bar with its title and labels removed is the bar alone in its margin" do
      keys = [%{label: "20", place: 0.0625, glyphs: [], sizes: []}]

      theme =
        Theme.complete(%{complete: :none, settings: %{legend_title: :none, legend_text: :none}})

      {width, scene} =
        Guide.draw(
          %Guide.Colorbar{bins: 15},
          %{
            title: "hwy",
            keys: keys,
            decor: [{0.0, "#132B43"}, {1.0, "#56B1F7"}],
            direction: :horizontal
          },
          theme
        )

      scene_height = height(scene)

      assert {Float.round(width, 2), Float.round(scene_height, 2),
              Enum.map(scene.cells, fn cell -> structs(cell.primitives) end)} ===
               {97.36, 28.24,
                [[Giggly.Scene.Rect], [Giggly.Scene.Gradient, Giggly.Scene.Polylines]]}
    end

    test "a legend with its title removed is its keys and labels in a row" do
      theme = Theme.complete(%{complete: :none, settings: %{legend_title: :none}})
      keys = Enum.map(~w(4 f r), fn label -> %{label: label, glyphs: [], sizes: []} end)

      {width, scene} =
        Guide.draw(%Guide.Legend{}, %{title: "drv", keys: keys, direction: :horizontal}, theme)

      scene_height = height(scene)
      assert {Float.round(width, 2), Float.round(scene_height, 2)} === {100.47, 28.24}
    end
  end

  # The kind of each primitive drawn, in drawing order.
  defp structs(primitives), do: Enum.map(primitives, fn primitive -> primitive.__struct__ end)

  # A legend titled `title` with a key for each of `labels`, drawn with no glyphs.
  defp legend(title, labels, theme) do
    keys = Enum.map(labels, fn label -> %{label: label, glyphs: [], sizes: []} end)
    Guide.draw(%Guide.Legend{}, %{title: title, keys: keys, direction: :vertical}, theme)
  end

  defp height(scene), do: Enum.sum(for {:points, height} <- scene.heights, do: height)
end
