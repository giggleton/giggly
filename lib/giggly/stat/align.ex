defmodule Giggly.Stat.Align do
  @moduledoc false

  # Aligning, ggplot2's `StatAlign`, `geom_area()`'s stat: each group of a panel interpolated at
  # every x the panel's groups have, and where any of them crosses zero, so areas whose rows sit at
  # different x stack into one another. Its parameter is the axis the areas run along
  # (`orientation`, `:x` unless the layer says `:y`); x and y swap while it runs along y. Run it
  # through `Giggly.Stat`.
  #
  # It needs `:x` and `:y`, takes `:group`, computes nothing a mapping's after_stat can read, as
  # ggplot2 documents none, and consumes nothing.
  #
  # A row missing its x or y, or at an infinite one, is left out first, as ggplot2's stats drop
  # one. A panel of one group keeps its rows as they are. In a panel of several, as
  # `StatAlign$compute_panel()` works it out: where two rows of a group follow one another in the
  # panel's order on either side of zero, the line between them crosses zero there, at R's
  # `-y0 * (x1 - x0) / (y1 - y0) + x0`; the panel's places are the distinct x of its rows and those
  # crossings, sorted, each also a thousandth of their range either side, or a third of the
  # smallest gap between two of them where that is less (`adjust`). Each group with more than one
  # distinct x, in order of group, then becomes a row at each place within its x range, its y
  # interpolated linearly between the rows either side, as R's `approxfun()` does, exactly a row's
  # y at its x, after the two rows at each x shared by several (its first and last) stand in for
  # them, the first moved `adjust` left; and a row of y 0 `adjust` beyond each end, `align_padding`
  # true, which the area leaves off its upper edge. Every other column is the group's first row's,
  # and the rows say which way they run in `flipped_aes`.
  #
  # It departs from ggplot2 in one place: a padding row whose x a scale's limits cut keeps its
  # missing x in the layer's table, where ggplot2's `StatAlign$finish_layer()` drops it once the
  # scales have been applied; the area leaves such a row out when drawn, so the drawing is R's
  # (design-log §4, the entry beginning "Smoothing and densities are Phase 3's twelfth").
  #
  # This stat pulls its panels' rows: interpolating each group at the others' places has no frame
  # operation (it is an as-of join), and its output is as large as its input, as the identity's is,
  # so an engine running it would save nothing (design-log §4, the entry beginning "Smoothing and
  # densities compute over the rows").

  @enforce_keys [:orientation]
  defstruct @enforce_keys

  @type t :: %__MODULE__{orientation: :x | :y}

  # The aesthetics a layer that aligns can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :x, :y]

  # The aesthetics a layer that aligns cannot be computed without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  # The variables aligning computes that a mapping's after_stat can read: none, as ggplot2
  # documents none.
  @doc false
  @spec computed_variables() :: [atom()]
  def computed_variables, do: []

  # The aesthetics aligning consumes: none.
  @doc false
  @spec dropped_aesthetics() :: [atom()]
  def dropped_aesthetics, do: []

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    alias Giggly.DataFrame
    alias Giggly.Stat.Curve

    # How far either side of each place a group is also interpolated, as a share of the places'
    # range, ggplot2's `0.001`.
    @adjust_share 0.001

    @impl Giggly.Stat
    def default_mapping(_stat), do: %{}

    @impl Giggly.Stat
    def compute_layer(%{orientation: orientation}, frame, _axes) do
      flipped = orientation == :y
      {across, up} = if flipped, do: {:y, :x}, else: {:x, :y}
      kept = DataFrame.filter(frame, {:and, [{:is_finite, [:x]}, {:is_finite, [:y]}]})

      columns = Enum.map([:panel, :group, across, up], fn name -> DataFrame.pull(kept, name) end)

      rows =
        columns
        |> Enum.zip_with(fn [panel, group, x, y] -> %{panel: panel, group: group, x: x, y: y} end)
        |> Enum.with_index(fn row, index -> Map.put(row, :index, index) end)

      panels =
        rows
        |> chunked_by(fn row -> row.panel end)
        |> Enum.map(&panel/1)

      if Enum.all?(panels, fn panel -> match?({:as_is, _rows}, panel) end),
        do: kept,
        else: aligned(kept, panels, {across, up}, flipped)
    end

    # A panel's rows: as they are where it holds one group, as ggplot2's `StatAlign` returns such a
    # panel's, else each group aligned at the panel's places.
    defp panel(rows) do
      case Enum.uniq_by(rows, fn row -> row.group end) do
        [_one] -> {:as_is, rows}
        _groups -> {:aligned, places_aligned(rows)}
      end
    end

    defp places_aligned(rows) do
      {places, adjust} = places(rows)

      rows
      |> chunked_by(fn row -> row.group end)
      |> Enum.flat_map(fn group_rows -> group(group_rows, places, adjust) end)
    end

    # The rows by `key`, in its order, each run's rows in their own, as R's `split()` orders them.
    defp chunked_by(rows, key) do
      rows
      |> Enum.sort_by(key)
      |> Enum.chunk_by(key)
    end

    # The panel's places, ggplot2's `unique_loc`: its rows' distinct x and the places their
    # groups cross zero, each also `adjust` either side, sorted and distinct, and `adjust`.
    defp places(rows) do
      crossings =
        rows
        |> Enum.chunk_by(fn row -> {row.group, row.y < 0} end)
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.filter(fn [run, next] -> hd(run).group == hd(next).group end)
        |> Enum.map(fn [run, [first_after | _rest]] -> crossing(List.last(run), first_after) end)

      locations =
        rows
        |> Enum.map(fn row -> row.x end)
        |> Enum.concat(crossings)
        |> distinct()

      adjust = adjust(locations)

      # No two places meet, `adjust` being at most a third of the smallest gap, so they stay sorted
      # and distinct, as R's second `unique(sort(...))` keeps them.
      places =
        Enum.flat_map(locations, fn location ->
          [location - adjust, location, location + adjust]
        end)

      {places, adjust}
    end

    # Where the line from one row to the next crosses zero, in R's order of operations.
    defp crossing(from, to), do: -from.y * (to.x - from.x) / (to.y - from.y) + from.x

    # A thousandth of the places' range, or a third of the smallest gap between two where that is
    # less; 0 for a single place, whose range is 0.
    defp adjust([_one]), do: 0.0

    defp adjust([first | _rest] = locations) do
      share = (List.last(locations) - first) * @adjust_share

      smallest_gap =
        locations
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [low, high] -> high - low end)
        |> Enum.min()

      min(share, smallest_gap / 3)
    end

    # Values sorted, each kept once, as R's `unique(sort(...))` keeps them, a whole number and its
    # float being one value.
    defp distinct(values) do
      values
      |> Enum.sort()
      |> Enum.reduce([], fn
        value, [previous | _rest] = kept when value == previous -> kept
        value, kept -> [value | kept]
      end)
      |> Enum.reverse()
    end

    # A group aligned at the panel's places, ggplot2's `StatAlign$compute_group()`: none where its
    # rows share one x; else a row at each place within its x range, its y interpolated, padded at
    # each end by a row of y 0 `adjust` beyond it, each carrying the group's first row.
    defp group(rows, places, adjust) do
      case Enum.uniq_by(rows, fn row -> row.x end) do
        [_one] -> []
        _several -> interpolated(rows, places, adjust)
      end
    end

    defp interpolated(rows, places, adjust) do
      known = standing_in(rows, adjust)
      [first | _rest] = known

      knots =
        known
        |> Enum.sort_by(fn row -> row.x end)
        |> Enum.map(fn row -> {row.x, row.y} end)

      interpolated = Curve.interpolate(knots, places)

      inside =
        places
        |> Enum.zip_with(interpolated, fn place, y -> {place, y} end)
        |> Enum.reject(fn {_place, y} -> is_nil(y) end)

      [{low, _y} | _rest] = inside
      {high, _y} = List.last(inside)
      padded = [{low - adjust, 0.0} | inside] ++ [{high + adjust, 0.0}]
      last = length(padded) - 1

      padded
      |> Enum.with_index()
      |> Enum.map(fn {{x, y}, position} ->
        %{source: first.index, x: x, y: y, padding: position in [0, last]}
      end)
    end

    # The rows that stand in for a group's: as they are where every x differs, else, by x in turn,
    # the one row at an x, or the first and last of several, the first moved `adjust` left, as
    # ggplot2 keeps two rows at an x so the line steps there.
    defp standing_in(rows, adjust) do
      if length(Enum.uniq_by(rows, fn row -> row.x end)) == length(rows) do
        rows
      else
        rows
        |> chunked_by(fn row -> row.x end)
        |> Enum.flat_map(fn
          [one] -> [one]
          [first | rest] -> [%{first | x: first.x - adjust}, List.last(rest)]
        end)
      end
    end

    # The layer's table aligned: each aligned row taken from the row it carries, its x and y put in
    # and the padding marked, the rows of a panel kept as they are taking none, and the columns in
    # ggplot2's order, x and y first where the first panel was aligned.
    defp aligned(kept, panels, {across, up}, flipped) do
      output =
        Enum.flat_map(panels, fn
          {:as_is, rows} ->
            Enum.map(rows, fn row ->
              %{source: row.index, x: row.x, y: row.y, padding: nil, flipped: nil}
            end)

          {:aligned, rows} ->
            Enum.map(rows, fn row -> Map.put(row, :flipped, flipped) end)
        end)

      sliced = DataFrame.slice(kept, Enum.map(output, fn row -> row.source end))

      put =
        sliced
        |> DataFrame.put(across, Enum.map(output, fn row -> row.x end))
        |> DataFrame.put(up, Enum.map(output, fn row -> row.y end))
        |> DataFrame.put(:align_padding, Enum.map(output, fn row -> row.padding end))
        |> DataFrame.put(:flipped_aes, Enum.map(output, fn row -> row.flipped end))

      case panels do
        [{:as_is, _rows} | _rest] -> put
        [{:aligned, _rows} | _rest] -> positions_first(put, [across, up])
      end
    end

    # The frame's columns with `first` leading, as ggplot2's `StatAlign` builds its rows from x
    # and y and then the rest.
    defp positions_first(frame, first) do
      rest = for name <- DataFrame.names(frame), name not in first, do: {name, name}
      DataFrame.select(frame, Enum.map(first, fn name -> {name, name} end) ++ rest)
    end
  end
end
