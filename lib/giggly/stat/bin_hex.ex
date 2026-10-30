defmodule Giggly.Stat.BinHex do
  @moduledoc false

  # Hexagonal binning, ggplot2's `stat_bin_hex()`, which `geom_hex()` computes with: the plane cut
  # into regular hexagons, and for each group in each panel, in that order, one row per hexagon
  # some row falls in, in the order hexbin numbers them, along each row of hexagons from the left
  # and the rows from the bottom. Each row holds its hexagon's centre (`x`, `y`), the bins' `width`
  # and `height`, its `count`, the rows in it or the sum of their weights where the layer maps
  # `weight`, its `density`, the count over the group's total, and its `ncount` and `ndensity`, the
  # count and the density over the group's largest. fill takes the count by default
  # (`after_stat(count)`), and a mapping's after_stat reads `count`, `density`, `ncount` and
  # `ndensity`, the variables ggplot2 documents. Run it through `Giggly.Stat`.
  #
  # The bins are `binwidth` wide along x and high along y, in transformed units, or else each
  # panel's axis's extent over its `bins`, as ggplot2's `hex_binwidth()` divides each axis's
  # `dimension()`, where its 4.0.3 divides x's twice for a pair of bins, against its documentation,
  # which Giggly follows. Each group's hexagons span its own rows, as ggplot2's `hex_bounds()`
  # rounds the group's least and greatest x and y out to the bins' width and a millionth beyond,
  # so groups are binned on hexagons of their own. A row falls in the hexagon whose centre is
  # nearest, found as Carr et al. (1987) describe and hexbin finds it: in units where the hexagons
  # are regular, the nearest centre on each of two rectangular lattices offset by half a step, the
  # nearer of the two, the first where they are as near. hexbin works that unit along y with a
  # single-precision √3, which a hexagon's centre takes in double precision, so a row near a
  # hexagon's edge falls where hexbin puts it. A row missing its x or y, or at an infinite one, is
  # not counted; a hexagon whose weights are missing or NaN is left out, as R's `na.omit()` leaves
  # it. Where ggplot2's binning fails, a panel whose axis has no width or whose group's hexagons
  # would not span its rows, the whole panel is given no rows, as ggplot2 catches the failure per
  # panel. A discrete axis is binned on its positions, as R bins it.
  #
  # The frame does what scales with the rows (`Giggly.DataFrame`): it chooses the rows at a finite
  # x and y, finds each group's least and greatest, joins each group's lattice to its rows, puts
  # each row in its hexagon by an expression (`floor`, arithmetic, `<` and `if_else`), sums the
  # weights in each hexagon of each group, as R's `sum()` adds them, and carries the columns
  # constant within each group (`Giggly.Stat.Carry`); the centres, the densities and the rest are
  # worked out on the summarised counts, so binning never pulls a column of its input.

  # Every field is given by the function that adds the layer, its defaults there: `bins` along x
  # and y, and `binwidth` along x and y, or `:none`.
  @enforce_keys [:bins, :binwidth]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          bins: {pos_integer(), pos_integer()},
          binwidth: :none | {float(), float()}
        }

  # The aesthetics a layer that bins in hexagons can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :weight, :x, :y]

  # The aesthetics a layer that bins in hexagons cannot be computed without, ggplot2's
  # `required_aes`.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  # The variables hexagonal binning computes that a mapping's after_stat can read, as ggplot2
  # documents `stat_bin_hex()`'s.
  @doc false
  @spec computed_variables() :: [atom()]
  def computed_variables, do: [:count, :density, :ncount, :ndensity]

  # The aesthetics hexagonal binning consumes, ggplot2's `dropped_aes`: a weight is summed into
  # the count.
  @doc false
  @spec dropped_aesthetics() :: [atom()]
  def dropped_aesthetics, do: [:weight]

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.DataFrame
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Stat.Carry

    # The columns hexagonal binning writes, in ggplot2's order.
    @computed [:x, :y, :width, :height, :density, :ndensity, :count, :ncount]

    # How far beyond its rows, rounded out to the bins' width, a group's hexagons reach, ggplot2's
    # `hex_bounds()`.
    @bounds_margin 1.0e-6

    # √3 as hexbin puts a row in its hexagon, in single precision, Fortran's `sqrt(3.)`, and as it
    # places a hexagon's centre, in double precision, R's `sqrt(3)`.
    @single_precision_root_three 1.73205077648162841796875
    @root_three 1.7320508075688772

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{fill: :count}

    @impl Giggly.Stat
    def compute_layer(stat, frame, axes) do
      check_weight(frame)

      carried =
        frame
        |> DataFrame.names()
        |> Enum.reject(fn name -> name in @computed end)

      positioned = DataFrame.filter(frame, {:and, [{:is_finite, [:x]}, {:is_finite, [:y]}]})
      constant = Carry.constant_columns(positioned, carried)
      firsts = for name <- constant, name not in [:panel, :group], do: {name, {:first, [name]}}

      extents = [
        x_least: {:min, [:x]},
        x_greatest: {:max, [:x]},
        y_least: {:min, [:y]},
        y_greatest: {:max, [:y]}
      ]

      groups = DataFrame.summarise(positioned, [:panel, :group], firsts ++ extents)
      lattices = lattices(groups, stat, axes)

      positioned
      |> weighted()
      |> counts(groups, lattices)
      |> Enum.flat_map(fn {key, cells} -> hexagons(cells, Map.fetch!(lattices, key), key) end)
      |> normalised()
      |> output(groups, constant)
    end

    # A weight is summed, so it must hold numbers, as counting's must.
    defp check_weight(frame) do
      case DataFrame.dtypes(frame) do
        %{weight: dtype} when dtype not in [:integer, :float, :null] ->
          raise ArgumentError,
                "hexagonal binning sums each row's weight, so a weight must be a number, but " <>
                  "the layer's weight is a #{inspect(dtype)} column"

        _numbers_or_no_weight ->
          :ok
      end
    end

    # The table with each row's weight, 1 where the layer maps none, as ggplot2's
    # `stat_bin_hex()` weighs each row 1.
    defp weighted(frame) do
      if :weight in DataFrame.names(frame),
        do: frame,
        else: DataFrame.mutate(frame, weight: 1.0)
    end

    # Each group's lattice, by `{panel, group}`, for the groups of every panel that can be binned:
    # its hexagons' extent, ggplot2's `hex_bounds()`, their number across and the ratio of their
    # number up to it, as ggplot2 hands hexbin `xbins` and `shape`, and the bins' width and height.
    defp lattices(groups, stat, axes) do
      groups
      |> keys()
      |> Enum.zip_with(extents(groups), fn {panel, _group} = key, extent ->
        {key, lattice(extent, widths(stat, Map.fetch!(axes, panel)))}
      end)
      |> Enum.group_by(fn {{panel, _group}, _lattice} -> panel end)
      |> Enum.reject(fn {_panel, lattices} ->
        Enum.any?(lattices, fn {_key, lattice} -> lattice == :failed end)
      end)
      |> Enum.flat_map(fn {_panel, lattices} -> lattices end)
      |> Map.new()
    end

    # Each group's least and greatest x and y, in group order.
    defp extents(groups) do
      [:x_least, :x_greatest, :y_least, :y_greatest]
      |> Enum.map(fn name -> DataFrame.pull(groups, name) end)
      |> Enum.zip_with(fn [x_least, x_greatest, y_least, y_greatest] ->
        {{x_least, x_greatest}, {y_least, y_greatest}}
      end)
    end

    # The bins' width and height in a panel: the stat's, or each axis's extent over its bins, as
    # ggplot2's `hex_binwidth()` divides each axis's `dimension()`.
    defp widths(%{binwidth: {width, height}}, _panel_axes), do: {width, height}

    defp widths(%{bins: {x_bins, y_bins}}, %{x: x_axis, y: y_axis}),
      do: {extent_width(x_axis) / x_bins, extent_width(y_axis) / y_bins}

    defp extent_width(%{limits: {low, high}}), do: high - low

    # A group's lattice, or `:failed` where ggplot2's binning fails: bins of no width, which
    # ggplot2's `hex_bounds()` divides by, or hexagons that would not span the group's rows, which
    # hexbin refuses.
    defp lattice(_extent, {width, height}) when width == 0 or height == 0, do: :failed

    defp lattice({x_extent, y_extent}, {width, height} = widths) do
      {x_low, x_high} = x_bounds = bounds(x_extent, width)
      {y_low, y_high} = y_bounds = bounds(y_extent, height)

      if spans?(x_bounds, x_extent) and spans?(y_bounds, y_extent) do
        across = (x_high - x_low) / width
        up = (y_high - y_low) / height

        %{
          x_bounds: x_bounds,
          y_bounds: y_bounds,
          across: across,
          shape: up / across,
          columns: trunc(Float.floor(across + 1.5001)),
          widths: widths
        }
      else
        :failed
      end
    end

    # ggplot2's `hex_bounds()`: the least value rounded down to a whole number of widths and the
    # greatest up, as its `round_any()` rounds them, each a millionth beyond.
    defp bounds({least, greatest}, width) do
      {Float.floor(least / width) * width - @bounds_margin,
       Float.ceil(greatest / width) * width + @bounds_margin}
    end

    defp spans?({low, high}, {least, greatest}),
      do: low < high and low <= least and high >= greatest

    defp keys(frame) do
      panels = DataFrame.pull(frame, :panel)
      groups = DataFrame.pull(frame, :group)
      Enum.zip(panels, groups)
    end

    # The summed weight of each hexagon some row falls in, by `{panel, group}`, each group's
    # `{cell, count}` in hexbin's order, a hexagon whose weights are missing or NaN left out.
    defp counts(frame, groups, lattices) do
      frame
      |> DataFrame.join(lattice_table(groups, lattices), [:panel, :group])
      |> DataFrame.filter({:is_finite, [:x_scale]})
      |> cells()
      |> DataFrame.summarise([:panel, :group, :cell], count: {:sum, [:weight]})
      |> counted()
    end

    # The constants each row is put in its hexagon by, one row per group, missing for a group of
    # a panel that cannot be binned: where its lattice starts, how many lattice steps a unit of x
    # and of y is, as hexbin's `c1` and `c2` scale them, how far its cells' numbers step for each
    # row of the first lattice, and where the second lattice's start.
    defp lattice_table(groups, lattices) do
      by_group =
        groups
        |> keys()
        |> Enum.map(fn key -> Map.get(lattices, key) end)

      columns = [
        x_origin: fn %{x_bounds: {low, _high}} -> low end,
        y_origin: fn %{y_bounds: {low, _high}} -> low end,
        x_scale: fn %{x_bounds: {low, high}} = lattice -> lattice.across / (high - low) end,
        y_scale: fn %{y_bounds: {low, high}} = lattice ->
          lattice.across * lattice.shape / ((high - low) * @single_precision_root_three)
        end,
        row_step: fn lattice -> 2.0 * lattice.columns end,
        second_start: fn lattice -> lattice.columns + 1.0 end
      ]

      Enum.reduce(columns, DataFrame.select(groups, panel: :panel, group: :group), fn
        {name, value}, table ->
          DataFrame.put(
            table,
            name,
            Enum.map(by_group, fn lattice -> lattice && value.(lattice) end)
          )
      end)
    end

    # Each row's hexagon, numbered as hexbin numbers its cells: in lattice units, the nearest
    # centre on the first lattice, at whole steps, and on the second, half a step across and up,
    # each's distance squared with y's three times x's, where the hexagons are regular, and the
    # nearer, the first where they are as near.
    defp cells(frame) do
      frame
      |> DataFrame.mutate(
        across: {:*, [:x_scale, {:-, [:x, :x_origin]}]},
        up: {:*, [:y_scale, {:-, [:y, :y_origin]}]}
      )
      |> DataFrame.mutate(
        first_column: {:floor, [{:+, [:across, 0.5]}]},
        first_row: {:floor, [{:+, [:up, 0.5]}]},
        second_column: {:floor, [:across]},
        second_row: {:floor, [:up]}
      )
      |> DataFrame.mutate(
        first_distance: distance({:-, [:across, :first_column]}, {:-, [:up, :first_row]}),
        second_distance:
          distance(
            {:-, [{:-, [:across, :second_column]}, 0.5]},
            {:-, [{:-, [:up, :second_row]}, 0.5]}
          )
      )
      |> DataFrame.mutate(
        cell:
          {:if_else,
           [
             {:<, [:second_distance, :first_distance]},
             {:+, [{:+, [{:*, [:second_row, :row_step]}, :second_column]}, :second_start]},
             {:+, [{:+, [{:*, [:first_row, :row_step]}, :first_column]}, 1.0]}
           ]}
      )
    end

    defp distance(across, up),
      do: {:+, [{:*, [across, across]}, {:*, [3.0, {:*, [up, up]}]}]}

    defp counted(summarised) do
      [:panel, :group, :cell, :count]
      |> Enum.map(fn name -> DataFrame.pull(summarised, name) end)
      |> Enum.zip_with(fn [panel, group, cell, count] -> {{panel, group}, {cell, count}} end)
      |> Enum.reject(fn {_key, {_cell, count}} -> count in [nil, :nan] end)
      |> Enum.chunk_by(fn {key, _cell} -> key end)
      |> Enum.map(fn [{key, _cell} | _rest] = cells ->
        {key, Enum.map(cells, fn {_key, cell} -> cell end)}
      end)
    end

    # A group's hexagons, each at its centre, as hexbin's `hcell2xy()` places a cell: its row up
    # the lattice and its column across, every other row half a column across.
    defp hexagons(cells, lattice, key) do
      %{x_bounds: {x_low, x_high}, y_bounds: {y_low, y_high}, widths: {width, height}} = lattice
      across_step = (x_high - x_low) / lattice.across
      up_step = (y_high - y_low) * @root_three / (2 * lattice.shape * lattice.across)

      Enum.map(cells, fn {cell, count} ->
        index = trunc(cell) - 1
        row = div(index, lattice.columns)
        column = rem(index, lattice.columns)
        offset = if rem(row, 2) == 0, do: column, else: column + 0.5

        %{
          key: key,
          x: across_step * offset + x_low,
          y: up_step * row + y_low,
          width: width,
          height: height,
          count: count
        }
      end)
    end

    # The hexagons with their density and their count and density over the group's largest, as
    # `stat_bin_hex()` divides them: the group's total summed by the frame, as R's `sum()` adds.
    defp normalised(hexagons) do
      totals = totals(hexagons)

      hexagons
      |> Enum.chunk_by(fn hexagon -> hexagon.key end)
      |> Enum.flat_map(fn [%{key: key} | _rest] = group ->
        total = Map.fetch!(totals, key)
        densities = Enum.map(group, fn hexagon -> Arithmetic.divide(hexagon.count, total) end)
        largest_density = Arithmetic.maximum(densities)

        largest_count =
          group
          |> Enum.map(fn hexagon -> hexagon.count end)
          |> Arithmetic.maximum()

        Enum.zip_with(group, densities, fn hexagon, density ->
          Map.merge(hexagon, %{
            density: density,
            ndensity: Arithmetic.divide(density, largest_density),
            ncount: Arithmetic.divide(hexagon.count, largest_count)
          })
        end)
      end)
    end

    defp totals([]), do: %{}

    defp totals(hexagons) do
      totals =
        [
          {:panel, Enum.map(hexagons, fn %{key: {panel, _group}} -> panel end)},
          {:group, Enum.map(hexagons, fn %{key: {_panel, group}} -> group end)},
          {:count, Enum.map(hexagons, fn hexagon -> hexagon.count end)}
        ]
        |> DataFrame.new()
        |> DataFrame.summarise([:panel, :group], total: {:sum, [:count]})

      totals
      |> keys()
      |> Enum.zip(DataFrame.pull(totals, :total))
      |> Map.new()
    end

    # The output table: the computed columns in ggplot2's order, then each column carried from its
    # group's rows, a category kept one, with its levels.
    defp output(hexagons, groups, constant) do
      computed =
        for name <- @computed,
            do: {name, Enum.map(hexagons, fn hexagon -> Map.fetch!(hexagon, name) end)}

      dtypes = DataFrame.dtypes(groups)
      keys = keys(groups)

      carried =
        Enum.map(constant, fn name ->
          by_group = by_group(groups, keys, name)
          values = Enum.map(hexagons, fn hexagon -> Map.fetch!(by_group, hexagon.key) end)

          if Map.fetch!(dtypes, name) == :category,
            do: {name, values, DataFrame.category(groups, name)},
            else: {name, values}
        end)

      computed
      |> Enum.concat(carried)
      |> DataFrame.new()
    end

    # Each group's value of a carried column, by `{panel, group}`.
    defp by_group(groups, keys, name) do
      values = DataFrame.pull(groups, name)

      keys
      |> Enum.zip(values)
      |> Map.new()
    end
  end
end
