defmodule Giggly.ScaleTest do
  use ExUnit.Case, async: true

  alias Giggly.{Datasets, Geom, Scale}
  alias Scales.Palette

  # A new discrete alpha scale trained once on `values`.
  defp discrete_alpha(values) do
    :discrete
    |> Scale.new(:alpha)
    |> Scale.train(values, :none)
  end

  # A new continuous colour scale trained once on `values`.
  defp gradient_scale(values) do
    :continuous
    |> Scale.new(:color)
    |> Scale.train(values, :none)
  end

  # A new discrete colour scale trained once on `values`.
  defp hue_scale(values) do
    :discrete
    |> Scale.new(:color)
    |> Scale.train(values, :none)
  end

  # A new scale of `kind` trained once on `values`.
  defp trained(kind, values) do
    kind
    |> Scale.new()
    |> Scale.train(values, :none)
  end

  describe "kind/1 and kind/2" do
    test "a column's type decides its scale's kind, and a type with no scale yet gets none" do
      dtypes = [
        :integer,
        :float,
        :null,
        :string,
        :boolean,
        :atom,
        :category,
        :date,
        :time,
        :term,
        {:list, :float}
      ]

      assert Enum.map(dtypes, &Scale.kind/1) == [
               :continuous,
               :continuous,
               :continuous,
               :discrete,
               :discrete,
               :discrete,
               :discrete,
               :date,
               :time,
               :none,
               :none
             ]
    end

    test "a date has a scale on a position aesthetic and none yet on alpha or size" do
      assert {Scale.kind(:date, :x), Scale.kind(:date, :ymax), Scale.kind(:date, :alpha),
              Scale.kind(:date, :size)} === {:date, :date, :none, :none}

      assert {Scale.kind(:float, :alpha), Scale.kind(:string, :alpha)} ===
               {:continuous, :discrete}
    end

    test "a colour or fill is discrete or continuous as any aesthetic is, and a date has none yet" do
      assert Enum.map([:string, :boolean, :atom, :category], fn dtype ->
               Scale.kind(dtype, :color)
             end) === [:discrete, :discrete, :discrete, :discrete]

      assert Enum.map([:integer, :float, :null, :date], fn dtype -> Scale.kind(dtype, :fill) end) ===
               [:continuous, :continuous, :continuous, :none]
    end

    test "a date-time, naive or in a zone, has a scale on a position aesthetic and none yet else" do
      dtypes = [{:datetime, "Etc/UTC"}, {:datetime, "Europe/London"}, :naive_datetime]

      assert {Enum.map(dtypes, &Scale.kind/1),
              Enum.map(dtypes, fn dtype -> Scale.kind(dtype, :xmin) end),
              Enum.map(dtypes, fn dtype -> Scale.kind(dtype, :color) end)} ===
               {[:datetime, :datetime, :naive_datetime], [:datetime, :datetime, :naive_datetime],
                [:none, :none, :none]}
    end

    test "a time has a scale on a position aesthetic and none yet else" do
      assert {Scale.kind(:time, :y), Scale.kind(:time, :xend), Scale.kind(:time, :fill),
              Scale.kind(:time, :alpha)} === {:time, :time, :none, :none}
    end
  end

  # The training rules are `Scales.DataRange`'s, which its tests pin to R's; these check the scale
  # records what it trains.
  describe "train/3" do
    test "a continuous scale records the range its trainings span" do
      scale =
        :continuous
        |> Scale.new()
        |> Scale.train([nil, 3, :infinity, 1.5], :none)
        |> Scale.train([2], :none)

      assert scale === %Scale.Continuous{
               range: {1.5, 3},
               transform: :identity,
               palette: :identity,
               na_value: nil,
               guide: :axis
             }
    end

    test "a discrete scale records the levels its trainings bring, and whether a factor led" do
      scale =
        :discrete
        |> Scale.new()
        |> Scale.train(["b", nil, "a"], :none)
        |> Scale.train(["c", "a"], :none)

      assert scale === %Scale.Discrete{
               levels: ["a", "b", "c", nil],
               factor: false,
               continuous_range: :none,
               palette: :identity,
               na_value: nil,
               guide: :axis
             }
    end
  end

  describe "train_positions/2" do
    test "a discrete scale handed positions widens its continuous range, not its levels" do
      scale =
        :discrete
        |> trained(["b", "a"])
        |> Scale.train_positions([1, 2])
        |> Scale.train_positions([0.55, nil, 2.45])

      assert scale === %Scale.Discrete{
               levels: ["a", "b"],
               factor: false,
               continuous_range: {0.55, 2.45},
               palette: :identity,
               na_value: nil,
               guide: :axis
             }
    end
  end

  describe "reset/1" do
    test "a continuous scale forgets its range, a discrete one its continuous range alone" do
      continuous = trained(:continuous, [1.0, 3.0])

      discrete =
        :discrete
        |> trained(["b", "a"])
        |> Scale.train_positions([0.55, 2.45])

      assert {Scale.reset(continuous), Scale.reset(discrete)} ===
               {%Scale.Continuous{
                  range: :none,
                  transform: :identity,
                  palette: :identity,
                  na_value: nil,
                  guide: :axis
                },
                %Scale.Discrete{
                  levels: ["a", "b"],
                  factor: false,
                  continuous_range: :none,
                  palette: :identity,
                  na_value: nil,
                  guide: :axis
                }}
    end
  end

  describe "map/2" do
    test "a discrete value is put at its level's position, counting from 1" do
      scale = trained(:discrete, ["6", "4", nil])

      assert Scale.map(scale, ["6", "4", "6", nil]) === [2, 1, 2, 3]
    end

    test "a continuous value is left as it is" do
      scale = trained(:continuous, [2.62, 2.875])

      assert Scale.map(scale, [2.62, 2.875]) === [2.62, 2.875]
    end
  end

  describe "dimension/2" do
    test "an extent is widened by the expansion handed it, none leaving the limits as they are" do
      continuous = trained(:continuous, [1, 3])
      discrete = trained(:discrete, ["a", "b", "c"])
      none = [mult: {0.0, 0.0}, add: {0.0, 0.0}]

      assert Scale.dimension(continuous, none) === {1.0, 3.0}
      assert Scale.dimension(continuous, mult: {0.5, 0.0}, add: {0.0, 1.0}) === {0.0, 4.0}
      assert Scale.dimension(discrete, none) === {1.0, 3.0}
    end
  end

  describe "dimension/1" do
    test "a continuous range is widened by 5% of its width at each end" do
      scale = trained(:continuous, [1, 3])

      assert Scale.dimension(scale) === {0.9, 3.1}
    end

    test "a range of zero width is widened as though its width were 1" do
      scale = trained(:continuous, [0])

      assert Scale.dimension(scale) === {-0.05, 0.05}
    end

    test "ends that differ only by rounding error, relative to their size, count as one value" do
      scale = trained(:continuous, [1000.0, 1000.0000000000001])

      assert Scale.dimension(scale) === {999.95, 1000.0500000000001}
    end

    test "an extent still zero wide once widened is its middle, both ends equal" do
      scale = trained(:continuous, [1.0e12])

      assert Scale.dimension(scale) === {1.0e12, 1.0e12}
    end

    test "an untrained continuous scale spans 0 to 1 before it is widened" do
      scale = Scale.new(:continuous)

      assert Scale.dimension(scale) === {-0.05, 1.05}
    end

    test "discrete levels at positions 1 to n are widened by 0.6" do
      scale = trained(:discrete, ["6", "4", "8"])

      assert Scale.dimension(scale) === {0.4, 3.6}
    end

    # Golden: ggplot2 4.0.3's x extents in R 4.6.1, for bars 0.9 wide on seven levels (`mpg`'s
    # classes) and 1.5 wide on three (`geom_col(width = 1.5)`).
    test "a continuous range widens the levels' extent where it reaches further, unwidened" do
      levels = Enum.map(1..7, fn level -> "level #{level}" end)

      narrow =
        :discrete
        |> trained(levels)
        |> Scale.train_positions([0.55, 7.45])

      wide =
        :discrete
        |> trained(["a", "b", "c"])
        |> Scale.train_positions([0.25, 3.75])

      assert {Scale.dimension(narrow), Scale.dimension(wide)} === {{0.4, 7.6}, {0.25, 3.75}}
    end
  end

  describe "breaks/2" do
    test "a continuous scale's breaks are its transformation's, labelled with shared decimals" do
      scale = trained(:continuous, [0, 10])
      extent = Scale.dimension(scale)

      assert Scale.breaks(scale, extent) ===
               [{0.0, "0.0"}, {2.5, "2.5"}, {5.0, "5.0"}, {7.5, "7.5"}, {10.0, "10.0"}]
    end

    test "breaks outside the extent are dropped, and whole breaks are labelled without decimals" do
      scale = trained(:continuous, [1.513, 5.424])
      extent = Scale.dimension(scale)

      assert Scale.breaks(scale, extent) ===
               [{2.0, "2"}, {3.0, "3"}, {4.0, "4"}, {5.0, "5"}]
    end

    test "a break exactly at an end of the extent is kept" do
      scale = trained(:continuous, [3, 17])

      assert Scale.breaks(scale, {0.0, 20.0}) ===
               [{0.0, "0"}, {5.0, "5"}, {10.0, "10"}, {15.0, "15"}, {20.0, "20"}]
    end

    test "an extent of zero width has one break, at its end" do
      scale = trained(:continuous, [1.0e16])
      extent = Scale.dimension(scale)

      assert Scale.breaks(scale, extent) === [{1.0e16, "10000000000000000"}]
    end

    test "an untrained continuous scale has no breaks" do
      scale = Scale.new(:continuous)

      assert Scale.breaks(scale, {-0.05, 1.05}) === []
    end

    test "a discrete scale has a break at each level, a missing level labelled NA" do
      scale = trained(:discrete, ["6", nil, "4"])
      extent = Scale.dimension(scale)

      assert Scale.breaks(scale, extent) === [{1, "4"}, {2, "6"}, {3, "NA"}]
    end
  end

  describe "minor_breaks/3" do
    test "a continuous scale's minor breaks fall midway between its breaks" do
      scale = trained(:continuous, [0, 10])
      extent = Scale.dimension(scale)
      breaks = Scale.breaks(scale, extent)

      assert Scale.minor_breaks(scale, breaks, extent) ===
               [1.25, 3.75, 6.25, 8.75]
    end

    test "minor breaks fall between the outermost breaks and the extent's ends too" do
      scale = trained(:continuous, [1.513, 5.424])
      extent = Scale.dimension(scale)
      breaks = Scale.breaks(scale, extent)

      assert Scale.minor_breaks(scale, breaks, extent) ===
               [1.5, 2.5, 3.5, 4.5, 5.5]
    end

    test "a minor break exactly at an end of the extent is kept" do
      scale = trained(:continuous, [0, 10])
      breaks = [{2.5, "2.5"}, {5.0, "5.0"}, {7.5, "7.5"}]

      assert Scale.minor_breaks(scale, breaks, {1.25, 8.75}) === [1.25, 3.75, 6.25, 8.75]
    end

    test "an axis with fewer than two breaks has no minor breaks" do
      scale = trained(:continuous, [1.0e16])
      extent = Scale.dimension(scale)
      breaks = Scale.breaks(scale, extent)

      assert Scale.minor_breaks(scale, breaks, extent) === []
    end

    test "a discrete scale has no minor breaks" do
      scale = trained(:discrete, ["a", "b", "c"])
      extent = Scale.dimension(scale)
      breaks = Scale.breaks(scale, extent)

      assert Scale.minor_breaks(scale, breaks, extent) === []
    end
  end

  # Golden throughout: ggplot2 4.0.3's view of mtcars' weights, 1.513 to 5.424, under the same
  # options in R 4.6.1 (`layer_data()` and the first panel's params), of mpg's class counts, 0 to
  # 62, and of a plot with no rows (`xlim(NA, 5)` spans the empty axis's -0.05 to 1.05 with no
  # breaks); labels are Giggly's own. They move with how ggplot2 widens limits, chooses breaks or
  # censors a position.
  describe "a continuous scale's options" do
    # A continuous position scale with `options` set, trained on mtcars' lightest and heaviest
    # weights.
    defp weights(options) do
      Scale.Continuous
      |> struct!(options)
      |> Scale.train([1.513, 5.424], :none)
    end

    test "limits replace the range before it is widened, and a nil end is the range's" do
      both = weights(limits: {2.0, 5.0})
      upper = weights(limits: {nil, 4.0})

      assert {Scale.dimension(both), Scale.dimension(upper)} ===
               {{1.85, 5.15}, {1.38865, 4.12435}}
    end

    test "limits with both ends give an axis before any data, and one end alone does not" do
      assert {Scale.dimension(%Scale.Continuous{limits: {2.0, 5.0}}),
              Scale.dimension(%Scale.Continuous{limits: {nil, 5.0}})} ===
               {{1.85, 5.15}, {-0.05, 1.05}}
    end

    test "expansion is set at each end, a multiple of the width plus a constant" do
      counts =
        Scale.train(
          %Scale.Continuous{expand: [mult: {0.0, 0.05}, add: {0.0, 0.0}]},
          [0, 62],
          :none
        )

      none = weights(expand: [mult: {0.0, 0.0}, add: {0.0, 0.0}])
      added = weights(expand: [mult: {0.0, 0.0}, add: {2.0, 1.0}])

      assert {Scale.dimension(counts), Scale.dimension(none), Scale.dimension(added)} ===
               {{0.0, 65.1}, {1.513, 5.424}, {-0.4870000000000001, 6.424}}
    end

    test "given breaks are kept, in the order given, wherever they fall inside the extent" do
      scale = weights(breaks: [5.5, 1.0, 3.0, 1.4, 7.0])

      assert Scale.breaks(scale, Scale.dimension(scale)) ===
               [{5.5, "5.5"}, {3.0, "3.0"}, {1.4, "1.4"}]
    end

    test "breaks of :none give no breaks, and so no minor breaks either" do
      scale = weights(breaks: :none)
      extent = Scale.dimension(scale)
      breaks = Scale.breaks(scale, extent)

      assert {breaks, Scale.minor_breaks(scale, breaks, extent)} === {[], []}
    end

    test "given labels go with their breaks, those of breaks left out going with them" do
      scale = weights(breaks: [1.0, 3.0, 5.0], labels: ["one", "three", "five"])

      assert Scale.breaks(scale, Scale.dimension(scale)) === [{3.0, "three"}, {5.0, "five"}]
    end

    test "a labels function is handed every break drawn at once and labels each" do
      labeller = fn breaks ->
        Enum.map(breaks, fn break -> "#{round(break)} of #{length(breaks)}" end)
      end

      scale = weights(labels: labeller)

      assert Scale.breaks(scale, Scale.dimension(scale)) ===
               [{2.0, "2 of 4"}, {3.0, "3 of 4"}, {4.0, "4 of 4"}, {5.0, "5 of 4"}]
    end

    test "a labels function that does not give a string for each break is refused" do
      for labeller <- [
            fn _breaks -> ["one"] end,
            fn breaks -> breaks end,
            fn [_first | rest] -> ["2" | rest] end
          ] do
        scale = weights(labels: labeller)

        assert_raise ArgumentError, ~r/must return a string for each of the breaks/, fn ->
          Scale.breaks(scale, Scale.dimension(scale))
        end
      end
    end

    test "labels of :none leave each break unlabelled" do
      scale = weights(limits: {2.0, 3.0}, labels: :none)

      assert Scale.breaks(scale, Scale.dimension(scale)) ===
               [{2.0, :none}, {2.25, :none}, {2.5, :none}, {2.75, :none}, {3.0, :none}]
    end

    test "given minor breaks are kept inside the extent, less the breaks; :none gives none" do
      given = weights(minor_breaks: [2.25, 3.0, 4.25, 9.0])
      none = weights(minor_breaks: :none)
      extent = Scale.dimension(given)

      assert {Scale.minor_breaks(given, Scale.breaks(given, extent), extent),
              Scale.minor_breaks(none, Scale.breaks(none, extent), extent)} === {[2.25, 4.25], []}
    end

    test "a position outside the limits is censored, an infinite one kept" do
      both = weights(limits: {2.0, 5.0})
      upper = weights(limits: {nil, 4.0})
      values = [1.513, 2.0, 3.5, 5.0, 5.424, nil, :infinity, :neg_infinity]

      assert {Scale.map(both, values), Scale.censor(both, values), Scale.censor(upper, values)} ===
               {[nil, 2.0, 3.5, 5.0, nil, nil, :infinity, :neg_infinity],
                [nil, 2.0, 3.5, 5.0, nil, nil, :infinity, :neg_infinity],
                [1.513, 2.0, 3.5, nil, nil, nil, :infinity, :neg_infinity]}
    end

    test "a discrete scale's positions are not censored" do
      scale = trained(:discrete, ["a", "b"])

      assert Scale.censor(scale, [0.55, 2.45, 9.0]) === [0.55, 2.45, 9.0]
    end

    test "a scale's kind is discrete, date, date-time, time or continuous" do
      assert Enum.map(
               [:discrete, :date, :datetime, :naive_datetime, :time, :continuous],
               fn kind ->
                 Scale.kind_of(Scale.new(kind))
               end
             ) ===
               [:discrete, :date, :datetime, :datetime, :time, :continuous]
    end

    test "a time scale is continuous through the time-of-day transformation" do
      assert Scale.new(:time) === %Scale.Continuous{transform: :time}
    end

    test "a date-time scale's kind is naive once a naive column has settled it" do
      naive = %Scale.Continuous{transform: {:datetime, :naive, Calendar.UTCOnlyTimeZoneDatabase}}
      utc = %Scale.Continuous{transform: {:datetime, "Etc/UTC", Calendar.UTCOnlyTimeZoneDatabase}}

      assert {Scale.kind_of(naive), Scale.kind_of(utc)} === {:naive_datetime, :datetime}
    end
  end

  # Golden throughout: R 4.6.1's `scales` 1.4.0 and ggplot2 4.0.3, printed to 17 significant
  # digits: `scales::rescale()`, `seq(0.1, 1, length.out = n)` and the alpha `layer_data()` of the
  # same values. They move only with R's arithmetic, or with ggplot2's default alpha range.
  describe "a discrete scale's options" do
    # A discrete position scale with `options` set, trained on p, q, r and a missing value.
    defp letters(options) do
      Scale.Discrete
      |> struct!(options)
      |> Scale.train(["p", "q", "r", nil], :none)
    end

    # Each scale's map of p, q, r and the missing value, its breaks and its extent.
    defp drawn(scale) do
      {Scale.map(scale, ["p", "q", "r", nil]), Scale.breaks(scale, Scale.dimension(scale)),
       Scale.dimension(scale)}
    end

    # Golden: ggplot2 4.0.3's layer_data() x and panel x breaks, labels and range in R 4.6.1 for
    # points at "p", "q", "r" and NA under scale_x_discrete(limits = ...).
    test "limits choose the values shown and their order, a value left out mapping to nil" do
      assert drawn(letters(limits: ["r", "p"])) ===
               {[2, nil, 1, nil], [{1, "r"}, {2, "p"}], {0.4, 2.6}}

      assert drawn(letters(limits: ["r", "z", "p"])) ===
               {[3, nil, 1, nil], [{1, "r"}, {2, "z"}, {3, "p"}], {0.4, 3.6}}

      assert drawn(letters(limits: ["r", nil, "p"])) ===
               {[3, nil, 1, 2], [{1, "r"}, {2, "NA"}, {3, "p"}], {0.4, 3.6}}
    end

    # Golden: as above, under scale_x_discrete(breaks = ...), with limits = c("p", "q") in the last.
    test "breaks mark the values given among the limits, in the order given" do
      given = letters(breaks: ["q", "p"])
      outside = letters(limits: ["p", "q"], breaks: ["q", "r"])
      none = letters(breaks: :none)

      assert {Scale.breaks(given, {0.4, 4.6}), Scale.breaks(outside, {0.4, 2.6}),
              Scale.breaks(none, {0.4, 4.6})} === {[{2, "q"}, {1, "p"}], [{2, "q"}], []}
    end

    # Golden: as above, under scale_x_discrete(labels = ...): R's named vector is matched by
    # value, a value it does not hold keeping its own label, and an unnamed one goes with the
    # breaks by place, one left out taking its label with it. R cannot name its missing value; a
    # map can.
    test "labels are given by place, by value, by a function, or left out" do
      by_place = letters(breaks: ["q", "p"], labels: ["Q", "P"])
      dropped = letters(limits: ["p", "q"], breaks: ["q", "r"], labels: ["Q", "R"])
      by_value = letters(labels: %{"q" => "Q", "zz" => "Z"})
      missing = letters(labels: %{nil => "none"})
      none = letters(labels: :none)

      assert Enum.map([by_place, dropped, by_value, missing, none], fn scale ->
               Scale.breaks(scale, Scale.dimension(scale))
             end) === [
               [{2, "Q"}, {1, "P"}],
               [{2, "Q"}],
               [{1, "p"}, {2, "Q"}, {3, "r"}, {4, "NA"}],
               [{1, "p"}, {2, "q"}, {3, "r"}, {4, "none"}],
               [{1, :none}, {2, :none}, {3, :none}, {4, :none}]
             ]
    end

    test "a labels function is handed every break's value, the missing value among them" do
      labeller = fn values -> Enum.map(values, &inspect/1) end
      scale = letters(labels: labeller)

      assert Scale.breaks(scale, Scale.dimension(scale)) ===
               [{1, ~s("p")}, {2, ~s("q")}, {3, ~s("r")}, {4, "nil"}]
    end

    test "a list of labels not one for each break, or a function's wrong count, is refused" do
      short = letters(labels: ["P", "Q"])
      counted = letters(labels: fn [first | _rest] -> [to_string(first)] end)

      assert_raise ArgumentError,
                   ~r/2 labels must be one for each of its 4 breaks, got: \["P", "Q"\]/,
                   fn ->
                     Scale.breaks(short, Scale.dimension(short))
                   end

      assert_raise ArgumentError, ~r/labels function must return a string for each/, fn ->
        Scale.breaks(counted, Scale.dimension(counted))
      end
    end

    # Golden: ggplot2 4.0.3 in R 4.6.1, the panel's x range and labels for factor(c(4, 6, 8, 10))
    # with labels = c("10" = "ten") and limits = c("8", "4"), which name the numbers by their text.
    test "a number names the value equal to it, an integer a float's level" do
      factor =
        :discrete
        |> trained([4.0, 6.0, 8.0, 10.0])
        |> struct!(labels: %{10 => "ten"})

      limited =
        :discrete
        |> trained([4, 6, 8])
        |> struct!(limits: [8.0, 4.0])

      assert {Scale.breaks(factor, Scale.dimension(factor)), Scale.map(limited, [4, 6, 8])} ===
               {[{1, "4"}, {2, "6"}, {3, "8"}, {4, "ten"}], [2, nil, 1]}
    end

    # Golden: as above, the panel's x range under expansion(mult = 0.1) and expansion(add = 2).
    test "expansion is set at each end, a multiple of the distance from first to last plus a constant" do
      mult = letters(expand: [mult: {0.1, 0.1}, add: {0.0, 0.0}])
      add = letters(expand: [mult: {0.0, 0.0}, add: {2.0, 2.0}])

      assert {Scale.dimension(mult), Scale.dimension(add)} === {{0.7, 4.3}, {-1.0, 6.0}}
    end

    # Golden: ggplot2 4.0.3's x range in R 4.6.1 for ggplot(s, aes(y = a)) + geom_bar() +
    # scale_x_discrete(), the counts its only values, and ggplot2's `expand_limits_discrete()` on
    # no values at all.
    test "with no values, a continuous range alone is widened, or else 0 to 1" do
      empty = Scale.new(:discrete)
      counts = Scale.train_positions(empty, [0.0, 1.0])

      assert {Scale.dimension(counts), Scale.dimension(empty)} === {{-0.6, 1.6}, {-0.6, 1.6}}
    end

    test "a discrete legend's breaks are its limits" do
      scale =
        :discrete
        |> Scale.new(:color)
        |> struct!(limits: ["r", "p"])
        |> Scale.train(["p", "q", "r"], :none)

      assert Scale.legend_breaks(scale) === [{"r", "r"}, {"p", "p"}]
    end
  end

  describe "a date scale's options" do
    # A date scale with `options` set, trained on the 30 days to 2026-10-19, and its axis's
    # extent, as the scale_date page's `last_month` spans.
    defp last_month(options) do
      scale =
        Scale.Continuous
        |> struct!([{:transform, :date} | options])
        |> Scale.train([20_716.0, 20_745.0], :none)

      {scale, Scale.dimension(scale)}
    end

    # Golden: ggplot2 4.0.3's panel x breaks and labels in R 4.6.1 for the scale_date page's
    # `base` on that month: given breaks and a width's are written in full, as R's `format()`
    # writes a date with no format, and the default breaks as suits their step.
    test "breaks the scale did not choose are labelled in full, its own as suits their step" do
      {given, extent} = last_month(breaks: [~D[2026-09-25], ~D[2026-10-10]])
      {width, _extent} = last_month(breaks: {:width, [week: 2]})
      {default, _extent} = last_month([])

      assert {extent, Scale.breaks(given, extent), Scale.breaks(width, extent),
              Scale.breaks(default, extent)} ===
               {{20_714.55, 20_746.45}, [{20_721.0, "2026-09-25"}, {20_736.0, "2026-10-10"}],
                [{20_724.0, "2026-09-28"}, {20_738.0, "2026-10-12"}],
                [
                  {20_717.0, "Sep 21"},
                  {20_724.0, "Sep 28"},
                  {20_731.0, "Oct 05"},
                  {20_738.0, "Oct 12"},
                  {20_745.0, "Oct 19"}
                ]}
    end

    # Golden: as above, with date_labels = "%d" beside date_breaks = "1 week", and with
    # date_labels = "%b %d" alone.
    test "a format writes every break's label, by width or by default" do
      {width, extent} = last_month(breaks: {:width, [week: 1]}, labels: {:format, "%d"})
      {default, _extent} = last_month(labels: {:format, "%b %d"})

      assert {Scale.breaks(width, extent), Scale.breaks(default, extent)} ===
               {[
                  {20_717.0, "21"},
                  {20_724.0, "28"},
                  {20_731.0, "05"},
                  {20_738.0, "12"},
                  {20_745.0, "19"}
                ],
                [
                  {20_717.0, "Sep 21"},
                  {20_724.0, "Sep 28"},
                  {20_731.0, "Oct 05"},
                  {20_738.0, "Oct 12"},
                  {20_745.0, "Oct 19"}
                ]}
    end

    test "a labels function is handed the breaks as dates" do
      {scale, extent} =
        last_month(
          breaks: {:width, [week: 2]},
          labels: fn dates -> Enum.map(dates, &Date.to_iso8601/1) end
        )

      assert Scale.breaks(scale, extent) ===
               [{20_724.0, "2026-09-28"}, {20_738.0, "2026-10-12"}]
    end

    # Golden: as above, with date_minor_breaks = "1 day": a minor line every day inside the
    # extent, the breaks among them, which the grid leaves out.
    test "a width of minor breaks gives one every step inside the extent, less the breaks" do
      {scale, extent} = last_month(minor_breaks: {:width, [day: 1]})
      breaks = Scale.breaks(scale, extent)
      major = [20_717.0, 20_724.0, 20_731.0, 20_738.0, 20_745.0]

      assert Scale.minor_breaks(scale, breaks, extent) ===
               Enum.map(20_715..20_746, fn day -> day / 1 end) -- major
    end
  end

  describe "takes?/2 and a date under the identity" do
    test "a scale takes its own kind of column, and an untransformed continuous one a date's" do
      assert Enum.map(
               [
                 {Scale.new(:continuous), :continuous},
                 {Scale.new(:continuous), :date},
                 {%Scale.Continuous{transform: :log10}, :date},
                 {%Scale.Continuous{transform: :reverse}, :date},
                 {Scale.new(:date), :date},
                 {Scale.new(:date), :continuous},
                 {Scale.new(:discrete), :discrete},
                 {Scale.new(:discrete), :continuous},
                 {Scale.new(:discrete), :date},
                 {Scale.new(:continuous), :discrete}
               ],
               fn {scale, kind} -> Scale.takes?(scale, kind) end
             ) === [true, true, false, false, true, false, true, false, false, false]
    end

    test "a date-time scale takes date-times of either kind until a column settles which" do
      database = Calendar.UTCOnlyTimeZoneDatabase
      unsettled = Scale.new(:datetime)
      naive = %Scale.Continuous{transform: {:datetime, :naive, database}}
      utc = %Scale.Continuous{transform: {:datetime, "Etc/UTC", database}}

      assert Enum.map(
               [
                 {unsettled, :datetime},
                 {unsettled, :naive_datetime},
                 {unsettled, :date},
                 {unsettled, :continuous},
                 {naive, :naive_datetime},
                 {naive, :datetime},
                 {utc, :datetime},
                 {utc, :naive_datetime},
                 {Scale.new(:continuous), :datetime},
                 {Scale.new(:continuous), :naive_datetime},
                 {%Scale.Continuous{transform: :sqrt}, :datetime},
                 {Scale.new(:date), :datetime}
               ],
               fn {scale, kind} -> Scale.takes?(scale, kind) end
             ) === [true, true, false, false, true, false, true, false, true, true, false, false]
    end

    test "a time scale takes times alone, and an untransformed continuous scale takes them too" do
      assert Enum.map(
               [
                 {Scale.new(:time), :time},
                 {Scale.new(:time), :datetime},
                 {Scale.new(:time), :continuous},
                 {Scale.new(:datetime), :time},
                 {Scale.new(:date), :time},
                 {Scale.new(:continuous), :time},
                 {%Scale.Continuous{transform: :log10}, :time}
               ],
               fn {scale, kind} -> Scale.takes?(scale, kind) end
             ) === [true, false, false, false, false, true, false]
    end

    # Golden: ggplot2 4.0.3's layer_data() x and panel x range, breaks and labels in R 4.6.1 for
    # points on 2024-01-01, 2024-01-11 and 2024-02-15 under scale_x_continuous().
    test "an untransformed continuous scale places a date at its days and labels them as numbers" do
      scale = Scale.new(:continuous)
      days = Scale.transform(scale, [~D[2024-01-01], ~D[2024-01-11], ~D[2024-02-15], nil])
      trained = Scale.train(scale, days, :none)
      extent = Scale.dimension(trained)

      assert {days, extent, Scale.breaks(trained, extent)} ===
               {[19_723.0, 19_733.0, 19_768.0, nil], {19_720.75, 19_770.25},
                [
                  {19_730.0, "19730"},
                  {19_740.0, "19740"},
                  {19_750.0, "19750"},
                  {19_760.0, "19760"},
                  {19_770.0, "19770"}
                ]}
    end
  end

  describe "settle_zone/2" do
    test "a date-time scale takes its first column's zone, or naive, once and for all" do
      database = Calendar.UTCOnlyTimeZoneDatabase
      unsettled = Scale.new(:datetime)
      naive = %Scale.Continuous{transform: {:datetime, :naive, database}}
      date = Scale.new(:date)

      assert {Scale.settle_zone(unsettled, {:datetime, "Etc/UTC"}),
              Scale.settle_zone(unsettled, :naive_datetime),
              Scale.settle_zone(naive, {:datetime, "Etc/UTC"}), Scale.settle_zone(date, :date)} ===
               {{:ok, %Scale.Continuous{transform: {:datetime, "Etc/UTC", database}}},
                {:ok, naive}, {:ok, naive}, {:ok, date}}
    end

    test "a zone the scale's time zone database does not know is refused, named with it" do
      unsettled = Scale.new(:datetime)

      assert Scale.settle_zone(unsettled, {:datetime, "Europe/London"}) ===
               {:error, {"Europe/London", Calendar.UTCOnlyTimeZoneDatabase}}
    end

    # scale_x_datetime(timezone = "Asia/Kolkata") keeps its zone whatever its column's tzone, and
    # its database need know only that zone, not the column's.
    test "a zone a plot gave is kept whatever the column's" do
      given = %Scale.Continuous{
        transform: {:datetime, "Etc/UTC", Calendar.UTCOnlyTimeZoneDatabase}
      }

      assert {Scale.settle_zone(given, {:datetime, "America/New_York"}),
              Scale.settle_zone(given, {:datetime, "Etc/UTC"})} === {{:ok, given}, {:ok, given}}
    end
  end

  describe "map/2 through a palette" do
    test "a continuous alpha is its place in the range rescaled onto 0.1 to 1, a missing one nil" do
      scale =
        :continuous
        |> Scale.new(:alpha)
        |> Scale.train([2, 4, nil, 10, 6], :none)

      assert Scale.map(scale, [2, 4, nil, 10, 6, 3.3, :nan]) ===
               [0.1, 0.325, nil, 1.0, 0.55, 0.24625, nil]
    end

    test "a discrete alpha spreads its present levels evenly from 0.1 to 1, a missing one nil" do
      scale =
        :discrete
        |> Scale.new(:alpha)
        |> Scale.train(["b", "a", nil, "c", "a"], :none)

      assert Scale.map(scale, ["b", "a", nil, "c", "a"]) === [0.55, 0.1, nil, 1.0, 0.1]
    end

    # A position scale's first training is reset before its second, so nothing a plot draws reads
    # its untrained range; only the scale itself pins it.
    test "a position scale is untrained, its palette the identity and its guide an axis" do
      assert {Scale.new(:continuous), Scale.new(:date), Scale.new(:discrete)} ===
               {%Scale.Continuous{
                  range: :none,
                  transform: :identity,
                  palette: :identity,
                  na_value: nil,
                  guide: :axis
                },
                %Scale.Continuous{
                  range: :none,
                  transform: :date,
                  palette: :identity,
                  na_value: nil,
                  guide: :axis
                },
                %Scale.Discrete{
                  levels: [],
                  continuous_range: :none,
                  palette: :identity,
                  na_value: nil,
                  guide: :axis
                }}
    end

    test "an alpha scale records ggplot2's default range and guide, untrained, the identity transformation" do
      assert {Scale.new(:continuous, :alpha), Scale.new(:discrete, :alpha)} ===
               {%Scale.Continuous{
                  range: :none,
                  transform: :identity,
                  palette: {:rescale, {0.1, 1.0}},
                  na_value: nil,
                  guide: :legend
                },
                %Scale.Discrete{
                  levels: [],
                  continuous_range: :none,
                  palette: {:sequence, {0.1, 1.0}},
                  na_value: nil,
                  guide: :legend
                }}
    end
  end

  # ggplot2's discrete colour scale records `pal_hue()`'s defaults and maps `NA` to grey50; the
  # palette's colours are `Scales.Palette`'s, which its tests pin to R's.
  describe "map/2 through the hue palette" do
    test "a colour or fill scale records pal_hue()'s hues, chroma and luminance, NA grey50, a legend" do
      expected = %Scale.Discrete{
        levels: [],
        continuous_range: :none,
        palette: {:hue, %{hue: {15.0, 375.0}, chroma: 100.0, luminance: 65.0, direction: 1}},
        na_value: "#7F7F7F",
        guide: :legend
      }

      assert {Scale.new(:discrete, :color), Scale.new(:discrete, :fill)} === {expected, expected}
    end

    test "each present level takes its hue in level order, and a missing value grey50" do
      scale = hue_scale(["r", "4", nil, "f"])
      [four, f, r] = Palette.discrete(scale.palette, 3)

      assert Scale.map(scale, ["f", nil, "4", "r", "4"]) === [f, "#7F7F7F", four, r, four]
    end

    test "a scale of missing values alone maps them all to grey50" do
      scale = hue_scale([nil])

      assert Scale.map(scale, [nil, nil]) === ["#7F7F7F", "#7F7F7F"]
    end
  end

  # Golden: ggplot2 4.0.3's `scale_colour_continuous()` in R 4.6.1, `layer_data()`'s colours and
  # `pal_seq_gradient("#132B43", "#56B1F7")`, through scales 1.4.0 and farver 2.1.2; a missing
  # value is grey50.
  describe "map/2 through the gradient" do
    test "a colour or fill scale records ggplot2's gradient, NA grey50, and a colour bar" do
      expected = %Scale.Continuous{
        range: :none,
        transform: :identity,
        palette: {:gradient, ["#132B43", "#56B1F7"]},
        na_value: "#7F7F7F",
        guide: :colorbar
      }

      assert {Scale.new(:continuous, :color), Scale.new(:continuous, :fill)} ===
               {expected, expected}
    end

    test "each value is its place in the range along the gradient, blended in Lab, a missing one grey50" do
      scale = gradient_scale([1, 2.5, nil, 4])
      [low, middle, high] = Palette.continuous(scale.palette, [0, 0.5, 1])

      assert Scale.map(scale, [1, 2.5, nil, 4, :nan]) === [
               low,
               middle,
               "#7F7F7F",
               high,
               "#7F7F7F"
             ]
    end
  end

  # Golden: ggplot2 4.0.3's colour bar for mpg's `colour = cty` in its gradient form, R 4.6.1:
  # `extract_decor()`'s 15 values over the range 9 to 35 and `extract_params()`'s places of the
  # breaks 10 to 35, printed to 17 digits.
  describe "samples/2 and places/2" do
    test "samples are R's seq() over the trained range" do
      scale = gradient_scale([9, 35])

      assert Scale.samples(scale, 15) === [
               9,
               10.857142857142858,
               12.714285714285715,
               14.571428571428571,
               16.428571428571431,
               18.285714285714285,
               20.142857142857142,
               22.0,
               23.857142857142858,
               25.714285714285715,
               27.571428571428573,
               29.428571428571431,
               31.285714285714285,
               33.142857142857139,
               35
             ]
    end

    test "a value's place runs from 0 at the range's low end to 1 at its high" do
      scale = gradient_scale([9, 35])

      assert Scale.places(scale, [10.0, 15.0, 20.0, 25.0, 30.0, 35.0]) === [
               0.038461538461538464,
               0.23076923076923078,
               0.42307692307692307,
               0.6153846153846154,
               0.8076923076923077,
               1.0
             ]
    end
  end

  describe "legend_breaks/1" do
    test "a continuous scale's are its breaks inside the trained range, labelled as an axis's" do
      scale =
        :continuous
        |> Scale.new(:alpha)
        |> Scale.train([1999, 2008], :none)

      assert Scale.legend_breaks(scale) === [
               {2000.0, "2000"},
               {2002.0, "2002"},
               {2004.0, "2004"},
               {2006.0, "2006"},
               {2008.0, "2008"}
             ]
    end

    test "a range of zero width has one break, its value, and an untrained scale none" do
      one =
        :continuous
        |> Scale.new(:alpha)
        |> Scale.train([7, 7], :none)

      untrained = Scale.new(:continuous, :alpha)

      assert {Scale.legend_breaks(one), Scale.legend_breaks(untrained)} === {[{7.0, "7"}], []}
    end

    test "a discrete scale's are its levels, a missing one last and labelled NA" do
      scale = discrete_alpha(["b", nil, "a"])

      assert Scale.legend_breaks(scale) === [{"a", "a"}, {"b", "b"}, {nil, "NA"}]
    end
  end

  # A discrete colour scale of `palette`, its missing value grey50, trained once on `values`.
  defp palette_scale(palette, values, options \\ []) do
    Scale.Discrete
    |> struct!([palette: palette, na_value: "#7F7F7F", guide: :legend] ++ options)
    |> Scale.train(values, :none)
  end

  # mtcars' horsepower range trains the scale, as R's does.
  defp size_scale(untrained), do: Scale.train(untrained, [52, 335], :none)

  # A scale of sizes by area from 0, as `Giggly.Plot.scale_size_area/2` records it with
  # `options`, trained on `values`.
  defp area_scale(values, options \\ []) do
    Scale.Continuous
    |> struct!([palette: {:abs_area, 6.0}, rescaler: :max, guide: :legend] ++ options)
    |> Scale.train(values, :none)
  end

  # A continuous colour scale of `palette`, its missing value grey50, trained once on `values`.
  defp gradient_through(colors, values, options \\ []) do
    Scale.Continuous
    |> struct!([palette: {:gradient, colors}, na_value: "#7F7F7F", guide: :colorbar] ++ options)
    |> Scale.train(values, :none)
  end

  defp hue(low, high, chroma \\ 100.0, luminance \\ 65.0, direction \\ 1),
    do: {:hue, %{hue: {low, high}, chroma: chroma, luminance: luminance, direction: direction}}

  # Golden: ggplot2 4.0.3's `scale_colour_manual()` in R 4.6.1, `layer_data()` and
  # `get_guide_data()` over mtcars's `factor(cyl)` and small tables: an unnamed list takes the
  # levels in order, a named one colours by name and shows only the levels it names, `NA` among
  # them, a value it lacks or one outside the limits grey50, and fewer colours than limits fail,
  # named or not ("Insufficient values in manual scale. 3 needed but only 2 provided.").
  describe "map/2 through a manual palette" do
    test "a list's colours go to the levels in order, the first of them as many as needed" do
      scale = palette_scale({:manual, ["#FF0000", "#0000FF", "#00FF00", "#FFA500"]}, [6, 4, 8])

      assert Scale.map(scale, [4, 6, 8, nil]) === ["#FF0000", "#0000FF", "#00FF00", "#7F7F7F"]
    end

    # As ggplot2 4.0.3's `scale_colour_manual(values = c("red", "blue", "green"), breaks = c("c",
    # "a"))` colours three levels in R 4.6.1 (`giggly_test.exs` has it): each break's level the
    # colour at its place, the level no break names grey50, the green named by no break, the limits
    # every level; and, as two values for three levels fail there, two values fail here, however
    # many breaks name them.
    test "a list named by breaks gives each break's level the colour at its place, the rest none" do
      scale = palette_scale({:manual, ["#FF0000", "#0000FF", "#00FF00"], [8, 4]}, [6, 4, 8])

      assert {Scale.map(scale, [4, 6, 8, nil]), Scale.Discrete.limits(scale)} ===
               {["#0000FF", "#7F7F7F", "#FF0000", "#7F7F7F"], [4, 6, 8]}

      short = palette_scale({:manual, ["#FF0000", "#0000FF"], [8, 4, 6, 10]}, [6, 4, 8])
      error = assert_raise ArgumentError, fn -> Scale.map(short, [4]) end
      assert error.message =~ "a value for each of its 3 levels, but has 2"
    end

    test "a list of too few colours for the levels cannot be drawn" do
      scale = palette_scale({:manual, ["#FF0000", "#0000FF"]}, [4, 6, 8])
      error = assert_raise ArgumentError, fn -> Scale.map(scale, [4]) end

      assert error.message =~
               ~s(needs a value for each of its 3 levels, but has 2: ["#FF0000", "#0000FF"])
    end

    test "a map colours each value by name, a number naming the value equal to it" do
      colors = %{8 => "#FF0000", 4 => "#0000FF", 6 => "#006400", 10 => "#FFA500"}
      scale = palette_scale({:manual, colors}, [4.0, 6.0, 8.0])

      assert Scale.map(scale, [4.0, 6.0, 8.0]) === ["#0000FF", "#006400", "#FF0000"]
    end

    test "a map's scale shows only the levels it names, and the missing value where it is one" do
      scale = palette_scale({:manual, %{"a" => "#FF0000", "c" => "#0000FF"}}, ["a", "b", nil])

      assert {Scale.legend_breaks(scale), Scale.map(scale, ["a", "b", nil])} ===
               {[{"a", "a"}, {nil, "NA"}], ["#FF0000", "#7F7F7F", "#7F7F7F"]}
    end

    test "a limit the map names takes its colour, one it does not the missing value" do
      colors = %{4 => "#0000FF", 10 => "#FFA500", 12 => "#FF0000"}
      scale = palette_scale({:manual, colors}, [4, 6], limits: [4, 6, 10])

      assert {Scale.legend_breaks(scale), Scale.map(scale, [4, 6, 10])} ===
               {[{4, "4"}, {6, "6"}, {10, "10"}], ["#0000FF", "#7F7F7F", "#FFA500"]}
    end

    test "a map of fewer colours than limits cannot be drawn, whatever their names" do
      scale =
        palette_scale({:manual, %{4 => "#0000FF", 10 => "#FFA500"}}, [4], limits: [4, 6, 10])

      assert_raise ArgumentError, ~r/needs a value for each of its 3 levels, but has 2/, fn ->
        Scale.map(scale, [4])
      end
    end
  end

  # A brewer palette's colours are `Scales.Palette`'s, which its tests pin to R's. Golden: ggplot2
  # 4.0.3's `scale_colour_brewer(palette = "Set1")` in R 4.6.1 gives a tenth level `NA` with a
  # warning and leaves it undrawn; nine levels are its largest set.
  describe "map/2 through a brewer palette" do
    test "its levels take the palette's colours, and a tenth past Set1's nine cannot be drawn" do
      brewer = {:brewer, %{palette: "Set1", direction: 1}}
      nine = palette_scale(brewer, ~w(a b c d e f g h i))
      ten = palette_scale(brewer, ~w(a b c d e f g h i j))

      colors = Palette.discrete(brewer, 9)
      assert Scale.map(nine, ~w(a i)) === [List.first(colors), List.last(colors)]

      error = assert_raise ArgumentError, fn -> Scale.map(ten, ["a"]) end
      assert error.message =~ "9 colours, too few for its 10 values"
      assert error.message =~ "Giggly.Plot.scale_color_manual/2 or scale_fill_manual/2"
    end
  end

  # Golden: ggplot2 4.0.3's `scale_colour_continuous(limits = c(0, 10))` and
  # `scale_colour_gradient2()`'s `layer_data()` in R 4.6.1: a value outside the limits is censored
  # to grey50, and gradient2 places each value by `rescale_mid()`.
  describe "map/2 of a continuous colour scale's limits and midpoint" do
    @default_gradient ["#132B43", "#56B1F7"]

    test "a value's place runs over the limits, and one outside them takes the missing value" do
      scale = gradient_through(@default_gradient, [0, 12], limits: {0.0, 10.0})

      assert Scale.map(scale, [5, 12, 0, -1]) === ["#336A98", "#7F7F7F", "#132B43", "#7F7F7F"]
    end

    test "an end of nil takes the trained range's" do
      scale = gradient_through(@default_gradient, [0, 12], limits: {nil, 24.0})

      assert Scale.map(scale, [12, 24, 30]) === ["#336A98", "#56B1F7", "#7F7F7F"]
    end

    test "a midpoint places each value by its distance from it, the further end at 0 or 1" do
      three = ["#832424", "#FFFFFF", "#3A3A98"]
      centred = gradient_through(three, [-2, 1], rescaler: {:mid, 0.0})
      off_centre = gradient_through(three, [0, 10], rescaler: {:mid, 4.0})

      assert {Scale.map(centred, [-2, 0, 1]), Scale.map(off_centre, [0, 5, 10])} ===
               {["#832424", "#FFFFFF", "#A197CC"], ["#B26D65", "#E0DBEE", "#3A3A98"]}
    end

    test "a scale of missing values alone maps them all to the missing value" do
      scale = gradient_through(@default_gradient, [nil])

      assert Scale.map(scale, [nil, :nan]) === ["#7F7F7F", "#7F7F7F"]
    end
  end

  # Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for `size = hp` on mtcars, whose
  # horsepower runs from 52 to 335, through `scale_size_continuous()`, `scale_size_area()`,
  # `scale_radius()` and `scale_size(range = c(0, 10))`, and for a discrete size of seven levels
  # through `scale_size_discrete()`, R's own figures to the last digit.
  describe "map/2 of a size scale" do
    @horsepower [110, 93, 175, 105]

    test "a continuous size is its place's square root rescaled onto 1 to 6, so its area grows" do
      default =
        :continuous
        |> Scale.new(:size)
        |> size_scale()

      wide = size_scale(%Scale.Continuous{palette: {:area, {0.0, 10.0}}, guide: :legend})

      assert {Scale.map(default, @horsepower), Scale.map(wide, @horsepower)} ===
               {[3.2635536025596519, 2.9031311376803437, 4.2963198239287159, 3.1637880669295164],
                [4.5271072051193038, 3.8062622753606878, 6.5926396478574318, 4.3275761338590328]}
    end

    test "a size by radius is its place rescaled onto 1 to 6" do
      scale = size_scale(%Scale.Continuous{palette: {:rescale, {1.0, 6.0}}, guide: :legend})

      assert Scale.map(scale, @horsepower) ===
               [2.0247349823321557, 1.7243816254416962, 3.1731448763250882, 1.9363957597173145]
    end

    test "a size by area from 0 is the square root of its share of the high end, times 6" do
      scale = area_scale([52, 335])

      assert Scale.map(scale, @horsepower) ===
               [3.438152923066113, 3.1613335557555877, 4.3365850792131049, 3.3591043582407853]
    end

    test "a size by area from 0 censors outside its limits, and takes its missing value's size" do
      values = [1, 2, nil, 10]
      wide = area_scale(values, limits: {0.0, 20.0})
      narrow = area_scale(values, limits: {2.0, 5.0})
      missing = area_scale(values, na_value: 2.0)

      assert {Scale.map(wide, values), Scale.map(narrow, values), Scale.map(missing, values)} ===
               {[1.3416407864998738, 1.8973665961010275, nil, 4.2426406871192857],
                [nil, 3.7947331922020551, nil, nil],
                [1.8973665961010275, 2.6832815729997477, 2.0, 6.0]}
    end

    # R gives 0 / 0, NaN, which maps to NA, and -1 / 0, minus infinity, a size R's legend cannot
    # draw ("non-finite location and/or size for viewport").
    test "a size by area from 0 whose high end is 0 drops 0 and refuses a value below it" do
      zeros = area_scale([0, 0])
      below = area_scale([-1, 0])

      assert Scale.map(zeros, [0, 0.0]) === [nil, nil]

      error = assert_raise ArgumentError, fn -> Scale.map(below, [-1]) end
      assert error.message =~ "cannot place -1 when that end is 0"
    end

    test "a discrete size spreads its levels' areas evenly from 2 to 6, or over its range" do
      levels = ~w(a b c d e f g)

      default =
        :discrete
        |> Scale.new(:size)
        |> Scale.train(levels, :none)

      narrow = Scale.train(%Scale.Discrete{palette: {:area_sequence, {1.0, 3.0}}}, levels, :none)

      assert {Scale.map(default, levels), Scale.map(narrow, levels)} ===
               {[
                  2.0,
                  3.0550504633038931,
                  3.8297084310253524,
                  4.4721359549995796,
                  5.0332229568471663,
                  5.5377492419453826,
                  6.0
                ],
                [
                  1.0,
                  1.5275252316519465,
                  1.9148542155126762,
                  2.2360679774997898,
                  2.5166114784235831,
                  2.7688746209726913,
                  3.0
                ]}
    end

    test "a size scale records ggplot2's default sizes and a legend, untrained, its missing value nil" do
      assert {Scale.new(:continuous, :size), Scale.new(:discrete, :size)} ===
               {%Scale.Continuous{palette: {:area, {1.0, 6.0}}, guide: :legend},
                %Scale.Discrete{palette: {:area_sequence, {2.0, 6.0}}, guide: :legend}}
    end
  end

  # Golden: scales 1.4.0's `pal_shape()` in R 4.6.1, `c(16, 17, 15, 3, 7, 8)` solid and `c(1, 2, 0,
  # 3, 7, 8)` open, each number turned into its name by the table points are drawn from; and
  # ggplot2 4.0.3's `layer_data()` under `scale_shape()` over mpg's seven classes, where the
  # palette warns and leaves `suv` unshaped.
  describe "map/2 of a shape scale" do
    test "a discrete shape gives its levels R's six shapes in order, solid or open, nil none" do
      levels = ~w(a b c d e f)

      by_number = fn numbers ->
        Enum.map(numbers, fn number -> Enum.at(Geom.Point.shapes(), number) end)
      end

      solid =
        :discrete
        |> Scale.new(:shape)
        |> Scale.train(levels, :none)

      open = Scale.train(%Scale.Discrete{palette: {:shape, :open}}, levels, :none)

      assert {Scale.map(solid, [nil | levels]), Scale.map(open, levels)} ===
               {[nil | by_number.([16, 17, 15, 3, 7, 8])], by_number.([1, 2, 0, 3, 7, 8])}
    end

    test "a seventh level cannot be drawn, and the scale that takes more is named" do
      scale =
        :discrete
        |> Scale.new(:shape)
        |> Scale.train(~w(a b c d e f g), :none)

      error = assert_raise ArgumentError, fn -> Scale.map(scale, ["a"]) end

      assert error.message =~ "6 shapes, too few for its 7 values"
      assert error.message =~ "Giggly.Plot.scale_shape_manual/2"
    end

    test "a shape scale is discrete alone, records R's solid shapes and a legend, its missing value nil" do
      assert {Scale.new(:discrete, :shape), Scale.discrete_only?(:shape)} ===
               {%Scale.Discrete{palette: {:shape, :solid}, guide: :legend}, true}
    end

    test "only shape and line type scales are discrete alone" do
      assert Enum.filter(Scale.non_position_aesthetics(), &Scale.discrete_only?/1) === [
               :linetype,
               :shape
             ]
    end
  end

  # A discrete line type takes `Scales.Palette`'s line types, which its tests pin to R's
  # `pal_linetype()`. Golden: ggplot2 4.0.3's `layer_data()` in R 4.6.1 for a line width mapped
  # from 2, 4.5, 3 and 7, and from three levels.
  describe "map/2 of a line type or line width scale" do
    test "a discrete line type gives its levels the palette's 13 line types in order, nil none" do
      levels = ~w(a b c d e f g h i j k l m)

      scale =
        :discrete
        |> Scale.new(:linetype)
        |> Scale.train(levels, :none)

      assert Scale.map(scale, [nil | levels]) === [nil | Palette.discrete(:linetype, 13)]
    end

    test "a fourteenth level cannot be drawn, and the scale that takes more is named" do
      scale =
        :discrete
        |> Scale.new(:linetype)
        |> Scale.train(~w(a b c d e f g h i j k l m n), :none)

      error = assert_raise ArgumentError, fn -> Scale.map(scale, ["a"]) end

      assert error.message =~ "13 line types, too few for its 14 values"
      assert error.message =~ "Giggly.Plot.scale_linetype_manual/2"
    end

    test "a line width is its place rescaled onto 1 to 6, or a level's spread from 2 to 6, nil none" do
      continuous =
        :continuous
        |> Scale.new(:linewidth)
        |> Scale.train([2, 4.5, 3, 7], :none)

      discrete =
        :discrete
        |> Scale.new(:linewidth)
        |> Scale.train(["b", "a", nil, "c"], :none)

      assert {Scale.map(continuous, [2, 4.5, 3, 7, nil]),
              Scale.map(discrete, ["b", "a", nil, "c"])} ===
               {[1.0, 3.5, 2.0, 6.0, nil], [4.0, 2.0, nil, 6.0]}
    end
  end

  # Golden: ggplot2 4.0.3's colour bar in R 4.6.1 over `scale_colour_continuous(limits = c(0,
  # 40))` on mpg's city mileage, 9 to 35: `extract_decor()` samples the limits, and
  # `extract_params()` places the breaks over them, a midpoint left out of both.
  describe "samples/2 and places/2 over a scale's limits" do
    test "the colour bar samples and places over the limits, whatever the midpoint" do
      scale =
        gradient_through(["#832424", "#FFFFFF", "#3A3A98"], [9, 35],
          limits: {0.0, 40.0},
          rescaler: {:mid, 20.0}
        )

      assert {Scale.samples(scale, 5), Scale.places(scale, [10.0, 20.0])} ===
               {[0.0, 10.0, 20.0, 30.0, 40.0], [0.25, 0.5]}
    end
  end

  # Golden: ggplot2 4.0.3's `get_guide_data()` in R 4.6.1: a legend's keys are the scale's breaks
  # among its limits, in the order given, labelled as given; `breaks = NULL` draws no guide.
  describe "legend_breaks/1 from a scale's options" do
    test "a continuous scale's breaks are those given inside its limits, labelled as given" do
      scale =
        gradient_through(["#132B43", "#56B1F7"], [9, 35],
          limits: {10.0, 30.0},
          breaks: [5.0, 10.0, 20.0, 30.0],
          labels: ["five", "ten", "twenty", "thirty"]
        )

      assert Scale.legend_breaks(scale) === [{10.0, "ten"}, {20.0, "twenty"}, {30.0, "thirty"}]
    end

    test "a continuous scale's limits beyond the data reach its legend's breaks" do
      scale = gradient_through(["#132B43", "#56B1F7"], [9, 35], limits: {0.0, 40.0})

      assert Scale.legend_breaks(scale) ===
               [{0.0, "0"}, {10.0, "10"}, {20.0, "20"}, {30.0, "30"}, {40.0, "40"}]
    end

    test "breaks of :none give no legend, and labels of :none keys with no labels" do
      none = gradient_through(["#132B43", "#56B1F7"], [9, 35], breaks: :none)
      unlabelled = palette_scale(hue(15.0, 375.0), ["a", "b"], labels: :none)

      assert {Scale.legend_breaks(none), Scale.legend_breaks(unlabelled)} ===
               {[], [{"a", :none}, {"b", :none}]}
    end

    test "a discrete scale's are its breaks among its limits, in the order given" do
      scale = palette_scale(hue(15.0, 375.0), ["4", "6", "8"], breaks: ["8", "5", "4"])

      assert Scale.legend_breaks(scale) === [{"8", "8"}, {"4", "4"}]
    end

    test "a discrete legend's labels go by place, by value, or from a function" do
      levels = ["4", "6", "8"]

      by_place =
        palette_scale(hue(15.0, 375.0), levels, breaks: ["8", "4"], labels: ["eight", "four"])

      by_value = palette_scale(hue(15.0, 375.0), levels, labels: %{"6" => "six"})

      by_function =
        palette_scale(hue(15.0, 375.0), levels,
          labels: fn values -> Enum.map(values, fn value -> value <> "!" end) end
        )

      assert {Scale.legend_breaks(by_place), Scale.legend_breaks(by_value),
              Scale.legend_breaks(by_function)} ===
               {[{"8", "eight"}, {"4", "four"}], [{"4", "4"}, {"6", "six"}, {"8", "8"}],
                [{"4", "4!"}, {"6", "6!"}, {"8", "8!"}]}
    end

    test "a break names the level equal to it, and the legend shows the level as held" do
      scale = palette_scale(hue(15.0, 375.0), [4.0, 6.0], breaks: [6])

      assert Scale.legend_breaks(scale) === [{6.0, "6"}]
    end
  end

  # A binned scale with `options` trained once on `values`.
  defp binned(values, options \\ []) do
    Scale.Binned
    |> struct!(options)
    |> Scale.train(values, :none)
  end

  defp break_values(scale) do
    scale
    |> Scale.legend_breaks()
    |> Enum.map(fn {value, _label} -> value end)
  end

  # Golden: ggplot2 4.0.3's `scale_colour_steps()`, `_steps2()` and `_fermenter()` in R 4.6.1,
  # each scale's `get_breaks()` and `get_limits()` once built and its `layer_data()` colours, R's
  # own figures, but where Giggly leaves given breaks outside the limits out and colours no
  # missing value.
  describe "a binned scale" do
    @blues {:binned, {:brewer, %{palette: "Blues", direction: -1}}}

    test "with no limits given, they widen so the end bins are as wide as their neighbours" do
      hp = binned([52, 150, 335])
      tens = binned([0, 3, 10])

      assert {break_values(hp), Scale.Binned.limits(hp), Scale.map(hp, [52, 150, 335])} ===
               {[100.0, 150.0, 200.0, 250.0, 300.0], {50.0, 350.0},
                ["#183550", "#22496C", "#50A5E7"]}

      assert {break_values(tens), Scale.Binned.limits(tens), Scale.map(tens, [0, 3, 10])} ===
               {[2.5, 5.0, 7.5], {0.0, 10.0}, ["#1B3A57", "#2A5A82", "#4D9FDE"]}
    end

    test "its defaults are scale_colour_binned()'s, and training on no values keeps them" do
      untrained = Scale.train(%Scale.Binned{}, [], :none)

      assert Map.from_struct(untrained) === %{
               range: :none,
               palette: {:gradient, ["#132B43", "#56B1F7"]},
               rescaler: :rescale,
               na_value: "#7F7F7F",
               guide: :colorsteps,
               name: :default,
               limits: {nil, nil},
               breaks: :default,
               labels: :default,
               n_breaks: 5,
               nice_breaks: true,
               right: true,
               show_limits: false
             }
    end

    # R's `scale_colour_binned(n.breaks = n)` on 52 to 335: three nice breaks wanted give four,
    # ten give ten 30 apart, and two give one inside the range, the limits then that break less
    # and plus its distance to the further end, the low end's there and the high end's on 280 to
    # 560; on 0 to 1, two give its ends, so the range is not widened and its ends are its
    # breaks.
    test "n_breaks nice breaks are wanted, the limits widened on those the count gives" do
      three = binned([52, 150, 335], n_breaks: 3)
      ten = binned([52, 150, 335], n_breaks: 10)
      one_inside = binned([52, 150, 335], n_breaks: 2)
      near_low = binned([280, 560], n_breaks: 2)
      none_inside = binned([0, 0.5, 1], n_breaks: 2)

      assert {break_values(three), Scale.Binned.limits(three), Scale.map(three, [52, 150, 335])} ===
               {[100.0, 200.0, 300.0], {0.0, 400.0}, ["#1B3A57", "#2A5A82", "#4D9FDE"]}

      assert {break_values(ten), Scale.Binned.limits(ten)} ===
               {[60.0, 90.0, 120.0, 150.0, 180.0, 210.0, 240.0, 270.0, 300.0, 330.0],
                {30.0, 360.0}}

      assert {break_values(one_inside), Scale.Binned.limits(one_inside),
              Scale.map(one_inside, [52, 335])} ===
               {[300.0], {52.0, 548.0}, ["#22496C", "#448DC6"]}

      assert {break_values(near_low), Scale.Binned.limits(near_low)} === {[300.0], {40.0, 560.0}}

      assert {Scale.legend_breaks(none_inside), Scale.Binned.limits(none_inside),
              Scale.map(none_inside, [0, 0.5, 1])} ===
               {[{0.0, "0"}, {1.0, "1"}], {0.0, 1.0}, ["#336A98", "#336A98", "#336A98"]}
    end

    # R's `scale_colour_binned(nice.breaks = FALSE)` on 52 to 335: R's `seq()` less its ends, the
    # limits widened by the step on either side, which R's arithmetic leaves a hair below 52 for
    # two breaks; one break is the middle, the limits about it the range; given limits are kept.
    test "without nice breaks, n_breaks are spaced evenly between the ends of the limits" do
      five = binned([52, 150, 335], nice_breaks: false)
      two = binned([52, 150, 335], nice_breaks: false, n_breaks: 2)
      one = binned([52, 150, 335], nice_breaks: false, n_breaks: 1)
      limited = binned([52, 150, 335], nice_breaks: false, limits: {0, 400})

      assert {break_values(five), Scale.Binned.limits(five), Scale.map(five, [52, 150, 335])} ===
               {[
                  99.16666666666666,
                  146.33333333333331,
                  193.5,
                  240.66666666666666,
                  287.8333333333333
                ], {52.0, 335.0}, ["#183550", "#2D5F89", "#50A5E7"]}

      assert {break_values(two), Scale.Binned.limits(two)} ===
               {[146.33333333333331, 240.66666666666666], {51.99999999999997, 335.0}}

      assert {break_values(one), Scale.Binned.limits(one), Scale.map(one, [52, 230, 335])} ===
               {[193.5], {52.0, 335.0}, ["#22496C", "#448DC6", "#448DC6"]}

      assert {break_values(limited), Scale.Binned.limits(limited)} ===
               {[
                  66.66666666666667,
                  133.33333333333334,
                  200.0,
                  266.6666666666667,
                  333.33333333333337
                ], {0.0, 400.0}}
    end

    # R's guide data for `scale_colour_binned(show.limits = TRUE)`: the limits labelled by the
    # scale's labels, written together, by a function, or not at all; beside a list of labels R
    # ignores `show.limits` with a warning.
    test "shown limits are the limits labelled as the scale labels them, and none unless shown" do
      shown = fn options ->
        [52, 150, 335]
        |> binned(options)
        |> Scale.shown_limits()
      end

      written = fn values -> Enum.map(values, fn value -> "<#{round(value)}>" end) end

      assert {shown.([]), shown.(show_limits: true), shown.(show_limits: true, labels: written),
              shown.(show_limits: true, labels: :none),
              shown.(show_limits: true, nice_breaks: false, n_breaks: 2)} ===
               {[], [{50.0, "50"}, {350.0, "350"}], [{50.0, "<50>"}, {350.0, "<350>"}],
                [{50.0, :none}, {350.0, :none}], [{51.99999999999997, "52"}, {335.0, "335"}]}

      error =
        assert_raise ArgumentError, fn ->
          shown.(show_limits: true, breaks: [100, 200], labels: ["a", "b"])
        end

      assert error.message ==
               "a binned scale shows its limits beside labels written by default or by a " <>
                 ~s(function, and its labels are a list, which labels its breaks alone, got: ["a", "b"])
    end

    test "edges far closer than 1 apart are bins of their own" do
      scale = binned([0.0, 4.0e-17])

      assert Scale.map(scale, [0.0, 1.0e-17, 4.0e-17]) === ["#1B3A57", "#1B3A57", "#4D9FDE"]
    end

    test "a range of one value widens 0.05 either side, its ends its breaks" do
      scale = binned([5, 5])

      assert {Scale.legend_breaks(scale), Scale.Binned.limits(scale), Scale.map(scale, [5])} ===
               {[{4.95, "4.95"}, {5.05, "5.05"}], {4.95, 5.05}, ["#336A98"]}
    end

    test "given limits are not widened, keep their breaks at either end, and squish values in" do
      both = binned([0, 5, 10], limits: {8, 2})
      high = binned([52, 150, 335], limits: {nil, 400})

      assert {break_values(both), Scale.Binned.limits(both), Scale.map(both, [0, 5, 10])} ===
               {[2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0], {2.0, 8.0},
                ["#183550", "#2D5F89", "#50A5E7"]}

      assert {break_values(high), Scale.Binned.limits(high), Scale.map(high, [52, 150, 335])} ===
               {[100.0, 200.0, 300.0, 400.0], {52.0, 400.0}, ["#17334E", "#244D71", "#4C9CDB"]}
    end

    test "a value on a break is in the bin below it, or with right: false above, the top in the last" do
      below = binned([52, 200, 335])
      above = binned([52, 200, 335], right: false)
      top = binned([52, 200, 335, 400], right: false)

      assert {Scale.map(below, [200]), Scale.map(above, [200]), Scale.map(top, [335, 400])} ===
               {["#2D5F89"], ["#3875A7"], ["#4D9FDE", "#4D9FDE"]}
    end

    test "given breaks are cut at inside the limits, those outside left out with their labels" do
      inside = binned([52, 150, 335], breaks: [100, 200])

      beyond =
        binned([52, 150, 335], breaks: [0, 100, 200, 300, 400, 500], labels: ~w(a b c d e f))

      assert Scale.map(inside, [52, 150, 335]) === ["#183551", "#29567D", "#458EC9"]

      assert {Scale.legend_breaks(beyond), Scale.Binned.limits(beyond),
              Scale.map(beyond, [52, 150, 335])} ===
               {[{100.0, "b"}, {200.0, "c"}, {300.0, "d"}], {52.0, 335.0},
                ["#183551", "#29567D", "#51A8EB"]}
    end

    test "no breaks inside the limits make one bin, which colours every value but a missing one" do
      none = binned([52, 150, 335], breaks: :none)
      outside = binned([52, 150, 335], breaks: [1000])
      single = binned([5, 5], breaks: :none)
      single_left = binned([5, 5], breaks: :none, right: false)

      assert {Scale.legend_breaks(none), Scale.map(none, [52, 335]), Scale.map(outside, [150])} ===
               {[], ["#336A98", "#336A98"], ["#336A98"]}

      assert {Scale.map(single, [5, nil]), Scale.map(single_left, [5])} ===
               {["#336A98", "#7F7F7F"], ["#336A98"]}
    end

    test "a missing value or one not finite takes the missing value, every one before limits" do
      scale = binned([52, 335])
      untrained = binned([nil, nil])

      assert Scale.map(scale, [nil, :infinity, :neg_infinity, :nan, 335]) ===
               ["#7F7F7F", "#7F7F7F", "#7F7F7F", "#7F7F7F", "#50A5E7"]

      assert {Scale.legend_breaks(untrained), Scale.Binned.limits(untrained),
              Scale.map(untrained, [nil])} === {[], :none, ["#7F7F7F"]}
    end

    test "a midpoint places the values and the breaks by their distance from it" do
      steps2 = {:gradient, ["#832424", "#FFFFFF", "#3A3A98"]}
      centred = binned([-3, 7], palette: steps2, rescaler: {:mid, 0})
      off_centre = binned([-3, 7], palette: steps2, rescaler: {:mid, 2})

      assert {Scale.map(centred, [-3, -1, 0, 2, 7]), Scale.map(off_centre, [-3, -1, 0, 2, 7])} ===
               {["#C89089", "#EED9D6", "#EED9D6", "#E0DBEE", "#6057A9"],
                ["#9D4C46", "#CC9891", "#CC9891", "#F4E7E5", "#8C82C1"]}
    end

    test "a discrete palette gives its colours for the bins' count, and too few raise" do
      scale = binned([52, 150, 335], palette: @blues)
      twelve = binned([0, 13], palette: @blues, breaks: Enum.to_list(1..12))

      assert Scale.map(scale, [52, 150, 335]) === ["#08519C", "#3182BD", "#EFF3FF"]

      error = assert_raise ArgumentError, fn -> Scale.map(twelve, [0]) end
      assert error.message =~ "9 colours, too few for its 13 bins"
    end

    test "a negative zero and a zero are one edge, as R counts them" do
      palette = {:brewer, %{palette: "Blues", direction: 1}}
      scale = binned([-0.0, 10.0], palette: {:binned, palette}, breaks: [0.0, 5.0])

      [_first, second] = Palette.discrete(palette, 2)

      assert Scale.map(scale, [10.0]) === [second]
    end

    test "a bin whose middle a continuous palette has no colour for takes the missing value" do
      palette = {:gradient, ["#132B43", "#56B1F7"], [0.5, 1.0]}
      scale = binned([52, 150, 335], palette: palette)

      assert Scale.map(scale, [52, 150, 335]) ===
               ["#7F7F7F", "#7F7F7F" | Palette.continuous(palette, [275 / 300])]
    end

    test "its labels are written plainly, given in a list, from a function, or left out" do
      listed = binned([52, 335], labels: ~w(a b c d e))
      short = binned([52, 335], labels: ~w(a b c))
      none = binned([0, 10], labels: :none)

      written =
        binned([0, 10],
          labels: fn breaks -> Enum.map(breaks, fn break -> "#{break}!" end) end
        )

      plain = binned([0, 10])

      assert {Scale.legend_breaks(plain), Scale.legend_breaks(none), Scale.legend_breaks(written)} ===
               {[{2.5, "2.5"}, {5.0, "5.0"}, {7.5, "7.5"}],
                [{2.5, :none}, {5.0, :none}, {7.5, :none}],
                [{2.5, "2.5!"}, {5.0, "5.0!"}, {7.5, "7.5!"}]}

      labels =
        listed
        |> Scale.legend_breaks()
        |> Enum.map(fn {_value, label} -> label end)

      assert labels === ~w(a b c d e)

      error = assert_raise ArgumentError, fn -> Scale.legend_breaks(short) end
      assert error.message =~ "3 labels must be one for each of its 5 breaks"
      assert error.message =~ ~s(got: ["a", "b", "c"])
    end

    test "it is its own kind, not discrete, and takes numbers alone" do
      scale = %Scale.Binned{}

      assert {Scale.kind_of(scale), Scale.discrete?(scale),
              Enum.map([:continuous, :discrete, :date], fn kind -> Scale.takes?(scale, kind) end)} ===
               {:binned, false, [true, false, false]}
    end
  end

  # Golden: ggplot2 4.0.3's `get_guide_data()` and the guide's params in R 4.6.1, mtcars' `colour
  # = hp` (52 to 335) read back by `guide_coloursteps()`, made by session 27474d8e's scratchpad
  # `r/steps.R`, `r/cont.R` and `r/pass.R`: each key's `.value` and each bin's `min`, `max` and
  # `colour`.
  describe "steps/2" do
    @gradient ["#132B43", "#56B1F7"]

    # What colour steps draw of `scale`, its legend's breaks handed in.
    defp steps(scale), do: Scale.steps(scale, break_values(scale))

    defp step_places(scale) do
      {places, _bins} = steps(scale)
      places
    end

    defp step_bins(scale) do
      {_places, bins} = steps(scale)
      bins
    end

    test "the bar is cut at the limits and breaks into bins of equal length, each its middle's colour" do
      binned = binned([52, 150, 335])
      continuous = gradient_through(@gradient, [52, 150, 335])

      assert {steps(binned), step_bins(continuous)} ===
               {{[
                   0.16666666666666666,
                   0.3333333333333333,
                   0.5,
                   0.6666666666666666,
                   0.8333333333333334
                 ],
                 [
                   {0.0, 0.16666666666666666, "#183550"},
                   {0.16666666666666666, 0.3333333333333333, "#22496C"},
                   {0.3333333333333333, 0.5, "#2D5F89"},
                   {0.5, 0.6666666666666666, "#3875A7"},
                   {0.6666666666666666, 0.8333333333333334, "#448DC6"},
                   {0.8333333333333334, 1.0, "#50A5E7"}
                 ]},
                [
                  {0.0, 0.16666666666666666, "#183551"},
                  {0.16666666666666666, 0.3333333333333333, "#234A6D"},
                  {0.3333333333333333, 0.5, "#2E618C"},
                  {0.5, 0.6666666666666666, "#3A79AC"},
                  {0.6666666666666666, 0.8333333333333334, "#4792CE"},
                  {0.8333333333333334, 1.0, "#51A8EB"}
                ]}
    end

    test "a continuous scale's default breaks on a limit are left out, a binned scale's kept" do
      continuous = gradient_through(@gradient, [52, 150, 335], limits: {100.0, 300.0})
      binned = binned([52, 150, 335], limits: {50, 350})

      assert {steps(continuous), step_places(binned)} ===
               {{[nil, 0.25, 0.5, 0.75, nil],
                 [
                   {0.0, 0.25, "#1B3A57"},
                   {0.25, 0.5, "#2A5A82"},
                   {0.5, 0.75, "#3B7BAF"},
                   {0.75, 1.0, "#4D9FDE"}
                 ]},
                [
                  0.0,
                  0.16666666666666666,
                  0.3333333333333333,
                  0.5,
                  0.6666666666666666,
                  0.8333333333333334,
                  1.0
                ]}
    end

    test "a first break given on a limit moves every break one step down the bar" do
      binned = binned([52, 150, 335], limits: {100, 350}, breaks: [100, 200, 300])

      continuous =
        gradient_through(@gradient, [52, 150, 335],
          limits: {100.0, 300.0},
          breaks: [100.0, 200.0, 300.0]
        )

      assert {step_places(binned), step_places(continuous)} ===
               {[0.0, 0.3333333333333333, 0.6666666666666666], [0.0, 0.5, 1.0]}
    end

    test "a first break given on the high limit moves every break one step down too" do
      binned = binned([52, 150, 335], limits: {100, 300}, breaks: [300, 200])

      continuous =
        gradient_through(@gradient, [52, 150, 335],
          limits: {100.0, 300.0},
          breaks: [300.0, 200.0]
        )

      assert {steps(binned), step_places(continuous)} ===
               {{[0.0, 0.5], [{0.0, 0.5, "#22496C"}, {0.5, 1.0, "#448DC6"}]}, [0.0, 0.5]}
    end

    test "edges far closer than 1 apart are bins of their own" do
      scale = binned([0.0, 4.0e-17])

      assert steps(scale) ===
               {[0.25, 0.5, 0.75],
                [
                  {0.0, 0.25, "#1B3A57"},
                  {0.25, 0.5, "#2A5A82"},
                  {0.5, 0.75, "#3B7BAF"},
                  {0.75, 1.0, "#4D9FDE"}
                ]}
    end

    # R counts the breaks in the order given, so each label lands on another break's edge.
    test "breaks given out of order are placed in the order given, as R places them" do
      binned = binned([52, 150, 335], breaks: [300, 100, 200])
      continuous = gradient_through(@gradient, [52, 150, 335], breaks: [300.0, 100.0, 200.0])

      assert {steps(binned), step_places(continuous)} ===
               {{[0.25, 0.5, 0.75],
                 [
                   {0.0, 0.25, "#183551"},
                   {0.25, 0.5, "#29567D"},
                   {0.5, 0.75, "#4086BD"},
                   {0.75, 1.0, "#51A8EB"}
                 ]}, [0.25, 0.5, 0.75]}
    end

    # R's step down reads the first break given, so one outside the limits stops it, and the last
    # break is counted past the bar's end.
    test "a first break given outside the limits keeps the rest from stepping down" do
      binned = binned([52, 150, 335], limits: {52, 335}, breaks: [40, 52, 200, 335])

      continuous =
        gradient_through(@gradient, [52, 150, 335], breaks: [40.0, 52.0, 200.0, 335.0])

      assert {steps(binned), step_places(continuous)} ===
               {{[0.5, 1.0, nil], [{0.0, 0.5, "#234B6E"}, {0.5, 1.0, "#458EC9"}]},
                [0.5, 1.0, nil]}
    end

    test "a single value's binned bar is one bin between its two breaks, its continuous bar none" do
      binned = binned([5])
      continuous = gradient_through(@gradient, [5])

      assert {steps(binned), steps(continuous)} ===
               {{[0.0, 1.0], [{0.0, 1.0, "#336A98"}]}, {[nil], []}}
    end
  end

  describe "level_labels/1" do
    # Golden: R 4.6.1's `levels(factor(...))` of the same values: `4`, `0.5`, `TRUE`, `1e+05`; a
    # missing level is labelled `NA`, as ggplot2's legend labels it.
    test "a level is written as R's as.character() writes it, and a missing one as NA" do
      assert Scale.level_labels(["manual", :auto, true, 4.0, 0.5, 1.0e5, nil]) ===
               ["manual", "auto", "TRUE", "4", "0.5", "1e+05", "NA"]
    end
  end

  # An axis of `values` on a continuous scale through `transform`: its extent, its breaks and its
  # minor breaks, as the assembly finds them.
  defp axis(transform, values, options) do
    scale = struct!(Scale.Continuous, [{:transform, transform} | options])
    trained = Scale.train(scale, Scale.transform(scale, values), :none)
    extent = Scale.dimension(trained)
    breaks = Scale.breaks(trained, extent)
    {extent, breaks, Scale.minor_breaks(trained, breaks, extent)}
  end

  defp column(dataset, name), do: Keyword.fetch!(dataset, name)

  # A wall-clock time in New York, as R's as.POSIXct(..., tz = "America/New_York") reads it.
  defp new_york(wall), do: DateTime.from_naive!(wall, "America/New_York", Tz.TimeZoneDatabase)

  # The labels of a trained scale's breaks on `extent`, in order.
  defp labels(scale, extent) do
    scale
    |> Scale.breaks(extent)
    |> Enum.map(fn {_position, label} -> label end)
  end

  # Golden: every axis below is R's own, from R 4.6.1 with ggplot2 4.0.3 and scales 1.4.0 (the
  # image `giggly-r:ggplot2-4.0.3`, and its `-hms` sibling for times): `ggplot_build()`'s panel
  # params for the plot in the comment above each, their continuous range, breaks inside it,
  # labels, and minor breaks less the breaks. The transformations' own breaks and labels are
  # `Scales.Transform`'s, which its tests pin; these are a scale's domain and options through
  # them.
  describe "a transformed scale's options" do
    test "finds its breaks from 1e-100 up, R's domain" do
      # data.frame(y = c(1e-120, 1e-80)) with scale_y_log10(): the extent from -122 is squished
      # to -100 before its breaks are found
      {extent, breaks, _minor} = axis(:log10, [1.0e-120, 1.0e-80], [])

      assert {extent, Enum.map(breaks, fn {position, _label} -> position end)} ==
               {{-122.0, -78.0}, [-100.0, -95.0, -90.0, -85.0, -80.0]}
    end

    test "takes limits, breaks and minor breaks in data units" do
      # hwy with scale_y_log10(limits = c(10, 100)); y = c(1, 10, 100) with breaks = c(0, 10, 100),
      # 0 outside the domain, and minor_breaks = c(5, 50)
      assert axis(:log10, column(Datasets.mpg(), :hwy), limits: {10, 100}) ==
               {{0.95, 2.05}, [{1.0, "10"}, {1.4771212547196624, "30"}, {2.0, "100"}],
                [1.2385606273598313, 1.7385606273598313]}

      {_extent, breaks, minor} =
        axis(:log10, [1, 10, 100], breaks: [0, 10, 100], minor_breaks: [5, 50])

      assert breaks == [{1.0, "10"}, {2.0, "100"}]
      assert minor == [0.69897000433601886, 1.6989700043360187]
    end

    test "sorts its limits once negated, and leaves an end to the data unsorted" do
      # ggplot(mtcars, aes(mpg, wt)) + geom_point() + xlim(20, 15); data.frame(y = c(1, 10, 100))
      # with scale_y_reverse(limits = c(50, NA)), whose 100 is censored
      assert axis(:reverse, column(Datasets.mtcars(), :mpg), limits: {20, 15}) ==
               {{-20.25, -14.75},
                [
                  {-15.0, "15"},
                  {-16.0, "16"},
                  {-17.0, "17"},
                  {-18.0, "18"},
                  {-19.0, "19"},
                  {-20.0, "20"}
                ], [-15.5, -16.5, -17.5, -18.5, -19.5]}

      scale = %Scale.Continuous{transform: :reverse, limits: {50, nil}}
      trained = Scale.train(scale, Scale.transform(scale, [1, 10, 100]), :none)
      extent = Scale.dimension(trained)

      assert extent == {-52.45, 1.4500000000000002}
      assert labels(trained, extent) == ~w(0 10 20 30 40 50)
      assert Scale.map(trained, Scale.transform(scale, [1, 10, 100])) == [-1, -10, nil]
    end

    # scale_x_time(date_breaks = "1 hour") over 22:12:00 and 22:48:00: no break falls inside, so
    # R draws no break, label or minor grid line
    test "a width laying no break inside the axis draws none" do
      assert axis(:time, [~T[22:12:00], ~T[22:48:00]], breaks: {:width, [hour: 1]}) ===
               {{79_812.0, 82_188.0}, [], []}
    end

    # scale_x_time(date_breaks = "6 hours", date_labels = "%H:%M") over 00:00:00 and 23:59:59:
    # R's format() wraps the last, 24:00:00, round midnight
    test "a width's breaks in a format, wrapped round midnight" do
      assert axis(:time, [~T[00:00:00], ~T[23:59:59]],
               breaks: {:width, [hour: 6]},
               labels: {:format, "%H:%M"}
             ) ===
               {{-4319.95, 90_718.95},
                [
                  {0.0, "00:00"},
                  {21_600.0, "06:00"},
                  {43_200.0, "12:00"},
                  {64_800.0, "18:00"},
                  {86_400.0, "00:00"}
                ], [10_800.0, 32_400.0, 54_000.0, 75_600.0]}
    end

    # scale_x_time(date_breaks = "10 secs", date_minor_breaks = "5 secs",
    # expand = expansion(mult = 0.5)) over 00:00:00 and 00:00:30, where R pads " 00:00:00"
    test "a width laid below midnight, and minor breaks every step of another" do
      assert axis(:time, [~T[00:00:00], ~T[00:00:30]],
               breaks: {:width, [second: 10]},
               minor_breaks: {:width, [second: 5]},
               expand: [mult: {0.5, 0.5}, add: {0, 0}]
             ) ===
               {{-15.0, 45.0},
                [
                  {-10.0, "-00:00:10"},
                  {0.0, "00:00:00"},
                  {10.0, "00:00:10"},
                  {20.0, "00:00:20"},
                  {30.0, "00:00:30"},
                  {40.0, "00:00:40"}
                ], [-15.0, -5.0, 5.0, 15.0, 25.0, 35.0, 45.0]}
    end
  end

  describe "a transformed scale's labels and limits" do
    test "a labels function is handed the breaks in data units" do
      # hwy with scale_y_log10(labels = function(b) ...): the function is handed 20, 30 and 40
      scale = %Scale.Continuous{
        transform: :log10,
        labels: fn breaks ->
          Enum.map(breaks, fn data ->
            data
            |> Float.round(9)
            |> inspect()
          end)
        end
      }

      trained = Scale.train(scale, Scale.transform(scale, column(Datasets.mpg(), :hwy)), :none)
      extent = Scale.dimension(trained)

      assert labels(trained, extent) == ["20.0", "30.0", "40.0"]
    end

    test "a labels function under reverse, sqrt and reciprocal is handed breaks in data units" do
      # ggplot(mtcars, aes(wt, mpg)) + geom_point() under scale_x_reverse(labels = f),
      # scale_x_sqrt(labels = f) and scale_x_continuous(transform = "reciprocal", labels = f): f
      # is handed 2, 3, 4 and 5, then their squares' roots squared, then 2 to 6
      handed = fn transform ->
        scale = %Scale.Continuous{
          transform: transform,
          labels: fn breaks -> Enum.map(breaks, &Float.to_string/1) end
        }

        values = Scale.transform(scale, column(Datasets.mtcars(), :wt))
        trained = Scale.train(scale, values, :none)
        labels(trained, Scale.dimension(trained))
      end

      assert Enum.map([:reverse, :sqrt, :reciprocal], handed) == [
               ["2.0", "3.0", "4.0", "5.0"],
               ["2.0000000000000004", "2.9999999999999996", "4.0", "5.000000000000001"],
               ["2.0", "3.0", "4.0", "5.0", "6.0"]
             ]
    end

    test "a labels function on a date axis is handed dates" do
      # scale_x_date(labels = function(dates) ...) is handed Date objects
      scale = %Scale.Continuous{
        transform: :date,
        labels: fn dates -> Enum.map(dates, &Date.to_iso8601/1) end
      }

      trained =
        Scale.train(scale, Scale.transform(scale, [~D[2020-01-01], ~D[2020-01-03]]), :none)

      extent = Scale.dimension(trained)

      assert labels(trained, extent) == ~w(2020-01-01 2020-01-02 2020-01-03)
    end

    test "a labels function on a date-time axis is handed date-times in the scale's zone" do
      # scale_x_datetime(labels = function(b) format(b, "%Y-%m-%d %H:%M %Z")) over 2024-03-09
      # 15:17 and 2024-03-11 04:40 in New York: R hands it the breaks there, across its change
      scale = %Scale.Continuous{
        transform: {:datetime, "America/New_York", Tz.TimeZoneDatabase},
        labels: fn datetimes ->
          Enum.map(datetimes, fn datetime -> Calendar.strftime(datetime, "%Y-%m-%d %H:%M %Z") end)
        end
      }

      values = [new_york(~N[2024-03-09 15:17:00]), new_york(~N[2024-03-11 04:40:00])]
      trained = Scale.train(scale, Scale.transform(scale, values), :none)

      assert labels(trained, Scale.dimension(trained)) ==
               ["2024-03-10 00:00 EST", "2024-03-10 13:00 EDT", "2024-03-11 01:00 EDT"]
    end

    test "a labels function on a date-time axis is handed date-times, to the second" do
      # scale_x_datetime(labels = function(b) ...) is handed POSIXct objects in the scale's zone
      scale = %Scale.Continuous{
        transform: {:datetime, "Etc/UTC", Calendar.UTCOnlyTimeZoneDatabase},
        labels: fn datetimes -> Enum.map(datetimes, &inspect/1) end
      }

      values = [~U[2024-03-09 20:17:00Z], ~U[2024-03-10 08:40:00Z]]
      trained = Scale.train(scale, Scale.transform(scale, values), :none)
      extent = Scale.dimension(trained)

      assert labels(trained, extent) ==
               Enum.map(
                 [
                   ~U[2024-03-09 21:00:00Z],
                   ~U[2024-03-10 00:00:00Z],
                   ~U[2024-03-10 03:00:00Z],
                   ~U[2024-03-10 06:00:00Z],
                   ~U[2024-03-10 09:00:00Z]
                 ],
                 &inspect/1
               )
    end

    test "a labels function on a time axis is handed times of day, wrapped past midnight" do
      # scale_x_time(date_breaks = "6 hours", labels = function(b) ...) over 00:00:00 and 23:59:59:
      # R hands it hms values, the last 24:00:00, which a Time cannot hold
      scale = %Scale.Continuous{
        transform: :time,
        breaks: {:width, [hour: 6]},
        labels: fn times -> Enum.map(times, &inspect/1) end
      }

      trained = Scale.train(scale, Scale.transform(scale, [~T[00:00:00], ~T[23:59:59]]), :none)

      assert labels(trained, Scale.dimension(trained)) ==
               ~w(~T[00:00:00] ~T[06:00:00] ~T[12:00:00] ~T[18:00:00] ~T[00:00:00])
    end

    test "a limit outside the transformation's domain cannot be placed, at either end" do
      # scale_y_log10(limits = c(0, 100)) fails in R: 'from' must be a finite number
      for limits <- [{0, 100}, {100, 0}] do
        scale = %Scale.Continuous{transform: :log10, limits: limits, range: {0.0, 2.0}}

        error = assert_raise ArgumentError, fn -> Scale.dimension(scale) end
        assert error.message =~ inspect(limits)
        assert error.message =~ "log10"
      end
    end

    test "limits are sorted once transformed, so either order names the same axis" do
      # ggplot(mtcars, aes(mpg, wt)) + geom_point() + scale_x_continuous(limits = c(20, 15)):
      # 14.75 to 20.25; under scale_x_reverse(), c(15, 20) and c(20, 15) both -20.25 to -14.75
      mpg = column(Datasets.mtcars(), :mpg)
      {identity_extent, _breaks, _minor} = axis(:identity, mpg, limits: {20, 15})
      {reverse_extent, _breaks, _minor} = axis(:reverse, mpg, limits: {15, 20})

      assert {identity_extent, reverse_extent} == {{14.75, 20.25}, {-20.25, -14.75}}
    end

    test "a labels function's refusal shows the breaks in data units" do
      scale = %Scale.Continuous{transform: :log10, labels: fn _breaks -> ["one"] end}
      trained = Scale.train(scale, Scale.transform(scale, column(Datasets.mpg(), :hwy)), :none)

      error =
        assert_raise ArgumentError, fn -> Scale.breaks(trained, Scale.dimension(trained)) end

      assert error.message =~ "[20.0"
    end
  end
end
