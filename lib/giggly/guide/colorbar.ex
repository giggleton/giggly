defmodule Giggly.Guide.Colorbar do
  @moduledoc false

  # A colour bar, ggplot2's `guide_colourbar()` in its gradient form (`display = "gradient"`), a
  # kind of guide (`Giggly.Guide`): the colours of a continuous colour or fill scale as a bar the
  # gradient runs along, sampled at `bins` values spread evenly over the scale's limits, 15 as
  # ggplot2's gradient form takes them, with a tick across each side of the bar at each break and
  # the break's label beside it. The assembly samples the colours and places the breaks; the bar
  # draws them, as a table of its own (`Giggly.Scene`) for the box of guides beside or inside the
  # panels, laid out as ggplot2 lays out a colour bar through its legend's layout, running up
  # (`:vertical`) or across (`:horizontal`) as rendering says:
  #
  #   * the theme's legend margin inside the edge, each side its own;
  #   * the title, laid out as a legend's (`Giggly.Guide.Parts`): above a bar running up, left of
  #     one running across, the room a title bigger than the bar and its labels leaves split by its
  #     justification;
  #   * the bar, running up, as wide as a key and five keys long (`legend.key.width`, and
  #     `legend.key.height` times 5), the gradient filling it from its bottom, the scale's low end,
  #     to its top; running across, five keys long and as tall as a key, the gradient from its left
  #     to its right; with no border;
  #   * a tick at each break's place along the bar, across each side, in the theme's colour bar
  #     ticks (white when the theme sets none), reaching the theme's tick length into it, and the
  #     break's label beside the bar at its tick, placed as `Giggly.Guide.Parts` places a text:
  #     running up, right of it (`legend_text_right`, left-aligned and centred on its tick unless
  #     the theme says otherwise), its margins either side counted; running across, below it
  #     (`legend_text_bottom`, centred and hung), its margins above and below counted, as ggplot2's
  #     colour bar counts only those across its labels;
  #   * running up, the labels' margin and their column, as wide as the labels turned, measured
  #     together as one grob measures them, and the labels' right margin; running across, the
  #     labels' row as deep as they are turned and their margins above and below; with no labels,
  #     neither the column or row nor its margins, its ticks still drawn, as ggplot2 draws a scale
  #     with no labels.
  #
  # Drawn in ggplot2's order: the background, the title, the bar, the ticks on its right side and
  # then on its left, or on its bottom and then its top, each from the bar's inside outward, and
  # the labels. A title or labels the theme removes draw as none given; a background or ticks it
  # removes draw nothing.

  @enforce_keys [:bins]
  defstruct @enforce_keys

  @type t :: %__MODULE__{bins: pos_integer()}

  defimpl Giggly.Guide, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Guide

    alias Giggly.Guide.Parts
    alias Giggly.{Scene, Theme}
    alias Giggly.Scene.{Cell, Gradient, Polylines}

    # The bar is five keys long, as ggplot2's colour bar multiplies `legend.key.height` by 5.
    @bar_keys 5

    # The bar's rectangle is drawn with no border, at grid's default line width, 1, which svglite
    # writes in points.
    @bar_stroke_width 72 / 96

    # The colour bar titled `title`, running `direction`, its bar the gradient through `decor`,
    # each its place along the bar, 0 to 1, and its colour, and a tick and label for each of
    # `keys`, each its place and its label, in `theme`'s look: its width in points and its table,
    # every size in points.
    @impl Giggly.Guide
    def draw(_guide, %{title: title, keys: keys, decor: decor, direction: direction}, theme) do
      %Theme{legend_margin: margin} = theme
      places = Enum.map(keys, fn key -> key.place end)
      {widths, heights, cells} = lay_out(direction, {title, keys}, {decor, places}, theme)
      widths = Enum.concat([[margin.left], widths, [margin.right]])
      heights = Enum.concat([[margin.top], heights, [margin.bottom]])

      columns = length(widths)
      background = Parts.background(columns, length(heights), theme)

      scene = %Scene{
        widths: Enum.map(widths, fn width -> {:points, width} end),
        heights: Enum.map(heights, fn height -> {:points, height} end),
        keep_proportions: false,
        cells: Enum.concat(background, cells)
      }

      {Enum.sum(widths), scene}
    end

    # The bar's widths and heights inside the legend's margin, and its cells after the
    # background: the title's, the bar's and the labels'.
    defp lay_out(:vertical, {title, keys}, {decor, places}, %Theme{} = theme) do
      %Theme{
        legend_key_width: key_width,
        legend_key_height: key_height,
        legend_title_top: title_look,
        legend_text_right: text_look
      } = theme

      title = Parts.title(title, title_look)
      labels = Parts.labels(keys, text_look)
      {label_margin, labels_width} = label_column(labels, text_look)

      {widths, title_heights, first, title_cells} =
        Parts.title_above(title, title_look, [key_width, label_margin, labels_width])

      bar_row = 2 + length(title_heights)

      cells =
        Enum.concat([
          title_cells,
          [bar_cell({decor, :up}, ticks_up(places, key_width, theme), {bar_row, first}, theme)],
          right_label_cells(labels, {bar_row, (first + 1)..(first + 2)}, places, text_look)
        ])

      {widths, Enum.concat(title_heights, [@bar_keys * key_height]), cells}
    end

    defp lay_out(:horizontal, {title, keys}, {decor, places}, %Theme{} = theme) do
      %Theme{
        legend_key_width: key_width,
        legend_key_height: key_height,
        legend_title_left: title_look,
        legend_text_bottom: text_look
      } = theme

      title = Parts.title(title, title_look)
      labels = Parts.labels(keys, text_look)
      label_height = label_row(labels, text_look)

      {title_widths, heights, first, title_cells} =
        Parts.title_column(title, title_look, [key_height, label_height])

      cells =
        Enum.concat([
          title_cells,
          [
            bar_cell(
              {decor, :across},
              ticks_across(places, key_height, theme),
              {first, first},
              theme
            )
          ],
          below_label_cells(labels, {first + 1, first}, places, text_look)
        ])

      bar_length = @bar_keys * key_width
      {Enum.concat(title_widths, [bar_length]), heights, cells}
    end

    # The bar and its ticks, in its row and column.
    defp bar_cell({decor, direction}, ticks, {row, column}, %Theme{legend_ticks: ticks_look}) do
      %Cell{
        rows: row..row,
        columns: column..column,
        clip: :off,
        hang: :none,
        primitives: [
          %Gradient{stops: decor, direction: direction, stroke_width: @bar_stroke_width}
          | ticks(ticks, ticks_look)
        ]
      }
    end

    # The ticks of a bar running up, `bar_width` points wide: across its right side at each
    # place, then its left, each from inside the bar outward.
    defp ticks_up(places, bar_width, %Theme{legend_ticks_length: tick_length}) do
      reach = tick_length / bar_width
      right = Enum.map(places, fn place -> [{1 - reach, place}, {1.0, place}] end)
      left = Enum.map(places, fn place -> [{reach, place}, {0.0, place}] end)
      Enum.concat(right, left)
    end

    # The ticks of a bar running across, `bar_height` points tall: across its bottom at each
    # place, then its top, each from inside the bar outward.
    defp ticks_across(places, bar_height, %Theme{legend_ticks_length: tick_length}) do
      reach = tick_length / bar_height
      bottom = Enum.map(places, fn place -> [{place, reach}, {place, 0.0}] end)
      top = Enum.map(places, fn place -> [{place, 1 - reach}, {place, 1.0}] end)
      Enum.concat(bottom, top)
    end

    # The ticks across the bar, dashed as the theme says; none where the theme removes them or
    # gives them the blank line type.
    defp ticks(_lines, :none), do: []
    defp ticks(_lines, %{dashes: :blank}), do: []

    defp ticks(lines, look) do
      [
        %Polylines{
          lines: lines,
          offsets: :none,
          stroke_width: look.line_width,
          dashes: look.dashes,
          color: List.duplicate(look.color, length(lines)),
          opacity: List.duplicate(look.opacity, length(lines)),
          line_end: look.line_end,
          line_join: :round,
          mitre_limit: 10.0
        }
      ]
    end

    # The labels' margin beside a bar running up and their column, as wide as the labels turned,
    # measured together as ggplot2's colour bar measures its one grob of labels, and their right
    # margin; none of either for a bar with no labels.
    defp label_column(labels, look) do
      if unlabelled?(labels) do
        {0.0, 0.0}
      else
        {width, _height} = Parts.extent(labels, look)
        {look.margin.left, width + look.margin.right}
      end
    end

    # How deep the labels' row below a bar running across is: the labels turned, measured together,
    # and their margins above and below; none for a bar with no labels.
    defp label_row(labels, look) do
      if unlabelled?(labels) do
        0.0
      else
        {_width, height} = Parts.extent(labels, look)
        look.margin.top + height + look.margin.bottom
      end
    end

    # The labels of a bar running up, each at its tick's place up the bar's row, across at its
    # turned justification of the labels' margin and column, its margins either side counted;
    # none for a bar with no labels.
    defp right_label_cells(labels, {row, columns}, places, text_look) do
      if unlabelled?(labels) do
        []
      else
        {{across, _up}, offset} = Parts.anchor(text_look, :across)
        label_places = Enum.map(places, fn place -> {across, place} end)
        [label_cell(Parts.text(labels, label_places, offset, text_look), {row..row, columns})]
      end
    end

    # The labels of a bar running across, each at its tick's place along the bar's column, up at
    # its turned justification of the labels' row below the bar, its margins above and below
    # counted; none for a bar with no labels.
    defp below_label_cells(labels, {row, column}, places, text_look) do
      if unlabelled?(labels) do
        []
      else
        {{_across, up}, offset} = Parts.anchor(text_look, :up)
        label_places = Enum.map(places, fn place -> {place, up} end)

        [
          label_cell(
            Parts.text(labels, label_places, offset, text_look),
            {row..row, column..column}
          )
        ]
      end
    end

    # Whether a bar has no labels: every key's is `:none`, as a scale with no labels or labels the
    # theme removes leave them.
    defp unlabelled?(labels), do: Enum.all?(labels, fn label -> label == :none end)

    defp label_cell(text, {rows, columns}) do
      %Cell{rows: rows, columns: columns, clip: :off, hang: :none, primitives: [text]}
    end
  end
end
