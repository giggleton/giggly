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

      assert {theme.axis_text_x_bottom.size, theme.legend_text_right.size, theme.plot_title.size,
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
                  opacity: 1.0,
                  line_width: 4.2679133858267715,
                  line_end: :butt,
                  dashes: :none
                }, 2.1339566929133857,
                %{
                  color: "#333333",
                  opacity: 1.0,
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
               {%{
                  color: "#FFFFFF",
                  opacity: 1.0,
                  line_width: 0.375,
                  line_end: :butt,
                  dashes: :none
                },
                %{
                  color: "#000000",
                  opacity: 1.0,
                  line_width: 1.0669783464566929,
                  line_end: :butt,
                  dashes: :none
                }}
    end

    # Golden: ggplot2 4.0.3 draws a colour bar's ticks black and 2.13 points wide for
    # `legend.ticks = element_line(linewidth = 1)`, the colour every line inherits.
    test "a colour bar's ticks the theme sets without a colour take the lines' ink" do
      assert complete(%{legend_ticks: %{linewidth: 1}}).legend_ticks ===
               %{
                 color: "#000000",
                 opacity: 1.0,
                 line_width: 2.1339566929133857,
                 line_end: :butt,
                 dashes: :none
               }
    end
  end

  # ggplot2 4.0.3's `calc_element()` of each text Giggly draws, under theme_gray() and
  # theme_void(); every other complete theme gives theme_gray()'s.
  describe "complete/1, text's face, angle and justification" do
    test "each complete theme's texts are plain, level or turned, and justified as R's" do
      looks = fn theme, leaves ->
        Enum.map(leaves, fn leaf ->
          %{face: face, angle: angle, hjust: hjust, vjust: vjust} = Map.fetch!(theme, leaf)
          {leaf, face, angle, hjust, vjust}
        end)
      end

      titles =
        [:legend_title_top, :strip_text_x_top, :plot_title, :plot_subtitle] ++
          [:plot_caption, :plot_tag]

      gray_titles = [
        {:legend_title_top, :plain, 0.0, 0.0, 0.5},
        {:strip_text_x_top, :plain, 0.0, 0.5, 0.5},
        {:plot_title, :plain, 0.0, 0.0, 1.0},
        {:plot_subtitle, :plain, 0.0, 0.0, 1.0},
        {:plot_caption, :plain, 0.0, 1.0, 1.0},
        {:plot_tag, :plain, 0.0, 0.5, 0.5}
      ]

      axes =
        [:axis_text_x_bottom, :axis_text_y_left, :axis_text_r, :axis_text_theta] ++
          [:axis_title_x_bottom, :axis_title_y_left]

      gray = complete(%{})
      void = chosen(:void)

      assert {looks.(gray, axes ++ titles), looks.(void, titles)} ===
               {[
                  {:axis_text_x_bottom, :plain, 0.0, 0.5, 1.0},
                  {:axis_text_y_left, :plain, 0.0, 1.0, 0.5},
                  {:axis_text_r, :plain, 0.0, 0.5, 0.5},
                  {:axis_text_theta, :plain, 0.0, 0.5, 1.0},
                  {:axis_title_x_bottom, :plain, 0.0, 0.5, 1.0},
                  {:axis_title_y_left, :plain, 90.0, 0.5, 1.0}
                  | gray_titles
                ], gray_titles}
    end

    # ggplot2's legend lays a text of its own over the root text, its justification for the side
    # its title or labels are drawn on, so the root's justification never reaches them, but its
    # face and angle do, as R's `calc_element()` of the overlaid theme shows.
    test "the root text's justification never reaches a legend's title and labels; its face and angle do" do
      theme = complete(%{text: %{hjust: 1, vjust: 0, face: :bold, angle: 10}})

      looks =
        Enum.map(
          [:legend_title_top, :legend_title_left, :legend_text_right, :legend_text_bottom] ++
            [:axis_title_x_bottom, :strip_text_x_top],
          fn leaf ->
            %{face: face, angle: angle, hjust: hjust, vjust: vjust} = Map.fetch!(theme, leaf)
            {face, angle, hjust, vjust}
          end
        )

      assert looks === [
               {:bold, 10.0, 0.0, 0.5},
               {:bold, 10.0, 0.0, 0.5},
               {:bold, 10.0, 0.0, 0.5},
               {:bold, 10.0, 0.5, 1.0},
               {:bold, 10.0, 1.0, 1.0},
               {:bold, 10.0, 1.0, 0.0}
             ]
    end

    # R's graphics engine spaces a text's lines `lineheight` times 1.2 times its size apart: the
    # title's 1.5 at 13.2 points, the axis title's 0 at 11, the subtitle's theme_gray() 0.9 at 11,
    # as test/golden/theme_text_lineheight.svg draws them, checked against R.
    test "a title's line height spaces its lines, a share of 1.2 times its size" do
      theme = complete(%{plot_title: %{lineheight: 1.5}, axis_title: %{lineheight: 0}})

      assert {theme.plot_title.line_spacing, theme.axis_title_x_bottom.line_spacing,
              theme.plot_subtitle.line_spacing} === {23.759999999999998, 0.0, 11.88}
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

      label = %{
        size: 11.0,
        color: "#FF0000",
        opacity: 1.0,
        face: :plain,
        angle: 0.0,
        hjust: 0.5,
        vjust: 1.0,
        margin: sides(2.1917808219178085, 0, 0, 0)
      }

      assert {theme.axis_text_x_bottom, theme.axis_text_theta, theme.axis_text_y_left} ===
               {label, label, :none}
    end

    # A setting given after a removal replaces it, and the element takes what it leaves unset from
    # the complete theme's own, as ggplot2 lays a plot's settings over theme_gray() when no
    # complete theme is added.
    test "a setting given after a removal replaces it" do
      settings = merge(%{axis_text: :none}, %{axis_text: %{color: "#FF0000"}})

      assert {settings, complete(settings).axis_text_x_bottom.size} ===
               {%{axis_text: %{color: "#FF0000"}}, 8.8}
    end

    test "a removal given after a setting replaces it" do
      assert merge(%{axis_text: %{color: "#FF0000"}}, %{axis_text: :none}) ===
               %{axis_text: :none}
    end

    test "under a removed root, a property nothing above an element gives is grid's default" do
      lines = complete(%{line: :none, panel_grid_major: %{color: "#7F7F7F"}})
      rects = complete(%{rect: :none, legend_key: %{color: "#0000FF"}})
      texts = complete(%{text: :none, plot_subtitle: %{color: "#FF0000"}})

      assert {lines.panel_grid_major_x, lines.panel_grid_minor_x, lines.axis_ticks_x_bottom,
              rects.legend_key, rects.panel_background, texts.plot_subtitle} ===
               {%{
                  color: "#7F7F7F",
                  opacity: 1.0,
                  line_width: 0.75,
                  line_end: :round,
                  dashes: :none
                }, :none, :none,
                %{
                  fill: "#EBEBEB",
                  fill_opacity: 1.0,
                  color: "#0000FF",
                  color_opacity: 1.0,
                  line_width: 0.75,
                  dashes: :none
                }, :none,
                %{
                  size: 12.0,
                  color: "#FF0000",
                  opacity: 1.0,
                  face: :plain,
                  angle: 0.0,
                  hjust: 0.0,
                  vjust: 1.0,
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
               {%{
                  size: 10.0,
                  color: "#000000",
                  opacity: 1.0,
                  face: :plain,
                  angle: 0.0,
                  hjust: 0.5,
                  vjust: 0.5,
                  margin: sides(0, 0, 0, 0)
                },
                %{
                  size: 15.0,
                  color: "#000000",
                  opacity: 1.0,
                  face: :plain,
                  angle: 0.0,
                  hjust: 0.5,
                  vjust: 0.5,
                  margin: sides(0, 0, 0, 0),
                  line_spacing: 21.599999999999998
                },
                %{
                  color: "#000000",
                  opacity: 1.0,
                  line_width: 2.1339566929133857,
                  line_end: :round,
                  dashes: :none
                },
                %{
                  fill: "#FFFFFF",
                  fill_opacity: 1.0,
                  color: "#FF0000",
                  color_opacity: 1.0,
                  line_width: 0.75,
                  dashes: :none
                },
                %{
                  fill: "#FF0000",
                  fill_opacity: 1.0,
                  color: "#000000",
                  color_opacity: 1.0,
                  line_width: 0.75,
                  dashes: :none
                }}
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
                %{
                  color: "#333333",
                  opacity: 1.0,
                  line_width: 0.75,
                  line_end: :round,
                  dashes: :none
                }}
    end

    # ggplot2's legend lays a text of its own over the root text to give its title and labels
    # their margins, which replaces a removed root, so they take theme_gray()'s look.
    test "a removed root text leaves a legend's title and labels in theme_gray()'s look" do
      theme = complete(%{text: :none})

      assert {theme.legend_title_top, theme.legend_text_right, theme.axis_title_x_bottom,
              theme.plot_title, theme.strip_text_x_top} ===
               {%{
                  size: 11.0,
                  color: "#000000",
                  opacity: 1.0,
                  face: :plain,
                  angle: 0.0,
                  hjust: 0.0,
                  vjust: 0.5,
                  margin: sides(0, 0, 5.4794520547945211, 0),
                  line_spacing: 11.88
                },
                %{
                  size: 8.8,
                  color: "#000000",
                  opacity: 1.0,
                  face: :plain,
                  angle: 0.0,
                  hjust: 0.0,
                  vjust: 0.5,
                  margin: sides(0, 0, 0, 5.4794520547945211)
                }, :none, :none, :none}
    end

    test "a colour bar's own ticks skip a removed line, ending as grid ends a line" do
      assert complete(%{line: :none}).legend_ticks ===
               %{
                 color: "#FFFFFF",
                 opacity: 1.0,
                 line_width: 0.375,
                 line_end: :round,
                 dashes: :none
               }
    end

    test "the legends go right of the panels unless the theme puts them nowhere" do
      assert {complete(%{}).legend_position, complete(%{legend_position: :none}).legend_position} ===
               {:right, :none}
    end
  end

  # Golden: `calc_element()` over each complete theme in ggplot2 4.0.3 (R 4.6.1), and the guide
  # box's own tables (`ggplotGrob()`, R's spacing in points by `convertUnit(..., "bigpts")`): every
  # theme sets `legend.position` "right" and `legend.justification` "center" but theme_void(),
  # which sets no justification, read as centred, and no `legend.spacing`, which the guide box
  # makes half a line, 7.2 points between theme_void()'s legends; none sets `legend.direction`,
  # `legend.box`, `legend.box.just` or `legend.location`, and each a box margin of 0 and no box
  # background. A justification is worked out as grid's `valid.just()` reads one: "top" 0.5 and
  # 1, "left" 0 and 0.5, c("right", "top") 1 and 1, c("center", "top") 0.5 and 1, c("left",
  # "bottom") 0 and 0, c(0.3, 0.8) as it is; a name beside a number,
  # which R refuses as one character vector, Giggly reads side by side, each as R reads it alone.
  # They move with the themes' legend values or how a justification is read.
  describe "complete/1, where the legends go" do
    test "every complete theme puts its legends right of the panels, centred, in a bare box" do
      for name <- [:gray, :bw, :linedraw, :light, :dark, :minimal, :classic, :void] do
        theme = chosen(name)

        assert {theme.legend_position, theme.legend_justification_right, theme.legend_location,
                theme.legend_direction, theme.legend_box, theme.legend_box_just,
                theme.legend_box_margin, theme.legend_box_background} ===
                 {:right, {0.5, 0.5}, :panel, :none, :none, :none, sides(0, 0, 0, 0), :none},
               "#{name}"
      end
    end

    test "legends are twice the spacing apart, and half a line under theme_void()" do
      gray = chosen(:gray)
      void = chosen(:void)
      set = chosen(:void, [], %{legend_spacing: {3, :pt}})

      assert {gray.legend_spacing_x, gray.legend_spacing_y, void.legend_spacing_x,
              void.legend_spacing_y, set.legend_spacing_x} ===
               {10.958904109589042, 10.958904109589042, 7.199999999999999, 7.199999999999999,
                2.9887920298879207}
    end

    test "a justification is worked out as grid reads one, by name or by share" do
      justification = fn given ->
        complete(%{legend_justification: given}).legend_justification_right
      end

      assert Enum.map(
               [
                 :top,
                 :left,
                 :bottom,
                 :right,
                 :center,
                 {:right, :top},
                 {:center, :top},
                 {:left, :bottom},
                 {0.3, 0.8},
                 {:left, 2}
               ],
               justification
             ) ===
               [
                 {0.5, 1.0},
                 {0.0, 0.5},
                 {0.5, 0.0},
                 {1.0, 0.5},
                 {0.5, 0.5},
                 {1.0, 1.0},
                 {0.5, 1.0},
                 {0.0, 0.0},
                 {0.3, 0.8},
                 {0.0, 2.0}
               ]
    end

    test "each side's justification is the legends' unless its own is given" do
      theme = complete(%{legend_justification: :top, legend_justification_inside: {1, 0}})

      assert {theme.legend_justification_top, theme.legend_justification_bottom,
              theme.legend_justification_left, theme.legend_justification_right,
              theme.legend_justification_inside} ===
               {{0.5, 1.0}, {0.5, 1.0}, {0.5, 1.0}, {0.5, 1.0}, {1.0, 0.0}}
    end

    test "an inside box goes at its justification's point of the panels unless given one" do
      justified = complete(%{legend_justification_inside: :right})
      placed = complete(%{legend_justification_inside: :right, legend_position_inside: {1, 0}})

      # A point given in whole numbers is held as floats, as the theme holds every point.
      assert {justified.legend_position_inside, placed.legend_position_inside,
              placed.legend_justification_inside} === {{1.0, 0.5}, {1.0, 0.0}, {1.0, 0.5}}
    end

    test "the direction, the arrangement and the place in the box are the settings'" do
      theme =
        complete(%{
          legend_direction: :horizontal,
          legend_box: :vertical,
          legend_box_just: {:right, :bottom},
          legend_location: :plot
        })

      assert {theme.legend_direction, theme.legend_box, theme.legend_box_just,
              theme.legend_location} === {:horizontal, :vertical, {1.0, 0.0}, :plot}
    end

    # Golden: ggplot2 4.0.3's guide box draws `legend.box.background` as the theme holds it,
    # through vdiffr 1.0.9 (R 4.6.1): `element_rect()` white with a black border 0.75 points wide
    # under `rect = element_rect(fill = "yellow", colour = "red")` too, and `element_rect(linewidth
    # = 2, colour = "blue")` blue and 4.27 wide, filled white.
    test "the legends' box background takes nothing from rect, its unset properties grid's" do
      given = complete(%{rect: %{fill: "#FFFF00", color: "#FF0000"}, legend_box_background: %{}})
      blue = complete(%{legend_box_background: %{linewidth: 2, color: "#0000FF"}})

      assert {given.legend_box_background, Float.round(blue.legend_box_background.line_width, 2),
              blue.legend_box_background.color, blue.legend_box_background.fill,
              complete(%{}).legend_box_background} ===
               {%{
                  fill: "#FFFFFF",
                  fill_opacity: 1.0,
                  color: "#000000",
                  color_opacity: 1.0,
                  line_width: 0.75,
                  dashes: :none
                }, 4.27, "#0000FF", "#FFFFFF", :none}
    end

    # Golden: ggplot2 4.0.3's guides lay their text over the theme with the root text's margin
    # widened by `legend.key.spacing`, 5.5 points, on the side facing the keys
    # (`position_margin()`): below a title above them, right of one left of them, left of labels
    # right of them and above labels below a colour bar.
    test "a legend's title and labels are widened by the keys' spacing on the side facing them" do
      theme = complete(%{})
      gap = 5.4794520547945211

      assert {theme.legend_key_spacing, theme.legend_title_top.margin,
              theme.legend_title_left.margin, theme.legend_text_right.margin,
              theme.legend_text_bottom.margin} ===
               {gap, sides(0, 0, gap, 0), sides(0, gap, 0, 0), sides(0, 0, 0, gap),
                sides(gap, 0, 0, 0)}
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
                  fill_opacity: 1.0,
                  color: :none,
                  color_opacity: 0.0,
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
                %{
                  fill: "#FFFFFF",
                  fill_opacity: 1.0,
                  color: :none,
                  color_opacity: 0.0,
                  line_width: 1.0669783464566929,
                  dashes: :none
                }}
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
        opacity: 1.0,
        line_width: 1.0669783464566929,
        line_end: :butt,
        dashes: :none
      }

      assert {theme.axis_line_x_bottom, theme.axis_line_theta, theme.axis_line_y_left,
              theme.panel_border, theme.panel_ontop} ===
               {red_line, red_line, :none,
                %{
                  fill: "#FFFFFF",
                  fill_opacity: 1.0,
                  color: "#000000",
                  color_opacity: 1.0,
                  line_width: 1.0669783464566929,
                  dashes: :none
                }, true}
    end
  end

  # Golden: each value is ggplot2 4.0.3's, as the module's other goldens are, worked out by
  # `calc_element()` over a plot with the complete theme added, at its default sizes unless the
  # test gives others; every element of each theme was checked so, at 11 points and at 16 points
  # with lines 1 millimetre and borders 2 wide. They move with each complete theme's elements, with
  # how its base sizes reach them, and with how an element replaced whole inherits.
  describe "complete/1 with a complete theme chosen" do
    test "theme_bw() borders the panels and strips in dark grey, its panels white" do
      theme = chosen(:bw)

      assert {theme.panel_border.color, theme.panel_background.fill,
              theme.panel_grid_major_x.color, theme.strip_background_x} ===
               {"#333333", "#FFFFFF", "#EBEBEB",
                %{
                  fill: "#D9D9D9",
                  fill_opacity: 1.0,
                  color: "#333333",
                  color_opacity: 1.0,
                  line_width: 1.0669783464566929,
                  dashes: :none
                }}
    end

    test "theme_linedraw() draws thin black grid lines and ticks, and black strips" do
      theme = chosen(:linedraw)

      assert {theme.panel_grid_minor_x.line_width, theme.axis_ticks_x_bottom,
              theme.axis_text_y_left.color, theme.strip_background_x.fill,
              theme.strip_text_x_top.color} ===
               {0.053348917322834644,
                %{
                  color: "#000000",
                  opacity: 1.0,
                  line_width: 0.5334891732283464,
                  line_end: :butt,
                  dashes: :none
                }, "#000000", "#000000", "#FFFFFF"}
    end

    # theme_linedraw() gives the border and the grid lines their ink, so a colour given every line
    # and rectangle does not reach them, as it reaches the strips', whose element gives none.
    test "theme_linedraw()'s border and grid lines keep their own ink under a root's colour" do
      theme = chosen(:linedraw, [], %{rect: %{color: "#FF0000"}, line: %{color: "#FF0000"}})

      assert {theme.panel_border.color, theme.panel_grid_major_x.color,
              theme.strip_background_x.color} === {"#000000", "#000000", "#FF0000"}
    end

    test "theme_light() and theme_dark() draw thinner grid lines in their own greys" do
      light = chosen(:light)
      dark = chosen(:dark)

      assert {light.panel_grid_major_x.color, light.panel_grid_major_x.line_width,
              light.axis_ticks_y_left.color, light.panel_border.color, dark.panel_background.fill,
              dark.legend_key.fill, dark.panel_grid_minor_y.color, dark.strip_text_x_top.color} ===
               {"#DEDEDE", 0.5334891732283464, "#B3B3B3", "#B3B3B3", "#7F7F7F", "#7F7F7F",
                "#6B6B6B", "#E5E5E5"}
    end

    test "theme_minimal() removes the ticks and backgrounds, moving the tick labels out" do
      theme = chosen(:minimal)

      assert {theme.axis_ticks_x_bottom, theme.axis_text_x_bottom.margin.top,
              theme.axis_text_theta.margin.top, theme.panel_background, theme.legend_key,
              theme.strip_background_x, theme.plot_background.color} ===
               {:none, 4.9315068493150696, 2.1917808219178085, :none, :none, :none, :none}
    end

    # theme_classic() replaces theme_bw()'s tick labels with an element that sets no colour, so
    # they take the text's ink.
    test "theme_classic() draws black axis lines with square ends, and no grid" do
      theme = chosen(:classic)

      assert {theme.axis_line_x_bottom.line_end, theme.axis_line_theta.color,
              theme.axis_text_y_left.color, theme.axis_ticks_x_bottom.color,
              theme.strip_background_x.line_width, theme.panel_grid_major_x, theme.panel_border} ===
               {:square, "#000000", "#000000", "#000000", 2.1339566929133857, :none, :none}
    end

    test "theme_void() draws no axes or backgrounds, on transparent paper with no margins" do
      theme = chosen(:void)
      shared = chosen(:void, [], %{legend_margin: {:rel, 2}})

      assert {theme.plot_background, theme.plot_margin, theme.axis_text_x_bottom,
              theme.axis_ticks_length_y_left, theme.panel_grid_major_x, theme.legend_key,
              theme.legend_margin, theme.legend_box_spacing, theme.legend_spacing_y,
              theme.plot_title.margin, theme.strip_text_x_top.margin} ===
               {%{
                  fill: "#000000",
                  fill_opacity: 0.0,
                  color: :none,
                  color_opacity: 0.0,
                  line_width: 0.0,
                  dashes: :none
                }, sides(0, 0, 0, 0), :none, 0.0, :none, :none, sides(0, 0, 0, 0),
                5.669291338582677, 7.199999999999999, sides(5.4794520547945211, 0, 0, 0),
                sides(0, 0, 0, 0)}

      # Its margins are half its base size, as theme_gray()'s, though no element it draws takes
      # them: a legend's margin set as a share does; its legends go right, their colour bars'
      # ticks a fifth of a key long, its panel under its layers and its titles' lines 0.9 apart.
      assert {shared.legend_margin, theme.legend_position, theme.legend_ticks_length,
              theme.panel_ontop, theme.plot_title.line_spacing} ===
               {sides(
                  10.958904109589042,
                  10.958904109589042,
                  10.958904109589042,
                  10.958904109589042
                ), :right, 3.456, false, 14.256}
    end

    test "the base sizes reach every size, spacing, line and border, but a legend's keys" do
      theme = chosen(:gray, base_size: 16, base_line_size: 1, base_rect_size: 2)
      void = chosen(:void, base_size: 16, base_line_size: 1, base_rect_size: 2)

      assert {theme.axis_text_x_bottom.size, theme.plot_title.size,
              theme.axis_ticks_length_x_bottom, theme.plot_margin.top,
              theme.panel_grid_major_x.line_width, theme.panel_grid_minor_x.line_width,
              theme.plot_background.line_width, theme.legend_key_width,
              void.plot_background.line_width, void.strip_text_x_top.size} ===
               {12.8, 19.2, 3.9850560398505603, 7.970112079701121, 2.1339566929133857,
                1.0669783464566929, 4.2679133858267715, 17.279999999999998, 0.0, 12.8}
    end

    # An element a setting replaces whole keeps nothing of the complete theme's, so its size is
    # the text's, not theme_bw()'s 0.8 of it; a root replaced whole takes what it leaves unset
    # from theme_gray()'s at its default size, as ggplot2 fills a root from its default theme,
    # while the spacing keeps the chosen theme's base size.
    test "an element a setting replaces whole takes what it leaves unset from its parent" do
      replaced = chosen(:bw, [], %{axis_text: {:replace, %{color: "#FF0000"}}})
      merged = chosen(:bw, [], %{axis_text: %{color: "#FF0000"}})
      root = chosen(:bw, [base_size: 16.0], %{text: {:replace, %{color: "#0000FF"}}})
      background = chosen(:dark, [], %{panel_background: {:replace, %{fill: "#FF0000"}}})

      assert {replaced.axis_text_x_bottom.size, replaced.axis_text_x_bottom.margin.top,
              merged.axis_text_x_bottom.size, root.axis_title_x_bottom.size,
              root.axis_title_x_bottom.color, root.plot_margin.top, background.panel_background} ===
               {11.0, 2.1917808219178085, 8.8, 11.0, "#0000FF", 7.970112079701121,
                %{
                  fill: "#FF0000",
                  fill_opacity: 1.0,
                  color: "#000000",
                  color_opacity: 1.0,
                  line_width: 1.0669783464566929,
                  dashes: :none
                }}
    end

    # A setting is marked to skip a removed element above it, replacing one whole too.
    test "an element a setting replaces whole skips a removed parent" do
      theme = chosen(:bw, [], %{axis_text: :none, axis_text_x: {:replace, %{color: "#FF0000"}}})

      assert {theme.axis_text_x_bottom, theme.axis_text_y_left} ===
               {%{
                  size: 11.0,
                  color: "#FF0000",
                  opacity: 1.0,
                  face: :plain,
                  angle: 0.0,
                  hjust: 0.5,
                  vjust: 0.5,
                  margin: sides(0, 0, 0, 0)
                }, :none}
    end

    test "a colour with an alpha of its own is worked out as its opacity, none as nothing" do
      theme =
        complete(%{
          panel_background: %{fill: "#FF000080", color: "#0000FF40"},
          axis_text: %{color: "#FF000080"},
          panel_grid: %{color: "#00FF0000"}
        })

      assert {theme.panel_background, theme.axis_text_y_left.color,
              theme.axis_text_y_left.opacity, theme.panel_grid_major_x.opacity} ===
               {%{
                  fill: "#FF0000",
                  fill_opacity: 0.5019607843137255,
                  color: "#0000FF",
                  color_opacity: 0.25098039215686274,
                  line_width: 1.0669783464566929,
                  dashes: :none
                }, "#FF0000", 0.5019607843137255, 0.0}
    end
  end

  # Golden: the defaults ggplot2 4.0.3's `layer_data()` shows in R 4.6.1 for points, lines, text,
  # bars and box plots under each complete theme and at other base sizes, its geoms reading the
  # theme's `element_geom()`: a point's size and stroke, a line's and a border's width, a text's
  # size, and the paper a bar's and a box's fill are mixed from. They move with how a complete
  # theme's base sizes reach its layers.
  describe "complete/1's defaults for the layers" do
    test "at the default sizes, black ink on white paper, 0.5 mm lines and 11-point text" do
      assert complete(%{}).geom === %{
               ink: "#000000",
               paper: "#FFFFFF",
               linewidth: 0.5,
               borderwidth: 0.5,
               linetype: {},
               bordertype: {},
               family: "",
               fontsize: 3.8660578386605779,
               pointsize: 1.5,
               pointshape: :circle
             }
    end

    test "the base size reaches the text's and the points' sizes, the line width every width" do
      sixteen = chosen(:gray, base_size: 16.0).geom
      eight = chosen(:gray, base_size: 8.0).geom

      assert Enum.map([sixteen, eight], fn geom ->
               {geom.fontsize, geom.pointsize, geom.linewidth, geom.borderwidth}
             end) === [
               {5.6233568562335678, 2.1818181818181817, 0.72727272727272729, 0.72727272727272729},
               {2.8116784281167839, 1.0909090909090908, 0.36363636363636365, 0.36363636363636365}
             ]
    end

    test "the borders take the line width, never the rectangles' base size" do
      geom = chosen(:gray, base_line_size: 1.0, base_rect_size: 2.0).geom
      assert {geom.linewidth, geom.borderwidth, geom.pointsize} === {1.0, 1.0, 1.5}
    end

    test "each theme gives theme_gray()'s defaults but theme_void(), whose paper is clear" do
      for name <- [:bw, :linedraw, :light, :dark, :minimal, :classic] do
        assert chosen(name, base_size: 16.0).geom === chosen(:gray, base_size: 16.0).geom
      end

      void = chosen(:void, base_size: 16.0, base_line_size: 1.0).geom

      assert {void.paper, void.fontsize, void.linewidth} ===
               {"#00000000", 5.6233568562335678, 1.0}
    end

    test "no setting reaches them, laid over a complete theme or over none" do
      assert chosen(:gray, [base_size: 16.0], %{
               text: %{size: 30.0},
               line: %{linewidth: 3.0},
               rect: %{fill: "#FF0000"}
             }).geom === chosen(:gray, base_size: 16.0).geom

      assert complete(%{line: %{linewidth: 3.0}}).geom === complete(%{}).geom
    end
  end

  describe "merge/2" do
    test "a line's, a rectangle's or a text's properties replace only the ones given" do
      merged = merge(%{axis_text: %{color: "#FF0000"}}, %{axis_text: %{size: 12}})

      assert Map.take(complete(merged).axis_text_x_bottom, [:color, :size]) ===
               %{color: "#FF0000", size: 12.0}
    end

    test "a line's or a rectangle's properties replace only the ones given, as a text's do" do
      assert merge(
               %{panel_grid: %{color: "#FF0000"}, panel_background: %{fill: "#FF0000"}},
               %{panel_grid: %{linewidth: 2}, panel_background: %{color: :none}}
             ) === %{
               panel_grid: %{color: "#FF0000", linewidth: 2},
               panel_background: %{fill: "#FF0000", color: :none}
             }
    end

    # ggplot2 lays each setting over a complete theme the plot added in turn: a removal takes the
    # theme's element, and an element given after it replaces the removal, so the theme's own.
    test "under a chosen complete theme, an element given after a removal replaces the theme's" do
      chosen = Theme.choose(:bw, [])

      settings =
        chosen
        |> Theme.merge(%{
          axis_text: :none,
          panel_grid: %{color: "#FF0000"},
          panel_border: :none,
          axis_ticks: :none
        })
        |> Theme.merge(%{
          axis_text: %{color: "#FF0000"},
          panel_grid: :none,
          panel_border: %{color: "#FF0000"},
          axis_ticks: %{color: "#FF0000"}
        })
        |> Theme.merge(%{
          axis_text: %{size: 12, color: "#0000FF"},
          panel_grid: %{linewidth: 2},
          axis_ticks: :none
        })
        |> Map.fetch!(:settings)

      assert settings === %{
               axis_text: {:replace, %{color: "#0000FF", size: 12}},
               panel_grid: {:replace, %{linewidth: 2}},
               panel_border: {:replace, %{color: "#FF0000"}},
               axis_ticks: :none
             }
    end

    test "choosing a complete theme drops the settings and records the sizes, widths from size" do
      assert {Theme.choose(:light, base_size: 16.0), Theme.choose(:dark, base_line_size: 2.0)} ===
               {
                 %{
                   complete: %{
                     name: :light,
                     base_size: 16.0,
                     base_line_size: 0.7272727272727273,
                     base_rect_size: 0.7272727272727273
                   },
                   settings: %{}
                 },
                 %{
                   complete: %{
                     name: :dark,
                     base_size: 11.0,
                     base_line_size: 2.0,
                     base_rect_size: 0.5
                   },
                   settings: %{}
                 }
               }
    end

    test "a length or a margin replaces the one before whole" do
      assert merge(
               %{panel_spacing: {1, :cm}, legend_margin: %{top: {1, :pt}}},
               %{panel_spacing: {:rel, 2}, legend_margin: {:rel, 3}}
             ) === %{panel_spacing: {:rel, 2}, legend_margin: {:rel, 3}}
    end
  end

  defp complete(settings), do: Theme.complete(%{complete: :none, settings: settings})

  # The complete theme `name` at `sizes`, with `settings` laid over it.
  defp chosen(name, sizes \\ [], settings \\ %{}),
    do: Theme.complete(%{Theme.choose(name, sizes) | settings: settings})

  # `new` merged into `settings` on a plot that chose no complete theme.
  defp merge(settings, new),
    do: Theme.merge(%{complete: :none, settings: settings}, new).settings

  # A margin in points, top, right, bottom and left, each a float.
  defp sides(top, right, bottom, left),
    do: %{top: top / 1, right: right / 1, bottom: bottom / 1, left: left / 1}
end
