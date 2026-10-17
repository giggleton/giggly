defmodule Giggly.Position.Identity do
  @moduledoc false

  # The identity position, ggplot2's `position_identity()`: every mark where its stat put it. It
  # takes no parameters. Run it through `Giggly.Position`.

  defstruct []

  @type t :: %__MODULE__{}

  defimpl Giggly.Position, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Position

    # The identity reads no aesthetics of its own.
    @impl Giggly.Position
    def default_aesthetics(_position), do: %{}

    @impl Giggly.Position
    def compute_layer(_position, frame), do: frame
  end
end
