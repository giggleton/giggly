defmodule Giggly.Guide.Colorbar do
  @moduledoc false

  # A colour bar, ggplot2's `guide_colourbar()` in its gradient form (`display = "gradient"`), a
  # kind of guide (`Giggly.Guide`): the colours of a continuous colour or fill scale as a bar the
  # gradient runs up, sampled at `bins` values spread evenly over the scale's range, 15 as
  # ggplot2's gradient form takes them, with a tick across each side of the bar at each break and
  # the break's label right of it. The assembly samples the colours and places the breaks; the bar
  # draws them, as a table of its own (`Giggly.Scene`) for the box of guides beside the panels,
  # laid out as ggplot2 lays out a vertical colour bar through its legend's layout:
  #
  #   * the theme's legend margin inside the edge on every side;
  #   * the title, as deep as its lines (`Giggly.Guide.Parts`), left-aligned and centred down its
  #     row as grid centres text, then the title's margin below it; a title of `:none` takes
  #     neither;
  #   * the bar, as wide as a key and five keys long (`legend.key.height` times 5), the gradient
  #     filling it from its bottom, the scale's low end, to its top, with no border;
  #   * a white tick at each break's place up the bar, across each side, reaching the theme's tick
  #     length into it, and the break's label right of the bar, the labels' margin from it, centred
  #     on its tick;
  #   * the label column as wide as the widest label, or wider when the title is wider than the
  #     bar and its labels, which leaves the room at the labels' right.
  #
  # Drawn in ggplot2's order: the background, the title, the bar, the ticks on its right side and
  # then on its left, each from the bar's inside outward, and the labels.

  @enforce_keys [:bins]
  defstruct @enforce_keys

  @type t :: %__MODULE__{bins: pos_integer()}

  defimpl Giggly.Guide, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Guide

    alias Giggly.{Font, Scene, Theme}
    alias Giggly.Guide.Parts
    alias Giggly.Scene.{Cell, Gradient, Polylines, Text}

    # The bar is five keys long, as ggplot2's colour bar multiplies `legend.key.height` by 5.
    @bar_keys 5

    # The bar's rectangle is drawn with no border, at grid's default line width, 1, which svglite
    # writes in points.
    @bar_stroke_width 72 / 96

    # The colour bar titled `title`, its bar the gradient through `decor`, each its place up the
    # bar, 0 to 1, and its colour, and a tick and label for each of `keys`, each its place and its
    # label, in `theme`'s look: its width in points and its table, every size in points.
    @impl Giggly.Guide
    def draw(_guide, %{title: title, keys: keys, decor: decor}, %Theme{} = theme) do
      %Theme{
        legend_margin: margin,
        legend_key_size: key_size,
        legend_title: title_look,
        legend_text: text_look
      } = theme

      labels = Enum.map(keys, fn key -> key.label end)
      places = Enum.map(keys, fn key -> key.place end)
      label_widths = Enum.map(labels, fn label -> Font.width(label, text_look.size) end)
      title_width = Parts.legend_title_width(title, title_look)
      label_column = max(Enum.max(label_widths), title_width - key_size - text_look.margin)
      {title_rows, title_cells} = Parts.title_rows(title, title_look, 2..4)
      bar_row = 2 + length(title_rows)

      widths = [margin, key_size, text_look.margin, label_column, margin]
      heights = Enum.concat([[margin], title_rows, [@bar_keys * key_size, margin]])

      columns = length(widths)
      background = Parts.background(columns, length(heights), theme)

      scene = %Scene{
        widths: Enum.map(widths, fn width -> {:points, width} end),
        heights: Enum.map(heights, fn height -> {:points, height} end),
        keep_proportions: false,
        cells:
          Enum.concat([
            [background],
            title_cells,
            [
              bar_cell(decor, places, {bar_row, key_size}, theme),
              label_cell(labels, label_widths, {bar_row, places}, text_look)
            ]
          ])
      }

      {Enum.sum(widths), scene}
    end

    # The bar and its ticks, in the bar's row and the second column.
    defp bar_cell(decor, places, {row, bar_width}, %Theme{} = theme) do
      %Theme{legend_ticks: ticks_look, legend_ticks_length: tick_length} = theme
      reach = tick_length / bar_width

      right = Enum.map(places, fn place -> [{1 - reach, place}, {1.0, place}] end)
      left = Enum.map(places, fn place -> [{reach, place}, {0.0, place}] end)
      lines = Enum.concat(right, left)

      %Cell{
        rows: row..row,
        columns: 2..2,
        clip: :off,
        hang: :none,
        primitives: [
          %Gradient{stops: decor, stroke_width: @bar_stroke_width},
          %Polylines{
            lines: lines,
            offsets: :none,
            stroke_width: ticks_look.line_width,
            color: List.duplicate(ticks_look.color, length(lines)),
            opacity: List.duplicate(1.0, length(lines)),
            line_end: :butt,
            line_join: :round,
            mitre_limit: 10.0
          }
        ]
      }
    end

    # The labels, each at its tick's place up the bar's row, left-aligned in the label column and
    # centred on its tick as grid centres text, its baseline half its ascent below the place.
    defp label_cell(labels, label_widths, {row, places}, text_look) do
      %Cell{
        rows: row..row,
        columns: 4..4,
        clip: :off,
        hang: :none,
        primitives: [
          %Text{
            x: Enum.map(places, fn _place -> 0.0 end),
            y: places,
            labels: labels,
            widths: label_widths,
            size: text_look.size,
            family: "",
            color: List.duplicate(text_look.color, length(places)),
            opacity: List.duplicate(1.0, length(places)),
            angle: 0,
            hjust: List.duplicate(0.0, length(places)),
            offset: List.duplicate({0.0, -Font.ascent(text_look.size) / 2}, length(places)),
            check_overlap: false,
            ascent: Font.ascent(text_look.size)
          }
        ]
      }
    end
  end
end
