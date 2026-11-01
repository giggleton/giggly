defmodule Scales.Labels.WidthTest do
  use ExUnit.Case, async: true

  alias Scales.Labels.Width

  # Golden: every width below is R 4.6.1's `nchar(x, type = "w")` under `en_US.UTF-8` (the image
  # `giggly-r:ggplot2-4.0.3`), but U+0000, which no R string holds, 0 as R's table of zero widths
  # starts there. They move only with R's tables; the whole table matched R on every code point.
  # nchar(c(<family>, "\u200B", "e\u0301", "\U0001F1EF\U0001F1F5", "\u00AD", "—", "Ω",
  # "ال"), type = "w")
  test "is as R counts it" do
    texts = ["👨\u200D👩\u200D👧", "\u200B", "e\u0301", "🇯🇵", "\u00AD", "—", "Ω", "ال"]

    assert Enum.map(texts, &Width.columns/1) == [6, 0, 1, 2, 1, 1, 1, 2]
    assert Width.columns(<<0x00::utf8>>) == 0
  end

  # Golden: `fixtures/r_widths_4.6.1.csv` is R's every run of code points not of width 1, as R
  # wrote it in the image above, moving only when R is measured again:
  # cp <- c(1:0xD7FF, 0xE000:0x10FFFF)
  # w <- nchar(intToUtf8(cp, multiple = TRUE), type = "w", allowNA = TRUE)
  # r <- rle(w); ends <- cumsum(r$lengths); starts <- c(1, head(ends, -1) + 1)
  # runs <- data.frame(first = cp[starts], last = cp[ends], width = r$values)
  # write.csv(runs[runs$width != 1, ], "r_widths_4.6.1.csv", row.names = FALSE)
  test "is R's at both ends of every run of R's table, and either side of them" do
    fixture = Path.join(__DIR__, "fixtures/r_widths_4.6.1.csv")

    runs =
      fixture
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.drop(1)
      |> Enum.map(fn row ->
        fields = String.split(row, ",")
        [first, last, width] = Enum.map(fields, &String.to_integer/1)
        {first, last, width}
      end)

    widths_by_r =
      for {first, last, _width} <- runs,
          code_point <- [first - 1, first, last, last + 1],
          code_point in 0x01..0xD7FF or code_point in 0xE000..0x10FFFF,
          into: %{} do
        {code_point,
         Enum.find_value(runs, 1, fn {run_first, run_last, width} ->
           code_point in run_first..run_last and width
         end)}
      end

    widths =
      Map.new(widths_by_r, fn {code_point, _width} ->
        {code_point, Width.columns(<<code_point::utf8>>)}
      end)

    assert widths == widths_by_r
  end
end
