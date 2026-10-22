defmodule Giggly.Position.Dodge do
  @moduledoc false

  # Dodging, ggplot2's `position_dodge()`: the bars at one x set side by side within the space one
  # bar takes, as `geom_bar(position = "dodge")` sets them. It takes no parameters yet; ggplot2's
  # `width = NULL`, `preserve = "total"` and `reverse = FALSE` are how it dodges. Run it through
  # `Giggly.Position`.
  #
  # Each panel's bars are dodged by their `xmin`, the bars at one x ranked by group, lowest first,
  # as ggplot2's `collide()` orders them for dodging. The n groups at an x share one bar's width:
  # the k-th is centred `width · ((k - 0.5) / n - 0.5)` from the x, where `width` is the panel's
  # first bar's width, and is the widest bar's width over n wide, as ggplot2's `pos_dodge()` places
  # it. An x with one group keeps its bar as it is, so a group missing at an x leaves no gap
  # (`preserve = "total"`). Every x comes out a double, as R's are. Heights are left alone, and a
  # row missing its x stays missing. Horizontal bars, those whose `flipped_aes` column says so, are
  # dodged along y, x and y swapped and swapped back (`Giggly.Position.Orientation`).

  defstruct []

  @type t :: %__MODULE__{}

  defimpl Giggly.Position, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Position

    alias Giggly.DataFrame
    alias Giggly.Position.Orientation

    @columns [:panel, :group, :x, :xmin, :xmax]

    # Dodging reads no aesthetics of its own.
    @impl Giggly.Position
    def default_aesthetics(_position), do: %{}

    @impl Giggly.Position
    def compute_layer(_position, frame) do
      flipped = Orientation.flipped?(frame)

      frame
      |> Orientation.flip(flipped)
      |> moved()
      |> Orientation.flip(flipped)
    end

    defp moved(frame) do
      dodged =
        @columns
        |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
        |> Enum.zip_with(fn values -> row(values) end)
        |> Enum.with_index(fn row, index -> Map.put(row, :index, index) end)
        |> Enum.group_by(fn row -> row.panel end)
        |> Enum.flat_map(fn {_panel, rows} -> dodge_panel(rows) end)
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

    # ggplot2's `collide()` for one panel: the dodge width is the panel's first bar's width, and
    # the bars at each `xmin` are dodged together, ranked by group.
    defp dodge_panel(rows) do
      width = Enum.find_value(rows, fn row -> bar_width(row) end)

      rows
      |> Enum.group_by(fn row -> row.xmin end)
      |> Enum.flat_map(fn {_xmin, bars} -> dodge(bars, width) end)
    end

    defp bar_width(%{xmin: xmin, xmax: xmax}) when is_number(xmin) and is_number(xmax),
      do: xmax - xmin

    defp bar_width(_row), do: nil

    # ggplot2's `pos_dodge()`: each of the n groups at one x takes its share of the bar's width.
    # Bars that lost their x share a missing `xmin`, and stay as they are.
    defp dodge(bars, width) do
      groups =
        bars
        |> Enum.map(fn bar -> bar.group end)
        |> Enum.uniq()
        |> Enum.sort()

      widths =
        bars
        |> Enum.map(fn bar -> bar_width(bar) end)
        |> Enum.filter(fn bar_width -> is_number(bar_width) end)

      case {groups, widths} do
        {[_only_group], _widths} -> bars
        {_groups, []} -> bars
        {groups, widths} -> spread(bars, groups, width, Enum.max(widths))
      end
    end

    defp spread(bars, groups, width, widest) do
      count = length(groups)

      Enum.map(bars, fn bar ->
        rank = Enum.find_index(groups, fn group -> group == bar.group end) + 1
        placed(bar, width * ((rank - 0.5) / count - 0.5), widest / count / 2)
      end)
    end

    defp placed(%{x: x} = bar, offset, half_width) when is_number(x) do
      centre = x + offset
      %{bar | x: centre, xmin: centre - half_width, xmax: centre + half_width}
    end

    defp placed(bar, _offset, _half_width), do: bar
  end
end
