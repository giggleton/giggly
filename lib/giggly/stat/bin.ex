defmodule Giggly.Stat.Bin do
  @moduledoc false

  # Binning, ggplot2's `stat_bin()`, which `geom_histogram()` computes with: the axis cut into
  # bins, and for each group in each panel, in that order, one row per bin, bins ascending, its
  # `count` the rows in it, or the sum of their weights where the layer maps `weight`, a bin no
  # row falls in counting 0. Each row holds its bin's middle (`x`), ends (`xmin`, `xmax`) and
  # `width`, its `density`, the count over the width over the group's total of the counts'
  # magnitudes, its `ncount` and `ndensity`, the count and the density over the group's largest
  # magnitude, NaN for a group whose counts are all 0, as R divides by zero, and `flipped_aes`.
  # y takes the count by default (`after_stat(count)`), and a mapping's after_stat reads `count`,
  # `density`, `ncount`, `ndensity` and `width`, the variables ggplot2 documents. Run it through
  # `Giggly.Stat`.
  #
  # The bins are R's (`bin.R`), from each panel's axis as the stat is handed it: the breaks given,
  # put through the axis's transformation and sorted, a missing one dropped; or bins `binwidth`
  # wide, in transformed units, one edge on `boundary` or one middle on `center`, else on half a
  # width, from the bin holding the axis's low limit to the one holding its high; or else `bins`
  # of them, 30 by default, spanning the limits, the outermost two centred on them, or edged on
  # them when the limits fall on a boundary. An axis of zero width takes bins 0.1 wide. A bin is
  # closed on the right, the lowest closed on the left too, or with `closed: :left` the other way
  # round; each break is moved a hundred-millionth of the bins' median width outward, so a value
  # on a break that rounding moved still falls where R puts it. `pad` adds a bin of no rows at
  # each end, so a frequency polygon reaches 0, and `drop` leaves out every bin of no rows
  # (`:all`) or those before the first and after the last bin with rows (`:extremes`).
  #
  # The frame does what scales with the rows (`Giggly.DataFrame`): it chooses the rows at a finite
  # x, puts each row in its bin (`cut`), sums the weights in each bin of each group, with R's
  # compensated sum, a missing weight adding nothing, and carries the columns constant within each
  # group (`Giggly.Stat.Carry`); the breaks come from two numbers, and the rest is worked out on
  # the summarised counts, so binning never pulls a column of its input. Binning along y, where
  # the layer maps `:y` alone, is binning along x with the two swapped and swapped back, as
  # ggplot2's `flip_data()` does; an axis that is discrete is refused, as `stat_bin()` refuses
  # one.

  # Every field is given by the function that adds the layer, its defaults there.
  @enforce_keys [:binwidth, :bins, :center, :boundary, :breaks, :closed, :pad, :drop]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          binwidth: :none | number(),
          bins: pos_integer(),
          center: :none | number(),
          boundary: :none | number(),
          breaks: :none | [number()],
          closed: :right | :left,
          pad: boolean(),
          drop: :none | :all | :extremes
        }

  # The aesthetics a layer that bins can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :weight, :x, :y]

  # The aesthetics a layer that bins cannot be computed without: one of x and y, ggplot2's
  # `required_aes = "x|y"`.
  @doc false
  @spec required_aesthetics() :: [[atom()]]
  def required_aesthetics, do: [[:x, :y]]

  # The aesthetics of which a layer that bins maps at most one, as ggplot2's `stat_bin()` refuses
  # x and y together.
  @doc false
  @spec exclusive_aesthetics() :: [[atom()]]
  def exclusive_aesthetics, do: [[:x, :y]]

  # The variables binning computes that a mapping's after_stat can read, as ggplot2 documents
  # `stat_bin()`'s.
  @doc false
  @spec computed_variables() :: [atom()]
  def computed_variables, do: [:count, :density, :ncount, :ndensity, :width]

  # The aesthetics binning consumes, ggplot2's `dropped_aes`: a weight is summed into the count.
  @doc false
  @spec dropped_aesthetics() :: [atom()]
  def dropped_aesthetics, do: [:weight]

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.{Aesthetics, DataFrame}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Stat.Carry

    # The columns binning writes, in ggplot2's order.
    @computed [:count, :x, :xmin, :xmax, :width, :density, :ncount, :ndensity, :flipped_aes]

    # R's `.Machine$double.eps`.
    @epsilon 2.220446049250313e-16

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{x: :count, y: :count}

    @impl Giggly.Stat
    def compute_layer(stat, frame, axes) do
      check_weight(frame)
      flipped = :x not in DataFrame.names(frame)
      axis = if flipped, do: :y, else: :x
      check_continuous(axes, axis)

      binned_axes =
        Map.new(axes, fn {panel, panel_axes} -> {panel, Map.fetch!(panel_axes, axis)} end)

      frame
      |> flip(flipped)
      |> bin(stat, binned_axes, flipped)
      |> flip(flipped)
    end

    # A weight is summed, so it must hold numbers, as counting's must.
    defp check_weight(frame) do
      case DataFrame.dtypes(frame) do
        %{weight: dtype} when dtype not in [:integer, :float, :null] ->
          raise ArgumentError,
                "binning sums each row's weight, so a weight must be a number, but the layer's " <>
                  "weight is a #{inspect(dtype)} column"

        _numbers_or_no_weight ->
          :ok
      end
    end

    defp check_continuous(axes, axis) do
      if Enum.any?(axes, fn {_panel, panel_axes} -> Map.fetch!(panel_axes, axis).discrete end) do
        raise ArgumentError,
              "binning cuts a continuous #{axis} into bins, but the layer's #{axis} is on a " <>
                "discrete axis; Giggly.Plot.geom_bar/3 counts the rows at each discrete value"
      end
    end

    defp flip(frame, false), do: frame

    defp flip(frame, true) do
      renames =
        frame
        |> DataFrame.names()
        |> Aesthetics.flipped()

      DataFrame.select(frame, renames)
    end

    defp bin(frame, stat, axes, flipped) do
      carried =
        frame
        |> DataFrame.names()
        |> Enum.reject(fn name -> name in @computed end)

      positioned = DataFrame.filter(frame, {:is_finite, [:x]})
      constant = Carry.constant_columns(positioned, carried)
      firsts = for name <- constant, name not in [:panel, :group], do: {name, {:first, [name]}}
      groups = DataFrame.summarise(positioned, [:panel, :group], firsts)
      keys = panels_and_groups(groups)

      breaks =
        keys
        |> Enum.map(fn {panel, _group} -> panel end)
        |> Enum.uniq()
        |> Map.new(fn panel -> {panel, breaks(stat, Map.fetch!(axes, panel))} end)

      counts = counts(weighted(positioned), breaks, stat.closed)

      bins_by_group =
        Enum.map(keys, fn {panel, _group} = key ->
          {key, group_bins(Map.fetch!(breaks, panel), counts, key, stat.pad)}
        end)

      totals = totals(bins_by_group)

      bins_by_group
      |> Enum.flat_map(fn {key, bins} ->
        bins
        |> normalised(Map.fetch!(totals, key))
        |> dropped(stat.drop)
        |> Enum.map(fn bin -> Map.put(bin, :key, key) end)
      end)
      |> output(groups, constant, flipped)
    end

    # The table with each row's weight, 1 where the layer maps none, as ggplot2's `stat_bin()`
    # weighs each row 1.
    defp weighted(frame) do
      if :weight in DataFrame.names(frame),
        do: frame,
        else: DataFrame.mutate(frame, weight: 1.0)
    end

    defp panels_and_groups(frame) do
      panels = DataFrame.pull(frame, :panel)
      groups = DataFrame.pull(frame, :group)
      Enum.zip(panels, groups)
    end

    # The summed weight of each panel's rows in each bin of each group, by `{panel, group, bin}`:
    # each panel's rows cut by its own breaks, as each panel's scale gives it its own.
    defp counts(frame, breaks, closed) do
      frame
      |> DataFrame.split(:panel)
      |> Enum.flat_map(fn {panel, panel_frame} ->
        fuzzy =
          breaks
          |> Map.fetch!(panel)
          |> fuzzy(closed)

        panel_frame
        |> DataFrame.mutate(bin: {:cut, [:x], breaks: fuzzy, closed: closed})
        |> DataFrame.summarise([:group, :bin], count: {:sum, [:weight], missing: :skip})
        |> counted(panel)
      end)
      |> Map.new()
    end

    defp counted(summarised, panel) do
      [:group, :bin, :count]
      |> Enum.map(fn name -> DataFrame.pull(summarised, name) end)
      |> Enum.zip_with(fn [group, bin, count] -> {{panel, group, bin}, count} end)
    end

    # A group's bins, R's `bin_vector()`: each bin's count, 0 where no row falls, its middle and
    # its width, with a bin of no rows at each end where `pad` says.
    defp group_bins(breaks, counts, {panel, group}, pad) do
      breaks
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.with_index(1)
      |> Enum.map(fn {[low, high], index} ->
        %{
          count: Map.get(counts, {panel, group, index}, 0.0),
          x: middle(low, high),
          width: Arithmetic.subtract(high, low)
        }
      end)
      |> padded(pad)
    end

    defp middle(low, high) do
      low
      |> Arithmetic.add(high)
      |> Arithmetic.divide(2)
    end

    defp padded(bins, false), do: bins

    defp padded(bins, true) do
      %{x: first_x, width: first_width} = List.first(bins)
      %{x: last_x, width: last_width} = List.last(bins)
      before = %{count: 0.0, x: Arithmetic.subtract(first_x, first_width), width: first_width}
      beyond = %{count: 0.0, x: Arithmetic.add(last_x, last_width), width: last_width}
      Enum.concat([[before], bins, [beyond]])
    end

    # Each group's total, the sum of its counts' magnitudes, which R's `sum()` adds in extended
    # precision, so the frame adds them.
    defp totals(bins_by_group) do
      rows =
        for {key, bins} <- bins_by_group,
            bin <- bins,
            do: {key, Arithmetic.magnitude(bin.count)}

      totals =
        [
          {:panel, Enum.map(rows, fn {{panel, _group}, _magnitude} -> panel end)},
          {:group, Enum.map(rows, fn {{_panel, group}, _magnitude} -> group end)},
          {:magnitude, Enum.map(rows, fn {_key, magnitude} -> magnitude end)}
        ]
        |> DataFrame.new()
        |> DataFrame.summarise([:panel, :group], total: {:sum, [:magnitude]})

      [:panel, :group, :total]
      |> Enum.map(fn name -> DataFrame.pull(totals, name) end)
      |> Enum.zip_with(fn [panel, group, total] -> {{panel, group}, total} end)
      |> Map.new()
    end

    # A group's bins with their ends, density, and count and density over their largest, R's
    # `bin_out()`.
    defp normalised(bins, total) do
      densities =
        Enum.map(bins, fn bin ->
          bin.count
          |> Arithmetic.divide(bin.width)
          |> Arithmetic.divide(total)
        end)

      largest_count = largest(Enum.map(bins, fn bin -> bin.count end))
      largest_density = largest(densities)

      Enum.zip_with(bins, densities, fn bin, density ->
        Map.merge(bin, %{
          xmin: Arithmetic.subtract(bin.x, Arithmetic.divide(bin.width, 2)),
          xmax: Arithmetic.add(bin.x, Arithmetic.divide(bin.width, 2)),
          density: density,
          ncount: Arithmetic.divide(bin.count, largest_count),
          ndensity: Arithmetic.divide(density, largest_density)
        })
      end)
    end

    # The largest magnitude among `values`, R's `max(abs(values))`.
    defp largest(values) do
      values
      |> Enum.map(&Arithmetic.magnitude/1)
      |> Arithmetic.maximum()
    end

    # A group's bins less those `drop` leaves out, as `stat_bin()`'s `drop` slices them.
    defp dropped(bins, :none), do: bins
    defp dropped(bins, :all), do: Enum.reject(bins, fn bin -> bin.count == 0 end)

    defp dropped(bins, :extremes) do
      bins
      |> Enum.drop_while(fn bin -> bin.count == 0 end)
      |> Enum.reverse()
      |> Enum.drop_while(fn bin -> bin.count == 0 end)
      |> Enum.reverse()
    end

    # The output table: the computed columns in ggplot2's order, then each column carried from its
    # group's rows, a category kept one, with its levels.
    defp output(bins, groups, constant, flipped) do
      computed =
        for name <- [:count, :x, :xmin, :xmax, :width, :density, :ncount, :ndensity],
            do: {name, Enum.map(bins, fn bin -> Map.fetch!(bin, name) end)}

      dtypes = DataFrame.dtypes(groups)
      keys = panels_and_groups(groups)

      carried =
        Enum.map(constant, fn name ->
          by_group = by_group(groups, keys, name)
          values = Enum.map(bins, fn bin -> Map.fetch!(by_group, bin.key) end)

          if Map.fetch!(dtypes, name) == :category,
            do: {name, values, DataFrame.category(groups, name)},
            else: {name, values}
        end)

      flipped_aes = {:flipped_aes, List.duplicate(flipped, length(bins))}

      [computed, [flipped_aes], carried]
      |> Enum.concat()
      |> DataFrame.new()
    end

    # Each group's value of a carried column, by `{panel, group}`.
    defp by_group(groups, keys, name) do
      values = DataFrame.pull(groups, name)

      keys
      |> Enum.zip(values)
      |> Map.new()
    end

    # A panel's breaks, as R's `compute_bins()` chooses them from the panel's axis.
    defp breaks(%{breaks: given}, %{transform: transform}) when is_list(given) do
      given
      |> transform.()
      |> Enum.reject(fn position -> position in [nil, :nan] end)
      |> Enum.sort_by(&order/1)
    end

    defp breaks(%{binwidth: width} = stat, %{limits: limits}) when is_number(width),
      do: width_breaks(limits, width, stat.center, stat.boundary)

    defp breaks(%{bins: bins} = stat, %{limits: limits}),
      do: bins_breaks(limits, bins, stat.center, stat.boundary)

    # Where a position sorts, as R's `sort()` orders the infinities.
    defp order(:neg_infinity), do: {0, 0}
    defp order(:infinity), do: {2, 0}
    defp order(position), do: {1, position}

    # Breaks `bins` many spanning the limits, R's `bin_breaks_bins()`: an axis of zero width, its
    # ends equal as the axis gives it, takes bins 0.1 wide; one bin spans the limits; more are
    # one span less than their number apart, the outermost centred on the limits unless a
    # boundary or a centre is given, and as many as their number apart where either limit falls on
    # the boundary.
    defp bins_breaks({low, high} = limits, _bins, center, boundary) when low == high,
      do: width_breaks(limits, 0.1, center, boundary)

    defp bins_breaks({low, high} = limits, 1, _center, _boundary),
      do: width_breaks(limits, high - low, :none, low)

    defp bins_breaks({low, high} = limits, bins, center, boundary) do
      width = (high - low) / (bins - 1)

      boundary =
        if center == :none and boundary == :none, do: low - width / 2, else: boundary

      width =
        if boundary != :none and
             (on_boundary?(low, width, boundary) or on_boundary?(high, width, boundary)),
           do: (high - low) / bins,
           else: width

      width_breaks(limits, width, center, boundary)
    end

    defp on_boundary?(limit, width, boundary),
      do: modulo(limit, width) == modulo(boundary, width)

    # `value %% divisor` as R works it for doubles (`myfmod()`), its sign the divisor's; R works
    # the first remainder in extended precision, which only a limit within rounding of a boundary
    # can tell apart.
    defp modulo(value, divisor) do
      remainder = value - Float.floor(value / divisor) * divisor
      remainder - Float.floor(remainder / divisor) * divisor
    end

    # Breaks `width` apart over the limits, R's `bin_breaks_width()`: an edge on `boundary`, or a
    # middle on `center`, or else an edge half a width from 0, the first break the edge below the
    # low limit and the last past the high one, by R's `seq()`; at least two.
    defp width_breaks({low, high}, width, center, boundary) do
      boundary =
        cond do
          boundary != :none -> boundary
          center != :none -> center - width / 2
          true -> width / 2
        end

      origin = boundary + Float.floor((low - boundary) / width) * width
      last = high + (1 - 1.0e-8) * width

      if (last - origin) / width > 1.0e6 do
        raise ArgumentError,
              "a bin width of #{inspect(width)} cuts the axis into more than 1,000,000 bins; " <>
                "give a wider binwidth:"
      end

      case sequence(origin, last, width) do
        [only] -> [only, only + width]
        breaks -> breaks
      end
    end

    # R's `seq(from, to, by)` for doubles: from `from` in steps of `by` while not past `to`, each
    # `from + step * by`, `from` alone where `to` is within rounding of it.
    defp sequence(from, to, by) do
      if abs(to - from) / max(abs(to), abs(from)) < 100 * @epsilon do
        [from]
      else
        steps = trunc((to - from) / by + 1.0e-10)
        Enum.map(0..steps, fn step -> min(from + step * by, to) end)
      end
    end

    # The breaks moved outward a hundred-millionth of their median width, R's `bins()`: the first
    # down and every other up when bins are closed on the right, the last up and every other down
    # when closed on the left, so a value on a break that rounding moved falls as R puts it.
    defp fuzzy(breaks, closed) do
      fuzz = fuzz(breaks)
      last = length(breaks) - 1

      breaks
      |> Enum.with_index()
      |> Enum.map(fn {break, index} -> shifted(break, fuzz_sign(index, last, closed) * fuzz) end)
    end

    defp fuzz_sign(0, _last, :right), do: -1
    defp fuzz_sign(_index, _last, :right), do: 1
    defp fuzz_sign(last, last, :left), do: 1
    defp fuzz_sign(_index, _last, :left), do: -1

    defp fuzz(breaks) do
      finite = Enum.filter(breaks, &is_number/1)

      gaps =
        finite
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [low, high] -> high - low end)

      case median(gaps) do
        nil -> @epsilon * 1000
        median -> 1.0e-8 * median
      end
    end

    # R's `median()`: the middle value, or the mean of the middle two; missing for none.
    defp median([]), do: nil

    defp median(values) do
      sorted = Enum.sort(values)
      count = length(sorted)
      middle = div(count, 2)

      if rem(count, 2) == 1,
        do: Enum.at(sorted, middle),
        else: (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
    end

    defp shifted(break, amount) when is_number(break), do: break + amount
    defp shifted(infinity, _amount), do: infinity
  end
end
