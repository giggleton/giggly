defmodule Giggly.Position.Identity do
  @moduledoc """
  The identity position, ggplot2's `position_identity()`: every mark where its stat put it. Use it
  through `Giggly.Position`.
  """

  @behaviour Giggly.Position

  @impl Giggly.Position
  def compute_layer(frame), do: frame
end
