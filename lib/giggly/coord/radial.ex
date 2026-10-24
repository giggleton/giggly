defmodule Giggly.Coord.Radial do
  @moduledoc false

  # Radial coordinates, ggplot2's `coord_radial()` in its simplest form: a full circle, x the angle
  # clockwise from 12 o'clock and y the radius out from the centre, in a square panel. Its struct
  # holds its parameters: whether each panel is clipped to its edges, `:off` by default, as
  # `coord_radial(clip = "off")` is. Its panel params hold the angle's extent and the radius's, the
  # x and y extents already widened by the scales exactly as cartesian coordinates take them, since
  # `coord_radial()` expands scales by default, and each axis's breaks and minor breaks. Run it
  # through `Giggly.Coord`.
  #
  # A position's angle is its x rescaled from the angle's extent to a full turn, a full turn being
  # 0, and its radius its y rescaled from the radius's extent to 0.4, so the circle fills the
  # middle eight tenths of the panel; it is placed `radius · sin(angle)` across from the panel's
  # middle and `radius · cos(angle)` up from it: ggplot2's `transform()`. An infinite position is
  # put at its extent's end, as `squish_infinite()` puts it, and a row missing either position is
  # missing both. On an extent of equal ends every position is put at the middle of what it is
  # rescaled to, half a turn or a radius of 0.2, infinite ones too, as `scales::rescale()` puts
  # them. Only `x` and `y` are placed: a range such as `xmin` cannot be placed without its pair, so
  # a frame holding another x-family or y-family column fails here, and a geom drawing one turns it
  # into a path first, as ggplot2's geoms do under coordinates that are not linear.
  #
  # The radius axis is drawn to the panel's left in the radius axis's look, its breaks placed up
  # the radius at the angle's start, 12 o'clock, as ggplot2 draws it outside a full circle. The
  # angle axis is drawn around the circle inside the panel, each break on the circle's edge at its
  # angle. The radius axis's line runs up the panel's left edge from the centre's height to the
  # circle's top, munched as a spoke is, and the angle axis's round the circle's edge, munched as a
  # grid circle is, as ggplot2 munches an axis guide's line. Nothing is drawn below the panel,
  # though the x axis's title still goes there.
  #
  # The grid is a spoke from the centre to the edge at each of the angle's breaks and minor breaks,
  # and a circle all the way round at each of the radius's, each run from minus to plus infinity
  # along the other aesthetic as ggplot2 runs it; the panel's background is the disc they lie on,
  # run round its corners at infinity. Each is munched as ggplot2's `coord_munch()` munches it:
  # every straight piece is cut into equal steps, as many as its placed length holds a hundredth
  # of the longest line a panel holds, then each step is placed, a piece measured as the arc of
  # Archimedes' spiral through its ends, a circle's arc or a ray. A layer's lines are munched the
  # same way (`munch/3`), each step copying the row it starts from. The panel is square, its aspect
  # ratio 1, since the circle's bounding box is the panel.

  defstruct clip: :off

  @type t :: %__MODULE__{clip: :off}

  @typedoc "A panel's params under radial coordinates."
  @type panel_params :: %{
          theta_range: {number(), number()},
          r_range: {number(), number()},
          theta_breaks: [Giggly.Coord.break()],
          r_breaks: [Giggly.Coord.break()],
          theta_minor_breaks: [number()],
          r_minor_breaks: [number()]
        }

  defimpl Giggly.Coord, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Coord

    alias Giggly.{Aesthetics, DataFrame}

    @full_turn 2 * :math.pi()

    # The circle's radius as a share of the panel's width, ggplot2's `c(0, 1) * 0.4`.
    @outer_radius 0.4

    # Munching cuts each piece into steps of at most a hundredth of the longest line, ggplot2's
    # `segment_length`, measuring radii raised to the power 0.75 so pieces near the centre are cut
    # finer than their length alone would cut them, ggplot2's `boost`.
    @segment_length 0.01
    @boost 0.75

    # The longest line a panel holds, which ggplot2's `dist_polar()` measures pieces against:
    # Archimedes' spiral from the centre at angle 0 to the edge a full turn round, by
    # ggplot2's `spiral_arc_length()`.
    @spiral_slope 1 / @full_turn
    @longest_line 0.5 * @spiral_slope *
                    (@full_turn * :math.sqrt(1 + @full_turn * @full_turn) +
                       :math.asinh(@full_turn))

    defguardp is_position(value) when is_number(value) or value in [:infinity, :neg_infinity]

    @impl Giggly.Coord
    def panel_params(
          _coord,
          {theta_range, theta_breaks, theta_minor_breaks},
          {r_range, r_breaks, r_minor_breaks}
        ) do
      %{
        theta_range: theta_range,
        r_range: r_range,
        theta_breaks: theta_breaks,
        r_breaks: r_breaks,
        theta_minor_breaks: theta_minor_breaks,
        r_minor_breaks: r_minor_breaks
      }
    end

    @impl Giggly.Coord
    def transform(_coord, frame, params) do
      # A range cannot be placed without its pair.
      [] =
        frame
        |> DataFrame.names()
        |> Enum.filter(fn name -> name not in [:x, :y] and Aesthetics.family(name) != :none end)

      x_positions = DataFrame.pull(frame, :x)
      y_positions = DataFrame.pull(frame, :y)

      {x_places, y_places} =
        x_positions
        |> Enum.zip_with(y_positions, fn x_position, y_position ->
          place({x_position, y_position}, params)
        end)
        |> Enum.unzip()

      frame
      |> DataFrame.put(:x, x_places)
      |> DataFrame.put(:y, y_places)
    end

    # Each line cut into steps, then placed, as ggplot2's `coord_munch()` munches data: an infinite
    # position put at its extent's end, each piece between two rows of one group cut as a grid
    # line is, a piece between two groups or from a missing position left whole, each step copying
    # the row it starts from, and the last row kept.
    @impl Giggly.Coord
    def munch(coord, frame, params) do
      positions =
        frame
        |> DataFrame.pull(:x)
        |> Enum.zip_with(DataFrame.pull(frame, :y), fn x_position, y_position ->
          bounded({x_position, y_position}, params)
        end)

      counts =
        positions
        |> Enum.zip(DataFrame.pull(frame, :group))
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn
          [{from, group}, {to, group}] -> step_count(from, to, params)
          [_from, _to] -> 1
        end)

      steps =
        positions
        |> Enum.chunk_every(2, 1)
        |> Enum.zip_with(Enum.concat(counts, [1]), fn
          [from, to], count -> steps(from, to, count)
          [last], 1 -> [last]
        end)

      {x_positions, y_positions} =
        steps
        |> Enum.concat()
        |> Enum.unzip()

      rows =
        steps
        |> Enum.with_index()
        |> Enum.flat_map(fn {row_steps, index} -> List.duplicate(index, length(row_steps)) end)

      munched =
        frame
        |> DataFrame.slice(rows)
        |> DataFrame.put(:x, x_positions)
        |> DataFrame.put(:y, y_positions)

      transform(coord, munched, params)
    end

    # ggplot2 places an axis's breaks as data, the other aesthetic at minus infinity for the radius
    # axis, the angle's start, and at plus infinity for the angle axis, the circle's edge. Each
    # line is munched from minus to plus infinity along its aesthetic, the other at plus infinity,
    # as ggplot2 munches an axis guide's line: the radius axis's a ray up from the centre at the
    # angle's end, a full turn, where the start is, whose heights up the panel its side takes, and
    # the angle axis's the circle at the edge. Nothing is drawn below the panel.
    @impl Giggly.Coord
    def axes(_coord, params) do
      r_breaks =
        Enum.map(params.r_breaks, fn {position, label} ->
          {_x_place, y_place} = place({:neg_infinity, position}, params)
          {y_place, label}
        end)

      theta_breaks =
        Enum.map(params.theta_breaks, fn {position, label} ->
          {place({position, :infinity}, params), angle(position, params.theta_range), label}
        end)

      r_line =
        [{:infinity, :neg_infinity}, {:infinity, :infinity}]
        |> munch(params)
        |> Enum.map(fn {_x_place, y_place} -> y_place end)

      theta_line = munch([{:neg_infinity, :infinity}, {:infinity, :infinity}], params)

      %{
        bottom: {:x, :x, [], []},
        left: {:y, :r, r_breaks, r_line},
        theta: {:x, :theta, theta_breaks, theta_line}
      }
    end

    @impl Giggly.Coord
    def grid(_coord, params) do
      %{
        major: %{
          x: spokes(break_positions(params.theta_breaks), params),
          y: circles(break_positions(params.r_breaks), params)
        },
        minor: %{
          x: spokes(params.theta_minor_breaks, params),
          y: circles(params.r_minor_breaks, params)
        },
        background: background(params)
      }
    end

    @impl Giggly.Coord
    def clip(%{clip: clip}), do: clip

    @impl Giggly.Coord
    def aspect(_coord, _params), do: 1.0

    defp break_positions(breaks), do: Enum.map(breaks, fn {position, _label} -> position end)

    defp spokes(positions, params) do
      Enum.map(positions, fn position ->
        munch([{position, :neg_infinity}, {position, :infinity}], params)
      end)
    end

    defp circles(positions, params) do
      Enum.map(positions, fn position ->
        munch([{:neg_infinity, position}, {:infinity, position}], params)
      end)
    end

    # The panel's corners at infinity, run round from the end of the angle's extent at the edge,
    # in to the centre, round it, out again at the angle's start and round the edge, closed by
    # returning to the first corner, which the outline then leaves off, as `coord_munch(is_closed =
    # TRUE)` closes and opens a polygon.
    defp background(params) do
      corners = [
        {:infinity, :infinity},
        {:infinity, :neg_infinity},
        {:neg_infinity, :neg_infinity},
        {:neg_infinity, :infinity},
        {:infinity, :infinity}
      ]

      corners
      |> munch(params)
      |> Enum.drop(-1)
    end

    # A line through `positions`, an infinity standing for its extent's end, cut into steps and
    # placed: ggplot2's `coord_munch()`. Each piece gives its steps from its start, and the line's
    # last position closes it.
    defp munch(positions, params) do
      positions
      |> Enum.map(fn position -> bounded(position, params) end)
      |> Enum.chunk_every(2, 1)
      |> Enum.flat_map(fn
        [from, to] -> steps(from, to, step_count(from, to, params))
        [last] -> [last]
      end)
      |> Enum.map(fn position -> place(position, params) end)
    end

    defp bounded({x_position, y_position}, params),
      do: {bound(x_position, params.theta_range), bound(y_position, params.r_range)}

    defp bound(:neg_infinity, {low, _high}), do: low
    defp bound(:infinity, {_low, high}), do: high
    defp bound(position, _extent), do: position

    # A piece's `count` steps, its start and the points that divide it equally, as R's `seq()`
    # divides 0 to 1: the step count times the reciprocal of the count. One step is the start
    # alone, as ggplot2's `interp()` returns it, whatever the end.
    defp steps(from, _to, 1), do: [from]

    defp steps({x_from, y_from}, {x_to, y_to}, count) do
      Enum.map(0..(count - 1)//1, fn step ->
        fraction = step * (1 / count)
        {x_from + fraction * (x_to - x_from), y_from + fraction * (y_to - y_from)}
      end)
    end

    # How many steps a piece is cut into: as many lengths of `@segment_length` as its placed length
    # holds, at least one and at most ten thousand, as `munch_data()` counts them; a piece that
    # goes nowhere is one step.
    defp step_count(from, to, params) do
      case distance(from, to, params) do
        :none ->
          1

        distance ->
          distance
          |> Kernel./(@segment_length)
          |> Float.floor()
          |> max(1.0)
          |> min(1.0e4)
          |> trunc()
      end
    end

    # A piece's placed length as a share of the longest line, ggplot2's `dist_polar()` on radii
    # boosted and angles rescaled to a full turn: each piece measured as the arc of Archimedes'
    # spiral through its ends, `r = a * angle` counted from where it would meet the centre, by
    # ggplot2's `spiral_arc_length()`; a piece whose radius stays the same is a circle's arc, one
    # whose angle stays the same a ray, and one that goes nowhere, or from a missing position, is
    # not measured, as R's `NA` slope is not.
    defp distance({x_from, y_from}, {x_to, y_to}, _params)
         when not (is_number(x_from) and is_number(y_from) and is_number(x_to) and is_number(y_to)),
         do: :none

    defp distance({x_from, y_from}, {x_to, y_to}, params) do
      from = {boosted(y_from, params), rescale(x_from, params.theta_range, @full_turn)}
      to = {boosted(y_to, params), rescale(x_to, params.theta_range, @full_turn)}

      case piece_length(from, to) do
        :none -> :none
        length -> abs(length / @longest_line)
      end
    end

    defp piece_length({radius_from, angle_from}, {radius_to, angle_to})
         when radius_from == radius_to and angle_from == angle_to,
         do: :none

    defp piece_length({radius, angle_from}, {radius_to, angle_to}) when radius == radius_to,
      do: radius * (angle_to - angle_from)

    defp piece_length({radius_from, angle}, {radius_to, angle_to}) when angle == angle_to,
      do: radius_from - radius_to

    defp piece_length({radius_from, angle_from}, {radius_to, angle_to}) do
      slope = (radius_to - radius_from) / (angle_to - angle_from)
      meets_centre = angle_to - radius_to / slope
      spiral_arc_length(slope, angle_from - meets_centre, angle_to - meets_centre)
    end

    # The length of Archimedes' spiral `r = slope * angle` from one angle to another, negative
    # when the second is the larger, as ggplot2's `spiral_arc_length()` writes it.
    defp spiral_arc_length(slope, angle_from, angle_to),
      do: 0.5 * slope * (spiral_term(angle_from) - spiral_term(angle_to))

    defp spiral_term(angle), do: angle * :math.sqrt(1 + angle * angle) + :math.asinh(angle)

    defp boosted(y_position, params) do
      y_position
      |> rescale(params.r_range, 1.0)
      |> :math.pow(@boost)
    end

    # Where a row's positions go in the panel, a row missing either missing both.
    defp place({x_position, y_position}, params)
         when is_position(x_position) and is_position(y_position) do
      angle = angle(x_position, params.theta_range)
      radius = rescale(y_position, params.r_range, @outer_radius)
      {radius * :math.sin(angle) + 0.5, radius * :math.cos(angle) + 0.5}
    end

    defp place({x_position, _y_position}, _params) when not is_position(x_position),
      do: {x_position, x_position}

    defp place({_x_position, y_position}, _params), do: {y_position, y_position}

    # ggplot2's `theta_rescale()`: the position rescaled to a full turn, and R's `%%` taking a
    # full turn to 0.
    defp angle(position, extent) do
      position
      |> rescale(extent, @full_turn)
      |> within_turn()
    end

    defp within_turn(@full_turn), do: 0.0
    defp within_turn(angle) when angle >= 0 and angle < @full_turn, do: angle

    # A position rescaled from its extent to 0 to `span`, as `scales::rescale()` rescales it, an
    # infinite one put at its extent's end first, as `squish_infinite()` puts it. On an extent of
    # equal ends, which R's `zero_range()` calls zero wide, every position is put at the middle,
    # infinite ones too.
    defp rescale(position, {low, low}, span) when is_position(position), do: span / 2
    defp rescale(:neg_infinity, {low, _high} = extent, span), do: rescale(low, extent, span)
    defp rescale(:infinity, {_low, high} = extent, span), do: rescale(high, extent, span)

    defp rescale(position, {low, high}, span) when is_number(position),
      do: (position - low) / (high - low) * span
  end
end
