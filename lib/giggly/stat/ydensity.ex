defmodule Giggly.Stat.Ydensity do
  @moduledoc false

  # A violin's densities, ggplot2's `stat_ydensity()`, which `geom_violin()` computes with: for
  # each group in each panel, in that order, a kernel density estimate of its y, 512 rows evenly
  # spaced across the group's own extent of y, or that widened by three of the rule's bandwidths
  # either end without `trim`, each its place `y`, its `density`, `scaled` and `ndensity`,
  # `count`, `wdensity` and `n`, as a density's (`Giggly.Stat.KernelDensity`, ggplot2's
  # `compute_density()`, its bandwidth worked out from all the group's rows, before the bounds
  # leave any out, as `stat_ydensity()` works it out before handing it over). Its `x` is the
  # group's x, or the middle of its x values' range where they are more than one, with a `width`
  # of 0.9 of that range; else its `width` is the stat's, the layer's `width:`, or else a mapped
  # one, carried, missing ones too, to each group of one x and each short group kept where it is
  # constant within every such group, as ggplot2 carries it, and leaving every row without a
  # `width` where it varies within one, as ggplot2 drops the column; else none. Then a
  # row for each of `quantiles`, in their order, at the type 7 quantile of the group's y, R's
  # `quantile()`, unweighted as ggplot2 takes it (and warns, which a pure pipeline cannot), its
  # `quantile` that probability, every other column the group's curve read at that y by R's
  # `approx()` formula (`Giggly.Stat.Curve`), missing past its ends; a curve row at the y of a
  # quantile is left out, as ggplot2 leaves it, so a group whose y are all one value keeps only
  # its quantile rows. `quantiles: :none` writes no `quantile` column, R's `NULL`; an empty list
  # writes one of missing values, as R's `numeric(0)` does. Each row's `violinwidth` is how wide
  # its violin is drawn there, a share of its width: its density over the panel's greatest
  # (`scale: :area`), so every violin has the same area; that times its group's rows over the
  # panel's most (`:count`); or its `scaled` density (`:width`), so every violin is as wide at
  # its widest. Then `flipped_aes`. y takes nothing by default, since the violin geom draws the
  # columns as they are named, and a mapping's after_stat reads `density`, `scaled`, `count`,
  # `violinwidth`, `n`, `width` and `quantile`, the variables ggplot2 documents. Run it through
  # `Giggly.Stat`.
  #
  # A row missing its x, y or weight, or at an infinite one, is left out first, as ggplot2's
  # `remove_missing()` drops it. A group of fewer than two rows is left out, as `drop` does by
  # default (ggplot2 also warns), or with `drop: false` kept as one row of its x, its y and `n`,
  # every other computed column missing, so a position can make room for it; a panel of such
  # groups alone is given no rows, as ggplot2's working out of its violins' widths fails it, but
  # with `scale: :width`, which reads no density. Where the estimate fails, or a group with
  # quantiles has fewer than two rows inside the bounds, which R's `approx()` cannot read, the
  # whole panel is given no rows, as ggplot2 catches the failure per panel; without quantiles such
  # a group is one row of its x, its width and every other column missing. A weight that is not a
  # number is refused.
  #
  # Its orientation, ggplot2's `has_flipped_aes()` for a violin: `orientation` when it names an
  # axis; else along whichever axis is continuous where the other is discrete; else along y where
  # every group holds one x, or along x where every group holds one y, among all its rows; else
  # along y. A violin along x is computed as one along y, the two swapped and swapped back, as
  # ggplot2's `flip_data()` does.
  #
  # The frame does what scales with the rows (`Giggly.DataFrame`): it chooses the rows, takes each
  # group's count, x and y extent, distinct x and quantiles, and the estimate's passes; the
  # quantile rows, positions and widths are worked out on each group's curve, its own small
  # output. A group's constant columns are carried to its rows (`Giggly.Stat.Carry`), counted over
  # the groups given rows.

  # Every field is given by the function that adds the layer, its defaults there.
  @enforce_keys [
    :bandwidth,
    :adjust,
    :kernel,
    :trim,
    :bounds,
    :scale,
    :quantiles,
    :drop,
    :width,
    :orientation
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          bandwidth: :nrd0 | :nrd | float(),
          adjust: float(),
          kernel: Giggly.Stat.KernelDensity.kernel(),
          trim: boolean(),
          bounds: {float() | :neg_infinity, float() | :infinity},
          scale: :area | :count | :width,
          quantiles: :none | [number()],
          drop: boolean(),
          width: :none | number(),
          orientation: :none | :x | :y
        }

  # The aesthetics a violin's layer can use for its densities, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :weight, :width, :x, :y]

  # The aesthetics a violin's densities cannot be computed without, ggplot2's `required_aes =
  # c("x", "y")`.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  # The variables a violin's densities compute that a mapping's after_stat can read, as ggplot2
  # documents `stat_ydensity()`'s.
  @doc false
  @spec computed_variables() :: [atom()]
  def computed_variables, do: [:count, :density, :n, :quantile, :scaled, :violinwidth, :width]

  # The aesthetics a violin's densities consume, ggplot2's `dropped_aes`: a weight is spread over
  # the grid.
  @doc false
  @spec dropped_aesthetics() :: [atom()]
  def dropped_aesthetics, do: [:weight]

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.{Aesthetics, DataFrame}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Stat.{Carry, Curve, KernelDensity}

    # How many places a violin's curve is read at, `compute_density()`'s default `n`.
    @places 512

    # How many of the rule's bandwidths an untrimmed violin reaches past its group's extent.
    @untrimmed_reach 3

    # The share of its x values' range a violin of several x is drawn across.
    @range_share 0.9

    # The columns of a group's curve, in ggplot2's order, before its `y`.
    @curve_columns [:x, :density, :scaled, :ndensity, :count, :wdensity, :n]

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{}

    @impl Giggly.Stat
    def compute_layer(stat, frame, axes) do
      KernelDensity.check_weight(frame)
      check_width(frame)
      flipped = flipped?(stat.orientation, frame, axes)

      frame
      |> flip(flipped)
      |> violins(stat, flipped)
      |> flip(flipped)
    end

    # A mapped width is how wide a violin is drawn, so it must hold numbers, as a weight must.
    defp check_width(frame) do
      case DataFrame.dtypes(frame) do
        %{width: dtype} when dtype not in [:integer, :float, :null] ->
          raise ArgumentError,
                "a violin is drawn as wide as its group's width, so a width must be a number, " <>
                  "but the layer's width is a #{inspect(dtype)} column"

        _numbers_or_no_width ->
          :ok
      end
    end

    # Whether the violins run along x, drawn across y, as ggplot2's `has_flipped_aes()` decides a
    # violin's orientation.
    defp flipped?(:x, _frame, _axes), do: false
    defp flipped?(:y, _frame, _axes), do: true

    defp flipped?(:none, frame, axes) do
      y_discrete = discrete?(axes, :y)

      if discrete?(axes, :x) != y_discrete,
        do: y_discrete,
        else: one_y_per_group?(frame)
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

    defp violins(frame, stat, flipped) do
      names = DataFrame.names(frame)
      carried = Enum.reject(names, fn name -> name in [:x, :y, :width] end)
      rows = DataFrame.filter(frame, finite(names))
      given = if :width in names, do: [given_width: {:first, [:width]}], else: []

      figures =
        DataFrame.summarise(
          rows,
          [:panel, :group],
          Enum.concat(
            [
              rows: {:count, [:y]},
              x_low: {:min, [:x]},
              x_high: {:max, [:x]},
              x_count: {:n_distinct, [:x]},
              y_low: {:min, [:y]}
            ],
            given
          )
        )

      quantiles = quantiles(stat.quantiles, rows, DataFrame.row_count(figures))

      curves =
        rows
        |> DataFrame.join(
          DataFrame.select(figures, panel: :panel, group: :group, group_rows: :rows),
          [:panel, :group]
        )
        |> DataFrame.filter({:>, [:group_rows, 1]})
        |> DataFrame.select(estimated_columns(names))
        |> KernelDensity.curves(settings(stat))
        |> Map.new()

      groups =
        figures
        |> KernelDensity.rows_by_group([:rows, :x_low, :x_high, :x_count, :y_low])
        |> Enum.zip_with(quantiles, fn {key, group}, group_quantiles ->
          {key, violin(Map.get(curves, key), group, stat, group_quantiles)}
        end)
        |> without_failed_panels(curves, stat.scale)

      kept_rows = kept_rows(rows, figures, groups)
      constant = Carry.constant_columns(kept_rows, carried)
      firsts = for name <- constant, name not in [:panel, :group], do: {name, {:first, [name]}}
      carried_values = DataFrame.summarise(kept_rows, [:panel, :group], firsts)

      {given_groups, carried_width} =
        with_given_widths(groups, given != [], figures, kept_rows, stat)

      given_groups
      |> widened(stat.scale)
      |> output(carried_values, constant, {stat.quantiles, carried_width}, flipped)
    end

    # Each group's rows with the layer's mapped width, where it maps one, as ggplot2 carries it to
    # the groups whose own rows gave no width: those of one x where the stat is given none, and a
    # short group kept. Where it varies within any such group given rows, every row loses its
    # width, a group's of several x too, as ggplot2 drops a column that varies from the whole
    # table. Beside them, whether a group given rows carries the mapped width, so the table holds
    # a `width` though every one carried is missing, as ggplot2 binds the column it carries.
    defp with_given_widths(groups, false, _figures, _kept_rows, _stat), do: {groups, false}

    defp with_given_widths(groups, true, figures, kept_rows, stat) do
      reading =
        figures
        |> KernelDensity.rows_by_group([:rows, :x_count, :given_width])
        |> Map.new(fn {key, group} -> {key, reads_given_width?(group, stat)} end)

      readers =
        figures
        |> DataFrame.select(panel: :panel, group: :group)
        |> DataFrame.put(
          :reads,
          Enum.map(groups, fn {key, _rows} -> Map.fetch!(reading, key) end)
        )

      read_rows =
        kept_rows
        |> DataFrame.join(readers, [:panel, :group])
        |> DataFrame.filter(:reads)

      given_widths =
        figures
        |> KernelDensity.rows_by_group([:given_width])
        |> Map.new(fn {key, group} -> {key, group.given_width} end)

      constant = Carry.constant_columns(read_rows, [:width]) == [:width]

      given_groups =
        Enum.map(groups, fn {key, group_rows} ->
          {key, given_width(group_rows, constant, Map.fetch!(reading, key), given_widths[key])}
        end)

      {given_groups, constant and DataFrame.row_count(read_rows) > 0}
    end

    # A group's rows given the mapped width where it reads it, every row's width dropped where the
    # mapped width varies within a group reading it.
    defp given_width(group_rows, false, _reads, _width),
      do: Enum.map(group_rows, fn row -> %{row | width: :dropped} end)

    defp given_width(group_rows, true, true, width),
      do: Enum.map(group_rows, fn row -> %{row | width: width} end)

    defp given_width(group_rows, true, false, _width), do: group_rows

    # Whether a group's rows take the mapped width: a short one's, or one of one x where the stat
    # is given no width.
    defp reads_given_width?(%{rows: rows}, _stat) when rows < 2, do: true
    defp reads_given_width?(%{x_count: 1}, %{width: :none}), do: true
    defp reads_given_width?(_group, _stat), do: false

    # Whether a row's x, y and weight, where the layer maps one, are all finite.
    defp finite(names) do
      tested = Enum.filter([:x, :y, :weight], fn name -> name in names end)
      [first | rest] = Enum.map(tested, fn name -> {:is_finite, [name]} end)
      Enum.reduce(rest, first, fn test, both -> {:and, [both, test]} end)
    end

    # Each group's quantiles, in the groups' order, each `{probability, y}` in the quantiles'
    # order: the frame's type 7 quantile of the group's y at each, one pass a probability.
    defp quantiles(none_or_empty, _rows, groups) when none_or_empty in [:none, []],
      do: List.duplicate([], groups)

    defp quantiles(probabilities, rows, _groups) do
      probabilities
      |> Enum.map(fn probability ->
        rows
        |> DataFrame.summarise([:panel, :group],
          place: {:quantile, [:y], probability: probability}
        )
        |> DataFrame.pull(:place)
        |> Enum.map(fn place -> {probability, place} end)
      end)
      |> Enum.zip_with(fn group_quantiles -> group_quantiles end)
    end

    # The rows the estimate reads, its y as the values it estimates.
    defp estimated_columns(names) do
      weight = if :weight in names, do: [weight: :weight], else: []
      Enum.concat([panel: :panel, group: :group, x: :y], weight)
    end

    # The estimate as `stat_ydensity()` hands it to `compute_density()`: its bandwidth worked out
    # from all the group's rows, its curve across the group's extent, widened without `trim`, at
    # 512 places.
    defp settings(stat) do
      %{
        bandwidth: stat.bandwidth,
        bandwidth_rows: :all,
        adjust: stat.adjust,
        kernel: stat.kernel,
        n: @places,
        span: {:group, if(stat.trim, do: 0, else: @untrimmed_reach)},
        bounds: stat.bounds
      }
    end

    # A group's rows: none for one of fewer than two rows, or one of its x, y and rows with
    # `drop: false`; `:fails` where its estimate fails, or it has quantiles to read and too few
    # rows inside the bounds; else its curve and its quantiles' rows.
    defp violin(nil, group, stat, _quantiles) do
      if stat.drop,
        do: [],
        else: [
          Map.merge(missing_row(), %{x: position(group), y: group.y_low, n: group.rows})
        ]
    end

    defp violin(:dropped, _group, _stat, _quantiles), do: :fails

    defp violin([%{x: nil}], group, stat, _quantiles) do
      if stat.quantiles == :none,
        do: [Map.merge(missing_row(), %{x: position(group), width: width(group, stat)})],
        else: :fails
    end

    defp violin(curve, group, stat, quantiles) do
      x = position(group)
      width = width(group, stat)

      placed =
        Enum.map(curve, fn row ->
          row
          |> Map.merge(%{x: x, y: row.x, width: width})
          |> Map.put(:quantile, nil)
        end)

      quantile_rows =
        Enum.map(quantiles, fn {probability, place} -> read_at(placed, place, probability) end)

      places = Enum.map(quantile_rows, fn row -> row.y end)
      kept = Enum.reject(placed, fn row -> Enum.any?(places, fn place -> place == row.y end) end)
      Enum.concat(kept, quantile_rows)
    end

    defp missing_row do
      %{
        x: nil,
        density: nil,
        scaled: nil,
        ndensity: nil,
        count: nil,
        wdensity: nil,
        n: nil,
        y: nil,
        width: nil,
        quantile: nil
      }
    end

    # A quantile's row: every column of the group's curve read at the quantile's y.
    defp read_at(placed, place, probability) do
      read =
        Map.new([:width | @curve_columns], fn name ->
          knots = Enum.map(placed, fn row -> {row.y, Map.fetch!(row, name)} end)
          {name, read_column(knots, place)}
        end)

      Map.merge(read, %{y: place, quantile: probability})
    end

    # A column read at `place`, missing for a column of no values, a width the group lacks.
    defp read_column([{_place, nil} | _rest], _place_read), do: nil

    defp read_column(knots, place) do
      [value] = Curve.interpolate(knots, [place])
      value
    end

    # Where a group's violin stands: the middle of its x values' range, R's `mean(range(x))`, and so
    # its x where it holds one.
    defp position(group) do
      group.x_low
      |> Arithmetic.add(group.x_high)
      |> Arithmetic.divide(2)
    end

    # How wide a group's violin is: 0.9 of its x values' range where they are more than one, else
    # the stat's width, or none.
    defp width(%{x_count: 1}, %{width: :none}), do: nil
    defp width(%{x_count: 1}, %{width: width}), do: width

    defp width(group, _stat) do
      group.x_high
      |> Arithmetic.subtract(group.x_low)
      |> Arithmetic.multiply(@range_share)
    end

    # The groups, every group of a panel where one fails given no rows, as ggplot2 gives a panel
    # whose computing fails none: so too a panel none of whose groups was estimated, unless its
    # violins are as wide as their scaled densities, since ggplot2 works a violin's width out from a
    # `density` column such a panel never gets.
    defp without_failed_panels(groups, curves, scale) do
      failing = for {{panel, _group}, :fails} <- groups, into: MapSet.new(), do: panel
      estimated = for {{panel, _group}, _curve} <- curves, into: MapSet.new(), do: panel
      panels = for {{panel, _group}, _rows} <- groups, into: MapSet.new(), do: panel

      failed =
        if scale == :width,
          do: failing,
          else: MapSet.union(failing, MapSet.difference(panels, estimated))

      Enum.map(groups, fn {{panel, _group} = key, rows} ->
        if panel in failed, do: {key, []}, else: {key, rows}
      end)
    end

    # The rows of the groups given rows.
    defp kept_rows(rows, figures, groups) do
      flags = DataFrame.put(figures, :kept, Enum.map(groups, fn {_key, kept} -> kept != [] end))

      rows
      |> DataFrame.join(DataFrame.select(flags, panel: :panel, group: :group, kept: :kept), [
        :panel,
        :group
      ])
      |> DataFrame.filter(:kept)
    end

    # Each group's rows given their `violinwidth`, worked out across each panel's rows: the
    # density over the panel's greatest, R's `max(na.rm = TRUE)`; that times the rows over the
    # panel's most, missing where any is; or the scaled density.
    defp widened(groups, scale) do
      by_panel =
        groups
        |> Enum.group_by(fn {{panel, _group}, _rows} -> panel end, fn {_key, rows} -> rows end)
        |> Map.new(fn {panel, panel_rows} -> {panel, peaks(Enum.concat(panel_rows))} end)

      Enum.map(groups, fn {{panel, _group} = key, rows} ->
        peaks = Map.fetch!(by_panel, panel)
        {key, Enum.map(rows, fn row -> Map.put(row, :violinwidth, share(row, scale, peaks)) end)}
      end)
    end

    defp peaks(rows) do
      densities = for %{density: density} <- rows, is_number(density), do: density
      counts = Enum.map(rows, fn row -> row.n end)

      {if(densities == [], do: :neg_infinity, else: Enum.max(densities)),
       if(nil in counts or counts == [], do: nil, else: Enum.max(counts))}
    end

    defp share(row, :area, {peak, _most}), do: Arithmetic.divide(row.density, peak)

    defp share(row, :count, {peak, most}) do
      row.density
      |> Arithmetic.divide(peak)
      |> Arithmetic.multiply(row.n)
      |> Arithmetic.divide(most)
    end

    defp share(row, :width, _peaks), do: row.scaled

    # The stat's table: each group's rows in its group's order, the columns ggplot2's, a `width`
    # where some group has one or carries a mapped one and a `quantile` where the stat reads
    # quantiles, then each carried column's group's value, the violins' widths and the orientation.
    defp output(groups, carried_values, constant, {quantiles, carried_width}, flipped) do
      rows =
        Enum.flat_map(groups, fn {key, group_rows} ->
          Enum.map(group_rows, fn row -> Map.put(row, :key, key) end)
        end)

      widths =
        if carried_width or Enum.any?(rows, fn row -> row.width not in [nil, :dropped] end),
          do: [:width],
          else: []

      quantile = if quantiles == :none, do: [], else: [:quantile]

      computed =
        for name <- Enum.concat([@curve_columns, [:y], widths, quantile]),
            do: {name, Enum.map(rows, fn row -> Map.fetch!(row, name) end)}

      dtypes = DataFrame.dtypes(carried_values)

      carried =
        Enum.map(constant, fn name ->
          by_group =
            carried_values
            |> KernelDensity.rows_by_group([name])
            |> Map.new(fn {key, values} -> {key, values[name]} end)

          values = Enum.map(rows, fn row -> Map.fetch!(by_group, row.key) end)

          if Map.fetch!(dtypes, name) == :category,
            do: {name, values, DataFrame.category(carried_values, name)},
            else: {name, values}
        end)

      violinwidth = {:violinwidth, Enum.map(rows, fn row -> row.violinwidth end)}
      flipped_aes = {:flipped_aes, List.duplicate(flipped, length(rows))}

      [computed, carried, [violinwidth, flipped_aes]]
      |> Enum.concat()
      |> DataFrame.new()
    end
  end
end
