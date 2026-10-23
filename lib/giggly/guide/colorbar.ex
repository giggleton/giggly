defmodule Giggly.Guide.Colorbar do
  @moduledoc false

  # A colour bar, ggplot2's `guide_colourbar()` in its gradient form (`display = "gradient"`), a
  # kind of guide (`Giggly.Guide`): the colours of a continuous colour or fill scale as a bar the
  # gradient runs up, sampled at `bins` values spread evenly over the scale's limits, 15 as
  # ggplot2's gradient form takes them, with a tick across each side of the bar at each break and
  # the break's label right of it. The assembly samples the colours and places the breaks; the bar
  # draws them, as a table of its own (`Giggly.Scene`) for the box of guides beside the panels,
  # laid out as ggplot2 lays out a vertical colour bar through its legend's layout:
  #
  #   * the theme's legend margin inside the edge, each side its own;
  #   * the title, laid out as a legend's (`Giggly.Guide.Parts`);
  #   * the bar, as wide as a key and five keys long (`legend.key.width`, and `legend.key.height`
  #     times 5), the gradient filling it from its bottom, the scale's low end, to its top, with
  #     no border;
  #   * a tick at each break's place up the bar, across each side, in the theme's colour bar ticks
  #     (white when the theme sets none), reaching the theme's tick length into it, and the break's
  #     label right of the bar, the labels' left margin from it, centred on its tick, its margins
  #     above and below not counted, as ggplot2's colour bar counts only those beside its labels;
  #   * the label column as wide as the widest label and the labels' right margin, or wider when
  #     the title is wider than the bar and its labels, which leaves the room at the labels'
  #     right; with no labels, neither the column nor its margins, but the room a wider title needs
  #     right of the bar, its ticks still drawn, as ggplot2 draws a scale with no labels.
  #
  # Drawn in ggplot2's order: the background, the title, the bar, the ticks on its right side and
  # then on its left, each from the bar's inside outward, and the labels. A title or labels the
  # theme removes draw as none given; a background or ticks it removes draw nothing.

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
        legend_key_width: key_width,
        legend_key_height: key_height,
        legend_title: title_look,
        legend_text: text_look
      } = theme

      title = Parts.title(title, title_look)
      labels = Parts.labels(keys, text_look)
      places = Enum.map(keys, fn key -> key.place end)
      label_widths = Parts.label_widths(labels, text_look)
      {label_margin, labels_width} = Parts.label_columns(labels, label_widths, text_look)
      title_width = Parts.legend_title_width(title, title_look)
      label_column = max(labels_width, title_width - key_width - label_margin)
      {title_rows, title_cells} = Parts.title_rows(title, title_look, 2..4)
      bar_row = 2 + length(title_rows)

      widths = [margin.left, key_width, label_margin, label_column, margin.right]

      heights =
        Enum.concat([[margin.top], title_rows, [@bar_keys * key_height, margin.bottom]])

      columns = length(widths)
      background = Parts.background(columns, length(heights), theme)

      scene = %Scene{
        widths: Enum.map(widths, fn width -> {:points, width} end),
        heights: Enum.map(heights, fn height -> {:points, height} end),
        keep_proportions: false,
        cells:
          Enum.concat([
            background,
            title_cells,
            [bar_cell(decor, places, {bar_row, key_width}, theme)],
            label_cells(labels, label_widths, {bar_row, places}, text_look)
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
          %Gradient{stops: decor, stroke_width: @bar_stroke_width} | ticks(lines, ticks_look)
        ]
      }
    end

    # The ticks across the bar, none where the theme removes them.
    defp ticks(_lines, :none), do: []

    defp ticks(lines, look) do
      [
        %Polylines{
          lines: lines,
          offsets: :none,
          stroke_width: look.line_width,
          dashes: :none,
          color: List.duplicate(look.color, length(lines)),
          opacity: List.duplicate(1.0, length(lines)),
          line_end: look.line_end,
          line_join: :round,
          mitre_limit: 10.0
        }
      ]
    end

    # The labels, each at its tick's place up the bar's row, left-aligned in the label column and
    # centred on its tick as grid centres text, its baseline half its ascent below the place; none
    # for a bar with no labels.
    defp label_cells(labels, label_widths, {row, places}, text_look) do
      if Enum.all?(labels, fn label -> label == :none end),
        do: [],
        else: [label_cell(labels, label_widths, {row, places}, text_look)]
    end

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
