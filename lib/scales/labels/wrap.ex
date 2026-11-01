defmodule Scales.Labels.Wrap do
  @moduledoc false

  # A label broken into lines as R's `strwrap()` breaks it, for `Scales.Labels.wrap/2`: from its
  # documented rules and what R gives, measured in R 4.6.1, never a port of its source.
  #
  # A label is split into paragraphs at each line holding only whitespace, a break at its start
  # giving an empty paragraph and one at its end none, as R's `strsplit()` splits. A paragraph is
  # split into words at each whitespace character (space, tab and line break, nothing else). A
  # word of no width (`Scales.Labels.Width`:
  # an empty one, or one of zero-width characters alone) is dropped, as whitespace is, but for
  # one straight after a word ending a sentence (in `.`, `?` or `!`, then at most one of `)`, `"`
  # and `'`): that one is kept, so two spaces follow a sentence's end where two or more
  # whitespace characters did, and a zero-width word there is kept as text.
  #
  # Each line takes its first word, then each next while the line, one space and the word fit
  # within `width` columns less one, so a line is shorter than `width`, a word wider than that on
  # a line of its own, never split. A word of no width is left off a line's end and off the start
  # of the next, though it counts while the line is filled. The lines are joined by a line break,
  # a paragraph's by a space, an empty paragraph an empty line, and an empty line between
  # paragraphs.

  alias Scales.Labels.Width

  # R's sentence end, matched against a word's end.
  @sentence_end ~r/[.?!][)"']?$/

  # `label`, valid UTF-8, broken into lines of fewer than `width` columns.
  @doc false
  @spec wrap(String.t(), pos_integer()) :: String.t()
  def wrap(label, width) when is_binary(label) and is_integer(width) and width > 0 do
    label
    |> paragraphs()
    |> Enum.map(fn paragraph ->
      paragraph
      |> words()
      |> lines(width)
    end)
    |> Enum.intersperse([""])
    |> Enum.concat()
    |> Enum.join("\n")
  end

  defp paragraphs(label) do
    pieces = String.split(label, ~r/\n[ \t\n]*\n/)
    if List.last(pieces) == "", do: Enum.drop(pieces, -1), else: pieces
  end

  # A paragraph's words, each with its width, those of no width dropped but after a sentence's
  # end. The empty word after a last whitespace character, which `strsplit()` drops, is not
  # dropped here: of no width, it is dropped as any is, or left off the end of its line.
  defp words(paragraph) do
    pieces = String.split(paragraph, [" ", "\t", "\n"])

    [nil | pieces]
    |> Enum.zip_with(pieces, fn before, word -> {before, word, Width.columns(word)} end)
    |> Enum.filter(fn {before, _word, columns} -> columns > 0 or sentence_end?(before) end)
    |> Enum.map(fn {_before, word, columns} -> {word, columns} end)
  end

  defp sentence_end?(nil), do: false
  defp sentence_end?(word), do: Regex.match?(@sentence_end, word)

  defp lines([], _width), do: [""]
  defp lines(words, width), do: laid(words, width, [])

  defp laid([], _width, done), do: Enum.reverse(done)

  defp laid(words, width, done) do
    {line, rest} = filled(words, width)
    shown = without_last_space(line)
    text = Enum.map_join(shown, " ", fn {word, _columns} -> word end)
    laid(without_first_space(rest), width, [text | done])
  end

  # A line's words, its first and each after it that fits, and the words left.
  defp filled([{_word, columns} = first | words], width) do
    {taken, rest} = fitting(words, width - columns - 1, [])
    {[first | taken], rest}
  end

  defp fitting([{_word, columns} = word | words], room, taken) when columns + 1 <= room,
    do: fitting(words, room - columns - 1, [word | taken])

  defp fitting(words, _room, taken), do: {Enum.reverse(taken), words}

  defp without_last_space(line) do
    case List.last(line) do
      {_word, 0} -> Enum.drop(line, -1)
      _word -> line
    end
  end

  defp without_first_space([{_word, 0} | rest]), do: rest
  defp without_first_space(rest), do: rest
end
