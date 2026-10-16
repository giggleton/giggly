defmodule Giggly.ScaleTest do
  use ExUnit.Case, async: true

  alias Giggly.Scale

  # A new discrete alpha scale trained once on `values`.
  defp discrete_alpha(values) do
    :discrete
    |> Scale.new(:alpha)
    |> Scale.train(values)
  end

  # A new scale of `kind` trained once on `values`.
  defp trained(kind, values) do
    kind
    |> Scale.new()
    |> Scale.train(values)
  end

  describe "kind/1" do
    test "a column's type decides its scale's kind, and a type with no scale yet gets none" do
      dtypes = [:integer, :float, :null, :string, :boolean, :atom, :date, :time, :term]

      assert Enum.map(dtypes, &Scale.kind/1) == [
               :continuous,
               :continuous,
               :continuous,
               :discrete,
               :discrete,
               :discrete,
               :none,
               :none,
               :none
             ]
    end
  end

  describe "train/2" do
    test "a continuous range spans the finite numbers only, across trainings" do
      scale =
        :continuous
        |> Scale.new()
        |> Scale.train([nil, 3, :infinity, 1.5])
        |> Scale.train([2])

      assert scale === %Scale.Continuous{
               range: {1.5, 3},
               transform: :identity,
               palette: :identity
             }
    end

    test "discrete levels are the distinct values sorted, nil last, across trainings" do
      scale =
        :discrete
        |> Scale.new()
        |> Scale.train(["b", nil, "a"])
        |> Scale.train(["c", "a"])

      assert scale === %Scale.Discrete{
               levels: ["a", "b", "c", nil],
               continuous_range: :none,
               palette: :identity
             }
    end

    test "a discrete scale handed positions widens its continuous range, not its levels" do
      scale =
        :discrete
        |> trained(["b", "a"])
        |> Scale.train([1, 2])
        |> Scale.train([0.55, nil, 2.45])

      assert scale === %Scale.Discrete{
               levels: ["a", "b"],
               continuous_range: {0.55, 2.45},
               palette: :identity
             }
    end
  end

  describe "reset/1" do
    test "a continuous scale forgets its range, a discrete one its continuous range alone" do
      continuous = trained(:continuous, [1.0, 3.0])

      discrete =
        :discrete
        |> trained(["b", "a"])
        |> Scale.train([0.55, 2.45])

      assert {Scale.reset(continuous), Scale.reset(discrete)} ===
               {%Scale.Continuous{range: :none, transform: :identity, palette: :identity},
                %Scale.Discrete{levels: ["a", "b"], continuous_range: :none, palette: :identity}}
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
        |> Scale.train([0.55, 7.45])

      wide =
        :discrete
        |> trained(["a", "b", "c"])
        |> Scale.train([0.25, 3.75])

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

  # Golden throughout: R 4.6.1's `scales` 1.4.0 and ggplot2 4.0.3, printed to 17 significant
  # digits: `scales::rescale()`, `seq(0.1, 1, length.out = n)` and the alpha `layer_data()` of the
  # same values. They move only with R's arithmetic, or with ggplot2's default alpha range.
  describe "rescale/3" do
    test "a value moves linearly from one range to another, in R's order of operations" do
      rescaled =
        Enum.map([2, 4, 10, 6, 3.3], fn value -> Scale.rescale(value, {2, 10}, {0, 1}) end)

      assert rescaled === [0.0, 0.25, 1.0, 0.5, 0.16249999999999998]
    end

    test "a range of zero width puts every value at the middle of the other" do
      assert Scale.rescale(5, {5, 5}, {0, 1}) === 0.5
      assert Scale.rescale(5, {5, 5}, {0.1, 1.0}) === 0.55
    end
  end

  describe "map/2 through a palette" do
    test "a continuous alpha is its place in the range rescaled onto 0.1 to 1, a missing one nil" do
      scale =
        :continuous
        |> Scale.new(:alpha)
        |> Scale.train([2, 4, nil, 10, 6])

      assert Scale.map(scale, [2, 4, nil, 10, 6, 3.3, :nan]) ===
               [0.1, 0.325, nil, 1.0, 0.55, 0.24625, nil]
    end

    test "a continuous alpha of one value is the middle of the palette" do
      scale =
        :continuous
        |> Scale.new(:alpha)
        |> Scale.train([7, 7])

      assert Scale.map(scale, [7, 7]) === [0.55, 0.55]
    end

    test "a discrete alpha spreads its present levels evenly from 0.1 to 1, a missing one nil" do
      scale =
        :discrete
        |> Scale.new(:alpha)
        |> Scale.train(["b", "a", nil, "c", "a"])

      assert Scale.map(scale, ["b", "a", nil, "c", "a"]) === [0.55, 0.1, nil, 1.0, 0.1]
    end

    test "the spread is R's seq(), its middle values found by steps from the first" do
      levels = ~w(a b c d e f g)

      scale =
        :discrete
        |> Scale.new(:alpha)
        |> Scale.train(levels)

      assert Scale.map(scale, levels) ===
               [
                 0.1,
                 0.25,
                 0.4,
                 0.54999999999999993,
                 0.69999999999999996,
                 0.84999999999999998,
                 1.0
               ]
    end

    test "one level is the palette's start, two its ends, none at all leave only nil" do
      one = discrete_alpha(["a", "a"])
      two = discrete_alpha(["a", "b"])
      none = discrete_alpha([nil])

      assert {Scale.map(one, ["a"]), Scale.map(two, ["a", "b"]), Scale.map(none, [nil])} ===
               {[0.1], [0.1, 1.0], [nil]}
    end

    test "a position scale's palette is the identity" do
      assert {Scale.new(:continuous).palette, Scale.new(:discrete).palette} ===
               {:identity, :identity}
    end

    test "an alpha scale records ggplot2's default range, untrained, the identity transformation" do
      assert {Scale.new(:continuous, :alpha), Scale.new(:discrete, :alpha)} ===
               {%Scale.Continuous{
                  range: :none,
                  transform: :identity,
                  palette: {:rescale, {0.1, 1.0}}
                },
                %Scale.Discrete{
                  levels: [],
                  continuous_range: :none,
                  palette: {:sequence, {0.1, 1.0}}
                }}
    end
  end
end
