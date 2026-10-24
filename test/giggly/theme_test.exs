defmodule Giggly.ThemeTest do
  use ExUnit.Case, async: true

  alias Giggly.Theme

  # Golden: every expected value here is ggplot2 4.0.3's in R 4.6.1: an element worked out by
  # `calc_element()` over a plot's built theme, its lengths converted into points by grid's
  # `convertUnit(..., "bigpts")`, and its line widths as R's graphics engine hands them to svglite,
  # `linewidth * .pt / 96 * 72`; a property `calc_element()` leaves unset as svglite draws it, at
  # grid's default. They move with theme_gray()'s elements, with how an element inherits from its
  # parent or a removal, and with how a unit is converted.

  describe "complete/1" do
    test "with no settings, it works out theme_gray()'s elements, each in points" do
      theme = complete(%{})

      assert {theme.axis_text_x_bottom.size, theme.axis_text_x_bottom.color,
              theme.axis_text_x_bottom.margin.top, theme.axis_ticks_length_x_bottom,
              theme.panel_grid_minor_x.line_width} ===
               {8.8, "#4D4D4D", 2.1917808219178085, 2.7397260273972606, 0.53348917322834644}
    end

    test "a text's size reaches every text that inherits it, as each one's share" do
      theme = complete(%{text: %{size: 20}})

      assert {theme.axis_text_x_bottom.size, theme.legend_text.size, theme.plot_title.size,
              theme.strip_text_x_top.size} === {16.0, 16.0, 24.0, 16.0}
    end

    test "a share of a size replaces the theme's own share, of the parent's size" do
      assert complete(%{axis_text: %{size: {:rel, 1.5}}}).axis_text_y_left.size === 16.5
    end

    test "a spacing reaches every length that inherits it, as each one's share" do
      theme = complete(%{spacing: {1, :cm}})

      assert {theme.axis_ticks_length_x_bottom, theme.panel_spacing_x, theme.legend_box_spacing,
              theme.legend_key_width} ===
               {14.173228346456693, 28.346456692913385, 56.69291338582677, 17.279999999999998}
    end

    test "the margins reach every margin that inherits them, side by side" do
      margins = %{top: {1, :pt}, right: {2, :pt}, bottom: {3, :pt}, left: {4, :pt}}

      assert complete(%{margins: margins}).plot_margin === %{
               top: 0.99626400996264008,
               right: 1.9925280199252802,
               bottom: 2.9887920298879207,
               left: 3.9850560398505603
             }
    end

    test "a share of a margin is that share of its parent's on each side" do
      margin = complete(%{legend_margin: {:rel, 2}}).legend_margin

      assert {margin.top, margin.left} === {10.958904109589042, 10.958904109589042}
    end

    test "a line's colour and width reach only the lines that leave them unset" do
      theme = complete(%{line: %{color: "#FF0000", linewidth: 2}})

      assert {theme.panel_grid_major_x, theme.panel_grid_minor_x.line_width,
              theme.axis_ticks_y_left} ===
               {%{
                  color: "#FFFFFF",
                  line_width: 4.2679133858267715,
                  line_end: :butt,
                  dashes: :none
                }, 2.1339566929133857,
                %{
                  color: "#333333",
                  line_width: 4.2679133858267715,
                  line_end: :butt,
                  dashes: :none
                }}
    end

    test "each unit is converted into points as grid converts it" do
      theme =
        complete(%{
          plot_margin: %{top: {1, :in}, right: {0, :pt}, bottom: {0, :pt}, left: {0, :pt}},
          panel_spacing: {3, :mm},
          legend_key_size: {2, :lines}
        })

      assert {theme.plot_margin.top, theme.panel_spacing_y, theme.legend_ticks_length,
              theme.legend_key_height} ===
               {72.0, 8.5039370078740149, 5.7600000000000016, 28.799999999999997}
    end

    test "a title's size is a number of points as a float, though given a whole number" do
      assert complete(%{axis_title: %{size: 12}}).axis_title_x_bottom.size === 12.0
    end

    # ggplot2's colour bar sets its own white ticks only where the theme leaves `legend.ticks`
    # unset (`replace_null()`), so a colour the theme gives every line does not reach them, and one
    # it gives the ticks takes the width of the theme's lines.
    test "a colour bar's ticks are white unless the theme sets them" do
      assert {complete(%{line: %{color: "#FF0000"}}).legend_ticks,
              complete(%{legend_ticks: %{color: "#000000"}}).legend_ticks} ===
               {%{color: "#FFFFFF", line_width: 0.375, line_end: :butt, dashes: :none},
                %{
                  color: "#000000",
                  line_width: 1.0669783464566929,
                  line_end: :butt,
                  dashes: :none
                }}
    end

    # Golden: ggplot2 4.0.3 draws a colour bar's ticks black and 2.13 points wide for
    # `legend.ticks = element_line(linewidth = 1)`, the colour every line inherits.
    test "a colour bar's ticks the theme sets without a colour take the lines' ink" do
      assert complete(%{legend_ticks: %{linewidth: 1}}).legend_ticks ===
               %{color: "#000000", line_width: 2.1339566929133857, line_end: :butt, dashes: :none}
    end
  end

  describe "complete/1 with elements removed" do
    test "a removed element takes every element that inherits from it" do
      theme = complete(%{axis_text: :none})

      assert {theme.axis_text_x_bottom, theme.axis_text_y_left, theme.axis_text_theta,
              theme.axis_text_r, theme.axis_title_x_bottom.size} ===
               {:none, :none, :none, :none, 11.0}
    end

    test "an element a setting gives skips its removed parent and inherits from the one above" do
      theme = complete(%{axis_text: :none, axis_text_x: %{color: "#FF0000"}})
      label = %{size: 11.0, color: "#FF0000", margin: sides(2.1917808219178085, 0, 0, 0)}

      assert {theme.axis_text_x_bottom, theme.axis_text_theta, theme.axis_text_y_left} ===
               {label, label, :none}
    end

    # A setting given after a removal replaces it, and the element takes what it leaves unset from
    # the complete theme's own, as ggplot2 lays a plot's settings over theme_gray() when no
    # complete theme is added.
    test "a setting given after a removal replaces it" do
      settings = Theme.merge(%{axis_text: :none}, %{axis_text: %{color: "#FF0000"}})

      assert {settings, complete(settings).axis_text_x_bottom.size} ===
               {%{axis_text: %{color: "#FF0000"}}, 8.8}
    end

    test "a removal given after a setting replaces it" do
      assert Theme.merge(%{axis_text: %{color: "#FF0000"}}, %{axis_text: :none}) ===
               %{axis_text: :none}
    end

    test "under a removed root, a property nothing above an element gives is grid's default" do
      lines = complete(%{line: :none, panel_grid_major: %{color: "#7F7F7F"}})
      rects = complete(%{rect: :none, legend_key: %{color: "#0000FF"}})
      texts = complete(%{text: :none, plot_subtitle: %{color: "#FF0000"}})

      assert {lines.panel_grid_major_x, lines.panel_grid_minor_x, lines.axis_ticks_x_bottom,
              rects.legend_key, rects.panel_background, texts.plot_subtitle} ===
               {%{color: "#7F7F7F", line_width: 0.75, line_end: :round, dashes: :none}, :none,
                :none, %{fill: "#EBEBEB", color: "#0000FF", line_width: 0.75, dashes: :none},
                :none,
                %{
                  size: 12.0,
                  color: "#FF0000",
                  margin: sides(0, 0, 5.4794520547945211, 0),
                  line_spacing: 17.28
                }}
    end

    # Each property an element of each kind may leave to grid: a text's colour and margin, a
    # title's line spacing too, a line's colour and end, and a rectangle's fill and border.
    test "every property nothing above an element under a removed root gives is grid's default" do
      text =
        complete(%{
          text: :none,
          axis_text: :none,
          axis_text_x: :none,
          axis_text_x_bottom: %{size: 10}
        })

      title = complete(%{text: :none, plot_tag: %{size: 15}})
      line = complete(%{line: :none, legend_ticks: %{linewidth: 1}})
      fill = complete(%{rect: :none, legend_background: %{color: "#FF0000"}})

      border =
        complete(%{rect: :none, strip_background: :none, strip_background_x: %{fill: "#FF0000"}})

      assert {text.axis_text_x_bottom, title.plot_tag, line.legend_ticks, fill.legend_background,
              border.strip_background_x} ===
               {%{size: 10.0, color: "#000000", margin: sides(0, 0, 0, 0)},
                %{
                  size: 15.0,
                  color: "#000000",
                  margin: sides(0, 0, 0, 0),
                  line_spacing: 21.599999999999998
                },
                %{
                  color: "#000000",
                  line_width: 2.1339566929133857,
                  line_end: :round,
                  dashes: :none
                }, %{fill: "#FFFFFF", color: "#FF0000", line_width: 0.75, dashes: :none},
                %{fill: "#FF0000", color: "#000000", line_width: 0.75, dashes: :none}}
    end

    # A share with no element above it at all is the share itself; a share of a parent that gives
    # none is nothing, so grid's default; and a share inherited from a parent whose own is still a
    # share is taken of it again, as ggplot2's `combine_elements()` works them out.
    test "a share with nothing above it to be a share of is worked out as R works it out" do
      lines = complete(%{line: :none, panel_grid: %{linewidth: {:rel, 2}}})

      assert {complete(%{text: :none, strip_text: %{size: {:rel, 2}}}).strip_text_x_top.size,
              {lines.panel_grid_major_x.line_width, lines.panel_grid_minor_x.line_width},
              complete(%{text: :none, axis_text_x: %{color: "#FF0000"}}).axis_text_x_bottom.size,
              complete(%{text: %{size: {:rel, 2}}}).axis_text_x_bottom.size,
              complete(%{text: :none, plot_title: %{size: {:rel, 2}}}).plot_title.size,
              complete(%{line: :none, axis_ticks_x: %{linewidth: {:rel, 2}}}).axis_ticks_x_bottom} ===
               {2.0, {4.2679133858267715, 2.1339566929133857}, 0.6400000000000001,
                2.5600000000000005, 12.0,
                %{color: "#333333", line_width: 0.75, line_end: :round, dashes: :none}}
    end

    # ggplot2's legend lays a text of its own over the root text to give its title and labels
    # their margins, which replaces a removed root, so they take theme_gray()'s look.
    test "a removed root text leaves a legend's title and labels in theme_gray()'s look" do
      theme = complete(%{text: :none})

      assert {theme.legend_title, theme.legend_text, theme.axis_title_x_bottom, theme.plot_title,
              theme.strip_text_x_top} ===
               {%{
                  size: 11.0,
                  color: "#000000",
                  margin: sides(0, 0, 5.4794520547945211, 0),
                  line_spacing: 11.88
                }, %{size: 8.8, color: "#000000", margin: sides(0, 0, 0, 5.4794520547945211)},
                :none, :none, :none}
    end

    test "a colour bar's own ticks skip a removed line, ending as grid ends a line" do
      assert complete(%{line: :none}).legend_ticks ===
               %{color: "#FFFFFF", line_width: 0.375, line_end: :round, dashes: :none}
    end

    test "the legends go right of the panels unless the theme puts them nowhere" do
      assert {complete(%{}).legend_position, complete(%{legend_position: :none}).legend_position} ===
               {:right, :none}
    end
  end

  # Golden: the dashes svglite writes for these line types in ggplot2 4.0.3's drawings (vdiffr
  # 1.0.9, R 4.6.1), two decimals of the values here: 5.69,5.69 for a dashed line half a
  # millimetre wide, 2.00,2.00 for a quarter-millimetre line dashed 2 and 2, 5.69,17.07 for a
  # dotted one 2 millimetres wide, and on rectangles 1.42,4.27 dotted and 2.85,8.54 twice as wide.
  describe "complete/1 with line types, ends and the panel" do
    test "a line is dashed in points, each length times its width in line-width units, or 1" do
      theme =
        complete(%{
          panel_grid_major: %{linetype: {4, 4}},
          panel_grid_minor: %{linetype: {2, 2}},
          axis_ticks: %{linetype: {1, 3}, linewidth: 2}
        })

      assert {theme.panel_grid_major_x.dashes, theme.panel_grid_minor_y.dashes,
              theme.axis_ticks_x_bottom.dashes} ===
               {[5.690551181102363, 5.690551181102363], [2.0, 2.0],
                [5.690551181102363, 17.071653543307086]}
    end

    test "a rectangle's border is dashed as a line is, whatever its colour" do
      theme =
        complete(%{
          rect: %{linetype: {1, 3}, color: "#000000"},
          panel_border: %{linewidth: {:rel, 2}}
        })

      assert {theme.panel_background, theme.panel_border.dashes} ===
               {%{
                  fill: "#EBEBEB",
                  color: :none,
                  line_width: 1.0669783464566929,
                  dashes: [1.4226377952755906, 4.2679133858267715]
                }, [2.8452755905511813, 8.535826771653543]}
    end

    # R's graphics engine draws no line of the blank line type, though the ticks keep their length,
    # and no border of it, though the rectangle is drawn.
    test "a line of the blank line type is marked blank, and a border of it is no border" do
      theme =
        complete(%{
          axis_ticks: %{linetype: :none},
          panel_border: %{color: "#FF0000", linetype: :none}
        })

      assert {theme.axis_ticks_y_left.dashes, theme.axis_ticks_length_y_left, theme.panel_border} ===
               {:blank, 2.7397260273972606,
                %{fill: "#FFFFFF", color: :none, line_width: 1.0669783464566929, dashes: :none}}
    end

    test "a line's end and a rectangle's fill are as a setting gives them, no fill too" do
      theme = complete(%{axis_line: %{lineend: :square}, panel_background: %{fill: :none}})

      assert {theme.axis_line_x_bottom.line_end, theme.panel_background.fill} === {:square, :none}
    end

    test "theme_gray() draws no axis lines or border, and the panel under the layers" do
      theme = complete(%{})

      assert {theme.axis_line_x_bottom, theme.axis_line_y_left, theme.axis_line_theta,
              theme.axis_line_r, theme.panel_border, theme.panel_ontop} ===
               {:none, :none, :none, :none, :none, false}
    end

    # An axis line a setting gives skips the removed `axis.line` and takes `line`'s look; the
    # border takes `rect`'s, its fill too, which the drawing never uses.
    test "an axis line or the border a setting gives inherits past theme_gray()'s removal" do
      theme = complete(%{axis_line_x: %{color: "#FF0000"}, panel_border: %{}, panel_ontop: true})

      red_line = %{
        color: "#FF0000",
        line_width: 1.0669783464566929,
        line_end: :butt,
        dashes: :none
      }

      assert {theme.axis_line_x_bottom, theme.axis_line_theta, theme.axis_line_y_left,
              theme.panel_border, theme.panel_ontop} ===
               {red_line, red_line, :none,
                %{
                  fill: "#FFFFFF",
                  color: "#000000",
                  line_width: 1.0669783464566929,
                  dashes: :none
                }, true}
    end
  end

  describe "merge/2" do
    test "a line's, a rectangle's or a text's properties replace only the ones given" do
      merged = Theme.merge(%{axis_text: %{color: "#FF0000"}}, %{axis_text: %{size: 12}})

      assert Map.take(complete(merged).axis_text_x_bottom, [:color, :size]) ===
               %{color: "#FF0000", size: 12.0}
    end

    test "a line's or a rectangle's properties replace only the ones given, as a text's do" do
      assert Theme.merge(
               %{panel_grid: %{color: "#FF0000"}, panel_background: %{fill: "#FF0000"}},
               %{panel_grid: %{linewidth: 2}, panel_background: %{color: :none}}
             ) === %{
               panel_grid: %{color: "#FF0000", linewidth: 2},
               panel_background: %{fill: "#FF0000", color: :none}
             }
    end

    test "a length or a margin replaces the one before whole" do
      assert Theme.merge(
               %{panel_spacing: {1, :cm}, legend_margin: %{top: {1, :pt}}},
               %{panel_spacing: {:rel, 2}, legend_margin: {:rel, 3}}
             ) === %{panel_spacing: {:rel, 2}, legend_margin: {:rel, 3}}
    end
  end

  defp complete(settings), do: Theme.complete(%{complete: :gray, settings: settings})

  # A margin in points, top, right, bottom and left, each a float.
  defp sides(top, right, bottom, left),
    do: %{top: top / 1, right: right / 1, bottom: bottom / 1, left: left / 1}
end
