defmodule Giggly.Font do
  @moduledoc false

  # How much room text takes in a family's face, at a size in points (1/72 inch), as a font size
  # is. A line's height above its baseline is that of "M", as R measures a string's height, and the
  # room ggplot2 leaves below it is the deepest descent among "gjpqyQ", whatever the text, so labels
  # with and without descenders take the same height.
  #
  # A family and face a font is registered under with Pica, in a project that lists Pica, is
  # measured from that font as svglite measures a font it is given; so, where installed fonts are
  # searched (`installed_fonts`), is one the machine has a font of that exact family name for, as
  # Pica finds one, except `""` and R's generic names, `"sans"`, `"serif"` and `"mono"`, which are
  # measured from a font only where one is registered under that name, whatever the machine has. A
  # string's width is its glyphs' advances once Pica has shaped it, kerning and ligatures applied,
  # at the size truncated to 1/64 point (a size under one at 1 point), in 1/64 point; a character
  # the font lacks takes the width of the font's glyph for one (`.notdef`). The height is the top of
  # "M"'s box and the room below the bottom of the lowest of "gjpqyQ"'s, each rounded outward to a
  # whole pixel at 10,000 dots per inch, as R takes heights from glyph boxes at that resolution.
  # Over sizes from 5 to 30 points in Lato and Source Serif 4, the widths come within 4/64 point of
  # svglite's, whose FreeType rounds an advance by its own arithmetic, and the heights within a
  # pixel, 0.0072 point, as its FreeType sizes a font its own way.
  #
  # Such a font also gives the glyphs each label is drawn with: each glyph's outline, in the font's
  # own units, at its place once shaped at the same truncated size, the pen moved on by each
  # advance and the glyph drawn its offset from the pen, so a label's glyphs span its measured
  # width; and the scale, in points per font unit, the outlines are drawn at. A glyph that draws
  # nothing, such as a space, is left out.
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
  # vdiffr's; its header says where it came from. Measuring reads nothing but the fonts Pica holds,
  # registered or, where they are searched, installed.

  # Measures strings, and gives the scene the outlines its labels are drawn with.
  use Boundary,
    deps: [Giggly.Scene] ++ if(Code.ensure_loaded?(Pica), do: [Pica], else: []),
    exports: []

  alias Giggly.Scene.Glyphs

  @glyph_table_path Application.app_dir(:giggly, "priv/fonts/liberation_sans.txt")
  @symbol_table_path Application.app_dir(:giggly, "priv/fonts/symbola.txt")
  @external_resource @glyph_table_path
  @external_resource @symbol_table_path

  # The size the tables' metrics are given at, in points.
  @table_size 12

  # why: the glyph tables are read once, at compile time; no IO happens when a plot is measured
  # instead of: the tables as heredocs in this module — rejected because they are generated data,
  #   kept as files so they can be regenerated and diffed against their source apart from the code
  # credo:disable-for-next-line Tack.Credo.Check.CorePurity
  @glyph_tables Enum.map([@glyph_table_path, @symbol_table_path], &File.read!/1)

  # Each table's glyphs, {width, ascent, descent} by codepoint, Liberation Sans's for the text
  # faces and Symbola's for the symbol face, a table's comment lines starting with "#"; and what a
  # measure reads from them: the metrics of codepoint 1, which vdiffr gives a character the font
  # lacks, the ascent of "M" and the deepest descent among "gjpqyQ".
  @tables Enum.map(@glyph_tables, fn table ->
            glyphs =
              table
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

            %{
              glyphs: glyphs,
              missing: Map.fetch!(glyphs, 1),
              ascent: elem(Map.fetch!(glyphs, ?M), 1),
              descent:
                "gjpqyQ"
                |> String.to_charlist()
                |> Enum.map(fn codepoint -> elem(Map.fetch!(glyphs, codepoint), 2) end)
                |> Enum.max()
            }
          end)

  @text_table hd(@tables)
  @symbol_table List.last(@tables)

  # A face, as `Giggly.Theme` names one, or the symbol face, grid's `fontface = 5`, which R's
  # plotmath draws an operator's sign in.
  @type face :: :plain | :bold | :italic | :bold_italic | :symbol

  # Each measure takes whether the machine's installed fonts are searched, `installed_fonts`.

  # The width of `text` set at `size` points in `family`'s `face`, in points.
  @doc false
  @spec width(String.t(), number(), String.t(), face(), boolean()) :: float()
  def width(text, size, family, face, installed_fonts) when is_boolean(installed_fonts),
    do: measure({:width, text, size}, family, face, installed_fonts)

  # The height of a line of text set at `size` points in `family`'s `face` above its baseline, in
  # points: that of "M".
  @doc false
  @spec ascent(number(), String.t(), face(), boolean()) :: float()
  def ascent(size, family, face, installed_fonts) when is_boolean(installed_fonts),
    do: measure({:ascent, size}, family, face, installed_fonts)

  # The room below the baseline of a line of text set at `size` points in `family`'s `face`, in
  # points: the deepest descent among "gjpqyQ".
  @doc false
  @spec descent(number(), String.t(), face(), boolean()) :: float()
  def descent(size, family, face, installed_fonts) when is_boolean(installed_fonts),
    do: measure({:descent, size}, family, face, installed_fonts)

  # How far `text` set at `size` points in `family`'s `face` reaches above its baseline and below
  # it, in points, as R's plotmath boxes a string: the highest ascent and the deepest descent among
  # its characters, each its own, and none below zero, as plotmath's box starts from none.
  @doc false
  @spec box(String.t(), number(), String.t(), face(), boolean()) :: {float(), float()}
  def box(text, size, family, face, installed_fonts) when is_boolean(installed_fonts),
    do: measure({:box, text, size}, family, face, installed_fonts)

  # The glyphs `texts`, each a label set at `size` points in `family`'s `face`, are drawn with, as
  # the scene carries them: each label's run of glyphs in order, and the outlines' scale in points
  # per font unit, where a font Pica holds gives them, or `:none` where they are measured from the
  # table.
  @doc false
  @spec glyphs([String.t()], number(), String.t(), face(), boolean()) :: Glyphs.t() | :none
  def glyphs(texts, size, family, face, installed_fonts)
      when is_list(texts) and is_boolean(installed_fonts),
      do: runs(texts, size, family, face, installed_fonts)

  defp from_table({:width, text, size}, face) do
    %{glyphs: glyphs, missing: missing} = table(face)

    advance =
      text
      |> String.to_charlist()
      |> Enum.map(fn codepoint -> elem(Map.get(glyphs, codepoint, missing), 0) end)
      |> Enum.sum()

    advance * (size / @table_size)
  end

  defp from_table({:ascent, size}, face), do: table(face).ascent * (size / @table_size)
  defp from_table({:descent, size}, face), do: table(face).descent * (size / @table_size)

  defp from_table({:box, text, size}, face) do
    %{glyphs: glyphs, missing: missing} = table(face)

    {height, depth} =
      text
      |> String.to_charlist()
      |> Enum.reduce({0.0, 0.0}, fn codepoint, {height, depth} ->
        {_width, ascent, descent} = Map.get(glyphs, codepoint, missing)
        {max(height, ascent), max(depth, descent)}
      end)

    {height * (size / @table_size), depth * (size / @table_size)}
  end

  # The table a face is measured from: Symbola's for the symbol face, as vdiffr measures R's
  # symbol font, Liberation Sans's for every other.
  defp table(:symbol), do: @symbol_table
  defp table(_face), do: @text_table

  if Code.ensure_loaded?(Pica) do
    # The resolution a font's heights are rounded at, in dots per inch, and the points in an inch.
    @dots_per_inch 10_000
    @points_per_inch 72

    # The families measured from a font only where one is registered under their name: the default
    # and R's generic names.
    @generic_families ["", "sans", "serif", "mono"]

    # The font of `family`'s `face` Pica holds: registered, or, where `installed_fonts`, installed,
    # but never installed for a generic family; for the symbol face, the font registered as
    # `"symbol"`, svglite's name for it, whatever the family, and never an installed one.
    defp lookup(_family, :symbol, _installed_fonts),
      do: Pica.lookup("symbol", :plain, installed: false)

    defp lookup(family, face, installed_fonts) do
      Pica.lookup(family, face, installed: installed_fonts and family not in @generic_families)
    end

    # `measure` taken from the font of `family`'s `face`, or from the table where there is none.
    defp measure(measure, family, face, installed_fonts) do
      case lookup(family, face, installed_fonts) do
        {:ok, font} -> from_font(measure, font)
        :error -> from_table(measure, face)
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

    defp from_font({:box, text, size}, font) do
      {top, bottom} =
        font
        |> boxes(text)
        |> Enum.reduce({0.0, 0.0}, fn
          :none, reached ->
            reached

          {_x_min, y_min, _x_max, y_max}, {top, bottom} ->
            above =
              y_max
              |> pixels(size, font)
              |> Float.ceil()

            below =
              y_min
              |> pixels(size, font)
              |> Float.floor()

            {max(top, above), max(bottom, -below)}
        end)

      {points(top), points(bottom)}
    end

    defp boxes(font, text), do: Pica.glyph_boxes(font, Pica.glyph_ids(font, text))

    defp runs(texts, size, family, face, installed_fonts) do
      case lookup(family, face, installed_fonts) do
        {:ok, font} ->
          %Glyphs{
            scale: sixty_fourths(size) / (64 * Pica.info(font).units_per_em),
            runs: Enum.map(texts, fn text -> run(text, size, font) end)
          }

        :error ->
          :none
      end
    end

    # `text`'s glyphs shaped at `size` points truncated to 1/64 point, each placed its offset from
    # the pen, which each advance moves on, in points; a glyph that draws nothing left out.
    defp run(text, size, font) do
      shaped = Pica.shape(font, text, scale: sixty_fourths(size))
      outlines = Pica.glyph_outlines(font, Enum.map(shaped, fn glyph -> glyph.glyph_id end))

      {glyphs, _pen} =
        shaped
        |> Enum.zip(outlines)
        |> Enum.flat_map_reduce(0, fn {glyph, outline}, pen ->
          placed =
            case outline do
              :none -> []
              commands -> [{commands, (pen + glyph.x_offset) / 64, glyph.y_offset / 64}]
            end

          {placed, pen + glyph.x_advance}
        end)

      glyphs
    end

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
    defp measure(measure, _family, face, _installed_fonts), do: from_table(measure, face)
    defp runs(_texts, _size, _family, _face, _installed_fonts), do: :none
  end
end
