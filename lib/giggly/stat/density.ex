defmodule Giggly.Stat.Density do
  @moduledoc false

  # Densities, ggplot2's `stat_density()`, which `geom_density()` computes with: for each group in
  # each panel, in that order, a kernel density estimate, R's `density()`, `n` rows evenly spaced
  # across the panel's axis short of its widening, or across the group's own extent with `trim`,
  # each its place `x`, its `density`, `scaled` and `ndensity`, the density over the group's
  # greatest, `count`, the density times the group's rows, `wdensity`, the density times the
  # weights' total, the rows `n`, and `flipped_aes`. y takes the density by default
  # (`after_stat(density)`), and a mapping's after_stat reads `density`, `count`, `scaled`,
  # `ndensity`, `wdensity` and `n`, the variables ggplot2 documents. It runs along whichever of x
  # and y is mapped, along y with the two swapped and swapped back, as ggplot2's `flip_data()`
  # does. Run it through `Giggly.Stat`.
  #
  # The estimate is ggplot2's `compute_density()` (`Giggly.Stat.KernelDensity`), as
  # `stat_density()` hands it over: its bandwidth worked out from the rows inside the bounds, its
  # curve across the panel's axis short of its widening, or the group's own extent with `trim`. A
  # row missing its x, or at an infinite one, is left out first, as ggplot2's `remove_missing()`
  # drops it, and a panel whose estimate fails is given no rows. A group's constant columns are
  # carried to its rows (`Giggly.Stat.Carry`), counted over the groups given rows.

  @enforce_keys [:bandwidth, :adjust, :kernel, :n, :trim, :bounds]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          bandwidth: :nrd0 | :nrd | float(),
          adjust: float(),
          kernel: Giggly.Stat.KernelDensity.kernel(),
          n: pos_integer(),
          trim: boolean(),
          bounds: {float() | :neg_infinity, float() | :infinity}
        }

  # The aesthetics a layer of densities can use for its estimate, from its own mapping or the
  # plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :weight, :x, :y]

  # The aesthetics a density cannot be computed without: one of x and y, ggplot2's `required_aes =
  # "x|y"`.
  @doc false
  @spec required_aesthetics() :: [[atom()]]
  def required_aesthetics, do: [[:x, :y]]

  # The aesthetics of which a layer of densities maps at most one, since ggplot2's density drops
  # the other and its geom then fails without it.
  @doc false
  @spec exclusive_aesthetics() :: [[atom()]]
  def exclusive_aesthetics, do: [[:x, :y]]

  # The variables a density computes that a mapping's after_stat can read, as ggplot2 documents
  # `stat_density()`'s.
  @doc false
  @spec computed_variables() :: [atom()]
  def computed_variables, do: [:count, :density, :n, :ndensity, :scaled, :wdensity]

  # The aesthetics a density consumes, ggplot2's `dropped_aes`: a weight is spread over the grid.
  @doc false
  @spec dropped_aesthetics() :: [atom()]
  def dropped_aesthetics, do: [:weight]

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.{Aesthetics, DataFrame}
    alias Giggly.Stat.{Carry, KernelDensity}

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{x: :density, y: :density}

    @impl Giggly.Stat
    def compute_layer(stat, frame, axes) do
      KernelDensity.check_weight(frame)
      flipped = :x not in DataFrame.names(frame)
      axis = if flipped, do: :y, else: :x
      along = Map.new(axes, fn {panel, panel_axes} -> {panel, Map.fetch!(panel_axes, axis)} end)

      frame
      |> flip(flipped)
      |> densities(stat, along, flipped)
      |> flip(flipped)
    end

    defp flip(frame, false), do: frame

    defp flip(frame, true) do
      renames =
        frame
        |> DataFrame.names()
        |> Aesthetics.flipped()

      DataFrame.select(frame, renames)
    end

    defp densities(frame, stat, along, flipped) do
      # Every column but the place, which the estimate writes afresh: a stat's table holds
      # aesthetics, `panel` and `group`, none of them another column a density writes.
      carried =
        frame
        |> DataFrame.names()
        |> Enum.reject(fn name -> name == :x end)

      rows = DataFrame.filter(frame, {:is_finite, [:x]})
      curves = KernelDensity.curves(rows, settings(stat, along))
      kept_rows = kept_rows(rows, curves)
      constant = Carry.constant_columns(kept_rows, carried)
      firsts = for name <- constant, name not in [:panel, :group], do: {name, {:first, [name]}}
      groups = DataFrame.summarise(kept_rows, [:panel, :group], firsts)
      by_group = Map.new(curves)

      groups
      |> KernelDensity.rows_by_group([])
      |> Enum.map(fn {key, _group} -> {key, Map.fetch!(by_group, key)} end)
      |> output(groups, constant, flipped)
    end

    # The estimate as `stat_density()` hands it to `compute_density()`: its curve across the
    # panel's axis, or the group's own extent with `trim`, its bandwidth from the rows inside the
    # bounds.
    defp settings(stat, along) do
      %{
        bandwidth: stat.bandwidth,
        bandwidth_rows: :inside,
        adjust: stat.adjust,
        kernel: stat.kernel,
        n: stat.n,
        span: if(stat.trim, do: {:group, 0}, else: {:axis, along}),
        bounds: stat.bounds
      }
    end

    # The rows of the groups given rows, those of no panel that fails.
    defp kept_rows(rows, curves) do
      flags =
        rows
        |> DataFrame.summarise([:panel, :group], [])
        |> DataFrame.put(:kept, Enum.map(curves, fn {_key, curve} -> curve != :dropped end))

      rows
      |> DataFrame.join(flags, [:panel, :group])
      |> DataFrame.filter(:kept)
    end

    # The stat's table: each group's curve's rows in its group's order, the columns ggplot2's,
    # then each carried column's group's value.
    defp output(curves, groups, constant, flipped) do
      rows =
        Enum.flat_map(curves, fn {key, curve} ->
          Enum.map(curve, fn row -> Map.put(row, :key, key) end)
        end)

      computed =
        for name <- [:x, :density, :scaled, :ndensity, :count, :wdensity, :n],
            do: {name, Enum.map(rows, fn row -> Map.fetch!(row, name) end)}

      flipped_aes = {:flipped_aes, List.duplicate(flipped, length(rows))}
      dtypes = DataFrame.dtypes(groups)

      carried =
        Enum.map(constant, fn name ->
          by_group =
            Map.new(KernelDensity.rows_by_group(groups, [name]), fn {key, values} ->
              {key, values[name]}
            end)

          values = Enum.map(rows, fn row -> Map.fetch!(by_group, row.key) end)

          if Map.fetch!(dtypes, name) == :category,
            do: {name, values, DataFrame.category(groups, name)},
            else: {name, values}
        end)

      [computed, [flipped_aes], carried]
      |> Enum.concat()
      |> DataFrame.new()
    end
  end
end
