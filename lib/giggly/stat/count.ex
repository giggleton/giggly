defmodule Giggly.Stat.Count do
  @moduledoc false

  # Counting, ggplot2's `stat_count()`, which `geom_bar()` computes with: one row for each distinct
  # x of each group in each panel, in that order, x ascending. Its `count` is the number of rows at
  # that x, or the sum of their weights where the layer maps `weight`, and its `prop` the count's
  # share of its group's total; its `width` is 0.9 of the closest spacing of the layer's x
  # positions, counting from zero (`Giggly.Resolution`), which the bar geom draws at. Counts are
  # doubles, as R's `rowsum()` gives them. y takes the count by default (`after_stat(count)`). It
  # takes no parameters yet. Run it through `Giggly.Stat`.
  #
  # Counting uses `:x`, `:weight` and `:group`, and needs `:x`.
  #
  # A row missing its x, or at an infinite one, is not counted, as ggplot2's `remove_missing()`
  # drops it; a missing weight adds nothing, as `rowsum(na.rm = TRUE)` skips it, and a group whose
  # counts are all zero has no proportions (NaN). Each other column of the table that holds one
  # value within every group is carried to that group's rows, as ggplot2 carries a group's constant
  # columns through a summary, `weight` included; one that varies within a group is dropped, where
  # ggplot2 also warns unless it is `weight`, which counting consumes.

  defstruct []

  @type t :: %__MODULE__{}

  # The aesthetics a layer that counts can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :weight, :x]

  # The aesthetics a layer that counts cannot be computed without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x]

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.{DataFrame, Resolution}

    # ggplot2's default bar width, as a share of the spacing of the x positions.
    @width_share 0.9

    # The columns counting writes, in ggplot2's order.
    @computed [:count, :prop, :x, :width]

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{x: :count, y: :count}

    @impl Giggly.Stat
    def compute_layer(_stat, frame) do
      names = DataFrame.names(frame)
      carried = Enum.reject(names, fn name -> name in @computed end)

      width =
        frame
        |> DataFrame.pull(:x)
        |> Resolution.of(zero: true)
        |> Kernel.*(@width_share)

      groups =
        names
        |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
        |> Enum.zip_with(fn values -> row(names, values) end)
        |> Enum.filter(fn row -> is_number(row.x) end)
        |> Enum.group_by(fn row -> {row.panel, row.group} end)
        |> Enum.sort_by(fn {panel_and_group, _rows} -> panel_and_group end)
        |> Enum.map(fn {_panel_and_group, rows} -> rows end)

      counted = Enum.flat_map(groups, fn rows -> count_group(rows, width) end)
      constant = Enum.filter(carried, fn name -> constant_in_every_group?(groups, name) end)

      columns =
        Enum.map(@computed ++ constant, fn name ->
          {name, Enum.map(counted, fn row -> Map.fetch!(row, name) end)}
        end)

      DataFrame.new(columns)
    end

    defp row(names, values) do
      names
      |> Enum.zip(values)
      |> Map.new()
    end

    # One row per distinct x of the group, x ascending, carrying the group's first row's columns.
    defp count_group([first | _rest] = rows, width) do
      counts =
        rows
        |> Enum.group_by(fn row -> row.x end, fn row -> weight(row) end)
        |> Enum.map(fn {x, weights} -> {x, Enum.reduce(weights, 0.0, &+/2)} end)
        |> Enum.sort_by(fn {x, _count} -> x end)

      total =
        counts
        |> Enum.map(fn {_x, count} -> abs(count) end)
        |> Enum.sum()

      Enum.map(counts, fn {x, count} ->
        Map.merge(first, %{count: count, prop: share(count, total), x: x, width: width})
      end)
    end

    # A row's weight, 1 where the layer maps none, nothing where its weight is missing.
    defp weight(%{weight: weight}) when is_number(weight), do: weight
    defp weight(%{weight: _missing}), do: 0.0
    defp weight(_row), do: 1.0

    defp share(_count, total) when total == 0, do: :nan
    defp share(count, total), do: count / total

    defp constant_in_every_group?(groups, name) do
      Enum.all?(groups, fn rows ->
        rows
        |> Enum.uniq_by(fn row -> Map.fetch!(row, name) end)
        |> length()
        |> Kernel.==(1)
      end)
    end
  end
end
