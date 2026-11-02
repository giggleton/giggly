defmodule Giggly.OutOfBoundsTest do
  use ExUnit.Case, async: true

  alias Giggly.{DataFrame, Plot}

  @values [:neg_infinity, -1, 5, 10, 20, 30, 40, :infinity, nil, :nan]
  @logged [0, 0.5, 1, 10, 100, 1000, 5000, :infinity, nil, :nan, -1]
  @first_day ~D[2020-01-01]

  # R's `function(x, range) pmin(x, 25)`, which leaves `NA` and `NaN` as they are.
  defp at_most_25(values, _limits) do
    Enum.map(values, fn
      value when is_number(value) -> min(value, 25.0)
      :infinity -> 25.0
      other -> other
    end)
  end

  # R's `function(x, range) ifelse(x > range[2], range[2] + 1, x)`, which makes `NaN` `NA`.
  defp past_high(values, {_low, high}) do
    Enum.map(values, fn
      value when is_number(value) and value > high -> high + 1
      :infinity -> high + 1
      :nan -> nil
      other -> other
    end)
  end

  defp oob("cap25"), do: &at_most_25/2
  defp oob("past_high"), do: &past_high/2

  defp oob(name) do
    Map.fetch!(
      %{
        "censor" => :censor,
        "censor_any" => :censor_any,
        "squish" => :squish,
        "squish_any" => :squish_any,
        "squish_infinite" => :squish_infinite,
        "keep" => :keep
      },
      name
    )
  end

  defp limits("none", _kind), do: []

  defp limits(given, "date_x") do
    {low, high} = ends(given)
    [limits: {day(low), day(high)}]
  end

  defp limits(given, _kind), do: [limits: ends(given)]

  defp ends(given) do
    [low, high] =
      given
      |> String.trim_leading("{")
      |> String.trim_trailing("}")
      |> String.split(", ")
      |> Enum.map(&number/1)

    {low, high}
  end

  defp day(nil), do: nil
  defp day(offset), do: Date.add(@first_day, trunc(offset))

  defp number("nil"), do: nil

  defp number(text) do
    {number, ""} = Float.parse(text)
    number
  end

  # A value R printed: a colour, R's `grey50` being the colour scales' missing value, `#7F7F7F`;
  # an infinity, `nil` or `:nan`; or a number to 17 significant digits.
  defp value(~s("grey50")), do: "#7F7F7F"
  defp value(~s(") <> _rest = quoted), do: String.trim(quoted, ~s("))
  defp value(":infinity"), do: :infinity
  defp value(":neg_infinity"), do: :neg_infinity
  defp value(":nan"), do: :nan
  defp value(text), do: number(text)

  defp printed(list) do
    list
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(", ")
    |> Enum.map(&value/1)
  end

  defp plot("log10_y", options) do
    %{"x" => Enum.to_list(1..11), "y" => @logged}
    |> Plot.new(%{x: "x", y: "y"})
    |> Plot.geom_point()
    |> Plot.scale_y_log10(options)
  end

  defp plot("date_x", options) do
    days = Enum.map([-30, -1, 5, 10, 20, 30, 40, nil], &day/1)

    %{"x" => days, "y" => List.duplicate(1, 8)}
    |> Plot.new(%{x: "x", y: "y"})
    |> Plot.geom_point()
    |> Plot.scale_x_date(options)
  end

  defp plot(kind, options) when kind in ["point_y", "col_y", "reverse_y"] do
    data = %{"x" => Enum.to_list(1..10), "y" => @values}

    geom =
      case kind do
        "col_y" -> &Plot.geom_col/1
        _point -> &Plot.geom_point/1
      end

    scale =
      case kind do
        "reverse_y" -> &Plot.scale_y_reverse/2
        _continuous -> &Plot.scale_y_continuous/2
      end

    data
    |> Plot.new(%{x: "x", y: "y"})
    |> geom.()
    |> scale.(options)
  end

  defp plot(kind, options) do
    {aesthetic, scale} = aesthetic_scale(kind)

    %{"x" => Enum.to_list(1..10), "y" => List.duplicate(1, 10), "z" => @values}
    |> Plot.new(%{:x => "x", :y => "y", aesthetic => "z"})
    |> Plot.geom_point()
    |> scale.(options)
  end

  defp aesthetic_scale("colour"), do: {:color, &Plot.scale_color_continuous/2}
  defp aesthetic_scale("alpha"), do: {:alpha, &Plot.scale_alpha_continuous/2}
  defp aesthetic_scale("size_area"), do: {:size, &Plot.scale_size_area/2}
  defp aesthetic_scale("binned"), do: {:color, &Plot.scale_color_binned/2}

  defp aesthetic_scale("gradient2"),
    do:
      {:color,
       fn plot, options -> Plot.scale_color_gradient2(plot, [midpoint: 20] ++ options) end}

  defp aesthetic_scale("steps2"),
    do: {:color, fn plot, options -> Plot.scale_color_steps2(plot, [midpoint: 20] ++ options) end}

  defp column("colour"), do: :color

  defp column(name),
    do:
      Map.fetch!(
        %{
          "y" => :y,
          "ymin" => :ymin,
          "ymax" => :ymax,
          "x" => :x,
          "alpha" => :alpha,
          "size" => :size
        },
        name
      )

  # Golden: `fixtures/r_oob_ggplot2_4.0.3.txt` is ggplot2 4.0.3's layer data in R 4.6.1, one line
  # a column: each of R's six oob functions and two of a user's (`at_most_25/2`, `past_high/2`) on
  # a y axis under points and under bars, whose bases and tops are mapped again once stacked, a
  # reversed and a log10 y axis, a date x axis, and colour, gradient2, alpha, size by area, binned
  # colour and steps2 scales, at limits on both ends, one, neither, given high to low and of no
  # width, over infinities, values outside either end, on the ends and inside, `NA` and `NaN`
  # (`inc4/step7/sweep/table.R`). A binned scale's limits of no width are left out, where R fails.
  test "every oob on every kind of scale draws as ggplot2's" do
    rows =
      __DIR__
      |> Path.join("fixtures/r_oob_ggplot2_4.0.3.txt")
      |> File.stream!()
      |> Enum.map(fn line ->
        line
        |> String.trim()
        |> String.split("|")
      end)

    assert Enum.count(rows) == 576

    differing =
      Enum.reject(rows, fn [kind, oob, given, name, printed] ->
        drawn =
          kind
          |> plot([{:oob, oob(oob)} | limits(given, kind)])
          |> Giggly.layer_data()
          |> DataFrame.pull(column(name))

        expected = printed(printed)

        length(drawn) == length(expected) and
          Enum.all?(
            Enum.zip_with(drawn, expected, fn drawn_value, expected_value ->
              drawn_value == expected_value
            end)
          )
      end)

    assert differing == []
  end
end
