defmodule Giggly.Stat.Count do
  @moduledoc false

  # Counting, ggplot2's `stat_count()`, which `geom_bar()` computes with: one row for each distinct
  # x of each group in each panel, in that order, x ascending. Its `count` is the number of rows at
  # that x, or the sum of their weights where the layer maps `weight`, and its `prop` the count's
  # share of its group's total; its `width` is the stat's `width`, the one a layer sets, or else 0.9
  # of the closest spacing of the layer's x positions, counting from zero (`Giggly.Resolution`),
  # which the bar geom draws at, as `stat_count()` takes its `width` parameter. The frame sums
  # them (`Giggly.DataFrame.summarise/3`): the counts in floats in row order, the doubles R's
  # `rowsum()` gives, and each group's total, the sum of its counts' magnitudes, with its
  # compensated sum, as R's `sum()` adds in extended precision. The frame also chooses the rows,
  # weighs them and finds the columns constant within each group (`filter/2`, `mutate/2`,
  # `n_distinct` and `first`), and the width is read from the counted table's x, which holds the
  # layer's distinct x positions, so counting never pulls a column of its input. y takes the count
  # by default (`after_stat(count)`), and a mapping's after_stat reads `count` and `prop`, the
  # variables ggplot2 documents. Run it through `Giggly.Stat`.
  #
  # Counting uses `:x` or `:y`, `:weight` and `:group`, and needs exactly one of `:x` and `:y`: it
  # counts along the one mapped, so a layer mapping `:y` alone is counted along y and drawn
  # horizontally, as ggplot2's `stat_count()` decides its orientation (`has_flipped_aes()` with
  # `main_is_orthogonal = FALSE`). It writes that orientation in a `flipped_aes` column, which the
  # bar geom and the positions read, and computes a horizontal layer as a vertical one, x and y
  # swapped and swapped back, as ggplot2's `flip_data()` does; y then takes no count, and x does.
  #
  # A row missing its x, or at an infinite one, is not counted, as ggplot2's `remove_missing()`
  # drops it; a missing weight, `nil` or NaN, adds nothing, as `rowsum(na.rm = TRUE)` skips it, and
  # an infinite one makes its count infinite, as R adds it; the proportions divide as R divides
  # (`Giggly.DataFrame.Arithmetic`), so a group whose counts are all zero has none (NaN), and one
  # with an infinite count has NaN for it and 0 for the rest. Each other column of the table that
  # holds one value within every group is carried to that group's rows, as ggplot2 carries a
  # group's constant columns through a summary, `weight` included; one that varies within a group
  # is dropped, where ggplot2 also warns unless it is `weight`, which counting consumes.

  # Every field is given by the function that adds the layer, its defaults there.
  @enforce_keys [:width]
  defstruct @enforce_keys

  @type t :: %__MODULE__{width: :none | number()}

  # The aesthetics a layer that counts can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :weight, :x, :y]

  # The aesthetics a layer that counts cannot be computed without: one of x and y, ggplot2's
  # `required_aes = "x|y"`.
  @doc false
  @spec required_aesthetics() :: [[atom()]]
  def required_aesthetics, do: [[:x, :y]]

  # The aesthetics of which a layer that counts maps at most one, as ggplot2's `stat_count()`
  # refuses x and y together: it counts along one, and the count is the other.
  @doc false
  @spec exclusive_aesthetics() :: [[atom()]]
  def exclusive_aesthetics, do: [[:x, :y]]

  # The variables counting computes that a mapping's after_stat can read, as ggplot2 documents
  # `stat_count()`'s: `count` and `prop`. Its table holds others, the position counted at, `width`
  # and `flipped_aes`, which ggplot2 documents for no aesthetic to read.
  @doc false
  @spec computed_variables() :: [atom()]
  def computed_variables, do: [:count, :prop]

  # The aesthetics counting consumes, ggplot2's `dropped_aes`: a weight is summed into the count, so
  # one given after the stat reaches nothing.
  @doc false
  @spec dropped_aesthetics() :: [atom()]
  def dropped_aesthetics, do: [:weight]

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.{Aesthetics, DataFrame, Resolution}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Stat.Carry

    # ggplot2's default bar width, as a share of the spacing of the x positions.
    @width_share 0.9

    # The columns counting writes, in ggplot2's order.
    @computed [:count, :prop, :x, :width, :flipped_aes]

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{x: :count, y: :count}

    @impl Giggly.Stat
    def compute_layer(stat, frame, _axes) do
      check_weight(frame)
      flipped = :x not in DataFrame.names(frame)

      frame
      |> flip(flipped)
      |> count(stat.width, flipped)
      |> flip(flipped)
    end

    # A weight is summed, so it must hold numbers. `Giggly.Plot` refuses a column or a constant
    # that does not at the call; an expression's type is known only once it has run, so one that
    # computes anything else is refused here, where ggplot2's `rowsum()` refuses it inside the
    # stat and ggplot2 warns and draws nothing of the layer, which a pure pipeline cannot.
    defp check_weight(frame) do
      case DataFrame.dtypes(frame) do
        %{weight: dtype} when dtype not in [:integer, :float, :null] ->
          raise ArgumentError,
                "counting sums each row's weight, so a weight must be a number, but the " <>
                  "layer's weight is a #{inspect(dtype)} column"

        _numbers_or_no_weight ->
          :ok
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

    defp count(frame, set_width, flipped) do
      carried =
        frame
        |> DataFrame.names()
        |> Enum.reject(fn name -> name in @computed end)

      positioned = DataFrame.filter(frame, {:is_finite, [:x]})
      constant = Carry.constant_columns(positioned, carried)

      firsts =
        for name <- constant, name not in [:panel, :group], do: {name, {:first, [name]}}

      counted =
        positioned
        |> weighted()
        |> DataFrame.summarise(
          [:panel, :group, :x],
          [{:count, {:sum, [:weight], summation: :plain, missing: :skip}} | firsts]
        )

      groups = panels_and_groups(counted)
      counts = DataFrame.pull(counted, :count)
      totals = totals_by_group(counted, counts)
      rows = DataFrame.row_count(counted)

      width = width(set_width, counted)

      prop =
        Enum.zip_with(counts, groups, fn count, group ->
          Arithmetic.divide(count, Map.fetch!(totals, group))
        end)

      counted
      |> DataFrame.put(:prop, prop)
      |> DataFrame.put(:width, List.duplicate(width, rows))
      |> DataFrame.put(:flipped_aes, List.duplicate(flipped, rows))
      |> DataFrame.select(Enum.map(@computed ++ constant, fn name -> {name, name} end))
    end

    # Each bar's width: the one the layer sets, or else 0.9 of the spacing of the counted table's
    # x positions, the layer's distinct ones, counting from zero.
    defp width(set_width, _counted) when is_number(set_width), do: set_width

    defp width(:none, counted) do
      counted
      |> DataFrame.pull(:x)
      |> Resolution.of(zero: true)
      |> Kernel.*(@width_share)
    end

    # The table with each row's weight, 1 where the layer maps none, as ggplot2's `stat_count()`
    # weighs each row 1.
    defp weighted(frame) do
      if :weight in DataFrame.names(frame),
        do: frame,
        else: DataFrame.mutate(frame, weight: 1.0)
    end

    # Each group's total, the sum of its counts' magnitudes, as ggplot2's `stat_count()` divides by
    # `sum(abs(count))`, which R adds in extended precision.
    defp totals_by_group(counted, counts) do
      totals =
        counted
        |> DataFrame.put(:magnitude, Enum.map(counts, &Arithmetic.magnitude/1))
        |> DataFrame.summarise([:panel, :group], total: {:sum, [:magnitude]})

      [:panel, :group, :total]
      |> Enum.map(fn name -> DataFrame.pull(totals, name) end)
      |> Enum.zip_with(fn [panel, group, total] -> {{panel, group}, total} end)
      |> Map.new()
    end

    # Each row's panel and group, in row order.
    defp panels_and_groups(frame) do
      panels = DataFrame.pull(frame, :panel)
      groups = DataFrame.pull(frame, :group)
      Enum.zip(panels, groups)
    end
  end
end
