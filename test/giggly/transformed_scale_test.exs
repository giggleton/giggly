defmodule Giggly.TransformedScaleTest do
  use ExUnit.Case, async: true

  alias Giggly.{Assembly, DataFrame, Guide, Plot, Scale}

  @values [-1, 0, 1, 3, 10, 30, 100, 300, 1000, 3000, 10_000, :infinity, nil]

  # R's `new_transform("cube", function(x) x^3, function(x) sign(x) * abs(x)^(1/3))`.
  defp cube do
    Scales.Transform.new("cube",
      transform: fn
        :infinity -> :infinity
        :neg_infinity -> :neg_infinity
        value -> value * value * value
      end,
      inverse: fn
        :infinity -> :infinity
        :neg_infinity -> :neg_infinity
        position when position < 0 -> -:math.pow(-position, 1 / 3)
        position -> :math.pow(position, 1 / 3)
      end
    )
  end

  defp transform("cube"), do: cube()
  defp transform("log10_reverse"), do: {:compose, [:log10, :reverse]}
  defp transform(name), do: String.to_existing_atom(name)

  defp scale("colour"), do: {:color, &Plot.scale_color_continuous/2, []}
  defp scale("colorsteps"), do: {:color, &Plot.scale_color_continuous/2, [guide: :colorsteps]}
  defp scale("fill"), do: {:fill, &Plot.scale_fill_continuous/2, []}
  defp scale("gradient"), do: {:color, &Plot.scale_color_gradient/2, []}
  defp scale("gradient2"), do: {:color, &Plot.scale_color_gradient2/2, [midpoint: 100]}

  defp scale("gradientn"),
    do: {:color, &Plot.scale_color_gradientn/2, [colors: ["#FF0000", "#00FF00", "#0000FF"]]}

  defp scale("viridis_c"), do: {:color, &Plot.scale_color_viridis_c/2, []}
  defp scale("distiller"), do: {:color, &Plot.scale_color_distiller/2, []}
  defp scale("alpha"), do: {:alpha, &Plot.scale_alpha_continuous/2, []}
  defp scale("size"), do: {:size, &Plot.scale_size_continuous/2, []}
  defp scale("size_area"), do: {:size, &Plot.scale_size_area/2, []}
  defp scale("radius"), do: {:size, &Plot.scale_radius/2, []}
  defp scale("linewidth"), do: {:linewidth, &Plot.scale_linewidth_continuous/2, []}

  # The size, radius and line width scales take no `oob:`, as R's take none: censor alone.
  defp oob(kind, _oob) when kind in ["size", "radius", "linewidth"], do: []
  defp oob(_kind, oob), do: [oob: String.to_existing_atom(oob)]

  defp limits("none"), do: []

  defp limits(given) do
    [low, high] =
      given
      |> String.trim_leading("{")
      |> String.trim_trailing("}")
      |> String.split(", ")
      |> Enum.map(&value/1)

    [limits: {low, high}]
  end

  # A value R printed: a colour, R's `grey50` being the colour scales' missing value, `#7F7F7F`;
  # an infinity, `nil` or `:nan`; or a number to 17 significant digits.
  defp value("nil"), do: nil
  defp value(~s("grey50")), do: "#7F7F7F"
  defp value(~s(") <> _rest = quoted), do: String.trim(quoted, ~s("))
  defp value(":infinity"), do: :infinity
  defp value(":neg_infinity"), do: :neg_infinity
  defp value(":nan"), do: :nan

  defp value(text) do
    {number, ""} = Float.parse(text)
    number
  end

  defp printed("[]"), do: []

  defp printed(list) do
    list
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(", ")
    |> Enum.map(&value/1)
  end

  # The plot of `kind`'s scale through `transform` on `@values`: points, but a line for a line
  # width and tiles for a fill, as R's table drew them.
  defp plot(kind, options) do
    {aesthetic, scale, own} = scale(kind)
    count = length(@values)

    plot =
      Plot.new(
        %{"x" => Enum.to_list(1..count), "y" => List.duplicate(1, count), "z" => @values},
        %{:x => "x", :y => "y", aesthetic => "z"}
      )

    geom =
      case aesthetic do
        :linewidth -> &Plot.geom_line/1
        :fill -> &Plot.geom_tile/1
        _point -> &Plot.geom_point/1
      end

    drawn =
      plot
      |> geom.()
      |> scale.(own ++ options)

    {aesthetic, drawn}
  end

  # What Giggly drew of each item R's table prints: the layer's column; the scale's limits, in
  # transformed space; the legend's keys, each its transformed break, or its place up a colour
  # bar or colour steps, its label and what it maps to; and a colour bar's samples, transformed,
  # and their colours, or colour steps' bins, from, to and colour.
  defp drawn(aesthetic, plot) do
    assembly = Assembly.run(plot)
    scale = Map.fetch!(assembly.non_position_scales, aesthetic)
    [legend] = assembly.legends
    bar? = not is_struct(legend.guide, Guide.Legend)
    [frame] = assembly.layer_data

    keyed = %{
      "layer" => DataFrame.pull(frame, aesthetic),
      "limits" => Scale.samples(scale, 2),
      "key.value" => Enum.map(legend.keys, fn key -> if bar?, do: key.place, else: key.value end),
      "key.label" => Enum.map(legend.keys, fn key -> key.label end),
      "key.mapped" => Enum.map(legend.keys, fn key -> key.values[aesthetic] end)
    }

    Map.merge(keyed, decor(legend, scale))
  end

  defp decor(%{guide: %Guide.Colorbar{}, decor: decor}, scale) do
    %{
      "decor.value" => Scale.samples(scale, length(decor)),
      "decor.colour" => Enum.map(decor, fn {_place, color} -> color end)
    }
  end

  defp decor(%{guide: %Guide.Colorsteps{}, decor: bins}, _scale) do
    %{
      "decor.min" => Enum.map(bins, fn {from, _to, _color} -> from end),
      "decor.max" => Enum.map(bins, fn {_from, to, _color} -> to end),
      "decor.colour" => Enum.map(bins, fn {_from, _to, color} -> color end)
    }
  end

  defp decor(_legend, _scale), do: %{}

  # Whether Giggly drew R's values: each the same, but under the pseudo-logarithm, whose
  # `asinh()` is the platform's, within a double of R's (the scales package's `scales.md`).
  defp same?(drawn, expected, transform) do
    length(drawn) == length(expected) and
      drawn
      |> Enum.zip_with(expected, fn drawn_value, expected_value ->
        drawn_value == expected_value or
          (transform == "pseudo_log" and neighbours?(drawn_value, expected_value))
      end)
      |> Enum.all?()
  end

  defp neighbours?(drawn, expected) when is_float(drawn) and is_float(expected) do
    <<drawn_bits::64>> = <<drawn::float>>
    <<expected_bits::64>> = <<expected::float>>
    abs(drawn_bits - expected_bits) <= 1
  end

  defp neighbours?(_drawn, _expected), do: false

  defp cases do
    __DIR__
    |> Path.join("fixtures/r_transform_ggplot2_4.0.3.txt")
    |> File.stream!()
    |> Enum.map(fn line ->
      [kind, transform, limits, oob, item, printed] =
        line
        |> String.trim()
        |> String.split("|")

      {{kind, transform, limits, oob}, {item, printed}}
    end)
    |> Enum.group_by(fn {key, _item} -> key end, fn {_key, item} -> item end)
  end

  # Golden: `fixtures/r_transform_ggplot2_4.0.3.txt` is ggplot2 4.0.3's build in R 4.6.1 of every
  # continuous colour, fill, alpha, size, radius and line width scale function, and a colour
  # scale drawn as colour steps, under log10, sqrt, reverse, log10 then reverse, a cube of one's
  # own and pseudo_log, at no limits, both, both high to low and one, by censor and squish where
  # the scale takes `oob`, over -1, 0, values from 1 to 10,000, an infinity and `NA`
  # (`inc4/step8/sweep/table.R`): one line an item, the layer's column, the scale's limits, the
  # legend's keys and a colour bar's or colour steps' decor, colour bars in the gradient form
  # Giggly draws. A size by area under log10 then reverse is left out: its limits' high end is
  # -0, where R draws every value at an infinite size and Giggly raises (below).
  test "every transformation on every kind of continuous non-position scale draws as ggplot2's" do
    cases = cases()
    assert Enum.count(cases) == 552

    differing =
      for {{kind, transform, given, oob}, items} <- cases,
          {kind, transform} != {"size_area", "log10_reverse"},
          {aesthetic, plot} =
            plot(kind, [{:transform, transform(transform)} | limits(given) ++ oob(kind, oob)]),
          drawn = drawn(aesthetic, plot),
          {item, printed} <- items,
          not same?(Map.fetch!(drawn, item), printed(printed), transform) do
        {kind, transform, given, oob, item}
      end

    assert differing == []
  end

  # ggplot2 4.0.3 transforms a colour before the stat: geom_count() counts -1 and -2, both NaN
  # under log10, as one place's value, n = 2 at size 6 and grey50, and 10 alone at size 1
  # (`inc4/step8/sum.R`); and a stat's own column, its count, after it: under a log10 size 3, 2
  # and 1 at 6, 4.9715543354317129 and 1 (`inc4/step8/count.R`).
  test "a column is transformed before the stat, and the stat's own after it" do
    counted =
      %{"x" => [1, 1, 1], "y" => [1, 1, 1], "z" => [-1, -2, 10]}
      |> Plot.new(%{x: "x", y: "y", color: "z"})
      |> Plot.geom_count()
      |> Plot.scale_color_continuous(transform: :log10)
      |> Giggly.layer_data()

    sized =
      %{"x" => [1, 1, 1, 2, 2, 3], "y" => List.duplicate(1, 6)}
      |> Plot.new(%{x: "x", y: "y"})
      |> Plot.geom_count()
      |> Plot.scale_size_continuous(transform: :log10)
      |> Giggly.layer_data()

    assert {DataFrame.pull(counted, :color), DataFrame.pull(counted, :n),
            DataFrame.pull(counted, :size)} == {["#336A98", "#7F7F7F"], [1.0, 2.0], [1.0, 6.0]}

    assert {DataFrame.pull(sized, :n), DataFrame.pull(sized, :size)} ==
             {[3.0, 2.0, 1.0], [6.0, 4.9715543354317129, 1.0]}
  end

  test "a column not of numbers is left for its transformed scale to refuse" do
    plot =
      %{"x" => [1, 2], "y" => [1, 2], "z" => ["a", "b"]}
      |> Plot.new(%{x: "x", y: "y", color: "z"})
      |> Plot.geom_point()
      |> Plot.scale_color_continuous(transform: :log10)

    error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end

    assert error.message =~
             "the plot's color scale is continuous through log10, but the layer at index 0 " <>
               "maps :color to \"z\", a discrete column"
  end

  # ggplot2 4.0.3 draws a size by area under log10 then reverse, whose limits' high end is -0, at
  # an infinite size, so not at all (`inc4/step8/sweep/table.R`); Giggly refuses it, as it
  # refuses any value it would place infinitely large.
  test "a size by area whose transformed limits end at 0 is refused when run" do
    {_aesthetic, plot} = plot("size_area", transform: {:compose, [:log10, :reverse]})
    error = assert_raise ArgumentError, fn -> Giggly.layer_data(plot) end
    assert error.message =~ "cannot place -0.47712125471966244 when that end is 0"
  end
end
