defmodule Giggly.Geom.Label do
  @moduledoc false

  # Labels, ggplot2's `GeomLabel`, which `geom_label()` draws with: each row's `label` as text on a
  # box with rounded corners, at its `x` and `y`, so it reads over what is drawn beneath. Its
  # parameters are R's: the room left round the text on each side (`label_padding`, `top`, `right`,
  # `bottom` and `left`, ggplot2's `label.padding`), the radius of the box's corners (`label_r`,
  # ggplot2's `label.r`), each a number of points, `{points, :points}`, or of lines of the label's
  # own text, `{lines, :lines}`, as grid works out a unit of `"lines"` in the label's font; and
  # the colours of the box's border and of the text (`border_color`, `text_color`, ggplot2's
  # `border.colour` and `text.colour`), each a colour, `:none`, R's `NA`, or `:color`, the row's
  # own, as ggplot2's `NULL` gives it. Use it through `Giggly.Geom`.
  #
  # Labels use `:x`, `:y`, `:label`, `:group`, `:alpha`, `:color`, `:fill`, `:linetype` and
  # `:linewidth`, and need `:x`, `:y` and `:label`; a layer may also set the size, angle,
  # justification and family of every label, as a text layer may (`Giggly.Geom.Text`).
  #
  # A label is drawn as ggplot2's `labelGrob()` draws one, a row at a time, its box and then its
  # text, so a later label covers an earlier, each placed through the coordinate system
  # (`Giggly.Coord.transform/3`) and turned its layer's `angle` about its place, box and text
  # alike. Its text is set as a text layer's is, its value written as R's `as.character()` writes
  # it (`Giggly.AsCharacter`), its size in millimetres times `.pt`, measured (`Giggly.Font`), and
  # justified by `hjust` and `vjust` as text is, `:inward` and `:outward` by where it falls in the
  # panel. Its box is the text's width with the padding either side across, and up the ascent of
  # "M" and the font's descent, with the padding above, at least the descent, and below, less the
  # descent, as `labelGrob()` balances them, so the baseline sits the bottom padding up whatever
  # the descent; the box is placed by `hjust` across and `vjust` up, as the text is, and its text
  # set in it at the padding from its edges. The box is the polygon grid's `roundrectGrob()` draws:
  # its straight edges, and at each corner 11 of 40 points evenly round a circle of the corner's
  # radius, 10 at its top right, as grid's `roundCorner()` picks them, its steps a 39th of a turn,
  # so each arc starts a little short of its edge, as R's does; a radius greater than half the box
  # is drawn as given, as grid draws it. A row missing its place or label is not drawn; one whose
  # colour is `:none` keeps its box, as R's does, its text written in no colour.
  #
  # Every label is drawn as ggplot2's default label is under the plot's theme, but where its layer
  # maps or sets its look: its text and border in the theme's ink, or the row's colour, unless
  # `text_color` or `border_color` gives another, each at its colour's own alpha, never the row's;
  # its box filled with the theme's paper, or the row's fill, at the row's alpha, as ggplot2's
  # `fill_alpha()` applies it; its border half as wide as the theme's borders, 0.25 mm at its
  # default sizes, and in their line type, dashed as a rectangle's is, none where it is 0 wide,
  # blank or missing, its corners and ends grid's, round. Its legend key is ggplot2's
  # `draw_key_label()`: the letter "a" on its box, drawn as a label is.

  @enforce_keys [:label_padding, :label_r, :border_color, :text_color]
  defstruct @enforce_keys

  @typedoc "A length a label is drawn at: a number of points, or of lines of its own text."
  @type measure :: {float(), :points | :lines}

  @typedoc "A colour of a label's border or text: a colour, `:none`, or `:color`, the row's own."
  @type part_color :: String.t() | :none | :color

  @type t :: %__MODULE__{
          label_padding: %{top: measure(), right: measure(), bottom: measure(), left: measure()},
          label_r: measure(),
          border_color: part_color(),
          text_color: part_color()
        }

  # The aesthetics a layer of labels can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics,
    do: [:alpha, :color, :fill, :group, :label, :linetype, :linewidth, :x, :y]

  # The aesthetics a layer of labels cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:label, :x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{AsCharacter, Coord, DataFrame, Font, Geom, Scene}
    alias Giggly.Geom.Mark

    # grid's line height, which a label's lines of text are measured at, since `labelGrob()` gives
    # its viewport the label's font size alone.
    @line_height 1.2

    # The font a key's padding is measured in for the room it needs: grid's default, 12 points, not
    # the label's own, since R turns the padding into centimetres outside the label's font.
    @key_measured_font_size 12

    # The widest a key's border is that `draw_key_label()` takes as none, `all.equal()`'s tolerance,
    # the square root of a double's epsilon, 2 to the -26, where a label's own border is none only
    # at 0.
    @key_no_border_width 1.4901161193847656e-8

    # How many points grid's `roundCorner()` puts round a whole circle, and which of them it draws
    # at each corner, counting from 0 at the circle's right, a 39th of a turn apart.
    @circle_points 40
    @corner_steps %{
      bottom_right: 29..39,
      top_right: 0..9,
      top_left: 9..19,
      bottom_left: 19..29
    }

    # grid's line ends, corners and mitre limit, which `labelGrob()` draws its box with.
    @line_end :round
    @line_join :round
    @mitre_limit 10.0

    # The letter a legend's key draws, as `draw_key_label()` writes one where the key has no label.
    @key_label "a"

    # ggplot2's `GeomLabel$default_aes`, as far as Giggly draws labels: the theme's ink, its paper,
    # its text's family and size, no angle, centred both ways, no alpha, and half its borders'
    # width, in their line type.
    @impl Giggly.Geom
    def default_aesthetics(_geom, element) do
      [
        color: element.ink,
        fill: element.paper,
        family: element.family,
        size: element.fontsize,
        angle: 0.0,
        hjust: 0.5,
        vjust: 0.5,
        alpha: nil,
        linewidth: element.borderwidth * 0.5,
        linetype: element.bordertype
      ]
    end

    # A label is drawn at its x and y alone.
    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds), do: frame

    # Each row placed in the panel as its box and then its text, justified by where it falls, but a
    # row missing its place or label.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params) do
      placed = Coord.transform(coord, frame, panel_params)

      font_size =
        placed
        |> Mark.set(:size)
        |> Geom.Text.font_size()

      angle = Mark.set(placed, :angle)
      hjust = Mark.set(placed, :hjust)
      vjust = Mark.set(placed, :vjust)

      layout =
        geom
        |> layout(font_size, font_size)
        |> Map.merge(%{angle: angle, family: Mark.set(placed, :family)})

      colors = Mark.colors(placed, :color)
      fills = Mark.colors(placed, :fill)

      [
        DataFrame.pull(placed, :x),
        DataFrame.pull(placed, :y),
        DataFrame.pull(placed, :label),
        colors,
        fills,
        Mark.opacities(placed, fills),
        DataFrame.pull(placed, :linewidth),
        Mark.line_types(placed)
      ]
      |> Enum.zip_with(fn row -> row end)
      |> Enum.filter(fn [x_position, y_position, label | _look] ->
        is_number(x_position) and is_number(y_position) and label not in [nil, :nan]
      end)
      |> Enum.flat_map(fn [x_position, y_position, label, color, fill, opacity, width, line_type] ->
        look = %{
          text: part_color(geom.text_color, color),
          border: border(part_color(geom.border_color, color), width, line_type),
          fill: fill,
          fill_opacity: opacity,
          width: width || 0.0,
          line_type: line_type
        }

        justification = {
          Geom.Text.justification(hjust, x_position, y_position, angle),
          Geom.Text.justification(vjust, y_position, x_position, angle)
        }

        label({x_position, y_position}, 0.0, AsCharacter.text(label), justification, look, layout)
      end)
    end

    # A legend's key, as ggplot2's `draw_key_label()` draws one: the letter "a" as a label in the
    # key's look and the layer's size, angle, family, padding and corners, at its justification in
    # the key, `:inward` and `:outward` read against the key's middle, so centred, turned with the
    # text as ggplot2's `rotate_just()` turns it, and lifted by the descent of a font as many points
    # as the key's size is millimetres, as R hands `font_descent()` the size in millimetres; its
    # border none at a width `all.equal()` takes as 0.
    @impl Giggly.Geom
    def draw_key(geom, key) do
      font_size =
        key
        |> Map.fetch!(:size)
        |> Geom.Text.font_size()

      angle = Map.fetch!(key, :angle)

      hjust =
        key
        |> Map.fetch!(:hjust)
        |> Geom.Text.justification(0.5, 0.5, 0.0)

      vjust =
        key
        |> Map.fetch!(:vjust)
        |> Geom.Text.justification(0.5, 0.5, 0.0)

      color = Mark.key_color(key, :color)
      fill = Mark.key_color(key, :fill)
      width = Map.fetch!(key, :linewidth)
      line_type = Map.fetch!(key, :linetype) || :none

      look = %{
        text: part_color(geom.text_color, color),
        border: key_border(part_color(geom.border_color, color), width, line_type),
        fill: fill,
        fill_opacity: Mark.opacity(fill, Map.fetch!(key, :alpha)),
        width: width || 0.0,
        line_type: line_type
      }

      layout =
        geom
        |> layout(font_size, font_size)
        |> Map.merge(%{angle: angle, family: Map.fetch!(key, :family)})

      lift =
        key
        |> Map.fetch!(:size)
        |> Font.descent()

      place = Geom.Text.turned_justification(angle, hjust, vjust)
      label(place, lift, @key_label, {hjust, vjust}, look, layout)
    end

    # The room a key's label needs, as `draw_key_label()` measures it: its text's box, the letter
    # "a" with its padding, turned with the text, the padding measured in lines of grid's default
    # font, not the label's own, though the box is drawn in the label's, so a label of a larger font
    # than grid's spills out of its key, as R's does.
    @impl Giggly.Geom
    def key_size(geom, key) do
      font_size =
        key
        |> Map.fetch!(:size)
        |> Geom.Text.font_size()

      {width, height} =
        @key_label
        |> Font.width(font_size)
        |> box_size(layout(geom, font_size, @key_measured_font_size))

      radians = Map.fetch!(key, :angle) * :math.pi() / 180
      cosine = abs(:math.cos(radians))
      sine = abs(:math.sin(radians))
      {width * cosine + height * sine, width * sine + height * cosine}
    end

    # The sizes every label of a layer is drawn at: its font size in points, its font's ascent and
    # descent, and its padding on each side and its corners' radius in points, lines of text
    # measured at `lines_font_size`, the padding above at least the descent and below less it, as
    # `labelGrob()` balances them. A label is drawn at them with its layer's `angle` and `family`.
    defp layout(geom, font_size, lines_font_size) do
      descent = Font.descent(font_size)

      %{top: top, right: right, bottom: bottom, left: left} =
        Map.new(geom.label_padding, fn {side, measure} ->
          {side, points(measure, lines_font_size)}
        end)

      %{
        font_size: font_size,
        ascent: Font.ascent(font_size),
        descent: descent,
        top: max(top, descent),
        right: right,
        bottom: max(bottom - descent, 0.0),
        left: left,
        radius: points(geom.label_r, font_size)
      }
    end

    # A length in points, a number of lines worked out through inches as grid works out a unit of
    # `"lines"` in a font of `font_size` points.
    defp points({amount, :points}, _font_size), do: amount
    defp points({amount, :lines}, font_size), do: amount * font_size * @line_height / 72 * 72

    # A label's box and its text at `place` in the cell, lifted `lift` points up the cell, its
    # text `text`, justified `{hjust, vjust}`, in `look`.
    defp label(place, lift, text, {hjust, vjust}, look, layout) do
      text_width = Font.width(text, layout.font_size)
      {width, height} = box_size(text_width, layout)
      left = -hjust * width
      bottom = -vjust * height

      offsets =
        width
        |> outline(height, layout.radius)
        |> Enum.map(fn {across, up} ->
          {turned_across, turned_up} = turned({left + across, bottom + up}, layout.angle)
          {turned_across, turned_up + lift}
        end)

      along = -layout.right * hjust + layout.left * (1 - hjust)

      up =
        (1 - vjust) * layout.descent - layout.top * vjust + layout.bottom * (1 - vjust) -
          vjust * layout.ascent

      {lift_along, lift_up} = along_text(lift, layout.angle)

      [
        %Scene.Polygons{
          outlines: [List.duplicate(place, length(offsets))],
          offsets: [offsets],
          stroke_width: Mark.stroke_width(look.width),
          color: [Mark.hex(look.border)],
          color_opacity: [Mark.own_opacity(look.border)],
          fill: [Mark.hex(look.fill)],
          fill_opacity: [look.fill_opacity],
          dashes: Mark.dashes(look.line_type, look.width),
          line_end: @line_end,
          line_join: @line_join,
          mitre_limit: @mitre_limit
        },
        %Scene.Text{
          x: [elem(place, 0)],
          y: [elem(place, 1)],
          labels: [text],
          widths: [text_width],
          size: layout.font_size,
          family: layout.family,
          face: :plain,
          color: [Mark.hex(look.text)],
          opacity: [Mark.own_opacity(look.text)],
          angle: layout.angle,
          hjust: [hjust],
          offset: [{along + lift_along, up + lift_up}],
          check_overlap: false,
          ascent: layout.ascent
        }
      ]
    end

    # The box round text `text_width` points wide, `{width, height}` in points: the text's width
    # with the padding either side, and the ascent of "M" and the descent with the padding above
    # and below.
    defp box_size(text_width, layout) do
      {
        layout.left + text_width + layout.right,
        layout.top + layout.ascent + layout.descent + layout.bottom
      }
    end

    # The outline of a box `width` by `height` points with corners of `radius`, from its bottom
    # left, as grid's `rrpoints()` lists it: along the bottom, round the bottom right corner, up the
    # right, round the top right, along the top, round the top left, down the left and round the
    # bottom left.
    defp outline(width, height, radius) do
      Enum.concat([
        [{radius, 0.0}, {width - radius, 0.0}],
        corner(:bottom_right, {width - radius, radius}, radius),
        [{width, radius}, {width, height - radius}],
        corner(:top_right, {width - radius, height - radius}, radius),
        [{width - radius, height}, {radius, height}],
        corner(:top_left, {radius, height - radius}, radius),
        [{0.0, height - radius}, {0.0, radius}],
        corner(:bottom_left, {radius, radius}, radius)
      ])
    end

    # A corner's points round the circle of `radius` about `centre`, as grid's `roundCorner()`
    # picks them from 40 points a 39th of a turn apart, the last a whole turn, where R's `seq()`
    # ends on its end and 39 steps land exactly.
    defp corner(name, {centre_across, centre_up}, radius) do
      step = 2 * :math.pi() / (@circle_points - 1)

      @corner_steps
      |> Map.fetch!(name)
      |> Enum.map(fn index ->
        angle = index * step
        {centre_across + :math.cos(angle) * radius, centre_up + :math.sin(angle) * radius}
      end)
    end

    # A point across and up from a label's place, turned `angle` degrees anticlockwise about it.
    defp turned({across, up}, angle) do
      radians = angle * :math.pi() / 180
      cosine = :math.cos(radians)
      sine = :math.sin(radians)
      {across * cosine - up * sine, across * sine + up * cosine}
    end

    # A lift `lift` points up the cell, as the offset along a text turned `angle` degrees
    # anticlockwise and toward its top.
    defp along_text(lift, angle) do
      radians = angle * :math.pi() / 180
      {lift * :math.sin(radians), lift * :math.cos(radians)}
    end

    # A border's or text's colour: the row's own for `:color`, else the layer's.
    defp part_color(:color, color), do: color
    defp part_color(given, _color), do: given

    # A label's border at its width and in its line type: none at a width of 0, as ggplot2 makes a
    # border of no width `NA`, else as a rectangle's is.
    defp border(_color, width, _line_type) when width == 0, do: :none
    defp border(color, width, line_type), do: Geom.Rect.border(color, width, line_type)

    # A key's border, none at a width `all.equal()` takes as 0.
    defp key_border(_color, width, _line_type)
         when is_number(width) and width <= @key_no_border_width,
         do: :none

    defp key_border(color, width, line_type), do: Geom.Rect.border(color, width, line_type)
  end
end
