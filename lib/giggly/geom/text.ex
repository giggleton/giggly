defmodule Giggly.Geom.Text do
  @moduledoc false

  # Text, ggplot2's `geom_text()`: one label per row, its `label`, at its `x` and `y`. Its one
  # parameter, `check_overlap`, leaves out each label that would cross one drawn before it, in the
  # order of the rows, as ggplot2's `check_overlap = TRUE` does. Draw it through `Giggly.Geom`.
  #
  # Text uses `:x`, `:y`, `:label`, `:group`, `:alpha` and `:color`, and needs `:x`, `:y` and
  # `:label`; a layer may also set its `size`, `angle`, `hjust`, `vjust` and `family` for every
  # label, which reach the geom in every row, as ggplot2's `aes_params` do.
  #
  # A label is its row's value written as R's `as.character()` writes it (`Giggly.AsCharacter`):
  # `21`, `2.62`, `0.333333333333333`, `1e+05`, `TRUE`. A row missing its `x`, `y` or label
  # (`nil`, or the float `:nan`) is not drawn, as ggplot2 drops it, nor is one whose colour is
  # `:none`, R's `NA`, or missing.
  #
  # Every label is drawn as ggplot2's default text is, until aesthetics can change it: black, or its
  # row's colour, at its row's alpha as a point is (`Giggly.Geom.Mark`); 11 points, the theme's
  # base size, or the layer's `size` in millimetres times ggplot2's `.pt`; turned the layer's
  # `angle` degrees anticlockwise; centred on its place, or justified by the layer's `hjust` along
  # its baseline and `vjust` up its height, a number from 0, its start or bottom, to 1, its end or
  # top, or one of ggplot2's words: `:left`, `:center` and `:right`, `:bottom`, `:middle` and
  # `:top`, and `:inward` and `:outward`, which justify each label toward or away from the middle
  # of the panel by where it falls, as ggplot2's `compute_just()` does, swapping the two axes for
  # text turned more than 45 degrees and reversing for text turned past 135. Its height for `vjust`
  # is the ascent of "M", as R's graphics engine measures it, so a label at `vjust` 0 sits on its
  # place and one at 1 hangs from it. Each label's width is measured (`Giggly.Font`), as the scene
  # draws a label at the width measured.

  @enforce_keys [:check_overlap]
  defstruct @enforce_keys

  @type t :: %__MODULE__{check_overlap: boolean()}

  # The aesthetics a layer of text can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:alpha, :color, :group, :label, :x, :y]

  # The aesthetics a layer of text cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:label, :x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{AsCharacter, Coord, DataFrame, Font}
    alias Giggly.Geom.Mark
    alias Giggly.Scene.Text

    # ggplot2's default text: its colour, the theme's ink, and its size, the theme's base size, in
    # points; and the line height a legend key's margins are measured in lines of.
    @color "#000000"
    @font_size 11.0
    @line_height 1.2

    # ggplot2's `.pt`: font points per millimetre, which turns a `size` in millimetres into points.
    @font_points_per_millimetre 72.27 / 25.4

    # How close to the middle of the panel a label justified `:inward` or `:outward` is taken as at
    # the middle, ggplot2's `just_dir()` tolerance.
    @middle_tolerance 0.001

    # A legend key's margin round its text, in lines of the text, as `draw_key_text()` sets it.
    @key_margin_lines 0.1

    # The same margin as `draw_key_text()` measures it for the room its key needs: a tenth of a line
    # of grid's default font, 12 points at a line height of 1.2, not of the text's own, since R
    # turns the margin into centimetres outside the text's font.
    @key_measured_margin @key_margin_lines * 12 * @line_height

    # Where ggplot2's words put a label's anchor along its baseline or up its height: at its start or
    # bottom, its middle, or its end or top.
    @word_places %{left: 0.0, bottom: 0.0, center: 0.5, middle: 0.5, right: 1.0, top: 1.0}

    # Text is drawn at its x and y alone.
    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds), do: frame

    # The labels of the rows placed in the panel, each justified by where it falls, but a row missing
    # its place or label, or whose colour is `:none`.
    @impl Giggly.Geom
    def draw_panel(%{check_overlap: check_overlap}, frame, coord, panel_params) do
      placed = Coord.transform(coord, frame, panel_params)
      font_size = font_size(Mark.set(placed, :size, :none))
      angle = Mark.set(placed, :angle, 0.0)
      hjust = Mark.set(placed, :hjust, 0.5)
      vjust = Mark.set(placed, :vjust, 0.5)
      colors = Mark.colors(placed, :color, @color)

      drawn =
        [
          DataFrame.pull(placed, :x),
          DataFrame.pull(placed, :y),
          DataFrame.pull(placed, :label),
          colors,
          Mark.opacities(placed, colors)
        ]
        |> Enum.zip_with(fn row -> row end)
        |> Enum.filter(fn [x_position, y_position, label, color, _opacity] ->
          is_number(x_position) and is_number(y_position) and label not in [nil, :nan] and
            color != :none
        end)
        |> Enum.map(fn [x_position, y_position, label, color, opacity] ->
          text = AsCharacter.text(label)

          %{
            x: x_position,
            y: y_position,
            label: text,
            width: Font.width(text, font_size),
            color: Mark.hex(color),
            opacity: opacity,
            hjust: justification(hjust, x_position, y_position, angle),
            vjust: justification(vjust, y_position, x_position, angle)
          }
        end)

      ascent = Font.ascent(font_size)

      [
        %Text{
          x: Enum.map(drawn, fn label -> label.x end),
          y: Enum.map(drawn, fn label -> label.y end),
          labels: Enum.map(drawn, fn label -> label.label end),
          widths: Enum.map(drawn, fn label -> label.width end),
          size: font_size,
          family: Mark.set(placed, :family, ""),
          color: Enum.map(drawn, fn label -> label.color end),
          opacity: Enum.map(drawn, fn label -> label.opacity end),
          angle: angle,
          hjust: Enum.map(drawn, fn label -> label.hjust end),
          offset: Enum.map(drawn, fn label -> {0.0, -label.vjust * ascent} end),
          check_overlap: check_overlap,
          ascent: ascent
        }
      ]
    end

    # A legend's key: the letter "a", as ggplot2's `draw_key_text()` draws it, in the key's colour at
    # its alpha and the layer's size, angle and family, placed at its justification in the key less
    # a margin of a tenth of a line all round, that justification turned with the text as ggplot2's
    # `rotate_just()` turns it, and justified as the layer's labels are; a colour of `:none` draws
    # nothing. The margin is an offset in points, `margin * (1 - 2 * place)` across and up the key
    # as `titleGrob()` moves its text, turned into the text's own frame, along its baseline and
    # toward its top.
    @impl Giggly.Geom
    def draw_key(_geom, key) do
      case Map.get(key, :color, @color) do
        :none ->
          []

        color ->
          font_size = font_size(Map.get(key, :size, :none))
          angle = Map.get(key, :angle, 0.0)
          hjust = justification(Map.get(key, :hjust, 0.5), 0.5, 0.5, angle)
          vjust = justification(Map.get(key, :vjust, 0.5), 0.5, 0.5, angle)
          {across, up} = turned_justification(angle, hjust, vjust)
          margin = @key_margin_lines * font_size * @line_height

          {along, toward_top} =
            turned_offset({margin * (1 - 2 * across), margin * (1 - 2 * up)}, angle)

          label = "a"

          [
            %Text{
              x: [across],
              y: [up],
              labels: [label],
              widths: [Font.width(label, font_size)],
              size: font_size,
              family: Map.get(key, :family, ""),
              color: [Mark.hex(color)],
              opacity: [Mark.opacity(color, Map.get(key, :alpha))],
              angle: angle,
              hjust: [hjust],
              offset: [{along, toward_top - vjust * Font.ascent(font_size)}],
              check_overlap: false,
              ascent: Font.ascent(font_size)
            }
          ]
      end
    end

    # The room a key's text needs, as `draw_key_text()` measures it: the box round the letter "a"
    # turned with the text, as wide as its width along the baseline and as tall as the ascent of
    # "M", as grid bounds turned text, with the font's descent added across and up by the angle's
    # sine and cosine, as `titleGrob()` adds it, and the measured margin each side.
    @impl Giggly.Geom
    def key_size(_geom, key) do
      font_size = font_size(Map.get(key, :size, :none))
      radians = Map.get(key, :angle, 0.0) * :math.pi() / 180
      cosine = abs(:math.cos(radians))
      sine = abs(:math.sin(radians))
      width = Font.width("a", font_size)
      ascent = Font.ascent(font_size)
      descent = Font.descent(font_size)

      {
        width * cosine + ascent * sine + sine * descent + 2 * @key_measured_margin,
        width * sine + ascent * cosine + cosine * descent + 2 * @key_measured_margin
      }
    end

    # An offset across and up a key, in points, as the offset along a text's baseline and toward its
    # top that moves it there, the text turned `angle` degrees anticlockwise.
    defp turned_offset({across, up}, angle) do
      radians = angle * :math.pi() / 180
      cosine = :math.cos(radians)
      sine = :math.sin(radians)
      {across * cosine + up * sine, up * cosine - across * sine}
    end

    # The text's size in points: the layer's size in millimetres times `.pt`, or the theme's base
    # size.
    defp font_size(:none), do: @font_size
    defp font_size(millimetres), do: millimetres * @font_points_per_millimetre

    # A justification as a number, from ggplot2's `compute_just()`: a number as it is, a word by its
    # place, and `:inward` or `:outward` by where the label falls along its own axis, `along`, or,
    # for text turned between 45 and 135 degrees either way, along the other, `across`, reversed for
    # text turned backward or past 135 degrees.
    defp justification(just, _along, _across, _angle) when is_number(just), do: just / 1

    defp justification(just, _along, _across, _angle) when is_map_key(@word_places, just),
      do: Map.fetch!(@word_places, just)

    defp justification(just, along, across, angle) when just in [:inward, :outward] do
      turn = half_turn(angle)
      forward = turn > 45 and turn < 135
      backward = turn < -45 and turn > -135
      place = if forward or backward, do: across, else: along
      swapped = backward or abs(turn) > 135
      toward_middle = just == :inward != swapped
      side_justification(toward_middle, direction(place))
    end

    # A label on the low or high side of the panel's middle justified toward the middle or away from
    # it, and one at the middle centred.
    defp side_justification(_toward_middle, :middle), do: 0.5
    defp side_justification(true, :low), do: 0.0
    defp side_justification(true, :high), do: 1.0
    defp side_justification(false, :low), do: 1.0
    defp side_justification(false, :high), do: 0.0

    # An angle in degrees as ggplot2's `compute_just()` reads it, from -180 to 180.
    defp half_turn(angle) do
      turn = angle - 360 * Float.floor(angle / 360)
      if turn > 180, do: turn - 360, else: turn
    end

    # Which side of the panel's middle a place falls on, ggplot2's `just_dir()`.
    defp direction(place) when place < 0.5 - @middle_tolerance, do: :low
    defp direction(place) when place > 0.5 + @middle_tolerance, do: :high
    defp direction(_place), do: :middle

    # A label's justification turned with the text, as ggplot2's `rotate_just()` turns it for a
    # legend key: where in the key, across and up, the label's anchor goes.
    defp turned_justification(angle, hjust, vjust) do
      turn = angle - 360 * Float.floor(angle / 360)

      cond do
        turn < 90 -> {hjust, vjust}
        turn < 180 -> {1 - vjust, hjust}
        turn < 270 -> {1 - hjust, 1 - vjust}
        true -> {vjust, 1 - hjust}
      end
    end
  end
end
