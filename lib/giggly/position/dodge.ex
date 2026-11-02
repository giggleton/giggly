defmodule Giggly.Position.Dodge do
  @moduledoc false

  # Dodging, ggplot2's `position_dodge()`: the marks at one x set side by side within the space
  # one takes, as `geom_bar(position = "dodge")` sets them, or within `width`. Its fields are R's
  # parameters, each given by a layer's `position: {:dodge, options}`: `width`, `:none` where it is
  # not given; `preserve`, `:total` or `:single`; `orientation`, `:x` or `:y`; and `reverse`. Run it
  # through `Giggly.Position`.
  #
  # The marks are horizontal where their orientation says so (`Giggly.Position.Orientation`): the
  # `flipped_aes` column the stat or the geom wrote, else y the one discrete axis, else
  # `orientation`; horizontal marks are dodged along y, x and y swapped and swapped back.
  #
  # A mark with sides and no x, a rectangle, is first given the middle of its sides as its x, and a
  # mark with no sides, `xmin` and `xmax`, such as a line range, is given them, as
  # ggplot2's `collide_setup()` gives them: its x less and plus half the width, where one is given,
  # else its x, so that, given none, a mark with no width is dodged by nothing (where ggplot2 also
  # warns, "Width not defined"). Each mark is ranked by its group among the groups at its x in its
  # panel, lowest first, or highest first with `reverse`, as ggplot2's `setup_data()` writes its
  # `order`; with `:single`, that rank is taken among every rank in the layer, which leaves it as
  # it is unless reversed, where a mark's rank counts from the most groups at any x. Each panel's
  # marks are then dodged by their `xmin`. The n groups at an x share the width: the mark of rank
  # k is centred `width · ((k - 0.5) / n - 0.5)` from the x, where `width` is the one given, else
  # the panel's first mark's, and is the widest mark's width over n wide, as ggplot2's `pos_dodge()`
  # places it. n is the number of groups at that x (`:total`), so an x with one group keeps its
  # mark as it is and a group missing at an x leaves no gap, or the most groups at one x in any
  # panel (`:single`), so a lone mark takes the first share. Every x comes out a double, as R's
  # are. Heights are left alone, but a mark with no `ymax`, a point, is given its y as one, as
  # ggplot2's `collide()` gives it, and a row missing its x stays missing.

  @enforce_keys [:width, :preserve, :orientation, :reverse]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          width: :none | float(),
          preserve: :total | :single,
          orientation: :x | :y,
          reverse: boolean()
        }

  defimpl Giggly.Position, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Position

    alias Giggly.DataFrame
    alias Giggly.Position.{Collide, Orientation}

    @columns [:panel, :group, :x, :xmin, :xmax]

    # Dodging reads no aesthetics of its own.
    @impl Giggly.Position
    def default_aesthetics(_position), do: %{}

    @impl Giggly.Position
    def compute_layer(position, frame, axis_kinds) do
      flipped = Orientation.flipped?(frame, axis_kinds, position.orientation == :y)

      frame
      |> Orientation.flip(flipped)
      |> Collide.with_middle()
      |> Collide.with_sides(position.width)
      |> moved(position)
      |> Collide.with_top()
      |> Orientation.flip(flipped)
    end

    defp moved(frame, position) do
      rows =
        @columns
        |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
        |> Enum.zip_with(fn values -> row(values) end)
        |> Enum.with_index(fn row, index -> Map.put(row, :index, index) end)

      share = share(rows, position.preserve)

      dodged =
        rows
        |> ranked(position)
        |> Enum.group_by(fn row -> row.panel end)
        |> Enum.flat_map(fn {_panel, panel_rows} ->
          dodge_panel(panel_rows, position.width, share)
        end)
        |> Enum.sort_by(fn row -> row.index end)

      Enum.reduce([:x, :xmin, :xmax], frame, fn name, placed ->
        DataFrame.put(placed, name, Enum.map(dodged, fn row -> double(Map.fetch!(row, name)) end))
      end)
    end

    # Positions as R holds them once dodged, doubles, so a column of a discrete axis's level
    # positions stays one type when only some of its bars move.
    defp double(position) when is_number(position), do: position / 1
    defp double(missing), do: missing

    defp row(values) do
      @columns
      |> Enum.zip(values)
      |> Map.new()
    end

    # How many shares the marks at an x are dodged into: the number of groups there
    # (`:total`), or the most groups at one `xmin` in any panel (`:single`), as ggplot2's
    # `setup_params()` counts them.
    defp share(_rows, :total), do: :groups

    defp share(rows, :single) do
      rows
      |> Enum.uniq_by(fn row -> {row.panel, row.xmin, row.group} end)
      |> Enum.frequencies_by(fn row -> {row.panel, row.xmin} end)
      |> Map.values()
      |> Enum.max(fn -> 1 end)
    end

    # Each row with its `rank`, ggplot2's `order` from `PositionDodge$setup_data()`: its group's
    # place among the groups at its x in its panel, negated with `reverse`, then placed again among
    # those at its x (`:total`) or among every one in the layer (`:single`).
    defp ranked(rows, position) do
      at_x = fn row -> {row.panel, row.x} end

      first =
        rows
        |> ranks_within(at_x, fn row -> row.group end)
        |> Enum.map(fn {row, rank} -> Map.put(row, :rank, signed(rank, position.reverse)) end)

      within = if position.preserve == :total, do: at_x, else: fn _row -> :layer end

      first
      |> ranks_within(within, fn row -> row.rank end)
      |> Enum.map(fn {row, rank} -> %{row | rank: rank} end)
    end

    defp signed(rank, false), do: rank
    defp signed(rank, true), do: -rank

    # Each row with the place of its `value` among the distinct values of the rows sharing its
    # `key`, the lowest first, as ggplot2's `match_sorted()` places them.
    defp ranks_within(rows, key, value) do
      places =
        rows
        |> Enum.group_by(key, value)
        |> Map.new(fn {shared, values} -> {shared, places(values)} end)

      Enum.map(rows, fn row ->
        rank =
          places
          |> Map.fetch!(key.(row))
          |> Map.fetch!(value.(row))

        {row, rank}
      end)
    end

    # Each distinct value of `values` by its place among them, the lowest 1.
    defp places(values) do
      values
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.with_index(1)
      |> Map.new()
    end

    # ggplot2's `collide()` for one panel: the dodge width is the one given, else the panel's first
    # mark's width, and the marks at each `xmin` are dodged together.
    defp dodge_panel(rows, given, share) do
      width = if given == :none, do: Enum.find_value(rows, &bar_width/1), else: given

      rows
      |> Enum.group_by(fn row -> row.xmin end)
      |> Enum.flat_map(fn {_xmin, bars} -> dodge(bars, width, share) end)
    end

    defp bar_width(%{xmin: xmin, xmax: xmax}) when is_number(xmin) and is_number(xmax),
      do: xmax - xmin

    defp bar_width(_row), do: nil

    # ggplot2's `pos_dodge()`: each of the n shares at one x takes its part of the bar's width.
    # Bars that lost their x share a missing `xmin`, and stay as they are.
    defp dodge(bars, width, share) do
      count = count(bars, share)

      widths =
        bars
        |> Enum.map(fn bar -> bar_width(bar) end)
        |> Enum.filter(fn bar_width -> is_number(bar_width) end)

      case {count, widths} do
        {1, _widths} -> bars
        {_count, []} -> bars
        {count, widths} -> spread(bars, count, width, Enum.max(widths))
      end
    end

    # The number of shares at one x: its groups' (`:total`), or the layer's most (`:single`).
    defp count(bars, :groups) do
      bars
      |> Enum.uniq_by(fn bar -> bar.group end)
      |> length()
    end

    defp count(_bars, share), do: share

    defp spread(bars, count, width, widest) do
      Enum.map(bars, fn bar ->
        placed(bar, width * ((bar.rank - 0.5) / count - 0.5), widest / count / 2)
      end)
    end

    defp placed(%{x: x} = bar, offset, half_width) when is_number(x) do
      centre = x + offset
      %{bar | x: centre, xmin: centre - half_width, xmax: centre + half_width}
    end

    defp placed(bar, _offset, _half_width), do: bar
  end
end
