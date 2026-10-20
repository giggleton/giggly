defmodule Giggly.Stat.Sum do
  @moduledoc false

  # Counting at each place, ggplot2's `stat_sum()`, which `geom_count()` computes with: in each
  # panel, one row for each distinct combination of the layer's aesthetic columns, x and y and
  # `group` among them, its `n` the number of rows holding it, or the sum of their weights where
  # the layer maps `weight`, and its `prop` that count's share of its group's total in the panel.
  # The counts and the totals are summed by the frame (`Giggly.DataFrame.summarise/3`), with its
  # compensated sum, so they are the doubles R's `sum()` gives, which adds in extended precision.
  # size takes the count by default (`after_stat(n)`), and a mapping's after_stat reads `n` and
  # `prop`, the variables ggplot2 documents. It takes no parameters. Run it through `Giggly.Stat`.
  #
  # The columns it counts over are those ggplot2's list of aesthetics names (`.all_aesthetics`),
  # every one but `weight`, in the table's column order: a column the plot's mapping carries in
  # under a name the list lacks, `linewidth`, `stroke` or a nudge, is dropped and splits nothing,
  # as ggplot2's `count()` keeps only the columns it counts over. The rows come out panel by panel,
  # sorted by those columns one by one, each by its values with a missing one last, as `count()`
  # orders the combinations it finds (`id()`).
  #
  # A row missing its x or y, or at an infinite one, is not counted, as ggplot2's
  # `remove_missing(finite = TRUE)` drops it. A weight that is missing, or not a finite number,
  # makes its place's count missing, as R's `sum()` gives `NA` where it meets one, and its group's
  # proportions with it; so a point sized by its count is not drawn there. A group whose counts
  # total zero has a proportion of NaN for a count of zero and an infinite one for any other, as R
  # divides by zero.

  defstruct []

  @type t :: %__MODULE__{}

  # The aesthetics a layer that counts at each place can use, from its own mapping or the plot's:
  # those it needs, those it computes by default, and `group`.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :size, :weight, :x, :y]

  # The aesthetics a layer that counts at each place cannot be computed without, ggplot2's
  # `required_aes = c("x", "y")`.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  # The variables it computes that a mapping's after_stat can read, as ggplot2 documents
  # `stat_sum()`'s: `n` and `prop`.
  @doc false
  @spec computed_variables() :: [atom()]
  def computed_variables, do: [:n, :prop]

  # The aesthetics it consumes: a weight is summed into the count, so one given after the stat
  # reaches nothing.
  @doc false
  @spec dropped_aesthetics() :: [atom()]
  def dropped_aesthetics, do: [:weight]

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.DataFrame

    # ggplot2's `.all_aesthetics` in Giggly's spelling, less `weight`, which is summed, and the
    # base graphics names (`col`, `pch`, `lwd` and the rest) ggplot2 renames before any table holds
    # them.
    @counted_over [
      :alpha,
      :angle,
      :color,
      :fill,
      :group,
      :hjust,
      :label,
      :linetype,
      :lower,
      :max,
      :middle,
      :min,
      :radius,
      :sample,
      :shape,
      :size,
      :upper,
      :vjust,
      :width,
      :x,
      :xend,
      :xintercept,
      :xmax,
      :xmin,
      :y,
      :yend,
      :yintercept,
      :ymax,
      :ymin,
      :z
    ]

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{size: :n}

    @impl Giggly.Stat
    def compute_layer(_stat, frame) do
      check_weight(frame)

      counted_over =
        frame
        |> DataFrame.names()
        |> Enum.filter(fn name -> name in @counted_over end)

      counted =
        frame
        |> weighted()
        |> positioned()
        |> DataFrame.summarise([:panel | counted_over], n: {:sum, :weight})

      DataFrame.put(counted, :prop, shares(counted))
    end

    # A weight is summed, so it must hold numbers. `Giggly.Plot` refuses a column or a constant
    # that does not at the call; an expression's type is known only once it has run, so one that
    # computes anything else is refused here, where R's `sum()` refuses it inside the stat and
    # ggplot2 warns and draws nothing of the layer, which a pure pipeline cannot.
    defp check_weight(frame) do
      case DataFrame.dtypes(frame) do
        %{weight: dtype} when dtype not in [:integer, :float, :null] ->
          raise ArgumentError,
                "counting the rows at each place sums each row's weight, so a weight must be a " <>
                  "number, but the layer's weight is a #{inspect(dtype)} column"

        _numbers_or_no_weight ->
          :ok
      end
    end

    # The table with a weight of 1 in every row where the layer maps none, as ggplot2's `stat_sum()`
    # gives every row one.
    defp weighted(frame) do
      if :weight in DataFrame.names(frame),
        do: frame,
        else: DataFrame.put(frame, :weight, List.duplicate(1.0, DataFrame.row_count(frame)))
    end

    # The rows at a finite x and y, the only ones counted.
    defp positioned(frame) do
      kept =
        [DataFrame.pull(frame, :x), DataFrame.pull(frame, :y)]
        |> Enum.zip_with(fn [x, y] -> is_number(x) and is_number(y) end)
        |> Enum.with_index()
        |> Enum.flat_map(fn {finite, index} -> if finite, do: [index], else: [] end)

      DataFrame.slice(frame, kept)
    end

    # Each place's share of its group's total in its panel, the totals summed as the counts are.
    defp shares(counted) do
      panels = DataFrame.pull(counted, :panel)
      groups = DataFrame.pull(counted, :group)
      counts = DataFrame.pull(counted, :n)

      totals =
        counted
        |> DataFrame.summarise([:panel, :group], total: {:sum, :n})
        |> totals_by_group()

      Enum.zip_with([counts, panels, groups], fn [count, panel, group] ->
        share(count, Map.fetch!(totals, {panel, group}))
      end)
    end

    defp totals_by_group(totals) do
      [:panel, :group, :total]
      |> Enum.map(fn name -> DataFrame.pull(totals, name) end)
      |> Enum.zip_with(fn [panel, group, total] -> {{panel, group}, total} end)
      |> Map.new()
    end

    # A count's share of its group's total: missing where the total is, and for a total of zero NaN
    # for a count of zero and otherwise an infinity of the count's sign, as R divides by zero.
    defp share(_count, nil), do: nil
    defp share(count, total) when total != 0, do: count / total
    defp share(count, _zero) when count > 0, do: :infinity
    defp share(count, _zero) when count < 0, do: :neg_infinity
    defp share(_zero, _also_zero), do: :nan
  end
end
