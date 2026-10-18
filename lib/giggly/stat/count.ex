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
  # Counting uses `:x` or `:y`, `:weight` and `:group`, and needs exactly one of `:x` and `:y`: it
  # counts along the one mapped, so a layer mapping `:y` alone is counted along y and drawn
  # horizontally, as ggplot2's `stat_count()` decides its orientation (`has_flipped_aes()` with
  # `main_is_orthogonal = FALSE`). It writes that orientation in a `flipped_aes` column, which the
  # bar geom and the positions read, and computes a horizontal layer as a vertical one, x and y
  # swapped and swapped back, as ggplot2's `flip_data()` does; y then takes no count, and x does.
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

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.{Aesthetics, DataFrame, Resolution}

    # ggplot2's default bar width, as a share of the spacing of the x positions.
    @width_share 0.9

    # The columns counting writes, in ggplot2's order.
    @computed [:count, :prop, :x, :width, :flipped_aes]

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{x: :count, y: :count}

    @impl Giggly.Stat
    def compute_layer(_stat, frame) do
      check_weight(frame)
      flipped = :x not in DataFrame.names(frame)

      frame
      |> flip(flipped)
      |> count(flipped)
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

    defp count(frame, flipped) do
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

      counted = Enum.flat_map(groups, fn rows -> count_group(rows, width, flipped) end)
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
    defp count_group([first | _rest] = rows, width, flipped) do
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
        Map.merge(first, %{
          count: count,
          prop: share(count, total),
          x: x,
          width: width,
          flipped_aes: flipped
        })
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
