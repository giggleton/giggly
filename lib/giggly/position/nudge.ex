defmodule Giggly.Position.Nudge do
  @moduledoc false

  # Nudging, ggplot2's `position_nudge()`: every mark moved a set distance along x, y or both, as
  # `geom_text()` defaults `position = "nudge"` to move labels off the points they name. It takes no
  # parameters yet; ggplot2's `x = NULL` and `y = NULL` are how it nudges, reading the distances
  # from the layer's `nudge_x` and `nudge_y` aesthetics, which it declares, each 0 by default. Run
  # it through `Giggly.Position`.
  #
  # Each of the layer's columns in the x family (`x`, `xmin`, `xmax`) moves by its row's `nudge_x`,
  # and each in the y family by its row's `nudge_y`, in the units of the position: a level's
  # position on a discrete axis, a day on a date axis. Every position comes out a double, as R's
  # do, and a row missing its position stays missing.

  defstruct []

  @type t :: %__MODULE__{}

  defimpl Giggly.Position, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Position

    alias Giggly.{Aesthetics, DataFrame}

    # Each axis's family and the aesthetic holding how far its positions move.
    @nudges [x: :nudge_x, y: :nudge_y]

    # Nudging reads how far to move each row along each axis, 0 unless a layer sets it.
    @impl Giggly.Position
    def default_aesthetics(_position), do: %{nudge_x: 0.0, nudge_y: 0.0}

    @impl Giggly.Position
    def compute_layer(_position, frame) do
      Enum.reduce(@nudges, frame, fn {family, aesthetic}, nudged ->
        nudge_family(nudged, family, DataFrame.pull(nudged, aesthetic))
      end)
    end

    defp nudge_family(frame, family, nudges) do
      frame
      |> DataFrame.names()
      |> Enum.filter(fn name -> Aesthetics.family(name) == family end)
      |> Enum.reduce(frame, fn name, nudged ->
        moved =
          nudged
          |> DataFrame.pull(name)
          |> Enum.zip_with(nudges, &nudge/2)

        DataFrame.put(nudged, name, moved)
      end)
    end

    defp nudge(position, distance) when is_number(position), do: position + distance
    defp nudge(missing, _distance), do: missing
  end
end
