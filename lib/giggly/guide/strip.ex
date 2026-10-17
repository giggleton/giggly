defmodule Giggly.Guide.Strip do
  @moduledoc false

  # A strip, one layer of what ggplot2's `render_strips()` draws above a facet's panel: the label of
  # the panel's value of one column, on a background as wide as the panel. `draw/2` draws a
  # panel's strips, one for each of its labels, top to bottom; a panel with no labels has none.
  #
  # It looks as the theme says (`Giggly.Theme`): the background fills the strip's cell, and the
  # label is centred in it, with the strip text's margin above and below a line of text, so a strip
  # is as tall as the margin twice and a line's ascent and deepest descent, as ggplot2 measures it.
  # The label's baseline is half an ascent below the strip's middle, as an axis label beside its
  # tick is.

  alias Giggly.{Font, Theme}
  alias Giggly.Scene.{Rect, Text}

  # A panel's strips, one for each of `labels`, top to bottom, in `theme`'s look: ggplot2's
  # `render_strips()` for strips above a panel.
  @doc false
  @spec draw([String.t()], Theme.t()) :: [Giggly.Guide.drawn()]
  def draw(labels, theme), do: Enum.map(labels, fn label -> strip(label, theme) end)

  # The strip labelled `label`, in `theme`'s look: how tall it is, in points, and its primitives,
  # placed in a cell that tall and as wide as the panel.
  defp strip(label, %Theme{strip_background: background, strip_text: text_look}) do
    size = text_look.size
    height = 2 * text_look.margin + Font.ascent(size) + Font.descent(size)

    text = %Text{
      x: [0.5],
      y: [0.5],
      labels: [label],
      widths: [Font.width(label, size)],
      size: size,
      family: "",
      color: [text_look.color],
      opacity: [1.0],
      angle: 0,
      hjust: [0.5],
      offset: [{0.0, -Font.ascent(size) / 2}],
      check_overlap: false,
      ascent: Font.ascent(size)
    }

    {height,
     [
       %Rect{fill: background.fill, color: background.color, stroke_width: background.line_width},
       text
     ]}
  end
end
