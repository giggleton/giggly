defmodule Giggly.Position.Dodge do
  @moduledoc false

  # Dodging, ggplot2's `position_dodge()`: the marks at one x set side by side within the space
  # one takes, as `geom_bar(position = "dodge")` sets them, or within `width`, ggplot2's `width`,
  # `:none` where it is not given. ggplot2's `preserve = "total"` and `reverse = FALSE` are how it
  # dodges; its other parameters wait. Run it through `Giggly.Position`.
  #
  # A mark with no sides, `xmin` and `xmax`, such as a line range, is first given them, as
  # ggplot2's `collide_setup()` gives them: its x less and plus half the width, where one is given,
  # else its x, so that, given none, a mark with no width is dodged by nothing (where ggplot2 also
  # warns, "Width not defined"). Each panel's marks are then dodged by their `xmin`, the marks at
  # one x ranked by group, lowest first, as ggplot2's `collide()` orders them for dodging. The n
  # groups at an x share the width: the k-th is centred `width · ((k - 0.5) / n - 0.5)` from the x,
  # where `width` is the one given, else the panel's first mark's, and is the widest mark's width
  # over n wide, as ggplot2's `pos_dodge()` places it. An x with one group keeps its mark as it
  # is, so a group missing at an x leaves no gap (`preserve = "total"`). Every x comes out a
  # double, as R's are. Heights are left alone, and a row missing its x stays missing. Horizontal
  # marks, those whose `flipped_aes` column says so, are dodged along y, x and y swapped and
  # swapped back (`Giggly.Position.Orientation`).

  @enforce_keys [:width]
  defstruct @enforce_keys

  @type t :: %__MODULE__{width: :none | float()}

  defimpl Giggly.Position, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Position

    alias Giggly.DataFrame
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Position.Orientation

    @columns [:panel, :group, :x, :xmin, :xmax]

    # Dodging reads no aesthetics of its own.
    @impl Giggly.Position
    def default_aesthetics(_position), do: %{}

    @impl Giggly.Position
    def compute_layer(position, frame, _axis_kinds) do
      flipped = Orientation.flipped?(frame)

      frame
      |> Orientation.flip(flipped)
      |> with_sides(position.width)
      |> moved(position.width)
      |> Orientation.flip(flipped)
    end

    # ggplot2's `collide_setup()`: a mark with no sides is given them, its x less and plus half the
    # width given, else its x on both.
    defp with_sides(frame, width) do
      if Enum.all?([:xmin, :xmax], fn side -> side in DataFrame.names(frame) end) do
        frame
      else
        x_positions = DataFrame.pull(frame, :x)
        half = if width == :none, do: 0.0, else: width / 2

        frame
        |> DataFrame.put(:xmin, Enum.map(x_positions, fn x -> Arithmetic.subtract(x, half) end))
        |> DataFrame.put(:xmax, Enum.map(x_positions, fn x -> Arithmetic.add(x, half) end))
      end
    end

    defp moved(frame, width) do
      dodged =
        @columns
        |> Enum.map(fn name -> DataFrame.pull(frame, name) end)
        |> Enum.zip_with(fn values -> row(values) end)
        |> Enum.with_index(fn row, index -> Map.put(row, :index, index) end)
        |> Enum.group_by(fn row -> row.panel end)
        |> Enum.flat_map(fn {_panel, rows} -> dodge_panel(rows, width) end)
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

    # ggplot2's `collide()` for one panel: the dodge width is the one given, else the panel's first
    # mark's width, and the marks at each `xmin` are dodged together, ranked by group.
    defp dodge_panel(rows, given) do
      width = if given == :none, do: Enum.find_value(rows, &bar_width/1), else: given

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
