defmodule Giggly.Position.Jitterdodge do
  @moduledoc false

  # Jittering beside dodging, ggplot2's `position_jitterdodge()`: the marks at one x set side by
  # side, then each moved a small random distance, as points drawn over dodged box plots are moved
  # to their group's box and spread across it. Its fields are R's parameters, each given by a
  # layer's `position: {:jitterdodge, options}`: `jitter_width`, `:none` where it is not given,
  # `jitter_height`, `dodge_width` and `seed`. Run it through `Giggly.Position`.
  #
  # The marks are horizontal where their orientation says so (`Giggly.Position.Orientation`): the
  # `flipped_aes` column the stat or the geom wrote, else y the one discrete axis, else not, as
  # ggplot2's `has_flipped_aes()` reads it here with no fallback of its own; horizontal marks are
  # dodged and jittered sideways along y, x and y swapped and swapped back.
  #
  # The dodge is ggplot2's `pos_dodge()` as `position_jitterdodge()` calls it, through `collide()`
  # with `dodge_width` and none of `PositionDodge`'s setup: a mark with no `xmin` and `xmax`, a
  # point, is given them, its x less and plus half `dodge_width`, as `collide_setup()` gives them,
  # and each panel's marks are dodged by their `xmin`. The n groups at an `xmin` share
  # `dodge_width`, each ranked by its group among them, lowest first: the mark of rank k is centred
  # `dodge_width · ((k - 0.5) / n - 0.5)` from its x and is the widest mark's width over n wide, so
  # an `xmin` with one group keeps its marks as they are. A mark with no `ymax`, a point, is given
  # its y as one, as `collide()` gives it. Every dodged x comes out a double, as R's are, and a row
  # missing its x stays missing.
  #
  # The jitter is then `Giggly.Position.Jitter`'s, its sideways amount `jitter_width` over the most
  # groups at one x in any panel plus 2, as ggplot2's `setup_params()` divides it whether given or
  # not, and its amount up `jitter_height`. Not given, the width is 0.4 of the closest spacing of
  # the layer's positions along x before they are dodged (`Giggly.Resolution`, not counting from
  # zero), worked out over every panel at once, as R's `setup_params()` works it out, 0.4 on a
  # discrete axis. Its distances are drawn from `seed`, each panel's afresh, and move every column
  # of each axis's family by its row's distance along it, as jittering moves them.

  @enforce_keys [:jitter_width, :jitter_height, :dodge_width, :seed]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          jitter_width: :none | float(),
          jitter_height: float(),
          dodge_width: float(),
          seed: integer()
        }

  defimpl Giggly.Position, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Position

    alias Giggly.{DataFrame, Position, Resolution}
    alias Giggly.Position.{Collide, Orientation}

    @columns [:panel, :group, :x, :xmin, :xmax]

    # The share of the closest spacing of the layer's positions the marks move at most sideways,
    # before it is divided among the groups, unless given.
    @share 0.4

    # Jittering beside dodging reads no aesthetics of its own.
    @impl Giggly.Position
    def default_aesthetics(_position), do: %{}

    @impl Giggly.Position
    def compute_layer(position, frame, axis_kinds) do
      flipped = Orientation.flipped?(frame, axis_kinds, false)
      upright = Orientation.flip(frame, flipped)
      sideways = sideways(position.jitter_width, upright, kind(axis_kinds, flipped))

      upright
      |> Collide.with_sides(position.dodge_width)
      |> dodged(position.dodge_width)
      |> Collide.with_top()
      |> Orientation.flip(flipped)
      |> jittered(position, sideways, flipped, axis_kinds)
    end

    # The kind of the axis the marks are dodged along: x's, or y's where they are horizontal.
    defp kind(axis_kinds, false), do: axis_kinds.x
    defp kind(axis_kinds, true), do: axis_kinds.y

    # How far the marks move at most sideways: `jitter_width`, else 0.4 of the closest spacing of
    # the layer's positions, over the most groups at one x in any panel plus 2.
    defp sideways(jitter_width, frame, kind),
      do: width(jitter_width, frame, kind) / (most_groups(frame) + 2)

    defp width(:none, frame, kind) do
      spacing =
        frame
        |> DataFrame.pull(:x)
        |> Resolution.of(zero: false, discrete: kind == :discrete)

      @share * spacing
    end

    defp width(jitter_width, _frame, _kind), do: jitter_width

    # The most groups at one x in any panel, as ggplot2's `setup_params()` counts them.
    defp most_groups(frame) do
      [:panel, :x, :group]
      |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
      |> Enum.zip_with(fn [panel, x, group] -> {panel, x, group} end)
      |> Enum.uniq()
      |> Enum.frequencies_by(fn {panel, x, _group} -> {panel, x} end)
      |> Map.values()
      |> Enum.max(fn -> 1 end)
    end

    # The dodged marks moved by jittering's distances, sideways along y where they are horizontal,
    # both amounts given, so jittering reads neither axis's kind.
    defp jittered(frame, position, sideways, flipped, axis_kinds) do
      {width, height} =
        if flipped,
          do: {position.jitter_height, sideways},
          else: {sideways, position.jitter_height}

      Position.compute_layer(
        %Position.Jitter{width: width, height: height, seed: position.seed},
        frame,
        axis_kinds
      )
    end

    defp dodged(frame, width) do
      rows =
        @columns
        |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
        |> Enum.zip_with(fn values -> row(values) end)
        |> Enum.with_index(fn row, index -> Map.put(row, :index, index) end)

      dodged =
        rows
        |> Enum.group_by(fn row -> {row.panel, row.xmin} end)
        |> Enum.flat_map(fn {_at, marks} -> dodge(marks, width) end)
        |> Enum.sort_by(fn row -> row.index end)

      Enum.reduce([:x, :xmin, :xmax], frame, fn name, placed ->
        DataFrame.put(placed, name, Enum.map(dodged, fn row -> double(Map.fetch!(row, name)) end))
      end)
    end

    defp row(values) do
      @columns
      |> Enum.zip(values)
      |> Map.new()
    end

    # Positions as R holds them once dodged, doubles, so a column of a discrete axis's level
    # positions stays one type when only some of its marks move.
    defp double(position) when is_number(position), do: position / 1
    defp double(missing), do: missing

    # ggplot2's `pos_dodge()` for the marks at one `xmin`: each of the n groups there takes its
    # share of `width`, ranked by group, as `match_sorted()` ranks them. Marks that lost their x
    # share a missing `xmin`, and stay as they are.
    defp dodge(marks, width) do
      ranks =
        marks
        |> Enum.map(fn mark -> mark.group end)
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.with_index(1)
        |> Map.new()

      widths =
        for %{xmin: xmin, xmax: xmax} <- marks,
            is_number(xmin) and is_number(xmax),
            do: xmax - xmin

      case {map_size(ranks), widths} do
        {1, _widths} -> marks
        {_count, []} -> marks
        {count, widths} -> spread(marks, ranks, count, width, Enum.max(widths))
      end
    end

    defp spread(marks, ranks, count, width, widest) do
      Enum.map(marks, fn mark ->
        offset = width * ((Map.fetch!(ranks, mark.group) - 0.5) / count - 0.5)
        placed(mark, offset, widest / count / 2)
      end)
    end

    defp placed(%{x: x} = mark, offset, half_width) when is_number(x) do
      centre = x + offset
      %{mark | x: centre, xmin: centre - half_width, xmax: centre + half_width}
    end

    defp placed(mark, _offset, _half_width), do: mark
  end
end
