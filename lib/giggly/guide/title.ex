defmodule Giggly.Guide.Title do
  @moduledoc false

  # The plot's own titles, which `labs()` sets: its title and subtitle above the panels, its
  # caption below them and its tag at the plot's top left, drawn as `theme_gray()` draws ggplot2's
  # `plot.title`, `plot.subtitle`, `plot.caption` and `plot.tag`, each of which may run over
  # several lines (`Giggly.Guide.Parts`). Rendering lays out their cells: the title's, the
  # subtitle's and the caption's spanning the panels (`plot.title.position = "panel"`), the tag's
  # in a row and column of its own (`plot.tag.position = "topleft"`).
  #
  # Each counts its margins on every side, as ggplot2's do. The title hangs from its margin below the
  # top of its cell, left-aligned its left margin in, with its margin below it, and so does the
  # subtitle. The caption hangs from its margin below the top of its cell, right-aligned its right
  # margin in. The tag is centred both ways in what its margins leave of its cell, which is as wide
  # as its widest line and its margins either side. A label of `:none` draws nothing and takes no
  # room, as ggplot2 leaves out a label set to `NULL`.

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
      title: above(title, theme.plot_title),
      subtitle: above(subtitle, theme.plot_subtitle),
      caption: below(caption, theme.plot_caption),
      tag: tag(tag, theme.plot_tag)
    }
  end

  # A title above the panels, hanging left-aligned from its margin below its cell's top, its left
  # margin in, its margin below it.
  defp above(:none, _look), do: {0.0, []}

  defp above(label, %{margin: margin} = look) do
    height = margin.top + Parts.title_height(label, look) + margin.bottom
    place = {0.0, 1 - margin.top / height}
    {height, [Parts.title_text(label, place, 0, {0.0, 1.0}, look, margin.left)]}
  end

  # A title below the panels, hanging right-aligned from its margin below its cell's top, its right
  # margin in, its margin below it.
  defp below(:none, _look), do: {0.0, []}

  defp below(label, %{margin: margin} = look) do
    height = margin.top + Parts.title_height(label, look) + margin.bottom
    place = {1.0, 1 - margin.top / height}
    {height, [Parts.title_text(label, place, 0, {1.0, 1.0}, look, -margin.right)]}
  end

  # The tag, centred in what its margins leave of a cell as wide as its widest line and as deep as
  # its lines, its margins included.
  defp tag(:none, _look), do: {{0.0, 0.0}, []}

  defp tag(label, %{margin: margin} = look) do
    width = Parts.title_width(label, look)
    height = Parts.title_height(label, look)
    cell_width = margin.left + width + margin.right
    cell_height = margin.top + height + margin.bottom
    place = {(margin.left + width / 2) / cell_width, 1 - (margin.top + height / 2) / cell_height}
    {{cell_width, cell_height}, [Parts.title_text(label, place, 0, {0.5, 0.5}, look)]}
  end
end
