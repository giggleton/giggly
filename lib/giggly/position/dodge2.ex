defmodule Giggly.Position.Dodge2 do
  @moduledoc false

  # Dodging by clusters, ggplot2's `position_dodge2()`: the bars at one position set side by side,
  # each its share of their widths, with a gap between them, as `geom_bar(position = "dodge2")`
  # sets them. Its fields are R's parameters but `width`, which R reads only for a mark without
  # edges: `preserve`, `:total` or `:single`; `padding`, from 0 to 1; and `reverse`, each given by
  # `Giggly.Plot.position_dodge2/1`, whose defaults are R's. Run it through `Giggly.Position`.
  #
  # It works on the layer's rows as lists, since they are its marks, a row each (design-log §4, the
  # entry beginning "Dodging by clusters computes on lists"), in R's order and R's arithmetic
  # (`Giggly.DataFrame.Arithmetic`), so its doubles are R's. Each panel's rows are sorted by x, a
  # missing one last, then by group, the highest first with `reverse`, and come out in that order,
  # as R's do. The bars whose spans overlap or meet form a cluster, found as ggplot2's
  # `find_x_overlaps()` finds them: walking the sorted bars, one starts a new cluster where its
  # `xmin` is beyond every earlier `xmax`, or on it for a bar with width. A bar's width is divided by
  # the number of bars in its cluster (`:total`), or by the most bars at one x in any panel
  # (`:single`), and a cluster's bars are laid side by side in order, from where half their widths'
  # sum falls short of the middle of the cluster's extent, by R's sums in extended precision, as
  # ggplot2's `pos_dodge2()` lays them; each bar's x moves to its middle. Where a cluster of a panel
  # holds two bars or more, every bar of that panel then shrinks about its x to `1 - padding` of its
  # width. A cluster is placed from its own middle and widths, where R gives each cluster after a
  # bar with no edges the next one's start (design-log §4, the entry beginning "Dodging by clusters
  # places each cluster"); a bar missing an edge is in no cluster, is placed nowhere, and loses its
  # x, even where no bar of its panel has edges, which R fails at. Heights are left alone.
  # Horizontal bars, those whose `flipped_aes` column says so, are dodged along y, x and y swapped
  # and swapped back (`Giggly.Position.Orientation`).

  @enforce_keys [:preserve, :padding, :reverse]
  defstruct @enforce_keys

  @type t :: %__MODULE__{preserve: :total | :single, padding: float(), reverse: boolean()}

  defimpl Giggly.Position, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Position

    alias Giggly.DataFrame
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Position.Orientation

    @columns [:panel, :group, :x, :xmin, :xmax]

    # Dodging by clusters reads no aesthetics of its own.
    @impl Giggly.Position
    def default_aesthetics(_position), do: %{}

    @impl Giggly.Position
    def compute_layer(position, frame) do
      flipped = Orientation.flipped?(frame)

      frame
      |> Orientation.flip(flipped)
      |> dodged(position)
      |> Orientation.flip(flipped)
    end

    defp dodged(frame, position) do
      rows =
        @columns
        |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
        |> Enum.zip_with(fn values -> row(values) end)
        |> Enum.with_index(fn row, index -> Map.put(row, :index, index) end)

      share = share(rows, position.preserve)

      placed =
        rows
        |> Enum.sort_by(fn row ->
          {row.panel, Arithmetic.sort_key(row.x), group_key(row.group, position)}
        end)
        |> Enum.chunk_by(fn row -> row.panel end)
        |> Enum.flat_map(fn panel_rows -> dodge_panel(panel_rows, share, position) end)

      sorted = DataFrame.slice(frame, Enum.map(placed, fn row -> row.index end))

      Enum.reduce([:x, :xmin, :xmax], sorted, fn name, dodged ->
        DataFrame.put(dodged, name, Enum.map(placed, fn row -> Map.fetch!(row, name) end))
      end)
    end

    defp row(values) do
      @columns
      |> Enum.zip(values)
      |> Map.new()
    end

    # What a bar's width is divided by: the number of bars in its cluster (`:total`), or the most
    # bars at one x in any panel (`:single`), a bar missing its x counted at none, as ggplot2's
    # `setup_params()` counts them with `table()`.
    defp share(_rows, :total), do: :cluster

    defp share(rows, :single) do
      rows
      |> Enum.reject(fn row -> missing?(row.x) end)
      |> Enum.frequencies_by(fn row -> {row.panel, row.x} end)
      |> Map.values()
      |> Enum.max(fn -> 1 end)
    end

    # ggplot2's `collide2()` and `pos_dodge2()` for one panel's rows, sorted.
    defp dodge_panel(sorted, share, position) do
      clusters = clusters(sorted)

      laid =
        clusters
        |> Enum.flat_map(fn cluster -> lay(cluster, share) end)
        |> Map.new()

      padding =
        if Enum.any?(clusters, fn cluster -> match?([_first, _second | _rest], cluster) end),
          do: position.padding,
          else: :none

      Enum.map(sorted, fn row ->
        row
        |> laid_out(laid)
        |> padded(padding)
      end)
    end

    defp group_key(group, %{reverse: false}), do: group
    defp group_key(group, %{reverse: true}), do: -group

    # ggplot2's `find_x_overlaps()`: walking the bars with both edges, in order, one starts a new
    # cluster where its `xmin` is beyond the furthest `xmax` before it, or on it for a bar with
    # width. A bar missing an edge is in none.
    defp clusters(sorted) do
      sorted
      |> Enum.reject(fn row -> missing?(row.xmin) or missing?(row.xmax) end)
      |> Enum.chunk_while(:none, &cluster/2, &last_cluster/1)
    end

    defp cluster(bar, :none), do: {:cont, {[bar], bar.xmax}}

    defp cluster(bar, {bars, reach}) do
      further = Arithmetic.greater(reach, bar.xmax)

      if Arithmetic.less?(reach, bar.xmin) or (bar.xmin == reach and bar.xmax != bar.xmin),
        do: {:cont, Enum.reverse(bars), {[bar], further}},
        else: {:cont, {[bar | bars], further}}
    end

    defp last_cluster(:none), do: {:cont, :none}
    defp last_cluster({bars, _reach}), do: {:cont, Enum.reverse(bars), :none}

    # ggplot2's `pos_dodge2()` for one cluster: each bar's width divided by its share, the bars
    # laid side by side from the middle of the cluster's extent less half their widths' sum, each
    # edge R's running sum, by each bar's index.
    defp lay(bars, share) do
      count = if share == :cluster, do: length(bars), else: share

      least =
        bars
        |> Enum.map(fn bar -> bar.xmin end)
        |> Enum.reduce(&Arithmetic.lesser/2)

      greatest =
        bars
        |> Enum.map(fn bar -> bar.xmax end)
        |> Enum.reduce(&Arithmetic.greater/2)

      middle = midpoint(least, greatest)

      widths =
        Enum.map(bars, fn bar ->
          Arithmetic.divide(Arithmetic.subtract(bar.xmax, bar.xmin), count)
        end)

      half_total =
        widths
        |> Arithmetic.sum()
        |> half()

      start = Arithmetic.subtract(middle, half_total)
      edges = Arithmetic.cumulative_sum([start | widths])

      Enum.zip_with([bars, widths, edges, tl(edges)], fn [bar, width, xmin, xmax] ->
        {bar.index, Map.merge(bar, %{xmin: xmin, xmax: xmax, width: width})}
      end)
    end

    # A bar as its cluster laid it, or, missing an edge, as it was, with no width; either way its x
    # moves to its middle, which a bar missing an edge does not have, so padding leaves it missing.
    defp laid_out(row, laid) do
      bar = Map.get_lazy(laid, row.index, fn -> Map.put(row, :width, nil) end)

      %{bar | x: midpoint(bar.xmin, bar.xmax)}
    end

    # A bar shrunk about its x to `1 - padding` of its width, where its panel is padded.
    defp padded(bar, :none), do: bar

    defp padded(bar, padding) do
      half_width =
        bar.width
        |> Arithmetic.multiply(1 - padding)
        |> half()

      %{
        bar
        | xmin: Arithmetic.subtract(bar.x, half_width),
          xmax: Arithmetic.add(bar.x, half_width)
      }
    end

    # The middle of two positions, and half a width, in R's arithmetic.
    defp midpoint(left, right) do
      left
      |> Arithmetic.add(right)
      |> half()
    end

    defp half(width), do: Arithmetic.divide(width, 2)

    defp missing?(value), do: value in [nil, :nan]
  end
end
