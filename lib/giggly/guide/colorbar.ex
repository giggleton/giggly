defmodule Giggly.Guide.Colorbar do
  @moduledoc false

  # A colour bar, ggplot2's `guide_colourbar()` in its gradient form (`display = "gradient"`), a
  # kind of guide (`Giggly.Guide`): the colours of a continuous colour or fill scale as a bar the
  # gradient runs along, sampled at `bins` values spread evenly over the scale's limits, 15 as
  # ggplot2's gradient form takes them, with a tick across each side of the bar at each break and
  # the break's label beside it. The assembly samples the colours and places the breaks; the bar
  # is laid out as `Giggly.Guide.Bar` lays one out, filled with a gradient from its bottom, the
  # scale's low end, to its top, or from its left to its right, with no border, its ticks in the
  # theme's colour bar ticks (white when the theme sets none).

  @enforce_keys [:bins]
  defstruct @enforce_keys

  @type t :: %__MODULE__{bins: pos_integer()}

  defimpl Giggly.Guide, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Guide

    alias Giggly.Guide.Bar
    alias Giggly.Scene.Gradient
    alias Giggly.Theme

    # The bar's rectangle is drawn with no border, at grid's default line width, 1, which svglite
    # writes in points.
    @bar_stroke_width 72 / 96

    # The colour bar `legend` describes, its bar the gradient through `decor`, each its place
    # along the bar, 0 to 1, and its colour, in `theme`'s look: its width in points and its table,
    # every size in points.
    @impl Giggly.Guide
    def draw(_guide, %{decor: decor} = legend, %Theme{legend_ticks: ticks_look} = theme) do
      fill = fn direction ->
        %Gradient{stops: decor, direction: direction, stroke_width: @bar_stroke_width}
      end

      Bar.draw(legend, fill, ticks_look, theme)
    end
  end
end
