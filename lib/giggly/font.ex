defmodule Giggly.Font do
  @moduledoc """
  How much room text takes, measured as ggplot2's own SVG test snapshots measure it: with the
  glyph metrics of Liberation Sans, which vdiffr, the tool that writes those snapshots, uses for
  every string it draws. Liberation Sans has the widths of Arial and of Helvetica, the fonts a
  browser most often draws sans-serif text in, and an SVG label is drawn at the width measured
  here whatever font draws it (`Giggly.SVG`).

  A string's width is the sum of its characters' advance widths, with no kerning; a character the
  font lacks takes vdiffr's width for a missing glyph. A line's height above its baseline is the
  ascent of "M", as R measures a string's height, and the room ggplot2 leaves below it is the
  deepest descent among "gjpqyQ", whatever the text, so labels with and without descenders take
  the same height. Sizes are in points (1/72 inch), as a font size is.

  The metrics are read when Giggly compiles, from `priv/fonts/liberation_sans.txt`, a copy of
  vdiffr's table; its header says where it came from. Measuring reads nothing.
  """

  # Measures strings and nothing else.
  use Boundary, deps: [], exports: []

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

  @doc """
  The width of `text` set at `size` points, in points.

      iex> Giggly.Font.width("10.0", 8.8)
      17.128320000000002

  A character the font lacks is measured as vdiffr measures it:

      iex> Giggly.Font.width("中", 12)
      9.0
  """
  @spec width(String.t(), number()) :: float()
  def width(text, size) do
    advance =
      text
      |> String.to_charlist()
      |> Enum.map(fn codepoint -> Map.get(@widths, codepoint, @missing_glyph_width) end)
      |> Enum.sum()

    advance * (size / @table_size)
  end

  @doc """
  The height of a line of text set at `size` points above its baseline, in points: the ascent of
  "M".

      iex> Giggly.Font.ascent(8.8)
      6.05616
  """
  @spec ascent(number()) :: float()
  def ascent(size), do: @ascent * (size / @table_size)

  @doc """
  The room below the baseline of a line of text set at `size` points, in points: the deepest
  descent among "gjpqyQ".

      iex> Giggly.Font.descent(8.8)
      1.8268800000000003
  """
  @spec descent(number()) :: float()
  def descent(size), do: @descent * (size / @table_size)
end
