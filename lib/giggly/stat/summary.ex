defmodule Giggly.Stat.Summary do
  @moduledoc false

  # Summarising y at each x, ggplot2's `stat_summary()`: for each panel, group and x, in that
  # order, one row with the x, the group, and the summary of the y values there, its `y`, `ymin`
  # and `ymax`, and `flipped_aes`. The summary is `fun_data`'s, a whole summary by name, where it
  # is given; otherwise `fun`, `fun_min` and `fun_max` each give one of `y`, `ymin` and `ymax`,
  # one not given missing, as ggplot2's `make_summary_fun()` makes them. A function is a summary's
  # name or a function of the values, a list of numbers in row order, returning a number.
  #
  # `{:mean_se, mult: mult}` is the mean and the mean less and plus `mult` standard errors, R's
  # `mean_se()`: the standard error the square root of the values' variance over their count, in
  # R's order, missing where there is one value. The Hmisc summaries are Hmisc's documented
  # methods, which ggplot2's `mean_cl_normal()`, `mean_sdl()`, `median_hilow()` and
  # `mean_cl_boot()` call:
  #
  #   * `{:mean_sdl, mult: mult}`, Hmisc's `smean.sdl()`: the centre the values' sum over their
  #     count, and it less and plus `mult` standard deviations, the deviation the square root of
  #     the squared distances from that centre summed and over the count less one. Against Hmisc
  #     5.3.0 on 3,003 random vectors it is digit for digit.
  #   * `{:mean_cl_normal, conf_int: level}`, `smean.cl.normal()`: that centre, and it less and
  #     plus t standard errors, the t holding `level` of the t distribution with one degree of
  #     freedom fewer than the values (`Giggly.Stat.TDistribution`), 0 at a level of 0, and the
  #     standard error the square root of that variance over the count; `{:mean_cl_normal, mult:
  #     mult}` takes `mult` in place of the t. Against Hmisc on the same vectors both ends are
  #     digit for digit in 2,869 and within a few units in the last place in the rest, where Hmisc
  #     rounds its steps otherwise.
  #   * `{:median_hilow, conf_int: level}`, `smedian.hilow()`: the type 7 quantiles at one half
  #     and at `(1 - level) / 2` and `(1 + level) / 2`, so one value is all three.
  #   * `{:mean_cl_boot, conf_int: level, resamples: resamples, seed: seed}`, `smean.cl.boot()`,
  #     the basic nonparametric bootstrap: R's mean, and the type 7 quantiles at `(1 - level) / 2`
  #     and `(1 + level) / 2` of the means of `resamples` resamples, each as many values as the
  #     position holds, drawn from them with replacement. The draws are `:rand`'s `exsss`,
  #     never OTP's default, each position's starting afresh from `seed`, so its interval
  #     depends only on its values, their order and the seed; a resample's values are drawn in
  #     turn, each index `:rand.uniform_s/2` of the count. R's random numbers are never
  #     reproduced, so the ends differ from R's by sampling.
  #
  # The three but `median_hilow` leave the ends missing where a position holds one value, as
  # Hmisc gives `NA`. By name, `:mean` is R's `mean()`, `:median` its
  # `median()`, which for numbers is the type 7 quantile at one half, digit for digit, and `:min`
  # and `:max` the least and the greatest, of the column's type.
  #
  # A row missing its x or y, or at an infinite one, is left out first, as ggplot2's
  # `compute_layer()` drops it with `finite = TRUE`. Every other column is carried cell by cell, as
  # ggplot2's `uniquecols()` keeps those holding one value in each group and x: the cell's value
  # where it holds one, missing where it holds more, and a column holding more in every cell left
  # out. That is not `Giggly.Stat.Carry`'s rule, which ggplot2's default `compute_panel()` applies
  # to a whole group. The columns a summary writes are never carried; any other is, a range it
  # does not write among them, as R carries it.
  #
  # Its orientation, ggplot2's `has_flipped_aes()` with `stat_summary()`'s defaults: `orientation`
  # when it names an axis; else along y, the summary of x at each y, where y alone is discrete;
  # else along x. A summary along y is computed as one along x, the two swapped and swapped back,
  # as ggplot2's `flip_data()` does.
  #
  # The frame chooses the rows and computes each cell's aggregates (`Giggly.DataFrame`); a
  # function's values come to it through the frame's `list` aggregate, as no engine could run it,
  # and so do a bootstrap's, whose resample means go back to the frame for their quantiles; a
  # standard deviation's squared distances are the frame's, from each row's position's centre,
  # and the standard errors are worked out on the table of cells, so the stat never pulls a column
  # of its input.

  # Every field is given by the function that adds the layer, `fun_data` recorded
  # `{:mean_se, mult: 1.0}` where no summary is given, as ggplot2 defaults to `mean_se()`.
  @enforce_keys [:fun_data, :fun, :fun_min, :fun_max, :orientation]
  defstruct @enforce_keys

  @typedoc "One of a summary's values: a summary by name, or a function of the values."
  @type summary_function :: :mean | :median | :min | :max | ([number()] -> number())

  @typedoc "A whole summary by name, with every one of its arguments."
  @type summary_data ::
          {:mean_se, [mult: float()]}
          | {:mean_cl_normal, [conf_int: float()] | [mult: float()]}
          | {:mean_sdl, [mult: float()]}
          | {:median_hilow, [conf_int: float()]}
          | {:mean_cl_boot, [conf_int: float(), resamples: pos_integer(), seed: integer()]}

  @type t :: %__MODULE__{
          fun_data: :none | summary_data(),
          fun: :none | summary_function(),
          fun_min: :none | summary_function(),
          fun_max: :none | summary_function(),
          orientation: :none | :x | :y
        }

  # The aesthetics a summary's layer can use for its summary, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :x, :y]

  # The aesthetics a summary cannot be computed without, ggplot2's `required_aes = c("x", "y")`.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  # The summary's columns, which ggplot2 documents no after_stat of, so a mapping reads none.
  @doc false
  @spec computed_variables() :: [atom()]
  def computed_variables, do: []

  # The aesthetics the summary consumes: none, as ggplot2's `StatSummary` drops none.
  @doc false
  @spec dropped_aesthetics() :: [atom()]
  def dropped_aesthetics, do: []

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.{Aesthetics, DataFrame}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Stat.TDistribution

    # The cells the stat summarises by, and the columns it writes there, which it never carries.
    @cells [:panel, :group, :x]
    @written [:x, :group, :y, :ymin, :ymax, :panel]

    # The algorithm a bootstrap's draws come from, named so a change in OTP's default moves none.
    @algorithm :exsss

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{}

    @impl Giggly.Stat
    def compute_layer(stat, frame, axes) do
      flipped = flipped?(stat.orientation, axes)

      frame
      |> flip(flipped)
      |> summarised(stat, flipped)
      |> flip(flipped)
    end

    # Whether the summary runs along y, as ggplot2's `has_flipped_aes()` decides it for
    # `stat_summary()`: by the orientation given, or else where y alone is discrete.
    defp flipped?(:x, _axes), do: false
    defp flipped?(:y, _axes), do: true
    defp flipped?(:none, axes), do: discrete?(axes, :y) and not discrete?(axes, :x)

    defp discrete?(axes, axis),
      do: Enum.any?(axes, fn {_panel, panel_axes} -> Map.fetch!(panel_axes, axis).discrete end)

    defp flip(frame, false), do: frame

    defp flip(frame, true) do
      renames =
        frame
        |> DataFrame.names()
        |> Aesthetics.flipped()

      DataFrame.select(frame, renames)
    end

    defp summarised(frame, stat, flipped) do
      names = DataFrame.names(frame)
      carried = Enum.reject(names, fn name -> name in @written end)
      rows = DataFrame.filter(frame, {:and, [{:is_finite, [:x]}, {:is_finite, [:y]}]})
      firsts = for name <- carried, do: {name, {:first, [name]}}

      cells =
        rows
        |> DataFrame.summarise(@cells, aggregates(stat) ++ firsts)
        |> summary(rows, stat)

      cells
      |> carry(rows, carried)
      |> DataFrame.put(:flipped_aes, List.duplicate(flipped, DataFrame.row_count(cells)))
    end

    # The aggregates the summary is worked out from: a whole summary's, or each value's by its
    # name, the values in a list for a function.
    defp aggregates(%{fun_data: {:mean_se, _options}}),
      do: [mean: {:mean, [:y]}, variance: {:variance, [:y]}, count: {:count, [:y]}]

    defp aggregates(%{fun_data: {summary, _options}})
         when summary in [:mean_cl_normal, :mean_sdl],
         do: [sum: {:sum, [:y]}, count: {:count, [:y]}]

    defp aggregates(%{fun_data: {:median_hilow, conf_int: level}}) do
      [
        y: {:quantile, [:y], probability: 0.5},
        ymin: {:quantile, [:y], probability: (1 - level) / 2},
        ymax: {:quantile, [:y], probability: (1 + level) / 2}
      ]
    end

    defp aggregates(%{fun_data: {:mean_cl_boot, _options}}),
      do: [mean: {:mean, [:y]}, values: {:list, [:y]}]

    defp aggregates(%{fun_data: :none} = stat) do
      named =
        for {column, summary} <- values(stat),
            is_atom(summary),
            summary != :none,
            do: {column, aggregate(summary)}

      listed =
        stat
        |> values()
        |> Enum.any?(fn {_column, summary} -> is_function(summary) end)

      if listed, do: [{:values, {:list, [:y]}} | named], else: named
    end

    defp values(stat), do: [ymin: stat.fun_min, y: stat.fun, ymax: stat.fun_max]

    defp aggregate(:mean), do: {:mean, [:y]}
    defp aggregate(:median), do: {:quantile, [:y], probability: 0.5}
    defp aggregate(:min), do: {:min, [:y]}
    defp aggregate(:max), do: {:max, [:y]}

    # The table of cells with `y`, `ymin` and `ymax`, each worked out on its rows, one a cell.
    defp summary(cells, _rows, %{fun_data: {:mean_se, mult: mult}}) do
      means = DataFrame.pull(cells, :mean)

      variances = DataFrame.pull(cells, :variance)
      counts = DataFrame.pull(cells, :count)

      errors =
        Enum.zip_with(variances, counts, fn variance, count ->
          standard_error(variance, count, mult)
        end)

      cells
      |> DataFrame.put(:y, means)
      |> DataFrame.put(:ymin, Enum.zip_with(means, errors, &Arithmetic.subtract/2))
      |> DataFrame.put(:ymax, Enum.zip_with(means, errors, &Arithmetic.add/2))
    end

    defp summary(cells, rows, %{fun_data: {summary, arguments}})
         when summary in [:mean_cl_normal, :mean_sdl] do
      counts = DataFrame.pull(cells, :count)

      centres =
        cells
        |> DataFrame.pull(:sum)
        |> Enum.zip_with(counts, &Arithmetic.divide/2)

      halves =
        cells
        |> DataFrame.put(:centre, centres)
        |> squared_distances(rows)
        |> Enum.zip_with(counts, fn squares, count ->
          half_width(summary, arguments, squares, count)
        end)

      put_interval(cells, centres, halves)
    end

    defp summary(cells, _rows, %{fun_data: {:median_hilow, _options}}), do: cells

    defp summary(cells, _rows, %{fun_data: {:mean_cl_boot, options}}) do
      [conf_int: level, resamples: resamples, seed: seed] = options
      values = DataFrame.pull(cells, :values)

      means =
        values
        |> Enum.with_index()
        |> Enum.flat_map(fn {cell_values, cell} ->
          cell_values
          |> resample_means(resamples, seed)
          |> Enum.map(fn mean -> {cell, mean} end)
        end)

      resampled =
        DataFrame.new(
          cell: Enum.map(means, fn {cell, _mean} -> cell end),
          mean: Enum.map(means, fn {_cell, mean} -> mean end)
        )

      ends =
        DataFrame.summarise(resampled, [:cell],
          ymin: {:quantile, [:mean], probability: (1 - level) / 2},
          ymax: {:quantile, [:mean], probability: (1 + level) / 2}
        )

      cells
      |> DataFrame.put(:y, DataFrame.pull(cells, :mean))
      |> DataFrame.put(:ymin, bootstrap_ends(DataFrame.pull(ends, :ymin), values))
      |> DataFrame.put(:ymax, bootstrap_ends(DataFrame.pull(ends, :ymax), values))
    end

    defp summary(cells, _rows, %{fun_data: :none} = stat) do
      stat
      |> values()
      |> Enum.reduce(cells, fn {column, summary}, summarised ->
        DataFrame.put(summarised, column, summary_values(summarised, column, summary))
      end)
    end

    defp summary_values(cells, _column, :none),
      do: List.duplicate(nil, DataFrame.row_count(cells))

    defp summary_values(cells, _column, summary) when is_function(summary, 1) do
      cells
      |> DataFrame.pull(:values)
      |> Enum.map(fn values -> number!(summary.(values)) end)
    end

    defp summary_values(cells, column, _named), do: DataFrame.pull(cells, column)

    # Each cell's squared distances of its rows' values from its centre, summed, in the cells'
    # order, as both are sorted by the cells' columns.
    defp squared_distances(cells, rows) do
      centres =
        DataFrame.select(cells, Enum.map([:centre | @cells], fn name -> {name, name} end))

      rows
      |> DataFrame.select(Enum.map([:y | @cells], fn name -> {name, name} end))
      |> DataFrame.join(centres, @cells)
      |> DataFrame.mutate(distance: {:-, [:y, :centre]})
      |> DataFrame.mutate(squared: {:*, [:distance, :distance]})
      |> DataFrame.summarise(@cells, squares: {:sum, [:squared]})
      |> DataFrame.pull(:squares)
    end

    # Half an interval's width, standard deviations' or standard errors', missing for one value.
    defp half_width(_summary, _arguments, _squares, 1), do: nil

    defp half_width(:mean_sdl, [mult: mult], squares, count),
      do: Arithmetic.multiply(mult, deviation(squares, count))

    defp half_width(:mean_cl_normal, [mult: mult], squares, count),
      do: Arithmetic.multiply(mult, error(squares, count))

    defp half_width(:mean_cl_normal, [conf_int: level], squares, count) do
      level
      |> t_quantile(count - 1)
      |> Arithmetic.multiply(error(squares, count))
    end

    defp deviation(squares, count) do
      squares
      |> Arithmetic.divide(count - 1)
      |> :math.sqrt()
    end

    defp error(squares, count) do
      squares
      |> Arithmetic.divide(count - 1)
      |> Arithmetic.divide(count)
      |> :math.sqrt()
    end

    defp t_quantile(level, _degrees_of_freedom) when level == 0, do: 0.0

    defp t_quantile(level, degrees_of_freedom),
      do: TDistribution.central_quantile(level, degrees_of_freedom)

    defp put_interval(cells, centres, halves) do
      cells
      |> DataFrame.put(:y, centres)
      |> DataFrame.put(:ymin, Enum.zip_with(centres, halves, &Arithmetic.subtract/2))
      |> DataFrame.put(:ymax, Enum.zip_with(centres, halves, &Arithmetic.add/2))
    end

    # The means of `resamples` resamples of `values`, each drawn from a stream started afresh
    # from `seed`, a resample's values in turn.
    defp resample_means(values, resamples, seed) do
      pool = List.to_tuple(values)
      count = tuple_size(pool)

      {means, _stream} =
        Enum.map_reduce(1..resamples, :rand.seed_s(@algorithm, seed), fn _resample, stream ->
          {total, stream} =
            Enum.reduce(1..count, {0.0, stream}, fn _draw, {total, stream} ->
              {index, stream} = :rand.uniform_s(count, stream)
              {Arithmetic.add(total, elem(pool, index - 1)), stream}
            end)

          {Arithmetic.divide(total, count), stream}
        end)

      means
    end

    # A bootstrap's ends, missing where its position holds one value.
    defp bootstrap_ends(ends, values) do
      Enum.zip_with(ends, values, fn
        _end, [_value] -> nil
        bound, _values -> bound
      end)
    end

    # R's `mult * sqrt(var(x) / length(x))`, missing where the variance is, for a single value.
    defp standard_error(nil, _count, _mult), do: nil

    defp standard_error(variance, count, mult) do
      variance
      |> Arithmetic.divide(count)
      |> :math.sqrt()
      |> then(fn root -> Arithmetic.multiply(mult, root) end)
    end

    defp number!(value) when is_number(value), do: value

    defp number!(value) do
      raise ArgumentError,
            "a summary function must return a number for the values at each x, got: " <>
              inspect(value)
    end

    # The cells with each carried column, as ggplot2's `uniquecols()` keeps it cell by cell, in
    # ggplot2's order: the summary first, the carried columns after.
    defp carry(cells, rows, carried) do
      distinct =
        DataFrame.summarise(rows, @cells, for(name <- carried, do: {name, {:n_distinct, [name]}}))

      kept =
        carried
        |> Enum.map(fn name -> {name, DataFrame.pull(distinct, name)} end)
        |> Enum.filter(fn {_name, counts} -> Enum.member?(counts, 1) end)

      selected =
        DataFrame.select(
          cells,
          Enum.map(@written, fn name -> {name, name} end) ++
            Enum.map(kept, fn {name, _counts} -> {name, name} end)
        )

      Enum.reduce(kept, selected, fn {name, counts}, carrying ->
        cell_values(carrying, name, counts)
      end)
    end

    # A carried column missing in each cell holding more than one of its values.
    defp cell_values(cells, name, counts) do
      values =
        cells
        |> DataFrame.pull(name)
        |> Enum.zip_with(counts, &in_cell/2)

      put_like(cells, name, values)
    end

    defp in_cell(value, 1), do: value
    defp in_cell(_value, _count), do: nil

    defp put_like(cells, name, values) do
      case DataFrame.dtypes(cells) do
        %{^name => :category} ->
          DataFrame.put(cells, name, values, DataFrame.category(cells, name))

        _other ->
          DataFrame.put(cells, name, values)
      end
    end
  end
end
