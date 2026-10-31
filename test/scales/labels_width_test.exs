defmodule Scales.Labels.WidthTest do
  use ExUnit.Case, async: true

  alias Scales.Labels.Width

  # Golden: every width below is R 4.6.1's `nchar(x, type = "w")` under `en_US.UTF-8` (the image
  # `giggly-r:ggplot2-4.0.3`), but U+0000, which no R string holds, 0 as R's table of zero widths
  # starts there. They move only with R's tables; the whole table matched R on every code point.
  # nchar(c(<family>, "\u200B", "e\u0301", "\U0001F1EF\U0001F1F5", "\u00AD", "—", "Ω",
  # "ال"), type = "w"), and the range ends of R's table either side of each.
  test "is as R counts it" do
    texts = ["👨\u200D👩\u200D👧", "\u200B", "e\u0301", "🇯🇵", "\u00AD", "—", "Ω", "ال"]

    assert Enum.map(texts, &Width.columns/1) == [6, 0, 1, 2, 1, 1, 1, 2]

    assert Enum.map([0x00, 0x1F, 0x20, 0x7E, 0x7F, 0x9F, 0xA0], fn code_point ->
             Width.columns(<<code_point::utf8>>)
           end) == [0, 0, 1, 1, 0, 0, 1]

    assert Enum.map([0x10FF, 0x1100, 0x115F, 0x1160, 0x10FFFF], fn code_point ->
             Width.columns(<<code_point::utf8>>)
           end) == [1, 2, 2, 0, 1]
  end
end
