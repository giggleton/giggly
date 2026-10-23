defmodule Giggly.ThemeTest do
  use ExUnit.Case, async: true

  alias Giggly.Theme

  # Golden: every expected value here is ggplot2 4.0.3's in R 4.6.1: an element worked out by
  # `calc_element()` over a plot's built theme, its lengths converted into points by grid's
  # `convertUnit(..., "bigpts")`, and its line widths as R's graphics engine hands them to svglite,
  # `linewidth * .pt / 96 * 72`. They move with theme_gray()'s elements, with how an element
  # inherits from its parent, and with how a unit is converted.

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
               {%{color: "#FFFFFF", line_width: 4.2679133858267715}, 2.1339566929133857,
                %{color: "#333333", line_width: 4.2679133858267715}}
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
               {%{color: "#FFFFFF", line_width: 0.375},
                %{color: "#000000", line_width: 1.0669783464566929}}
    end

    # Golden: ggplot2 4.0.3 draws a colour bar's ticks black and 2.13 points wide for
    # `legend.ticks = element_line(linewidth = 1)`, the colour every line inherits.
    test "a colour bar's ticks the theme sets without a colour take the lines' ink" do
      assert complete(%{legend_ticks: %{linewidth: 1}}).legend_ticks ===
               %{color: "#000000", line_width: 2.1339566929133857}
    end
  end

  describe "merge/2" do
    test "a line's, a rectangle's or a text's properties replace only the ones given" do
      merged = Theme.merge(%{axis_text: %{color: "#FF0000"}}, %{axis_text: %{size: 12}})

      assert Map.take(complete(merged).axis_text_x_bottom, [:color, :size]) ===
               %{color: "#FF0000", size: 12.0}
    end

    test "a length or a margin replaces the one before whole" do
      assert Theme.merge(
               %{spacing: {1, :cm}, margins: %{top: {1, :pt}}},
               %{spacing: {:rel, 2}, margins: {:rel, 3}}
             ) === %{spacing: {:rel, 2}, margins: {:rel, 3}}
    end
  end

  defp complete(settings), do: Theme.complete(%{complete: :gray, settings: settings})
end
