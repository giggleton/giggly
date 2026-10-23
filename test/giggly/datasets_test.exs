defmodule Giggly.DatasetsTest do
  use ExUnit.Case, async: true

  doctest Giggly.Datasets

  # Golden: R 4.6.1 with ggplot2 4.0.3, `sum(diamonds$price)` and
  # `table(as.character(diamonds$cut))`, whole numbers so no summation order can move them. They
  # move only if ggplot2's diamonds does, when the file is regenerated from a later release.
  test "diamonds decodes to R's every row: its prices' total and its cuts' counts are R's" do
    diamonds = Giggly.Datasets.diamonds()
    prices = Keyword.fetch!(diamonds, :price)
    cuts = Keyword.fetch!(diamonds, :cut)

    assert Enum.sum(prices) == 212_135_217

    assert Enum.frequencies(cuts) == %{
             "Fair" => 1610,
             "Good" => 4906,
             "Ideal" => 21_551,
             "Premium" => 13_791,
             "Very Good" => 12_082
           }
  end

  # Golden: R 4.6.1 with ggplot2 4.0.3's `levels()` of diamonds' `cut`, `color` and `clarity`,
  # each `is.ordered()`. They move only if ggplot2's diamonds does.
  test "diamonds' cut, color and clarity are factors with R's levels, ordered" do
    diamonds = Giggly.Datasets.diamonds()

    assert Enum.map([:cut, :color, :clarity], fn name ->
             %Giggly.Factor{levels: levels, ordered: ordered} = Keyword.fetch!(diamonds, name)
             {levels, ordered}
           end) == [
             {["Fair", "Good", "Very Good", "Premium", "Ideal"], true},
             {["D", "E", "F", "G", "H", "I", "J"], true},
             {["I1", "SI2", "SI1", "VS2", "VS1", "VVS2", "VVS1", "IF"], true}
           ]
  end

  # Golden: R 4.6.1 with ggplot2 4.0.3, `sum(economics$unemploy)` and
  # `sum(as.numeric(economics$date))`, whole numbers so no summation order can move them, and the
  # first and last dates. They move only if ggplot2's economics does.
  test "economics reads R's every row: its unemployment's and its dates' totals are R's" do
    economics = Giggly.Datasets.economics()
    dates = Keyword.fetch!(economics, :date)

    unemployed = Keyword.fetch!(economics, :unemploy)

    assert Enum.sum(unemployed) === 4_460_732.0

    assert {Enum.sum_by(dates, fn date -> Date.diff(date, ~D[1970-01-01]) end), hd(dates),
            List.last(dates)} === {4_480_873, ~D[1967-07-01], ~D[2015-04-01]}
  end

  # Golden: R 4.6.1 with ggplot2 4.0.3, `table(economics_long$variable)`, and
  # `sprintf("%.17g", economics_long$value01[4])`, the first of the 993 values that 16 significant
  # digits cannot write, so a copy written as `write.csv()` writes, to 15, would miss it.
  test "economics_long reads R's every row, and a value only 17 digits write as R's double" do
    economics_long = Giggly.Datasets.economics_long()

    variables = Keyword.fetch!(economics_long, :variable)
    value01s = Keyword.fetch!(economics_long, :value01)

    assert Enum.frequencies(variables) == %{
             "pce" => 574,
             "pop" => 574,
             "psavert" => 574,
             "uempmed" => 574,
             "unemploy" => 574
           }

    assert Enum.at(value01s, 3) === 0.00047060434153896666
  end
end
