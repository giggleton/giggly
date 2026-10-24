defmodule Giggly.Guide.Title do
  @moduledoc false

  # The plot's own titles, which `labs()` sets: its title and subtitle above the panels, its
  # caption below them and its tag at the plot's top left, drawn as `theme_gray()` draws ggplot2's
  # `plot.title`, `plot.subtitle`, `plot.caption` and `plot.tag`, each of which may run over
  # several lines (`Giggly.Guide.Parts`). Rendering lays out their cells: the title's, the
  # subtitle's and the caption's spanning the panels (`plot.title.position = "panel"`), the tag's
  # in a row and column of its own (`plot.tag.position = "topleft"`).
  #
  # Each is placed as `Giggly.Guide.Parts` places every text, ggplot2's `titleGrob()`, counting its
  # margins on every side, in a row as deep as it is turned and its margins: `theme_gray()`'s title
  # and subtitle hang left-aligned from their margins, its caption hangs right-aligned, and its tag
  # is centred both ways in a cell as wide as it is turned and its margins either side. A label of
  # `:none` draws nothing and takes no room, as ggplot2 leaves out a label set to `NULL`, and so
  # does one whose look the theme removes.

  alias Giggly.Guide.Parts
  alias Giggly.Theme

  @typedoc "A label's text, `:none` for none."
  @type label :: String.t() | :none

  @typedoc "How deep a title's row is, in points, and its primitives, placed in its cell."
  @type drawn :: {float(), [struct()]}

  # The plot's `labels` in `theme`'s look: the title, the subtitle and the caption each its row's
  # depth and its primitives, and the tag its cell's width and height and its primitives.
  @doc false
  @spec draw(
          %{title: label(), subtitle: label(), caption: label(), tag: label()},
          Theme.t()
        ) :: %{
          title: drawn(),
          subtitle: drawn(),
          caption: drawn(),
          tag: {{float(), float()}, [struct()]}
        }
  def draw(%{title: title, subtitle: subtitle, caption: caption, tag: tag}, %Theme{} = theme) do
    %{
      title: row_label(title, theme.plot_title),
      subtitle: row_label(subtitle, theme.plot_subtitle),
      caption: row_label(caption, theme.plot_caption),
      tag: tag(tag, theme.plot_tag)
    }
  end

  # A label in a row of its own, spanning the panels: as deep as it and its margins above and
  # below, anchored in the row as `Giggly.Guide.Parts` places it.
  defp row_label(:none, _look), do: {0.0, []}
  defp row_label(_label, :none), do: {0.0, []}

  defp row_label(label, %{margin: margin} = look) do
    {_width, height} = Parts.extent([label], look)
    {place, offset} = Parts.anchor(look, :both)
    {margin.top + height + margin.bottom, [Parts.text([label], [place], offset, look)]}
  end

  # The tag, in a cell as wide and as deep as it and its margins, anchored in it as
  # `Giggly.Guide.Parts` places it.
  defp tag(:none, _look), do: {{0.0, 0.0}, []}
  defp tag(_label, :none), do: {{0.0, 0.0}, []}

  defp tag(label, %{margin: margin} = look) do
    {width, height} = Parts.extent([label], look)
    {place, offset} = Parts.anchor(look, :both)
    cell = {margin.left + width + margin.right, margin.top + height + margin.bottom}
    {cell, [Parts.text([label], [place], offset, look)]}
  end
end
