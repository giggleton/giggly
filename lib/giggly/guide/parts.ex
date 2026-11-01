defmodule Giggly.Guide.Parts do
  @moduledoc false

  # The parts the guides of aesthetics other than position build their tables from, alike in a
  # legend (`Giggly.Guide.Legend`) and the bar a colour bar and colour steps share
  # (`Giggly.Guide.Bar`), as ggplot2's
  # `GuideColourbar` lays itself out through `GuideLegend`'s measuring and arranging: the
  # background over the whole table, the title above or left of the keys with the room a title
  # bigger than them leaves, a label in its cell, how wide the labels are and how far from the
  # keys; and the title and labels as the theme leaves them, none where it removes them, so a
  # guide draws them as it draws a title or labels it is not given.
  #
  # And the one rule every text a guide draws is placed and measured by, ggplot2's `titleGrob()`:
  # an axis's labels and title, a strip's label, a legend's title and labels, the plot's titles.
  # A text is drawn in its look's family and face, turned its angle, and justified by its `hjust`
  # and `vjust` in its own turned frame, as grid's text grob draws it. It is anchored in its room at
  # its justification turned with it a quarter turn at a time (`turned_justification/1`, ggplot2's
  # `rotate_just()`), moved by the margins it counts (`anchor/2`), and it is as wide and as deep as
  # the box grid's text grob takes, turned, with the font's descent turned with it added
  # (`extent/3`): a level label is a line of text deep, one turned 90 degrees as deep as it is
  # wide. A text may run over several lines, split where it breaks, each line drawn by itself as
  # R's graphics engine draws one, a line spacing below the one before, stacked `vjust` of the way
  # down from their top: the baseline of line `i` of `n`, counting from 0, is
  # `((1 - vjust)(n - 1) - i)` line spacings above the anchor, less `vjust` of a line's ascent; a
  # text is as deep as its lines spaced out and an ascent, as grid measures one, and as wide as its
  # widest line. Every text breaks so, a tick label, a legend's label and a strip's as a title.
  # A guide's labels that hold a power are expressions (`Giggly.Guide.Plotmath`), each measured as
  # its box, as wide as it is and as deep as it reaches above and below its baseline, and drawn as
  # its pieces, each a text of its own, its box justified as a text is.

  alias Giggly.{Font, Theme}
  alias Giggly.Guide.Plotmath
  alias Giggly.Scene.{Cell, Rect, Text}

  @typedoc "A text a guide draws: a string, or an expression (`Giggly.Guide.Plotmath`)."
  @type label :: String.t() | Plotmath.t()

  # The guide's background, spanning a table of `columns` and `rows`, in `theme`'s look: its cell,
  # or none where the theme removes it.
  @doc false
  @spec background(pos_integer(), pos_integer(), Theme.t()) :: [Cell.t()]
  def background(_columns, _rows, %Theme{legend_background: :none}), do: []

  def background(columns, rows, %Theme{legend_background: look}) do
    [
      %Cell{
        rows: 1..rows,
        columns: 1..columns,
        clip: :off,
        hang: :none,
        primitives: [
          %Rect{
            fill: look.fill,
            fill_opacity: look.fill_opacity,
            color: look.color,
            color_opacity: look.color_opacity,
            stroke_width: look.line_width,
            dashes: look.dashes
          }
        ]
      }
    ]
  end

  # A guide's title as drawn in `look`: `:none` where the theme removes the title, so the guide
  # draws as one with no title, as ggplot2's does.
  @doc false
  @spec title(String.t() | :none, Theme.text()) :: String.t() | :none
  def title(_title, :none), do: :none
  def title(title, _look), do: title

  # The labels of a guide's `keys` as drawn in `look`: each `:none` where the theme removes the
  # labels, so the guide draws as one whose scale has no labels, as ggplot2's does; and each an
  # expression where any is (`Giggly.Guide.Plotmath.expressions/1`).
  @doc false
  @spec labels([%{label: label() | :none}], Theme.text()) :: [label() | :none]
  def labels(keys, :none), do: Enum.map(keys, fn _key -> :none end)

  def labels(keys, _look) do
    keys
    |> Enum.map(fn key -> key.label end)
    |> Plotmath.expressions()
  end

  # A legend's title above its keys, in `look`, over a grid of `widths`, left to right: the widths
  # with the room a title wider than the grid leaves, split by the title's turned justification,
  # left of the grid and right of it, as ggplot2's `add_title()` adds it; the title's row, as deep as
  # it and its margins above and below; the column the grid then starts at; and the title's cell,
  # spanning the grid's columns, the title anchored in it as `anchor/2` places it. A title of
  # `:none` takes no room, as ggplot2's legend leaves out a title it is given as `NULL`.
  @doc false
  @spec title_above(String.t() | :none, Theme.text(), [float()], boolean()) ::
          {[float()], [float()], pos_integer(), [Cell.t()]}
  def title_above(:none, _look, widths, _installed_fonts), do: {widths, [], 2, []}

  def title_above(title, %{margin: margin} = look, widths, installed_fonts) do
    {title_width, title_height} = extent([title], look, installed_fonts)
    extra = max(margin.left + title_width + margin.right - Enum.sum(widths), 0.0)
    {across, _up} = turned_justification(look)

    {with_room, first} =
      if extra > 0,
        do: {Enum.concat([[across * extra], widths, [(1 - across) * extra]]), 3},
        else: {widths, 2}

    {place, offset} = anchor(look, :both)

    cell = %Cell{
      rows: 2..2,
      columns: first..(first + length(widths) - 1),
      clip: :off,
      hang: :none,
      primitives: text([title], [place], offset, look, installed_fonts)
    }

    {with_room, [margin.top + title_height + margin.bottom], first, [cell]}
  end

  # A legend's title left of its keys, in `look`, beside a grid whose rows are `heights` points
  # tall: the title's column, as wide as it and its margins either side; the grid's heights with
  # the room a title taller than them leaves, split by the title's turned justification, above the
  # grid and below it, as ggplot2's `add_title()` adds it; the row and the column the grid then
  # starts at; and the title's cell, spanning the grid's rows, the title anchored in it as
  # `anchor/2` places it. A title of `:none` takes no room.
  @doc false
  @spec title_column(String.t() | :none, Theme.text(), [float()], boolean()) ::
          {[float()], [float()], pos_integer(), [Cell.t()]}
  def title_column(:none, _look, heights, _installed_fonts), do: {[], heights, 2, []}

  def title_column(title, %{margin: margin} = look, heights, installed_fonts) do
    {title_width, title_height} = extent([title], look, installed_fonts)
    extra = max(margin.top + title_height + margin.bottom - Enum.sum(heights), 0.0)
    {_across, up} = turned_justification(look)
    {place, offset} = anchor(look, :both)

    cell = %Cell{
      rows: 3..(length(heights) + 2),
      columns: 2..2,
      clip: :off,
      hang: :none,
      primitives: text([title], [place], offset, look, installed_fonts)
    }

    heights = Enum.concat([[(1 - up) * extra], heights, [up * extra]])
    {[margin.left + title_width + margin.right], heights, 3, [cell]}
  end

  # `label` in `look`, in a cell of `row` and `columns`, the labels' margin before it and their
  # column, anchored as `anchor/2` places it, counting its margins on every side.
  @doc false
  @spec label_cell(label(), Theme.text(), pos_integer(), Range.t(), boolean()) :: Cell.t()
  def label_cell(label, look, row, columns, installed_fonts) do
    {place, offset} = anchor(look, :both)

    %Cell{
      rows: row..row,
      columns: columns,
      clip: :off,
      hang: :none,
      primitives: text([label], [place], offset, look, installed_fonts)
    }
  end

  # How wide each of a guide's `labels` is in `look`, turned, in points, a label of `:none` taking
  # no room.
  @doc false
  @spec label_widths([label() | :none], Theme.text(), boolean()) :: [float()]
  def label_widths(labels, look, installed_fonts) do
    Enum.map(labels, fn
      :none ->
        0.0

      label ->
        {width, _height} = extent([label], look, installed_fonts)
        width
    end)
  end

  # The margin between a guide's keys and its labels, the labels' left margin in `look`, and the
  # labels' column, the widest of `label_widths` and the labels' right margin: none of either when
  # every label is `:none`, as ggplot2 leaves out the labels and their margins for a scale with no
  # labels, or for labels the theme removes, whose `look` is `:none`.
  @doc false
  @spec label_columns([label() | :none], [float()], Theme.text()) :: {float(), float()}
  def label_columns(labels, label_widths, look) do
    if Enum.all?(labels, fn label -> label == :none end),
      do: {0.0, 0.0},
      else: {look.margin.left, Enum.max(label_widths) + look.margin.right}
  end

  # How tall a guide's label is in `look`, turned, its margins above and below it included: none
  # for `:none`.
  @doc false
  @spec label_height(label() | :none, Theme.text(), boolean()) :: float()
  def label_height(:none, _look, _installed_fonts), do: 0.0

  def label_height(label, %{margin: margin} = look, installed_fonts) do
    {_width, height} = extent([label], look, installed_fonts)
    margin.top + height + margin.bottom
  end

  # The share of its room across and up that a text in `look` is anchored at: its justification
  # turned with it a quarter turn at a time, as ggplot2's `rotate_just()` turns it, since grid
  # justifies text in its own turned frame. A quarter turn takes `{1 - vjust, hjust}`, a half turn
  # `{1 - hjust, 1 - vjust}`, three quarters `{vjust, 1 - hjust}`.
  @doc false
  @spec turned_justification(Theme.text()) :: {float(), float()}
  def turned_justification(%{angle: angle, hjust: hjust, vjust: vjust}) do
    case trunc(turned_angle(angle) / 90) do
      0 -> {hjust, vjust}
      1 -> {1 - vjust, hjust}
      2 -> {1 - hjust, 1 - vjust}
      3 -> {vjust, 1 - hjust}
    end
  end

  # Where a text in `look` is anchored in its room, as ggplot2's `titleGrob()` places it: across
  # and up, the share of the room its turned justification gives, and the points its margins move
  # it, `-right * across + left * (1 - across)` across when `counted` is `:across` or `:both`, and
  # likewise up with its bottom and top when `:up` or `:both`, none otherwise.
  @doc false
  @spec anchor(Theme.text(), :across | :up | :both) ::
          {{float(), float()}, {float(), float()}}
  def anchor(%{margin: margin} = look, counted) do
    {across, up} = turned_justification(look)

    across_offset =
      if counted in [:across, :both],
        do: -margin.right * across + margin.left * (1 - across),
        else: 0.0

    up_offset =
      if counted in [:up, :both],
        do: -margin.top * up + margin.bottom * (1 - up),
        else: 0.0

    {{across, up}, {across_offset, up_offset}}
  end

  # How wide and how deep `texts` drawn in `look` at one anchor are, in points, as ggplot2's
  # `titleGrob()` measures them: the box grid's text grob takes round each text, as wide as its
  # widest line and as deep as its lines spaced out and an ascent, or an expression's box,
  # justified at the anchor and
  # turned with it, every text's box together; then the font's descent turned too, its sine added
  # across and its cosine up. An axis's labels or a colour bar's are measured together, as one grob
  # holds them; ggplot2 measures them along a line, so only the way across it counts.
  @doc false
  @spec extent([label()], Theme.text(), boolean()) :: {float(), float()}
  def extent(texts, look, installed_fonts) do
    radians = look.angle / 180 * :math.pi()
    cosine = :math.cos(radians)
    sine = :math.sin(radians)
    ascent = Font.ascent(look.size, look.family, look.face, installed_fonts)

    corners =
      Enum.flat_map(texts, fn text ->
        {width, height} = measured(text, look, ascent, installed_fonts)

        for across <- [-look.hjust * width, width - look.hjust * width],
            up <- [-look.vjust * height, height - look.vjust * height],
            do: {across * cosine - up * sine, across * sine + up * cosine}
      end)

    {left, right} =
      corners
      |> Enum.map(fn {across, _up} -> across end)
      |> Enum.min_max()

    {bottom, top} =
      corners
      |> Enum.map(fn {_across, up} -> up end)
      |> Enum.min_max()

    descent = Font.descent(look.size, look.family, look.face, installed_fonts)
    descent_radians = turned_angle(look.angle) / 180 * :math.pi()

    {right - left + abs(:math.sin(descent_radians)) * descent,
     top - bottom + abs(:math.cos(descent_radians)) * descent}
  end

  # How wide and how high one text drawn in `look` is, unturned, before its descent: as wide as its
  # widest line and as high as its lines spaced out and an ascent, or an expression's box,
  # `Giggly.Guide.Plotmath`'s, as wide as it is and as high and as deep as it reaches.
  defp measured(text, look, ascent, installed_fonts) when is_binary(text) do
    lines = lines(text)

    width =
      lines
      |> Enum.map(fn line ->
        Font.width(line, look.size, look.family, look.face, installed_fonts)
      end)
      |> Enum.max()

    {width, (length(lines) - 1) * look.line_spacing + ascent}
  end

  defp measured(expression, look, _ascent, installed_fonts) do
    {{width, height, depth}, _pieces} = Plotmath.layout(expression, look, installed_fonts)
    {width, height + depth}
  end

  # `texts` drawn in `look`, each anchored at its place in its cell, `places`, and moved `offset`
  # points across and up the cell, as `anchor/2` moves a text by its margins: turned, justified
  # `hjust` along its baseline, and each line stacked `vjust` of the way down from its top, every
  # line a label of its own, as grid's text grob draws them: one text, or, where any of `texts` is
  # an expression, a text for each piece of each.
  @doc false
  @spec text(
          [label()],
          [{float(), float()}],
          {float(), float()},
          Theme.text(),
          boolean()
        ) :: [Text.t()]
  def text(texts, places, offset, look, installed_fonts) do
    if Enum.any?(texts, &Plotmath.expression?/1),
      do: expressions(texts, places, offset, look, installed_fonts),
      else: [plain_text(texts, places, offset, look, installed_fonts)]
  end

  # Expressions drawn in `look` as `Giggly.Guide.Plotmath` lays them out, each at its place: each
  # piece a text of its own, in the order plotmath draws them, an expression's after the one
  # before, started where its layout puts it from the expression's start, which is justified
  # `hjust` of its width along the baseline and `vjust` of its height and depth up, its baseline
  # its depth above its bottom, as `GEMathText()` justifies its box.
  defp expressions(texts, places, offset, look, installed_fonts) do
    {along, up} = in_text_frame(offset, look.angle)

    texts
    |> Enum.zip_with(places, fn text, place ->
      {{width, height, depth}, pieces} =
        text
        |> as_expression()
        |> Plotmath.layout(look, installed_fonts)

      start = {along - look.hjust * width, up + depth - look.vjust * (height + depth)}
      Enum.map(pieces, fn piece -> piece_text(piece, place, start, look, installed_fonts) end)
    end)
    |> Enum.concat()
  end

  defp as_expression(text) when is_binary(text), do: {:string, text}
  defp as_expression(expression), do: expression

  # A piece of an expression, a text of one label at its size and face, started at its place from
  # the expression's start.
  defp piece_text(
         {text, size, face, {piece_along, piece_up}},
         place,
         {along, up},
         look,
         installed_fonts
       ) do
    {x_place, y_place} = place

    %Text{
      x: [x_place],
      y: [y_place],
      labels: [text],
      widths: [Font.width(text, size, look.family, face, installed_fonts)],
      size: size,
      family: look.family,
      face: face,
      color: [look.color],
      opacity: [look.opacity],
      angle: look.angle,
      hjust: [0.0],
      offset: [{along + piece_along, up + piece_up}],
      check_overlap: false,
      ascent: Font.ascent(size, look.family, face, installed_fonts),
      glyphs: Font.glyphs([text], size, look.family, face, installed_fonts)
    }
  end

  defp plain_text(texts, places, offset, look, installed_fonts) do
    ascent = Font.ascent(look.size, look.family, look.face, installed_fonts)
    {along, up} = in_text_frame(offset, look.angle)

    lines =
      texts
      |> Enum.zip_with(places, fn text, place ->
        lines = lines(text)
        count = length(lines)

        Enum.with_index(lines, fn line, index ->
          stacked = ((1 - look.vjust) * (count - 1) - index) * look.line_spacing
          {line, place, {along, up + stacked - look.vjust * ascent}}
        end)
      end)
      |> Enum.concat()

    count = length(lines)

    %Text{
      x: Enum.map(lines, fn {_line, {x_place, _y_place}, _offset} -> x_place end),
      y: Enum.map(lines, fn {_line, {_x_place, y_place}, _offset} -> y_place end),
      labels: Enum.map(lines, fn {line, _place, _offset} -> line end),
      widths:
        Enum.map(lines, fn {line, _place, _offset} ->
          Font.width(line, look.size, look.family, look.face, installed_fonts)
        end),
      size: look.size,
      family: look.family,
      face: look.face,
      color: List.duplicate(look.color, count),
      opacity: List.duplicate(look.opacity, count),
      angle: look.angle,
      hjust: List.duplicate(look.hjust, count),
      offset: Enum.map(lines, fn {_line, _place, offset} -> offset end),
      check_overlap: false,
      ascent: ascent,
      glyphs:
        lines
        |> Enum.map(fn {line, _place, _offset} -> line end)
        |> Font.glyphs(look.size, look.family, look.face, installed_fonts)
    }
  end

  # An offset `{across, up}` in a cell's frame, in points, as an offset along and up a text turned
  # `angle` degrees, the frame a text's offset is given in.
  @doc false
  @spec in_text_frame({float(), float()}, number()) :: {float(), float()}
  def in_text_frame({across, up}, angle) do
    radians = angle / 180 * :math.pi()
    cosine = :math.cos(radians)
    sine = :math.sin(radians)
    {across * cosine + up * sine, up * cosine - across * sine}
  end

  # A text's lines, split where it breaks.
  defp lines(text), do: String.split(text, "\n")

  # An angle in degrees as R's `%% 360` takes it, from 0 up to 360.
  defp turned_angle(angle) do
    once = angle - Float.floor(angle / 360) * 360
    once - Float.floor(once / 360) * 360
  end
end
