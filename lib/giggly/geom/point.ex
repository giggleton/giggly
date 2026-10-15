defmodule Giggly.Geom.Point do
  @moduledoc false

  # Points, ggplot2's `geom_point()`: one solid circle per row, at its `x` and `y`. It takes no
  # parameters yet. Draw it through `Giggly.Geom`.
  #
  # Points use `:x`, `:y` and `:group`, and need `:x` and `:y`; an aesthetic joins the accepted list
  # with the scale that maps it, so a mapping never silently does nothing.
  #
  # A row whose `x` or `y` is missing (`nil`, or the float `:nan`) is not drawn, as ggplot2 drops
  # it; ggplot2 also warns, which a pure pipeline cannot. An infinite position is drawn at the
  # panel's edge, where the coordinate system puts it.
  #
  # Every point looks as ggplot2's default point does, until aesthetics such as colour and size can
  # be mapped or set: black, size 1.5 mm with a 0.5 mm border, which grid draws as a circle of
  # radius 1.95 points with a 0.71-point outline, the figures in ggplot2's own SVG test snapshots.

  defstruct []

  @type t :: %__MODULE__{}

  # The aesthetics a layer of points can use, from its own mapping or the plot's.
  @doc false
  @spec accepted_aesthetics() :: [atom()]
  def accepted_aesthetics, do: [:group, :x, :y]

  # The aesthetics a layer of points cannot be drawn without.
  @doc false
  @spec required_aesthetics() :: [atom()]
  def required_aesthetics, do: [:x, :y]

  defimpl Giggly.Geom, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Geom

    alias Giggly.{Coord, DataFrame}
    alias Giggly.Scene.Circles

    # ggplot2's default point: size and border width in millimetres, and its ink.
    @size 1.5
    @stroke 0.5
    @color "#000000"

    # ggplot2's `.pt` (font points per millimetre) and `.stroke` (line-width units, 1/96 inch, per
    # millimetre). ggplot2 sets a point's font size to `size * .pt + stroke * .stroke / 2` and its
    # outline to `stroke * .stroke / 2` line-width units.
    @font_points_per_millimetre 72.27 / 25.4
    @line_width_units_per_millimetre 96 / 25.4
    @points_per_line_width_unit 72 / 96

    # R's graphics engine draws shape 19 as a circle whose radius is 0.375 times the font size.
    @radius_per_font_size 0.375

    @outline @stroke * @line_width_units_per_millimetre / 2
    @radius @radius_per_font_size * (@size * @font_points_per_millimetre + @outline)
    @stroke_width @outline * @points_per_line_width_unit

    @impl Giggly.Geom
    def draw_panel(_geom, frame, coord, panel_params) do
      placed = Coord.transform(coord, frame, panel_params)

      {x_positions, y_positions} =
        [DataFrame.pull(placed, :x), DataFrame.pull(placed, :y)]
        |> Enum.zip()
        |> Enum.filter(fn {x_position, y_position} ->
          is_number(x_position) and is_number(y_position)
        end)
        |> Enum.unzip()

      [
        %Circles{
          x: x_positions,
          y: y_positions,
          radius: @radius,
          stroke_width: @stroke_width,
          color: @color
        }
      ]
    end
  end
end
