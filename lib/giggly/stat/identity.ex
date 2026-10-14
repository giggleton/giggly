defmodule Giggly.Stat.Identity do
  @moduledoc false

  # The identity stat, ggplot2's `StatIdentity`: the layer's table as it is, one mark per row. Use
  # it through `Giggly.Stat`.

  @behaviour Giggly.Stat

  @impl Giggly.Stat
  def compute_layer(frame), do: frame
end
