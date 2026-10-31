defmodule Giggly.Guide.Colorsteps do
  @moduledoc false

  # A colour steps guide, ggplot2's `guide_coloursteps()` at its defaults (`even.steps = TRUE`,
  # `show.limits` the scale's, off), a kind of guide (`Giggly.Guide`): the bins of a binned colour
  # or fill scale, or of a continuous one cut at its breaks, as a bar of one rectangle per bin,
  # each in its bin's one colour and all as long as one another however wide the bins are, with
  # each break's label beside the bar at the edge it sits at. The assembly works out the bins and
  # places the breaks; the bar is laid out as `Giggly.Guide.Bar` lays one out, its rectangles from
  # its bottom, the scale's low end, to its top, or from its left to its right, with no border, and
  # its ticks in the theme's colour steps ticks, none unless the theme sets `legend_ticks`, as
  # ggplot2's colour steps guide defaults them to `element_blank()`.

  defstruct []

  @type t :: %__MODULE__{}

  defimpl Giggly.Guide, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Guide

    alias Giggly.Guide.Bar
    alias Giggly.Scene.Rectangles
    alias Giggly.Theme

    # Each bin's rectangle is drawn with no border, at grid's default line width, 1, which svglite
    # writes in points.
    @bin_stroke_width 72 / 96

    # The colour steps guide `legend` describes, its bar a rectangle for each of `decor`'s bins,
    # each its place along the bar from and to, 0 to 1, and its colour, in `theme`'s look: its
    # width in points and its table, every size in points.
    @impl Giggly.Guide
    def draw(
          _guide,
          %{decor: decor} = legend,
          %Theme{legend_steps_ticks: ticks_look} = theme,
          installed_fonts
        ) do
      fill = fn direction -> bins(decor, direction) end
      Bar.draw(legend, fill, ticks_look, theme, installed_fonts)
    end

    # The bins' rectangles, along a bar running up, across its whole width, or along one running
    # across, up its whole height, in order from the low end.
    defp bins(decor, direction) do
      {froms, tos, colors} = unzip3(decor)
      count = length(decor)
      zeros = List.duplicate(0.0, count)
      ones = List.duplicate(1.0, count)

      {xmin, xmax, ymin, ymax} =
        case direction do
          :up -> {zeros, ones, froms, tos}
          :across -> {froms, tos, zeros, ones}
        end

      %Rectangles{
        xmin: xmin,
        xmax: xmax,
        ymin: ymin,
        ymax: ymax,
        offsets: :none,
        fill: colors,
        fill_opacity: List.duplicate(1.0, count),
        color: List.duplicate(:none, count),
        color_opacity: zeros,
        stroke_width: @bin_stroke_width,
        dashes: :none,
        line_end: :round,
        line_join: :round,
        mitre_limit: 10.0
      }
    end

    defp unzip3(decor) do
      {Enum.map(decor, fn {from, _to, _color} -> from end),
       Enum.map(decor, fn {_from, to, _color} -> to end),
       Enum.map(decor, fn {_from, _to, color} -> color end)}
    end
  end
end
