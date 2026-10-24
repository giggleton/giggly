defmodule Giggly.Guide.Strip do
  @moduledoc false

  # A strip, one layer of what ggplot2's `render_strips()` draws above a facet's panel: the label of
  # the panel's value of one column, on a background as wide as the panel. `draw/2` draws a
  # panel's strips, one for each of its labels, top to bottom; a panel with no labels has none.
  #
  # It looks as the theme says (`Giggly.Theme`'s `strip_background_x` and `strip_text_x_top`): the
  # background fills the strip's cell, and the label is placed in it as `Giggly.Guide.Parts`
  # places every text, ggplot2's `titleGrob()`, counting its margins on every side: centred in what
  # the margins leave unless the theme justifies it otherwise, its margins above and below the
  # label turned, so a level strip is as tall as those margins and a line's ascent and deepest
  # descent, as ggplot2 measures it. The label is anchored by shares of the strip and offsets in
  # points, so it sits right in a strip taller than itself, as a row of strips is as tall as its
  # tallest. A strip whose text the theme removes is not drawn at all, its background with it, and
  # takes no room, as ggplot2's is; a background the theme removes leaves the label alone.

  alias Giggly.Guide.Parts
  alias Giggly.Scene.Rect
  alias Giggly.Theme

  # A panel's strips, one for each of `labels`, top to bottom, in `theme`'s look: ggplot2's
  # `render_strips()` for strips above a panel.
  @doc false
  @spec draw([String.t()], Theme.t()) :: [Giggly.Guide.drawn()]
  def draw(_labels, %Theme{strip_text_x_top: :none}), do: []
  def draw(labels, theme), do: Enum.map(labels, fn label -> strip(label, theme) end)

  # The strip labelled `label`, in `theme`'s look: how tall it is, in points, and its primitives,
  # placed in a cell that tall and as wide as the panel.
  defp strip(label, %Theme{strip_background_x: background, strip_text_x_top: text_look}) do
    %{margin: margin} = text_look
    {_width, label_height} = Parts.extent([label], text_look)
    {place, offset} = Parts.anchor(text_look, :both)
    text = Parts.text([label], [place], offset, text_look)

    background_rect = background(background)
    {margin.top + label_height + margin.bottom, Enum.concat(background_rect, [text])}
  end

  defp background(:none), do: []

  defp background(look),
    do: [
      %Rect{
        fill: look.fill,
        fill_opacity: look.fill_opacity,
        color: look.color,
        color_opacity: look.color_opacity,
        stroke_width: look.line_width,
        dashes: look.dashes
      }
    ]
end
