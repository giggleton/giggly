defmodule Giggly.Guide.Strip do
  @moduledoc false

  # A strip, one layer of what ggplot2's `render_strips()` draws above a facet's panel: the label of
  # the panel's value of one column, on a background as wide as the panel. `draw/2` draws a
  # panel's strips, one for each of its labels, top to bottom; a panel with no labels has none.
  #
  # It looks as the theme says (`Giggly.Theme`'s `strip_background_x` and `strip_text_x_top`): the
  # background fills the strip's cell, and the label is centred in what the strip text's margins
  # leave of it, its margins above and below a line of text, so a strip is as tall as those margins
  # and a line's ascent and deepest descent, as ggplot2 measures it. The label's baseline is half an
  # ascent below the middle of that line, as an axis label beside its tick is. A strip whose text
  # the theme removes is not drawn at all, its background with it, and takes no room, as ggplot2's
  # is; a background the theme removes leaves the label alone.

  alias Giggly.{Font, Theme}
  alias Giggly.Scene.{Rect, Text}

  # A panel's strips, one for each of `labels`, top to bottom, in `theme`'s look: ggplot2's
  # `render_strips()` for strips above a panel.
  @doc false
  @spec draw([String.t()], Theme.t()) :: [Giggly.Guide.drawn()]
  def draw(_labels, %Theme{strip_text_x_top: :none}), do: []
  def draw(labels, theme), do: Enum.map(labels, fn label -> strip(label, theme) end)

  # The strip labelled `label`, in `theme`'s look: how tall it is, in points, and its primitives,
  # placed in a cell that tall and as wide as the panel.
  defp strip(label, %Theme{strip_background_x: background, strip_text_x_top: text_look}) do
    %{size: size, margin: margin} = text_look
    line_height = Font.ascent(size) + Font.descent(size)
    height = margin.top + line_height + margin.bottom

    text = %Text{
      x: [0.5],
      y: [(margin.bottom + line_height / 2) / height],
      labels: [label],
      widths: [Font.width(label, size)],
      size: size,
      family: "",
      color: [text_look.color],
      opacity: [1.0],
      angle: 0,
      hjust: [0.5],
      offset: [{(margin.left - margin.right) / 2, -Font.ascent(size) / 2}],
      check_overlap: false,
      ascent: Font.ascent(size)
    }

    background_rect = background(background)
    {height, Enum.concat(background_rect, [text])}
  end

  defp background(:none), do: []

  defp background(look),
    do: [
      %Rect{
        fill: look.fill,
        color: look.color,
        stroke_width: look.line_width,
        dashes: look.dashes
      }
    ]
end
