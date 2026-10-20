defmodule Giggly.Geom.Shape do
  @moduledoc false

  # A point's shape as R's graphics engine draws it: `GESymbol()` in R's `src/main/engine.c`,
  # which grid's `pointsGrob()` calls for each point, turns each of the 26 shapes into the circles,
  # squares, polygons and line segments a device draws, in the order it draws them. Here each is
  # worked out round the point's place, in points, as offsets `{across, up}`, and says what its
  # outline and its fill are drawn in: `:color`, the point's colour; `:fill`, its fill; or `:none`.
  # A segment is drawn in the point's colour.
  #
  # A shape is worked out from the point's font size in points, ggplot2's `size * .pt + stroke *
  # .stroke / 2`: its circles have a radius of 0.375 of it (R's `RADIUS`), as do its open squares,
  # crosses and the half of its square's side, and a quarter of it (`SMALL`) for the bullet; its
  # plus, its open diamonds and its asterisk's upright segments reach the square root of two times
  # that; its triangles are equilateral, as big in area as the circle (`TRC0`, `TRC1`, `TRC2`), and
  # so are the filled square (`SQRC`) and filled diamond (`DMDC`) of shapes 22 and 23. R works in a
  # device's units, which are points on the devices ggplot2's snapshots draw on, both ways alike.
  #
  # A circle of no radius is not drawn, as `GECircle()` draws none; every other element is drawn at
  # any size, a square or a segment of no length included.

  # The 26 shapes by name, in the order of R's numbers for them, 0 to 25.
  @names [
    :square_open,
    :circle_open,
    :triangle_open,
    :plus,
    :cross,
    :diamond_open,
    :triangle_down_open,
    :square_cross,
    :asterisk,
    :diamond_plus,
    :circle_plus,
    :star,
    :square_plus,
    :circle_cross,
    :square_triangle,
    :square,
    :circle_small,
    :triangle,
    :diamond,
    :circle,
    :bullet,
    :circle_filled,
    :square_filled,
    :diamond_filled,
    :triangle_filled,
    :triangle_down_filled
  ]

  # R's `RADIUS` and `SMALL`: a circle's radius in font sizes, and the bullet's.
  @radius 0.375
  @small_radius 0.25

  # R's `M_SQRT2`, how much further a plus and an open diamond reach than a cross.
  @square_root_of_two 1.41421356237309504880

  # R's `SQRC` and `DMDC`, the filled square's half side and the filled diamond's half diagonal in
  # radii, each as big in area as the circle: sqrt(pi / 4) and sqrt(pi / 4) * sqrt(2).
  @filled_square_half_side 0.88622692545275801364
  @filled_diamond_half_diagonal 1.25331413731550025119

  # R's `TRC0`, `TRC1` and `TRC2`, an equilateral triangle as big in area as the circle: from its
  # middle up to its apex, across to a corner of its base, and down to its base, in radii.
  @triangle_apex 1.55512030155621416073
  @triangle_half_base 1.34677368708859836060
  @triangle_base 0.77756015077810708036

  # What an element's outline and fill are drawn in.
  @open {:color, :none}
  @solid {:none, :color}
  @colored {:color, :color}
  @filled {:color, :fill}

  @typedoc "What an element's outline or fill is drawn in: the point's colour, its fill, or none."
  @type paint :: :color | :fill | :none

  @typedoc "A place round the point, in points across and up from it."
  @type offset :: {float(), float()}

  @typedoc """
  A circle by its radius, a square by half its side, a polygon round its corners, each with what
  its outline and fill are drawn in; or a segment from one place to another, in the point's
  colour.
  """
  @type element ::
          {:circle, float(), {paint(), paint()}}
          | {:square, float(), {paint(), paint()}}
          | {:polygon, [offset()], {paint(), paint()}}
          | {:segment, offset(), offset()}

  # The 26 shapes' names, in the order of R's numbers for them, 0 to 25.
  @doc false
  @spec names() :: [atom()]
  def names, do: @names

  # The elements `shape` is drawn with at a font size of `size` points, in the order R draws them.
  @doc false
  @spec elements(atom(), float()) :: [element()]
  def elements(shape, size) do
    shape
    |> drawn(@radius * size, size)
    |> Enum.reject(fn element -> match?({:circle, radius, _paint} when radius <= 0, element) end)
  end

  # Each shape from `GESymbol()`, given the radius its size makes and the size itself.
  defp drawn(:square_open, radius, _size), do: [{:square, radius, @open}]
  defp drawn(:circle_open, radius, _size), do: [{:circle, radius, @open}]
  defp drawn(:triangle_open, radius, _size), do: [triangle_up(radius, @open)]
  defp drawn(:plus, radius, _size), do: plus(@square_root_of_two * radius)
  defp drawn(:cross, radius, _size), do: cross(radius)
  defp drawn(:diamond_open, radius, _size), do: [diamond(@square_root_of_two * radius, @open)]
  defp drawn(:triangle_down_open, radius, _size), do: [triangle_down(radius, @open)]
  defp drawn(:square_cross, radius, _size), do: [{:square, radius, @open} | cross(radius)]

  defp drawn(:asterisk, radius, _size) do
    reach = @square_root_of_two * radius
    cross(radius) ++ plus(reach)
  end

  defp drawn(:diamond_plus, radius, _size) do
    reach = @square_root_of_two * radius
    [across, up] = plus(reach)
    [across, up, diamond(reach, @open)]
  end

  defp drawn(:circle_plus, radius, _size), do: [{:circle, radius, @open} | plus(radius)]
  defp drawn(:star, radius, _size), do: star(radius)

  defp drawn(:square_plus, radius, _size) do
    [across, up] = plus(radius)
    [across, up, {:square, radius, @open}]
  end

  defp drawn(:circle_cross, radius, _size), do: [{:circle, radius, @open} | cross(radius)]

  defp drawn(:square_triangle, radius, _size) do
    triangle = {:polygon, [{0.0, radius}, {radius, -radius}, {-radius, -radius}], @open}
    [triangle, {:square, radius, @open}]
  end

  defp drawn(:square, radius, _size) do
    corners = [{-radius, -radius}, {radius, -radius}, {radius, radius}, {-radius, radius}]
    [{:polygon, corners, @solid}]
  end

  defp drawn(:circle_small, radius, _size), do: [{:circle, radius, @solid}]
  defp drawn(:triangle, radius, _size), do: [triangle_up(radius, @solid)]
  defp drawn(:diamond, radius, _size), do: [diamond(radius, @solid)]
  defp drawn(:circle, radius, _size), do: [{:circle, radius, @colored}]
  defp drawn(:bullet, _radius, size), do: [{:circle, @small_radius * size, @colored}]
  defp drawn(:circle_filled, radius, _size), do: [{:circle, radius, @filled}]

  defp drawn(:square_filled, radius, _size),
    do: [{:square, @filled_square_half_side * radius, @filled}]

  defp drawn(:diamond_filled, radius, _size) do
    reach = @filled_diamond_half_diagonal * radius
    [{:polygon, [{0.0, -reach}, {reach, 0.0}, {0.0, reach}, {-reach, 0.0}], @filled}]
  end

  defp drawn(:triangle_filled, radius, _size), do: [triangle_up(radius, @filled)]
  defp drawn(:triangle_down_filled, radius, _size), do: [triangle_down(radius, @filled)]

  # A triangle pointing up, its apex first, then the right and left corners of its base.
  defp triangle_up(radius, paint) do
    across = @triangle_half_base * radius
    down = @triangle_base * radius
    {:polygon, [{0.0, @triangle_apex * radius}, {across, -down}, {-across, -down}], paint}
  end

  # A triangle pointing down, its apex first, then the right and left corners of its base.
  defp triangle_down(radius, paint) do
    across = @triangle_half_base * radius
    up = @triangle_base * radius
    {:polygon, [{0.0, -@triangle_apex * radius}, {across, up}, {-across, up}], paint}
  end

  # Two open triangles, one pointing down and one up, their bases moved halfway to the other's
  # apex.
  defp star(radius) do
    apex = @triangle_apex * radius
    across = @triangle_half_base * radius
    base = 0.5 * (@triangle_base * radius + apex)

    [
      {:polygon, [{0.0, -apex}, {across, base}, {-across, base}], @open},
      {:polygon, [{0.0, apex}, {across, -base}, {-across, -base}], @open}
    ]
  end

  # A diamond reaching `reach` each way, from its left corner round by its top.
  defp diamond(reach, paint),
    do: {:polygon, [{-reach, 0.0}, {0.0, reach}, {reach, 0.0}, {0.0, -reach}], paint}

  # A segment across and one up, each reaching `reach` each way.
  defp plus(reach),
    do: [{:segment, {-reach, 0.0}, {reach, 0.0}}, {:segment, {0.0, -reach}, {0.0, reach}}]

  # Two diagonal segments, from the bottom left to the top right and from the top left to the
  # bottom right, each reaching `reach` each way.
  defp cross(reach) do
    [
      {:segment, {-reach, -reach}, {reach, reach}},
      {:segment, {-reach, reach}, {reach, -reach}}
    ]
  end
end
