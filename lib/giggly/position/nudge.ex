defmodule Giggly.Position.Nudge do
  @moduledoc false

  # Nudging, ggplot2's `position_nudge()`: every mark moved a set distance along x, y or both, as
  # `geom_text()` defaults `position = "nudge"` to move labels off the points they name. It takes no
  # parameters; ggplot2's `x = NULL` and `y = NULL` are how it nudges, reading the distances from
  # the layer's `nudge_x` and `nudge_y` aesthetics, set or mapped, which it declares, each 0 by
  # default. Run it through `Giggly.Position`.
  #
  # Each of the layer's columns in the x family (`x`, `xmin`, `xmax`) moves by its row's `nudge_x`,
  # and each in the y family by its row's `nudge_y`, in the units of the position: a level's
  # position on a discrete axis, a day on a date axis. The moves are the frame's `+`
  # (`DataFrame.mutate/2`), R's arithmetic, so every position comes out a double, as R's do, an
  # infinite nudge sends its mark to that infinity, and a row missing its position or its nudge is
  # missing that position. **It departs from R where R fails**: R fails on a missing nudge in a
  # layer whose other nudges along that axis are all 0, which this leaves missing as R leaves one
  # beside a nudge that is not.

  defstruct []

  @type t :: %__MODULE__{}

  defimpl Giggly.Position, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Position

    alias Giggly.{Aesthetics, DataFrame}

    # Each axis's family and the aesthetic holding how far its positions move.
    @nudges [x: :nudge_x, y: :nudge_y]

    # Nudging reads how far to move each row along each axis, 0 unless a layer sets or maps it.
    @impl Giggly.Position
    def default_aesthetics(_position), do: %{nudge_x: 0.0, nudge_y: 0.0}

    # Each position moved by its row's nudge, made a double first, so an integer position comes
    # out a double whatever its nudge's column holds.
    @impl Giggly.Position
    def compute_layer(_position, frame, _axis_kinds) do
      moves =
        for name <- DataFrame.names(frame),
            {family, aesthetic} <- @nudges,
            Aesthetics.family(name) == family,
            do: {name, {:+, [{:+, [name, 0.0]}, aesthetic]}}

      DataFrame.mutate(frame, moves)
    end
  end
end
