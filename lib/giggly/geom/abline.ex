defmodule Giggly.Geom.Abline do
  @moduledoc false

  # Diagonal reference lines, ggplot2's `GeomAbline`, which `geom_abline()` draws with: a line
  # across the whole panel for each row, `y = intercept + slope * x`. Its one parameter is how a
  # line's ends are drawn (`line_end`, ggplot2's `lineend`). Use it through `Giggly.Geom`.
  #
  # Diagonal lines use `:intercept`, `:slope`, `:group`, `:alpha`, `:color`, `:linetype` and
  # `:linewidth`, and need `:intercept` and `:slope`, numbers no scale trains on or transforms, as
  # ggplot2 gives them none: the intercept is in the y axis's positions, the units its scale
  # transforms into, and the slope in those over the x axis's. A line is drawn as ggplot2's
  # `GeomAbline` draws one: each panel's rows, the repeats dropped, as `unique0()` drops them, are
  # segments (`Giggly.Geom.Segment`) between the panel's extents (`Giggly.Coord.extents/2`), each
  # first widened by its own width each side where the coordinate system keeps straight lines
  # straight and clips the panel, so a thick line's ends never show. Each line's x runs where its
  # y is in the y extent, `(y - intercept) / slope` at each end, cut to the x extent, and its y
  # is `intercept + slope * x` at both ends, in R's arithmetic (`Giggly.DataFrame.Arithmetic`), so
  # a flat line's ends are the x extent's, from the division's infinities. It is drawn with the
  # lines' ends and a segment's round corners, as `GeomAbline` hands its rows to
  # `GeomSegment$draw_panel()` with its `lineend` alone, so under radial coordinates it follows
  # the panel's curves. A row missing its intercept, its slope, a width or a line type is not
  # drawn, and nor is one whose arithmetic makes NaN: an infinite intercept or slope, or a flat
  # line exactly on the edge of a panel not widened, as R's `0 / 0` drops it. A line that misses
  # the panel is still drawn, beyond it, as R draws it: hidden where the panel is clipped, and
  # past its edge where it is not, a spiral round radial coordinates. Its look, when the layer
  # neither maps nor sets one, is a path's, as `GeomAbline$default_aes` is `GeomPath`'s. Its
  # legend key is `draw_key_abline()`'s: a line across the key from its bottom left corner to its
  # top right, with the lines' ends, needing a path's room.

  @enforce_keys [:line_end]
  defstruct @enforce_keys

  @type t :: %__MODULE__{line_end: Giggly.Scene.Polylines.line_end()}

  # The aesthetics a layer of diagonal lines can use, from its own mapping alone, since it takes
  # nothing from the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics,
    do: [:alpha, :color, :group, :intercept, :linetype, :linewidth, :slope]

  # The aesthetics a layer of diagonal lines cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:intercept, :slope]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame, Geom}
    alias Giggly.DataFrame.Arithmetic
    alias Giggly.Geom.Path

    # A legend's key, `draw_key_abline()`: a line from the key's bottom left corner to its top
    # right.
    @key_line {{0.0, 0.0}, {1.0, 1.0}}

    @impl Giggly.Geom
    def default_aesthetics(geom, element) do
      geom
      |> segment()
      |> Geom.default_aesthetics(element)
    end

    # A line is drawn from its intercept and slope alone, in the data's order. Both must be
    # numbers: `Giggly.Plot` refuses a column or a value that is not at the call, and an
    # expression's type is known only once it has run, so one that computes anything else is
    # refused here, where ggplot2 fails at `y - intercept`.
    @impl Giggly.Geom
    def setup_data(_geom, frame, _axis_kinds) do
      frame
      |> DataFrame.dtypes()
      |> Map.take([:intercept, :slope])
      |> Enum.each(fn
        {aesthetic, dtype} when dtype not in [:integer, :float, :null] ->
          raise ArgumentError,
                "a line is drawn at y = intercept + slope * x, so its #{aesthetic} must be a " <>
                  "number, but the layer's #{aesthetic} is a #{inspect(dtype)} column"

        _numbers ->
          :ok
      end)

      frame
    end

    # The panel's lines: each distinct row a segment from where it enters the panel's extents to
    # where it leaves them, as `GeomAbline` works them out. Its rows' intercept and slope are
    # kept, as R keeps them, and are no position the coordinate system places; the repeats are
    # dropped before the ends are worked out, which drops what `unique0()` drops after, since a
    # row's ends follow from the columns it keeps.
    @impl Giggly.Geom
    def draw_panel(geom, frame, coord, panel_params) do
      %{x: x_extent, y: y_extent} =
        coord
        |> Coord.extents(panel_params)
        |> widened(coord)

      lines = DataFrame.distinct(frame)

      ends =
        lines
        |> DataFrame.pull(:intercept)
        |> Enum.zip_with(DataFrame.pull(lines, :slope), fn intercept, slope ->
          ends(intercept, slope, x_extent, y_extent)
        end)

      segments =
        [:x, :y, :xend, :yend]
        |> Enum.with_index()
        |> Enum.reduce(lines, fn {name, place}, ended ->
          DataFrame.put(ended, name, Enum.map(ends, fn line -> elem(line, place) end))
        end)

      geom
      |> segment()
      |> Geom.draw_panel(segments, coord, panel_params)
    end

    @impl Giggly.Geom
    def draw_key(geom, key), do: Path.line_key(key, @key_line, geom.line_end, :none)

    # A path's room, as `draw_key_abline()` sets no size of its own.
    @impl Giggly.Geom
    def key_size(geom, key) do
      geom
      |> segment()
      |> Geom.key_size(key)
    end

    # Each extent widened by its own width each side, where straight lines stay straight and the
    # panel is clipped, as `GeomAbline` widens them so a thick line's ends fall well outside.
    defp widened(extents, coord) do
      if Coord.linear?(coord) and Coord.clip(coord) == :on do
        Map.new(extents, fn {aesthetic, {low, high}} ->
          {aesthetic, {low - (high - low), high + (high - low)}}
        end)
      else
        extents
      end
    end

    # A line's `{x, y, xend, yend}`: its x where its y is at each end of the y extent, the lesser
    # cut to the x extent's start and the greater to its end, as R's `pmax()` and `pmin()` cut
    # them, and its y at each of those x.
    defp ends(intercept, slope, {x_low, x_high}, {y_low, y_high}) do
      at_low = crossing(y_low, intercept, slope)
      at_high = crossing(y_high, intercept, slope)
      lesser = Arithmetic.lesser(at_low, at_high)
      greater = Arithmetic.greater(at_low, at_high)
      x = Arithmetic.greater(x_low, lesser)
      xend = Arithmetic.lesser(x_high, greater)
      {x, height(x, intercept, slope), xend, height(xend, intercept, slope)}
    end

    # Where a line is at height `y`, as R works out `(y - intercept) / slope`.
    defp crossing(y, intercept, slope) do
      y
      |> Arithmetic.subtract(intercept)
      |> Arithmetic.divide(slope)
    end

    # A line's y at `x`, as R works out `x * slope + intercept`.
    defp height(x, intercept, slope) do
      x
      |> Arithmetic.multiply(slope)
      |> Arithmetic.add(intercept)
    end

    # The segments the lines are drawn as, with the lines' ends and a segment's round corners, as
    # `GeomAbline` hands `GeomSegment$draw_panel()` its `lineend` alone, and no arrowheads.
    defp segment(geom),
      do: %Geom.Segment{line_end: geom.line_end, line_join: :round, arrow: :none}
  end
end
