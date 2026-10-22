defmodule Giggly.Stat.Boxplot do
  @moduledoc false

  # The box plot's summary, ggplot2's `stat_boxplot()`: for each group in each panel, in that
  # order, one row describing its box. `lower`, `middle` and `upper` are the quartiles of its y,
  # as R's `quantile()` takes them by default (type 7); a row is an outlier when its y lies more
  # than `coef` times the box's height (the interquartile range) below `lower` or above `upper`,
  # and the box's `outliers` are their y values, in row order, an empty list for none; its
  # whiskers end at `ymin` and `ymax`, the least and the greatest y that is no outlier, or, where
  # the box has outliers, at the hinges should they reach further, as R takes the range of the
  # quartiles and the rest; its notches at `notchlower` and `notchupper`, `middle` less and plus
  # 1.58 times the box's height over the square root of its rows. Its `x` is the middle of its x
  # values' range; its `width` the group's first mapped `width`, or else 0.9 of its x values' range
  # where they are more than one, or else the stat's `width`, or else 0.75 of the layer's x spacing
  # counting from zero (`Giggly.Resolution`); its `relvarwidth` the square root of its rows, which
  # a box as wide as its rows are many is drawn by; and `flipped_aes`. y takes nothing by default,
  # since the box geom draws the columns as they are named. Run it through `Giggly.Stat`.
  #
  # A row missing its x or y, or at an infinite one, is left out, as ggplot2's `remove_missing()`
  # drops it, and a group left with no rows has no box; where the layer maps no x, every row is at
  # 0. The layer's x spacing is read before that, from every row, as ggplot2 reads it.
  #
  # Its orientation, ggplot2's `has_flipped_aes()` for a box plot: `orientation` when it names an
  # axis; else along y, the box drawn across x, where the layer maps y alone, and along x where it
  # maps x alone; else along whichever axis is continuous where the other is discrete; else along y
  # where every group holds one x, or along x where every group holds one y, among all its rows;
  # else along y, where ggplot2 also warns, which a pure pipeline cannot. A box along x is
  # summarised as one along y, the two swapped and swapped back, as ggplot2's `flip_data()` does.
  #
  # The frame does what scales with the rows (`Giggly.DataFrame`): it chooses the rows, takes each
  # group's quartiles, count, x range and constant columns (`Giggly.Stat.Carry`), joins each
  # group's fences to its rows, collects the outliers into a list and finds the least and greatest
  # y of the rest; the fences, notches, whiskers and widths are worked out on the table of boxes,
  # one row each, so the stat never pulls a column of its input.

  # Every field is given by the function that adds the layer, its defaults there.
  @enforce_keys [:coef, :width, :orientation]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          coef: number(),
          width: :none | number(),
          orientation: :none | :x | :y
        }

  # The aesthetics a box plot's layer can use for its summary, from its own mapping or the plot's:
  # ggplot2's `stat_boxplot()`'s but `weight`, since weighted boxes are left out.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :width, :x, :y]

  # The aesthetics a box plot's summary cannot be computed without: x or y, ggplot2's
  # `required_aes = "y|x"`; both may be mapped, the summary running along one of them.
  @doc false
  @spec required_aesthetics() :: [[atom()]]
  def required_aesthetics, do: [[:x, :y]]

  # The variables the summary computes that a mapping's after_stat can read, as ggplot2 documents
  # `stat_boxplot()`'s, each of the whiskers and hinges in either orientation (`ymin` or `xmin`):
  # not the `outliers`, `relvarwidth` and `flipped_aes` its table also holds.
  @doc false
  @spec computed_variables() :: [atom()]
  def computed_variables,
    do: [
      :lower,
      :middle,
      :notchlower,
      :notchupper,
      :upper,
      :width,
      :xlower,
      :xmax,
      :xmiddle,
      :xmin,
      :xupper,
      :ymax,
      :ymin
    ]

  # The aesthetics the summary consumes, ggplot2's `dropped_aes`: the axis it summarises and the
  # one it places each box along, whose position it writes afresh, and a weight.
  @doc false
  @spec dropped_aesthetics() :: [atom()]
  def dropped_aesthetics, do: [:weight, :x, :y]

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.{Aesthetics, DataFrame, Resolution}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Stat.Carry

    # The columns the stat writes, in ggplot2's order.
    @computed [
      :ymin,
      :lower,
      :middle,
      :upper,
      :ymax,
      :outliers,
      :notchupper,
      :notchlower,
      :x,
      :width,
      :relvarwidth,
      :flipped_aes
    ]

    # ggplot2's default box width, as a share of the spacing of the x positions, and the share of
    # a group's x range a box spanning several x values takes.
    @width_share 0.75
    @range_share 0.9

    # ggplot2's notch: 1.58 times the box's height over the square root of its rows either side of
    # the median.
    @notch_share 1.58

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{}

    @impl Giggly.Stat
    def compute_layer(stat, frame, axes) do
      check_width(frame)
      flipped = flipped?(stat.orientation, frame, axes)

      frame
      |> flip(flipped)
      |> at_zero()
      |> boxes(stat, flipped)
      |> flip(flipped)
    end

    # A mapped width is how wide a box is drawn, so it must hold numbers, as a weight must.
    defp check_width(frame) do
      case DataFrame.dtypes(frame) do
        %{width: dtype} when dtype not in [:integer, :float, :null] ->
          raise ArgumentError,
                "a box is drawn as wide as its group's width, so a width must be a number, but " <>
                  "the layer's width is a #{inspect(dtype)} column"

        _numbers_or_no_width ->
          :ok
      end
    end

    # Whether the boxes run along x, drawn across y, as ggplot2's `has_flipped_aes()` decides a box
    # plot's orientation.
    defp flipped?(:x, _frame, _axes), do: false
    defp flipped?(:y, _frame, _axes), do: true

    defp flipped?(:none, frame, axes) do
      names = DataFrame.names(frame)
      x_discrete = discrete?(axes, :x)

      cond do
        :y not in names -> true
        :x not in names -> false
        x_discrete != discrete?(axes, :y) -> not x_discrete
        true -> one_y_per_group?(frame)
      end
    end

    defp discrete?(axes, axis),
      do: Enum.any?(axes, fn {_panel, panel_axes} -> Map.fetch!(panel_axes, axis).discrete end)

    # Whether every group holds one y and some group more than one x, among all the layer's rows,
    # as ggplot2 reads a group's values before it drops any.
    defp one_y_per_group?(frame) do
      distinct =
        DataFrame.summarise(frame, [:group], x: {:n_distinct, [:x]}, y: {:n_distinct, [:y]})

      not one_each?(distinct, :x) and one_each?(distinct, :y)
    end

    defp one_each?(distinct, name) do
      distinct
      |> DataFrame.pull(name)
      |> Enum.all?(fn count -> count == 1 end)
    end

    defp flip(frame, false), do: frame

    defp flip(frame, true) do
      renames =
        frame
        |> DataFrame.names()
        |> Aesthetics.flipped()

      DataFrame.select(frame, renames)
    end

    # The layer's rows at 0 where it maps no x, as ggplot2's box plot stat puts them.
    defp at_zero(frame) do
      if :x in DataFrame.names(frame),
        do: frame,
        else: DataFrame.mutate(frame, x: 0.0)
    end

    defp boxes(frame, stat, flipped) do
      names = DataFrame.names(frame)
      carried = Enum.reject(names, fn name -> name in @computed end)
      default_width = default_width(stat, frame)
      rows = DataFrame.filter(frame, {:and, [{:is_finite, [:x]}, {:is_finite, [:y]}]})
      constant = Carry.constant_columns(rows, carried)
      firsts = for name <- constant, name not in [:panel, :group], do: {name, {:first, [name]}}
      given_width = if :width in names, do: [given_width: {:first, [:width]}], else: []

      summarised =
        DataFrame.summarise(
          rows,
          [:panel, :group],
          [
            lower: {:quantile, [:y], probability: 0.25},
            middle: {:quantile, [:y], probability: 0.5},
            upper: {:quantile, [:y], probability: 0.75},
            rows: {:count, [:y]},
            x_low: {:min, [:x]},
            x_high: {:max, [:x]},
            x_count: {:n_distinct, [:x]}
          ] ++ given_width ++ firsts
        )

      heights = heights(summarised)
      fenced = fenced(summarised, heights, stat.coef)
      judged = DataFrame.join(rows, fenced, [:panel, :group])
      outlying = {:or, [{:<, [:y, :low_fence]}, {:>, [:y, :high_fence]}]}

      outliers =
        judged
        |> DataFrame.filter(outlying)
        |> DataFrame.summarise([:panel, :group], outliers: {:list, [:y]})

      reach =
        judged
        |> DataFrame.filter({:not, [outlying]})
        |> DataFrame.summarise([:panel, :group],
          reach_low: {:min, [:y]},
          reach_high: {:max, [:y]}
        )

      summarised
      |> DataFrame.join(outliers, [:panel, :group])
      |> DataFrame.join(reach, [:panel, :group])
      |> described(heights, default_width, flipped)
      |> DataFrame.select(Enum.map(@computed ++ constant, fn name -> {name, name} end))
    end

    # The stat's width, or else 0.75 of the spacing of the layer's x values counting from zero,
    # read from every row, as ggplot2 reads it before it drops any.
    defp default_width(%{width: width}, _frame) when is_number(width), do: width

    defp default_width(%{width: :none}, frame) do
      frame
      |> DataFrame.summarise([:x], [])
      |> DataFrame.pull(:x)
      |> Resolution.of(zero: true)
      |> Kernel.*(@width_share)
    end

    # Each box's height, the distance from `lower` to `upper`, R's `IQR` of its quartiles.
    defp heights(summarised) do
      lower = DataFrame.pull(summarised, :lower)
      upper = DataFrame.pull(summarised, :upper)
      Enum.zip_with(upper, lower, &Arithmetic.subtract/2)
    end

    # Each box's fences, `coef` times its height below `lower` and above `upper`, by panel and
    # group.
    defp fenced(summarised, heights, coef) do
      reaches = Enum.map(heights, fn height -> Arithmetic.multiply(coef, height) end)
      lower = DataFrame.pull(summarised, :lower)
      upper = DataFrame.pull(summarised, :upper)
      low_fences = Enum.zip_with(lower, reaches, &Arithmetic.subtract/2)
      high_fences = Enum.zip_with(upper, reaches, &Arithmetic.add/2)

      summarised
      |> DataFrame.put(:low_fence, low_fences)
      |> DataFrame.put(:high_fence, high_fences)
      |> DataFrame.select(
        panel: :panel,
        group: :group,
        low_fence: :low_fence,
        high_fence: :high_fence
      )
    end

    # The table of boxes with the columns the stat computes, worked out on its rows, one a box.
    defp described(boxes, heights, default_width, flipped) do
      boxes_count = DataFrame.row_count(boxes)
      lower = DataFrame.pull(boxes, :lower)
      middle = DataFrame.pull(boxes, :middle)
      upper = DataFrame.pull(boxes, :upper)
      rows = DataFrame.pull(boxes, :rows)

      outliers =
        boxes
        |> DataFrame.pull(:outliers)
        |> Enum.map(fn listed -> listed || [] end)

      notch_reaches = Enum.zip_with(heights, rows, &notch_reach/2)
      x_low = DataFrame.pull(boxes, :x_low)
      x_high = DataFrame.pull(boxes, :x_high)

      reach_low = DataFrame.pull(boxes, :reach_low)
      reach_high = DataFrame.pull(boxes, :reach_high)

      whiskers =
        Enum.zip_with([lower, middle, upper, reach_low, reach_high, outliers], &whisker_ends/1)

      boxes
      |> DataFrame.put(:ymin, Enum.map(whiskers, fn {low, _high} -> low end))
      |> DataFrame.put(:ymax, Enum.map(whiskers, fn {_low, high} -> high end))
      |> DataFrame.put(:outliers, outliers)
      |> DataFrame.put(:notchupper, Enum.zip_with(middle, notch_reaches, &Arithmetic.add/2))
      |> DataFrame.put(:notchlower, Enum.zip_with(middle, notch_reaches, &Arithmetic.subtract/2))
      |> DataFrame.put(:x, Enum.zip_with(x_low, x_high, &middle_of/2))
      |> DataFrame.put(:width, widths(boxes, x_low, x_high, default_width))
      |> DataFrame.put(:relvarwidth, Enum.map(rows, &:math.sqrt/1))
      |> DataFrame.put(:flipped_aes, List.duplicate(flipped, boxes_count))
    end

    # Where a box's whiskers end, as ggplot2's `stat_boxplot()` finds them: the least and the
    # greatest y that is no outlier, which are its least and greatest y where it has no outliers;
    # where it has, the range of its quartiles and those y, as R's `range(na.rm = TRUE)` takes it,
    # so a box whose every row is an outlier reaches its hinges.
    defp whisker_ends([_lower, _middle, _upper, reach_low, reach_high, []]),
      do: {as_float(reach_low), as_float(reach_high)}

    defp whisker_ends([lower, middle, upper, reach_low, reach_high, _outliers]) do
      quartiles = [lower, middle, upper]

      low =
        [reach_low | quartiles]
        |> Enum.reject(&is_nil/1)
        |> Enum.min()

      high =
        [reach_high | quartiles]
        |> Enum.reject(&is_nil/1)
        |> Enum.max()

      {as_float(low), as_float(high)}
    end

    # How far a box's notch reaches either side of its median: 1.58 times its height over the
    # square root of its rows, in R's order.
    defp notch_reach(height, rows) do
      @notch_share
      |> Arithmetic.multiply(height)
      |> Arithmetic.divide(:math.sqrt(rows))
    end

    # The middle of a box's x values' range, R's `mean(range(x))`.
    defp middle_of(low, high) do
      low
      |> Arithmetic.add(high)
      |> Arithmetic.divide(2)
    end

    # Each box's width: its group's first mapped width, or else 0.9 of its x values' range where
    # they are more than one, or else the default.
    defp widths(boxes, x_low, x_high, default_width) do
      given =
        if :given_width in DataFrame.names(boxes),
          do: DataFrame.pull(boxes, :given_width),
          else: List.duplicate(:none, DataFrame.row_count(boxes))

      x_count = DataFrame.pull(boxes, :x_count)

      Enum.zip_with([given, x_count, x_low, x_high], fn [given_width, distinct, low, high] ->
        width(given_width, distinct, low, high, default_width)
      end)
    end

    defp width(:none, x_count, low, high, _default_width) when x_count > 1 do
      high
      |> Arithmetic.subtract(low)
      |> Arithmetic.multiply(@range_share)
    end

    defp width(:none, _x_count, _low, _high, default_width), do: default_width
    defp width(given_width, _x_count, _low, _high, _default_width), do: given_width

    defp as_float(value) when is_integer(value), do: value / 1
    defp as_float(value), do: value
  end
end
