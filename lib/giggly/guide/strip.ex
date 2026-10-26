defmodule Giggly.Guide.Strip do
  @moduledoc false

  # A strip, one layer of what ggplot2's `render_strips()` draws beside a facet's panel: the label
  # of the panel's value of one column, on a background as long as the panel's side. `draw/3`
  # draws a panel's strips on one side, one for each of its labels: above the panel, top to
  # bottom, or right of it, the first nearest the panel; a panel with no labels on a side has none
  # there.
  #
  # It looks as the theme says, each side its own elements (`Giggly.Theme`'s `strip_background_x`
  # and `strip_text_x_top` above, `strip_background_y` and `strip_text_y_right` to the right, whose
  # text `theme_gray()` turns 90 degrees clockwise): the background fills the strip's cell, and the
  # label is placed in it as `Giggly.Guide.Parts` places every text, ggplot2's `titleGrob()`,
  # counting its margins on every side, each side of the cell's own: centred in what the margins
  # leave unless the theme justifies it otherwise. A strip above is as tall as its margins above
  # and below and its label turned, a level one a line's ascent and deepest descent, as ggplot2
  # measures it; one to the right is as wide as its margins left and right and its label turned. The
  # label is anchored by shares of the strip and offsets in points, so it sits right in a strip
  # longer or deeper than itself, as a row or column of strips is as deep as its deepest. A strip
  # whose text the theme removes is not drawn at all, its background with it, and takes no room, as
  # ggplot2's is; a background the theme removes leaves the label alone.

  alias Giggly.Guide.Parts
  alias Giggly.Scene.Rect
  alias Giggly.Theme

  # A panel's strips on `side`, one for each of `labels`, in `theme`'s look, each how deep it is
  # away from the panel, in points, and its primitives: ggplot2's `render_strips()` for strips
  # above a panel (`:top`) or right of it (`:right`).
  @doc false
  @spec draw([String.t()], :top | :right, Theme.t()) :: [Giggly.Guide.drawn()]
  def draw(_labels, :top, %Theme{strip_text_x_top: :none}), do: []
  def draw(_labels, :right, %Theme{strip_text_y_right: :none}), do: []

  def draw(labels, :top, theme),
    do:
      Enum.map(labels, fn label ->
        strip(label, :top, theme.strip_text_x_top, theme.strip_background_x)
      end)

  def draw(labels, :right, theme),
    do:
      Enum.map(labels, fn label ->
        strip(label, :right, theme.strip_text_y_right, theme.strip_background_y)
      end)

  # The strip labelled `label` on `side`, in `text_look` on `background`: how deep it is, in
  # points, and its primitives, placed in a cell that deep and as long as the panel's side.
  defp strip(label, side, %{margin: margin} = text_look, background) do
    {place, offset} = Parts.anchor(text_look, :both)
    text = Parts.text([label], [place], offset, text_look)
    extent = Parts.extent([label], text_look)
    background_rect = background(background)

    {depth(side, margin, extent), Enum.concat(background_rect, [text])}
  end

  # A strip's depth away from its panel: its label turned and its margins across that way.
  defp depth(:top, margin, {_width, height}), do: margin.top + height + margin.bottom
  defp depth(:right, margin, {width, _height}), do: margin.left + width + margin.right

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
