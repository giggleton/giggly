defmodule Giggly.Font do
  @moduledoc false

  # How much room text takes in a family's face, at a size in points (1/72 inch), as a font size
  # is. A line's height above its baseline is that of "M", as R measures a string's height, and the
  # room ggplot2 leaves below it is the deepest descent among "gjpqyQ", whatever the text, so labels
  # with and without descenders take the same height.
  #
  # A family and face a font is registered under with Pica, in a project that lists Pica, is
  # measured from that font as svglite measures a font it is given. A string's width is its glyphs'
  # advances once Pica has shaped it, kerning and ligatures applied, at the size truncated to 1/64
  # point (a size under one at 1 point), in 1/64 point; a character the font lacks takes the width
  # of the font's glyph for one (`.notdef`). The height is the top of "M"'s box and the room below
  # the bottom of the lowest of "gjpqyQ"'s, each rounded outward to a whole pixel at 10,000 dots
  # per inch, as R takes heights from glyph boxes at that resolution. Over sizes from 5 to 30
  # points in Lato and Source Serif 4, the widths come within 4/64 point of svglite's, whose
  # FreeType rounds an advance by its own arithmetic, and the heights within a pixel, 0.0072 point,
  # as its FreeType sizes a font its own way. Installed fonts are not searched: a label is written
  # as text naming its family, which only the fonts a project registers, and serves, are sure to
  # draw.
  #
  # Every other family and face, and every one in a project without Pica, is measured as ggplot2's
  # own SVG test snapshots measure it: with the glyph metrics of Liberation Sans, which vdiffr, the
  # tool that writes those snapshots, uses for every string it draws. Liberation Sans has the
  # widths of Arial and of Helvetica, the fonts a browser most often draws sans-serif text in, and
  # an SVG label is drawn at the width measured here whatever font draws it (`Giggly.SVG`). A
  # string's width is the sum of its characters' advance widths, with no kerning; a character the
  # table lacks takes vdiffr's width for a missing glyph; the heights are the table's own.
  #
  # The table is read when Giggly compiles, from `priv/fonts/liberation_sans.txt`, a copy of
  # vdiffr's; its header says where it came from. Measuring reads nothing but the fonts registered
  # with Pica.

  # Measures strings and nothing else.
  use Boundary, deps: if(Code.ensure_loaded?(Pica), do: [Pica], else: []), exports: []

  @glyph_table_path Application.app_dir(:giggly, "priv/fonts/liberation_sans.txt")
  @external_resource @glyph_table_path

  # The size the table's metrics are given at, in points.
  @table_size 12

  # why: the glyph table is read once, at compile time; no IO happens when a plot is measured
  # instead of: the table as a heredoc in this module — rejected because it is generated data,
  #   kept as a file so it can be regenerated and diffed against its source apart from the code
  # credo:disable-for-next-line Tack.Credo.Check.CorePurity
  @glyph_table File.read!(@glyph_table_path)

  # Each glyph's {width, ascent, descent} by codepoint; the table's comment lines start with "#".
  @glyphs @glyph_table
          |> String.split("\n", trim: true)
          |> Enum.reject(fn line -> String.starts_with?(line, "#") end)
          |> Map.new(fn line ->
            [codepoint | metrics] = String.split(line)

            [width, ascent, descent] =
              Enum.map(metrics, fn metric ->
                {value, ""} = Float.parse(metric)
                value
              end)

            {String.to_integer(codepoint), {width, ascent, descent}}
          end)

  @widths Map.new(@glyphs, fn {codepoint, {width, _ascent, _descent}} -> {codepoint, width} end)

  # vdiffr measures a character the font lacks as the glyph at codepoint 1.
  @missing_glyph_width elem(Map.fetch!(@glyphs, 1), 0)

  @ascent elem(Map.fetch!(@glyphs, ?M), 1)

  @descent "gjpqyQ"
           |> String.to_charlist()
           |> Enum.map(fn codepoint -> elem(Map.fetch!(@glyphs, codepoint), 2) end)
           |> Enum.max()

  # A face, as `Giggly.Theme` names one.
  @type face :: :plain | :bold | :italic | :bold_italic

  # The width of `text` set at `size` points in `family`'s `face`, in points.
  @doc false
  @spec width(String.t(), number(), String.t(), face()) :: float()
  def width(text, size, family, face), do: measure({:width, text, size}, family, face)

  # The height of a line of text set at `size` points in `family`'s `face` above its baseline, in
  # points: that of "M".
  @doc false
  @spec ascent(number(), String.t(), face()) :: float()
  def ascent(size, family, face), do: measure({:ascent, size}, family, face)

  # The room below the baseline of a line of text set at `size` points in `family`'s `face`, in
  # points: the deepest descent among "gjpqyQ".
  @doc false
  @spec descent(number(), String.t(), face()) :: float()
  def descent(size, family, face), do: measure({:descent, size}, family, face)

  defp from_table({:width, text, size}) do
    advance =
      text
      |> String.to_charlist()
      |> Enum.map(fn codepoint -> Map.get(@widths, codepoint, @missing_glyph_width) end)
      |> Enum.sum()

    advance * (size / @table_size)
  end

  defp from_table({:ascent, size}), do: @ascent * (size / @table_size)
  defp from_table({:descent, size}), do: @descent * (size / @table_size)

  if Code.ensure_loaded?(Pica) do
    # The resolution a font's heights are rounded at, in dots per inch, and the points in an inch.
    @dots_per_inch 10_000
    @points_per_inch 72

    # `measure` taken from the font registered with Pica under `family` with `face`, or from the
    # table where none is.
    defp measure(measure, family, face) do
      case Pica.lookup(family, face, installed: false) do
        {:ok, font} -> from_font(measure, font)
        :error -> from_table(measure)
      end
    end

    defp from_font({:width, text, size}, font) do
      advance =
        font
        |> Pica.shape(text, scale: sixty_fourths(size))
        |> Enum.map(fn glyph -> glyph.x_advance end)
        |> Enum.sum()

      advance / 64
    end

    defp from_font({:ascent, size}, font) do
      [{_x_min, _y_min, _x_max, top}] = boxes(font, "M")

      top
      |> pixels(size, font)
      |> Float.ceil()
      |> points()
    end

    defp from_font({:descent, size}, font) do
      bottom =
        font
        |> boxes("gjpqyQ")
        |> Enum.map(fn {_x_min, y_min, _x_max, _y_max} -> y_min end)
        |> Enum.min()

      bottom
      |> pixels(size, font)
      |> Float.floor()
      |> points()
      |> Kernel.-()
    end

    defp boxes(font, text), do: Pica.glyph_boxes(font, Pica.glyph_ids(font, text))

    # A length in `font`'s units, at `size` points truncated to 1/64 point, in pixels at 10,000
    # dots per inch: one division of whole numbers, so a length that is a whole number of pixels
    # comes out exactly one.
    defp pixels(units, size, font) do
      units * sixty_fourths(size) * @dots_per_inch /
        (64 * @points_per_inch * Pica.info(font).units_per_em)
    end

    defp points(pixels), do: pixels * @points_per_inch / @dots_per_inch

    # `size` points in whole 1/64 points, truncated, as svglite hands a size to FreeType, which
    # takes a size truncated to nothing as 1 point.
    defp sixty_fourths(size) do
      case trunc(size * 64) do
        0 -> 64
        sixty_fourths -> sixty_fourths
      end
    end
  else
    defp measure(measure, _family, _face), do: from_table(measure)
  end
end
