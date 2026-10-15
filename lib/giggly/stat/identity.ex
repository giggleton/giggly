defmodule Giggly.Stat.Identity do
  @moduledoc false

  # The identity stat, ggplot2's `StatIdentity`: the layer's table as it is, one mark per row. It
  # takes no parameters. Run it through `Giggly.Stat`.

  defstruct []

  @type t :: %__MODULE__{}

  defimpl Giggly.Stat, for: __MODULE__ do
    use Boundary, classify_to: Giggly.Stat

    @impl Giggly.Stat
    def compute_layer(_stat, frame), do: frame
  end
end
